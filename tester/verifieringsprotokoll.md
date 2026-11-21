# Verifieringsprotokoll – The Wall

Alla tester utförda av Daniel Hormos i projektet `student-daniel-hormos-lerniastudent-se`,
OKD 4.22 (`api.okd.cloud2.se`). Tider i svensk tid (CET) om inget annat anges; klustrets
loggar och SQL-tider är i UTC (= svensk tid − 1 h). Bevisfiler i `tester/bevis/`.
Lösenord och tokens förekommer inte i bevisen (lösenord skickades via stdin eller Secret).

**Åtkomstvägar:**
**Route** = extern HTTPS via routern ·
**Svc** = Service-DNS från en Pod i klustret ·
**Exec** = `oc exec` i en Pod ·
**PF** = `oc port-forward` direkt till en Pod ·
**API** = `oc get/describe` mot klustrets API ·
**Lokalt** = Docker på egen dator

---

## V1 – Bygge och start

| Krav | Tid | Åtkomst | Kommando / metod | Förväntat | Faktiskt | Bevis |
|---|---|---|---|---|---|---|
| A2 | 2026-11-18 | Lokalt | `git log` – upstream `caa199b`, egna ändringar i separata commits | Spårbar källkod | Commit `caa199b…` importerad oförändrad, egna filer därefter | Git-historik, README |
| A1, A2 | 2026-11-18 ~21:40 | Lokalt | `docker build -t …:1.0.0 -f app/Containerfile app` | Image byggs | Byggd, basimage `ubi9/python-312@sha256:5b184c2a…` | README |
| A2 | 2026-11-18 | Lokalt | `docker run --rm the-wall:dev pip freeze` / `python --version` | Exakta versioner | Flask 3.1.3, gunicorn 23.0.0, psycopg 3.3.9, Python 3.12.15 | `lokal-pip-freeze.txt`, `lokal-python-version.txt` |
| A2 | 2026-11-18 ~22:10 | Lokalt | `docker push` + Quay-API | Publik image | `1.0.0` digest `sha256:7e25a53a…`, `is_public: true` | `V1-image-v1-digest.txt`, `V1-quay-publik.txt` |
| A1 | 2026-11-18 ~21:42 | Lokalt | `docker run` webb + db; `curl /health`, `POST /post`, `GET /` | 200, 302, 400, meddelande syns | 200, 302, 400 (tomt namn), `Messages: 1` | (terminalutskrift) |
| A5 | 2026-11-21 15:04 | API | `oc apply` DB på tom PVC; `oc logs deployment/wall-db` | initdb + init-skript körs | initdb, `CREATE ROLE`, `init: applikationskontot walluser skapat` | `V1-db-init-tom-volym.txt` |
| A1 | 2026-11-21 16:18 | API | `oc logs deployment/wall-web` | Initiering före Gunicorn | `Database initialized` → `Listening at 0.0.0.0:8080`, Gunicorn PID 1 | `V1-web-start-kluster.txt` |
| A2 | 2026-11-21 ~19:33 | API | `oc get pods -o custom-columns=…imageID` | imageID = pushad digest | `…the-wall@sha256:23b4c36d…` (v2) i båda Pods | `A2-imageid-v2.txt`, `F2-image-v2-digest.txt` |
| E3 | 2026-11-21 18:32 | API | `oc adm top pods`, `oc get deployment -o jsonpath=…resources` | Resurser satta | webb 100m/128Mi – 500m/256Mi, db 100m/256Mi – 1/512Mi; vila 1m/40Mi resp. 4m/19Mi | `E3-top-vila.txt` |
| A3 | 2026-11-21 16:04, 16:43 | API | `oc describe service wall-db / wall-web` | ClusterIP, rätt portar, endpoints | db 5432→5432, webb 80→8080, båda med endpoints | `A3-service-db.txt`, `A3-service-web.txt` |

## V2 – Trafikkedja

