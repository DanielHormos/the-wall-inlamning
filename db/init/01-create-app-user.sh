#!/bin/sh
# Körs EN gång, vid första initiering av en tom datavolym.
# Skapar applikationskontot utan superuser-rättigheter och gör det
# till ägare av appens databas, så att det får skapa tabellen messages.
set -eu

psql -v ON_ERROR_STOP=1 \
     --username "$POSTGRES_USER" \
     --dbname "$POSTGRES_DB" \
     -v app_user="$APP_DB_USER" \
     -v app_password="$APP_DB_PASSWORD" \
     -v db="$POSTGRES_DB" <<'EOSQL'
CREATE ROLE :"app_user" WITH LOGIN PASSWORD :'app_password'
    NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
ALTER DATABASE :"db" OWNER TO :"app_user";
REVOKE ALL ON DATABASE :"db" FROM PUBLIC;
GRANT CONNECT, TEMPORARY ON DATABASE :"db" TO :"app_user";
EOSQL

echo "init: applikationskontot $APP_DB_USER skapat som ägare av $POSTGRES_DB"