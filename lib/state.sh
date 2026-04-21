# shellcheck shell=bash

# ------------------------------
# 状态与配置读取层
# 负责状态文件、托管输出、配置回填
# ------------------------------

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

reset_loaded_runtime_context() {
  REALITY_UUID=""
  REALITY_SNI=""
  REALITY_TARGET=""
  REALITY_SHORT_ID=""
  REALITY_PRIVATE_KEY=""
  REALITY_PUBLIC_KEY=""
  XHTTP_UUID=""
  XHTTP_DOMAIN=""
  XHTTP_PATH=""
  XHTTP_VLESS_ENCRYPTION_ENABLED=""
  XHTTP_VLESS_DECRYPTION=""
  XHTTP_VLESS_ENCRYPTION=""
  TLS_ALPN=""
  SERVER_IP=""
  NODE_LABEL_PREFIX=""
  FINGERPRINT=""
  ENABLE_WARP=""
  ENABLE_NET_OPT=""
  WARP_PROXY_PORT=""
  WARP_TEAM_NAME=""
  WARP_CLIENT_ID=""
  WARP_CLIENT_SECRET=""
  WARP_RULES_TEXT=""
  CERT_MODE=""
  CF_ZONE_ID=""
  CF_CERT_VALIDITY=""
  ACME_EMAIL=""
  ACME_CA=""
  CF_DNS_ACCOUNT_ID=""
  CF_DNS_ZONE_ID=""
  XHTTP_ECH_CONFIG_LIST=""
  XHTTP_ECH_FORCE_QUERY=""
  CORE_HEALTH_LAST_CHECK_AT=""
  CORE_HEALTH_LAST_ACTION=""
  CORE_HEALTH_LAST_REASON=""
  WARP_HEALTH_LAST_CHECK_AT=""
  WARP_HEALTH_LAST_ACTION=""
  WARP_HEALTH_LAST_REASON=""
}

