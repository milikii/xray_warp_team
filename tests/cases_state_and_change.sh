run_state_context_case() {
  local workdir=""

  workdir="$(mktemp -d)"
  prepare_workspace "${workdir}"

  NGINX_CONF_DIR="${workdir}/nginx"
  NGINX_CONFIG_FILE="${NGINX_CONF_DIR}/xray-warp-team.conf"
  WARP_MDM_FILE="${workdir}/warp-mdm.xml"
  HEALTH_STATE_FILE="${workdir}/health-state.env"
  HEALTH_HISTORY_FILE="${workdir}/health-history.log"
  NET_SERVICE_FILE="${workdir}/net.service"
  NET_SYSCTL_CONF="${workdir}/net.conf"
  mkdir -p "${NGINX_CONF_DIR}"

  cat > "${XRAY_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    {
      "tag": "reality-vision",
      "settings": {
        "clients": [
          {
            "id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
          }
        ]
      },
      "streamSettings": {
        "realitySettings": {
          "serverNames": [
            "reality.example.com"
          ],
          "target": "www.scu.edu:443",
          "shortIds": [
            "abcd1234"
          ],
          "privateKey": "private-key-value"
        }
      }
    },
    {
      "tag": "xhttp-cdn",
      "settings": {
        "clients": [
          {
            "id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
          }
        ],
        "decryption": "enc-value"
      },
      "streamSettings": {
        "xhttpSettings": {
          "path": "/assets/v3"
        }
      }
    }
  ],
  "outbounds": [
    {
      "tag": "WARP",
      "settings": {
        "servers": [
          {
            "port": 41000
          }
        ]
      }
    }
  ]
}
EOF

  cat > "${NGINX_CONFIG_FILE}" <<'EOF'
server {
    listen 127.0.0.1:8443 ssl;
    server_name cdn.example.com;

    location /assets/v3 {
        grpc_pass 127.0.0.1:8001;
    }
}
EOF

  cat > "${STATE_FILE}" <<'EOF'
STATE_VERSION='1'
TLS_ALPN='h2'
CERT_MODE='existing'
ACME_CA='letsencrypt'
XHTTP_ECH_CONFIG_LIST='https://1.1.1.1/dns-query'
XHTTP_ECH_FORCE_QUERY='none'
EOF

  cat > "${OUTPUT_FILE}" <<'EOF'
- 地址: 203.0.113.20
- 节点名前缀: HKG
- 公钥: public-key-value
- 指纹: firefox
EOF

  cat > "${HEALTH_STATE_FILE}" <<'EOF'
CORE_HEALTH_LAST_CHECK_AT='2026-04-21T12:00:00Z'
CORE_HEALTH_LAST_ACTION='ok'
CORE_HEALTH_LAST_REASON='services healthy'
WARP_HEALTH_LAST_CHECK_AT='2026-04-21T12:05:00Z'
WARP_HEALTH_LAST_ACTION='restarted'
WARP_HEALTH_LAST_REASON='warp socks5 probe failed'
EOF

  cat > "${HEALTH_HISTORY_FILE}" <<'EOF'
