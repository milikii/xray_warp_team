#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_VERSION="0.4.1"
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
HAPROXY_CONFIG="/etc/haproxy/haproxy.cfg"
NGINX_CONF_DIR="/etc/nginx/conf.d"
NGINX_CONFIG_FILE="${NGINX_CONF_DIR}/xray-warp-team.conf"
NGINX_TLS_PORT="8443"
XHTTP_LOCAL_PORT="8001"
NGINX_SERVICE_FILE="/lib/systemd/system/nginx.service"
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

log() {
  printf '[信息] %s\n' "$*"
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

usage() {
  local command_name=""

  command_name="$(basename "${0}")"
  cat <<'EOF'
xray-warp-team.sh v0.4.1
EOF
  cat <<EOF

用法:
  ${command_name}
  ${command_name} install [参数]
  ${command_name} upgrade
  ${command_name} change-uuid [参数]
  ${command_name} change-sni [参数]
  ${command_name} change-path [参数]
  ${command_name} change-label-prefix [参数]
  ${command_name} change-warp [参数]
  ${command_name} change-cert-mode [参数]
  ${command_name} uninstall [--yes]
  ${command_name} show-links
  ${command_name} status [--raw]
  ${command_name} restart
  ${command_name} repair-perms
  ${command_name} help

安装参数:
  --non-interactive           非交互运行；缺少必要参数时直接失败。
  --server-ip VALUE           REALITY 直连节点的公网 IP 或域名。
  --node-label-prefix VALUE   导出节点名称前缀，例如 HKG 或 SJC。
  --reality-uuid VALUE        指定 REALITY 节点 UUID。
  --reality-sni VALUE         REALITY 可见 SNI，同时用于 HAProxy 分流。
  --reality-short-id VALUE    REALITY 短 ID。
  --reality-private-key VALUE 复用现有 REALITY 私钥。
  --xhttp-uuid VALUE          指定 XHTTP CDN 节点 UUID。
  --xhttp-domain VALUE        XHTTP CDN 使用的橙云域名。
  --xhttp-path VALUE          XHTTP 路径，例如 /cfup-example。
  --enable-xhttp-vless-encryption   启用 XHTTP CDN 的 VLESS Encryption。
  --disable-xhttp-vless-encryption  禁用 XHTTP CDN 的 VLESS Encryption。
  --cert-mode VALUE           证书模式：self-signed、existing、cf-origin-ca、acme-dns-cf。
  --cert-file VALUE           当证书模式为 existing 时使用的证书文件。
  --key-file VALUE            当证书模式为 existing 时使用的私钥文件。
  --cert-pem VALUE            当证书模式为 existing 时直接传入证书 PEM 内容。
  --key-pem VALUE             当证书模式为 existing 时直接传入私钥 PEM 内容。
  --cf-zone-id VALUE          cf-origin-ca 模式使用的 Cloudflare Zone ID。
  --cf-api-token VALUE        cf-origin-ca 模式使用的 Cloudflare API 令牌。
  --cf-cert-validity VALUE    Cloudflare Origin CA 证书有效期，默认 5475 天。
  --acme-email VALUE          acme.sh 注册邮箱。
  --acme-ca VALUE             acme.sh 使用的 CA，默认 letsencrypt。
  --cf-dns-token VALUE        acme dns_cf 模式使用的 Cloudflare DNS API 令牌。
  --cf-dns-account-id VALUE   acme dns_cf 模式使用的 Cloudflare Account ID，可选。
  --cf-dns-zone-id VALUE      acme dns_cf 模式使用的 Cloudflare Zone ID，可选。
  --enable-warp               启用选择性 WARP 出站。
  --disable-warp              禁用 WARP 出站。
  --enable-net-opt            启用 BBR/FQ/RPS 网络优化。
  --disable-net-opt           禁用网络优化。
  --warp-team VALUE           Cloudflare Zero Trust 团队名。
  --warp-client-id VALUE      服务令牌 Client ID。
  --warp-client-secret VALUE  服务令牌 Client Secret。
  --warp-proxy-port VALUE     WARP 本地 SOCKS5 端口，默认 40000。

变更 UUID 参数:
  --reality-uuid VALUE        指定新的 REALITY UUID，而不是自动生成。
  --xhttp-uuid VALUE          指定新的 XHTTP UUID，而不是自动生成。
  --reality-only              只轮换 REALITY UUID。
  --xhttp-only                只轮换 XHTTP UUID。

变更 SNI 参数:
  --non-interactive           非交互运行。
  --reality-sni VALUE         新的 REALITY 可见 SNI。

变更路径参数:
  --non-interactive           非交互运行。
  --xhttp-path VALUE          新的 XHTTP 路径。

变更节点名前缀参数:
  --non-interactive           非交互运行。
  --node-label-prefix VALUE   新的导出节点名前缀。

变更 WARP 参数:
  --non-interactive           非交互运行。
  --enable-warp               启用 WARP 分流。
  --disable-warp              禁用 WARP 分流。
  --warp-team VALUE           Cloudflare Zero Trust 团队名。
  --warp-client-id VALUE      服务令牌 Client ID。
  --warp-client-secret VALUE  服务令牌 Client Secret。
  --warp-proxy-port VALUE     WARP 本地 SOCKS5 端口。

变更证书模式参数:
  --non-interactive           非交互运行。
  --cert-mode VALUE           新证书模式：self-signed、existing、cf-origin-ca、acme-dns-cf。
  --xhttp-domain VALUE        新的 XHTTP CDN 域名，可选。
  --cert-file VALUE           existing 模式使用的证书文件。
  --key-file VALUE            existing 模式使用的私钥文件。
  --cert-pem VALUE            existing 模式直接传入证书 PEM 内容。
  --key-pem VALUE             existing 模式直接传入私钥 PEM 内容。
  --cf-zone-id VALUE          cf-origin-ca 模式使用的 Cloudflare Zone ID。
  --cf-api-token VALUE        cf-origin-ca 模式使用的 Cloudflare API 令牌。
  --cf-cert-validity VALUE    Cloudflare Origin CA 证书有效期。
  --acme-email VALUE          acme.sh 注册邮箱。
  --acme-ca VALUE             acme.sh 使用的 CA。
  --cf-dns-token VALUE        acme dns_cf 模式使用的 Cloudflare DNS API 令牌。
  --cf-dns-account-id VALUE   acme dns_cf 模式使用的 Cloudflare Account ID，可选。
  --cf-dns-zone-id VALUE      acme dns_cf 模式使用的 Cloudflare Zone ID，可选。

卸载参数:
  --yes                       跳过确认提示。

状态参数:
  --raw                       显示原始 systemctl 输出，而不是面板。

示例:
  ${command_name}
  ${command_name} upgrade
  ${command_name} repair-perms
  ${command_name} change-uuid
  ${command_name} change-sni --reality-sni www.stanford.edu
  ${command_name} change-path --xhttp-path /assets/v3
  ${command_name} change-label-prefix --node-label-prefix HKG
  ${command_name} change-warp --disable-warp
  ${command_name} change-cert-mode --cert-mode self-signed
  ${command_name} uninstall --yes
  ${command_name} install --non-interactive \
    --server-ip 203.0.113.10 \
    --xhttp-domain cdn.example.com \
    --cert-mode self-signed \
    --enable-net-opt \
    --enable-warp \
    --warp-team your-team \
    --warp-client-id xxxxxxxxx.access \
    --warp-client-secret xxxxxxxxx
EOF
}

guess_server_ip() {
  local guessed=""
  local fallback=""

  guessed="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") {print $(i + 1); exit}}')"

  if is_public_ipv4 "${guessed}"; then
    printf '%s' "${guessed}"
    return
  fi

  fallback="${guessed}"
  guessed="$(fetch_public_ipv4)"
  if is_public_ipv4 "${guessed}"; then
    printf '%s' "${guessed}"
    return
  fi

  if [[ -z "${fallback}" ]]; then
    fallback="$(ip -o -4 addr show scope global 2>/dev/null | awk '{split($4, a, "/"); print a[1]; exit}')"
  fi
  printf '%s' "${fallback}"
}

is_ipv4() {
  local ip="${1:-}"

  [[ -n "${ip}" ]] || return 1
  awk -F'.' '
    NF != 4 { exit 1 }
    {
      for (i = 1; i <= 4; i++) {
        if ($i !~ /^[0-9]+$/) exit 1
        if ($i < 0 || $i > 255) exit 1
      }
    }
    END { exit 0 }
  ' <<<"${ip}" >/dev/null 2>&1
}

is_private_ipv4() {
  local ip="${1:-}"

  is_ipv4 "${ip}" || return 1

  case "${ip}" in
    10.*|127.*|0.*|192.168.*|169.254.*)
      return 0
      ;;
    172.1[6-9].*|172.2[0-9].*|172.3[0-1].*)
      return 0
      ;;
    100.6[4-9].*|100.[7-9][0-9].*|100.1[0-1][0-9].*|100.12[0-7].*)
      return 0
      ;;
  esac

  return 1
}

is_public_ipv4() {
  local ip="${1:-}"

  is_ipv4 "${ip}" || return 1
  is_private_ipv4 "${ip}" && return 1
  return 0
}

fetch_public_ipv4() {
  local url=""
  local ip=""

  for url in \
    "https://api.ipify.org" \
    "https://ifconfig.me/ip" \
    "https://ipv4.icanhazip.com"
  do
    ip="$(curl -4fsSL --max-time 4 "${url}" 2>/dev/null | tr -d '\r\n')"
    if is_public_ipv4 "${ip}"; then
      printf '%s' "${ip}"
      return
    fi
  done

  return 1
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
  local candidates=(
    "/assets/v3"
    "/static/app"
    "/images/webp"
    "/fonts/inter"
    "/media/cache"
  )

  printf '%s' "${candidates[$((RANDOM % ${#candidates[@]}))]}"
}

normalize_cert_mode() {
  local input="${1:-}"

  case "${input}" in
    self-signed|自签名|selfsigned)
      printf 'self-signed'
      ;;
    existing|现有证书|已有证书|现有)
      printf 'existing'
      ;;
    cf-origin-ca|cloudflare-origin-ca|cloudflare-origin|cf-origin|origin-ca|cfca|cloudflare-originca|cloudflare-ca|cf-origin-ca证书|cf-origin-ca模式)
      printf 'cf-origin-ca'
      ;;
    acme-dns-cf|acme|acme-dns|acme-cf|acme证书)
      printf 'acme-dns-cf'
      ;;
    *)
      printf '%s' "${input}"
      ;;
  esac
}

normalize_node_label_prefix() {
  local input="${1:-}"
  local cleaned=""

  cleaned="$(printf '%s' "${input}" \
    | tr '[:lower:]' '[:upper:]' \
    | sed -E 's/[^A-Z0-9._-]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g')"

  if [[ -z "${cleaned}" || "${cleaned}" == "LOCALHOST" ]]; then
    cleaned="VPS"
  fi

  printf '%s' "${cleaned}"
}

default_node_label_prefix() {
  local guessed=""

  guessed="$(hostname -s 2>/dev/null || true)"
  normalize_node_label_prefix "${guessed}"
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
    die "缺少必填参数：${var_name}。"
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
    die "缺少必填密钥参数：${var_name}。"
  fi

  read -r -s -p "${prompt_text}: " current_value
  printf '\n'
  printf -v "${var_name}" '%s' "${current_value}"
}