nginx_server_name() {
  local path_hint="${1}"

  [[ -f "${NGINX_CONFIG_FILE}" ]] || return 0
  awk -v path_hint="${path_hint}" '
    function brace_delta(line, opens, closes, tmp) {
      tmp = line
      opens = gsub(/\{/, "{", tmp)
      closes = gsub(/\}/, "}", tmp)
      return opens - closes
    }

    /^[[:space:]]*server[[:space:]]*\{/ {
      in_server = 1
      depth = brace_delta($0)
      current = ""
      wanted = 0
      next
    }

    in_server {
      if ($0 ~ /^[[:space:]]*server_name[[:space:]]+/) {
        line = $0
        sub(/^[[:space:]]*server_name[[:space:]]+/, "", line)
        sub(/;.*/, "", line)
        current = line
      }

      if ($0 ~ /^[[:space:]]*location[[:space:]]+\// && index($0, path_hint)) {
        wanted = 1
      }

      if (wanted && current != "") {
        print current
        exit
      }

      depth += brace_delta($0)
      if (depth <= 0) {
        in_server = 0
        current = ""
        wanted = 0
      }
    }
  ' "${NGINX_CONFIG_FILE}" 2>/dev/null | head -n 1
}

load_existing_state() {
  reset_loaded_runtime_context

  if [[ -f "${STATE_FILE}" ]]; then
    # shellcheck disable=SC1090
    . "${STATE_FILE}"
    if [[ "${STATE_VERSION:-0}" != "${STATE_VERSION_CURRENT}" ]]; then
      warn "检测到旧版本状态文件（${STATE_VERSION:-0} -> ${STATE_VERSION_CURRENT}），将按当前脚本默认值补全缺失字段。"
    fi
  fi
  if [[ "${XHTTP_ECH_CONFIG_LIST:-}" == "https://1.1.1.1/dns-query" && "${XHTTP_ECH_FORCE_QUERY:-}" == "none" ]]; then
    XHTTP_ECH_CONFIG_LIST=""
    XHTTP_ECH_FORCE_QUERY=""
  fi
  if [[ -f "${HEALTH_STATE_FILE}" ]]; then
    # shellcheck disable=SC1090
    . "${HEALTH_STATE_FILE}"
  fi
  load_warp_mdm_context
}

config_has_warp_outbound() {
  [[ "$(config_jq_read '.outbounds[] | select(.tag=="WARP") | .tag')" == "WARP" ]]
}

load_config_runtime_context() {
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
  if [[ -z "${ENABLE_WARP:-}" ]]; then
    if config_has_warp_outbound; then
      ENABLE_WARP="yes"
    else
      ENABLE_WARP="no"
    fi
  fi
  WARP_PROXY_PORT="${WARP_PROXY_PORT:-$(config_jq_read '.outbounds[] | select(.tag=="WARP") | .settings.servers[0].port')}"
}

load_output_runtime_context() {
  SERVER_IP="${SERVER_IP:-$(output_field_value '地址')}"
  NODE_LABEL_PREFIX="${NODE_LABEL_PREFIX:-$(output_field_value '节点名前缀')}"
  REALITY_PUBLIC_KEY="${REALITY_PUBLIC_KEY:-$(output_field_value '公钥')}"
  FINGERPRINT="${FINGERPRINT:-$(output_field_value '指纹')}"
}

normalize_runtime_defaults() {
  SERVER_IP="${SERVER_IP:-$(guess_server_ip)}"
  NODE_LABEL_PREFIX="${NODE_LABEL_PREFIX:-$(default_node_label_prefix)}"
  FINGERPRINT="${FINGERPRINT:-${DEFAULT_FINGERPRINT}}"
  CERT_MODE="${CERT_MODE:-existing}"
  ACME_CA="${ACME_CA:-${DEFAULT_ACME_CA}}"
  XHTTP_ECH_CONFIG_LIST="${XHTTP_ECH_CONFIG_LIST:-${DEFAULT_XHTTP_ECH_CONFIG_LIST}}"
  XHTTP_ECH_FORCE_QUERY="${XHTTP_ECH_FORCE_QUERY:-${DEFAULT_XHTTP_ECH_FORCE_QUERY}}"
  ENABLE_NET_OPT="${ENABLE_NET_OPT:-$(if [[ -f "${NET_SERVICE_FILE}" || -f "${NET_SYSCTL_CONF}" ]]; then printf 'yes'; else printf 'no'; fi)}"
  WARP_PROXY_PORT="${WARP_PROXY_PORT:-${DEFAULT_WARP_PROXY_PORT}}"
}

sync_xhttp_vless_encryption_state() {
  if [[ "${XHTTP_VLESS_DECRYPTION:-}" == "none" || -z "${XHTTP_VLESS_DECRYPTION:-}" ]]; then
    XHTTP_VLESS_ENCRYPTION_ENABLED="${XHTTP_VLESS_ENCRYPTION_ENABLED:-no}"
  else
    XHTTP_VLESS_ENCRYPTION_ENABLED="${XHTTP_VLESS_ENCRYPTION_ENABLED:-yes}"
  fi
}

load_managed_runtime_context() {
  # ------------------------------
  # 托管上下文只在这里回填一次
  # UI 与 change-* 共用同一份事实来源
  # ------------------------------
  load_config_runtime_context
  load_output_runtime_context
  normalize_runtime_defaults
  sync_xhttp_vless_encryption_state
}

load_dashboard_context() {
  load_existing_state

  [[ -f "${XRAY_CONFIG_FILE}" ]] || return 0
  load_managed_runtime_context
}

require_current_install_context() {
  [[ -n "${REALITY_UUID}" ]] || die "无法从当前安装中识别 REALITY UUID。"
  [[ -n "${REALITY_SNI}" ]] || die "无法从当前安装中识别 REALITY SNI。"
  [[ -n "${REALITY_TARGET}" ]] || die "无法从当前安装中识别 REALITY 目标地址。"
  [[ -n "${REALITY_SHORT_ID}" ]] || die "无法从当前安装中识别 REALITY 短 ID。"
  [[ -n "${REALITY_PRIVATE_KEY}" ]] || die "无法从当前安装中识别 REALITY 私钥。"
  [[ -n "${XHTTP_UUID}" ]] || die "无法从当前安装中识别 XHTTP UUID。"
  [[ -n "${XHTTP_DOMAIN}" ]] || die "无法从当前安装中识别 XHTTP 域名。"
  [[ -n "${XHTTP_PATH}" ]] || die "无法从当前安装中识别 XHTTP 路径。"
}

load_current_install_context() {
  load_existing_state

  [[ -f "${XRAY_CONFIG_FILE}" ]] || die "找不到当前 Xray 配置：${XRAY_CONFIG_FILE}"
  load_managed_runtime_context
  require_current_install_context
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

state_file_text() {
  # ------------------------------
  # 状态文件统一走 shell 转义
  # 避免密钥或路径里的特殊字符污染 source
  # ------------------------------
  write_state_kv "STATE_VERSION" "${STATE_VERSION_CURRENT}"
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
}

write_state_file() {
  write_generated_file_atomically "${STATE_FILE}" state_file_text
  chmod 0600 "${STATE_FILE}"
}