2026-04-21T12:00:00Z | core | ok | services healthy
2026-04-21T12:10:00Z | core | restarted | service inactive
2026-04-21T12:05:00Z | warp | restarted | warp socks5 probe failed
EOF

  REALITY_UUID="" REALITY_SNI="" REALITY_TARGET="" REALITY_SHORT_ID="" REALITY_PRIVATE_KEY="" \
  REALITY_PUBLIC_KEY="" XHTTP_UUID="" XHTTP_DOMAIN="" XHTTP_PATH="" XHTTP_VLESS_DECRYPTION="" \
  XHTTP_VLESS_ENCRYPTION_ENABLED="" TLS_ALPN="" SERVER_IP="" NODE_LABEL_PREFIX="" FINGERPRINT="" \
  ENABLE_WARP="" ENABLE_NET_OPT="" WARP_PROXY_PORT="" WARP_TEAM_NAME="" WARP_CLIENT_ID="" \
  WARP_CLIENT_SECRET="" CERT_MODE="" ACME_CA="" XHTTP_ECH_CONFIG_LIST="" XHTTP_ECH_FORCE_QUERY=""

  load_dashboard_context
  [[ "${REALITY_UUID}" == "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" ]]
  [[ "${XHTTP_DOMAIN}" == "cdn.example.com" ]]
  [[ "${SERVER_IP}" == "203.0.113.20" ]]
  [[ "${NODE_LABEL_PREFIX}" == "HKG" ]]
  [[ "${REALITY_PUBLIC_KEY}" == "public-key-value" ]]
  [[ "${FINGERPRINT}" == "firefox" ]]
  [[ "${ENABLE_WARP}" == "yes" ]]
  [[ "${WARP_PROXY_PORT}" == "41000" ]]
  [[ "${XHTTP_VLESS_ENCRYPTION_ENABLED}" == "yes" ]]
  [[ "${ENABLE_NET_OPT}" == "no" ]]
  [[ -z "${XHTTP_ECH_CONFIG_LIST}" ]]
  [[ -z "${XHTTP_ECH_FORCE_QUERY}" ]]
  [[ "${CORE_HEALTH_LAST_ACTION}" == "ok" ]]
  [[ "${WARP_HEALTH_LAST_ACTION}" == "restarted" ]]
  [[ "$(latest_health_history_text)" == "2026-04-21T12:05:00Z | warp | restarted | warp socks5 probe failed" ]]
  HEALTH_HISTORY_NOW='2026-04-21T12:30:00Z'
  [[ "$(health_history_count_text 1 core)" == "1" ]]
  [[ "$(health_history_count_text 1 warp)" == "1" ]]
  [[ "$(health_history_count_text 24 core)" == "1" ]]
  [[ "$(stability_signal_text)" == *"稳定"* ]]

  REALITY_UUID="" REALITY_SNI="" REALITY_TARGET="" REALITY_SHORT_ID="" REALITY_PRIVATE_KEY="" \
  REALITY_PUBLIC_KEY="" XHTTP_UUID="" XHTTP_DOMAIN="" XHTTP_PATH="" XHTTP_VLESS_DECRYPTION="" \
  XHTTP_VLESS_ENCRYPTION_ENABLED="" TLS_ALPN="" SERVER_IP="" NODE_LABEL_PREFIX="" FINGERPRINT="" \
  ENABLE_WARP="" ENABLE_NET_OPT="" WARP_PROXY_PORT="" WARP_TEAM_NAME="" WARP_CLIENT_ID="" \
  WARP_CLIENT_SECRET="" CERT_MODE="" ACME_CA="" XHTTP_ECH_CONFIG_LIST="" XHTTP_ECH_FORCE_QUERY=""

  load_current_install_context
  [[ "${REALITY_PRIVATE_KEY}" == "private-key-value" ]]
  [[ "${TLS_ALPN}" == "h2" ]]
  [[ "${CERT_MODE}" == "existing" ]]
  [[ "${ACME_CA}" == "letsencrypt" ]]
}

run_state_version_case() {
  local workdir=""
  local warned=""

  workdir="$(mktemp -d)"
  prepare_workspace "${workdir}"
  cat > "${STATE_FILE}" <<'EOF'
STATE_VERSION='0'
TLS_ALPN='h2'
EOF

  warn() {
    warned+="${1}"$'\n'
  }

  load_existing_state
  [[ "${TLS_ALPN}" == "h2" ]]
  printf '%s' "${warned}" | grep -q '旧版本状态文件'
}

run_health_history_count_without_python_case() {
  local workdir=""

  workdir="$(mktemp -d)"
  prepare_workspace "${workdir}"
  HEALTH_HISTORY_FILE="${workdir}/health-history.log"
  cat > "${HEALTH_HISTORY_FILE}" <<'EOF'
2026-04-21T12:00:00Z | core | ok | services healthy
2026-04-21T12:10:00Z | core | restarted | service inactive
2026-04-21T12:05:00Z | warp | restarted | warp probe failed
EOF

  python3() {
    return 99
  }

  HEALTH_HISTORY_NOW='2026-04-21T12:30:00Z'
  [[ "$(health_history_count_text 1 core)" == "1" ]]
  [[ "$(health_history_count_text 1 warp)" == "1" ]]
  [[ "$(health_history_count_text 24 core)" == "1" ]]
  unset -f python3
}

run_state_file_decode_case() {
  local workdir=""

  workdir="$(mktemp -d)"
  prepare_workspace "${workdir}"
  cat > "${STATE_FILE}" <<'EOF'
STATE_VERSION=1
WARP_CLIENT_SECRET=sec\'ret\ 0\ \[\]
XHTTP_ECH_CONFIG_LIST=$'line1\nline2'
EOF

  load_existing_state
  [[ "${WARP_CLIENT_SECRET}" == "sec'ret 0 []" ]]
  [[ "${XHTTP_ECH_CONFIG_LIST}" == $'line1\nline2' ]]
}

run_runtime_context_reset_case() {
  local workdir=""

  workdir="$(mktemp -d)"
  prepare_workspace "${workdir}"
  WARP_MDM_FILE="${workdir}/missing-mdm.xml"
  WARP_RULES_FILE="${workdir}/missing-rules.list"
  HEALTH_STATE_FILE="${workdir}/missing-health.env"

  REALITY_UUID="stale-reality"
  XHTTP_DOMAIN="stale.example.com"
  ENABLE_WARP="yes"
  WARP_RULES_TEXT="domain:stale.example.com"
  CORE_HEALTH_LAST_ACTION="restarted"

  load_dashboard_context
  [[ -z "${REALITY_UUID}" ]]
  [[ -z "${XHTTP_DOMAIN}" ]]
  [[ -z "${ENABLE_WARP}" ]]
  [[ -z "${WARP_RULES_TEXT}" ]]
  [[ -z "${CORE_HEALTH_LAST_ACTION}" ]]
  [[ "$(warp_rule_count_text)" == "0" ]]
}