| Krav | Tid | Åtkomst | Kommando / metod | Förväntat | Faktiskt | Bevis |
|---|---|---|---|---|---|---|
| B1 | 2026-11-21 17:19 | Route | `curl -I http://<route>` | Omdirigering till HTTPS | `302 Found`, `location: https://…` | `B1-http-redirect.txt` |
| B1 | 2026-11-21 17:19 | Route | `curl -I https://<route>` (utan `-k`) | 200 med certifikatverifiering | `200 OK`, `server: gunicorn`, certifikatet godtogs | `B1-https-200.txt`, `B1-route.txt` |
| B2 | 2026-11-21 | Route | Formulär i webbläsaren + `GET /` | Unikt meddelande sparas och visas | Meddelanden skrivna och synliga | `B2-webb-forsta-meddelande.png`, `D2-webb-tre-meddelanden.png` |
| B2 | 2026-11-21 18:37 | Exec | `psql … SELECT … FROM messages` | Samma rader i tabellen | 4 rader inkl. formulärmeddelandena | `D2-sql-messages.txt` |

## V3 – Nätverk

| Krav | Tid | Åtkomst | Kommando / metod | Förväntat | Faktiskt | Bevis |
|---|---|---|---|---|---|---|
| B4 | 2026-11-21 18:24 | Svc | Testklient (andra labels): `curl -m 5 http://wall-web/health`, `timeout 5 bash -c "</dev/tcp/wall-db/5432"` – **före** policy | Båda når fram | webb 200, db `ANSLUTEN` | `B4-fore-policy.txt` |
| B3 | 2026-11-21 18:25 | API | `oc apply` + `oc describe networkpolicy` | Ingress till db endast från webb, TCP 5432 | `wall-db-allow-from-web` | `B3-networkpolicy.txt` |
| B4 | 2026-11-21 18:25 | Svc | Samma tester **efter** policy | Klient→webb ok, klient→db blockerad | webb 200; db **exit 124** (timeout 5 s, paket släpps) | `B4-efter-policy.txt` |
| B2, B3 | 2026-11-21 18:25 | Svc | Från webb-Pod: Python `socket.create_connection(('wall-db',5432),5)` | Tillåten | `ANSLUTEN` | `B4-efter-policy.txt` |

## V4 – Säkerhet

| Krav | Tid | Åtkomst | Kommando / metod | Förväntat | Faktiskt | Bevis |
|---|---|---|---|---|---|---|
| C3 | 2026-11-21 15:06 | Exec | `oc exec deployment/wall-db -- id` | Icke-root | `uid=1001090000` (tilldelat av SCC) | `C3-db-uid.txt` |
| C3 | 2026-11-21 18:22 | Exec | `oc exec deployment/wall-web -- id` | Icke-root | `uid=1001090000 gid=0(root)` (grupp 0, inte användare root) | `C3-web-uid.txt` |
| C3 | 2026-11-21 18:22 | API | `oc get deployment -o jsonpath=…securityContext` | runAsNonRoot, ingen eskalering | `runAsNonRoot: true`, `seccomp RuntimeDefault`, `allowPrivilegeEscalation: false`, `drop: ALL` (båda) | manifest 30/40 |
| C2 | 2026-11-19 17:07 | API | `oc describe secret` | Två Secrets, inga värden synliga | `wall-db-admin` (password 31 B), `wall-db-credentials` (username 8 B, password 32 B) | `C2-secrets-describe.txt` |
| C2 | 2026-11-18 | Lokalt | `psql -c "\du"` före/efter init-skript | Appkonto utan superuser | Före: `Superuser…`; efter: `walluser` utan attribut | `C2-du-fore-superuser.txt`, `C2-du-efter-appkonto.txt` |
| C2 | 2026-11-18 | Lokalt | `pg_hba.conf` | Lösenord krävs över nätverket | `127.0.0.1 trust`, övriga `scram-sha-256` | `lokal-pg-hba.txt` |
| C1 | 2026-11-21 21:53 | Exec/API | ConfigMap ändrad → `printenv DB_NAME` i körande Pods | Körande processer oförändrade | ConfigMap `finnsinte`, processer `walldb`, Route 200 | `G2-incident2.txt` |

