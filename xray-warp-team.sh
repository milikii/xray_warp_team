#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_VERSION="0.4.1"
DEFAULT_REALITY_SNI="www.scu.edu"
DEFAULT_WARP_PROXY_PORT="40000"
DEFAULT_TLS_ALPN="h2"
DEFAULT_FINGERPRINT="chrome"
DEFAULT_CF_CERT_VALIDITY="5475"
DEFAULT_ACME_CA="letsencrypt"
DEFAULT_XHTTP_ECH_CONFIG_LIST="https://1.1.1.1/dns-query"
DEFAULT_XHTTP_ECH_FORCE_QUERY="none"
XRAY_BIN="/usr/local/bin/xray"
XRAY_CONFIG_DIR="/usr/local/etc/xray"
XRAY_CONFIG_FILE="${XRAY_CONFIG_DIR}/config.json"
XRAY_ASSET_DIR="/usr/local/share/xray"
XRAY_SERVICE_FILE="/etc/systemd/system/xray.service"
SELF_COMMAND_PATH="/usr/local/sbin/xray-warp-team"
HAPROXY_CONFIG="/etc/haproxy/haproxy.cfg"
STATE_FILE="${XRAY_CONFIG_DIR}/node-meta.env"
OUTPUT_FILE="/root/xray-warp-team-output.md"
SSL_DIR="/etc/ssl/xray-warp-team"
TLS_CERT_FILE="${SSL_DIR}/cert.pem"
TLS_KEY_FILE="${SSL_DIR}/key.pem"
WARP_MDM_FILE="/var/lib/cloudflare-warp/mdm.xml"
BACKUP_ROOT="/root/xray-warp-team-backups"
NET_SYSCTL_CONF="/etc/sysctl.d/98-xray-warp-team-net.conf"
NET_HELPER_PATH="/usr/local/sbin/xray-warp-team-net-optimize.sh"
NET_SERVICE_NAME="xray-warp-team-net-optimize.service"
NET_SERVICE_FILE="/etc/systemd/system/${NET_SERVICE_NAME}"
ACME_HOME="/root/.acme.sh"
ACME_SH_BIN="${ACME_HOME}/acme.sh"
ACME_RELOAD_HELPER="/usr/local/sbin/xray-warp-team-cert-reload.sh"

NON_INTERACTIVE=0
ENABLE_WARP=""
ENABLE_NET_OPT=""
CERT_MODE=""
SERVER_IP=""
REALITY_UUID=""
REALITY_SNI=""
REALITY_TARGET=""
REALITY_SHORT_ID=""
REALITY_PRIVATE_KEY=""
REALITY_PUBLIC_KEY=""
XHTTP_UUID=""
XHTTP_DOMAIN=""
XHTTP_PATH=""
TLS_ALPN="${DEFAULT_TLS_ALPN}"
FINGERPRINT="${DEFAULT_FINGERPRINT}"
WARP_TEAM_NAME=""
WARP_CLIENT_ID=""
WARP_CLIENT_SECRET=""
WARP_PROXY_PORT="${DEFAULT_WARP_PROXY_PORT}"
CERT_SOURCE_FILE=""
KEY_SOURCE_FILE=""
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

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Please run this script as root."
  fi
}

usage() {
  cat <<'EOF'
xray-warp-team.sh v0.4.1

Usage:
  bash xray-warp-team.sh
  bash xray-warp-team.sh install [options]
  bash xray-warp-team.sh upgrade
  bash xray-warp-team.sh change-uuid [options]
  bash xray-warp-team.sh change-sni [options]
  bash xray-warp-team.sh change-path [options]
  bash xray-warp-team.sh change-cert-mode [options]
  bash xray-warp-team.sh uninstall [--yes]
  bash xray-warp-team.sh show-links
  bash xray-warp-team.sh status [--raw]
  bash xray-warp-team.sh restart
  bash xray-warp-team.sh help

Install options:
  --non-interactive           Run without prompts. Missing required values will fail.
  --server-ip VALUE           Public IP or hostname for the direct REALITY node.
  --reality-uuid VALUE        UUID for the REALITY node.
  --reality-sni VALUE         Visible SNI for REALITY and HAProxy routing.
  --reality-target VALUE      REALITY target in host:port form.
  --reality-short-id VALUE    Short ID for REALITY.
  --reality-private-key VALUE Preserve an existing REALITY private key.
  --xhttp-uuid VALUE          UUID for the XHTTP CDN node.
  --xhttp-domain VALUE        Orange-cloud domain for the XHTTP CDN node.
  --xhttp-path VALUE          XHTTP path, for example /cfup-example.
  --cert-mode VALUE           self-signed, existing, cf-origin-ca, or acme-dns-cf.
  --cert-file VALUE           Existing certificate file when --cert-mode existing.
  --key-file VALUE            Existing key file when --cert-mode existing.
  --cf-zone-id VALUE          Cloudflare zone ID for cf-origin-ca mode.
  --cf-api-token VALUE        Cloudflare API token for cf-origin-ca mode.
  --cf-cert-validity VALUE    Cloudflare Origin CA validity days. Default: 5475
  --acme-email VALUE          Email used by acme.sh account registration.
  --acme-ca VALUE             ACME CA name passed to acme.sh. Default: letsencrypt
  --cf-dns-token VALUE        Cloudflare DNS API token for acme dns_cf mode.
  --cf-dns-account-id VALUE   Cloudflare account ID for acme dns_cf mode. Optional.
  --cf-dns-zone-id VALUE      Cloudflare zone ID for acme dns_cf mode. Optional.
  --enable-warp               Enable selective WARP outbound.
  --disable-warp              Disable WARP outbound.
  --enable-net-opt            Enable BBR/FQ/RPS network optimization.
  --disable-net-opt           Disable network optimization.
  --warp-team VALUE           Cloudflare Zero Trust team name.
  --warp-client-id VALUE      Service token client ID.
  --warp-client-secret VALUE  Service token client secret.
  --warp-proxy-port VALUE     Local SOCKS5 port used by WARP. Default: 40000

Change-uuid options:
  --reality-uuid VALUE        Set a custom REALITY UUID instead of generating one.
  --xhttp-uuid VALUE          Set a custom XHTTP UUID instead of generating one.
  --reality-only              Rotate only the REALITY UUID.
  --xhttp-only                Rotate only the XHTTP UUID.

Change-sni options:
  --non-interactive           Run without prompts.
  --reality-sni VALUE         New REALITY visible SNI.
  --reality-target VALUE      New REALITY target in host:port form.

Change-path options:
  --non-interactive           Run without prompts.
  --xhttp-path VALUE          New XHTTP path.

Change-cert-mode options:
  --non-interactive           Run without prompts.
  --cert-mode VALUE           New cert mode: self-signed, existing, cf-origin-ca, acme-dns-cf.
  --xhttp-domain VALUE        New XHTTP CDN domain. Optional.
  --cert-file VALUE           Existing certificate file when using existing mode.
  --key-file VALUE            Existing key file when using existing mode.
  --cf-zone-id VALUE          Cloudflare zone ID for cf-origin-ca mode.
  --cf-api-token VALUE        Cloudflare API token for cf-origin-ca mode.
  --cf-cert-validity VALUE    Cloudflare Origin CA validity days.
  --acme-email VALUE          Email used by acme.sh account registration.
  --acme-ca VALUE             ACME CA name passed to acme.sh.
  --cf-dns-token VALUE        Cloudflare DNS API token for acme dns_cf mode.
  --cf-dns-account-id VALUE   Cloudflare account ID for acme dns_cf mode. Optional.
  --cf-dns-zone-id VALUE      Cloudflare zone ID for acme dns_cf mode. Optional.

Uninstall options:
  --yes                       Skip confirmation prompt.

Status options:
  --raw                       Show raw systemctl output instead of the panel.

Examples:
  bash xray-warp-team.sh
  bash xray-warp-team.sh upgrade
  bash xray-warp-team.sh change-uuid
  bash xray-warp-team.sh change-sni --reality-sni www.stanford.edu
  bash xray-warp-team.sh change-path --xhttp-path /cfup-new
  bash xray-warp-team.sh change-cert-mode --cert-mode self-signed
  bash xray-warp-team.sh uninstall --yes
  bash xray-warp-team.sh install --non-interactive \
    --server-ip 203.0.113.10 \
    --xhttp-domain cdn.example.com \
    --cert-mode self-signed \
    --enable-net-opt \
    --warp-team your-team \
    --warp-client-id xxxxxxxxx.access \
    --warp-client-secret xxxxxxxxx
EOF
}

guess_server_ip() {
  local guessed=""

  guessed="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") {print $(i + 1); exit}}')"
  if [[ -z "${guessed}" ]]; then
    guessed="$(ip -o -4 addr show scope global 2>/dev/null | awk '{split($4, a, "/"); print a[1]; exit}')"
  fi
  printf '%s' "${guessed}"
}

random_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr 'A-Z' 'a-z'
  else
    cat /proc/sys/kernel/random/uuid
  fi
}

random_hex() {
  local bytes="${1}"
  openssl rand -hex "${bytes}"
}

random_path() {
  printf '/cfup-%s' "$(random_hex 6)"
}

prompt_with_default() {
  local var_name="${1}"
  local prompt_text="${2}"
  local default_value="${3}"
  local current_value=""

  current_value="${!var_name:-}"
  if [[ -n "${current_value}" ]]; then
    return
  fi

  if [[ "${NON_INTERACTIVE}" -eq 1 ]]; then
    if [[ -n "${default_value}" ]]; then
      printf -v "${var_name}" '%s' "${default_value}"
      return
    fi
    die "Missing required value for ${var_name}."
  fi

  if [[ -n "${default_value}" ]]; then
    read -r -p "${prompt_text} [${default_value}]: " current_value
    current_value="${current_value:-${default_value}}"
  else
    read -r -p "${prompt_text}: " current_value
  fi

  printf -v "${var_name}" '%s' "${current_value}"
}

prompt_secret() {
  local var_name="${1}"
  local prompt_text="${2}"
  local current_value=""

  current_value="${!var_name:-}"
  if [[ -n "${current_value}" ]]; then
    return
  fi

  if [[ "${NON_INTERACTIVE}" -eq 1 ]]; then
    die "Missing required secret value for ${var_name}."
  fi

  read -r -s -p "${prompt_text}: " current_value
  printf '\n'
  printf -v "${var_name}" '%s' "${current_value}"
}

prompt_yes_no() {
  local var_name="${1}"
  local prompt_text="${2}"
  local default_value="${3}"
  local answer=""

  if [[ -n "${!var_name:-}" ]]; then
    return
  fi

  if [[ "${NON_INTERACTIVE}" -eq 1 ]]; then
    printf -v "${var_name}" '%s' "${default_value}"
    return
  fi

  read -r -p "${prompt_text} [${default_value}]: " answer
  answer="${answer:-${default_value}}"
  printf -v "${var_name}" '%s' "${answer}"
}