prompt_multiline_value() {
  local var_name="${1}"
  local prompt_text="${2}"
  local current_value=""
  local line=""

  current_value="${!var_name:-}"
  if [[ -n "${current_value}" ]]; then
    return
  fi

  if [[ "${NON_INTERACTIVE}" -eq 1 ]]; then
    die "缺少必填多行内容：${var_name}。"
  fi

  printf '%s\n' "${prompt_text}"
  printf '%s\n' "请直接粘贴内容，结束后单独输入一行 EOF。"

  current_value=""
  while IFS= read -r line; do
    if [[ "${line}" == "EOF" ]]; then
      break
    fi
    current_value+="${line}"$'\n'
  done

  current_value="${current_value%$'\n'}"
  [[ -n "${current_value}" ]] || die "${var_name} 内容不能为空。"
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

prepare_existing_cert_inputs() {
  local input_mode=""
  local first_input=""

  if [[ -n "${CERT_SOURCE_FILE}" || -n "${KEY_SOURCE_FILE}" ]]; then
    [[ -n "${CERT_SOURCE_FILE}" && -n "${KEY_SOURCE_FILE}" ]] || die "existing 模式下，证书文件路径和私钥文件路径必须同时提供。"
    CERT_SOURCE_PEM=""
    KEY_SOURCE_PEM=""
    return
  fi

  if [[ -n "${CERT_SOURCE_PEM}" || -n "${KEY_SOURCE_PEM}" ]]; then
    [[ -n "${CERT_SOURCE_PEM}" && -n "${KEY_SOURCE_PEM}" ]] || die "existing 模式下，证书 PEM 内容和私钥 PEM 内容必须同时提供。"
    CERT_SOURCE_FILE=""
    KEY_SOURCE_FILE=""
    return
  fi

  if [[ "${NON_INTERACTIVE}" -eq 1 ]]; then
    die "existing 模式下，请提供 --cert-file/--key-file，或 --cert-pem/--key-pem。"
  fi

  read -r -p "证书输入方式 [path/pem] [path]，也可以直接输入证书文件路径: " first_input
  input_mode="${first_input:-path}"

  case "${input_mode}" in
    path|'')
      prompt_with_default CERT_SOURCE_FILE "现有证书文件路径" ""
      prompt_with_default KEY_SOURCE_FILE "现有私钥文件路径" ""
      ;;
    pem)
      prompt_multiline_value CERT_SOURCE_PEM "请输入证书 PEM 内容"
      prompt_multiline_value KEY_SOURCE_PEM "请输入私钥 PEM 内容"
      ;;
    *)
      if [[ -f "${input_mode}" || "${input_mode}" == /* || "${input_mode}" == ./* || "${input_mode}" == ../* ]]; then
        CERT_SOURCE_FILE="${input_mode}"
        prompt_with_default KEY_SOURCE_FILE "现有私钥文件路径" ""
      else
        die "证书输入方式只能是 path、pem，或者直接输入证书文件路径。"
      fi
      ;;
  esac
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

  state="$(systemctl show "${unit_name}" -p ActiveState --value 2>/dev/null || true)"
  if [[ -n "${state}" ]]; then
    printf '%s' "${state}"
  else
    printf 'installed'
  fi
}

service_enable_state() {
  local unit_name="${1}"

  if ! service_exists "${unit_name}"; then
    printf 'not-installed'
    return
  fi

  case "$(systemctl show "${unit_name}" -p UnitFileState --value 2>/dev/null || true)" in
    enabled)
      printf 'enabled'
      ;;
    disabled|masked|static|indirect|generated|transient)
      printf 'installed'
      ;;
    *)
      printf 'installed'
      ;;
  esac
}

service_badge() {
  local state="${1}"

  case "${state}" in
    active)
      style_text "${C_GREEN}" "运行中"
      ;;
    inactive|failed|activating|deactivating)
      case "${state}" in
        inactive) style_text "${C_RED}" "未运行" ;;
        failed) style_text "${C_RED}" "失败" ;;
        activating) style_text "${C_YELLOW}" "启动中" ;;
        deactivating) style_text "${C_YELLOW}" "停止中" ;;
      esac
      ;;
    not-installed)
      style_text "${C_YELLOW}" "未安装"
      ;;
    *)
      style_text "${C_YELLOW}" "${state}"
      ;;
  esac
}

bool_badge() {
  case "${1}" in
    yes|enabled|true)
      style_text "${C_GREEN}" "已启用"
      ;;
    skipped)
      style_text "${C_YELLOW}" "已跳过"
      ;;
    no|disabled|false)
      style_text "${C_YELLOW}" "已禁用"
      ;;
    *)
      style_text "${C_YELLOW}" "${1:-未知}"
      ;;
  esac
}

service_install_state_label() {
  case "${1}" in
    enabled)
      printf '已启用'
      ;;
    installed)
      printf '已安装'
      ;;
    not-installed)
      printf '未安装'
      ;;
    *)
      printf '%s' "${1}"
      ;;
  esac
}

pretty_cert_mode() {
  case "${CERT_MODE:-unknown}" in
    self-signed)
      printf '自签名'
      ;;
    existing)
      printf '现有证书'
      ;;
    cf-origin-ca)
      printf 'Cloudflare Origin CA'
      ;;
    acme-dns-cf)
      printf 'ACME DNS CF'
      ;;
    *)
      printf '%s' "${CERT_MODE:-未知}"
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
  XHTTP_VLESS_DECRYPTION="${XHTTP_VLESS_DECRYPTION:-$(config_jq_read '.inbounds[] | select(.tag=="xhttp-cdn") | .settings.decryption')}"
  XHTTP_DOMAIN="${XHTTP_DOMAIN:-$(nginx_server_name "${XHTTP_PATH:-/}")}"
  SERVER_IP="${SERVER_IP:-$(output_field_value '地址')}"
  NODE_LABEL_PREFIX="${NODE_LABEL_PREFIX:-$(output_field_value '节点名前缀')}"
  REALITY_PUBLIC_KEY="${REALITY_PUBLIC_KEY:-$(output_field_value '公钥')}"
  FINGERPRINT="${FINGERPRINT:-$(output_field_value '指纹')}"
  ENABLE_WARP="${ENABLE_WARP:-$(if config_jq_read '.outbounds[] | select(.tag=="WARP") | .tag' | grep -q 'WARP'; then printf 'yes'; else printf 'no'; fi)}"
  WARP_PROXY_PORT="${WARP_PROXY_PORT:-$(config_jq_read '.outbounds[] | select(.tag=="WARP") | .settings.servers[0].port')}"
  CERT_MODE="${CERT_MODE:-existing}"
  ENABLE_NET_OPT="${ENABLE_NET_OPT:-$(if [[ -f "${NET_SERVICE_FILE}" || -f "${NET_SYSCTL_CONF}" ]]; then printf 'yes'; else printf 'no'; fi)}"
  ACME_CA="${ACME_CA:-${DEFAULT_ACME_CA}}"
  SERVER_IP="${SERVER_IP:-$(guess_server_ip)}"
  NODE_LABEL_PREFIX="${NODE_LABEL_PREFIX:-$(default_node_label_prefix)}"
  FINGERPRINT="${FINGERPRINT:-${DEFAULT_FINGERPRINT}}"
  WARP_PROXY_PORT="${WARP_PROXY_PORT:-${DEFAULT_WARP_PROXY_PORT}}"
  if [[ "${XHTTP_VLESS_DECRYPTION:-}" == "none" || -z "${XHTTP_VLESS_DECRYPTION:-}" ]]; then
    XHTTP_VLESS_ENCRYPTION_ENABLED="${XHTTP_VLESS_ENCRYPTION_ENABLED:-no}"
  else
    XHTTP_VLESS_ENCRYPTION_ENABLED="${XHTTP_VLESS_ENCRYPTION_ENABLED:-yes}"
  fi
}

show_dashboard() {
  local xray_state=""
  local haproxy_state=""
  local nginx_state=""
  local warp_state=""
  local net_state=""
  local xray_enabled=""
  local haproxy_enabled=""
  local nginx_enabled=""
  local warp_enabled=""
  local net_enabled=""
  local version_line=""

  load_dashboard_context

  xray_state="$(service_active_state 'xray.service')"
  haproxy_state="$(service_active_state 'haproxy.service')"
  nginx_state="$(service_active_state 'nginx.service')"
  warp_state="$(service_active_state 'warp-svc.service')"
  net_state="$(service_active_state "${NET_SERVICE_NAME}")"
  xray_enabled="$(service_enable_state 'xray.service')"
  haproxy_enabled="$(service_enable_state 'haproxy.service')"
  nginx_enabled="$(service_enable_state 'nginx.service')"
  warp_enabled="$(service_enable_state 'warp-svc.service')"
  net_enabled="$(service_enable_state "${NET_SERVICE_NAME}")"
  version_line="$(xray_version_line)"

  divider
  printf '%b%s%b\n' "${C_BOLD}${C_CYAN}" "Xray WARP 管理面板" "${C_RESET}"
  divider
  panel_row "脚本版本" "${SCRIPT_VERSION}"
  panel_row "更新时间" "$(date '+%Y-%m-%d %H:%M:%S %Z')"

  if [[ -f "${XRAY_CONFIG_FILE}" ]]; then
    panel_row "安装状态" "$(style_text "${C_GREEN}" "已托管")"
    [[ -n "${version_line}" ]] && panel_row "Xray 核心" "${version_line}"
    panel_row "证书模式" "$(pretty_cert_mode)"
    panel_row "REALITY" "${SERVER_IP:-未知}:443  sni=${REALITY_SNI:-未知}"
    panel_row "XHTTP CDN" "${XHTTP_DOMAIN:-未知}:443  path=${XHTTP_PATH:-未知}"
    panel_row "节点前缀" "${NODE_LABEL_PREFIX:-未知}"
    panel_row "REALITY UUID" "$(short_value "${REALITY_UUID:-未知}")"
    panel_row "XHTTP UUID" "$(short_value "${XHTTP_UUID:-未知}")"
    panel_row "REALITY 公钥" "$(short_value "${REALITY_PUBLIC_KEY:-未知}" 10 8)"
    panel_row "链接文件" "${OUTPUT_FILE}"
  else
    panel_row "安装状态" "$(style_text "${C_YELLOW}" "未安装")"
  fi

  divider
  printf '%b%s%b\n' "${C_BOLD}" "服务状态" "${C_RESET}"
  panel_row "xray" "$(service_badge "${xray_state}") ($(service_install_state_label "${xray_enabled}"))"
  panel_row "haproxy" "$(service_badge "${haproxy_state}") ($(service_install_state_label "${haproxy_enabled}"))"
  panel_row "nginx" "$(service_badge "${nginx_state}") ($(service_install_state_label "${nginx_enabled}"))"
  panel_row "warp-svc" "$(service_badge "${warp_state}") ($(service_install_state_label "${warp_enabled}"))"
  panel_row "网络优化" "$(service_badge "${net_state}") ($(service_install_state_label "${net_enabled}"))"

  divider
  printf '%b%s%b\n' "${C_BOLD}" "功能开关" "${C_RESET}"
  panel_row "WARP 分流" "$(bool_badge "${ENABLE_WARP:-no}")  端口=${WARP_PROXY_PORT:-${DEFAULT_WARP_PROXY_PORT}}"
  panel_row "网络优化" "$(bool_badge "${ENABLE_NET_OPT:-no}")"
  panel_row "VLESS Encryption" "$(bool_badge "${XHTTP_VLESS_ENCRYPTION_ENABLED:-${DEFAULT_XHTTP_VLESS_ENCRYPTION_ENABLED}}")"
  panel_row "XHTTP ECH" "$(if [[ -n "${XHTTP_ECH_CONFIG_LIST:-${DEFAULT_XHTTP_ECH_CONFIG_LIST}}" ]]; then bool_badge "yes"; else bool_badge "no"; fi)  doh=${XHTTP_ECH_CONFIG_LIST:-未设置}"
  if [[ "${CERT_MODE:-}" == "acme-dns-cf" ]]; then
    panel_row "ACME CA" "${ACME_CA:-${DEFAULT_ACME_CA}}"
  fi
  divider
}

ensure_debian_family() {
  if [[ ! -f /etc/os-release ]]; then
    die "不支持的系统：找不到 /etc/os-release。"
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

  die "当前脚本仅支持 Debian 和 Ubuntu。"
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
      die "不支持的 CPU 架构：$(uname -m)"
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
    '.inbounds[] | select(.tag=="xhttp-cdn") | .settings.decryption')
      config_fallback_string_in_tag "xhttp-cdn" "decryption"
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

warp_mdm_value() {
  local key_name="${1}"

  [[ -f "${WARP_MDM_FILE}" ]] || return 0

  awk -v key_name="${key_name}" '
    $0 ~ "<key>" key_name "</key>" {
      getline
      line=$0
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line ~ /^<string>/) {
        sub(/^<string>/, "", line)
        sub(/<\/string>$/, "", line)
        print line
        exit
      }
      if (line ~ /^<integer>/) {
        sub(/^<integer>/, "", line)
        sub(/<\/integer>$/, "", line)
        print line
        exit
      }
    }
  ' "${WARP_MDM_FILE}" 2>/dev/null || true
}

load_warp_mdm_context() {
  WARP_TEAM_NAME="${WARP_TEAM_NAME:-$(warp_mdm_value 'organization')}"
  WARP_CLIENT_ID="${WARP_CLIENT_ID:-$(warp_mdm_value 'auth_client_id')}"
  WARP_CLIENT_SECRET="${WARP_CLIENT_SECRET:-$(warp_mdm_value 'auth_client_secret')}"
  WARP_PROXY_PORT="${WARP_PROXY_PORT:-$(warp_mdm_value 'proxy_port')}"
}

nginx_server_name() {
  local path_hint="${1}"

  [[ -f "${NGINX_CONFIG_FILE}" ]] || return 0
  awk -v path_hint="${path_hint}" '
    /location[[:space:]]+\// { in_loc = 1 }
    in_loc && index($0, path_hint) { wanted = 1 }
    /^[[:space:]]*server_name[[:space:]]+/ {
      line = $0
      sub(/^[[:space:]]*server_name[[:space:]]+/, "", line)
      sub(/;.*/, "", line)
      current = line
      if (wanted) {
        print current
        exit
      }
    }
    /^}/ {
      in_loc = 0
      wanted = 0
    }
  ' "${NGINX_CONFIG_FILE}" 2>/dev/null | head -n 1
}