## V5 – Lösenordsbyte

| Krav | Tid | Åtkomst | Kommando / metod | Förväntat | Faktiskt | Bevis |
|---|---|---|---|---|---|---|
| C5 | 2026-11-21 ~22:26 | Svc (från webb-Pod) | Ny anslutning, gamla lösenordet, före byte | Accepteras | `ACCEPTERAT` | `C4-losenordsbyte.txt` |
| C4 | 2026-11-21 ~22:27 | Exec | `ALTER ROLE walluser WITH PASSWORD …` (via stdin), `oc set data secret/…`, `oc rollout restart` | Samordnat byte | `ALTER ROLE`, Secret uppdaterad, utrullning klar | `C4-losenordsbyte.txt` |
| C5 | 2026-11-21 ~22:29 | Svc (från webb-Pod) | Ny anslutning, gamla lösenordet, efter byte | Nekas | `NEKAT: … password authentication failed for user "walluser"` | `C4-losenordsbyte.txt` |
| C5 | 2026-11-21 ~22:29 | Svc (från webb-Pod) | Ny anslutning, nya lösenordet | Accepteras | `ACCEPTERAT` | `C4-losenordsbyte.txt` |
| C5 | 2026-11-21 ~22:29 | Route | Skrivning + läsning | 302, tidigare data kvar | 302, `Messages: 8` inkl. äldre meddelanden | `C4-losenordsbyte.txt` |

Avbrottstid: bakgrundsmätningen avbröts; avbrottet beräknades från tidsstämplar (se notering i bevisfilen).

## V6 – Persistens

| Krav | Tid | Åtkomst | Kommando / metod | Förväntat | Faktiskt | Bevis |
|---|---|---|---|---|---|---|
| D1 | 2026-11-19 / 2026-11-21 | API | `oc get pvc`, `oc describe pvc` | 1Gi RWO, Bound efter DB-start | Pending (WaitForFirstConsumer) → Bound, `gp3-csi` | `D1-pvc-pending.txt`, `D1-storageclass.txt` |
| D2 | 2026-11-21 18:37 | Route + Exec | 3 meddelanden via formulär; `SELECT … FROM messages` | Synliga i webb och SQL | 4 rader (id 1–4) | `D2-webb-tre-meddelanden.png`, `D2-sql-messages.txt` |
| D3 | 2026-11-21 18:38 | API + Exec | Pod- och PVC-UID → `oc delete pod` → nya UID + `count(*)` | Nytt Pod-UID, samma PVC-UID, data kvar | Pod `1072781f…` → `553641b5…`; PVC `fa406d16…` oförändrad; 4 rader | `D3-radera-db-pod.txt` |
| D4 | 2026-11-21 18:54 | Exec | `curl localhost:8080/` i varje webb-Pod, före och efter att en Pod ersatts | Alla visar samma data | `jpr4v`, `s9gp4`, nya `7m9hz`: alla `Messages: 4` | `D4-webb-pods.txt` |

## V7 – Skalning

