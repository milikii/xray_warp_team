#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

load_functions() {
  # ------------------------------
  # 只加载函数定义，不执行 main
  # 这样 smoke test 可以直接调用内部生成器
  # ------------------------------
  # shellcheck disable=SC1090
  source <(sed '$d' "${ROOT_DIR}/xray-warp-team.sh")
}

prepare_workspace() {
  local workdir="${1}"

  XRAY_CONFIG_DIR="${workdir}/xray"
  XRAY_CONFIG_FILE="${XRAY_CONFIG_DIR}/config.json"
  STATE_FILE="${XRAY_CONFIG_DIR}/node-meta.env"
  OUTPUT_FILE="${workdir}/output.md"
  mkdir -p "${XRAY_CONFIG_DIR}"
}

stub_side_effects() {
  ensure_managed_permissions() { :; }
  backup_path() { :; }
}

assert_contains() {
  local pattern="${1}"
  local path="${2}"

  grep -q -- "${pattern}" "${path}"
}
