# Incidentlogg – The Wall

## Incident 1 – Databasens Service väljer fel Pods

| Fält | Innehåll |
|---|---|
| **Start** | 2026-11-21 21:31 (selector ändrad) |
| **Slut** | 2026-11-21 21:50 (selector återställd, full funktion) |
| **Symptom** | Route gav 503. Webb-Pods `READY false` men `RESTARTS 0`. Databas-Poden `READY true`. |
| **Hypoteser** | 1) Databasen kraschad – avfärdad (Pod ready, 0 omstarter). 2) Webben kraschad – avfärdad (0 omstarter, /health 200). 3) NetworkPolicy blockerar – osannolik, policyn oförändrad och felet var inte timeout. 4) Servicen wall-db når inte databasen – **bekräftad**. |
| **Bevis** | `oc get endpoints wall-db` → `<none>`. Selector `wall-db-FEL` men Podens label `wall-db`. Port-forward direkt till webb-Pod: `/health` 200, `/` 503. Applogg: `connection to server at "172.30.187.1" … server closed the connection unexpectedly` – DNS fungerar (Service-IP), men Servicen saknar mål. Se `tester/bevis/G1-incident1.txt`. |
| **Orsak** | Servicens selector matchade inga Pods → inga endpoints → webben når inte databasen → readiness (`GET /`) 503 → webb-Pods ur trafik → routern saknar backends → 503. |
| **Åtgärd** | `oc apply -f manifests/31-service-db.yaml` – återställde selectorn från den versionshanterade filen. |
| **Verifiering** | Endpoints åter (db 1, webb 2), webb-Pods ready, RESTARTS fortfarande 0, skrivning 302, Messages: 6. |
| **Förebyggande** | 1) Ändra aldrig resurser för hand (`oc set`, `oc edit`) – endast via Git + `oc apply`. 2) Larm på Service utan endpoints. 3) Kontrollera `oc get endpoints` som första steg vid 503. |

**Readiness vs omstart:** Under hela incidenten var webben `READY false` men `RESTARTS 0`. Readiness
tog Poderna ur trafik utan att döda processen; när databasen åter var nåbar släpptes de in direkt.
Liveness mot `/health` (som inte frågar databasen) förhindrade onödiga omstarter. Hade liveness
pekat på `/` skulle webben ha startats om upprepade gånger (CrashLoopBackOff) utan att det hjälpte.



## Incident 2 – Fel databasnamn i webbens konfiguration

| Fält | Innehåll |
|---|---|
| **Start** | 2026-11-21 21:52:36 – ConfigMap `DB_NAME` → `finnsinte` |
| **Slut** | 2026-11-21 22:22:28 |
| **Symptom** | Direkt efter ConfigMap-ändringen: inga. Route 200, körande processer hade fortfarande `DB_NAME=walldb`. Efter `rollout restart`: ny Pod `0/1` → `Error` efter ~62 s → `CrashLoopBackOff`, RESTARTS 1→9. Gamla Pods kvar `1/1`, Route fortsatt 200. Utrullningen fastnade. |
| **Hypoteser** | 1) Servicen/nätverket (som incident 1) – avfärdad: endpoints för wall-db fanns, gamla Pods når databasen. 2) Databasen nere – avfärdad: wall-db ready, gamla Pods fungerar. 3) Felaktig konfiguration i den nya Poden – **bekräftad**. |
| **Bevis** | `oc logs --previous`: `RuntimeError: Database could not be initialized`, `Exit Code: 1`. Events: `Startup probe failed … connect: connection refused` (Gunicorn startade aldrig), `Back-off restarting failed container`. ConfigMap `finnsinte` men gamla processer `walldb`. Se `tester/bevis/G2-incident2.txt`. |
| **Orsak** | Nya Pods fick `DB_NAME=finnsinte`. `start.sh` kör `initialize()` före Gunicorn; PostgreSQL svarar direkt `database "finnsinte" does not exist`, så 30 försök × 2 s ≈ 60 s, sedan `RuntimeError` → `set -e` avbryter → Gunicorn startar aldrig → exit 1 → omstart → CrashLoopBackOff. |
| **Åtgärd** | `oc apply -f manifests/10-configmap-web.yaml` (återställde värde och labels) + `oc rollout restart deployment/wall-web`. |
| **Verifiering** | Två nya Pods ready, RESTARTS 0, `printenv DB_NAME` = `walldb`, skrivning 302, Messages: 7. |
| **Förebyggande** | 1) Konfiguration endast via Git + `oc apply`. 2) Larm på CrashLoopBackOff och utrullningar som fastnar (`ProgressDeadlineExceeded`). 3) Låt `start.sh` avbryta direkt vid `does not exist` (permanent fel) istället för 30 försök – ger snabbare och tydligare fel. |

