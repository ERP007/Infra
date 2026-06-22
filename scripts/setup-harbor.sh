#!/usr/bin/env bash
set -euo pipefail

HARBOR_VERSION="${HARBOR_VERSION:-2.14.0}"
HARBOR_HOSTNAME="${HARBOR_HOSTNAME:-registry.erp007.xyz}"
INSTALL_ROOT="${INSTALL_ROOT:-/home/taehyung/apps/platform/harbor}"
DATA_VOLUME="${DATA_VOLUME:-${INSTALL_ROOT}/data}"
CERT_DIR="${CERT_DIR:-/home/taehyung/apps/msa-server/infra/server-secrets/harbor}"
ADMIN_PASSWORD_FILE="${ADMIN_PASSWORD_FILE:-${CERT_DIR}/admin-password}"
DB_PASSWORD_FILE="${DB_PASSWORD_FILE:-${CERT_DIR}/database-password}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-${INSTALL_ROOT}/downloads}"
CERT_FILE="${CERT_FILE:-${CERT_DIR}/${HARBOR_HOSTNAME}.crt}"
KEY_FILE="${KEY_FILE:-${CERT_DIR}/${HARBOR_HOSTNAME}.key}"
ALLOW_SELF_SIGNED_ORIGIN="${ALLOW_SELF_SIGNED_ORIGIN:-false}"
HOST_GATEWAY_BIND_IP="${HOST_GATEWAY_BIND_IP:-172.17.0.1}"

mkdir -p "$INSTALL_ROOT" "$DATA_VOLUME" "$CERT_DIR" "$DOWNLOAD_DIR"

if { [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; } && [ "$ALLOW_SELF_SIGNED_ORIGIN" = "true" ]; then
  openssl req -x509 -nodes -newkey rsa:4096 -days 3650 \
    -keyout "$KEY_FILE" \
    -out "$CERT_FILE" \
    -subj "/CN=${HARBOR_HOSTNAME}" \
    -addext "subjectAltName=DNS:${HARBOR_HOSTNAME}"
  chmod 600 "$KEY_FILE"
fi

if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
  cat >&2 <<EOF
Missing Harbor TLS files:
  $CERT_FILE
  $KEY_FILE

Create a real certificate for ${HARBOR_HOSTNAME} first. Docker clients must trust
this endpoint when they connect directly. If Harbor is only reached through
Cloudflare Tunnel, run with ALLOW_SELF_SIGNED_ORIGIN=true and keep
originRequest.noTLSVerify enabled for registry.erp007.xyz.
EOF
  exit 1
fi

if [ ! -f "$ADMIN_PASSWORD_FILE" ]; then
  openssl rand -base64 32 > "$ADMIN_PASSWORD_FILE"
  chmod 600 "$ADMIN_PASSWORD_FILE"
fi

if [ ! -f "$DB_PASSWORD_FILE" ]; then
  openssl rand -base64 32 > "$DB_PASSWORD_FILE"
  chmod 600 "$DB_PASSWORD_FILE"
fi

ARCHIVE="harbor-online-installer-v${HARBOR_VERSION}.tgz"
ARCHIVE_PATH="${DOWNLOAD_DIR}/${ARCHIVE}"
if [ ! -f "$ARCHIVE_PATH" ]; then
  curl -fL "https://github.com/goharbor/harbor/releases/download/v${HARBOR_VERSION}/${ARCHIVE}" -o "$ARCHIVE_PATH"
fi

tar -xzf "$ARCHIVE_PATH" -C "$INSTALL_ROOT"
HARBOR_DIR="${INSTALL_ROOT}/harbor"
cd "$HARBOR_DIR"

cp -f harbor.yml.tmpl harbor.yml
ADMIN_PASSWORD="$(cat "$ADMIN_PASSWORD_FILE")"
DB_PASSWORD="$(cat "$DB_PASSWORD_FILE")"
export HARBOR_HOSTNAME CERT_FILE KEY_FILE ADMIN_PASSWORD DB_PASSWORD DATA_VOLUME

python3 - <<'PY'
import os
from pathlib import Path

path = Path("harbor.yml")
text = path.read_text()
replacements = {
    "hostname: reg.mydomain.com": f"hostname: {os.environ['HARBOR_HOSTNAME']}",
    "  port: 80": "  port: 8088",
    "  port: 443": "  port: 443",
    "  certificate: /your/certificate/path": f"  certificate: {os.environ['CERT_FILE']}",
    "  private_key: /your/private/key/path": f"  private_key: {os.environ['KEY_FILE']}",
    "harbor_admin_password: Harbor12345": f"harbor_admin_password: {os.environ['ADMIN_PASSWORD']}",
    "  password: root123": f"  password: {os.environ['DB_PASSWORD']}",
    "data_volume: /data": f"data_volume: {os.environ['DATA_VOLUME']}",
}
for src, dst in replacements.items():
    text = text.replace(src, dst)
if "external_url:" not in text:
    text += f"\nexternal_url: https://{os.environ['HARBOR_HOSTNAME']}\n"
path.write_text(text)
PY

mkdir -p common/config "$DATA_VOLUME"
perl -0pi -e 's/ --user "\$\(id -u\):\$\(id -g\)"//g' prepare
./prepare

docker run --rm \
  -v "${HARBOR_DIR}:/work" \
  alpine:3.20 \
  sh -c "chown -R $(id -u):$(id -g) /work/common /work/docker-compose.yml && chmod -R u+rwX,go+rX /work/common"

cat > docker-compose.local.yml <<'EOF'
services:
  proxy:
    ports: !override
      - 127.0.0.1:8088:8080
      - 127.0.0.1:443:8443
EOF

if [ -n "$HOST_GATEWAY_BIND_IP" ]; then
  python3 - <<'PY'
import os
from pathlib import Path

path = Path("docker-compose.local.yml")
text = path.read_text()
bind_ip = os.environ["HOST_GATEWAY_BIND_IP"]
text = text.replace(
    "      - 127.0.0.1:8088:8080\n      - 127.0.0.1:443:8443\n",
    f"      - 127.0.0.1:8088:8080\n      - {bind_ip}:8088:8080\n"
    f"      - 127.0.0.1:443:8443\n      - {bind_ip}:443:8443\n",
)
path.write_text(text)
PY
fi

docker compose -f docker-compose.yml -f docker-compose.local.yml up -d
docker compose ps

cat <<EOF
Harbor is running locally.

Admin password file:
  ${ADMIN_PASSWORD_FILE}

Next manual steps:
  1. Create private project: erp007
  2. Create robot account for Jenkins and store it as Jenkins credential: harbor-robot-erp007
  3. Configure retention: keep latest 10 artifacts per repository
  4. Configure project quota: 120GB
  5. Configure weekly garbage collection
EOF
