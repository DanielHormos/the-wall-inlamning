# Runbook – The Wall i OKD

Driftinstruktioner för The Wall (Flask/Gunicorn + PostgreSQL) i OKD 4.22.
Alla kommandon är testade i projektet `student-daniel-hormos-lerniastudent-se`
(Windows, PowerShell 7). Motsvarande bash-varianter anges där de skiljer sig.

| | |
|---|---|
| Route | https://wall-web-student-daniel-hormos-lerniastudent-se.apps.okd.cloud2.se |
| Webb-image (v2, i drift) | `quay.io/lerniadevopsdanielhormos/the-wall:2.0.0` |
| Webb-image (v1) | `quay.io/lerniadevopsdanielhormos/the-wall:1.0.0` |
| Databas-image | `quay.io/kurs/postgresql:2026-10-29` (PostgreSQL 16.15) |
| Manifest | `manifests/` (installeras med `oc apply -f manifests/`) |

---

## 0. Förutsättningar och start av arbetspass

Verktyg: `oc` (4.22), Docker eller Podman, Git. PowerShell 7 rekommenderas på Windows
(Windows PowerShell 5.1 skriver UTF-16 och förstör å/ä/ö i filer och utskrifter).

```powershell
cd <repo>/inlamning
$env:LAB_PROJECT = "student-daniel-hormos-lerniastudent-se"   # bash: export LAB_PROJECT=...
oc whoami                       # "Unauthorized" -> ny token: konsolen, ? -> Copy login command
oc project $env:LAB_PROJECT
git status
```

Om utskrifter från `oc` visar konstiga tecken (`├Â`) i PowerShell:

```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
```

---

## 1. Bygga och publicera image

```sh
git checkout v2.0.0                       # eller v1.0.0
docker login quay.io
docker build -t quay.io/lerniadevopsdanielhormos/the-wall:2.0.0 -f app/Containerfile app
docker push  quay.io/lerniadevopsdanielhormos/the-wall:2.0.0
```

- Notera digesten från `docker push` (`2.0.0: digest: sha256:...`) och för in den i README.
- Repositoryt på Quay ska vara **publikt** (Settings → Repository Visibility).
  Kontroll utan inloggning:
  `curl -s https://quay.io/api/v1/repository/lerniadevopsdanielhormos/the-wall` → `"is_public": true`.
- Beroendeversioner i imagen: `docker run --rm <image> pip freeze`.

---

## 2. Installation i ett tomt projekt (ny tom datavolym)

### 2.1 Secrets (finns inte i Git)

Webben får bara `wall-db-credentials`, aldrig adminlösenordet.

**PowerShell 7:**
```powershell
$admin = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(24)) -replace '[+/=]',''
$app   = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(24)) -replace '[+/=]',''
oc create secret generic wall-db-admin --from-literal=password=$admin
oc create secret generic wall-db-credentials --from-literal=username=walluser --from-literal=password=$app
oc label secret wall-db-admin wall-db-credentials app.kubernetes.io/part-of=the-wall
Remove-Variable admin, app
```

**bash:**
```sh
oc create secret generic wall-db-admin --from-literal=password="$(openssl rand -base64 24 | tr -d '/+=')"
oc create secret generic wall-db-credentials --from-literal=username=walluser \
  --from-literal=password="$(openssl rand -base64 24 | tr -d '/+=')"
oc label secret wall-db-admin wall-db-credentials app.kubernetes.io/part-of=the-wall
```

Kontroll (visar bara längder): `oc describe secret wall-db-admin wall-db-credentials`

### 2.2 Applicera manifesten

```sh
oc apply -f manifests/
oc rollout status deployment/wall-db
oc rollout status deployment/wall-web
```

Ordningen spelar ingen roll: webben väntar själv på databasen (`initialize()` försöker i upp
till 150 s, startup-proben tillåter 200 s).

PVC:n står som `Pending` tills databas-Poden startar (StorageClass `gp3-csi`,
`WaitForFirstConsumer`). Det är normalt.

### 2.3 Förväntat vid första start

