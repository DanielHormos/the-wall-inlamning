# The Wall – slutuppgift i Containerteknik

## Översikt

| | |
|---|---|
| Namn | Daniel Hormos |
| Kluster | OKD 4.22 (Kubernetes 1.35), `https://api.okd.cloud2.se:6443` |
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
- **Databasversion:** PostgreSQL 16.15
- **Basimage webb:** `registry.access.redhat.com/ubi9/python-312`

## Egna ändringar mot upstream

- `app/Containerfile` – bygger imagen (UBI9 Python 3.12, körs som UID 1001)
- `app/start.sh` – kör `initialize()` före Gunicorn och startar Gunicorn med `exec`
- `db/init/01-create-app-user.sh` – skapar applikationskontot utan superuser
- `.gitattributes` – LF-radslut för skript, kod och konfiguration
- `app/app.py` – *(v2-ändringen, krav F)*

## Beroenden

*(versioner från `pip freeze` i den byggda imagen, se `tester/bevis/lokal-pip-freeze.txt`)*

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

## Bygga imagen

*(fylls i)*

## Installera i klustret

*(fylls i)*

## Verifiera

*(fylls i)*