#!/bin/sh
set -eu
echo "start.sh: DB_HOST=${DB_HOST:-saknas} DB_NAME=${DB_NAME:-saknas}"
echo "start.sh: kör databasinitiering"
python -c 'import app; app.initialize()'
echo "start.sh: initiering klar, startar Gunicorn"
exec gunicorn app:app --bind 0.0.0.0:8080