`oc logs deployment/wall-db` ska innehålla:
- `running`/`sourcing /docker-entrypoint-initdb.d/01-create-app-user.sh`
- `init: applikationskontot walluser skapat som ägare av walldb`
- `database system is ready to accept connections`

`oc logs deployment/wall-web` ska innehålla `Database initialized` och `Listening at: http://0.0.0.0:8080`.

### 2.4 Ändra init-skriptet

`db/init/01-create-app-user.sh` läggs in som ConfigMap `wall-db-init`. Efter ändring, generera om:

```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$yaml = (oc create configmap wall-db-init --from-file=db\init\01-create-app-user.sh --dry-run=client -o yaml) -join "`n"
[IO.File]::WriteAllText("$PWD\manifests\12-configmap-db-init.yaml", $yaml + "`n")
# lägg tillbaka labels under metadata, kontrollera UTF-8/LF, applicera
```

Skriptet körs **bara** vid initiering av en tom datavolym.

---

## 3. Verifiering (snabbkontroll efter installation eller ändring)

```sh
oc get pods -l app.kubernetes.io/part-of=the-wall         # alla READY, RESTARTS 0
oc get endpoints wall-db wall-web                          # båda ska ha adresser
oc get hpa wall-web                                        # REPLICAS 2, TARGETS cpu: x%/50%
curl -sI http://<route>                                    # 302 -> https
curl -sI https://<route>                                   # 200, server: gunicorn
curl -s -d "author=Kontroll&message=Runbook-test" https://<route>/post -o /dev/null -w "%{http_code}\n"   # 302
oc exec deployment/wall-db -- psql -U postgres -d walldb -c "SELECT count(*) FROM messages;"
```

Startsidan visar högst 100 meddelanden – använd SQL för totalt antal.

---

## 4. Lösenordsbyte för applikationskontot

**Viktigt:** Secret och imagens variabler används bara vid första initiering. Att ändra
Secreten byter **inte** lösenordet i databasen. Bytet görs med `ALTER ROLE`.

**Planerat avbrott:** från `ALTER ROLE` tills första nya webb-Pod är ready (uppskattat 15–30 s).
Under den tiden ger befintliga webbprocesser `password authentication failed` → 503.

**Lösenordstest måste göras utifrån databas-Poden.** Inne i databas-Poden gäller
`trust` för `127.0.0.1` (pg_hba.conf) och då accepteras vilket lösenord som helst.

```powershell
# 1. Förbered (lösenorden visas aldrig)
$oldPw = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((oc get secret wall-db-credentials -o jsonpath="{.data.password}")))
$newPw = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(24)) -replace '[+/=]',''

function Test-DbPw($pw, $etikett) { $r = $pw | oc exec -i deployment/wall-web -- python -c "import sys,psycopg`ntry:`n  psycopg.connect(host='wall-db',dbname='walldb',user='walluser',password=sys.stdin.read().strip(),connect_timeout=5).close(); print('ACCEPTERAT')`nexcept Exception as e: print('NEKAT:', str(e).splitlines()[0])"; "$etikett -> $r" }
Test-DbPw $oldPw "gamla (före)"        # ACCEPTERAT

# 2-4. Kör direkt efter varandra
"ALTER ROLE walluser WITH PASSWORD '$newPw';" | oc exec -i deployment/wall-db -- psql -U postgres -d walldb -v ON_ERROR_STOP=1
oc set data secret/wall-db-credentials --from-literal=password=$newPw
oc rollout restart deployment/wall-web; oc rollout status deployment/wall-web

# 5. Verifiera med nya anslutningar
Test-DbPw $oldPw "gamla (efter)"       # NEKAT: password authentication failed
Test-DbPw $newPw "nya (efter)"         # ACCEPTERAT
# + läsning, skrivning och SQL-räkning enligt avsnitt 3