style_text() {
  local style="${1}"
  local text="${2}"
  printf '%b%s%b' "${style}" "${text}" "${C_RESET}"
}

divider() {
  printf '%s\n' '--------------------------------------------------------------------'
}

panel_row() {
  printf '  %-18s %s\n' "${1}" "${2}"
}

short_value() {
  local value="${1}"
  local head="${2:-8}"
  local tail="${3:-6}"
  local len=0

  len="${#value}"
  if [[ "${len}" -le $((head + tail + 3)) ]]; then
    printf '%s' "${value}"
  else
    printf '%s...%s' "${value:0:head}" "${value: -tail}"
  fi
}

service_active_state() {
  local unit_name="${1}"
  local state=""

  if ! service_exists "${unit_name}"; then
    printf 'not-installed'
    return
  fi

  case "${unit_name}" in
    xray.service)
      if pgrep -x xray >/dev/null 2>&1; then
        printf 'active'
        return
      fi
      ;;
    haproxy.service)
      if pgrep -x haproxy >/dev/null 2>&1; then
        printf 'active'
        return
      fi
      ;;
    warp-svc.service)
      if pgrep -f 'warp-svc|warp-service' >/dev/null 2>&1; then
        printf 'active'
        return
      fi
      ;;
  esac

  state="$(systemctl is-active "${unit_name}" 2>/dev/null || true)"
  if [[ -n "${state}" ]]; then
    printf '%s' "${state}"
  else
    printf 'installed'
  fi
}

service_enable_state() {
  local unit_name="${1}"
  local path=""

  if ! service_exists "${unit_name}"; then
    printf 'not-installed'
    return
  fi

  for path in /etc/systemd/system/*.wants/"${unit_name}" /etc/systemd/system/"${unit_name}"; do
    if [[ -e "${path}" || -L "${path}" ]]; then
      printf 'enabled'
      return
    fi
  done

  printf 'installed'
}

service_badge() {
  local state="${1}"

  case "${state}" in
    active)
      style_text "${C_GREEN}" "running"
      ;;
    inactive|failed|activating|deactivating)
      style_text "${C_RED}" "${state}"
      ;;
    not-installed)
      style_text "${C_YELLOW}" "not-installed"
      ;;
    *)
      style_text "${C_YELLOW}" "${state}"
      ;;
  esac
}

bool_badge() {
  case "${1}" in
    yes|enabled|true)
      style_text "${C_GREEN}" "enabled"
      ;;
    skipped)
      style_text "${C_YELLOW}" "skipped"
      ;;
    no|disabled|false)
      style_text "${C_YELLOW}" "disabled"
      ;;
    *)
      style_text "${C_YELLOW}" "${1:-unknown}"
      ;;
  esac
}

pretty_cert_mode() {
  case "${CERT_MODE:-unknown}" in
    self-signed)
      printf 'self-signed'
      ;;
    existing)
      printf 'existing'
      ;;
    cf-origin-ca)
      printf 'cloudflare-origin-ca'
      ;;
    acme-dns-cf)
      printf 'acme-dns-cf'
      ;;
    *)
      printf '%s' "${CERT_MODE:-unknown}"
      ;;
  esac
}

xray_version_line() {
  if [[ -x "${XRAY_BIN}" ]]; then
    "${XRAY_BIN}" version 2>/dev/null | head -n 1 || true
  fi
}

load_dashboard_context() {
  load_existing_state

  if [[ ! -f "${XRAY_CONFIG_FILE}" ]]; then
    return
  fi

  REALITY_UUID="${REALITY_UUID:-$(config_jq_read '.inbounds[] | select(.tag=="reality-vision") | .settings.clients[0].id')}"
  REALITY_SNI="${REALITY_SNI:-$(config_jq_read '.inbounds[] | select(.tag=="reality-vision") | .streamSettings.realitySettings.serverNames[0]')}"
  REALITY_TARGET="${REALITY_TARGET:-$(config_jq_read '.inbounds[] | select(.tag=="reality-vision") | .streamSettings.realitySettings.target')}"
  REALITY_SHORT_ID="${REALITY_SHORT_ID:-$(config_jq_read '.inbounds[] | select(.tag=="reality-vision") | .streamSettings.realitySettings.shortIds[0]')}"
  XHTTP_UUID="${XHTTP_UUID:-$(config_jq_read '.inbounds[] | select(.tag=="xhttp-cdn") | .settings.clients[0].id')}"
  XHTTP_PATH="${XHTTP_PATH:-$(config_jq_read '.inbounds[] | select(.tag=="xhttp-cdn") | .streamSettings.xhttpSettings.path')}"
  XHTTP_DOMAIN="${XHTTP_DOMAIN:-$(haproxy_sni_for_backend 'be_xhttp_cdn')}"
  SERVER_IP="${SERVER_IP:-$(output_field_value 'Address')}"
  REALITY_PUBLIC_KEY="${REALITY_PUBLIC_KEY:-$(output_field_value 'Public key')}"
  FINGERPRINT="${FINGERPRINT:-$(output_field_value 'Fingerprint')}"
  ENABLE_WARP="${ENABLE_WARP:-$(if config_jq_read '.outbounds[] | select(.tag=="WARP") | .tag' | grep -q 'WARP'; then printf 'yes'; else printf 'no'; fi)}"
  WARP_PROXY_PORT="${WARP_PROXY_PORT:-$(config_jq_read '.outbounds[] | select(.tag=="WARP") | .settings.servers[0].port')}"
  CERT_MODE="${CERT_MODE:-existing}"
  ENABLE_NET_OPT="${ENABLE_NET_OPT:-$(if [[ -f "${NET_SERVICE_FILE}" || -f "${NET_SYSCTL_CONF}" ]]; then printf 'yes'; else printf 'no'; fi)}"
  ACME_CA="${ACME_CA:-${DEFAULT_ACME_CA}}"
  SERVER_IP="${SERVER_IP:-$(guess_server_ip)}"
  FINGERPRINT="${FINGERPRINT:-${DEFAULT_FINGERPRINT}}"
  WARP_PROXY_PORT="${WARP_PROXY_PORT:-${DEFAULT_WARP_PROXY_PORT}}"
}

show_dashboard() {
  local xray_state=""
  local haproxy_state=""
  local warp_state=""
  local net_state=""
  local xray_enabled=""
  local haproxy_enabled=""
  local warp_enabled=""
  local net_enabled=""
  local version_line=""

  load_dashboard_context

  xray_state="$(service_active_state 'xray.service')"
  haproxy_state="$(service_active_state 'haproxy.service')"
  warp_state="$(service_active_state 'warp-svc.service')"
  net_state="$(service_active_state "${NET_SERVICE_NAME}")"
  xray_enabled="$(service_enable_state 'xray.service')"
  haproxy_enabled="$(service_enable_state 'haproxy.service')"
  warp_enabled="$(service_enable_state 'warp-svc.service')"
  net_enabled="$(service_enable_state "${NET_SERVICE_NAME}")"
  version_line="$(xray_version_line)"

  divider
  printf '%b%s%b\n' "${C_BOLD}${C_CYAN}" "Xray WARP Team Panel" "${C_RESET}"
  divider
  panel_row "Script version" "${SCRIPT_VERSION}"
  panel_row "Updated at" "$(date '+%Y-%m-%d %H:%M:%S %Z')"

  if [[ -f "${XRAY_CONFIG_FILE}" ]]; then
    panel_row "Install status" "$(style_text "${C_GREEN}" "managed")"
    [[ -n "${version_line}" ]] && panel_row "Xray core" "${version_line}"
    panel_row "Cert mode" "$(pretty_cert_mode)"
    panel_row "REALITY" "${SERVER_IP:-unknown}:443  sni=${REALITY_SNI:-unknown}"
    panel_row "XHTTP CDN" "${XHTTP_DOMAIN:-unknown}:443  path=${XHTTP_PATH:-unknown}"
    panel_row "REALITY UUID" "$(short_value "${REALITY_UUID:-unknown}")"
    panel_row "XHTTP UUID" "$(short_value "${XHTTP_UUID:-unknown}")"
    panel_row "REALITY key" "$(short_value "${REALITY_PUBLIC_KEY:-unknown}" 10 8)"
    panel_row "Links file" "${OUTPUT_FILE}"
  else
    panel_row "Install status" "$(style_text "${C_YELLOW}" "not-installed")"
  fi

  divider
  printf '%b%s%b\n' "${C_BOLD}" "Services" "${C_RESET}"
  panel_row "xray" "$(service_badge "${xray_state}") (${xray_enabled})"
  panel_row "haproxy" "$(service_badge "${haproxy_state}") (${haproxy_enabled})"
  panel_row "warp-svc" "$(service_badge "${warp_state}") (${warp_enabled})"
  panel_row "net-opt" "$(service_badge "${net_state}") (${net_enabled})"

  divider
  printf '%b%s%b\n' "${C_BOLD}" "Features" "${C_RESET}"
  panel_row "WARP route" "$(bool_badge "${ENABLE_WARP:-no}")  port=${WARP_PROXY_PORT:-${DEFAULT_WARP_PROXY_PORT}}"
  panel_row "Net tuning" "$(bool_badge "${ENABLE_NET_OPT:-no}")"
  panel_row "XHTTP ECH" "$(bool_badge "yes")  doh=${XHTTP_ECH_CONFIG_LIST:-${DEFAULT_XHTTP_ECH_CONFIG_LIST}}"
  if [[ "${CERT_MODE:-}" == "acme-dns-cf" ]]; then
    panel_row "ACME CA" "${ACME_CA:-${DEFAULT_ACME_CA}}"
  fi
  divider
}

ensure_debian_family() {
  if [[ ! -f /etc/os-release ]]; then
    die "Unsupported system: /etc/os-release not found."
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  case "${ID:-}" in
    debian|ubuntu)
      return
      ;;
  esac

  if [[ "${ID_LIKE:-}" == *debian* ]]; then
    return
  fi

  die "This installer currently supports Debian and Ubuntu only."
}

detect_xray_arch() {
  case "$(uname -m)" in
    x86_64|amd64)
      printf '64'
      ;;
    aarch64|arm64)
      printf 'arm64-v8a'
      ;;
    *)
      die "Unsupported CPU architecture: $(uname -m)"
      ;;
  esac
}

backup_path() {
  local path="${1}"
  local target=""

  if [[ ! -e "${path}" ]]; then
    return
  fi

  target="${BACKUP_DIR}${path}"
  mkdir -p "$(dirname "${target}")"
  cp -a "${path}" "${target}"
}

start_backup_session() {
  BACKUP_DIR="${BACKUP_ROOT}/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "${BACKUP_DIR}"
}

config_fallback_string_in_tag() {
  local tag="${1}"
  local key="${2}"

  awk -v tag="${tag}" -v key="${key}" '
    index($0, "\"tag\": \"" tag "\"") {inside=1}
    inside && $0 ~ /"tag":/ && index($0, "\"tag\": \"" tag "\"") == 0 {exit}
    inside && index($0, "\"" key "\"") {
      line=$0
      if (line ~ /:[[:space:]]*"/) {
        sub(/.*:[[:space:]]*"/, "", line)
        sub(/".*/, "", line)
        print line
        exit
      }
      if (line ~ /:[[:space:]]*[0-9]+/) {
        sub(/.*:[[:space:]]*/, "", line)
        sub(/,.*/, "", line)
        print line
        exit
      }
    }
  ' "${XRAY_CONFIG_FILE}" 2>/dev/null || true
}