run_managed_apply_case() {
  local tls_calls=0
  local runtime_calls=0
  local validate_calls=0
  local restart_calls=0
  local state_calls=0
  local output_calls=0

  write_tls_assets() {
    tls_calls=$((tls_calls + 1))
  }
  write_runtime_managed_files() {
    runtime_calls=$((runtime_calls + 1))
  }
  validate_configs() {
    validate_calls=$((validate_calls + 1))
  }
  restart_core_services() {
    restart_calls=$((restart_calls + 1))
  }
  write_state_file() {
    state_calls=$((state_calls + 1))
  }
  write_output_file() {
    output_calls=$((output_calls + 1))
  }

  apply_managed_runtime_update
  [[ "${tls_calls}" -eq 0 ]]
  [[ "${runtime_calls}" -eq 1 ]]
  [[ "${validate_calls}" -eq 1 ]]
  [[ "${restart_calls}" -eq 1 ]]
  [[ "${state_calls}" -eq 1 ]]
  [[ "${output_calls}" -eq 1 ]]

  apply_managed_update
  [[ "${tls_calls}" -eq 1 ]]
  [[ "${runtime_calls}" -eq 2 ]]
  [[ "${validate_calls}" -eq 2 ]]
  [[ "${restart_calls}" -eq 2 ]]
  [[ "${state_calls}" -eq 2 ]]
  [[ "${output_calls}" -eq 2 ]]
}

run_tls_stage_failure_case() {
  local workdir=""
  local status=0

  workdir="$(mktemp -d)"
  SSL_DIR="${workdir}/ssl"
  TLS_CERT_FILE="${SSL_DIR}/cert.pem"
  TLS_KEY_FILE="${SSL_DIR}/key.pem"
  CERT_MODE="cf-origin-ca"
  XHTTP_DOMAIN="cdn.example.com"
  CF_ZONE_ID="zone-id"
  CF_API_TOKEN="api-token"
  XRAY_GID="0"
  mkdir -p "${SSL_DIR}"

  printf 'old-cert\n' > "${TLS_CERT_FILE}"
  printf 'old-key\n' > "${TLS_KEY_FILE}"

  curl() {
    return 1
  }

  set +e
  ( write_tls_assets ) >/dev/null 2>&1
  status=$?
  set -e

  [[ "${status}" -ne 0 ]]
  [[ "$(cat "${TLS_CERT_FILE}")" == "old-cert" ]]
  [[ "$(cat "${TLS_KEY_FILE}")" == "old-key" ]]
  [[ ! -e "${SSL_DIR}/.cert.pem.stage" ]]
  [[ ! -e "${SSL_DIR}/.key.pem.stage" ]]
}

run_managed_rollback_case() {
  local workdir=""
  local status=0
  local recovery_calls=0

  workdir="$(mktemp -d)"
  XRAY_CONFIG_DIR="${workdir}/xray"
  XRAY_CONFIG_FILE="${XRAY_CONFIG_DIR}/config.json"
  HAPROXY_CONFIG="${workdir}/haproxy.cfg"
  NGINX_CONFIG_FILE="${workdir}/nginx.conf"
  BACKUP_DIR="${workdir}/backup"
  mkdir -p "${XRAY_CONFIG_DIR}" "${BACKUP_DIR}"

  printf 'old-xray\n' > "${XRAY_CONFIG_FILE}"
  printf 'old-haproxy\n' > "${HAPROXY_CONFIG}"
  printf 'old-nginx\n' > "${NGINX_CONFIG_FILE}"

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
  write_runtime_managed_files() {
    backup_path "${XRAY_CONFIG_FILE}"
    backup_path "${HAPROXY_CONFIG}"
    backup_path "${NGINX_CONFIG_FILE}"
    printf 'new-xray\n' > "${XRAY_CONFIG_FILE}"
    printf 'new-haproxy\n' > "${HAPROXY_CONFIG}"
    printf 'new-nginx\n' > "${NGINX_CONFIG_FILE}"
  }
  validate_configs() {
    return 1
  }
  ensure_xray_user() {
    recovery_calls=$((recovery_calls + 1))
  }
  ensure_managed_permissions() { :; }
  systemctl() { :; }
  log() { :; }
  warn() { :; }

  set +e
  apply_managed_runtime_update >/dev/null 2>&1
  status=$?
  set -e

  [[ "${status}" -ne 0 ]]
  [[ "${recovery_calls}" -eq 1 ]]
  [[ "$(cat "${XRAY_CONFIG_FILE}")" == "old-xray" ]]
  [[ "$(cat "${HAPROXY_CONFIG}")" == "old-haproxy" ]]
  [[ "$(cat "${NGINX_CONFIG_FILE}")" == "old-nginx" ]]
}