| Krav | Tid | Åtkomst | Kommando / metod | Förväntat | Faktiskt | Bevis |
|---|---|---|---|---|---|---|
| E4 | 2026-11-21 18:32 | API | `oc describe hpa` i vila | min 2, max 3, mål 50 % | 1 %/50 %, 2 repliker, `ValidMetricFound` | `E4-hpa-vila.txt` |
| E5 | 2026-11-21 22:46 | Svc | Job `wall-loadgen`: 2 klienter, 60 s, `curl -m 5`, limit 500m | Inga fel | 7 658 ok, 0 fel (~128 req/s) | `E5-omgang1-2klienter.txt` |
| E6 | 2026-11-21 22:46–22:49 | API | Logg var 15:e s: HPA, Deployment, `oc adm top pods` | 2 → 3 → 2 | 22:46:41 91 % → 22:46:58 **3/3** (374 %) → last slut 22:48 → 22:49:39 **2/2** | `E6-forlopp.txt` |
| E5 | 2026-11-21 22:52 | Svc | 4 klienter, 90 s | – | 11 976 ok, 0 fel (~133 req/s); loadgen 500m = sitt tak | `E5-omgang2-4klienter.txt`, `E6-forlopp.txt` |
| E5 | 2026-11-21 22:59 | Svc | 8 klienter, 120 s (limit oavsiktligt kvar på 500m) | – | 14 252 ok, 0 fel (~119 req/s); loadgen 500m | `E5-omgang3-8klienter.txt`, `E6-forlopp-omgang3.txt` |
| E5, E6 | 2026-11-21 23:05 | Svc | 8 klienter, 90 s, loadgen-limit 1 CPU | Högre genomströmning om loadgen var flaskhals | 15 264 ok, 0 fel (**~170 req/s**); loadgen 672m, db 853m/1000m, webb 494m/500m | `E5-omgang4-8klienter-1cpu.txt`, `E6-forlopp-omgang3.txt` |
| E4 | 2026-11-21 23:06 | API | `oc describe hpa` (conditions) direkt efter omgång 4 | Stabiliseringsfönster vid nedskalning | `AbleToScale True ScaleDownStabilized`, `ScalingActive True ValidMetricFound` | `E4-hpa-under-last.txt` |
| E4 | 2026-11-21 22:59 | API | `oc describe hpa` (events) | Skalningshändelser | `SuccessfulRescale New size: 3 … above target` och `New size: 2 … All metrics below target` (×2 vardera) | terminalutskrift omgång 3 (första versionen av `E4-hpa-under-last.txt`, ersatt) |

## V8 – Release

| Krav | Tid | Åtkomst | Kommando / metod | Förväntat | Faktiskt | Bevis |
|---|---|---|---|---|---|---|
| F1 | 2026-11-21 18:58 | Lokalt | `git tag v1.0.0` | v1 från dokumenterad källkod | Tagg på commit med oförändrad `app.py` | Git-taggar |
| F2 | 2026-11-21 18:58 | Lokalt | `git diff v1.0.0 -- app/app.py` | En synlig ändring | `<h1>THE WALL_</h1>` → `<h1>THE WALL_ <small>v2</small></h1>` | `F2-diff-v1-v2.txt` |
| F2 | 2026-11-21 19:25 | Lokalt | `docker push …:2.0.0` | Egen v2-image | digest `sha256:23b4c36d…` | `F2-image-v2-digest.txt` |
| F2 | 2026-11-21 19:30 | Route | `oc apply` + `GET /` | v2 synlig, data kvar | `THE WALL_ v2`, `Messages: 4` | `F2-v2-live.txt`, `F2-webb-v2.png`, `F3-historik-v2.txt` |
| F3 | 2026-11-21 19:31 | API | `oc set image …:9.9.9-finns-inte` | Utrullningen stannar | Ny Pod `ImagePullBackOff`, `rollout status` timeout; v2-Pods kvar | `F3-pods-trasig.txt`, `F3-conditions.txt`, `F3-describe-trasig-pod.txt` |
| F3 | 2026-11-21 19:33 | Route | `GET /` under felet | – | **200** (maxUnavailable=0 behöll v2) | `F3-sidan-svarar-under-fel.txt` |
| F4 | 2026-11-21 19:39 | API | `oc rollout undo --to-revision=4` | Fungerande revision åter | Rev 4 → rev 6, `oc apply` av manifest: `unchanged` | `F4-historik-*.txt`, `F4-manifest-matchar-klustret.txt` |
| F4 | 2026-11-21 19:41 | Route | Skrivning + läsning | 302, v2, tidigare data | 302, `v2`, `Messages: 5` | `F4-efter-rollback.txt`, `F4-pods-efter-rollback.txt` |