config_fallback_first_array_value_in_tag() {
  local tag="${1}"
  local key="${2}"

  awk -v tag="${tag}" -v key="${key}" '
    index($0, "\"tag\": \"" tag "\"") {inside=1}
    inside && $0 ~ /"tag":/ && index($0, "\"tag\": \"" tag "\"") == 0 {exit}
    inside && index($0, "\"" key "\"") {want=1; next}
    want {
      line=$0
      if (line ~ /"/) {
        sub(/^[^"]*"/, "", line)
        sub(/".*/, "", line)
        print line
        exit
      }
      if ($0 ~ /\]/) {
        exit
      }
    }
  ' "${XRAY_CONFIG_FILE}" 2>/dev/null || true
}

config_fallback_has_outbound_tag() {
  local tag="${1}"

  grep -q "\"tag\": \"${tag}\"" "${XRAY_CONFIG_FILE}" 2>/dev/null
}

config_fallback_outbound_port() {
  local tag="${1}"

  awk -v tag="${tag}" '
    index($0, "\"tag\": \"" tag "\"") {inside=1}
    inside && $0 ~ /"tag":/ && index($0, "\"tag\": \"" tag "\"") == 0 {exit}
    inside && index($0, "\"port\"") {
      line=$0
      if (line ~ /:[[:space:]]*[0-9]+/) {
        sub(/.*:[[:space:]]*/, "", line)
        sub(/,.*/, "", line)
        print line
        exit
      }
    }
  ' "${XRAY_CONFIG_FILE}" 2>/dev/null || true
}

config_jq_read() {
  local filter="${1}"

  [[ -f "${XRAY_CONFIG_FILE}" ]] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r "${filter} // empty" "${XRAY_CONFIG_FILE}" 2>/dev/null || true
    return
  fi

  case "${filter}" in
    '.inbounds[] | select(.tag=="reality-vision") | .settings.clients[0].id')
      config_fallback_string_in_tag "reality-vision" "id"
      ;;
    '.inbounds[] | select(.tag=="reality-vision") | .streamSettings.realitySettings.serverNames[0]')
      config_fallback_first_array_value_in_tag "reality-vision" "serverNames"
      ;;
    '.inbounds[] | select(.tag=="reality-vision") | .streamSettings.realitySettings.target')
      config_fallback_string_in_tag "reality-vision" "target"
      ;;
    '.inbounds[] | select(.tag=="reality-vision") | .streamSettings.realitySettings.shortIds[0]')
      config_fallback_first_array_value_in_tag "reality-vision" "shortIds"
      ;;
    '.inbounds[] | select(.tag=="reality-vision") | .streamSettings.realitySettings.privateKey')
      config_fallback_string_in_tag "reality-vision" "privateKey"
      ;;
    '.inbounds[] | select(.tag=="xhttp-cdn") | .settings.clients[0].id')
      config_fallback_string_in_tag "xhttp-cdn" "id"
      ;;
    '.inbounds[] | select(.tag=="xhttp-cdn") | .streamSettings.xhttpSettings.path')
      config_fallback_string_in_tag "xhttp-cdn" "path"
      ;;
    '.inbounds[] | select(.tag=="xhttp-cdn") | .streamSettings.tlsSettings.alpn[0]')
      config_fallback_first_array_value_in_tag "xhttp-cdn" "alpn"
      ;;
    '.outbounds[] | select(.tag=="WARP") | .tag')
      if config_fallback_has_outbound_tag "WARP"; then
        printf 'WARP'
      fi
      ;;
    '.outbounds[] | select(.tag=="WARP") | .settings.servers[0].port')
      config_fallback_outbound_port "WARP"
      ;;
  esac
}

output_field_value() {
  local field_name="${1}"

  [[ -f "${OUTPUT_FILE}" ]] || return 0
  sed -n "s/^- ${field_name}: //p" "${OUTPUT_FILE}" | head -n 1
}

haproxy_sni_for_backend() {
  local backend_name="${1}"

  [[ -f "${HAPROXY_CONFIG}" ]] || return 0
  sed -n "s/.*use_backend ${backend_name} if { req\\.ssl_sni -i \\([^ }][^ }]*\\) }.*/\\1/p" "${HAPROXY_CONFIG}" | head -n 1
}

load_existing_state() {
  if [[ -f "${STATE_FILE}" ]]; then
    # shellcheck disable=SC1090
    . "${STATE_FILE}"
  fi
}

load_current_install_context() {
  load_existing_state

  [[ -f "${XRAY_CONFIG_FILE}" ]] || die "Current Xray config not found: ${XRAY_CONFIG_FILE}"

  REALITY_UUID="${REALITY_UUID:-$(config_jq_read '.inbounds[] | select(.tag=="reality-vision") | .settings.clients[0].id')}"
  REALITY_SNI="${REALITY_SNI:-$(config_jq_read '.inbounds[] | select(.tag=="reality-vision") | .streamSettings.realitySettings.serverNames[0]')}"
  REALITY_TARGET="${REALITY_TARGET:-$(config_jq_read '.inbounds[] | select(.tag=="reality-vision") | .streamSettings.realitySettings.target')}"
  REALITY_SHORT_ID="${REALITY_SHORT_ID:-$(config_jq_read '.inbounds[] | select(.tag=="reality-vision") | .streamSettings.realitySettings.shortIds[0]')}"
  REALITY_PRIVATE_KEY="${REALITY_PRIVATE_KEY:-$(config_jq_read '.inbounds[] | select(.tag=="reality-vision") | .streamSettings.realitySettings.privateKey')}"
  XHTTP_UUID="${XHTTP_UUID:-$(config_jq_read '.inbounds[] | select(.tag=="xhttp-cdn") | .settings.clients[0].id')}"
  XHTTP_PATH="${XHTTP_PATH:-$(config_jq_read '.inbounds[] | select(.tag=="xhttp-cdn") | .streamSettings.xhttpSettings.path')}"
  TLS_ALPN="${TLS_ALPN:-$(config_jq_read '.inbounds[] | select(.tag=="xhttp-cdn") | .streamSettings.tlsSettings.alpn[0]')}"
  XHTTP_DOMAIN="${XHTTP_DOMAIN:-$(haproxy_sni_for_backend 'be_xhttp_cdn')}"
  ENABLE_WARP="${ENABLE_WARP:-$(if config_jq_read '.outbounds[] | select(.tag=="WARP") | .tag' | grep -q 'WARP'; then printf 'yes'; else printf 'no'; fi)}"
  WARP_PROXY_PORT="${WARP_PROXY_PORT:-$(config_jq_read '.outbounds[] | select(.tag=="WARP") | .settings.servers[0].port')}"
  SERVER_IP="${SERVER_IP:-$(output_field_value 'Address')}"
  REALITY_PUBLIC_KEY="${REALITY_PUBLIC_KEY:-$(output_field_value 'Public key')}"
  FINGERPRINT="${FINGERPRINT:-$(output_field_value 'Fingerprint')}"
  SERVER_IP="${SERVER_IP:-$(guess_server_ip)}"
  FINGERPRINT="${FINGERPRINT:-${DEFAULT_FINGERPRINT}}"
  CERT_MODE="${CERT_MODE:-existing}"
  ACME_CA="${ACME_CA:-${DEFAULT_ACME_CA}}"
  XHTTP_ECH_CONFIG_LIST="${XHTTP_ECH_CONFIG_LIST:-${DEFAULT_XHTTP_ECH_CONFIG_LIST}}"
  XHTTP_ECH_FORCE_QUERY="${XHTTP_ECH_FORCE_QUERY:-${DEFAULT_XHTTP_ECH_FORCE_QUERY}}"
  ENABLE_NET_OPT="${ENABLE_NET_OPT:-$(if [[ -f "${NET_SERVICE_FILE}" || -f "${NET_SYSCTL_CONF}" ]]; then printf 'yes'; else printf 'no'; fi)}"
  WARP_PROXY_PORT="${WARP_PROXY_PORT:-${DEFAULT_WARP_PROXY_PORT}}"

  [[ -n "${REALITY_UUID}" ]] || die "Could not determine REALITY UUID from current install."
  [[ -n "${REALITY_SNI}" ]] || die "Could not determine REALITY SNI from current install."
  [[ -n "${REALITY_TARGET}" ]] || die "Could not determine REALITY target from current install."
  [[ -n "${REALITY_SHORT_ID}" ]] || die "Could not determine REALITY short ID from current install."
  [[ -n "${REALITY_PRIVATE_KEY}" ]] || die "Could not determine REALITY private key from current install."
  [[ -n "${XHTTP_UUID}" ]] || die "Could not determine XHTTP UUID from current install."
  [[ -n "${XHTTP_DOMAIN}" ]] || die "Could not determine XHTTP domain from current install."
  [[ -n "${XHTTP_PATH}" ]] || die "Could not determine XHTTP path from current install."
}

install_packages() {
  log "Installing required packages."
  apt-get update
  apt-get install -y ca-certificates curl gnupg haproxy iproute2 jq kmod openssl unzip uuid-runtime
}

install_xray() {
  local arch=""
  local tmp_dir=""
  local download_url=""

  arch="$(detect_xray_arch)"
  download_url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${arch}.zip"
  tmp_dir="$(mktemp -d)"

  log "Downloading Xray-core."
  curl -fsSL "${download_url}" -o "${tmp_dir}/xray.zip"
  unzip -qo "${tmp_dir}/xray.zip" -d "${tmp_dir}/xray"

  mkdir -p /usr/local/bin "${XRAY_CONFIG_DIR}" "${XRAY_ASSET_DIR}" /var/log/xray
  install -m 0755 "${tmp_dir}/xray/xray" "${XRAY_BIN}"

  if [[ -f "${tmp_dir}/xray/geoip.dat" ]]; then
    install -m 0644 "${tmp_dir}/xray/geoip.dat" "${XRAY_ASSET_DIR}/geoip.dat"
  fi

  if [[ -f "${tmp_dir}/xray/geosite.dat" ]]; then
    install -m 0644 "${tmp_dir}/xray/geosite.dat" "${XRAY_ASSET_DIR}/geosite.dat"
  fi

  rm -rf "${tmp_dir}"
}

