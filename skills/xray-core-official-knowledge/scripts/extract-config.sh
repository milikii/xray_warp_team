#!/usr/bin/env bash
# extract-config.sh — Helper to extract config structs and defaults from Xray Core source.
# Usage: ./extract-config.sh <path-to-xray-core-clone> <output-dir>
#
# This script is a template. Customize it based on the actual source structure
# of XTLS/Xray-core. It demonstrates the intended extraction workflow.

set -euo pipefail

XRAY_SRC="${1:-}"
OUT_DIR="${2:-../source/config}"

if [[ -z "$XRAY_SRC" ]]; then
    echo "Usage: $0 <path-to-xray-core-clone> [output-dir]"
    exit 1
fi

mkdir -p "$OUT_DIR"

echo "[extract-config] Scanning $XRAY_SRC/infra/conf ..."
# Example: extract Go struct definitions for inbound/outbound configs.
# find "$XRAY_SRC/infra/conf" -name '*.go' -exec grep -l 'type.*Config struct' {} \; > "$OUT_DIR/struct-files.txt"

echo "[extract-config] Extracting default values ..."
# Example: grep for default constants.
# grep -rn 'Default' "$XRAY_SRC/infra/conf" > "$OUT_DIR/defaults.txt" || true

echo "[extract-config] Done. Output in $OUT_DIR"