run_optional_component_rollback_case() {
  local stopped=()
  local rolled=()
  local sysctl_calls=0
  local warned=""

  ENABLE_WARP="yes"
  ENABLE_NET_OPT="yes"
  stop_and_disable_service_if_present() {
    stopped+=("${1}")
  }
  rollback_managed_paths() {
    rolled=("$@")
  }
  systemctl() { :; }
  sysctl() {
    sysctl_calls=$((sysctl_calls + 1))
  }
  warn() {
    warned+="${1}"$'\n'
  }

  rollback_optional_component_state
  [[ " ${stopped[*]} " == *" warp-svc.service "* ]]
  [[ " ${stopped[*]} " == *" ${WARP_HEALTH_TIMER_NAME} "* ]]
  [[ " ${stopped[*]} " == *" ${NET_SERVICE_NAME} "* ]]
  [[ " ${rolled[*]} " == *" ${WARP_APT_KEYRING} "* ]]
  [[ " ${rolled[*]} " == *" ${WARP_APT_SOURCE_LIST} "* ]]
  [[ " ${rolled[*]} " == *" ${WARP_MDM_FILE} "* ]]
  [[ " ${rolled[*]} " == *" ${NET_SYSCTL_CONF} "* ]]
  [[ "${sysctl_calls}" -eq 1 ]]
  printf '%s' "${warned}" | grep -q '可选组件应用失败'
  load_functions
}

run_install_rollback_helper_case() {
  local workdir=""

  workdir="$(mktemp -d)"
  BACKUP_DIR="${workdir}/backup"
  XRAY_CONFIG_DIR="${workdir}/xray"
  XRAY_CONFIG_FILE="${XRAY_CONFIG_DIR}/config.json"
  HAPROXY_CONFIG="${workdir}/haproxy.cfg"
  NGINX_CONFIG_FILE="${workdir}/nginx.conf"
  XRAY_SERVICE_FILE="${workdir}/xray.service"
  SSL_DIR="${workdir}/ssl"
  TLS_CERT_FILE="${SSL_DIR}/cert.pem"
  TLS_KEY_FILE="${SSL_DIR}/key.pem"
  ACME_RELOAD_HELPER="${workdir}/cert-reload.sh"
  mkdir -p "${BACKUP_DIR}" "${XRAY_CONFIG_DIR}" "${SSL_DIR}"

  printf 'old-xray\n' > "${XRAY_CONFIG_FILE}"
  printf 'old-haproxy\n' > "${HAPROXY_CONFIG}"
  printf 'old-nginx\n' > "${NGINX_CONFIG_FILE}"
  printf 'old-service\n' > "${XRAY_SERVICE_FILE}"
  printf 'old-cert\n' > "${TLS_CERT_FILE}"
  printf 'old-key\n' > "${TLS_KEY_FILE}"
  printf 'old-helper\n' > "${ACME_RELOAD_HELPER}"

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
  backup_path "${XRAY_CONFIG_FILE}"
  backup_path "${HAPROXY_CONFIG}"
  backup_path "${NGINX_CONFIG_FILE}"
  backup_path "${XRAY_SERVICE_FILE}"
  backup_path "${TLS_CERT_FILE}"
  backup_path "${TLS_KEY_FILE}"
  backup_path "${ACME_RELOAD_HELPER}"

  printf 'new-xray\n' > "${XRAY_CONFIG_FILE}"
  printf 'new-haproxy\n' > "${HAPROXY_CONFIG}"
  printf 'new-nginx\n' > "${NGINX_CONFIG_FILE}"
  printf 'new-service\n' > "${XRAY_SERVICE_FILE}"
  printf 'new-cert\n' > "${TLS_CERT_FILE}"
  printf 'new-key\n' > "${TLS_KEY_FILE}"
  printf 'new-helper\n' > "${ACME_RELOAD_HELPER}"

  ensure_xray_user() { :; }
  ensure_managed_permissions() { :; }
  systemctl() { :; }
  warn() { :; }

  rollback_managed_runtime_state "yes" "yes"

  [[ "$(cat "${XRAY_CONFIG_FILE}")" == "old-xray" ]]
  [[ "$(cat "${HAPROXY_CONFIG}")" == "old-haproxy" ]]
  [[ "$(cat "${NGINX_CONFIG_FILE}")" == "old-nginx" ]]
  [[ "$(cat "${XRAY_SERVICE_FILE}")" == "old-service" ]]
  [[ "$(cat "${TLS_CERT_FILE}")" == "old-cert" ]]
  [[ "$(cat "${TLS_KEY_FILE}")" == "old-key" ]]
  [[ "$(cat "${ACME_RELOAD_HELPER}")" == "old-helper" ]]
}