## V9 – Incidenter

| Krav | Tid | Åtkomst | Kommando / metod | Förväntat | Faktiskt | Bevis |
|---|---|---|---|---|---|---|
| G1 | 21:28:58 | API | `oc set selector service/wall-db …=wall-db-FEL` | – | Selector ändrad | `G1-incident1.txt` |
| G1 | ~21:29 | Route/API | Route, Pods, endpoints | 503, readiness påverkas | Route 503, webb `READY false`, `RESTARTS 0`, `wall-db` endpoints `<none>` | `G1-incident1.txt` |
| G1 | ~21:43 | PF | Direkt till webb-Pod: `/health`, `/` | 200 resp. 503 | `/health` 200, `/` 503; readiness failed ×66 på 10 min, 0 omstarter | `G1-incident1.txt` |
| G1 | 21:43:54–21:45:07 | API/Route | `oc apply -f manifests/31-service-db.yaml` + verifiering | Full funktion | Endpoints åter, ready, RESTARTS 0, skrivning 302, `Messages: 6` | `G1-incident1.txt`, `drift/incidentlogg.md` |
| G2 | ~21:53 | API/Exec | ConfigMap `DB_NAME=finnsinte` | Ingen effekt utan omstart | Processer kvar på `walldb`, Route 200 | `G2-incident2.txt` |
| G2 | ~21:54–22:20 | API | `oc rollout restart` + `oc get pods -w`, `logs --previous`, `describe` | Felet syns före webbserverstart | Ny Pod `Error` efter ~62 s → `CrashLoopBackOff`, RESTARTS 9, `Exit Code 1`, `RuntimeError`, startup probe `connection refused`; Route 200 via gamla Pods | `G2-incident2.txt` |
| G2 | ~22:22 | API/Route | ConfigMap från Git + `rollout restart` + verifiering | Full funktion | Nya Pods ready, RESTARTS 0, `DB_NAME=walldb`, skrivning 302, `Messages: 7` | `G2-incident2.txt`, `drift/incidentlogg.md` |

## V10 – Återskapande

| Krav | Tid | Åtkomst | Kommando / metod | Förväntat | Faktiskt | Bevis |
|---|---|---|---|---|---|---|
| H2 | 2026-11-21 ~23:13 | API/Exec | Före: `count(*)`, PVC-UID, objektlista | – | 8 meddelanden, PVC `fa406d16…` | `H2-aterskapa.txt` |
| H2 | ~23:14–23:52 | API | Borttaget: HPA, Deployment + Service `wall-web`; `scale wall-db 0`; Deployment + Service `wall-db`. Kvar: PVC, Secrets | Endast PVC och Secrets kvar | Bekräftat i mellanläge | `H2-aterskapa.txt` |
| H2 | ~23:53 | API | `oc apply -f manifests/` | Återskapat | 5 objekt `created`, övriga `unchanged` | `H2-aterskapa.txt` |
| H2 | ~23:55 | API | `oc logs deployment/wall-db` | Ingen ny initiering, ren nedstängning | `Skipping initialization`, `database system was shut down at 22:14:01 UTC` | `H2-aterskapa.txt` |
| H3 | ~23:56 | Exec/Route | `count(*)`, PVC-UID, skrivning | Samma data, samma PVC, ny skrivning | 8 → 9 meddelanden, PVC `fa406d16…`, 302, v2 | `H2-aterskapa.txt` |
| H4 | 2026-11-22 | API | `oc get all,job -l app.kubernetes.io/part-of=the-wall` | Inga testlaster | Endast wall-db, wall-web, Services, HPA, Route | `H4-slutlage.txt` |

Test med ny tom PVC: dokumenterat i `drift/runbook.md` avsnitt 8 (ej genomfört, för att inte riskera produktionsdatan).
