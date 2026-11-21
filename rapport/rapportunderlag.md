# Underlag till projektrapporten (skriv texten med egna ord)

Det här är **stödpunkter**, inte rapporttext. Varje punkt bygger på dina egna observationer
och bevis. Gör om dem till löpande text (4–6 A4-sidor) och hänvisa till bevisfilerna.
Uppgiften kräver att resonemangen knyts till observationerna – siffrorna nedan är dina.

**Ska stå i rapporten:** länk till Git-repot (https://github.com/DanielHormos/the-wall-inlamning),
Route-adress, namn och projekt.

---

## 1. Containerarkitektur, VM, Gunicorn och ansvarsfördelning

**Container vs virtuell maskin**
- Container = process(er) som delar värdens Linux-kärna, isolerade med namespaces/cgroups. VM = eget OS med egen kärna.
- Egen observation: på Windows krävs en Linux-VM (WSL2) för Docker – `docker version` visade Client `windows/amd64`, Server `linux/amd64`.
- Egen observation: imagen innehåller allt (Python 3.12.15, biblioteken) – fungerade trots trasig lokal Python (`E:\python.exe`).
- Imagen är oföränderlig och identifieras med digest; samma digest syntes vid build, push och som `imageID` i klustret (`sha256:23b4c36d…`).

**Gunicorn-processer**
- `start.sh`: `initialize()` en gång → `exec gunicorn`. Gunicorn blir PID 1 (syns som `[1]` i loggen) och får SIGTERM direkt.
- Varför start.sh: Gunicorn importerar `app:app`, `if __name__ == "__main__"` körs inte → tabellen skapas aldrig.
- Master + 1 sync-worker (standard). En worker = ett anrop i taget → del av flaskhalsen i lasttestet.

**Ansvarsfördelning**
- Webbskikt: tillståndslöst, skalas horisontellt (HPA 2–3), RollingUpdate, ingen lagring.
- Databas: tillståndsfull, 1 replika, Recreate, äger PVC:n.
- Klustret: schemalägger, startar om (liveness), tar ur trafik (readiness), DNS/Services, routern (TLS), SCC (UID), kvoter.

## 2. Säkerhet: UID, Secret, nätverk, TLS, åtkomstmodell, projekträttigheter

**UID / rootless (C3)**
- Båda containrarna kör som `uid=1001090000` – tilldelat av OKD:s SCC (`restricted-v2`), inte imagens 1001.
- `gid=0` = gruppen root, inte användaren root; därför `COPY --chown=1001:0` i Containerfile.
- Manifest: `runAsNonRoot`, `seccompProfile RuntimeDefault`, `allowPrivilegeEscalation: false`, `capabilities drop ALL`.

**Databaskonton och Secrets (C2)**
- Upptäckt: med `POSTGRES_USER` blev appens konto superuser (`\du`). Risk: intrång i webben = full kontroll, även OS-kommandon via `COPY … FROM PROGRAM`.
- Åtgärd: init-skript skapar `walluser` utan extra rättigheter som ägare av `walldb`; admin `postgres` i separat Secret som webben aldrig får.
- Verifierat: `walluser` får skapa tabell men nekas `CREATE DATABASE`.
- Secret är base64-kodad, inte krypterad – den som får läsa Secrets får lösenordet (visades vid lösenordsbytet).

**Nätverk (B3–B5)**
- NetworkPolicy: endast webb-Pods → db TCP 5432. Testklient blockerad (timeout, exit 124), webben tillåten.
- Skillnad timeout (paket släpps) vs `connection refused` vs `server closed the connection` – vilket lager felet sitter i.

**B5 – Samverkan och höga projekträttigheter**
- Lager: NetworkPolicy (vem når porten) → autentisering scram-sha-256 (rätt lösenord) → rättigheter (inte superuser).
- Upptäckt: `pg_hba.conf` har `trust` för 127.0.0.1 – inifrån databas-Poden släpps alla in utan lösenord (fel lösenord godtogs i test).
- Den som har höga projekträttigheter kan: `oc exec` i databas-Poden (superuser utan lösenord), läsa Secrets, ändra/ta bort NetworkPolicy, port-forward förbi policyn, ändra Deployments/ConfigMaps (incidenterna visar hur lätt det går).
- Slutsats: NetworkPolicy skyddar mot andra Pods, inte mot människor med projekträttigheter. Projekträttigheter bör begränsas (RBAC), Secrets kan krypteras/hanteras externt.

**TLS**
- Edge-terminering: HTTPS till routern, okrypterad HTTP inne i klustret till Servicen. `Redirect` för HTTP (302).
- Certifikatet verifierades utan `-k`. Alternativ: `reencrypt` (kryptering hela vägen, kräver certifikat i appen) eller `passthrough`.
- Routern sätter en sticky-session-kaka – webbläsaren hamnar på samma Pod.

**C6 – Webbgränssnittets åtkomstmodell**
- I dag: vem som helst med adressen kan läsa och skriva, anonymt (författarnamnet är fritext). Ingen autentisering, ingen behörighet, inget skydd mot spam/CSRF.
- För att begränsa till inloggade användare behövs t.ex.: inloggning (OIDC mot en identitetsleverantör, t.ex. via oauth2-proxy framför appen eller OpenShift OAuth), sessioner/kakor, koppling av meddelanden till inloggad identitet istället för fritt namn, behörighetskontroll per endpoint, CSRF-skydd, rate limiting.

## 3. Requests/limits, probes, uppstart, skalning och lagring

**Uppstart och probes**
- `initialize()`: 30 försök × (upp till 3 s timeout + 2 s paus) = max 150 s. Observerat: ~60 s när databasen svarar direkt (connection refused / database does not exist).
- Webb: startup `/health` 5 s × 40 = 200 s > 150 s; liveness `/health` (frågar inte db → ingen onödig omstart); readiness `GET /` (bevisar SELECT mot `messages`), timeout 5 s.
- Databas: `pg_isready` för alla tre – kräver inget lösenord, så proberna påverkas inte av lösenordsbytet. Startup 300 s (initdb på tom volym), liveness försiktig (90 s).
- Bevis för valet: incident 1 – readiness misslyckades 66 gånger på 10 min, 0 omstarter, återhämtning direkt efter åtgärd.

**Requests/limits (E3)**
- Kvot: 2 CPU requests / 4 CPU limits / 4Gi / 8Gi; LimitRange default-limit 1 CPU/1Gi → alla containrar måste ha egna värden.
- Vila: webb 1m CPU / 40Mi, db 4m / 19Mi. Under last: webb 270–494m, db upp till 853m, minne oförändrat (≤ 44Mi).
- Minne var aldrig begränsande. Webbens CPU-request 100m är lågt jämfört med faktisk användning (gör att HPA reagerar tidigt men garanterar lite); förslag ~250m.

**Skalning (E4–E6)**
- 2 → 3 inom ~30 s (91 % → 374 % av request), 3 → 2 efter stabiliseringsfönstret 120 s.
- Genomströmning: ~128/133/119 req/s i omgång 1–3 – lastgeneratorn låg på sitt tak 500m (flaskhals 1). Med 1 CPU: ~170 req/s; då webben 494/500m och databasen 853/1000m (flaskhals 2).
- Metodlärdom: verifiera att testverktyget inte begränsar innan slutsatser dras.

**Databasens kapacitet (rapportkrav)**
- Varje anrop öppnar ny anslutning → ny PostgreSQL-process + scram-autentisering. Databasen använde mest CPU av alla.
- Fler webb-Pods = fler samtidiga anslutningar mot en enda databas; `max_connections` 100. Webben skalar, databasen blir taket.
- Förbättringar: anslutningspool i appen eller PgBouncer, fler Gunicorn-workers/threads, läsrepliker/cache.

**Lagring (D5)**
- En instans: PostgreSQL äger sina datafiler; två processer mot samma datakatalog kan förstöra den.
- Recreate: gamla Poden stoppas och släpper disken före ny start. RollingUpdate hade gett `Multi-Attach error` (annan nod) eller två postmaster (samma nod).
- RWO: EBS gp3 är zonbunden och kan bara sitta i en nod; `WaitForFirstConsumer` skapar disken där Poden hamnar.
- Utöver PVC behövs backup: ReclaimPolicy `Delete` → raderad PVC = raderad data. Logisk dump (`pg_dump`) lagrad utanför klustret, schemalagd, med testad återställning (se runbook avsnitt 9).
- Observerat: ny DB-Pod (UID 1072781f → 553641b5) med samma PVC (fa406d16) – data kvar. Återskapande: `Skipping initialization`, `was shut down at …` (ren nedstängning).

## 4. Driftincidenterna och lärarens fel

**Incident 1 – fel Service-selector** (se `drift/incidentlogg.md`)
- Symptom → hypoteser (db kraschad? webb kraschad? NetworkPolicy? Service?) → bevis (endpoints `<none>`, selector ≠ label, loggen mot Service-IP) → åtgärd från Git → verifiering.
- Readiness vs omstart: `READY false`, `RESTARTS 0`.

**Incident 2 – fel DB_NAME**
- ConfigMap-ändring utan effekt tills omstart (C1).
- Felet före webbserverstarten: `start.sh` → `initialize()` → `does not exist` → 60 s → `RuntimeError` → exit 1 → CrashLoopBackOff (RESTARTS 9). Gamla Pods höll tjänsten uppe.
- Skillnaden mot incident 1 (tabellen i incidentloggen).

**Egna oväntade problem (felsökningsmetod, bra för VG)**
- Podman/Docker-krock, `quad.io`-stavfel (`text/html`), CRLF/LF, UTF-16 i ConfigMap och bevisfiler (räddade data genom att ta bort nollbytes), `127.0.0.1 trust` som släppte in fel lösenord, osparad ändring av lastgeneratorns limit som mätningen avslöjade, misslyckad bakgrundsmätning vid lösenordsbytet (ersatt med tidsstämplar).
- Mönster: observation → hypotes → test → verifierat resultat.

**Lärarens fel (incidentpasset med Jonas)** – fyll i efter mötet: ledtrådar, hypoteser, använd hjälp, bevis som avgjorde.

## 5. Metod för införande och förvaltning i flera projekt

Ange för varje del **testat** eller **föreslaget**.

| Område | Testat här | Förslag för flera projekt |
|---|---|---|
| Images | Egen image, versionstaggar, digest, publik registry | Bygg i CI från Git-tagg, signera, skanna sårbarheter, lås basimage med digest, referera digest i manifest |
| Beroendeversioner | `pip freeze` dokumenterat | Låsfil i repo, automatiska uppdateringar (t.ex. Renovate) med test |
| Konfiguration | ConfigMap/Secret, manifest i Git, `oc apply` | Kustomize-overlays eller Helm per projekt/miljö, GitOps (Argo CD) som enda väg in, ingen handpåläggning |
| Verifiering | Testskript och bevisfiler per krav | Automatiserade röktester efter varje utrullning, larm (endpoints saknas, CrashLoopBackOff, ProgressDeadlineExceeded) |
| Rollback | `oc rollout undo`, change-cause, manifest = kluster | Git revert som rollback i GitOps, krav på change-cause |
| Lösenordsbyte | ALTER ROLE + Secret + omstart, ~kort avbrott | Två-kontosstrategi (växla mellan walluser_a/b) för nollavbrott, extern hemlighetshantering (Vault/External Secrets), schemalagd rotation |
| Backup/återställning | Endast dokumenterat | CronJob med `pg_dump` till objektlagring, retention, regelbundna återställningstester, alternativt operator med PITR |
| Ansvar | Ett projekt, en person | Tydlig ägare per projekt, plattformsteam äger kluster/router/lagring, apputvecklare äger image och manifest |

Avvägningar att diskutera: GitOps ger spårbarhet men kräver disciplin; operatorer för PostgreSQL ger HA/backup men mer komplexitet; strikta NetworkPolicys som standard (deny-all) vs enkelhet.

---

## Redovisning av källor och verktyg (krävs i uppgiften)

Förslag på formulering – anpassa så att den stämmer:

> Jag har använt OKD-, Kubernetes- och PostgreSQL-dokumentation, kursens laborationer
> och Claude (Anthropic) som handledare. Claude förklarade begrepp, gav exempel och
> granskade mina filer och kommandon; jag har själv kört alla kommandon, samlat bevisen,
> felsökt och kan förklara varje del av lösningen. Runbook och verifieringsprotokoll
> sammanställdes med AI-stöd utifrån mina egna kommandon och resultat och har granskats av mig.