run_warp_xml_escape_case() {
  local workdir=""

  workdir="$(mktemp -d)"
  WARP_MDM_FILE="${workdir}/mdm.xml"
  WARP_CLIENT_ID='id&<>"'"'"'value'
  WARP_CLIENT_SECRET='sec&<>"'"'"'value'
  WARP_TEAM_NAME='team&<>"'"'"'value'
  WARP_PROXY_PORT="40000"

  write_warp_mdm_file

  python3 - <<'PY' "${WARP_MDM_FILE}"
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
root = ET.parse(path).getroot()
values = [node.text for node in root.findall('string')]
assert values[0] == 'id&<>"\'value'
assert values[1] == 'sec&<>"\'value'
assert values[2] == 'team&<>"\'value'
print('xml ok')
PY
}

run_warp_health_monitor_case() {
  local workdir=""

  workdir="$(mktemp -d)"
  WARP_HEALTH_HELPER="${workdir}/warp-health.sh"
  WARP_HEALTH_SERVICE_FILE="${workdir}/warp-health.service"
  WARP_HEALTH_TIMER_FILE="${workdir}/warp-health.timer"
  WARP_HEALTH_SERVICE_NAME="xray-warp-team-warp-health.service"
  WARP_HEALTH_TIMER_NAME="xray-warp-team-warp-health.timer"
  HEALTH_STATE_FILE="${workdir}/health-state.env"
  HEALTH_HISTORY_FILE="${workdir}/health-history.log"
  WARP_PROXY_PORT="41000"

  write_warp_health_helper
  write_warp_health_service
  write_warp_health_timer

  assert_contains 'proxy_port='\''41000'\''' "${WARP_HEALTH_HELPER}"
  assert_contains "health_state_file='${HEALTH_STATE_FILE}'" "${WARP_HEALTH_HELPER}"
  assert_contains "health_history_file='${HEALTH_HISTORY_FILE}'" "${WARP_HEALTH_HELPER}"
  assert_contains 'dirname "${health_state_file}"' "${WARP_HEALTH_HELPER}"
  assert_contains '$(date -u '\''+%Y-%m-%dT%H:%M:%SZ'\'')' "${WARP_HEALTH_HELPER}"
  assert_contains 'curl --socks5-hostname "127.0.0.1:${proxy_port}"' "${WARP_HEALTH_HELPER}"
  assert_contains "ExecStart=${WARP_HEALTH_HELPER}" "${WARP_HEALTH_SERVICE_FILE}"
  assert_contains 'OnUnitActiveSec=5min' "${WARP_HEALTH_TIMER_FILE}"
  assert_contains "Unit=${WARP_HEALTH_SERVICE_NAME}" "${WARP_HEALTH_TIMER_FILE}"
}

run_restart_optional_service_case() {
  local restarted=()

  load_dashboard_context() {
    ENABLE_WARP="no"
    ENABLE_NET_OPT="no"
  }
  restart_service_if_present() {
    restarted+=("${1}")
  }
  log() { :; }

  restart_cmd
  [[ " ${restarted[*]} " == *" xray.service "* ]]
  [[ " ${restarted[*]} " == *" haproxy.service "* ]]
  [[ " ${restarted[*]} " == *" nginx.service "* ]]
  [[ " ${restarted[*]} " == *" ${CORE_HEALTH_TIMER_NAME} "* ]]
  [[ " ${restarted[*]} " != *" warp-svc.service "* ]]
  [[ " ${restarted[*]} " != *" ${WARP_HEALTH_TIMER_NAME} "* ]]
  [[ " ${restarted[*]} " != *" ${NET_SERVICE_NAME} "* ]]

  restarted=()
  load_dashboard_context() {
    ENABLE_WARP="yes"
    ENABLE_NET_OPT="yes"
  }

  restart_cmd
  [[ " ${restarted[*]} " == *" warp-svc.service "* ]]
  [[ " ${restarted[*]} " == *" ${WARP_HEALTH_TIMER_NAME} "* ]]
  [[ " ${restarted[*]} " == *" ${NET_SERVICE_NAME} "* ]]
  load_functions
}