ensure_xray_user() {
  if ! id -u xray >/dev/null 2>&1; then
    useradd --system --home /var/lib/xray --create-home --shell /usr/sbin/nologin xray
  fi

  mkdir -p /var/log/xray "${XRAY_CONFIG_DIR}" "${XRAY_ASSET_DIR}" "${SSL_DIR}"
  chown -R xray:xray /var/log/xray
  chmod 750 /var/log/xray
}

generate_reality_keys_if_needed() {
  local key_output=""

  if [[ -n "${REALITY_PRIVATE_KEY}" && -n "${REALITY_PUBLIC_KEY}" ]]; then
    return
  fi

  if [[ -n "${REALITY_PRIVATE_KEY}" && -z "${REALITY_PUBLIC_KEY}" ]]; then
    key_output="$("${XRAY_BIN}" x25519 -i "${REALITY_PRIVATE_KEY}")"
    REALITY_PUBLIC_KEY="$(printf '%s\n' "${key_output}" | awk -F': ' '/Password \(PublicKey\)|Public key/ {print $2; exit}')"
    [[ -n "${REALITY_PUBLIC_KEY}" ]] || die "Failed to derive REALITY public key from the provided private key."
    return
  fi

  key_output="$("${XRAY_BIN}" x25519)"
  REALITY_PRIVATE_KEY="$(printf '%s\n' "${key_output}" | awk -F': ' '/Private key/ {print $2}')"
  REALITY_PUBLIC_KEY="$(printf '%s\n' "${key_output}" | awk -F': ' '/Public key/ {print $2}')"

  [[ -n "${REALITY_PRIVATE_KEY}" ]] || die "Failed to generate REALITY private key."
  [[ -n "${REALITY_PUBLIC_KEY}" ]] || die "Failed to generate REALITY public key."
}

prepare_install_inputs() {
  local guessed_ip=""

  guessed_ip="$(guess_server_ip)"

  prompt_with_default SERVER_IP "REALITY direct node address or IP" "${guessed_ip}"
  prompt_with_default REALITY_UUID "REALITY UUID" "$(random_uuid)"
  prompt_with_default REALITY_SNI "REALITY visible SNI" "${DEFAULT_REALITY_SNI}"
  prompt_with_default REALITY_TARGET "REALITY target host:port" "${REALITY_SNI}:443"
  prompt_with_default REALITY_SHORT_ID "REALITY short ID" "$(random_hex 8)"
  prompt_with_default XHTTP_UUID "XHTTP UUID" "$(random_uuid)"
  prompt_with_default XHTTP_DOMAIN "XHTTP CDN domain" ""
  prompt_with_default XHTTP_PATH "XHTTP path" "$(random_path)"
  prompt_with_default CERT_MODE "TLS certificate mode (self-signed/existing/cf-origin-ca/acme-dns-cf)" "self-signed"

  case "${CERT_MODE}" in
    self-signed|existing|cf-origin-ca|acme-dns-cf)
      ;;
    *)
      die "Unsupported cert mode: ${CERT_MODE}. Use self-signed, existing, cf-origin-ca, or acme-dns-cf."
      ;;
  esac

  if [[ "${CERT_MODE}" == "existing" ]]; then
    prompt_with_default CERT_SOURCE_FILE "Existing certificate file path" ""
    prompt_with_default KEY_SOURCE_FILE "Existing key file path" ""
  fi

  if [[ "${CERT_MODE}" == "cf-origin-ca" ]]; then
    prompt_with_default CF_ZONE_ID "Cloudflare zone ID" ""
    prompt_with_default CF_CERT_VALIDITY "Cloudflare Origin CA validity days" "${DEFAULT_CF_CERT_VALIDITY}"
    prompt_secret CF_API_TOKEN "Cloudflare API token"
  fi

  if [[ "${CERT_MODE}" == "acme-dns-cf" ]]; then
    prompt_with_default ACME_EMAIL "acme.sh account email" ""
    prompt_with_default ACME_CA "ACME CA" "${DEFAULT_ACME_CA}"
    prompt_secret CF_DNS_TOKEN "Cloudflare DNS API token"
    if [[ -z "${CF_DNS_ACCOUNT_ID}" && "${NON_INTERACTIVE}" -eq 0 ]]; then
      read -r -p "Cloudflare account ID (optional): " CF_DNS_ACCOUNT_ID
    fi
    if [[ -z "${CF_DNS_ZONE_ID}" && "${NON_INTERACTIVE}" -eq 0 ]]; then
      read -r -p "Cloudflare zone ID for DNS API (optional): " CF_DNS_ZONE_ID
    fi
  fi

  prompt_yes_no ENABLE_NET_OPT "Enable network optimization? [y/n]" "y"
  ENABLE_NET_OPT="$(printf '%s' "${ENABLE_NET_OPT}" | tr 'A-Z' 'a-z')"

  case "${ENABLE_NET_OPT}" in
    y|yes)
      ENABLE_NET_OPT="yes"
      ;;
    n|no)
      ENABLE_NET_OPT="no"
      ;;
    *)
      die "ENABLE_NET_OPT must be yes or no."
      ;;
  esac

  prompt_yes_no ENABLE_WARP "Enable selective WARP outbound? [y/n]" "y"
  ENABLE_WARP="$(printf '%s' "${ENABLE_WARP}" | tr 'A-Z' 'a-z')"

  case "${ENABLE_WARP}" in
    y|yes)
      ENABLE_WARP="yes"
      prompt_with_default WARP_TEAM_NAME "Cloudflare Zero Trust team name" ""
      prompt_with_default WARP_CLIENT_ID "Cloudflare service token client ID" ""
      prompt_secret WARP_CLIENT_SECRET "Cloudflare service token client secret"
      prompt_with_default WARP_PROXY_PORT "Local WARP SOCKS5 port" "${DEFAULT_WARP_PROXY_PORT}"
      ;;
    n|no)
      ENABLE_WARP="no"
      ;;
    *)
      die "ENABLE_WARP must be yes or no."
      ;;
  esac
}

default_reality_target_for_sni() {
  local sni="${1}"
  printf '%s:443' "${sni}"
}

