# The Wall – slutuppgift i Containerteknik

## Översikt

| | |
|---|---|
| Namn | Daniel Hormos |
| Kluster | OKD 4.22 (härlett från Kubernetes 1.35), `https://api.okd.cloud2.se:6443` |
| Projekt | `student-daniel-hormos-lerniastudent-se` |
| Route-adress | *(fylls i efter driftsättning)* |
| Upstream | https://github.com/jonasbjork/the-wall |
| Upstream-commit | `caa199b60b0218675bc2156f0dff00131d464512` |

## Images

| Komponent | Image | Digest |
|---|---|---|
| Webb v1 | `quay.io/lerniadevopsdanielhormos/the-wall:1.0.0` | `sha256:7e25a53a4ef88a29dd2e8dab8efb4fd1919e7ec469fedab98bffd437cdfb378f` |
| Webb v2 | *(krav F)* | |
| Databas | `quay.io/kurs/postgresql:2026-10-29` | `sha256:5e1750934d4de30c9718f358e4913e98fa2024c3a86de88e972ba5d5b640d82f` |

- **Registry:** Quay.io, publikt repository (ingen pull secret behövs)
- **Databasversion:** PostgreSQL 16.15 (Alpine), körs som icke-root (UID 1001)
- **Basimage webb:** `registry.access.redhat.com/ubi9/python-312`
  (vid bygget löst till `sha256:5b184c2acfe9e2eb9df1a243da8e4a82fedd96e5e7f6648ec5512656177fa326`)

## Egna ändringar mot upstream

- `app/Containerfile` – bygger imagen (UBI9 Python 3.12, körs som UID 1001)
- `app/start.sh` – kör `initialize()` före Gunicorn och startar Gunicorn med `exec`
  (Gunicorn anropar inte `initialize()` vid import av `app:app`)
- `db/init/01-create-app-user.sh` – skapar applikationskontot `walluser` utan
  superuser-rättigheter, som ägare av databasen `walldb`
- `.gitattributes` – LF-radslut för skript, kod och konfiguration
- `app/app.py` – *(v2-ändringen, krav F)*

## Beroenden

Upstream `requirements.txt` anger tillåtna intervall (t.ex. `Flask>=3.1,<4`).
Exakta versioner i den byggda imagen v1 (`pip freeze`, se
`tester/bevis/lokal-pip-freeze.txt`):

```text
blinker==1.9.0
click==8.5.1
Flask==3.1.3
gunicorn==23.0.0
itsdangerous==2.2.0
Jinja2==3.1.6
MarkupSafe==3.0.4
packaging==26.3
psycopg==3.3.9
psycopg-binary==3.3.9
typing_extensions==4.16.0
Werkzeug==3.1.9
```

Python i imagen: Python 3.12.15

## Verktyg som använts

- Docker 29.9.3 (Docker Desktop, WSL2) på Windows
- oc 4.22.0
- Git 2.46

## Mappstruktur

| Mapp | Innehåll |
|---|---|
| `app/` | Appkod, Containerfile, start.sh |
| `db/init/` | Init-skript för databasen |
| `manifests/` | Kubernetes-/OKD-manifest |
| `tester/` | Verifieringsprotokoll och bevis |
| `drift/` | Runbook och incidentlogg |
| `rapport/` | Projektrapport och beslutslogg |

Avvikelse från uppgiftens struktur: `db/init/` är tillagd för databasens
init-skript. Det läggs in i klustret som ConfigMap `wall-db-init`
(`manifests/12-configmap-db-init.yaml`), genererad från skriptet.

## Bygga imagen

Förutsättningar: Docker eller Podman, inloggad i registryt (`docker login quay.io`).

```sh
docker build -t quay.io/lerniadevopsdanielhormos/the-wall:1.0.0 -f app/Containerfile app
docker push quay.io/lerniadevopsdanielhormos/the-wall:1.0.0
```

- Byggkontext: mappen `app/`
- Imagen körs som UID 1001 och startar `start.sh`

## Databasuppgifter (Secrets)

Lösenorden finns inte i repot. Skapa dem innan installationen.
Webben får aldrig adminlösenordet.

| Secret | Nycklar | Används av |
|---|---|---|
| `wall-db-admin` | `password` | databasen (superuser `postgres`) |
| `wall-db-credentials` | `username`, `password` | databasen (init-skriptet) och webben |

**Linux/macOS:**
```sh
oc create secret generic wall-db-admin \
  --from-literal=password="$(openssl rand -base64 24 | tr -d '/+=')"
oc create secret generic wall-db-credentials \
  --from-literal=username=walluser \
  --from-literal=password="$(openssl rand -base64 24 | tr -d '/+=')"
oc label secret wall-db-admin wall-db-credentials app.kubernetes.io/part-of=the-wall
```

**Windows PowerShell:**
```powershell
$b = New-Object byte[] 24; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
$adminPw = [Convert]::ToBase64String($b) -replace '[+/=]',''
$b = New-Object byte[] 24; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
$appPw = [Convert]::ToBase64String($b) -replace '[+/=]',''
oc create secret generic wall-db-admin --from-literal=password=$adminPw
oc create secret generic wall-db-credentials --from-literal=username=walluser --from-literal=password=$appPw
oc label secret wall-db-admin wall-db-credentials app.kubernetes.io/part-of=the-wall
```

Kontroll (visar bara längder, inga värden):
```sh
oc describe secret wall-db-admin wall-db-credentials
```

**Obs:** Lösenorden används bara vid första initiering av en tom datavolym.
Att ändra en Secret i efterhand byter inte lösenordet i databasen – se runbooken.

## Installera i klustret

```sh
oc project "$LAB_PROJECT"
oc apply -f manifests/
```

*(kompletteras när alla manifest är klara)*

## Verifiera

*(fylls i)*