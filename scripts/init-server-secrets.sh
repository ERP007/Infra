#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
SOURCE_DIR="$INFRA_DIR/server-secrets.example"
TARGET_DIR="$INFRA_DIR/server-secrets"

mkdir -p "$TARGET_DIR"

for source_file in "$SOURCE_DIR"/*.env; do
  target_file="$TARGET_DIR/$(basename "$source_file")"

  if [ -e "$target_file" ]; then
    echo "skip $(basename "$target_file")"
  else
    cp "$source_file" "$target_file"
    echo "created $(basename "$target_file")"
  fi
done

mkdir -p "$TARGET_DIR/cloudflared"

if [ ! -e "$TARGET_DIR/cloudflared/config.yml" ]; then
  cp "$SOURCE_DIR/cloudflared/config.yml.example" "$TARGET_DIR/cloudflared/config.yml"
  echo "created cloudflared/config.yml"
else
  echo "skip cloudflared/config.yml"
fi