ensure_xhttp_path_format() {
  [[ -n "${XHTTP_PATH}" ]] || die "XHTTP path cannot be empty."
  [[ "${XHTTP_PATH}" == /* ]] || die "XHTTP path must start with '/'."
}

prompt_cert_mode_inputs() {
  case "${CERT_MODE}" in
    self-signed)
      CERT_SOURCE_FILE=""
      KEY_SOURCE_FILE=""
      CF_ZONE_ID=""
      CF_CERT_VALIDITY="${DEFAULT_CF_CERT_VALIDITY}"
      ACME_EMAIL=""
      ACME_CA="${DEFAULT_ACME_CA}"
      CF_DNS_ACCOUNT_ID=""
      CF_DNS_ZONE_ID=""
      ;;
    existing)
      prompt_with_default CERT_SOURCE_FILE "Existing certificate file path" "${CERT_SOURCE_FILE:-}"
      prompt_with_default KEY_SOURCE_FILE "Existing key file path" "${KEY_SOURCE_FILE:-}"
      CF_ZONE_ID=""
      CF_CERT_VALIDITY="${DEFAULT_CF_CERT_VALIDITY}"
      ACME_EMAIL=""
      ACME_CA="${DEFAULT_ACME_CA}"
      CF_DNS_ACCOUNT_ID=""
      CF_DNS_ZONE_ID=""
      ;;
    cf-origin-ca)
      CERT_SOURCE_FILE=""
      KEY_SOURCE_FILE=""
      prompt_with_default CF_ZONE_ID "Cloudflare zone ID" "${CF_ZONE_ID:-}"
      prompt_with_default CF_CERT_VALIDITY "Cloudflare Origin CA validity days" "${CF_CERT_VALIDITY:-${DEFAULT_CF_CERT_VALIDITY}}"
      prompt_secret CF_API_TOKEN "Cloudflare API token"
      ACME_EMAIL=""
      ACME_CA="${DEFAULT_ACME_CA}"
      CF_DNS_ACCOUNT_ID=""
      CF_DNS_ZONE_ID=""
      ;;
    acme-dns-cf)
      CERT_SOURCE_FILE=""
      KEY_SOURCE_FILE=""
      prompt_with_default ACME_EMAIL "acme.sh account email" "${ACME_EMAIL:-}"
      prompt_with_default ACME_CA "ACME CA" "${ACME_CA:-${DEFAULT_ACME_CA}}"
      prompt_secret CF_DNS_TOKEN "Cloudflare DNS API token"
      if [[ -z "${CF_DNS_ACCOUNT_ID}" && "${NON_INTERACTIVE}" -eq 0 ]]; then
        read -r -p "Cloudflare account ID (optional): " CF_DNS_ACCOUNT_ID
      fi
      if [[ -z "${CF_DNS_ZONE_ID}" && "${NON_INTERACTIVE}" -eq 0 ]]; then
        read -r -p "Cloudflare zone ID for DNS API (optional): " CF_DNS_ZONE_ID
      fi
      CF_ZONE_ID=""
      CF_CERT_VALIDITY="${DEFAULT_CF_CERT_VALIDITY}"
      ;;
    *)
      die "Unsupported cert mode: ${CERT_MODE}"
      ;;
  esac
}

write_cf_origin_csr() {
  local csr_file="${1}"
  local openssl_cfg=""

  openssl_cfg="$(mktemp)"
  cat > "${openssl_cfg}" <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = ${XHTTP_DOMAIN}

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${XHTTP_DOMAIN}
EOF

  openssl req -new -sha256 \
    -key "${TLS_KEY_FILE}" \
    -out "${csr_file}" \
    -config "${openssl_cfg}" >/dev/null 2>&1

  rm -f "${openssl_cfg}"
}

request_cf_origin_ca_cert() {
  local csr_file=""
  local csr_json=""
  local response=""
  local cert_body=""
  local error_text=""

  [[ -n "${CF_ZONE_ID}" ]] || die "CF_ZONE_ID is required for cf-origin-ca mode."
  [[ -n "${CF_API_TOKEN}" ]] || die "CF_API_TOKEN is required for cf-origin-ca mode."

  csr_file="$(mktemp)"
  openssl ecparam -name prime256v1 -genkey -noout -out "${TLS_KEY_FILE}"
  chmod 0640 "${TLS_KEY_FILE}"
  write_cf_origin_csr "${csr_file}"
  csr_json="$(jq -Rs . < "${csr_file}")"

  response="$(curl -fsSL https://api.cloudflare.com/client/v4/certificates \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    --data "{\"csr\":${csr_json},\"hostnames\":[\"${XHTTP_DOMAIN}\"],\"request_type\":\"origin-ecc\",\"requested_validity\":${CF_CERT_VALIDITY}}" \
  )" || die "Failed to call Cloudflare Origin CA API."

  cert_body="$(printf '%s' "${response}" | jq -r '.result.certificate // empty')"
  if [[ -z "${cert_body}" ]]; then
    error_text="$(printf '%s' "${response}" | jq -r '.errors[0].message // .messages[0].message // "unknown Cloudflare API error"')"
    die "Cloudflare Origin CA API returned no certificate: ${error_text}"
  fi

  printf '%b\n' "${cert_body}" > "${TLS_CERT_FILE}"
  chmod 0640 "${TLS_CERT_FILE}"
  rm -f "${csr_file}"
}

set_cloudflare_ssl_mode_strict() {
  local response=""
  local success=""

  [[ -n "${CF_ZONE_ID}" ]] || return
  [[ -n "${CF_API_TOKEN}" ]] || return

  response="$(curl -fsSL -X PATCH "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/settings/ssl" \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    --data '{"value":"strict"}' 2>/dev/null || true)"

  success="$(printf '%s' "${response}" | jq -r '.success // empty' 2>/dev/null || true)"
  if [[ "${success}" != "true" ]]; then
    warn "Could not automatically set Cloudflare SSL/TLS mode to strict. Check the zone setting manually."
  fi
}

write_acme_reload_helper() {
  local tmp_file=""

  tmp_file="$(mktemp)"
  cat > "${tmp_file}" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -f "${TLS_CERT_FILE}" && -f "${TLS_KEY_FILE}" ]]; then
  chown root:xray "${TLS_CERT_FILE}" "${TLS_KEY_FILE}" 2>/dev/null || true
  chmod 0640 "${TLS_CERT_FILE}" "${TLS_KEY_FILE}" 2>/dev/null || true
fi

systemctl restart xray >/dev/null 2>&1 || true
systemctl restart haproxy >/dev/null 2>&1 || true
EOF

  backup_path "${ACME_RELOAD_HELPER}"
  install -m 0755 "${tmp_file}" "${ACME_RELOAD_HELPER}"
  rm -f "${tmp_file}"
}

install_acme_sh() {
  local tmp_file=""

  if [[ -x "${ACME_SH_BIN}" ]]; then
    return
  fi

  [[ -n "${ACME_EMAIL}" ]] || die "ACME_EMAIL is required for acme-dns-cf mode."
  tmp_file="$(mktemp)"
  curl -fsSL https://get.acme.sh -o "${tmp_file}"
  sh "${tmp_file}" email="${ACME_EMAIL}" >/dev/null
  rm -f "${tmp_file}"
  [[ -x "${ACME_SH_BIN}" ]] || die "acme.sh installation failed."
}

issue_acme_cf_cert() {
  [[ -n "${ACME_EMAIL}" ]] || die "ACME_EMAIL is required for acme-dns-cf mode."
  [[ -n "${CF_DNS_TOKEN}" ]] || die "CF_DNS_TOKEN is required for acme-dns-cf mode."

  install_acme_sh
  write_acme_reload_helper

  unset CF_Account_ID CF_Zone_ID
  export CF_Token="${CF_DNS_TOKEN}"
  if [[ -n "${CF_DNS_ACCOUNT_ID}" ]]; then
    export CF_Account_ID="${CF_DNS_ACCOUNT_ID}"
  fi
  if [[ -n "${CF_DNS_ZONE_ID}" ]]; then
    export CF_Zone_ID="${CF_DNS_ZONE_ID}"
  fi

  "${ACME_SH_BIN}" --register-account -m "${ACME_EMAIL}" --server "${ACME_CA}" >/dev/null 2>&1 || true
  "${ACME_SH_BIN}" --issue --dns dns_cf -d "${XHTTP_DOMAIN}" --server "${ACME_CA}" --keylength ec-256
  "${ACME_SH_BIN}" --install-cert -d "${XHTTP_DOMAIN}" \
    --ecc \
    --key-file "${TLS_KEY_FILE}" \
    --fullchain-file "${TLS_CERT_FILE}" \
    --reloadcmd "${ACME_RELOAD_HELPER}"
}

write_tls_assets() {
  local tls_config=""

  mkdir -p "${SSL_DIR}"
  backup_path "${TLS_CERT_FILE}"
  backup_path "${TLS_KEY_FILE}"

  if [[ "${CERT_MODE}" == "existing" ]]; then
    [[ -f "${CERT_SOURCE_FILE}" ]] || die "Certificate file not found: ${CERT_SOURCE_FILE}"
    [[ -f "${KEY_SOURCE_FILE}" ]] || die "Key file not found: ${KEY_SOURCE_FILE}"

    install -m 0640 "${CERT_SOURCE_FILE}" "${TLS_CERT_FILE}"
    install -m 0640 "${KEY_SOURCE_FILE}" "${TLS_KEY_FILE}"
  elif [[ "${CERT_MODE}" == "cf-origin-ca" ]]; then
    request_cf_origin_ca_cert
  elif [[ "${CERT_MODE}" == "acme-dns-cf" ]]; then
    issue_acme_cf_cert
  else
    tls_config="$(mktemp)"
    cat > "${tls_config}" <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = ${XHTTP_DOMAIN}

[v3_req]
subjectAltName = @alt_names
extendedKeyUsage = serverAuth

[alt_names]
DNS.1 = ${XHTTP_DOMAIN}
EOF
    openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
      -keyout "${TLS_KEY_FILE}" \
      -out "${TLS_CERT_FILE}" \
      -config "${tls_config}" >/dev/null 2>&1
    rm -f "${tls_config}"
    chmod 0640 "${TLS_CERT_FILE}" "${TLS_KEY_FILE}"
  fi

  chown root:xray "${TLS_CERT_FILE}" "${TLS_KEY_FILE}"

  if [[ "${CERT_MODE}" == "cf-origin-ca" ]]; then
    set_cloudflare_ssl_mode_strict
  fi
}

available_cc() {
  if [[ -r /proc/sys/net/ipv4/tcp_available_congestion_control ]]; then
    cat /proc/sys/net/ipv4/tcp_available_congestion_control
  else
    sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true
  fi
}

supports_default_qdisc() {
  sysctl -a 2>/dev/null | grep -q '^net.core.default_qdisc ='
}

write_net_sysctl_conf() {
  local tmp_file=""

  tmp_file="$(mktemp)"
  {
    cat <<'EOF'
# Generated by xray-warp-team.sh
# Safe baseline for proxy workloads and long-lived TCP sessions.

EOF
    if supports_default_qdisc; then
      printf '%s\n' 'net.core.default_qdisc = fq'
    fi
    cat <<'EOF'
net.ipv4.tcp_congestion_control = bbr

net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.optmem_max = 1048576
net.core.somaxconn = 32768

net.ipv4.ip_local_port_range = 10240 65535
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 16384
net.ipv4.tcp_rmem = 4096 262144 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5

net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
EOF
  } > "${tmp_file}"

  backup_path "${NET_SYSCTL_CONF}"
  install -m 0644 "${tmp_file}" "${NET_SYSCTL_CONF}"
  rm -f "${tmp_file}"
}

write_net_helper_script() {
  local tmp_file=""

  tmp_file="$(mktemp)"
  cat > "${tmp_file}" <<'EOF'
#!/bin/sh
set -eu

iface="${1:-${IFACE:-$(ip -o -4 route show to default | awk '{print $5; exit}')}}"
[ -n "$iface" ] || exit 0
[ -d "/sys/class/net/$iface" ] || exit 0

cpus="$(nproc 2>/dev/null || echo 1)"
if [ "$cpus" -le 1 ]; then
    mask="1"
else
    mask="$(printf '%x' "$(( (1 << cpus) - 1 ))")"
fi

rx_queues="$(find "/sys/class/net/$iface/queues" -maxdepth 1 -type d -name 'rx-*' | wc -l)"
[ "$rx_queues" -ge 1 ] || rx_queues=1

global_entries=32768
per_queue=$((global_entries / rx_queues))
[ "$per_queue" -ge 4096 ] || per_queue=4096

modprobe sch_fq >/dev/null 2>&1 || true
tc qdisc replace dev "$iface" root fq >/dev/null 2>&1 || true

if [ -w /proc/sys/net/core/rps_sock_flow_entries ]; then
    printf '%s' "$global_entries" > /proc/sys/net/core/rps_sock_flow_entries
fi

for f in /sys/class/net/"$iface"/queues/rx-*/rps_cpus; do
    [ -w "$f" ] || continue
    printf '%s' "$mask" > "$f"
done

for f in /sys/class/net/"$iface"/queues/rx-*/rps_flow_cnt; do
    [ -w "$f" ] || continue
    printf '%s' "$per_queue" > "$f"
done

for f in /sys/class/net/"$iface"/queues/tx-*/xps_rxqs; do
    [ -w "$f" ] || continue
    printf '%s' 1 > "$f"
done
EOF

  backup_path "${NET_HELPER_PATH}"
  install -m 0755 "${tmp_file}" "${NET_HELPER_PATH}"
  rm -f "${tmp_file}"
}

write_net_service() {
  local tmp_file=""

  tmp_file="$(mktemp)"
  cat > "${tmp_file}" <<EOF
[Unit]
Description=Apply Xray WARP Team network optimizations
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${NET_HELPER_PATH}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  backup_path "${NET_SERVICE_FILE}"
  install -m 0644 "${tmp_file}" "${NET_SERVICE_FILE}"
  rm -f "${tmp_file}"
}

install_network_optimization() {
  local cc=""

  [[ "${ENABLE_NET_OPT}" == "yes" ]] || return

  cc="$(available_cc)"
  if ! printf ' %s ' "${cc}" | grep -q ' bbr '; then
    modprobe tcp_bbr >/dev/null 2>&1 || true
    modprobe sch_fq >/dev/null 2>&1 || true
    cc="$(available_cc)"
  fi

  if ! printf ' %s ' "${cc}" | grep -q ' bbr '; then
    warn "Kernel does not expose BBR support. Skipping network optimization."
    ENABLE_NET_OPT="skipped"
    return
  fi

  write_net_sysctl_conf
  write_net_helper_script
  write_net_service
  sysctl --system >/dev/null
  systemctl daemon-reload
  systemctl enable --now "${NET_SERVICE_NAME}" >/dev/null
}

write_xray_config() {
  backup_path "${XRAY_CONFIG_FILE}"

  if [[ "${ENABLE_WARP}" == "yes" ]]; then
    cat > "${XRAY_CONFIG_FILE}" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "tag": "reality-vision",
      "listen": "127.0.0.1",
      "port": 2443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${REALITY_UUID}",
            "flow": "xtls-rprx-vision",
            "email": "reality-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "target": "${REALITY_TARGET}",
          "serverNames": [
            "${REALITY_SNI}"
          ],
          "privateKey": "${REALITY_PRIVATE_KEY}",
          "shortIds": [
            "${REALITY_SHORT_ID}"
          ]
        }
      }
    },
    {
      "tag": "xhttp-cdn",
      "listen": "127.0.0.1",
      "port": 3443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${XHTTP_UUID}",
            "email": "xhttp-cdn"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "tls",
        "tlsSettings": {
          "minVersion": "1.2",
          "alpn": [
            "${TLS_ALPN}",
            "http/1.1"
          ],
          "rejectUnknownSni": true,
          "certificates": [
            {
              "certificateFile": "${TLS_CERT_FILE}",
              "keyFile": "${TLS_KEY_FILE}"
            }
          ]
        },
        "xhttpSettings": {
          "path": "${XHTTP_PATH}"
        }
      }
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "outboundTag": "direct",
        "domain": [
          "domain:telegram.org",
          "domain:api.telegram.org",
          "domain:t.me",
          "domain:telegram.me",
          "domain:core.telegram.org"
        ]
      },
      {
        "type": "field",
        "outboundTag": "WARP",
        "domain": [
          "geosite:google",
          "geosite:youtube",
          "geosite:openai",
          "geosite:netflix",
          "geosite:disney",
          "domain:gemini.google.com",
          "domain:claude.ai",
          "domain:anthropic.com",
          "domain:api.anthropic.com",
          "domain:console.anthropic.com",
          "domain:statsig.anthropic.com",
          "domain:sentry.io",
          "domain:x.com",
          "domain:twitter.com",
          "domain:t.co",
          "domain:twimg.com",
          "domain:github.com",
          "domain:api.github.com",
          "domain:githubcopilot.com",
          "domain:copilot-proxy.githubusercontent.com",
          "domain:origin-tracker.githubusercontent.com",
          "domain:copilot-telemetry.githubusercontent.com",
          "domain:collector.github.com",
          "domain:default.exp-tas.com"
        ]
      }
    ]
  },
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom"
    },
    {
      "tag": "WARP",
      "protocol": "socks",
      "settings": {
        "servers": [
          {
            "address": "127.0.0.1",
            "port": ${WARP_PROXY_PORT},
            "users": []
          }
        ]
      }
    },
    {
      "tag": "block",
      "protocol": "blackhole"
    }
  ]
}
EOF
  else
    cat > "${XRAY_CONFIG_FILE}" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "tag": "reality-vision",
      "listen": "127.0.0.1",
      "port": 2443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${REALITY_UUID}",
            "flow": "xtls-rprx-vision",
            "email": "reality-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "target": "${REALITY_TARGET}",
          "serverNames": [
            "${REALITY_SNI}"
          ],
          "privateKey": "${REALITY_PRIVATE_KEY}",
          "shortIds": [
            "${REALITY_SHORT_ID}"
          ]
        }
      }
    },
    {
      "tag": "xhttp-cdn",
      "listen": "127.0.0.1",
      "port": 3443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${XHTTP_UUID}",
            "email": "xhttp-cdn"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "tls",
        "tlsSettings": {
          "minVersion": "1.2",
          "alpn": [
            "${TLS_ALPN}",
            "http/1.1"
          ],
          "rejectUnknownSni": true,
          "certificates": [
            {
              "certificateFile": "${TLS_CERT_FILE}",
              "keyFile": "${TLS_KEY_FILE}"
            }
          ]
        },
        "xhttpSettings": {
          "path": "${XHTTP_PATH}"
        }
      }
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": []
  },
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom"
    },
    {
      "tag": "block",
      "protocol": "blackhole"
    }
  ]
}
EOF
  fi

  chown root:xray "${XRAY_CONFIG_FILE}"
  chmod 0640 "${XRAY_CONFIG_FILE}"
}