### Skillnad mot incident 1 (felaktigt Service-urval)

| | Incident 1 | Incident 2 |
|---|---|---|
| Lager | Service (nätverk) | Appkonfiguration |
| Drabbade | Alla körande Pods direkt | Bara nya Pods efter omstart |
| Gunicorn | Körde (`/health` 200) | Startade aldrig (`connection refused`) |
| RESTARTS | 0 | Ökade (1→9) |
| Status | Running 0/1 | Error → CrashLoopBackOff |
| Route | 503 | 200 (gamla Pods kvar) |
| Felmeddelande | `server closed the connection` mot Service-IP – nådde aldrig PostgreSQL | `database "finnsinte" does not exist` – nådde och loggade in i PostgreSQL |
| Första diagnossteg | `oc get endpoints` | `oc logs --previous` |

**Förlopp och uppstart:** Felet syntes före webbserverstarten eftersom `start.sh` kör
`initialize()` innan `exec gunicorn`. Ändringen i ConfigMapen fick ingen effekt förrän
processerna startades om (miljövariabler läses vid containerstart och vid import i `app.py`),
vilket visar varför en omstart krävs vid konfigurationsändring (C1).

## Incidentpass med Jonas – 2026-11-26

| Fält | Innehåll |
|---|---|
| **Start** | ca 15:00 |
| **Slut** | 15:11 (verifierat: 200, alla Pods 1/1, dry-run allt unchanged) |
| **Symptom** | Sidan svarade 200, men en ny webb-Pod stod i `ImagePullBackOff` (0/1) medan två gamla körde. Utrullningen hade fastnat. |
| **Ledtrådar** | `koll`: ny ReplicaSet-kod (79fff57c85) med ImagePullBackOff. Dry-run: **två** objekt `configured` – `deployment.apps/wall-web` och `configmap/wall-web-config`. |
| **Hypoteser** | 1) Felaktig image i webbens Deployment (som F3) – bekräftad. 2) Dry-run visade även ändrad ConfigMap – ett andra, dolt fel som ännu inte påverkade körande Pods. |
| **Bevis** | `oc describe deployment wall-web`: `Image: quay.io/lerniadevopsdanielhormos/the-wallz:2.0.0` (stavfel, "wallz"). `oc describe configmap wall-web-config`: `DB_PORT: 54322` (ska vara 5432). Se `tester/bevis/incidentpass-jonas.txt`. |
| **Orsak** | Två manuella ändringar: (1) ogiltig image → ny Pod kunde inte hämta imagen; RollingUpdate med maxUnavailable 0 behöll de gamla Poderna, så tjänsten var uppe. (2) fel DB_PORT i ConfigMap → påverkade inte körande processer (miljövariabler läses vid start), men hade gett `connection refused` och CrashLoopBackOff vid nästa omstart. |
| **Åtgärd** | `oc apply -f manifests/40-deployment-web.yaml` och `oc apply -f manifests/10-configmap-web.yaml` – återställde båda från Git. |
| **Verifiering** | `koll`: sidan 200, två webb-Pods 1/1, endpoints korrekta, dry-run allt `unchanged`. |
| **Lärdom/förebyggande** | Läs **hela** dry-run-utskriften – fel nr 2 syntes inte för användaren och hade slagit till först vid nästa omstart. Förebyggande: GitOps (automatisk synk från Git) eller regelbunden dry-run/drift-kontroll som larmar vid avvikelse. |