#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
SOURCE_DIR="$INFRA_DIR/server-secrets.example"
TARGET_DIR="$INFRA_DIR/server-secrets"

mkdir -p "$TARGET_DIR"

get_env_value() {
  env_file="$1"
  env_key="$2"

  if [ ! -e "$env_file" ]; then
    return 0
  fi

  grep -E "^${env_key}=" "$env_file" | tail -n 1 | cut -d= -f2- || true
}

set_env_value() {
  env_file="$1"
  env_key="$2"
  env_value="$3"

  if grep -q "^${env_key}=" "$env_file"; then
    tmp_file="$(mktemp)"
    sed "s|^${env_key}=.*|${env_key}=${env_value}|" "$env_file" > "$tmp_file"
    mv "$tmp_file" "$env_file"
  else
    printf '\n%s=%s\n' "$env_key" "$env_value" >> "$env_file"
  fi
}

create_service_postgres_env() {
  service_name="$1"
  db_name="$2"
  default_user="$3"
  default_password="$4"

  service_env="$TARGET_DIR/${service_name}-service.env"
  postgres_env="$TARGET_DIR/${service_name}-postgres.env"
  datasource_url="jdbc:postgresql://${service_name}-postgres:5432/${db_name}"

  if [ -e "$service_env" ]; then
    set_env_value "$service_env" "SPRING_DATASOURCE_URL" "$datasource_url"
    echo "synced ${service_name}-service.env datasource"
  fi

  if [ -e "$postgres_env" ]; then
    echo "skip $(basename "$postgres_env")"
    return 0
  fi

  db_user="$(get_env_value "$service_env" "SPRING_DATASOURCE_USERNAME")"
  db_password="$(get_env_value "$service_env" "SPRING_DATASOURCE_PASSWORD")"

  if [ -z "$db_user" ]; then
    db_user="$default_user"
  fi

  if [ -z "$db_password" ]; then
    db_password="$default_password"
  fi

  {
    printf 'POSTGRES_USER=%s\n' "$db_user"
    printf 'POSTGRES_PASSWORD=%s\n' "$db_password"
    printf 'POSTGRES_DB=%s\n' "$db_name"
  } > "$postgres_env"
  echo "created $(basename "$postgres_env")"
}

for source_file in "$SOURCE_DIR"/*.env; do
  case "$(basename "$source_file")" in
    *-postgres.env)
      continue
      ;;
  esac

  target_file="$TARGET_DIR/$(basename "$source_file")"

  if [ -e "$target_file" ]; then
    echo "skip $(basename "$target_file")"
  else
    cp "$source_file" "$target_file"
    echo "created $(basename "$target_file")"
  fi
done

create_service_postgres_env "user" "user_db" "user_user" "change_me_user_db_password"
create_service_postgres_env "item" "item_db" "item_user" "change_me_item_db_password"
create_service_postgres_env "inventory" "inventory_db" "inventory_user" "change_me_inventory_db_password"
create_service_postgres_env "procurement" "procurement_db" "procurement_user" "change_me_procurement_db_password"
create_service_postgres_env "sales" "sales_db" "sales_user" "change_me_sales_db_password"

procurement_service_env="$TARGET_DIR/procurement-service.env"
if [ -e "$procurement_service_env" ]; then
  set_env_value "$procurement_service_env" "INVENTORY_SERVICE_URL" "http://inventory-service:8080"
  set_env_value "$procurement_service_env" "ITEM_SERVICE_URL" "http://item-service:8080"
  set_env_value "$procurement_service_env" "USER_SERVICE_URL" "http://user-service:8080"
  set_env_value "$procurement_service_env" "KEYCLOAK_ISSUER_URI" "https://auth.erp007.xyz/realms/master"
  set_env_value "$procurement_service_env" "KEYCLOAK_JWK_SET_URI" "https://auth.erp007.xyz/realms/master/protocol/openid-connect/certs"
  set_env_value "$procurement_service_env" "SPRING_JPA_HIBERNATE_DDL_AUTO" "none"
  echo "synced procurement-service.env service urls and jwt settings"
fi

mkdir -p "$TARGET_DIR/cloudflared"

if [ ! -e "$TARGET_DIR/cloudflared/config.yml" ]; then
  cp "$SOURCE_DIR/cloudflared/config.yml.example" "$TARGET_DIR/cloudflared/config.yml"
  echo "created cloudflared/config.yml"
else
  echo "skip cloudflared/config.yml"
fi