write_haproxy_config() {
  backup_path "${HAPROXY_CONFIG}"

  cat > "${HAPROXY_CONFIG}" <<EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon
    user haproxy
    group haproxy
    maxconn 20000

defaults
    log global
    mode tcp
    option tcplog
    timeout connect 5s
    timeout client 2m
    timeout server 2m

frontend fe_tls_shared_443
    bind :443
    mode tcp
    tcp-request inspect-delay 5s
    tcp-request content accept if { req.ssl_hello_type 1 }

    use_backend be_xhttp_cdn if { req.ssl_sni -i ${XHTTP_DOMAIN} }
    use_backend be_reality_vision if { req.ssl_sni -i ${REALITY_SNI} }
    default_backend be_reject

backend be_xhttp_cdn
    mode tcp
    server xhttp_cdn 127.0.0.1:3443 check

backend be_reality_vision
    mode tcp
    server reality_vision 127.0.0.1:2443 check

backend be_reject
    mode tcp
    server blackhole 127.0.0.1:9
EOF
}

write_xray_service() {
  backup_path "${XRAY_SERVICE_FILE}"

  cat > "${XRAY_SERVICE_FILE}" <<EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=xray
Group=xray
Environment=XRAY_LOCATION_ASSET=${XRAY_ASSET_DIR}
ExecStart=${XRAY_BIN} run -config ${XRAY_CONFIG_FILE}
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
}

install_warp() {
  local repo_codename=""
  local key_tmp=""

  [[ "${ENABLE_WARP}" == "yes" ]] || return

  # shellcheck disable=SC1091
  . /etc/os-release
  repo_codename="${VERSION_CODENAME:-}"
  [[ -n "${repo_codename}" ]] || die "VERSION_CODENAME is empty, cannot install Cloudflare WARP."

  key_tmp="$(mktemp)"
  log "Installing Cloudflare WARP client."
  curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg -o "${key_tmp}"
  gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg "${key_tmp}"
  rm -f "${key_tmp}"

  cat > /etc/apt/sources.list.d/cloudflare-client.list <<EOF
deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ ${repo_codename} main
EOF

  apt-get update
  apt-get install -y cloudflare-warp

  mkdir -p /var/lib/cloudflare-warp
  backup_path "${WARP_MDM_FILE}"
  cat > "${WARP_MDM_FILE}" <<EOF
<dict>
    <key>auth_client_id</key>
    <string>${WARP_CLIENT_ID}</string>
    <key>auth_client_secret</key>
    <string>${WARP_CLIENT_SECRET}</string>
    <key>organization</key>
    <string>${WARP_TEAM_NAME}</string>
    <key>auto_connect</key>
    <integer>1</integer>
    <key>onboarding</key>
    <false/>
    <key>service_mode</key>
    <string>proxy</string>
    <key>proxy_port</key>
    <integer>${WARP_PROXY_PORT}</integer>
    <key>warp_tunnel_protocol</key>
    <string>masque</string>
</dict>
EOF

  chmod 0600 "${WARP_MDM_FILE}"
  systemctl enable --now warp-svc
  warp-cli --accept-tos mdm refresh || true
  systemctl restart warp-svc
}

service_exists() {
  local unit_name="${1}"
  local path=""

  for path in /etc/systemd/system/"${unit_name}" /lib/systemd/system/"${unit_name}" /usr/lib/systemd/system/"${unit_name}"; do
    if [[ -f "${path}" || -L "${path}" ]]; then
      return 0
    fi
  done

  return 1
}

stop_and_disable_service_if_present() {
  local unit_name="${1}"

  if service_exists "${unit_name}"; then
    systemctl disable --now "${unit_name}" >/dev/null 2>&1 || systemctl stop "${unit_name}" >/dev/null 2>&1 || true
  fi
}

remove_managed_paths() {
  local path=""

  for path in "$@"; do
    if [[ -e "${path}" || -L "${path}" ]]; then
      backup_path "${path}"
      rm -rf "${path}"
    fi
  done
}

validate_configs() {
  log "Validating Xray config."
  "${XRAY_BIN}" run -test -config "${XRAY_CONFIG_FILE}"

  log "Validating HAProxy config."
  haproxy -c -f "${HAPROXY_CONFIG}"
}

restart_services() {
  systemctl daemon-reload
  systemctl enable --now xray
  systemctl enable --now haproxy
  systemctl restart xray
  systemctl restart haproxy

  if [[ "${ENABLE_WARP}" == "yes" ]]; then
    systemctl enable --now warp-svc
  fi
}

restart_core_services() {
  systemctl restart xray
  systemctl restart haproxy
}

install_self_command() {
  local source_path="${BASH_SOURCE[0]:-$0}"

  if [[ -f "${source_path}" ]]; then
    install -m 0755 "${source_path}" "${SELF_COMMAND_PATH}"
  else
    warn "Could not persist the management command because the script path is unavailable."
  fi
}

cleanup_previous_acme_cert() {
  local old_cert_mode="${1:-}"
  local old_xhttp_domain="${2:-}"

  if [[ "${old_cert_mode}" == "acme-dns-cf" && -x "${ACME_SH_BIN}" && -n "${old_xhttp_domain}" ]]; then
    if [[ "${CERT_MODE}" != "acme-dns-cf" || "${XHTTP_DOMAIN}" != "${old_xhttp_domain}" ]]; then
      "${ACME_SH_BIN}" --remove -d "${old_xhttp_domain}" --ecc >/dev/null 2>&1 || true
    fi
  fi
}

apply_managed_update() {
  write_tls_assets
  write_xray_config
  write_haproxy_config
  validate_configs
  restart_core_services
  write_state_file
  write_output_file
}

apply_managed_runtime_update() {
  write_xray_config
  write_haproxy_config
  validate_configs
  restart_core_services
  write_state_file
  write_output_file
}

upgrade_cmd() {
  local current_version=""

  need_root
  ensure_debian_family
  [[ -x "${XRAY_BIN}" ]] || die "Current Xray binary not found: ${XRAY_BIN}"

  start_backup_session
  backup_path "${XRAY_BIN}"
  backup_path "${XRAY_ASSET_DIR}"

  install_xray
  validate_configs
  systemctl restart xray

  current_version="$("${XRAY_BIN}" version 2>/dev/null | head -n 1 || true)"
  log "Upgrade finished."
  log "Backup directory: ${BACKUP_DIR}"
  [[ -n "${current_version}" ]] && log "Current version: ${current_version}"
}

