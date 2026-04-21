# shellcheck shell=bash

# ------------------------------
# 基础工具层
# 负责最小核心工具与基础模块装配
# ------------------------------

log() {
  printf '[信息] %s\n' "$*"
}

log_step() {
  printf '[步骤] %s\n' "$*"
}

log_success() {
  printf '[完成] %s\n' "$*"
}

warn() {
  printf '[警告] %s\n' "$*" >&2
}

die() {
  printf '[错误] %s\n' "$*" >&2
  exit 1
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "请使用 root 用户运行此脚本。"
  fi
}

. "${SCRIPT_ROOT}/lib/base/input.sh"
. "${SCRIPT_ROOT}/lib/base/env.sh"
