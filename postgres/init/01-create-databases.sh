#!/bin/sh
set -eu

create_role() {
  role_name="$1"
  role_password="$2"

  psql -v ON_ERROR_STOP=1 \
    --username "$POSTGRES_USER" \
    --dbname "$POSTGRES_DB" \
    --set=role_name="$role_name" \
    --set=role_password="$role_password" <<'EOSQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'role_name', :'role_password')
WHERE NOT EXISTS (
  SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = :'role_name'
)\gexec
EOSQL
}

create_database() {
  db_name="$1"
  db_owner="$2"

  psql -v ON_ERROR_STOP=1 \
    --username "$POSTGRES_USER" \
    --dbname "$POSTGRES_DB" \
    --set=db_name="$db_name" \
    --set=db_owner="$db_owner" <<'EOSQL'
SELECT format('CREATE DATABASE %I OWNER %I', :'db_name', :'db_owner')
WHERE NOT EXISTS (
  SELECT 1 FROM pg_catalog.pg_database WHERE datname = :'db_name'
)\gexec
SELECT format('GRANT ALL PRIVILEGES ON DATABASE %I TO %I', :'db_name', :'db_owner')\gexec
EOSQL

  psql -v ON_ERROR_STOP=1 \
    --username "$POSTGRES_USER" \
    --dbname "$db_name" \
    --set=db_owner="$db_owner" <<'EOSQL'
SELECT format('ALTER SCHEMA public OWNER TO %I', :'db_owner')\gexec
SELECT format('GRANT ALL ON SCHEMA public TO %I', :'db_owner')\gexec
EOSQL
}

create_service_database() {
  db_name="$1"
  db_user="$2"
  db_password="$3"

  create_role "$db_user" "$db_password"
  create_database "$db_name" "$db_user"
}

create_service_database "$AUTH_DB_NAME" "$AUTH_DB_USER" "$AUTH_DB_PASSWORD"
create_service_database "$ITEM_DB_NAME" "$ITEM_DB_USER" "$ITEM_DB_PASSWORD"
create_service_database "$INVENTORY_DB_NAME" "$INVENTORY_DB_USER" "$INVENTORY_DB_PASSWORD"
create_service_database "$PROCUREMENT_DB_NAME" "$PROCUREMENT_DB_USER" "$PROCUREMENT_DB_PASSWORD"
create_service_database "$SALES_DB_NAME" "$SALES_DB_USER" "$SALES_DB_PASSWORD"