uri_encode() {
  local input="${1}"

  if command -v jq >/dev/null 2>&1; then
    jq -rn --arg v "${input}" '$v|@uri'
    return
  fi

  printf '%s' "${input}" \
    | sed \
      -e 's/%/%25/g' \
      -e 's/:/%3A/g' \
      -e 's/\//%2F/g' \
      -e 's/+/%2B/g' \
      -e 's/=/%3D/g' \
      -e 's/?/%3F/g' \
      -e 's/&/%26/g'
}

path_to_uri_component() {
  uri_encode "${1}"
}

write_state_file() {
  mkdir -p "${XRAY_CONFIG_DIR}"
  cat > "${STATE_FILE}" <<EOF
SERVER_IP='${SERVER_IP}'
REALITY_UUID='${REALITY_UUID}'
REALITY_SNI='${REALITY_SNI}'
REALITY_TARGET='${REALITY_TARGET}'
REALITY_SHORT_ID='${REALITY_SHORT_ID}'
REALITY_PRIVATE_KEY='${REALITY_PRIVATE_KEY}'
REALITY_PUBLIC_KEY='${REALITY_PUBLIC_KEY}'
XHTTP_UUID='${XHTTP_UUID}'
XHTTP_DOMAIN='${XHTTP_DOMAIN}'
XHTTP_PATH='${XHTTP_PATH}'
TLS_ALPN='${TLS_ALPN}'
FINGERPRINT='${FINGERPRINT}'
ENABLE_WARP='${ENABLE_WARP}'
ENABLE_NET_OPT='${ENABLE_NET_OPT}'
WARP_PROXY_PORT='${WARP_PROXY_PORT}'
CERT_MODE='${CERT_MODE}'
CF_ZONE_ID='${CF_ZONE_ID}'
CF_CERT_VALIDITY='${CF_CERT_VALIDITY}'
ACME_EMAIL='${ACME_EMAIL}'
ACME_CA='${ACME_CA}'
CF_DNS_ACCOUNT_ID='${CF_DNS_ACCOUNT_ID}'
CF_DNS_ZONE_ID='${CF_DNS_ZONE_ID}'
XHTTP_ECH_CONFIG_LIST='${XHTTP_ECH_CONFIG_LIST}'
XHTTP_ECH_FORCE_QUERY='${XHTTP_ECH_FORCE_QUERY}'
EOF
  chmod 0600 "${STATE_FILE}"
}

write_output_file() {
  local xhttp_path_component=""
  local xhttp_ech_component=""
  local cf_ssl_mode="Full (strict)"

  xhttp_path_component="$(path_to_uri_component "${XHTTP_PATH}")"
  xhttp_ech_component="$(uri_encode "${XHTTP_ECH_CONFIG_LIST}")"

  if [[ "${CERT_MODE}" == "self-signed" ]]; then
    cf_ssl_mode="Full"
  fi

  cat > "${OUTPUT_FILE}" <<EOF
# Xray WARP Team deployment

## Node 1
- Type: VLESS + REALITY + Vision
- Address: ${SERVER_IP}
- Port: 443
- UUID: ${REALITY_UUID}
- SNI: ${REALITY_SNI}
- Public key: ${REALITY_PUBLIC_KEY}
- Short ID: ${REALITY_SHORT_ID}
- Flow: xtls-rprx-vision
- Fingerprint: ${FINGERPRINT}

URI:
vless://${REALITY_UUID}@${SERVER_IP}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SNI}&fp=${FINGERPRINT}&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp&headerType=none#REALITY-VISION

## Node 2
- Type: VLESS + XHTTP + TLS + CDN
- Address: ${XHTTP_DOMAIN}
- Port: 443
- UUID: ${XHTTP_UUID}
- SNI: ${XHTTP_DOMAIN}
- Host: ${XHTTP_DOMAIN}
- ALPN: ${TLS_ALPN}
- Path: ${XHTTP_PATH}
- Mode: stream-one
- Fingerprint: ${FINGERPRINT}
- ECH query: ${XHTTP_ECH_CONFIG_LIST}
- ECH mode: ${XHTTP_ECH_FORCE_QUERY}

URI:
vless://${XHTTP_UUID}@${XHTTP_DOMAIN}:443?mode=stream-one&path=${xhttp_path_component}&security=tls&alpn=${TLS_ALPN}&encryption=none&insecure=0&host=${XHTTP_DOMAIN}&fp=${FINGERPRINT}&ech=${xhttp_ech_component}&type=xhttp&allowInsecure=0&sni=${XHTTP_DOMAIN}#XHTTP-CDN

## Cloudflare DNS
- Point ${XHTTP_DOMAIN} to this server IP.
- Enable orange-cloud for ${XHTTP_DOMAIN}.
- Set Cloudflare SSL/TLS mode to ${cf_ssl_mode}.

## Local files
- Xray config: ${XRAY_CONFIG_FILE}
- HAProxy config: ${HAPROXY_CONFIG}
- Installer state: ${STATE_FILE}
- Links output: ${OUTPUT_FILE}

## WARP
- Enabled: ${ENABLE_WARP}
- Local SOCKS5 port: ${WARP_PROXY_PORT}

## XHTTP ECH
- Enabled: yes
- DoH / ECH query: ${XHTTP_ECH_CONFIG_LIST}
- Force query mode: ${XHTTP_ECH_FORCE_QUERY}
- Note: generated XHTTP share link includes `ech=` for clients that support it. `none` remains the safer default than `full`.

## Network optimization
- Enabled: ${ENABLE_NET_OPT}
- Sysctl file: ${NET_SYSCTL_CONF}
- Service: ${NET_SERVICE_NAME}
EOF
}

change_uuid_cmd() {
  local rotate_reality=1
  local rotate_xhttp=1
  local new_reality_uuid=""
  local new_xhttp_uuid=""

  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --reality-uuid)
        new_reality_uuid="${2}"
        shift
        ;;
      --xhttp-uuid)
        new_xhttp_uuid="${2}"
        shift
        ;;
      --reality-only)
        rotate_xhttp=0
        ;;
      --xhttp-only)
        rotate_reality=0
        ;;
      --help|-h|help)
        usage
        exit 0
        ;;
      *)
        die "Unknown change-uuid option: ${1}"
        ;;
    esac
    shift
  done

  if [[ "${rotate_reality}" -eq 0 && "${rotate_xhttp}" -eq 0 ]]; then
    die "Nothing to change. Use default behavior, --reality-only, or --xhttp-only."
  fi

  need_root
  start_backup_session
  load_current_install_context

  if [[ "${rotate_reality}" -eq 1 ]]; then
    REALITY_UUID="${new_reality_uuid:-$(random_uuid)}"
  fi

  if [[ "${rotate_xhttp}" -eq 1 ]]; then
    XHTTP_UUID="${new_xhttp_uuid:-$(random_uuid)}"
  fi

  write_xray_config
  validate_configs
  systemctl restart xray
  write_state_file
  write_output_file

  log "UUID rotation finished."
  log "Backup directory: ${BACKUP_DIR}"
  show_links
}

change_sni_cmd() {
  local old_reality_sni=""
  local old_reality_target=""
  local target_default=""
  local sni_overridden=0
  local target_overridden=0

  need_root
  start_backup_session
  load_current_install_context

  old_reality_sni="${REALITY_SNI}"
  old_reality_target="${REALITY_TARGET}"

  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --non-interactive)
        NON_INTERACTIVE=1
        ;;
      --reality-sni)
        REALITY_SNI="${2}"
        sni_overridden=1
        shift
        ;;
      --reality-target)
        REALITY_TARGET="${2}"
        target_overridden=1
        shift
        ;;
      --help|-h|help)
        usage
        exit 0
        ;;
      *)
        die "Unknown change-sni option: ${1}"
        ;;
    esac
    shift
  done

  if [[ "${sni_overridden}" -eq 0 ]]; then
    REALITY_SNI=""
    prompt_with_default REALITY_SNI "New REALITY visible SNI" "${old_reality_sni}"
  fi

  if [[ "${target_overridden}" -eq 0 ]]; then
    REALITY_TARGET=""
    if [[ "${old_reality_target}" == "$(default_reality_target_for_sni "${old_reality_sni}")" ]]; then
      target_default="$(default_reality_target_for_sni "${REALITY_SNI}")"
    else
      target_default="${old_reality_target}"
    fi
    prompt_with_default REALITY_TARGET "New REALITY target host:port" "${target_default}"
  fi

  apply_managed_runtime_update
  log "REALITY SNI updated."
  log "Backup directory: ${BACKUP_DIR}"
  show_links
}

change_path_cmd() {
  local path_overridden=0

  need_root
  start_backup_session
  load_current_install_context

  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --non-interactive)
        NON_INTERACTIVE=1
        ;;
      --xhttp-path)
        XHTTP_PATH="${2}"
        path_overridden=1
        shift
        ;;
      --help|-h|help)
        usage
        exit 0
        ;;
      *)
        die "Unknown change-path option: ${1}"
        ;;
    esac
    shift
  done

  if [[ "${path_overridden}" -eq 0 ]]; then
    XHTTP_PATH=""
    prompt_with_default XHTTP_PATH "New XHTTP path" "$(config_jq_read '.inbounds[] | select(.tag=="xhttp-cdn") | .streamSettings.xhttpSettings.path')"
  fi
  ensure_xhttp_path_format

  apply_managed_runtime_update
  log "XHTTP path updated."
  log "Backup directory: ${BACKUP_DIR}"
  show_links
}

