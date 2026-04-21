#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_ROOT="${ROOT_DIR:-}"
if [[ -z "${SCRIPT_ROOT}" ]]; then
  SCRIPT_SELF="${BASH_SOURCE[0]}"
  case "${SCRIPT_SELF}" in
    /dev/fd/* | /proc/*/fd/*)
      SCRIPT_ROOT="$(pwd)"
      ;;
    *)
      SCRIPT_SELF="$(readlink -f "${SCRIPT_SELF}" 2>/dev/null || printf '%s' "${SCRIPT_SELF}")"
      SCRIPT_ROOT="$(cd "$(dirname "${SCRIPT_SELF}")" && pwd)"
      ;;
  esac
fi

SELF_INSTALL_DIR_DEFAULT="/usr/local/lib/xray-warp-team"
BOOTSTRAP_SELF_INSTALL_DIR="${XRAY_WARP_TEAM_SELF_INSTALL_DIR:-${SELF_INSTALL_DIR_DEFAULT}}"
BOOTSTRAP_ARCHIVE_URL="${XRAY_WARP_TEAM_BOOTSTRAP_ARCHIVE_URL:-https://codeload.github.com/milikii/xray_warp_team/tar.gz/main}"

bootstrap_die() {
  printf '[错误] %s\n' "$*" >&2
  exit 1
}

bundle_root_ready() {
  local root_path="${1}"
  [[ -n "${root_path}" && -f "${root_path}/xray-warp-team.sh" && -f "${root_path}/lib/base/helpers.sh" ]]
}

exec_bundle_root() {
  local bundle_root="${1}"
  shift

  exec env \
    ROOT_DIR="${bundle_root}" \
    XRAY_WARP_TEAM_COMMAND_NAME="${XRAY_WARP_TEAM_COMMAND_NAME:-$(basename "$0")}" \
    bash "${bundle_root}/xray-warp-team.sh" "$@"
}

bootstrap_script_root_if_needed() {
  local bundle_root=""
  local tmp_dir=""
  local archive_path=""

  bundle_root_ready "${SCRIPT_ROOT}" && return 0

  if bundle_root_ready "${XRAY_WARP_TEAM_BOOTSTRAP_ROOT:-}"; then
    exec_bundle_root "${XRAY_WARP_TEAM_BOOTSTRAP_ROOT}" "$@"
  fi

  if bundle_root_ready "${BOOTSTRAP_SELF_INSTALL_DIR}"; then
    exec_bundle_root "${BOOTSTRAP_SELF_INSTALL_DIR}" "$@"
  fi

  command -v curl >/dev/null 2>&1 || bootstrap_die "当前目录缺少 lib/，且系统中未找到 curl，无法自动拉取脚本 bundle。"
  command -v tar >/dev/null 2>&1 || bootstrap_die "当前目录缺少 lib/，且系统中未找到 tar，无法自动拉取脚本 bundle。"

  tmp_dir="$(mktemp -d)"
  archive_path="${tmp_dir}/xray-warp-team.tar.gz"
  curl -fsSL "${BOOTSTRAP_ARCHIVE_URL}" -o "${archive_path}" || bootstrap_die "自动下载脚本 bundle 失败：${BOOTSTRAP_ARCHIVE_URL}"
  tar -xzf "${archive_path}" -C "${tmp_dir}" || bootstrap_die "解压脚本 bundle 失败。"
  bundle_root="$(find "${tmp_dir}" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  bundle_root_ready "${bundle_root}" || bootstrap_die "下载的脚本 bundle 缺少必需文件。"
  exec_bundle_root "${bundle_root}" "$@"
}

bootstrap_script_root_if_needed "$@"

SCRIPT_VERSION="0.4.1"
STATE_VERSION_CURRENT="1"
DEFAULT_REALITY_SNI="www.scu.edu"
DEFAULT_WARP_PROXY_PORT="40000"
DEFAULT_TLS_ALPN="h2"
DEFAULT_FINGERPRINT="chrome"
DEFAULT_XHTTP_VLESS_ENCRYPTION_ENABLED="yes"
DEFAULT_CF_CERT_VALIDITY="5475"
DEFAULT_ACME_CA="letsencrypt"
DEFAULT_XHTTP_ECH_CONFIG_LIST=""
DEFAULT_XHTTP_ECH_FORCE_QUERY=""
XRAY_BIN="/usr/local/bin/xray"
XRAY_CONFIG_DIR="/usr/local/etc/xray"
XRAY_CONFIG_FILE="${XRAY_CONFIG_DIR}/config.json"
XRAY_ASSET_DIR="/usr/local/share/xray"
XRAY_SERVICE_FILE="/etc/systemd/system/xray.service"
SELF_COMMAND_PATH="/usr/local/sbin/xray-warp-team"
SELF_INSTALL_DIR="${BOOTSTRAP_SELF_INSTALL_DIR}"
HAPROXY_CONFIG="/etc/haproxy/haproxy.cfg"
NGINX_CONF_DIR="/etc/nginx/conf.d"
NGINX_CONFIG_FILE="${NGINX_CONF_DIR}/xray-warp-team.conf"
NGINX_TLS_PORT="8443"
XHTTP_LOCAL_PORT="8001"
NGINX_SERVICE_FILE="/lib/systemd/system/nginx.service"
STATE_FILE="${XRAY_CONFIG_DIR}/node-meta.env"
HEALTH_STATE_FILE="${XRAY_CONFIG_DIR}/health-state.env"
HEALTH_HISTORY_FILE="${XRAY_CONFIG_DIR}/health-history.log"
OUTPUT_FILE="/root/xray-warp-team-output.md"
SSL_DIR="/etc/ssl/xray-warp-team"
TLS_CERT_FILE="${SSL_DIR}/cert.pem"
TLS_KEY_FILE="${SSL_DIR}/key.pem"
WARP_MDM_FILE="/var/lib/cloudflare-warp/mdm.xml"
WARP_RULES_FILE="${XRAY_CONFIG_DIR}/warp-domains.list"
WARP_APT_KEYRING="/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg"
WARP_APT_SOURCE_LIST="/etc/apt/sources.list.d/cloudflare-client.list"
WARP_HEALTH_HELPER="/usr/local/sbin/xray-warp-team-warp-health.sh"
WARP_HEALTH_SERVICE_NAME="xray-warp-team-warp-health.service"
WARP_HEALTH_SERVICE_FILE="/etc/systemd/system/${WARP_HEALTH_SERVICE_NAME}"
WARP_HEALTH_TIMER_NAME="xray-warp-team-warp-health.timer"
WARP_HEALTH_TIMER_FILE="/etc/systemd/system/${WARP_HEALTH_TIMER_NAME}"
CORE_HEALTH_HELPER="/usr/local/sbin/xray-warp-team-core-health.sh"
CORE_HEALTH_SERVICE_NAME="xray-warp-team-core-health.service"
CORE_HEALTH_SERVICE_FILE="/etc/systemd/system/${CORE_HEALTH_SERVICE_NAME}"
CORE_HEALTH_TIMER_NAME="xray-warp-team-core-health.timer"
CORE_HEALTH_TIMER_FILE="/etc/systemd/system/${CORE_HEALTH_TIMER_NAME}"
BACKUP_ROOT="/root/xray-warp-team-backups"
NET_SYSCTL_CONF="/etc/sysctl.d/98-xray-warp-team-net.conf"
NET_HELPER_PATH="/usr/local/sbin/xray-warp-team-net-optimize.sh"
NET_SERVICE_NAME="xray-warp-team-net-optimize.service"
NET_SERVICE_FILE="/etc/systemd/system/${NET_SERVICE_NAME}"
ACME_HOME="/root/.acme.sh"
ACME_SH_BIN="${ACME_HOME}/acme.sh"
ACME_RELOAD_HELPER="/usr/local/sbin/xray-warp-team-cert-reload.sh"
INSTALL_DRAFT_FILE="/root/.xray-warp-team-install-draft.env"

NON_INTERACTIVE=0
ENABLE_WARP=""
ENABLE_NET_OPT=""
CERT_MODE=""
SERVER_IP=""
NODE_LABEL_PREFIX=""
REALITY_UUID=""
REALITY_SNI=""
REALITY_TARGET=""
REALITY_SHORT_ID=""
REALITY_PRIVATE_KEY=""
REALITY_PUBLIC_KEY=""
XHTTP_UUID=""
XHTTP_DOMAIN=""
XHTTP_PATH=""
XHTTP_VLESS_ENCRYPTION_ENABLED="${DEFAULT_XHTTP_VLESS_ENCRYPTION_ENABLED}"
XHTTP_VLESS_DECRYPTION=""
XHTTP_VLESS_ENCRYPTION=""
TLS_ALPN="${DEFAULT_TLS_ALPN}"
FINGERPRINT="${DEFAULT_FINGERPRINT}"
WARP_TEAM_NAME=""
WARP_CLIENT_ID=""
WARP_CLIENT_SECRET=""
WARP_PROXY_PORT="${DEFAULT_WARP_PROXY_PORT}"
WARP_RULES_TEXT=""
XRAY_UID=""
XRAY_GID=""
XHTTP_SPLIT_EXTRA=""
CERT_SOURCE_FILE=""
KEY_SOURCE_FILE=""
CERT_SOURCE_PEM=""
KEY_SOURCE_PEM=""
CF_ZONE_ID=""
CF_API_TOKEN=""
CF_CERT_VALIDITY="${DEFAULT_CF_CERT_VALIDITY}"
ACME_EMAIL=""
ACME_CA="${DEFAULT_ACME_CA}"
CF_DNS_TOKEN=""
CF_DNS_ACCOUNT_ID=""
CF_DNS_ZONE_ID=""
XHTTP_ECH_CONFIG_LIST="${DEFAULT_XHTTP_ECH_CONFIG_LIST}"
XHTTP_ECH_FORCE_QUERY="${DEFAULT_XHTTP_ECH_FORCE_QUERY}"

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
  C_CYAN=$'\033[36m'
else
  C_RESET=""
  C_BOLD=""
  C_GREEN=""
  C_YELLOW=""
  C_RED=""
  C_CYAN=""
fi

. "${SCRIPT_ROOT}/lib/base/helpers.sh"

. "${SCRIPT_ROOT}/lib/install.sh"
. "${SCRIPT_ROOT}/lib/generators.sh"
. "${SCRIPT_ROOT}/lib/state.sh"
. "${SCRIPT_ROOT}/lib/base/runtime.sh"

. "${SCRIPT_ROOT}/lib/ui.sh"
. "${SCRIPT_ROOT}/lib/commands.sh"

main() {
  run_cli_command "$@"
}

main "$@"