load_existing_state() {
  if [[ -f "${STATE_FILE}" ]]; then
    # shellcheck disable=SC1090
    . "${STATE_FILE}"
  fi
  if [[ "${XHTTP_ECH_CONFIG_LIST:-}" == "https://1.1.1.1/dns-query" && "${XHTTP_ECH_FORCE_QUERY:-}" == "none" ]]; then
    XHTTP_ECH_CONFIG_LIST=""
    XHTTP_ECH_FORCE_QUERY=""
  fi
  load_warp_mdm_context
}

load_current_install_context() {
  load_existing_state

  [[ -f "${XRAY_CONFIG_FILE}" ]] || die "找不到当前 Xray 配置：${XRAY_CONFIG_FILE}"

  REALITY_UUID="${REALITY_UUID:-$(config_jq_read '.inbounds[] | select(.tag=="reality-vision") | .settings.clients[0].id')}"
  REALITY_SNI="${REALITY_SNI:-$(config_jq_read '.inbounds[] | select(.tag=="reality-vision") | .streamSettings.realitySettings.serverNames[0]')}"
  REALITY_TARGET="${REALITY_TARGET:-$(config_jq_read '.inbounds[] | select(.tag=="reality-vision") | .streamSettings.realitySettings.target')}"
  REALITY_SHORT_ID="${REALITY_SHORT_ID:-$(config_jq_read '.inbounds[] | select(.tag=="reality-vision") | .streamSettings.realitySettings.shortIds[0]')}"
  REALITY_PRIVATE_KEY="${REALITY_PRIVATE_KEY:-$(config_jq_read '.inbounds[] | select(.tag=="reality-vision") | .streamSettings.realitySettings.privateKey')}"
  XHTTP_UUID="${XHTTP_UUID:-$(config_jq_read '.inbounds[] | select(.tag=="xhttp-cdn") | .settings.clients[0].id')}"
  XHTTP_PATH="${XHTTP_PATH:-$(config_jq_read '.inbounds[] | select(.tag=="xhttp-cdn") | .streamSettings.xhttpSettings.path')}"
  XHTTP_VLESS_DECRYPTION="${XHTTP_VLESS_DECRYPTION:-$(config_jq_read '.inbounds[] | select(.tag=="xhttp-cdn") | .settings.decryption')}"
  TLS_ALPN="${TLS_ALPN:-$(config_jq_read '.inbounds[] | select(.tag=="xhttp-cdn") | .streamSettings.tlsSettings.alpn[0]')}"
  XHTTP_DOMAIN="${XHTTP_DOMAIN:-$(nginx_server_name "${XHTTP_PATH:-/}")}"
  ENABLE_WARP="${ENABLE_WARP:-$(if config_jq_read '.outbounds[] | select(.tag=="WARP") | .tag' | grep -q 'WARP'; then printf 'yes'; else printf 'no'; fi)}"
  WARP_PROXY_PORT="${WARP_PROXY_PORT:-$(config_jq_read '.outbounds[] | select(.tag=="WARP") | .settings.servers[0].port')}"
  SERVER_IP="${SERVER_IP:-$(output_field_value '地址')}"
  NODE_LABEL_PREFIX="${NODE_LABEL_PREFIX:-$(output_field_value '节点名前缀')}"
  REALITY_PUBLIC_KEY="${REALITY_PUBLIC_KEY:-$(output_field_value '公钥')}"
  FINGERPRINT="${FINGERPRINT:-$(output_field_value '指纹')}"
  SERVER_IP="${SERVER_IP:-$(guess_server_ip)}"
  FINGERPRINT="${FINGERPRINT:-${DEFAULT_FINGERPRINT}}"
  CERT_MODE="${CERT_MODE:-existing}"
  ACME_CA="${ACME_CA:-${DEFAULT_ACME_CA}}"
  XHTTP_ECH_CONFIG_LIST="${XHTTP_ECH_CONFIG_LIST:-${DEFAULT_XHTTP_ECH_CONFIG_LIST}}"
  XHTTP_ECH_FORCE_QUERY="${XHTTP_ECH_FORCE_QUERY:-${DEFAULT_XHTTP_ECH_FORCE_QUERY}}"
  ENABLE_NET_OPT="${ENABLE_NET_OPT:-$(if [[ -f "${NET_SERVICE_FILE}" || -f "${NET_SYSCTL_CONF}" ]]; then printf 'yes'; else printf 'no'; fi)}"
  WARP_PROXY_PORT="${WARP_PROXY_PORT:-${DEFAULT_WARP_PROXY_PORT}}"
  NODE_LABEL_PREFIX="${NODE_LABEL_PREFIX:-$(default_node_label_prefix)}"
  if [[ "${XHTTP_VLESS_DECRYPTION:-}" == "none" || -z "${XHTTP_VLESS_DECRYPTION:-}" ]]; then
    XHTTP_VLESS_ENCRYPTION_ENABLED="${XHTTP_VLESS_ENCRYPTION_ENABLED:-no}"
  else
    XHTTP_VLESS_ENCRYPTION_ENABLED="${XHTTP_VLESS_ENCRYPTION_ENABLED:-yes}"
  fi

  [[ -n "${REALITY_UUID}" ]] || die "无法从当前安装中识别 REALITY UUID。"
  [[ -n "${REALITY_SNI}" ]] || die "无法从当前安装中识别 REALITY SNI。"
  [[ -n "${REALITY_TARGET}" ]] || die "无法从当前安装中识别 REALITY 目标地址。"
  [[ -n "${REALITY_SHORT_ID}" ]] || die "无法从当前安装中识别 REALITY 短 ID。"
  [[ -n "${REALITY_PRIVATE_KEY}" ]] || die "无法从当前安装中识别 REALITY 私钥。"
  [[ -n "${XHTTP_UUID}" ]] || die "无法从当前安装中识别 XHTTP UUID。"
  [[ -n "${XHTTP_DOMAIN}" ]] || die "无法从当前安装中识别 XHTTP 域名。"
  [[ -n "${XHTTP_PATH}" ]] || die "无法从当前安装中识别 XHTTP 路径。"
}

install_packages() {
  log "正在安装依赖包。"
  apt-get update
  apt-get install -y ca-certificates curl gnupg haproxy nginx iproute2 jq kmod openssl unzip uuid-runtime libcap2-bin
}

install_xray() {
  local arch=""
  local tmp_dir=""
  local download_url=""

  arch="$(detect_xray_arch)"
  download_url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${arch}.zip"
  tmp_dir="$(mktemp -d)"

  log "正在下载 Xray-core。"
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

ensure_xray_bind_capability() {
  if command -v setcap >/dev/null 2>&1; then
    setcap cap_net_bind_service=+ep "${XRAY_BIN}" || die "为 Xray 二进制设置 CAP_NET_BIND_SERVICE 失败。"
  else
    warn "系统中未找到 setcap，Xray 可能无法以普通用户绑定 443。"
  fi
}

ensure_managed_permissions() {
  [[ -n "${XRAY_UID}" && -n "${XRAY_GID}" ]] || die "尚未解析 xray 用户的 UID/GID。"

  if [[ -f "${XRAY_CONFIG_FILE}" ]]; then
    chown 0:"${XRAY_GID}" "${XRAY_CONFIG_FILE}"
    chmod 0640 "${XRAY_CONFIG_FILE}"
  fi

  if [[ -f "${TLS_CERT_FILE}" ]]; then
    chown 0:"${XRAY_GID}" "${TLS_CERT_FILE}"
    chmod 0640 "${TLS_CERT_FILE}"
  fi

  if [[ -f "${TLS_KEY_FILE}" ]]; then
    chown 0:"${XRAY_GID}" "${TLS_KEY_FILE}"
    chmod 0640 "${TLS_KEY_FILE}"
  fi

  if [[ -d "${SSL_DIR}" ]]; then
    chown 0:"${XRAY_GID}" "${SSL_DIR}"
    chmod 0750 "${SSL_DIR}"
  fi

  if [[ -d /var/log/xray ]]; then
    chown "${XRAY_UID}:${XRAY_GID}" /var/log/xray
    chmod 0750 /var/log/xray
    if [[ -f /var/log/xray/access.log ]]; then
      chown "${XRAY_UID}:${XRAY_GID}" /var/log/xray/access.log
      chmod 0640 /var/log/xray/access.log
    fi
    if [[ -f /var/log/xray/error.log ]]; then
      chown "${XRAY_UID}:${XRAY_GID}" /var/log/xray/error.log
      chmod 0640 /var/log/xray/error.log
    fi
  fi
}

ensure_xray_user() {
  if ! id -u xray >/dev/null 2>&1; then
    useradd --system --home /var/lib/xray --create-home --shell /usr/sbin/nologin xray
  fi

  XRAY_UID="$(id -u xray)"
  XRAY_GID="$(id -g xray)"
  [[ -n "${XRAY_UID}" && -n "${XRAY_GID}" ]] || die "无法解析 xray 用户的 UID/GID。"

  mkdir -p "${XRAY_CONFIG_DIR}" "${XRAY_ASSET_DIR}"
  install -d -o "${XRAY_UID}" -g "${XRAY_GID}" -m 0750 /var/log/xray
  install -d -o 0 -g "${XRAY_GID}" -m 0750 "${SSL_DIR}"
  ensure_managed_permissions
}

generate_reality_keys_if_needed() {
  local key_output=""

  if [[ -n "${REALITY_PRIVATE_KEY}" && -n "${REALITY_PUBLIC_KEY}" ]]; then
    return
  fi

  if [[ -n "${REALITY_PRIVATE_KEY}" && -z "${REALITY_PUBLIC_KEY}" ]]; then
    key_output="$("${XRAY_BIN}" x25519 -i "${REALITY_PRIVATE_KEY}")"
    REALITY_PUBLIC_KEY="$(printf '%s\n' "${key_output}" | awk '
      /^(Password \(PublicKey\)|Public key|PublicKey):/ {
        sub(/^[^:]+:[[:space:]]*/, "", $0)
        print
        exit
      }
    ')"
    [[ -n "${REALITY_PUBLIC_KEY}" ]] || die "无法从提供的 REALITY 私钥推导公钥。"
    return
  fi

  key_output="$("${XRAY_BIN}" x25519)"
  REALITY_PRIVATE_KEY="$(printf '%s\n' "${key_output}" | awk '
    /^(Private key|PrivateKey):/ {
      sub(/^[^:]+:[[:space:]]*/, "", $0)
      print
      exit
    }
  ')"
  REALITY_PUBLIC_KEY="$(printf '%s\n' "${key_output}" | awk '
    /^(Password \(PublicKey\)|Public key|PublicKey):/ {
      sub(/^[^:]+:[[:space:]]*/, "", $0)
      print
      exit
    }
  ')"

  [[ -n "${REALITY_PRIVATE_KEY}" ]] || die "生成 REALITY 私钥失败。"
  [[ -n "${REALITY_PUBLIC_KEY}" ]] || die "生成 REALITY 公钥失败。"
}

generate_xhttp_vless_encryption_if_needed() {
  local enc_output=""

  if [[ "${XHTTP_VLESS_ENCRYPTION_ENABLED}" != "yes" ]]; then
    XHTTP_VLESS_DECRYPTION=""
    XHTTP_VLESS_ENCRYPTION=""
    return
  fi

  if [[ -n "${XHTTP_VLESS_DECRYPTION}" && -n "${XHTTP_VLESS_ENCRYPTION}" ]]; then
    return
  fi

  enc_output="$("${XRAY_BIN}" vlessenc)"
  XHTTP_VLESS_DECRYPTION="$(printf '%s\n' "${enc_output}" | awk -F'"' '/"decryption":/ {print $4; exit}')"
  XHTTP_VLESS_ENCRYPTION="$(printf '%s\n' "${enc_output}" | awk -F'"' '/"encryption":/ {print $4; exit}')"

  [[ -n "${XHTTP_VLESS_DECRYPTION}" ]] || die "生成 XHTTP 的 VLESS decryption 失败。"
  [[ -n "${XHTTP_VLESS_ENCRYPTION}" ]] || die "生成 XHTTP 的 VLESS encryption 失败。"
}

prepare_install_inputs() {
  local guessed_ip=""

  guessed_ip="$(guess_server_ip)"

  prompt_with_default SERVER_IP "REALITY 直连节点地址或 IP" "${guessed_ip}"
  prompt_with_default NODE_LABEL_PREFIX "导出链接使用的节点名前缀" "$(default_node_label_prefix)"
  prompt_with_default REALITY_UUID "REALITY UUID" "$(random_uuid)"
  prompt_with_default REALITY_SNI "REALITY 可见 SNI" "${DEFAULT_REALITY_SNI}"
  prompt_with_default REALITY_TARGET "REALITY 目标地址 host:port" "$(default_reality_target_for_sni "${REALITY_SNI}")"
  prompt_with_default REALITY_SHORT_ID "REALITY 短 ID" "$(random_hex 8)"
  prompt_with_default XHTTP_UUID "XHTTP UUID" "$(random_uuid)"
  prompt_with_default XHTTP_DOMAIN "XHTTP CDN 域名" ""
  prompt_with_default XHTTP_PATH "XHTTP 路径" "$(random_path)"
  prompt_yes_no XHTTP_VLESS_ENCRYPTION_ENABLED "是否启用 XHTTP CDN 的 VLESS Encryption？ [y/n]" "y"
  XHTTP_VLESS_ENCRYPTION_ENABLED="$(normalize_yes_no_value "XHTTP_VLESS_ENCRYPTION_ENABLED" "${XHTTP_VLESS_ENCRYPTION_ENABLED}")"
  prompt_with_default CERT_MODE "TLS 证书模式（自签名/self-signed，现有证书/existing，Cloudflare Origin CA/cf-origin-ca，ACME DNS/acme-dns-cf）" "self-signed"
  CERT_MODE="$(validate_cert_mode_value "${CERT_MODE}")"
  prompt_cert_mode_inputs

  prompt_yes_no ENABLE_NET_OPT "是否启用网络优化？ [y/n]" "y"
  ENABLE_NET_OPT="$(normalize_yes_no_value "ENABLE_NET_OPT" "${ENABLE_NET_OPT}")"

  NODE_LABEL_PREFIX="$(normalize_node_label_prefix "${NODE_LABEL_PREFIX}")"

  prompt_yes_no ENABLE_WARP "是否启用选择性 WARP 出站？ [y/n]" "y"
  ENABLE_WARP="$(normalize_yes_no_value "ENABLE_WARP" "${ENABLE_WARP}")"
  if [[ "${ENABLE_WARP}" == "yes" ]]; then
    prompt_warp_settings
  fi
}

default_reality_target_for_sni() {
  local sni="${1}"
  printf '%s:443' "${sni}"
}

normalize_yes_no_value() {
  local field_name="${1}"
  local raw_value="${2}"
  local value=""

  value="$(printf '%s' "${raw_value}" | tr 'A-Z' 'a-z')"
  case "${value}" in
    y|yes|enable|enabled)
      printf 'yes'
      ;;
    n|no|disable|disabled)
      printf 'no'
      ;;
    *)
      die "${field_name} 只能是 yes 或 no。"
      ;;
  esac
}