Remove-Variable oldPw, newPw
```

Lösenordet skickas via stdin, aldrig som kommandoradsargument.
Databas-Poden behöver inte startas om (dess `APP_DB_PASSWORD` används bara vid initiering).

### Återgång vid problem

```powershell
"ALTER ROLE walluser WITH PASSWORD '$oldPw';" | oc exec -i deployment/wall-db -- psql -U postgres -d walldb -v ON_ERROR_STOP=1
oc set data secret/wall-db-credentials --from-literal=password=$oldPw
oc rollout restart deployment/wall-web
```

Stäng inte terminalen förrän bytet är verifierat – annars försvinner `$oldPw`.
(Har den försvunnit: sätt ett nytt lösenord med ALTER ROLE + Secret enligt ovan.)

---

## 5. Felsökning

### Första kommandon

```sh
oc get pods -o wide                           # status, READY, RESTARTS
oc get endpoints wall-db wall-web             # hittar Services sina Pods?
oc describe pod <pod>                         # Events: probes, ImagePull, BackOff
oc logs <pod>                                 # appens logg
oc logs <pod> --previous                      # logg från föregående (kraschad) körning
oc get events --sort-by=.lastTimestamp | tail -20
```

### Symptom → trolig orsak

| Symptom | Trolig orsak | Kontroll | Åtgärd |
|---|---|---|---|
| Route 503, webb `READY 0/1`, `RESTARTS 0`, applogg `server closed the connection` mot Service-IP | Databasens Service saknar endpoints (fel selector) | `oc get endpoints wall-db` → `<none>`; jämför selector med Pod-labels | `oc apply -f manifests/31-service-db.yaml` |
| Ny webb-Pod `Error` → `CrashLoopBackOff` efter ~60 s, gamla Pods OK | Fel konfiguration som bara nya processer ser (t.ex. `DB_NAME`) | `oc logs <pod> --previous` (start.sh skriver ut DB_HOST/DB_NAME) | Rätta ConfigMap via Git, `oc rollout restart deployment/wall-web` |
| Applogg `database "X" does not exist` | Fel `DB_NAME` | `oc get configmap wall-web-config -o yaml` | Som ovan |
| Applogg `password authentication failed` | Secret och databasens lösenord ur takt | Test-DbPw (avsnitt 4) | Samordna enligt avsnitt 4 |
| Anslutning tar 3–5 s och går ut (timeout) | NetworkPolicy släpper paketen | `oc get networkpolicy`, labels på klienten | Rätta policy/labels |
| Pod `ImagePullBackOff` | Image/tagg finns inte eller är privat | `oc describe pod` → Events | Rätta image eller rollback (avsnitt 6) |
| PVC `Pending` | Normalt innan databas-Poden finns (WaitForFirstConsumer) | `oc describe pvc wall-db-data` | Starta databasen |
| Utrullning fastnar, sidan fungerar | Ny Pod blir aldrig ready; `maxUnavailable=0` håller gamla kvar | `oc rollout status`, `oc get pods` | Rätta orsaken eller rollback |
| Nya Pods vägras med `exceeded quota` | Projektkvoten (2 CPU requests / 4 CPU limits) | `oc describe quota` | Sänk resurser, ta bort testlaster |

**Princip:** ändra aldrig resurser för hand i klustret (`oc set`, `oc edit`). Rätta i Git och
`oc apply`. Felmeddelandet avgör vilket lager felet sitter i (nätverk, Service, autentisering, konfiguration).

---

## 6. Release och rollback

### Ny version

1. Ändra kod, committa, tagga (`git tag -a vX.Y.Z`), bygg och pusha imagen (avsnitt 1).
2. Ändra `image:` och `kubernetes.io/change-cause` i `manifests/40-deployment-web.yaml`.
3. `oc apply -f manifests/40-deployment-web.yaml` och `oc rollout status deployment/wall-web`.
4. Verifiera (avsnitt 3), committa manifestet.

RollingUpdate (maxSurge 1, maxUnavailable 0) byter en Pod i taget utan avbrott.
En trasig image stoppar utrullningen men tar inte ned tjänsten.

### Rollback

```sh
oc rollout history deployment/wall-web
oc rollout undo deployment/wall-web --to-revision=<N>
oc rollout status deployment/wall-web
oc apply -f manifests/40-deployment-web.yaml     # ska ge "unchanged" om manifestet = fungerande version
```

Om manifestet pekar på den trasiga versionen: rätta `image:` i filen och committa, annars
skriver nästa `oc apply` över rollbacken.

---

## 7. Återstart med bevarad databasvolym

Tar bort och återskapar Deployments, Services och HPA. **PVC och Secrets behålls.**
Ta aldrig bort PVC:n – StorageClass har `ReclaimPolicy: Delete`, data raderas permanent.

```sh
# Före
oc exec deployment/wall-db -- psql -U postgres -d walldb -c "SELECT count(*), max(id) FROM messages;"
oc get pvc wall-db-data -o custom-columns=PVC:.metadata.name,UID:.metadata.uid

