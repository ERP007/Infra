#!/usr/bin/env bash
set -euo pipefail

TARGET_SIZE="${1:-300G}"
LV_PATH="${LV_PATH:-/dev/ubuntu-vg/ubuntu-lv}"

if [ ! -e "$LV_PATH" ]; then
  LV_PATH="/dev/mapper/ubuntu--vg-ubuntu--lv"
fi

echo "Before:"
lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT
df -h /

echo "Extending $LV_PATH to $TARGET_SIZE"
sudo lvextend -L "$TARGET_SIZE" -r "$LV_PATH"

echo "After:"
lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT
df -h /