normalize_warp_target_mode() {
  local value=""

  value="$(printf '%s' "${1}" | tr 'A-Z' 'a-z')"
  case "${value}" in
    yes|enable|enabled)
      printf 'enable'
      ;;
    no|disable|disabled)
      printf 'disable'
      ;;
    *)
      die "WARP 操作只能是 enable 或 disable。"
      ;;
  esac
}

validate_cert_mode_value() {
  local value=""

  value="$(normalize_cert_mode "${1}")"
  case "${value}" in
    self-signed|existing|cf-origin-ca|acme-dns-cf)
      printf '%s' "${value}"
      ;;
    *)
      die "不支持的证书模式：${1}"
      ;;
  esac
}

prompt_warp_settings() {
  prompt_with_default WARP_TEAM_NAME "Cloudflare Zero Trust 团队名" "${WARP_TEAM_NAME:-}"
  prompt_with_default WARP_CLIENT_ID "Cloudflare 服务令牌 Client ID" "${WARP_CLIENT_ID:-}"
  prompt_secret WARP_CLIENT_SECRET "Cloudflare 服务令牌 Client Secret"
  prompt_with_default WARP_PROXY_PORT "本地 WARP SOCKS5 端口" "${WARP_PROXY_PORT:-${DEFAULT_WARP_PROXY_PORT}}"
}

clear_existing_cert_inputs() {
  CERT_SOURCE_FILE=""
  KEY_SOURCE_FILE=""
  CERT_SOURCE_PEM=""
  KEY_SOURCE_PEM=""
}

clear_cf_origin_ca_settings() {
  CF_ZONE_ID=""
  CF_API_TOKEN=""
  CF_CERT_VALIDITY="${DEFAULT_CF_CERT_VALIDITY}"
}

clear_acme_dns_cf_settings() {
  ACME_EMAIL=""
  ACME_CA="${DEFAULT_ACME_CA}"
  CF_DNS_TOKEN=""
  CF_DNS_ACCOUNT_ID=""
  CF_DNS_ZONE_ID=""
}

prompt_cf_origin_ca_inputs() {
  prompt_with_default CF_ZONE_ID "Cloudflare Zone ID" "${CF_ZONE_ID:-}"
  prompt_with_default CF_CERT_VALIDITY "Cloudflare Origin CA 有效期（天）" "${CF_CERT_VALIDITY:-${DEFAULT_CF_CERT_VALIDITY}}"
  prompt_secret CF_API_TOKEN "Cloudflare API 令牌"
}

prompt_optional_cloudflare_scope() {
  if [[ -z "${CF_DNS_ACCOUNT_ID}" && "${NON_INTERACTIVE}" -eq 0 ]]; then
    read -r -p "Cloudflare Account ID（可选）: " CF_DNS_ACCOUNT_ID
  fi
  if [[ -z "${CF_DNS_ZONE_ID}" && "${NON_INTERACTIVE}" -eq 0 ]]; then
    read -r -p "Cloudflare DNS API 使用的 Zone ID（可选）: " CF_DNS_ZONE_ID
  fi
}

prompt_acme_dns_cf_inputs() {
  prompt_with_default ACME_EMAIL "acme.sh 账户邮箱" "${ACME_EMAIL:-}"
  prompt_with_default ACME_CA "ACME CA" "${ACME_CA:-${DEFAULT_ACME_CA}}"
  prompt_secret CF_DNS_TOKEN "Cloudflare DNS API 令牌"
  prompt_optional_cloudflare_scope
}

