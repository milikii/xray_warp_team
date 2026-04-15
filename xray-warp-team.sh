#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_VERSION="0.1.0"
DEFAULT_REALITY_SNI="www.scu.edu"
DEFAULT_WARP_PROXY_PORT="40000"
DEFAULT_TLS_ALPN="h2"
DEFAULT_FINGERPRINT="chrome"
DEFAULT_CF_CERT_VALIDITY="5475"
XRAY_BIN="/usr/local/bin/xray"
XRAY_CONFIG_DIR="/usr/local/etc/xray"
XRAY_CONFIG_FILE="${XRAY_CONFIG_DIR}/config.json"
XRAY_ASSET_DIR="/usr/local/share/xray"
XRAY_SERVICE_FILE="/etc/systemd/system/xray.service"
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
xray-warp-team.sh v0.1.0

Usage:
  bash xray-warp-team.sh
  bash xray-warp-team.sh install [options]
  bash xray-warp-team.sh show-links
  bash xray-warp-team.sh status
  bash xray-warp-team.sh restart
  bash xray-warp-team.sh help

Install options:
  --non-interactive           Run without prompts. Missing required values will fail.
  --server-ip VALUE           Public IP or hostname for the direct REALITY node.
  --reality-uuid VALUE        UUID for the REALITY node.
  --reality-sni VALUE         Visible SNI for REALITY and HAProxy routing.
  --reality-target VALUE      REALITY target in host:port form.
  --reality-short-id VALUE    Short ID for REALITY.
  --xhttp-uuid VALUE          UUID for the XHTTP CDN node.
  --xhttp-domain VALUE        Orange-cloud domain for the XHTTP CDN node.
  --xhttp-path VALUE          XHTTP path, for example /cfup-example.
  --cert-mode VALUE           self-signed, existing, or cf-origin-ca.
  --cert-file VALUE           Existing certificate file when --cert-mode existing.
  --key-file VALUE            Existing key file when --cert-mode existing.
  --cf-zone-id VALUE          Cloudflare zone ID for cf-origin-ca mode.
  --cf-api-token VALUE        Cloudflare API token for cf-origin-ca mode.
  --cf-cert-validity VALUE    Cloudflare Origin CA validity days. Default: 5475
  --enable-warp               Enable selective WARP outbound.
  --disable-warp              Disable WARP outbound.
  --enable-net-opt            Enable BBR/FQ/RPS network optimization.
  --disable-net-opt           Disable network optimization.
  --warp-team VALUE           Cloudflare Zero Trust team name.
  --warp-client-id VALUE      Service token client ID.
  --warp-client-secret VALUE  Service token client secret.
  --warp-proxy-port VALUE     Local SOCKS5 port used by WARP. Default: 40000

Examples:
  bash xray-warp-team.sh
  bash xray-warp-team.sh install --non-interactive \
    --server-ip 203.0.113.10 \
    --xhttp-domain cdn.example.com \
    --cert-mode self-signed \
    --enable-net-opt \
    --disable-warp
EOF
}

guess_server_ip() {
  local guessed=""

  guessed="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") {print $(i + 1); exit}}')"
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
  prompt_with_default CERT_MODE "TLS certificate mode (self-signed/existing/cf-origin-ca)" "self-signed"

  case "${CERT_MODE}" in
    self-signed|existing|cf-origin-ca)
      ;;
    *)
      die "Unsupported cert mode: ${CERT_MODE}. Use self-signed, existing, or cf-origin-ca."
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

path_to_uri_component() {
  printf '%s' "${1}" | sed 's/\//%2F/g'
}

write_state_file() {
  mkdir -p "${XRAY_CONFIG_DIR}"
  cat > "${STATE_FILE}" <<EOF
SERVER_IP='${SERVER_IP}'
REALITY_UUID='${REALITY_UUID}'
REALITY_SNI='${REALITY_SNI}'
REALITY_TARGET='${REALITY_TARGET}'
REALITY_SHORT_ID='${REALITY_SHORT_ID}'
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
EOF
  chmod 0600 "${STATE_FILE}"
}

write_output_file() {
  local xhttp_path_component=""
  local cf_ssl_mode="Full (strict)"

  xhttp_path_component="$(path_to_uri_component "${XHTTP_PATH}")"

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

URI:
vless://${XHTTP_UUID}@${XHTTP_DOMAIN}:443?encryption=none&security=tls&sni=${XHTTP_DOMAIN}&alpn=${TLS_ALPN}&fp=${FINGERPRINT}&type=xhttp&host=${XHTTP_DOMAIN}&path=${xhttp_path_component}&mode=stream-one#XHTTP-CDN

## Cloudflare DNS
- Point ${XHTTP_DOMAIN} to this server IP.
- Enable orange-cloud for ${XHTTP_DOMAIN}.
- Set Cloudflare SSL/TLS mode to ${cf_ssl_mode}.

## Local files
- Xray config: ${XRAY_CONFIG_FILE}
- HAProxy config: ${HAPROXY_CONFIG}
- Installer state: ${STATE_FILE}

## WARP
- Enabled: ${ENABLE_WARP}
- Local SOCKS5 port: ${WARP_PROXY_PORT}

## Network optimization
- Enabled: ${ENABLE_NET_OPT}
- Sysctl file: ${NET_SYSCTL_CONF}
- Service: ${NET_SERVICE_NAME}
EOF
}

show_links() {
  [[ -f "${STATE_FILE}" ]] || die "State file not found: ${STATE_FILE}"
  [[ -f "${OUTPUT_FILE}" ]] || die "Output file not found: ${OUTPUT_FILE}"
  cat "${OUTPUT_FILE}"
}

status_cmd() {
  systemctl --no-pager --full status xray haproxy warp-svc "${NET_SERVICE_NAME}" 2>/dev/null || true
}

restart_cmd() {
  systemctl restart xray haproxy
  if systemctl list-unit-files --type=service --no-pager | grep -q '^warp-svc\.service'; then
    systemctl restart warp-svc || true
  fi
  if systemctl list-unit-files --type=service --no-pager | grep -Fq "${NET_SERVICE_NAME}"; then
    systemctl restart "${NET_SERVICE_NAME}" || true
  fi
  log "Services restarted."
}

main_menu() {
  local choice=""

  while true; do
    cat <<'EOF'

Xray WARP Team
  1. Install or reinstall
  2. Show node links
  3. Show service status
  4. Restart services
  0. Exit
EOF
    read -r -p "Select: " choice
    case "${choice}" in
      1) install_cmd ;;
      2) show_links ;;
      3) status_cmd ;;
      4) restart_cmd ;;
      0) exit 0 ;;
      *) warn "Unknown selection: ${choice}" ;;
    esac
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

  BACKUP_DIR="${BACKUP_ROOT}/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "${BACKUP_DIR}"

  parse_install_args "$@"
  prepare_install_inputs
  install_packages
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
    show-links)
      show_links
      ;;
    status)
      status_cmd
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