run_change_helper_case() {
  local original_prompt=""
  local -A uuid_request=()
  local -A warp_request=()
  local -A cert_request=()

  original_prompt="$(declare -f prompt_with_default)"
  NON_INTERACTIVE=0
  init_change_uuid_request uuid_request
  parse_change_uuid_args uuid_request \
    --non-interactive \
    --reality-uuid 11111111-1111-1111-1111-111111111111 \
    --xhttp-only
  [[ "${NON_INTERACTIVE}" -eq 1 ]]
  [[ "${uuid_request[rotate_reality]}" == "0" ]]
  [[ "${uuid_request[rotate_xhttp]}" == "1" ]]
  [[ "${uuid_request[reality_uuid]}" == "11111111-1111-1111-1111-111111111111" ]]

  NON_INTERACTIVE=0
  init_change_warp_request warp_request
  parse_change_warp_args warp_request \
    --non-interactive \
    --enable-warp \
    --warp-team team-name \
    --warp-client-id client-id \
    --warp-client-secret client-secret \
    --warp-proxy-port 41000
  [[ "${NON_INTERACTIVE}" -eq 1 ]]
  [[ "${warp_request[target_mode]}" == "enable" ]]
  [[ "${warp_request[warp_team_name]}" == "team-name" ]]
  [[ "${warp_request[warp_client_id]}" == "client-id" ]]
  [[ "${warp_request[warp_client_secret]}" == "client-secret" ]]
  [[ "${warp_request[warp_proxy_port]}" == "41000" ]]

  NON_INTERACTIVE=0
  init_change_cert_mode_request cert_request
  parse_change_cert_mode_args cert_request \
    --non-interactive \
    --cert-mode existing \
    --xhttp-domain cdn.example.com \
    --cert-file /tmp/cert.pem \
    --key-file /tmp/key.pem \
    --cf-zone-id zone-id \
    --acme-email ops@example.com
  [[ "${NON_INTERACTIVE}" -eq 1 ]]
  [[ "${cert_request[cert_mode_overridden]}" == "1" ]]
  [[ "${cert_request[xhttp_domain_overridden]}" == "1" ]]
  [[ "${cert_request[cert_mode]}" == "existing" ]]
  [[ "${cert_request[xhttp_domain]}" == "cdn.example.com" ]]
  [[ "${cert_request[cert_source_file]}" == "/tmp/cert.pem" ]]
  [[ "${cert_request[key_source_file]}" == "/tmp/key.pem" ]]
  [[ "${cert_request[cf_zone_id]}" == "zone-id" ]]
  [[ "${cert_request[acme_email]}" == "ops@example.com" ]]

  CERT_SOURCE_FILE="old-cert.pem"
  apply_optional_override CERT_SOURCE_FILE ""
  [[ "${CERT_SOURCE_FILE}" == "old-cert.pem" ]]
  apply_optional_override CERT_SOURCE_FILE "new-cert.pem"
  [[ "${CERT_SOURCE_FILE}" == "new-cert.pem" ]]
  apply_optional_override CERT_SOURCE_FILE "" "1"
  [[ -z "${CERT_SOURCE_FILE}" ]]

  CF_DNS_ACCOUNT_ID="old-account"
  cert_request[cf_dns_account_id]=""
  cert_request["$(request_value_presence_key "cf_dns_account_id")"]="1"
  apply_request_overrides cert_request "cf_dns_account_id:CF_DNS_ACCOUNT_ID"
  [[ -z "${CF_DNS_ACCOUNT_ID}" ]]

  CERT_MODE="existing"
  XHTTP_DOMAIN="cdn.old.example.com"
  resolve_cert_mode_change_targets "existing" "cdn.old.example.com" 1 1 "self-signed" "cdn.new.example.com"
  [[ "${CERT_MODE}" == "self-signed" ]]
  [[ "${XHTTP_DOMAIN}" == "cdn.new.example.com" ]]

  prompt_with_default() {
    local var_name="${1}"

    case "${var_name}" in
      CERT_MODE)
        printf -v "${var_name}" '%s' "cf-origin-ca"
        ;;
      XHTTP_DOMAIN)
        printf -v "${var_name}" '%s' "cdn.prompt.example.com"
        ;;
      *)
        return 1
        ;;
    esac
  }

  resolve_cert_mode_change_targets "existing" "cdn.old.example.com" 0 0 "" ""
  [[ "${CERT_MODE}" == "cf-origin-ca" ]]
  [[ "${XHTTP_DOMAIN}" == "cdn.prompt.example.com" ]]

  eval "${original_prompt}"
}