# 1. Avsluta skrivningar (HPA först, annars återskapar den webben)
oc delete hpa wall-web
oc delete deployment wall-web
oc delete service wall-web

# 2. Ta ned databasen kontrollerat (PostgreSQL får 60 s att stänga rent)
oc scale deployment wall-db --replicas=0
oc delete deployment wall-db
oc delete service wall-db

# 3. Återskapa
oc apply -f manifests/
oc rollout status deployment/wall-db
oc rollout status deployment/wall-web

# 4. Verifiera
oc logs deployment/wall-db | grep -E "Skipping initialization|was shut down"
#   "Skipping initialization"            = befintlig data hittades
#   "database system was shut down at"   = förra nedstängningen var ren
#   ("interrupted"/"redo" hade betytt krasch)
# + samma antal meddelanden, samma PVC-UID, ny skrivning ger 302
```

**Obs:** Secreten måste vara densamma som databasens lösenord. Skapas Secreten om med ett
nytt lösenord kan webben inte logga in (init-skriptet körs inte på en befintlig volym).

---

## 8. Test med ny tom PVC (separat test, dokumenterat – ej genomfört)

Syfte: verifiera att installationen fungerar från helt tom datavolym utan att röra produktionsdatan.

```sh
# 0. Säkerhetskopiera
oc exec deployment/wall-db -- pg_dump -U postgres -d walldb > walldb-backup.sql

# 1. Skapa en test-PVC
oc create -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: wall-db-data-test
  labels: {app.kubernetes.io/part-of: the-wall}
spec:
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 1Gi}}
EOF

# 2. Peka databasen mot test-PVC:n
oc scale deployment wall-db --replicas=0
oc set volume deployment/wall-db --add --overwrite --name=data --type=pvc --claim-name=wall-db-data-test
oc scale deployment wall-db --replicas=1
oc logs -f deployment/wall-db        # ska visa initdb + init-skriptet (CREATE ROLE ...)

# 3. Webben måste startas om: tabellen messages skapas av initialize() vid webbens start
oc rollout restart deployment/wall-web
# Verifiera: Messages: 0, skrivning 302, SQL count = 1

# 4. Återställ till produktionsvolymen
oc scale deployment wall-db --replicas=0
oc apply -f manifests/30-deployment-db.yaml     # claimName: wall-db-data igen
oc rollout restart deployment/wall-web
oc delete pvc wall-db-data-test
```

Alternativ: gör testet i ett separat projekt genom att följa avsnitt 2 från början.

---

## 9. Backup och återställning (föreslaget, ej testat)

En PVC är ingen backup: förloras volymen är datan borta.

```sh
# Backup (logisk dump, lagras utanför klustret)
oc exec deployment/wall-db -- pg_dump -U postgres -d walldb -Fc > walldb-$(date +%F).dump

# Återställning till en ny tom databas
oc exec -i deployment/wall-db -- pg_restore -U postgres -d walldb --clean --if-exists < walldb-YYYY-MM-DD.dump
```

Bör schemaläggas (t.ex. CronJob) och återställningen testas regelbundet.

---

## 10. Städning efter tester

```sh
oc delete job wall-loadgen --ignore-not-found
oc delete pod wall-netclient --ignore-not-found
oc get all,job -l app.kubernetes.io/part-of=the-wall   # bara wall-db, wall-web, Services, HPA, Route kvar
```