change_cert_mode_cmd() {
  local old_cert_mode=""
  local old_xhttp_domain=""
  local mode_overridden=0
  local domain_overridden=0

  need_root
  start_backup_session
  load_current_install_context

  old_cert_mode="${CERT_MODE}"
  old_xhttp_domain="${XHTTP_DOMAIN}"

  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --non-interactive)
        NON_INTERACTIVE=1
        ;;
      --cert-mode)
        CERT_MODE="${2}"
        mode_overridden=1
        shift
        ;;
      --xhttp-domain)
        XHTTP_DOMAIN="${2}"
        domain_overridden=1
        shift
        ;;
      --cert-file)
        CERT_SOURCE_FILE="${2}"
        shift
        ;;
      --key-file)
        KEY_SOURCE_FILE="${2}"
        shift
        ;;
      --cf-zone-id)
        CF_ZONE_ID="${2}"
        shift
        ;;
      --cf-api-token)
        CF_API_TOKEN="${2}"
        shift
        ;;
      --cf-cert-validity)
        CF_CERT_VALIDITY="${2}"
        shift
        ;;
      --acme-email)
        ACME_EMAIL="${2}"
        shift
        ;;
      --acme-ca)
        ACME_CA="${2}"
        shift
        ;;
      --cf-dns-token)
        CF_DNS_TOKEN="${2}"
        shift
        ;;
      --cf-dns-account-id)
        CF_DNS_ACCOUNT_ID="${2}"
        shift
        ;;
      --cf-dns-zone-id)
        CF_DNS_ZONE_ID="${2}"
        shift
        ;;
      --help|-h|help)
        usage
        exit 0
        ;;
      *)
        die "Unknown change-cert-mode option: ${1}"
        ;;
    esac
    shift
  done

  if [[ "${mode_overridden}" -eq 0 ]]; then
    CERT_MODE=""
    prompt_with_default CERT_MODE "New cert mode (self-signed/existing/cf-origin-ca/acme-dns-cf)" "${old_cert_mode}"
  fi
  case "${CERT_MODE}" in
    self-signed|existing|cf-origin-ca|acme-dns-cf)
      ;;
    *)
      die "Unsupported cert mode: ${CERT_MODE}"
      ;;
  esac

  if [[ "${domain_overridden}" -eq 0 ]]; then
    XHTTP_DOMAIN=""
    prompt_with_default XHTTP_DOMAIN "XHTTP CDN domain" "${old_xhttp_domain}"
  fi
  prompt_cert_mode_inputs
  apply_managed_update
  cleanup_previous_acme_cert "${old_cert_mode}" "${old_xhttp_domain}"

  log "Certificate mode updated."
  log "Backup directory: ${BACKUP_DIR}"
  show_links
}

show_links() {
  [[ -f "${STATE_FILE}" ]] || die "State file not found: ${STATE_FILE}"
  [[ -f "${OUTPUT_FILE}" ]] || die "Output file not found: ${OUTPUT_FILE}"
  cat "${OUTPUT_FILE}"
}

status_raw_cmd() {
  systemctl --no-pager --full status xray haproxy warp-svc "${NET_SERVICE_NAME}" 2>/dev/null || true
}

status_cmd() {
  local raw=0

  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --raw)
        raw=1
        ;;
      --help|-h|help)
        usage
        exit 0
        ;;
      *)
        die "Unknown status option: ${1}"
        ;;
    esac
    shift
  done

  if [[ "${raw}" -eq 1 ]]; then
    status_raw_cmd
    return
  fi

  show_dashboard
}

restart_cmd() {
  if service_exists "xray.service"; then
    systemctl restart xray
  fi
  if service_exists "haproxy.service"; then
    systemctl restart haproxy
  fi
  if service_exists "warp-svc.service"; then
    systemctl restart warp-svc || true
  fi
  if service_exists "${NET_SERVICE_NAME}"; then
    systemctl restart "${NET_SERVICE_NAME}" || true
  fi
  log "Services restarted."
}

uninstall_cmd() {
  local assume_yes=0
  local answer=""

  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --yes|-y)
        assume_yes=1
        ;;
      --help|-h|help)
        usage
        exit 0
        ;;
      *)
        die "Unknown uninstall option: ${1}"
        ;;
    esac
    shift
  done

  need_root
  start_backup_session
  load_existing_state

  if [[ "${assume_yes}" -ne 1 ]]; then
    read -r -p "This will stop services and remove managed files, but keep installed packages. Continue? [y/N]: " answer
    answer="$(printf '%s' "${answer}" | tr 'A-Z' 'a-z')"
    if [[ "${answer}" != "y" && "${answer}" != "yes" ]]; then
      die "Uninstall cancelled."
    fi
  fi

  stop_and_disable_service_if_present "xray.service"
  stop_and_disable_service_if_present "haproxy.service"
  stop_and_disable_service_if_present "warp-svc.service"
  stop_and_disable_service_if_present "${NET_SERVICE_NAME}"

  if [[ "${CERT_MODE:-}" == "acme-dns-cf" && -x "${ACME_SH_BIN}" && -n "${XHTTP_DOMAIN:-}" ]]; then
    "${ACME_SH_BIN}" --remove -d "${XHTTP_DOMAIN}" --ecc >/dev/null 2>&1 || true
  fi

  remove_managed_paths \
    "${SELF_COMMAND_PATH}" \
    "${XRAY_BIN}" \
    "${XRAY_CONFIG_DIR}" \
    "${XRAY_ASSET_DIR}" \
    "${XRAY_SERVICE_FILE}" \
    "${HAPROXY_CONFIG}" \
    "${SSL_DIR}" \
    "${WARP_MDM_FILE}" \
    "${NET_SYSCTL_CONF}" \
    "${NET_HELPER_PATH}" \
    "${NET_SERVICE_FILE}" \
    "${ACME_RELOAD_HELPER}" \
    "${OUTPUT_FILE}" \
    "/var/log/xray" \
    "/var/lib/xray"

  systemctl daemon-reload
  systemctl reset-failed xray.service haproxy.service warp-svc.service "${NET_SERVICE_NAME}" >/dev/null 2>&1 || true
  sysctl --system >/dev/null 2>&1 || true

  log "Managed files removed."
  log "Backup directory: ${BACKUP_DIR}"
  log "Installed packages were kept in place."
}

main_menu() {
  local choice=""

  while true; do
    if [[ -t 1 ]]; then
      clear >/dev/null 2>&1 || true
    fi
    show_dashboard
    cat <<'EOF'
  1. Install or reinstall
  2. Show node links
  3. Refresh status panel
  4. Restart services
  5. Upgrade Xray core
  6. Rotate node UUIDs
  7. Change REALITY SNI
  8. Change XHTTP path
  9. Change cert mode / CDN domain
  10. Uninstall managed files
  11. Raw service details
  12. Help
  0. Exit
EOF
    read -r -p "Select: " choice
    case "${choice}" in
      1) install_cmd ;;
      2) show_links ;;
      3) status_cmd ;;
      4) restart_cmd ;;
      5) upgrade_cmd ;;
      6) change_uuid_cmd ;;
      7) change_sni_cmd ;;
      8) change_path_cmd ;;
      9) change_cert_mode_cmd ;;
      10) uninstall_cmd ;;
      11) status_raw_cmd ;;
      12) usage ;;
      0) exit 0 ;;
      *) warn "Unknown selection: ${choice}" ;;
    esac
    if [[ "${choice}" != "0" ]]; then
      printf '\n'
      read -r -p "Press Enter to continue..." _
    fi
  done
}

parse_install_args() {
  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --non-interactive)
        NON_INTERACTIVE=1
        ;;
      --server-ip)
        SERVER_IP="${2}"
        shift
        ;;
      --reality-uuid)
        REALITY_UUID="${2}"
        shift
        ;;
      --reality-sni)
        REALITY_SNI="${2}"
        shift
        ;;
      --reality-target)
        REALITY_TARGET="${2}"
        shift
        ;;
      --reality-short-id)
        REALITY_SHORT_ID="${2}"
        shift
        ;;
      --reality-private-key)
        REALITY_PRIVATE_KEY="${2}"
        shift
        ;;
      --xhttp-uuid)
        XHTTP_UUID="${2}"
        shift
        ;;
      --xhttp-domain)
        XHTTP_DOMAIN="${2}"
        shift
        ;;
      --xhttp-path)
        XHTTP_PATH="${2}"
        shift
        ;;
      --cert-mode)
        CERT_MODE="${2}"
        shift
        ;;
      --cert-file)
        CERT_SOURCE_FILE="${2}"
        shift
        ;;
      --key-file)
        KEY_SOURCE_FILE="${2}"
        shift
        ;;
      --cf-zone-id)
        CF_ZONE_ID="${2}"
        shift
        ;;
      --cf-api-token)
        CF_API_TOKEN="${2}"
        shift
        ;;
      --cf-cert-validity)
        CF_CERT_VALIDITY="${2}"
        shift
        ;;
      --acme-email)
        ACME_EMAIL="${2}"
        shift
        ;;
      --acme-ca)
        ACME_CA="${2}"
        shift
        ;;
      --cf-dns-token)
        CF_DNS_TOKEN="${2}"
        shift
        ;;
      --cf-dns-account-id)
        CF_DNS_ACCOUNT_ID="${2}"
        shift
        ;;
      --cf-dns-zone-id)
        CF_DNS_ZONE_ID="${2}"
        shift
        ;;
      --enable-warp)
        ENABLE_WARP="yes"
        ;;
      --disable-warp)
        ENABLE_WARP="no"
        ;;
      --enable-net-opt)
        ENABLE_NET_OPT="yes"
        ;;
      --disable-net-opt)
        ENABLE_NET_OPT="no"
        ;;
      --warp-team)
        WARP_TEAM_NAME="${2}"
        shift
        ;;
      --warp-client-id)
        WARP_CLIENT_ID="${2}"
        shift
        ;;
      --warp-client-secret)
        WARP_CLIENT_SECRET="${2}"
        shift
        ;;
      --warp-proxy-port)
        WARP_PROXY_PORT="${2}"
        shift
        ;;
      --help|-h|help)
        usage
        exit 0
        ;;
      *)
        die "Unknown install option: ${1}"
        ;;
    esac
    shift
  done
}

install_cmd() {
  need_root
  ensure_debian_family

  start_backup_session

  parse_install_args "$@"
  prepare_install_inputs
  install_packages
  install_self_command
  install_xray
  ensure_xray_user
  generate_reality_keys_if_needed
  write_tls_assets
  write_xray_config
  write_haproxy_config
  write_xray_service
  install_network_optimization
  install_warp
  validate_configs
  restart_services
  write_state_file
  write_output_file

  log "Deployment finished."
  log "Backup directory: ${BACKUP_DIR}"
  log "Management command: ${SELF_COMMAND_PATH}"
  log "Node links saved to: ${OUTPUT_FILE}"
  show_links
}

main() {
  local command="${1:-menu}"

  case "${command}" in
    menu)
      if [[ $# -gt 0 ]]; then
        shift
      fi
      main_menu
      ;;
    install)
      shift || true
      install_cmd "$@"
      ;;
    upgrade)
      shift || true
      upgrade_cmd "$@"
      ;;
    change-uuid)
      shift || true
      change_uuid_cmd "$@"
      ;;
    change-sni)
      shift || true
      change_sni_cmd "$@"
      ;;
    change-path)
      shift || true
      change_path_cmd "$@"
      ;;
    change-cert-mode)
      shift || true
      change_cert_mode_cmd "$@"
      ;;
    uninstall)
      shift || true
      uninstall_cmd "$@"
      ;;
    show-links)
      show_links
      ;;
    status)
      shift || true
      status_cmd "$@"
      ;;
    restart)
      restart_cmd
      ;;
    help|--help|-h)
      usage
      ;;
    *)
      die "Unknown command: ${command}"
      ;;
  esac
}

main "$@"
