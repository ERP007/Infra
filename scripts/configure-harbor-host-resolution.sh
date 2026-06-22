#!/usr/bin/env bash
set -euo pipefail

HARBOR_HOSTNAME="${HARBOR_HOSTNAME:-registry.erp007.xyz}"
HARBOR_IP="${HARBOR_IP:-127.0.0.1}"
HOSTS_LINE="${HARBOR_IP} ${HARBOR_HOSTNAME}"

if ! grep -Eq "[[:space:]]${HARBOR_HOSTNAME}([[:space:]]|$)" /etc/hosts; then
  printf '%s\n' "$HOSTS_LINE" | sudo tee -a /etc/hosts >/dev/null
else
  sudo sed -i.bak -E "s#^[0-9a-fA-F:.]+[[:space:]]+${HARBOR_HOSTNAME}([[:space:]]|$)#${HOSTS_LINE}#" /etc/hosts
fi

echo "Host resolution:"
getent hosts "$HARBOR_HOSTNAME"