run_change_command_case() {
  local output=""
  local runtime_updated=0
  local runtime_sni=""
  local runtime_target=""
  local state_written=0
  local output_written=0
  local written_prefix=""
  local shown_links=0
  local rules_written=""

  need_root() { :; }
  start_backup_session() { BACKUP_DIR="/tmp/change-backup"; }
  load_current_install_context() {
    REALITY_SNI="old.example.com"
    REALITY_TARGET="www.harvard.edu:443"
    XHTTP_PATH="/old"
    NODE_LABEL_PREFIX="HKG"
    CERT_MODE="existing"
    XHTTP_DOMAIN="cdn.old.example.com"
    ENABLE_WARP="no"
    WARP_TEAM_NAME="old-team"
    WARP_CLIENT_ID="old-id"
    WARP_CLIENT_SECRET="old-secret"
    WARP_PROXY_PORT="40000"
    WARP_RULES_TEXT=$'geosite:google\ndomain:github.com'
  }
  begin_managed_output_change() {
    NODE_LABEL_PREFIX="HKG"
  }
  apply_managed_runtime_update() {
    runtime_updated=1
    runtime_sni="${REALITY_SNI}"
    runtime_target="${REALITY_TARGET}"
    rules_written="${WARP_RULES_TEXT}"
  }
  write_state_file() {
    state_written=1
    written_prefix="${NODE_LABEL_PREFIX}"
  }
  write_output_file() {
    output_written=1
  }
  show_links() {
    shown_links=$((shown_links + 1))
  }
  log() { :; }
  log_step() { :; }
  log_success() { :; }

  NON_INTERACTIVE=0
  change_sni_cmd --non-interactive --reality-sni new.example.com
  [[ "${runtime_updated}" -eq 1 ]]
  [[ "${runtime_sni}" == "new.example.com" ]]
  [[ "${runtime_target}" == "www.harvard.edu:443" ]]
  [[ "${shown_links}" -eq 1 ]]

  NON_INTERACTIVE=0
  change_label_prefix_cmd --non-interactive
  [[ "${state_written}" -eq 1 ]]
  [[ "${output_written}" -eq 1 ]]
  [[ "${written_prefix}" == "HKG" ]]
  [[ "${shown_links}" -eq 2 ]]

  load_current_install_context() {
    return 99
  }
  begin_managed_output_change() {
    NODE_LABEL_PREFIX="LAX"
    SERVER_IP="203.0.113.30"
    REALITY_UUID="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    REALITY_SNI="reality.example.com"
    REALITY_PUBLIC_KEY="public-key"
    REALITY_SHORT_ID="abcd1234"
    XHTTP_UUID="bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    XHTTP_DOMAIN="cdn.example.com"
    XHTTP_PATH="/edge"
    XHTTP_VLESS_ENCRYPTION_ENABLED="no"
    XHTTP_VLESS_ENCRYPTION=""
    XHTTP_VLESS_DECRYPTION="none"
    TLS_ALPN="h2"
    FINGERPRINT="chrome"
    ENABLE_WARP="no"
    ENABLE_NET_OPT="no"
    CERT_MODE="existing"
  }
  NON_INTERACTIVE=0
  change_label_prefix_cmd --non-interactive --node-label-prefix nrt
  [[ "${written_prefix}" == "NRT" ]]

  load_current_install_context() {
    REALITY_SNI="old.example.com"
    REALITY_TARGET="www.harvard.edu:443"
    XHTTP_PATH="/old"
    NODE_LABEL_PREFIX="HKG"
    CERT_MODE="existing"
    XHTTP_DOMAIN="cdn.old.example.com"
    ENABLE_WARP="no"
    WARP_TEAM_NAME="old-team"
    WARP_CLIENT_ID="old-id"
    WARP_CLIENT_SECRET="old-secret"
    WARP_PROXY_PORT="40000"
    WARP_RULES_TEXT=$'geosite:google\ndomain:github.com'
  }

  NON_INTERACTIVE=0
  change_warp_rules_cmd --non-interactive --add-domain chat.openai.com --del-domain github.com
  [[ "${runtime_updated}" -eq 1 ]]
  [[ "${rules_written}" == *$'domain:chat.openai.com'* ]]
  [[ "${rules_written}" != *$'domain:github.com'* ]]
  [[ "${shown_links}" -eq 4 ]]

  load_existing_state() {
    WARP_RULES_TEXT=$'geosite:google\ndomain:chat.openai.com'
  }
  runtime_updated=0
  shown_links=0
  output="$(change_warp_rules_cmd --list)"
  [[ "${runtime_updated}" -eq 0 ]]
  [[ "${shown_links}" -eq 0 ]]
  [[ "${output}" == *"domain:chat.openai.com"* ]]
}

run_change_warp_enable_rollback_case() {
  local rolled_back=0
  local status=0

  parse_change_warp_args() {
    local -n request_ref="${1}"
    request_ref[target_mode]="enable"
  }
  ensure_debian_family() { :; }
  begin_managed_change() { :; }
  apply_warp_change_request() { :; }
  prompt_warp_settings() { :; }
  install_warp() { :; }
  apply_managed_runtime_update() {
    return 1
  }
  rollback_optional_component_state() {
    rolled_back=$((rolled_back + 1))
  }

  set +e
  change_warp_cmd --enable-warp >/dev/null 2>&1
  status=$?
  set -e

  [[ "${status}" -ne 0 ]]
  [[ "${rolled_back}" -eq 1 ]]
  load_functions
}

