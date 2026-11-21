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