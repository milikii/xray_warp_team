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

acquire_script_lock() {
  local lock_dir=""
  local lock_file="${SCRIPT_LOCK_FILE}"
  local lock_opened=0

  mkdir -p "$(dirname "${lock_file}")" 2>/dev/null || true
  if command -v flock >/dev/null 2>&1; then
    if touch "${lock_file}" >/dev/null 2>&1; then
      exec 9>"${lock_file}"
      lock_opened=1
    else
      lock_file="/tmp/$(basename "${SCRIPT_LOCK_FILE}")"
      touch "${lock_file}" >/dev/null 2>&1 || die "无法创建脚本锁文件：${lock_file}"
      exec 9>"${lock_file}" || die "无法创建脚本锁文件：${lock_file}"
      lock_opened=1
    fi

    [[ "${lock_opened}" -eq 1 ]] || die "无法创建脚本锁文件。"
    flock -n 9 || die "检测到另一个 xray-warp-team 进程正在运行，请稍后重试。"
    return
  fi

  lock_dir="${lock_file}.d"
  if mkdir "${lock_dir}" 2>/dev/null; then
    trap 'rmdir "'"${lock_dir}"'" 2>/dev/null || true' EXIT
    return
  fi

  lock_dir="/tmp/$(basename "${SCRIPT_LOCK_FILE}").d"
  if mkdir "${lock_dir}" 2>/dev/null; then
    trap 'rmdir "'"${lock_dir}"'" 2>/dev/null || true' EXIT
    return
  fi

  die "检测到另一个 xray-warp-team 进程正在运行，请稍后重试。"
}

. "${SCRIPT_ROOT}/lib/base/input.sh"
. "${SCRIPT_ROOT}/lib/base/env.sh"