run_renew_cert_command_case() {
  local applied=0
  local shown_links=0
  local logged=""

  need_root() { :; }
  start_backup_session() { BACKUP_DIR="/tmp/renew-backup"; }
  load_current_install_context() {
    CERT_MODE="acme-dns-cf"
    XHTTP_DOMAIN="cdn.old.example.com"
    REALITY_SNI="old.example.com"
    REALITY_TARGET="www.harvard.edu:443"
    XHTTP_PATH="/old"
    WARP_PROXY_PORT="40000"
  }
  apply_managed_update() {
    applied=$((applied + 1))
  }
  show_links() {
    shown_links=$((shown_links + 1))
  }
  log() {
    logged+="${1}"$'\n'
  }
  log_step() {
    logged+="STEP:${1}"$'\n'
  }
  log_success() {
    logged+="OK:${1}"$'\n'
  }
  resolve_install_input_sources() { :; }
  prompt_cert_mode_inputs() { :; }
  validate_install_inputs() { :; }

  renew_cert_cmd --non-interactive --acme-email ops@example.com --cf-dns-token dns-token
  [[ "${applied}" -eq 1 ]]
  [[ "${shown_links}" -eq 1 ]]
  printf '%s' "${logged}" | grep -q 'STEP:刷新 TLS 证书资产。'
  printf '%s' "${logged}" | grep -q 'OK:证书已续期。'
}

run_upgrade_command_case() {
  local logged=""
  local restored=()
  local restarted=0
  local status=0
  local workdir=""

  workdir="$(mktemp -d)"

  need_root() { :; }
  ensure_debian_family() { :; }
  start_backup_session() { BACKUP_DIR="/tmp/upgrade-backup"; }
  backup_path() { :; }
  install_xray() { :; }
  ensure_xray_bind_capability() { :; }
  validate_configs() { return 1; }
  restore_backup_path() {
    restored+=("${1}")
  }
  systemctl() {
    restarted=$((restarted + 1))
  }
  log() {
    logged+="${1}"$'\n'
  }
  log_step() {
    logged+="STEP:${1}"$'\n'
  }
  log_success() {
    logged+="OK:${1}"$'\n'
  }
  warn() {
    logged+="WARN:${1}"$'\n'
  }
  XRAY_BIN="${workdir}/xray"
  XRAY_ASSET_DIR="${workdir}/xray-assets"
  printf '#!/usr/bin/env bash\n' > "${XRAY_BIN}"
  chmod 0755 "${XRAY_BIN}"
  mkdir -p "${XRAY_ASSET_DIR}"

  set +e
  upgrade_cmd
  status=$?
  set -e
  [[ "${status}" -ne 0 ]]
  [[ "${restored[*]}" == "${XRAY_BIN} ${XRAY_ASSET_DIR}" ]]
  [[ "${restarted}" -eq 0 ]]
  printf '%s' "${logged}" | grep -q 'STEP:升级 Xray 核心。'
  printf '%s' "${logged}" | grep -q 'WARN:升级后的配置校验失败，正在回滚 Xray 核心文件。'
}

run_diagnose_command_case() {
  local output=""
  local status=0
  local probe_file=""

  probe_file="$(mktemp)"

  load_dashboard_context() { :; }
  service_active_state() {
    case "${1}" in
      xray.service|haproxy.service|nginx.service|warp-svc.service|${CORE_HEALTH_TIMER_NAME}|${WARP_HEALTH_TIMER_NAME})
        printf 'active'
        ;;
      *)
        printf 'unknown'
        ;;
    esac
  }
  listening_port_text() { printf '运行中'; }
  is_port_listening() { return 0; }
  xray_config_check_state() { printf 'ok'; }
  nginx_config_check_state() { printf 'ok'; }
  haproxy_config_check_state() { printf 'ok'; }
  local_tls_probe_state() { printf 'ok'; }
  xray_config_check_text() { printf '通过'; }
  nginx_config_check_text() { printf '通过'; }
  haproxy_config_check_text() { printf '通过'; }
  local_tls_probe_text() { printf '通过'; }
  cert_expiry_text() { printf 'Jun  1 00:00:00 2026 GMT'; }
  warp_exit_ip_text() {
    local count=0
    count="$(cat "${probe_file}" 2>/dev/null || printf '0')"
    printf '%s' "$((count + 1))" > "${probe_file}"
    printf '203.0.113.99'
  }
  health_event_text() { printf 'ok'; }
  latest_health_history_text() { printf 'latest history'; }

  output="$(diagnose_cmd)"
  printf '%s' "${output}" | grep -q 'Xray WARP 诊断'
  printf '%s' "${output}" | grep -q '监听 443: 运行中'
  printf '%s' "${output}" | grep -q '诊断摘要: 未发现关键问题'
  [[ "$(cat "${probe_file}")" == "1" ]]

  service_active_state() { printf 'failed'; }
  printf '0' > "${probe_file}"
  set +e
  output="$(diagnose_cmd 2>&1)"
  status=$?
  set -e
  [[ "${status}" -ne 0 ]]
  printf '%s' "${output}" | grep -q '诊断摘要: 检测到'
  printf '%s' "${output}" | grep -q '服务: xray 未运行'
  [[ "$(cat "${probe_file}")" == "1" ]]
}
