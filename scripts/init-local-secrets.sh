#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
SOURCE_DIR="$INFRA_DIR/local-secrets.example"
TARGET_DIR="$INFRA_DIR/local-secrets"

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