ensure_xhttp_path_format() {
  [[ -n "${XHTTP_PATH}" ]] || die "XHTTP 路径不能为空。"
  [[ "${XHTTP_PATH}" == /* ]] || die "XHTTP 路径必须以 / 开头。"
}

prompt_cert_mode_inputs() {
  case "${CERT_MODE}" in
    self-signed)
      clear_existing_cert_inputs
      clear_cf_origin_ca_settings
      clear_acme_dns_cf_settings
      ;;
    existing)
      prepare_existing_cert_inputs
      clear_cf_origin_ca_settings
      clear_acme_dns_cf_settings
      ;;
    cf-origin-ca)
      clear_existing_cert_inputs
      prompt_cf_origin_ca_inputs
      clear_acme_dns_cf_settings
      ;;
    acme-dns-cf)
      clear_existing_cert_inputs
      clear_cf_origin_ca_settings
      prompt_acme_dns_cf_inputs
      ;;
    *)
      die "不支持的证书模式：${CERT_MODE}"
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

  [[ -n "${CF_ZONE_ID}" ]] || die "cf-origin-ca 模式必须提供 CF_ZONE_ID。"
  [[ -n "${CF_API_TOKEN}" ]] || die "cf-origin-ca 模式必须提供 CF_API_TOKEN。"

  csr_file="$(mktemp)"
  openssl ecparam -name prime256v1 -genkey -noout -out "${TLS_KEY_FILE}"
  chmod 0640 "${TLS_KEY_FILE}"
  write_cf_origin_csr "${csr_file}"
  csr_json="$(jq -Rs . < "${csr_file}")"

  response="$(curl -fsSL https://api.cloudflare.com/client/v4/certificates \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    --data "{\"csr\":${csr_json},\"hostnames\":[\"${XHTTP_DOMAIN}\"],\"request_type\":\"origin-ecc\",\"requested_validity\":${CF_CERT_VALIDITY}}" \
  )" || die "调用 Cloudflare Origin CA API 失败。"

  cert_body="$(printf '%s' "${response}" | jq -r '.result.certificate // empty')"
  if [[ -z "${cert_body}" ]]; then
    error_text="$(printf '%s' "${response}" | jq -r '.errors[0].message // .messages[0].message // "未知的 Cloudflare API 错误"')"
    die "Cloudflare Origin CA API 未返回证书：${error_text}"
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
    warn "无法自动把 Cloudflare SSL/TLS 模式切到 strict，请手动检查 Zone 设置。"
  fi
}

write_acme_reload_helper() {
  local tmp_file=""

  tmp_file="$(mktemp)"
  cat > "${tmp_file}" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -f "${TLS_CERT_FILE}" && -f "${TLS_KEY_FILE}" ]]; then
  chown 0:${XRAY_GID} "${TLS_CERT_FILE}" "${TLS_KEY_FILE}" 2>/dev/null || true
  chmod 0640 "${TLS_CERT_FILE}" "${TLS_KEY_FILE}" 2>/dev/null || true
fi

systemctl restart xray >/dev/null 2>&1 || true
systemctl restart nginx >/dev/null 2>&1 || true
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

  [[ -n "${ACME_EMAIL}" ]] || die "acme-dns-cf 模式必须提供 ACME_EMAIL。"
  tmp_file="$(mktemp)"
  curl -fsSL https://get.acme.sh -o "${tmp_file}"
  sh "${tmp_file}" email="${ACME_EMAIL}" >/dev/null
  rm -f "${tmp_file}"
  [[ -x "${ACME_SH_BIN}" ]] || die "acme.sh 安装失败。"
}

issue_acme_cf_cert() {
  [[ -n "${ACME_EMAIL}" ]] || die "acme-dns-cf 模式必须提供 ACME_EMAIL。"
  [[ -n "${CF_DNS_TOKEN}" ]] || die "acme-dns-cf 模式必须提供 CF_DNS_TOKEN。"

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

validate_tls_assets() {
  local cert_pub_hash=""
  local key_pub_hash=""

  openssl x509 -in "${TLS_CERT_FILE}" -noout >/dev/null 2>&1 || die "写入后的证书内容无效：${TLS_CERT_FILE}"
  openssl pkey -in "${TLS_KEY_FILE}" -noout >/dev/null 2>&1 || die "写入后的私钥内容无效：${TLS_KEY_FILE}"

  cert_pub_hash="$(openssl x509 -in "${TLS_CERT_FILE}" -pubkey -noout 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null | sha256sum | awk '{print $1}')"
  key_pub_hash="$(openssl pkey -in "${TLS_KEY_FILE}" -pubout -outform DER 2>/dev/null | sha256sum | awk '{print $1}')"

  [[ -n "${cert_pub_hash}" && -n "${key_pub_hash}" ]] || die "无法校验证书与私钥是否匹配。"
  [[ "${cert_pub_hash}" == "${key_pub_hash}" ]] || die "证书与私钥不匹配，请检查输入内容。"
}

write_tls_assets() {
  local tls_config=""

  mkdir -p "${SSL_DIR}"
  backup_path "${TLS_CERT_FILE}"
  backup_path "${TLS_KEY_FILE}"

  if [[ "${CERT_MODE}" == "existing" ]]; then
    if [[ -n "${CERT_SOURCE_FILE}" || -n "${KEY_SOURCE_FILE}" ]]; then
      [[ -f "${CERT_SOURCE_FILE}" ]] || die "找不到证书文件：${CERT_SOURCE_FILE}"
      [[ -f "${KEY_SOURCE_FILE}" ]] || die "找不到私钥文件：${KEY_SOURCE_FILE}"

      install -o 0 -g "${XRAY_GID}" -m 0640 "${CERT_SOURCE_FILE}" "${TLS_CERT_FILE}"
      install -o 0 -g "${XRAY_GID}" -m 0640 "${KEY_SOURCE_FILE}" "${TLS_KEY_FILE}"
    else
      [[ -n "${CERT_SOURCE_PEM}" ]] || die "existing 模式下缺少证书 PEM 内容。"
      [[ -n "${KEY_SOURCE_PEM}" ]] || die "existing 模式下缺少私钥 PEM 内容。"

      printf '%s\n' "${CERT_SOURCE_PEM}" > "${TLS_CERT_FILE}"
      printf '%s\n' "${KEY_SOURCE_PEM}" > "${TLS_KEY_FILE}"
      chmod 0640 "${TLS_CERT_FILE}" "${TLS_KEY_FILE}"
    fi
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

  ensure_managed_permissions
  validate_tls_assets

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
    warn "当前内核未暴露 BBR 支持，已跳过网络优化。"
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

xray_log_json() {
  cat <<'EOF'
{
  "loglevel": "warning",
  "access": "/var/log/xray/access.log",
  "error": "/var/log/xray/error.log"
}
EOF
}

xray_sniffing_json() {
  cat <<'EOF'
{
  "enabled": true,
  "destOverride": [
    "http",
    "tls",
    "quic"
  ],
  "metadataOnly": false,
  "routeOnly": true
}
EOF
}

xray_reality_inbound_json() {
  local sniffing_json=""

  sniffing_json="$(xray_sniffing_json)"
  cat <<EOF
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
    "decryption": "none",
    "fallbacks": [
      {
        "dest": "${XHTTP_LOCAL_PORT}",
        "xver": 0
      }
    ]
  },
  "streamSettings": {
    "network": "raw",
    "security": "reality",
    "realitySettings": {
      "show": false,
      "target": "${REALITY_TARGET}",
      "xver": 0,
      "serverNames": [
        "${REALITY_SNI}"
      ],
      "privateKey": "${REALITY_PRIVATE_KEY}",
      "shortIds": [
        "${REALITY_SHORT_ID}"
      ]
    }
  },
  "sniffing": ${sniffing_json}
}
EOF
}

xray_xhttp_inbound_json() {
  local sniffing_json=""

  sniffing_json="$(xray_sniffing_json)"
  cat <<EOF
{
  "tag": "xhttp-cdn",
  "listen": "127.0.0.1",
  "port": ${XHTTP_LOCAL_PORT},
  "protocol": "vless",
  "settings": {
    "clients": [
      {
        "id": "${XHTTP_UUID}",
        "email": "xhttp-cdn"
      }
    ],
    "decryption": "${XHTTP_VLESS_DECRYPTION:-none}"
  },
  "streamSettings": {
    "network": "xhttp",
    "xhttpSettings": {
      "host": "",
      "path": "${XHTTP_PATH}",
      "mode": "auto"
    }
  },
  "sniffing": ${sniffing_json}
}
EOF
}

xray_inbounds_json() {
  cat <<EOF
[
  $(xray_reality_inbound_json),
  $(xray_xhttp_inbound_json)
]
EOF
}

xray_direct_domains_json() {
  cat <<'EOF'
[
  "domain:telegram.org",
  "domain:api.telegram.org",
  "domain:t.me",
  "domain:telegram.me",
  "domain:core.telegram.org"
]
EOF
}

xray_warp_domains_json() {
  cat <<'EOF'
[
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
EOF
}

xray_routing_rules_json() {
  local direct_domains=""
  local warp_domains=""

  if [[ "${ENABLE_WARP}" != "yes" ]]; then
    cat <<'EOF'
[]
EOF
    return
  fi

  direct_domains="$(xray_direct_domains_json)"
  warp_domains="$(xray_warp_domains_json)"
  cat <<EOF
[
  {
    "type": "field",
    "outboundTag": "direct",
    "domain": ${direct_domains}
  },
  {
    "type": "field",
    "outboundTag": "WARP",
    "domain": ${warp_domains}
  }
]
EOF
}

xray_direct_outbound_json() {
  cat <<'EOF'
{
  "tag": "direct",
  "protocol": "freedom"
}
EOF
}

xray_block_outbound_json() {
  cat <<'EOF'
{
  "tag": "block",
  "protocol": "blackhole"
}
EOF
}

xray_warp_outbound_json() {
  cat <<EOF
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
}
EOF
}

xray_outbounds_json() {
  local direct_outbound=""
  local block_outbound=""
  local warp_outbound=""

  direct_outbound="$(xray_direct_outbound_json)"
  block_outbound="$(xray_block_outbound_json)"
  if [[ "${ENABLE_WARP}" != "yes" ]]; then
    cat <<EOF
[
  ${direct_outbound},
  ${block_outbound}
]
EOF
    return
  fi

  warp_outbound="$(xray_warp_outbound_json)"
  cat <<EOF
[
  ${direct_outbound},
  ${warp_outbound},
  ${block_outbound}
]
EOF
}

write_xray_config() {
  local log_json=""
  local inbounds=""
  local routing_rules=""
  local outbounds=""

  backup_path "${XRAY_CONFIG_FILE}"
  generate_xhttp_vless_encryption_if_needed
  log_json="$(xray_log_json)"
  inbounds="$(xray_inbounds_json)"
  routing_rules="$(xray_routing_rules_json)"
  outbounds="$(xray_outbounds_json)"

  cat > "${XRAY_CONFIG_FILE}" <<EOF
{
  "log": ${log_json},
  "inbounds": ${inbounds},
  "routing": {
    "domainStrategy": "AsIs",
    "rules": ${routing_rules}
  },
  "outbounds": ${outbounds}
}
EOF

  ensure_managed_permissions
}

nginx_proxy_headers_config() {
  cat <<'EOF'
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
EOF
}

nginx_fallback_location_config() {
  local proxy_headers=""

  proxy_headers="$(nginx_proxy_headers_config)"
  cat <<EOF
    location / {
        proxy_pass https://www.harvard.edu;
        proxy_set_header Host www.harvard.edu;
${proxy_headers}
    }
EOF
}

nginx_xhttp_location_config() {
  cat <<EOF
    location ${XHTTP_PATH} {
        grpc_pass 127.0.0.1:${XHTTP_LOCAL_PORT};
        grpc_set_header Host \$host;
        grpc_set_header X-Real-IP \$remote_addr;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        grpc_set_header X-Forwarded-Proto \$scheme;
        grpc_set_header X-Forwarded-Host \$host;
    }
EOF
}

nginx_server_config() {
  local fallback_location=""
  local xhttp_location=""

  fallback_location="$(nginx_fallback_location_config)"
  xhttp_location="$(nginx_xhttp_location_config)"
  cat <<EOF
server {
    listen 127.0.0.1:${NGINX_TLS_PORT} ssl;
    http2 on;
    server_name ${XHTTP_DOMAIN};

    ssl_certificate ${TLS_CERT_FILE};
    ssl_certificate_key ${TLS_KEY_FILE};

${fallback_location}

${xhttp_location}
}
EOF
}

write_nginx_config() {
  mkdir -p "${NGINX_CONF_DIR}"
  backup_path "${NGINX_CONFIG_FILE}"

  nginx_server_config > "${NGINX_CONFIG_FILE}"
}

haproxy_global_config() {
  cat <<'EOF'
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon
    user haproxy
    group haproxy
    maxconn 20000
EOF
}

haproxy_defaults_config() {
  cat <<'EOF'
defaults
    log global
    mode tcp
    option tcplog
    timeout connect 5s
    timeout client 2m
    timeout server 2m
EOF
}

haproxy_frontend_config() {
  cat <<EOF
frontend fe_tls_shared_443
    bind :443
    mode tcp
    tcp-request inspect-delay 5s
    tcp-request content accept if { req.ssl_hello_type 1 }

    use_backend be_xhttp_cdn if { req.ssl_sni -i ${XHTTP_DOMAIN} }
    default_backend be_reality_vision
EOF
}

haproxy_xhttp_backend_config() {
  cat <<EOF
backend be_xhttp_cdn
    mode tcp
    server nginx_cdn 127.0.0.1:${NGINX_TLS_PORT} check
EOF
}

haproxy_reality_backend_config() {
  cat <<'EOF'
backend be_reality_vision
    mode tcp
    server reality_vision 127.0.0.1:2443 check
EOF
}

haproxy_config_text() {
  cat <<EOF
$(haproxy_global_config)

$(haproxy_defaults_config)

$(haproxy_frontend_config)

$(haproxy_xhttp_backend_config)

$(haproxy_reality_backend_config)
EOF
}

write_haproxy_config() {
  backup_path "${HAPROXY_CONFIG}"
  haproxy_config_text > "${HAPROXY_CONFIG}"
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
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
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
  [[ -n "${repo_codename}" ]] || die "VERSION_CODENAME 为空，无法安装 Cloudflare WARP。"

  key_tmp="$(mktemp)"
  log "正在安装 Cloudflare WARP 客户端。"
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
  log "正在校验 Xray 配置。"
  "${XRAY_BIN}" run -test -config "${XRAY_CONFIG_FILE}"

  log "正在校验 Nginx 配置。"
  nginx -t

  log "正在校验 HAProxy 配置。"
  haproxy -c -f "${HAPROXY_CONFIG}"
}

restart_services() {
  ensure_xray_user
  ensure_managed_permissions
  systemctl daemon-reload
  systemctl enable --now xray
  systemctl enable --now haproxy
  systemctl enable --now nginx
  systemctl restart xray
  systemctl restart haproxy
  systemctl restart nginx

  if [[ "${ENABLE_WARP}" == "yes" ]]; then
    systemctl enable --now warp-svc
  fi
}

finalize_installation() {
  validate_configs
  restart_services
  write_state_file
  write_output_file
}

restart_core_services() {
  ensure_xray_user
  ensure_managed_permissions
  systemctl restart xray
  systemctl restart haproxy
  systemctl restart nginx
}

write_runtime_managed_files() {
  write_xray_config
  write_haproxy_config
  write_nginx_config
}

apply_managed_files() {
  local include_tls_assets="${1:-no}"

  if [[ "${include_tls_assets}" == "yes" ]]; then
    write_tls_assets
  fi

  write_runtime_managed_files
  validate_configs
  restart_core_services
  write_state_file
  write_output_file
}

install_self_command() {
  local source_path="$0"
  local source_real=""
  local target_real=""

  if [[ -f "${source_path}" ]]; then
    source_real="$(readlink -f "${source_path}" 2>/dev/null || printf '%s' "${source_path}")"
    target_real="$(readlink -f "${SELF_COMMAND_PATH}" 2>/dev/null || printf '%s' "${SELF_COMMAND_PATH}")"
    if [[ "${source_real}" != "${target_real}" ]]; then
      install -m 0755 "${source_path}" "${SELF_COMMAND_PATH}"
    fi
  else
    warn "无法写入持久化管理命令，因为当前脚本路径不可用。"
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
  apply_managed_files "yes"
}

apply_managed_runtime_update() {
  apply_managed_files "no"
}

handle_change_common_arg() {
  case "${1}" in
    --non-interactive)
      NON_INTERACTIVE=1
      return 0
      ;;
    --help|-h|help)
      usage
      exit 0
      ;;
  esac

  return 1
}

require_option_value() {
  local option_name="${1}"

  shift
  [[ $# -gt 0 ]] || die "参数 ${option_name} 需要值。"
}

assign_option_value() {
  local var_name="${1}"
  local option_name="${2}"

  shift 2
  require_option_value "${option_name}" "$@"
  printf -v "${var_name}" '%s' "${1}"
}

request_value_presence_key() {
  printf '%s__set' "${1}"
}

apply_optional_override() {
  local var_name="${1}"
  local value="${2-}"
  local overridden="${3:-0}"

  if [[ "${overridden}" != "1" && -z "${value}" ]]; then
    return 0
  fi
  printf -v "${var_name}" '%s' "${value}"
}

resolve_change_value() {
  local var_name="${1}"
  local prompt_text="${2}"
  local default_value="${3}"
  local overridden="${4}"
  local explicit_value="${5:-}"

  if [[ "${overridden}" -eq 1 ]]; then
    printf -v "${var_name}" '%s' "${explicit_value}"
    return
  fi

  printf -v "${var_name}" '%s' ""
  prompt_with_default "${var_name}" "${prompt_text}" "${default_value}"
}

resolve_cert_mode_change_targets() {
  local old_cert_mode="${1}"
  local old_xhttp_domain="${2}"
  local cert_mode_overridden="${3}"
  local xhttp_domain_overridden="${4}"
  local new_cert_mode="${5:-}"
  local new_xhttp_domain="${6:-}"

  resolve_change_value CERT_MODE "新的证书模式 (self-signed/existing/cf-origin-ca/acme-dns-cf)" "${old_cert_mode}" "${cert_mode_overridden}" "${new_cert_mode}"
  CERT_MODE="$(validate_cert_mode_value "${CERT_MODE}")"
  resolve_change_value XHTTP_DOMAIN "XHTTP CDN 域名" "${old_xhttp_domain}" "${xhttp_domain_overridden}" "${new_xhttp_domain}"
}

apply_request_literal_spec() {
  local -n request_ref="${1}"
  local option="${2}"
  local spec="${3}"
  local spec_option=""
  local request_key=""
  local request_value=""

  IFS=':' read -r spec_option request_key request_value <<< "${spec}"
  [[ "${option}" == "${spec_option}" ]] || return 1
  request_ref["${request_key}"]="${request_value}"
  return 0
}

apply_request_value_spec() {
  local -n request_ref="${1}"
  local option="${2}"
  local spec="${3}"
  local spec_option=""
  local request_key=""
  local override_key=""

  shift 3
  IFS=':' read -r spec_option request_key override_key <<< "${spec}"
  [[ "${option}" == "${spec_option}" ]] || return 1
  require_option_value "${option}" "$@"
  request_ref["${request_key}"]="${1}"
  if [[ -z "${override_key}" ]]; then
    override_key="$(request_value_presence_key "${request_key}")"
  fi
  request_ref["${override_key}"]="1"
  return 0
}

parse_request_args_by_specs() {
  local request_name="${1}"
  local -n request_ref="${request_name}"
  local -n literal_specs_ref="${2}"
  local -n value_specs_ref="${3}"
  local unknown_arg_message="${4}"
  local consumed=0
  local spec=""

  shift 4
  while [[ $# -gt 0 ]]; do
    if handle_change_common_arg "${1}"; then
      shift
      continue
    fi

    consumed=0
    for spec in "${literal_specs_ref[@]}"; do
      if apply_request_literal_spec "${request_name}" "${1}" "${spec}"; then
        consumed=1
        break
      fi
    done

    if [[ "${consumed}" -eq 0 ]]; then
      for spec in "${value_specs_ref[@]}"; do
        if apply_request_value_spec "${request_name}" "${1}" "${spec}" "${@:2}"; then
          consumed=2
          break
        fi
      done
    fi

    [[ "${consumed}" -gt 0 ]] || die "${unknown_arg_message}${1}"
    shift "${consumed}"
  done
}

apply_request_overrides() {
  local -n request_ref="${1}"
  local spec=""
  local request_key=""
  local target_var=""
  local override_key=""

  shift
  for spec in "$@"; do
    IFS=':' read -r request_key target_var override_key <<< "${spec}"
    if [[ -z "${override_key}" ]]; then
      override_key="$(request_value_presence_key "${request_key}")"
    fi
    apply_optional_override "${target_var}" "${request_ref[${request_key}]-}" "${request_ref[${override_key}]-0}"
  done
}

init_change_warp_request() {
  local -n request_ref="${1}"

  request_ref=(
    [target_mode]=""
    [warp_team_name]=""
    [warp_client_id]=""
    [warp_client_secret]=""
    [warp_proxy_port]=""
  )
}

parse_change_warp_args() {
  local request_name="${1}"
  local literal_specs=(
    "--enable-warp:target_mode:enable"
    "--disable-warp:target_mode:disable"
  )
  local value_specs=(
    "--warp-team:warp_team_name"
    "--warp-client-id:warp_client_id"
    "--warp-client-secret:warp_client_secret"
    "--warp-proxy-port:warp_proxy_port"
  )

  parse_request_args_by_specs "${request_name}" literal_specs value_specs "未知的 change-warp 参数：" "${@:2}"
}

apply_warp_change_request() {
  local request_name="${1}"

  apply_request_overrides "${request_name}" \
    "warp_team_name:WARP_TEAM_NAME" \
    "warp_client_id:WARP_CLIENT_ID" \
    "warp_client_secret:WARP_CLIENT_SECRET" \
    "warp_proxy_port:WARP_PROXY_PORT"
}

resolve_change_warp_target_mode() {
  local requested_mode="${1:-}"

  if [[ -z "${requested_mode}" ]]; then
    if [[ "${NON_INTERACTIVE}" -eq 1 ]]; then
      die "change-warp 在非交互模式下必须显式传入 --enable-warp 或 --disable-warp。"
    fi

    read -r -p "请选择 WARP 操作 [enable/disable] [${ENABLE_WARP:-yes}]: " requested_mode
    requested_mode="${requested_mode:-${ENABLE_WARP:-yes}}"
  fi

  normalize_warp_target_mode "${requested_mode}"
}

run_change_warp_action() {
  local target_mode="${1}"

  case "${target_mode}" in
    enable)
      ENABLE_WARP="yes"
      prompt_warp_settings
      install_warp
      apply_managed_runtime_update
      finish_managed_change "WARP 分流已启用。"
      ;;
    disable)
      ENABLE_WARP="no"
      apply_managed_runtime_update
      stop_and_disable_service_if_present "warp-svc.service"
      finish_managed_change "WARP 分流已禁用。"
      ;;
    *)
      die "WARP 操作只能是 enable 或 disable。"
      ;;
  esac
}

init_change_cert_mode_request() {
  local -n request_ref="${1}"

  request_ref=(
    [cert_mode_overridden]="0"
    [xhttp_domain_overridden]="0"
    [cert_mode]=""
    [xhttp_domain]=""
    [cert_source_file]=""
    [key_source_file]=""
    [cert_source_pem]=""
    [key_source_pem]=""
    [cf_zone_id]=""
    [cf_api_token]=""
    [cf_cert_validity]=""
    [acme_email]=""
    [acme_ca]=""
    [cf_dns_token]=""
    [cf_dns_account_id]=""
    [cf_dns_zone_id]=""
  )
}

parse_change_cert_mode_args() {
  local request_name="${1}"
  local literal_specs=()
  local value_specs=(
    "--cert-mode:cert_mode:cert_mode_overridden"
    "--xhttp-domain:xhttp_domain:xhttp_domain_overridden"
    "--cert-file:cert_source_file"
    "--key-file:key_source_file"
    "--cert-pem:cert_source_pem"
    "--key-pem:key_source_pem"
    "--cf-zone-id:cf_zone_id"
    "--cf-api-token:cf_api_token"
    "--cf-cert-validity:cf_cert_validity"
    "--acme-email:acme_email"
    "--acme-ca:acme_ca"
    "--cf-dns-token:cf_dns_token"
    "--cf-dns-account-id:cf_dns_account_id"
    "--cf-dns-zone-id:cf_dns_zone_id"
  )

  parse_request_args_by_specs "${request_name}" literal_specs value_specs "未知的 change-cert-mode 参数：" "${@:2}"
}

apply_cert_mode_change_request() {
  local request_name="${1}"
  local -n request_ref="${request_name}"
  local old_cert_mode="${2}"
  local old_xhttp_domain="${3}"

  resolve_cert_mode_change_targets \
    "${old_cert_mode}" \
    "${old_xhttp_domain}" \
    "${request_ref[cert_mode_overridden]}" \
    "${request_ref[xhttp_domain_overridden]}" \
    "${request_ref[cert_mode]}" \
    "${request_ref[xhttp_domain]}"
  apply_request_overrides "${request_name}" \
    "cert_source_file:CERT_SOURCE_FILE" \
    "key_source_file:KEY_SOURCE_FILE" \
    "cert_source_pem:CERT_SOURCE_PEM" \
    "key_source_pem:KEY_SOURCE_PEM" \
    "cf_zone_id:CF_ZONE_ID" \
    "cf_api_token:CF_API_TOKEN" \
    "cf_cert_validity:CF_CERT_VALIDITY" \
    "acme_email:ACME_EMAIL" \
    "acme_ca:ACME_CA" \
    "cf_dns_token:CF_DNS_TOKEN" \
    "cf_dns_account_id:CF_DNS_ACCOUNT_ID" \
    "cf_dns_zone_id:CF_DNS_ZONE_ID"
}

begin_managed_change() {
  need_root
  start_backup_session
  load_current_install_context
}

finish_managed_change() {
  local message="${1}"

  log "${message}"
  log "备份目录：${BACKUP_DIR}"
  show_links
}

upgrade_cmd() {
  local current_version=""

  need_root
  ensure_debian_family
  [[ -x "${XRAY_BIN}" ]] || die "找不到当前 Xray 可执行文件：${XRAY_BIN}"

  start_backup_session
  backup_path "${XRAY_BIN}"
  backup_path "${XRAY_ASSET_DIR}"

  install_xray
  ensure_xray_bind_capability
  validate_configs
  systemctl restart xray

  current_version="$("${XRAY_BIN}" version 2>/dev/null | head -n 1 || true)"
  log "升级完成。"
  log "备份目录：${BACKUP_DIR}"
  [[ -n "${current_version}" ]] && log "当前版本：${current_version}"
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

write_state_kv() {
  local key="${1}"
  local value="${2-}"

  printf '%s=%q\n' "${key}" "${value}"
}

write_state_file() {
  mkdir -p "${XRAY_CONFIG_DIR}"
  {
    # ------------------------------
    # 状态文件统一走 shell 转义
    # 避免密钥或路径里的特殊字符污染 source
    # ------------------------------
    write_state_kv "SERVER_IP" "${SERVER_IP}"
    write_state_kv "NODE_LABEL_PREFIX" "${NODE_LABEL_PREFIX}"
    write_state_kv "REALITY_UUID" "${REALITY_UUID}"
    write_state_kv "REALITY_SNI" "${REALITY_SNI}"
    write_state_kv "REALITY_TARGET" "${REALITY_TARGET}"
    write_state_kv "REALITY_SHORT_ID" "${REALITY_SHORT_ID}"
    write_state_kv "REALITY_PRIVATE_KEY" "${REALITY_PRIVATE_KEY}"
    write_state_kv "REALITY_PUBLIC_KEY" "${REALITY_PUBLIC_KEY}"
    write_state_kv "XHTTP_UUID" "${XHTTP_UUID}"
    write_state_kv "XHTTP_DOMAIN" "${XHTTP_DOMAIN}"
    write_state_kv "XHTTP_PATH" "${XHTTP_PATH}"
    write_state_kv "XHTTP_VLESS_ENCRYPTION_ENABLED" "${XHTTP_VLESS_ENCRYPTION_ENABLED}"
    write_state_kv "XHTTP_VLESS_DECRYPTION" "${XHTTP_VLESS_DECRYPTION}"
    write_state_kv "XHTTP_VLESS_ENCRYPTION" "${XHTTP_VLESS_ENCRYPTION}"
    write_state_kv "TLS_ALPN" "${TLS_ALPN}"
    write_state_kv "FINGERPRINT" "${FINGERPRINT}"
    write_state_kv "ENABLE_WARP" "${ENABLE_WARP}"
    write_state_kv "ENABLE_NET_OPT" "${ENABLE_NET_OPT}"
    write_state_kv "WARP_PROXY_PORT" "${WARP_PROXY_PORT}"
    write_state_kv "WARP_TEAM_NAME" "${WARP_TEAM_NAME}"
    write_state_kv "WARP_CLIENT_ID" "${WARP_CLIENT_ID}"
    write_state_kv "WARP_CLIENT_SECRET" "${WARP_CLIENT_SECRET}"
    write_state_kv "CERT_MODE" "${CERT_MODE}"
    write_state_kv "CF_ZONE_ID" "${CF_ZONE_ID}"
    write_state_kv "CF_CERT_VALIDITY" "${CF_CERT_VALIDITY}"
    write_state_kv "ACME_EMAIL" "${ACME_EMAIL}"
    write_state_kv "ACME_CA" "${ACME_CA}"
    write_state_kv "CF_DNS_ACCOUNT_ID" "${CF_DNS_ACCOUNT_ID}"
    write_state_kv "CF_DNS_ZONE_ID" "${CF_DNS_ZONE_ID}"
    write_state_kv "XHTTP_ECH_CONFIG_LIST" "${XHTTP_ECH_CONFIG_LIST}"
    write_state_kv "XHTTP_ECH_FORCE_QUERY" "${XHTTP_ECH_FORCE_QUERY}"
  } > "${STATE_FILE}"
  chmod 0600 "${STATE_FILE}"
}

xhttp_vless_status_text() {
  if [[ "${XHTTP_VLESS_ENCRYPTION_ENABLED}" == "yes" ]]; then
    printf '已启用'
    return
  fi

  printf '未启用'
}

xhttp_vless_enabled_text() {
  if [[ "${XHTTP_VLESS_ENCRYPTION_ENABLED}" == "yes" ]]; then
    printf '是'
    return
  fi

  printf '否'
}

xhttp_ech_status_text() {
  if [[ -n "${XHTTP_ECH_CONFIG_LIST}" ]]; then
    printf '是'
    return
  fi

  printf '否'
}

xhttp_uri_encryption_value() {
  local encoded_encryption="${1}"

  if [[ "${XHTTP_VLESS_ENCRYPTION_ENABLED}" == "yes" && -n "${XHTTP_VLESS_ENCRYPTION}" ]]; then
    printf '%s' "${encoded_encryption}"
    return
  fi

  printf 'none'
}

build_xhttp_uri() {
  local label="${1}"
  local path_component="${2}"
  local encoded_encryption="${3}"
  local ech_component="${4:-}"
  local extra_component="${5:-}"
  local ech_query=""
  local extra_query=""
  local encryption_value=""

  encryption_value="$(xhttp_uri_encryption_value "${encoded_encryption}")"
  [[ -n "${ech_component}" ]] && ech_query="&ech=${ech_component}"
  [[ -n "${extra_component}" ]] && extra_query="&extra=${extra_component}"

  printf 'vless://%s@%s:443?mode=auto&path=%s&security=tls&alpn=%s&encryption=%s&insecure=0&host=%s&fp=%s&type=xhttp&allowInsecure=0&sni=%s%s%s#%s' \
    "${XHTTP_UUID}" \
    "${XHTTP_DOMAIN}" \
    "${path_component}" \
    "${TLS_ALPN}" \
    "${encryption_value}" \
    "${XHTTP_DOMAIN}" \
    "${FINGERPRINT}" \
    "${XHTTP_DOMAIN}" \
    "${ech_query}" \
    "${extra_query}" \
    "${label}"
}

build_xhttp_split_extra_json() {
  jq -cn \
    --arg address "${SERVER_IP}" \
    --arg server_name "${REALITY_SNI}" \
    --arg fingerprint "${FINGERPRINT}" \
    --arg short_id "${REALITY_SHORT_ID}" \
    --arg public_key "${REALITY_PUBLIC_KEY}" \
    --arg path "${XHTTP_PATH}" \
    '{
      downloadSettings: {
        address: $address,
        port: 443,
        network: "xhttp",
        security: "reality",
        realitySettings: {
          show: false,
          serverName: $server_name,
          fingerprint: $fingerprint,
          shortId: $short_id,
          publicKey: $public_key
        },
        xhttpSettings: {
          host: "",
          path: $path,
          mode: "auto"
        }
      }
    }'
}

prefixed_node_label() {
  local suffix="${1}"
  printf '%s-%s' "$(normalize_node_label_prefix "${NODE_LABEL_PREFIX}")" "${suffix}"
}

cloudflare_ssl_mode_text() {
  if [[ "${CERT_MODE}" == "self-signed" ]]; then
    printf 'Full'
    return
  fi

  printf 'Full (strict)'
}

build_reality_uri() {
  local label="${1}"

  printf 'vless://%s@%s:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=%s&fp=%s&pbk=%s&sid=%s&type=tcp&headerType=none#%s' \
    "${REALITY_UUID}" \
    "${SERVER_IP}" \
    "${REALITY_SNI}" \
    "${FINGERPRINT}" \
    "${REALITY_PUBLIC_KEY}" \
    "${REALITY_SHORT_ID}" \
    "${label}"
}

output_reality_block() {
  local reality_uri="${1}"

  cat <<EOF
## 节点 1
- 类型: VLESS + REALITY + Vision
- 节点名前缀: ${NODE_LABEL_PREFIX}
- 地址: ${SERVER_IP}
- 端口: 443
- UUID: ${REALITY_UUID}
- SNI: ${REALITY_SNI}
- 公钥: ${REALITY_PUBLIC_KEY}
- 短 ID: ${REALITY_SHORT_ID}
- 流控: xtls-rprx-vision
- 指纹: ${FINGERPRINT}

链接:
${reality_uri}
EOF
}

output_xhttp_block() {
  local title="${1}"

  cat <<EOF
## ${title}
- 地址: ${XHTTP_DOMAIN}
- 端口: 443
- UUID: ${XHTTP_UUID}
EOF
}

output_xhttp_shared_details() {
  cat <<EOF
- 路径: ${XHTTP_PATH}
- VLESS Encryption: $(xhttp_vless_status_text)
EOF
}

output_xhttp_cdn_block() {
  local uri="${1}"

  cat <<EOF
$(output_xhttp_block "节点 2")
- 类型: VLESS + XHTTP + TLS + CDN
- SNI: ${XHTTP_DOMAIN}
- 主机名: ${XHTTP_DOMAIN}
- ALPN: ${TLS_ALPN}
- 模式: auto
- 指纹: ${FINGERPRINT}
$(output_xhttp_shared_details)

链接:
${uri}
EOF
}

output_xhttp_split_block() {
  local uri="${1}"

  cat <<EOF
$(output_xhttp_block "节点 3")
- 类型: 上行 XHTTP + TLS + CDN ｜ 下行 XHTTP + Reality
- 上行: XHTTP + TLS + CDN
- 下行: XHTTP + Reality
$(output_xhttp_shared_details)

链接:
${uri}
EOF
}

output_runtime_summary_block() {
  local cf_ssl_mode="${1}"

  cat <<EOF
## Cloudflare DNS 设置
- 请将 ${XHTTP_DOMAIN} 解析到此服务器 IP。
- 请为 ${XHTTP_DOMAIN} 打开橙云代理。
- 请将 Cloudflare SSL/TLS 模式设置为 ${cf_ssl_mode}。

## 本地文件
- Xray 配置: ${XRAY_CONFIG_FILE}
- Nginx 配置: ${NGINX_CONFIG_FILE}
- 安装状态文件: ${STATE_FILE}
- 链接输出文件: ${OUTPUT_FILE}

## WARP
- 已启用: ${ENABLE_WARP}
- 本地 SOCKS5 端口: ${WARP_PROXY_PORT}

## XHTTP ECH
- 已启用: $(xhttp_ech_status_text)
- DoH / ECH 查询: ${XHTTP_ECH_CONFIG_LIST:-未设置}
- 强制查询模式: ${XHTTP_ECH_FORCE_QUERY:-未设置}
- 说明: 默认不启用 ECH，导出的两个 XHTTP 节点分享链接也不会带 ech= 参数，避免额外的 DNS / DoH 查询。

## XHTTP VLESS Encryption
- 已启用: $(xhttp_vless_enabled_text)
- 说明: 默认开启，用于给 XHTTP 相关节点增加一层 VLESS 端到端加密。

## 网络优化
- 已启用: ${ENABLE_NET_OPT}
- Sysctl 文件: ${NET_SYSCTL_CONF}
- 服务名: ${NET_SERVICE_NAME}
EOF
}

write_output_file() {
  local xhttp_path_component=""
  local xhttp_ech_component=""
  local xhttp_vlessenc_component=""
  local reality_label=""
  local xhttp_label=""
  local xhttp_split_label=""
  local reality_uri=""
  local xhttp_uri=""
  local xhttp_split_uri=""
  local split_extra_json=""
  local split_extra_component=""
  local cf_ssl_mode=""

  xhttp_path_component="$(path_to_uri_component "${XHTTP_PATH}")"
  xhttp_ech_component="$(uri_encode "${XHTTP_ECH_CONFIG_LIST}")"
  xhttp_vlessenc_component="$(uri_encode "${XHTTP_VLESS_ENCRYPTION}")"
  reality_label="$(prefixed_node_label "REALITY")"
  xhttp_label="$(prefixed_node_label "XHTTP-CDN")"
  xhttp_split_label="$(prefixed_node_label "XHTTP-SPLIT-CDN-REALITY")"
  reality_uri="$(build_reality_uri "${reality_label}")"
  xhttp_uri="$(build_xhttp_uri "${xhttp_label}" "${xhttp_path_component}" "${xhttp_vlessenc_component}" "${xhttp_ech_component}")"
  split_extra_json="$(build_xhttp_split_extra_json)"
  split_extra_component="$(uri_encode "${split_extra_json}")"
  xhttp_split_uri="$(build_xhttp_uri "${xhttp_split_label}" "${xhttp_path_component}" "${xhttp_vlessenc_component}" "" "${split_extra_component}")"
  cf_ssl_mode="$(cloudflare_ssl_mode_text)"

  cat > "${OUTPUT_FILE}" <<EOF
# Xray WARP Team 部署信息

$(output_reality_block "${reality_uri}")

$(output_xhttp_cdn_block "${xhttp_uri}")

$(output_xhttp_split_block "${xhttp_split_uri}")

$(output_runtime_summary_block "${cf_ssl_mode}")
EOF
}

change_uuid_cmd() {
  local rotate_reality=1
  local rotate_xhttp=1
  local new_reality_uuid=""
  local new_xhttp_uuid=""

  while [[ $# -gt 0 ]]; do
    if handle_change_common_arg "${1}"; then
      shift
      continue
    fi

    case "${1}" in
      --reality-uuid)
        assign_option_value new_reality_uuid "$@"
        shift
        ;;
      --xhttp-uuid)
        assign_option_value new_xhttp_uuid "$@"
        shift
        ;;
      --reality-only)
        rotate_xhttp=0
        ;;
      --xhttp-only)
        rotate_reality=0
        ;;
      *)
        die "未知的 change-uuid 参数：${1}"
        ;;
    esac
    shift
  done

  if [[ "${rotate_reality}" -eq 0 && "${rotate_xhttp}" -eq 0 ]]; then
    die "没有需要修改的内容。请使用默认行为，或传入 --reality-only / --xhttp-only。"
  fi

  begin_managed_change

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

  finish_managed_change "UUID 轮换完成。"
}

change_sni_cmd() {
  local old_reality_sni=""
  local new_reality_sni=""
  local sni_overridden=0

  while [[ $# -gt 0 ]]; do
    if handle_change_common_arg "${1}"; then
      shift
      continue
    fi

    case "${1}" in
      --reality-sni)
        assign_option_value new_reality_sni "$@"
        sni_overridden=1
        shift
        ;;
      *)
        die "未知的 change-sni 参数：${1}"
        ;;
    esac
    shift
  done

  begin_managed_change
  old_reality_sni="${REALITY_SNI}"

  resolve_change_value REALITY_SNI "新的 REALITY 可见 SNI" "${old_reality_sni}" "${sni_overridden}" "${new_reality_sni}"

  apply_managed_runtime_update
  finish_managed_change "REALITY SNI 已更新。"
}

change_path_cmd() {
  local old_xhttp_path=""
  local new_xhttp_path=""
  local path_overridden=0

  while [[ $# -gt 0 ]]; do
    if handle_change_common_arg "${1}"; then
      shift
      continue
    fi

    case "${1}" in
      --xhttp-path)
        assign_option_value new_xhttp_path "$@"
        path_overridden=1
        shift
        ;;
      *)
        die "未知的 change-path 参数：${1}"
        ;;
    esac
    shift
  done

  begin_managed_change
  old_xhttp_path="${XHTTP_PATH}"

  resolve_change_value XHTTP_PATH "新的 XHTTP 路径" "${old_xhttp_path}" "${path_overridden}" "${new_xhttp_path}"
  ensure_xhttp_path_format

  apply_managed_runtime_update
  finish_managed_change "XHTTP 路径已更新。"
}

change_label_prefix_cmd() {
  local old_node_label_prefix=""
  local new_node_label_prefix=""
  local prefix_overridden=0

  while [[ $# -gt 0 ]]; do
    if handle_change_common_arg "${1}"; then
      shift
      continue
    fi

    case "${1}" in
      --node-label-prefix)
        assign_option_value new_node_label_prefix "$@"
        prefix_overridden=1
        shift
        ;;
      *)
        die "未知的 change-label-prefix 参数：${1}"
        ;;
    esac
    shift
  done

  begin_managed_change
  old_node_label_prefix="${NODE_LABEL_PREFIX}"

  resolve_change_value NODE_LABEL_PREFIX "新的节点名前缀" "${old_node_label_prefix}" "${prefix_overridden}" "${new_node_label_prefix}"
  NODE_LABEL_PREFIX="$(normalize_node_label_prefix "${NODE_LABEL_PREFIX}")"

  write_state_file
  write_output_file

  finish_managed_change "节点名前缀已更新。"
}

change_warp_cmd() {
  local -A request=()

  init_change_warp_request request
  parse_change_warp_args request "$@"
  ensure_debian_family
  begin_managed_change

  apply_warp_change_request request
  run_change_warp_action "$(resolve_change_warp_target_mode "${request[target_mode]}")"
}

change_cert_mode_cmd() {
  local old_cert_mode=""
  local old_xhttp_domain=""
  local -A request=()

  init_change_cert_mode_request request
  parse_change_cert_mode_args request "$@"
  begin_managed_change
  old_cert_mode="${CERT_MODE}"
  old_xhttp_domain="${XHTTP_DOMAIN}"

  apply_cert_mode_change_request request "${old_cert_mode}" "${old_xhttp_domain}"
  prompt_cert_mode_inputs
  apply_managed_update
  cleanup_previous_acme_cert "${old_cert_mode}" "${old_xhttp_domain}"

  finish_managed_change "证书模式已更新。"
}

show_links() {
  [[ -f "${STATE_FILE}" ]] || die "找不到状态文件：${STATE_FILE}"
  [[ -f "${OUTPUT_FILE}" ]] || die "找不到输出文件：${OUTPUT_FILE}"
  cat "${OUTPUT_FILE}"
}

status_raw_cmd() {
  systemctl --no-pager --full status xray haproxy nginx warp-svc "${NET_SERVICE_NAME}" 2>/dev/null || true
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
        die "未知的 status 参数：${1}"
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
  if service_exists "nginx.service"; then
    systemctl restart nginx
  fi
  if service_exists "warp-svc.service"; then
    systemctl restart warp-svc || true
  fi
  if service_exists "${NET_SERVICE_NAME}"; then
    systemctl restart "${NET_SERVICE_NAME}" || true
  fi
  log "服务已重启。"
}

repair_perms_cmd() {
  need_root
  ensure_xray_user
  ensure_managed_permissions
  systemctl daemon-reload
  systemctl restart xray haproxy nginx >/dev/null 2>&1 || true
  log "已修复脚本托管文件权限，并尝试重启 xray、haproxy 与 nginx。"
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
        die "未知的 uninstall 参数：${1}"
        ;;
    esac
    shift
  done

  need_root
  start_backup_session
  load_existing_state

  if [[ "${assume_yes}" -ne 1 ]]; then
    read -r -p "该操作会停止服务并删除脚本托管文件，但保留已安装的软件包。是否继续？ [y/N]: " answer
    answer="$(printf '%s' "${answer}" | tr 'A-Z' 'a-z')"
    if [[ "${answer}" != "y" && "${answer}" != "yes" ]]; then
      die "已取消卸载。"
    fi
  fi

  stop_and_disable_service_if_present "xray.service"
  stop_and_disable_service_if_present "haproxy.service"
  stop_and_disable_service_if_present "nginx.service"
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
    "${NGINX_CONFIG_FILE}" \
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
  systemctl reset-failed xray.service haproxy.service nginx.service warp-svc.service "${NET_SERVICE_NAME}" >/dev/null 2>&1 || true
  sysctl --system >/dev/null 2>&1 || true

  log "脚本托管文件已删除。"
  log "备份目录：${BACKUP_DIR}"
  log "已安装的软件包已保留。"
}

show_main_menu() {
  cat <<'EOF'
  1. 安装或重装
  2. 查看节点链接
  3. 刷新状态面板
  4. 重启服务
  5. 升级 Xray 核心
  6. 轮换节点 UUID
  7. 修改 REALITY SNI
  8. 修改 XHTTP 路径
  9. 修改节点名前缀
  10. 开关 WARP 分流
  11. 修改证书模式 / CDN 域名
  12. 抢修文件权限
  13. 卸载托管文件
  14. 查看原始服务详情
  15. 帮助
  0. 退出
EOF
}

pause_after_menu_action() {
  printf '\n'
  read -r -p "按回车继续..." _
}

run_cli_command() {
  local command="${1:-menu}"

  if [[ $# -gt 0 ]]; then
    shift
  fi

  case "${command}" in
    menu)
      main_menu
      ;;
    install)
      install_cmd "$@"
      ;;
    upgrade)
      upgrade_cmd "$@"
      ;;
    change-uuid)
      change_uuid_cmd "$@"
      ;;
    change-sni)
      change_sni_cmd "$@"
      ;;
    change-path)
      change_path_cmd "$@"
      ;;
    change-label-prefix)
      change_label_prefix_cmd "$@"
      ;;
    change-warp)
      change_warp_cmd "$@"
      ;;
    change-cert-mode)
      change_cert_mode_cmd "$@"
      ;;
    uninstall)
      uninstall_cmd "$@"
      ;;
    show-links)
      show_links
      ;;
    status)
      status_cmd "$@"
      ;;
    restart)
      restart_cmd
      ;;
    repair-perms)
      repair_perms_cmd
      ;;
    help|--help|-h)
      usage
      ;;
    *)
      die "未知命令：${command}"
      ;;
  esac
}

run_menu_choice() {
  case "${1}" in
    1) run_cli_command install ;;
    2) run_cli_command show-links ;;
    3) run_cli_command status ;;
    4) run_cli_command restart ;;
    5) run_cli_command upgrade ;;
    6) run_cli_command change-uuid ;;
    7) run_cli_command change-sni ;;
    8) run_cli_command change-path ;;
    9) run_cli_command change-label-prefix ;;
    10) run_cli_command change-warp ;;
    11) run_cli_command change-cert-mode ;;
    12) run_cli_command repair-perms ;;
    13) run_cli_command uninstall ;;
    14) run_cli_command status --raw ;;
    15) run_cli_command help ;;
    *)
      warn "未知的菜单项：${1}"
      return 1
      ;;
  esac
}

main_menu() {
  local choice=""

  while true; do
    if [[ -t 1 ]]; then
      clear >/dev/null 2>&1 || true
    fi
    show_dashboard
    show_main_menu
    read -r -p "请选择: " choice
    if [[ "${choice}" == "0" ]]; then
      exit 0
    fi
    run_menu_choice "${choice}" || true
    pause_after_menu_action
  done
}

parse_install_flag_arg() {
  case "${1}" in
    --non-interactive)
      NON_INTERACTIVE=1
      ;;
    --enable-xhttp-vless-encryption)
      XHTTP_VLESS_ENCRYPTION_ENABLED="yes"
      ;;
    --disable-xhttp-vless-encryption)
      XHTTP_VLESS_ENCRYPTION_ENABLED="no"
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
    --help|-h|help)
      usage
      exit 0
      ;;
    *)
      return 1
      ;;
  esac
}

parse_install_core_value_arg() {
  case "${1}" in
    --server-ip) assign_option_value SERVER_IP "$@" ;;
    --node-label-prefix) assign_option_value NODE_LABEL_PREFIX "$@" ;;
    --reality-uuid) assign_option_value REALITY_UUID "$@" ;;
    --reality-sni) assign_option_value REALITY_SNI "$@" ;;
    --reality-target) assign_option_value REALITY_TARGET "$@" ;;
    --reality-short-id) assign_option_value REALITY_SHORT_ID "$@" ;;
    --reality-private-key) assign_option_value REALITY_PRIVATE_KEY "$@" ;;
    --xhttp-uuid) assign_option_value XHTTP_UUID "$@" ;;
    --xhttp-domain) assign_option_value XHTTP_DOMAIN "$@" ;;
    --xhttp-path) assign_option_value XHTTP_PATH "$@" ;;
    *)
      return 1
      ;;
  esac
}

parse_install_cert_value_arg() {
  case "${1}" in
    --cert-mode) assign_option_value CERT_MODE "$@" ;;
    --cert-file) assign_option_value CERT_SOURCE_FILE "$@" ;;
    --key-file) assign_option_value KEY_SOURCE_FILE "$@" ;;
    --cert-pem) assign_option_value CERT_SOURCE_PEM "$@" ;;
    --key-pem) assign_option_value KEY_SOURCE_PEM "$@" ;;
    --cf-zone-id) assign_option_value CF_ZONE_ID "$@" ;;
    --cf-api-token) assign_option_value CF_API_TOKEN "$@" ;;
    --cf-cert-validity) assign_option_value CF_CERT_VALIDITY "$@" ;;
    --acme-email) assign_option_value ACME_EMAIL "$@" ;;
    --acme-ca) assign_option_value ACME_CA "$@" ;;
    --cf-dns-token) assign_option_value CF_DNS_TOKEN "$@" ;;
    --cf-dns-account-id) assign_option_value CF_DNS_ACCOUNT_ID "$@" ;;
    --cf-dns-zone-id) assign_option_value CF_DNS_ZONE_ID "$@" ;;
    *)
      return 1
      ;;
  esac
}

parse_install_warp_value_arg() {
  case "${1}" in
    --warp-team) assign_option_value WARP_TEAM_NAME "$@" ;;
    --warp-client-id) assign_option_value WARP_CLIENT_ID "$@" ;;
    --warp-client-secret) assign_option_value WARP_CLIENT_SECRET "$@" ;;
    --warp-proxy-port) assign_option_value WARP_PROXY_PORT "$@" ;;
    *)
      return 1
      ;;
  esac
}

parse_install_value_arg() {
  if parse_install_core_value_arg "$@"; then
    return 0
  fi
  if parse_install_cert_value_arg "$@"; then
    return 0
  fi
  if parse_install_warp_value_arg "$@"; then
    return 0
  fi

  return 1
}

parse_install_args() {
  while [[ $# -gt 0 ]]; do
    if parse_install_flag_arg "${1}"; then
      shift
      continue
    fi
    if parse_install_value_arg "$@"; then
      shift 2
      continue
    fi

    die "未知的 install 参数：${1}"
  done
}

prepare_install_command() {
  need_root
  ensure_debian_family
  start_backup_session
  parse_install_args "$@"
  prepare_install_inputs
}

install_xray_runtime() {
  install_packages
  install_self_command
  install_xray
  ensure_xray_bind_capability
  ensure_xray_user
  generate_reality_keys_if_needed
}

write_install_managed_files() {
  write_tls_assets
  write_xray_config
  write_haproxy_config
  write_nginx_config
  write_xray_service
}

install_optional_components() {
  install_network_optimization
  install_warp
}

install_cmd() {
  prepare_install_command "$@"
  install_xray_runtime
  write_install_managed_files
  install_optional_components
  finalize_installation

  log "部署完成。"
  log "备份目录：${BACKUP_DIR}"
  log "管理命令：${SELF_COMMAND_PATH}"
  log "节点链接已写入：${OUTPUT_FILE}"
  show_links
}

main() {
  run_cli_command "$@"
}

main "$@"
