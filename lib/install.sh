# shellcheck shell=bash

# ------------------------------
# 安装与副作用层
# 负责安装依赖、证书处理、WARP、网络优化
# 以及安装前输入准备
# ------------------------------

install_packages() {
  log_step "安装依赖包。"
  apt-get update
  apt-get install -y ca-certificates curl gnupg haproxy nginx iproute2 jq kmod openssl unzip uuid-runtime libcap2-bin
  log_success "依赖包安装完成。"
}

xray_release_base_url() {
  printf '%s' "https://github.com/XTLS/Xray-core/releases/latest/download"
}

xray_release_api_url() {
  printf '%s' "https://api.github.com/repos/XTLS/Xray-core/releases/latest"
}

managed_package_names() {
  printf '%s\n' \
    "haproxy" \
    "nginx" \
    "nginx-common" \
    "jq" \
    "uuid-runtime" \
    "cloudflare-warp"
}

xray_archive_name() {
  local arch="${1}"
  printf 'Xray-linux-%s.zip' "${arch}"
}

xray_digest_name() {
  local archive_name="${1}"
  printf '%s.dgst' "${archive_name}"
}

fetch_xray_release_metadata_json() {
  curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$(xray_release_api_url)"
}

xray_release_asset_field_from_metadata() {
  local metadata_json="${1}"
  local asset_name="${2}"
  local field_name="${3}"

  [[ -n "${metadata_json}" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  jq -r \
    --arg asset_name "${asset_name}" \
    --arg field_name "${field_name}" \
    '.assets[]? | select(.name == $asset_name) | .[$field_name] // empty' \
    <<< "${metadata_json}" 2>/dev/null | head -n 1
}

normalize_xray_sha256_value() {
  local raw_value="${1:-}"
  local normalized=""

  normalized="$(printf '%s' "${raw_value}" | tr 'A-Z' 'a-z' | sed -E 's/^[[:space:]]*sha256:[[:space:]]*//; s/^[[:space:]]+|[[:space:]]+$//g')"
  if [[ "${normalized}" =~ ^[0-9a-f]{64}$ ]]; then
    printf '%s' "${normalized}"
  fi
}

parse_xray_dgst_sha256() {
  local dgst_file="${1}"
  local asset_name="${2}"
  local value=""

  value="$(grep -Fi "${asset_name}" "${dgst_file}" 2>/dev/null | grep -Eo '[0-9a-fA-F]{64}' | head -n 1 || true)"
  if [[ -z "${value}" ]]; then
    value="$(grep -Ei 'sha256' "${dgst_file}" 2>/dev/null | grep -Eo '[0-9a-fA-F]{64}' | head -n 1 || true)"
  fi
  if [[ -z "${value}" ]]; then
    value="$(
      awk -v asset_name="${asset_name}" '
        BEGIN { IGNORECASE = 1; asset_seen = 0 }
        {
          line = tolower($0)
          if (index($0, asset_name) > 0) {
            asset_seen = 1
            next
          }

          if (asset_seen && line ~ /sha(2-)?256/) {
            if (match(line, /[0-9a-f]{64}/)) {
              print substr(line, RSTART, RLENGTH)
              exit
            }
          }
        }
      ' "${dgst_file}" 2>/dev/null || true
    )"
  fi
  if [[ -z "${value}" ]]; then
    value="$(grep -Eo '[0-9a-fA-F]{64}' "${dgst_file}" 2>/dev/null | head -n 1 || true)"
  fi

  normalize_xray_sha256_value "${value}"
}

verify_file_sha256() {
  local file_path="${1}"
  local expected_sha256="${2}"
  local label="${3}"
  local actual_sha256=""

  [[ -n "${expected_sha256}" ]] || die "${label} 缺少 SHA256 校验值。"
  actual_sha256="$(sha256sum "${file_path}" | awk '{print tolower($1)}')"
  [[ "${actual_sha256}" == "${expected_sha256}" ]] || die "${label} SHA256 校验失败。"
}

install_xray() {
  local arch=""
  local tmp_dir=""
  local archive_name=""
  local digest_name=""
  local base_url=""
  local release_metadata_json=""
  local archive_url=""
  local digest_url=""
  local archive_path=""
  local digest_path=""
  local expected_sha256=""
  local checksum_source=""

  arch="$(detect_xray_arch)"
  archive_name="$(xray_archive_name "${arch}")"
  digest_name="$(xray_digest_name "${archive_name}")"
  base_url="$(xray_release_base_url)"
  release_metadata_json="$(fetch_xray_release_metadata_json 2>/dev/null || true)"
  archive_url="$(xray_release_asset_field_from_metadata "${release_metadata_json}" "${archive_name}" "browser_download_url")"
  digest_url="$(xray_release_asset_field_from_metadata "${release_metadata_json}" "${digest_name}" "browser_download_url")"
  expected_sha256="$(normalize_xray_sha256_value "$(xray_release_asset_field_from_metadata "${release_metadata_json}" "${archive_name}" "digest")")"
  tmp_dir="$(mktemp -d)"
  archive_path="${tmp_dir}/${archive_name}"
  digest_path="${tmp_dir}/${digest_name}"

  log_step "下载 Xray-core 最新版本。"
  log "资源文件：${archive_name}"
  log "校验文件：${digest_name}"
  [[ -n "${archive_url}" ]] || archive_url="${base_url}/${archive_name}"
  curl -fsSL "${archive_url}" -o "${archive_path}"

  if [[ -n "${expected_sha256}" ]]; then
    checksum_source="GitHub Release API digest"
  else
    [[ -n "${digest_url}" ]] || digest_url="${base_url}/${digest_name}"
    curl -fsSL "${digest_url}" -o "${digest_path}"
    expected_sha256="$(parse_xray_dgst_sha256 "${digest_path}" "${archive_name}")"
    checksum_source="${digest_name}"
  fi

  log "校验来源：${checksum_source}"
  verify_file_sha256 "${archive_path}" "${expected_sha256}" "Xray-core 安装包"
  log_success "Xray-core 安装包校验通过。"
  unzip -qo "${archive_path}" -d "${tmp_dir}/xray"

  mkdir -p /usr/local/bin "${XRAY_CONFIG_DIR}" "${XRAY_ASSET_DIR}" /var/log/xray
  install -m 0755 "${tmp_dir}/xray/xray" "${XRAY_BIN}"

  if [[ -f "${tmp_dir}/xray/geoip.dat" ]]; then
    install -m 0644 "${tmp_dir}/xray/geoip.dat" "${XRAY_ASSET_DIR}/geoip.dat"
  fi

  if [[ -f "${tmp_dir}/xray/geosite.dat" ]]; then
    install -m 0644 "${tmp_dir}/xray/geosite.dat" "${XRAY_ASSET_DIR}/geosite.dat"
  fi

  rm -rf "${tmp_dir}"
  log_success "Xray-core 已安装到 ${XRAY_BIN}。"
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

  if [[ -f "${WARP_RULES_FILE}" ]]; then
    chown 0:"${XRAY_GID}" "${WARP_RULES_FILE}"
    chmod 0640 "${WARP_RULES_FILE}"
  fi

  if [[ -f "${HEALTH_STATE_FILE}" ]]; then
    chown 0:"${XRAY_GID}" "${HEALTH_STATE_FILE}"
    chmod 0640 "${HEALTH_STATE_FILE}"
  fi

  if [[ -f "${HEALTH_HISTORY_FILE}" ]]; then
    chown 0:"${XRAY_GID}" "${HEALTH_HISTORY_FILE}"
    chmod 0640 "${HEALTH_HISTORY_FILE}"
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

  if [[ -f "${WARP_APT_KEYRING}" ]]; then
    chown 0:0 "${WARP_APT_KEYRING}"
    chmod 0644 "${WARP_APT_KEYRING}"
  fi

  if [[ -f "${WARP_APT_SOURCE_LIST}" ]]; then
    chown 0:0 "${WARP_APT_SOURCE_LIST}"
    chmod 0644 "${WARP_APT_SOURCE_LIST}"
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

install_draft_file_text() {
  write_state_kv "SERVER_IP" "${SERVER_IP-}"
  write_state_kv "NODE_LABEL_PREFIX" "${NODE_LABEL_PREFIX-}"
  write_state_kv "REALITY_UUID" "${REALITY_UUID-}"
  write_state_kv "REALITY_SNI" "${REALITY_SNI-}"
  write_state_kv "REALITY_TARGET" "${REALITY_TARGET-}"
  write_state_kv "REALITY_SHORT_ID" "${REALITY_SHORT_ID-}"
  write_state_kv "REALITY_PRIVATE_KEY" "${REALITY_PRIVATE_KEY-}"
  write_state_kv "XHTTP_UUID" "${XHTTP_UUID-}"
  write_state_kv "XHTTP_DOMAIN" "${XHTTP_DOMAIN-}"
  write_state_kv "XHTTP_PATH" "${XHTTP_PATH-}"
  write_state_kv "XHTTP_VLESS_ENCRYPTION_ENABLED" "${XHTTP_VLESS_ENCRYPTION_ENABLED-}"
  write_state_kv "CERT_MODE" "${CERT_MODE-}"
  write_state_kv "CERT_SOURCE_FILE" "${CERT_SOURCE_FILE-}"
  write_state_kv "KEY_SOURCE_FILE" "${KEY_SOURCE_FILE-}"
  write_state_kv "CERT_SOURCE_PEM" "${CERT_SOURCE_PEM-}"
  write_state_kv "KEY_SOURCE_PEM" "${KEY_SOURCE_PEM-}"
  write_state_kv "CF_ZONE_ID" "${CF_ZONE_ID-}"
  write_state_kv "CF_API_TOKEN" "${CF_API_TOKEN-}"
  write_state_kv "CF_CERT_VALIDITY" "${CF_CERT_VALIDITY-}"
  write_state_kv "ACME_EMAIL" "${ACME_EMAIL-}"
  write_state_kv "ACME_CA" "${ACME_CA-}"
  write_state_kv "CF_DNS_TOKEN" "${CF_DNS_TOKEN-}"
  write_state_kv "CF_DNS_ACCOUNT_ID" "${CF_DNS_ACCOUNT_ID-}"
  write_state_kv "CF_DNS_ZONE_ID" "${CF_DNS_ZONE_ID-}"
  write_state_kv "ENABLE_WARP" "${ENABLE_WARP-}"
  write_state_kv "ENABLE_NET_OPT" "${ENABLE_NET_OPT-}"
  write_state_kv "WARP_TEAM_NAME" "${WARP_TEAM_NAME-}"
  write_state_kv "WARP_CLIENT_ID" "${WARP_CLIENT_ID-}"
  write_state_kv "WARP_CLIENT_SECRET" "${WARP_CLIENT_SECRET-}"
  write_state_kv "WARP_PROXY_PORT" "${WARP_PROXY_PORT-}"
}

load_install_draft_file() {
  [[ -f "${INSTALL_DRAFT_FILE}" ]] || return 0
  load_shell_kv_file "${INSTALL_DRAFT_FILE}"
}

write_install_draft_file() {
  write_generated_file_atomically "${INSTALL_DRAFT_FILE}" install_draft_file_text
  chmod 0600 "${INSTALL_DRAFT_FILE}"
}

clear_install_draft_file() {
  rm -f "${INSTALL_DRAFT_FILE}"
}

purge_managed_packages() {
  local packages=()

  mapfile -t packages < <(managed_package_names)
  [[ "${#packages[@]}" -gt 0 ]] || return 0
  apt-get purge -y "${packages[@]}" >/dev/null 2>&1 || warn "部分软件包卸载失败，请手动检查 apt 输出。"
  apt-get autoremove -y >/dev/null 2>&1 || true
}

install_draft_session_begin() {
  INSTALL_DRAFT_SESSION_ACTIVE="1"
  trap 'install_draft_session_handle_exit "$?"' EXIT
  trap 'install_draft_session_handle_signal 130' INT
  trap 'install_draft_session_handle_signal 143' TERM
}

install_draft_session_disarm() {
  trap - EXIT INT TERM
  INSTALL_DRAFT_SESSION_ACTIVE="0"
}

install_draft_session_persist() {
  write_install_draft_file >/dev/null 2>&1 || true
}

install_draft_session_handle_exit() {
  local exit_status="${1:-0}"

  if [[ "${INSTALL_DRAFT_SESSION_ACTIVE:-0}" == "1" && "${exit_status}" -ne 0 ]]; then
    install_draft_session_persist
  fi

  install_draft_session_disarm
  return "${exit_status}"
}

install_draft_session_handle_signal() {
  local exit_status="${1}"

  if [[ "${INSTALL_DRAFT_SESSION_ACTIVE:-0}" == "1" ]]; then
    install_draft_session_persist
  fi

  install_draft_session_disarm
  exit "${exit_status}"
}

install_draft_session_abort() {
  if [[ "${INSTALL_DRAFT_SESSION_ACTIVE:-0}" == "1" ]]; then
    install_draft_session_persist
  fi

  install_draft_session_disarm
}

install_draft_session_finish() {
  clear_install_draft_file
  install_draft_session_disarm
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
  prompt_cert_mode_selection "TLS 证书模式序号" "self-signed"
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
  [[ -n "${sni}" ]] || return 0
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

show_cert_mode_menu() {
  cat <<'EOF'
证书模式:
  1. 自签名
  2. 现有证书
  3. Cloudflare Origin CA
  4. ACME DNS (Cloudflare)
EOF
}

prompt_cert_mode_selection() {
  local prompt_text="${1}"
  local default_mode="${2}"
  local default_choice=""

  default_choice="$(cert_mode_choice_value "${default_mode}")"
  [[ -n "${CERT_MODE:-}" ]] || show_cert_mode_menu
  prompt_with_default CERT_MODE "${prompt_text}" "${default_choice}"
  CERT_MODE="$(validate_cert_mode_value "${CERT_MODE}")"
}

prompt_warp_settings() {
  resolve_value_source WARP_TEAM_NAME
  resolve_value_source WARP_CLIENT_ID
  resolve_value_source WARP_CLIENT_SECRET
  resolve_value_source WARP_PROXY_PORT
  prompt_with_default WARP_TEAM_NAME "Cloudflare Zero Trust 团队名" "${WARP_TEAM_NAME:-}"
  prompt_with_default WARP_CLIENT_ID "Cloudflare 服务令牌 Client ID" "${WARP_CLIENT_ID:-}"
  prompt_secret WARP_CLIENT_SECRET "Cloudflare 服务令牌 Client Secret"
  prompt_with_default WARP_PROXY_PORT "本地 WARP SOCKS5 端口" "${WARP_PROXY_PORT:-${DEFAULT_WARP_PROXY_PORT}}"
}

default_warp_rules_text() {
  cat <<'EOF'
geosite:google
geosite:youtube
geosite:openai
geosite:netflix
geosite:disney
domain:gemini.google.com
domain:claude.ai
domain:anthropic.com
domain:api.anthropic.com
domain:console.anthropic.com
domain:statsig.anthropic.com
domain:sentry.io
domain:x.com
domain:twitter.com
domain:t.co
domain:twimg.com
domain:github.com
domain:api.github.com
domain:githubcopilot.com
domain:copilot-proxy.githubusercontent.com
domain:origin-tracker.githubusercontent.com
domain:copilot-telemetry.githubusercontent.com
domain:collector.github.com
domain:default.exp-tas.com
EOF
}

normalize_warp_rule_value() {
  local raw_value="${1:-}"
  local trimmed=""

  trimmed="$(printf '%s' "${raw_value}" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [[ -n "${trimmed}" ]] || die "WARP 分流规则不能为空。"
  [[ "${trimmed}" != *[[:space:]]* ]] || die "WARP 分流规则不能包含空白字符：${trimmed}"

  case "${trimmed}" in
    domain:*)
      validate_hostname_value "WARP 域名规则" "${trimmed#domain:}"
      printf '%s' "${trimmed}"
      ;;
    geosite:*)
      [[ "${trimmed#geosite:}" =~ ^[A-Za-z0-9._-]+$ ]] || die "WARP geosite 规则不合法：${trimmed}"
      printf '%s' "${trimmed}"
      ;;
    *)
      validate_hostname_value "WARP 域名规则" "${trimmed}"
      printf 'domain:%s' "${trimmed}"
      ;;
  esac
}

normalize_warp_rules_text() {
  local input_text="${1:-}"
  local line=""
  local normalized_line=""
  local seen=""

  while IFS= read -r line; do
    line="$(printf '%s' "${line}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [[ -n "${line}" ]] || continue
    [[ "${line}" != \#* ]] || continue
    normalized_line="$(normalize_warp_rule_value "${line}")"

    case $'\n'"${seen}" in
      *$'\n'"${normalized_line}"$'\n'*)
        continue
        ;;
    esac

    seen+="${normalized_line}"$'\n'
    printf '%s\n' "${normalized_line}"
  done <<< "${input_text}"
}

current_warp_rules_text() {
  if [[ -n "${WARP_RULES_TEXT:-}" ]]; then
    printf '%s\n' "${WARP_RULES_TEXT}" | sed '/^$/d'
    return
  fi

  if [[ -f "${WARP_RULES_FILE}" ]]; then
    normalize_warp_rules_text "$(<"${WARP_RULES_FILE}")"
    return
  fi

  default_warp_rules_text
}

write_warp_rules_file() {
  local tmp_file=""
  local rules_text=""

  rules_text="$(normalize_warp_rules_text "$(current_warp_rules_text)")"
  mkdir -p "${XRAY_CONFIG_DIR}"
  backup_path "${WARP_RULES_FILE}"
  tmp_file="$(mktemp "${XRAY_CONFIG_DIR}/.warp-domains.list.tmp.XXXXXX")"
  printf '%s\n' "${rules_text}" > "${tmp_file}"
  mv -f "${tmp_file}" "${WARP_RULES_FILE}"
  chmod 0640 "${WARP_RULES_FILE}"
}

resolve_install_input_sources() {
  resolve_value_source CERT_SOURCE_PEM
  resolve_value_source KEY_SOURCE_PEM
  resolve_value_source WARP_TEAM_NAME
  resolve_value_source WARP_CLIENT_ID
  resolve_value_source WARP_CLIENT_SECRET
  resolve_value_source WARP_PROXY_PORT
  resolve_value_source CF_API_TOKEN
  resolve_value_source CF_DNS_TOKEN
}

preflight_check_port_443() {
  local listeners=""

  if ! command -v ss >/dev/null 2>&1; then
    warn "系统中未找到 ss，已跳过 443 端口占用预检。"
    return 0
  fi

  listeners="$(ss -ltnH '( sport = :443 )' 2>/dev/null || true)"
  [[ -z "${listeners}" ]] && return 0

  if [[ -f "${XRAY_CONFIG_FILE}" || -f "${HAPROXY_CONFIG}" ]]; then
    warn "检测到 443 端口已被当前机器上的现有服务占用，继续执行重装流程。"
    return 0
  fi

  die "预检失败：443 端口已被占用，请先释放端口或确认是否为当前脚本托管服务。"
}

preflight_check_domain_resolution() {
  local domain="${1}"
  local label="${2}"
  local resolved_ip=""

  [[ -n "${domain}" ]] || return 0
  resolved_ip="$(getent ahostsv4 "${domain}" 2>/dev/null | awk 'NR==1 {print $1}')"
  if [[ -z "${resolved_ip}" ]]; then
    warn "预检提示：${label} 当前无法解析，后续请确认 DNS 配置。"
    return 0
  fi

  if [[ -n "${SERVER_IP:-}" && "${resolved_ip}" == "${SERVER_IP}" ]]; then
    log_success "${label} 已解析到当前服务器地址：${resolved_ip}"
    return 0
  fi

  warn "预检提示：${label} 当前解析为 ${resolved_ip}，如果使用了 Cloudflare 橙云，这可能是正常现象。"
}

verify_cloudflare_token() {
  local token="${1}"
  local label="${2}"
  local response=""

  [[ -n "${token}" ]] || return 0
  response="$(curl -fsSL https://api.cloudflare.com/client/v4/user/tokens/verify \
    -H "Authorization: Bearer ${token}" \
    -H 'Content-Type: application/json' 2>/dev/null || true)"
  if [[ -z "${response}" ]]; then
    warn "预检提示：无法在线校验 ${label}，已跳过权限验证。"
    return 0
  fi

  printf '%s' "${response}" | grep -Eq '"success"[[:space:]]*:[[:space:]]*true' \
    || die "预检失败：${label} 校验未通过。"
  log_success "${label} 校验通过。"
}

run_install_preflight_checks() {
  log_step "执行安装前预检。"
  preflight_check_port_443
  preflight_check_domain_resolution "${XHTTP_DOMAIN}" "XHTTP CDN 域名"

  case "${CERT_MODE}" in
    cf-origin-ca)
      verify_cloudflare_token "${CF_API_TOKEN}" "Cloudflare API Token"
      ;;
    acme-dns-cf)
      verify_cloudflare_token "${CF_DNS_TOKEN}" "Cloudflare DNS Token"
      ;;
  esac
}

is_valid_hostname() {
  local host="${1:-}"
  local old_ifs=""
  local label=""

  [[ -n "${host}" ]] || return 1
  [[ "${#host}" -le 253 ]] || return 1
  [[ "${host}" != .* && "${host}" != *..* && "${host}" != *. ]] || return 1
  [[ "${host}" =~ ^[A-Za-z0-9.-]+$ ]] || return 1

  old_ifs="${IFS}"
  IFS='.'
  for label in ${host}; do
    [[ -n "${label}" ]] || return 1
    [[ "${#label}" -le 63 ]] || return 1
    [[ "${label}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
  done
  IFS="${old_ifs}"

  return 0
}

validate_hostname_value() {
  local field_name="${1}"
  local host="${2:-}"

  is_valid_hostname "${host}" || die "${field_name} 不是合法域名：${host}"
}

validate_port_value() {
  local field_name="${1}"
  local port="${2:-}"

  [[ "${port}" =~ ^[0-9]+$ ]] || die "${field_name} 必须是 1-65535 之间的端口：${port}"
  (( port >= 1 && port <= 65535 )) || die "${field_name} 必须是 1-65535 之间的端口：${port}"
}

validate_hostport_value() {
  local field_name="${1}"
  local hostport="${2:-}"
  local host=""
  local port=""

  [[ -n "${hostport}" ]] || die "${field_name} 不能为空。"
  [[ "${hostport}" == *:* ]] || die "${field_name} 必须是 host:port 格式：${hostport}"
  host="${hostport%:*}"
  port="${hostport##*:}"
  [[ -n "${host}" && -n "${port}" ]] || die "${field_name} 必须是 host:port 格式：${hostport}"

  if ! is_ipv4 "${host}"; then
    validate_hostname_value "${field_name}" "${host}"
  fi
  validate_port_value "${field_name}" "${port}"
}

ensure_reality_sni_format() {
  validate_hostname_value "REALITY SNI" "${REALITY_SNI}"
}

ensure_xhttp_domain_format() {
  validate_hostname_value "XHTTP CDN 域名" "${XHTTP_DOMAIN}"
}

ensure_reality_target_format() {
  validate_hostport_value "REALITY 目标地址" "${REALITY_TARGET}"
}

ensure_xhttp_path_format() {
  [[ -n "${XHTTP_PATH}" ]] || die "XHTTP 路径不能为空。"
  [[ "${XHTTP_PATH}" == /* ]] || die "XHTTP 路径必须以 / 开头。"
  [[ "${XHTTP_PATH}" != *$'\n'* && "${XHTTP_PATH}" != *$'\r'* ]] || die "XHTTP 路径不能包含换行。"
  [[ "${XHTTP_PATH}" != *'"'* ]] || die "XHTTP 路径不能包含双引号。"
  [[ "${XHTTP_PATH}" != *'\\'* ]] || die "XHTTP 路径不能包含反斜杠。"
  [[ "${XHTTP_PATH}" != *[[:space:]]* ]] || die "XHTTP 路径不能包含空白字符。"
}

ensure_warp_proxy_port_format() {
  validate_port_value "WARP 本地 SOCKS5 端口" "${WARP_PROXY_PORT}"
}

validate_install_inputs() {
  ensure_reality_sni_format
  ensure_reality_target_format
  ensure_xhttp_domain_format
  ensure_xhttp_path_format

  if [[ "${ENABLE_WARP:-no}" == "yes" ]]; then
    [[ -n "${WARP_TEAM_NAME}" ]] || die "启用 WARP 时必须提供团队名。"
    [[ -n "${WARP_CLIENT_ID}" ]] || die "启用 WARP 时必须提供 Client ID。"
    [[ -n "${WARP_CLIENT_SECRET}" ]] || die "启用 WARP 时必须提供 Client Secret。"
    ensure_warp_proxy_port_format
  fi
}

install_self_command() {
  local source_path="${SCRIPT_SELF:-$0}"
  local source_real=""
  local source_root=""
  local staging_dir=""
  local source_bundle_root=""

  if [[ ! -f "${source_path}" ]]; then
    warn "无法写入持久化管理命令，因为当前脚本路径不可用。"
    return
  fi

  source_real="$(readlink -f "${source_path}" 2>/dev/null || printf '%s' "${source_path}")"
  source_root="$(cd "$(dirname "${source_real}")" && pwd)"
  [[ -d "${source_root}/lib" ]] || die "当前脚本目录缺少 lib/，无法安装持久化管理命令。"
  source_bundle_root="${source_root}"

  if [[ "${source_root}" == "${SELF_INSTALL_DIR}" ]]; then
    staging_dir="$(mktemp -d)"
    install -m 0755 "${source_root}/xray-warp-team.sh" "${staging_dir}/xray-warp-team.sh"
    cp -a "${source_root}/lib" "${staging_dir}/lib"
    source_bundle_root="${staging_dir}"
  fi

  install_bundle_root_to_self "${source_bundle_root}"
  if [[ -n "${staging_dir}" ]]; then
    rm -rf "${staging_dir}"
  fi
  return 0
}

bundle_script_version() {
  local bundle_root="${1}"

  sed -n 's/^SCRIPT_VERSION="\([^"]*\)".*/\1/p' "${bundle_root}/xray-warp-team.sh" 2>/dev/null | head -n 1
}

install_bundle_root_to_self() {
  local source_bundle_root="${1}"
  local target_entry="${SELF_INSTALL_DIR}/xray-warp-team.sh"
  local wrapper_tmp=""
  [[ -d "${source_bundle_root}/lib" && -f "${source_bundle_root}/xray-warp-team.sh" ]] || die "脚本 bundle 缺少必需文件，无法安装。"

  backup_path "${SELF_INSTALL_DIR}"
  backup_path "${SELF_COMMAND_PATH}"

  rm -rf "${SELF_INSTALL_DIR}"
  install -d -m 0755 "${SELF_INSTALL_DIR}"
  install -d -m 0755 "$(dirname "${SELF_COMMAND_PATH}")"
  install -m 0755 "${source_bundle_root}/xray-warp-team.sh" "${target_entry}"
  cp -a "${source_bundle_root}/lib" "${SELF_INSTALL_DIR}/lib"

  wrapper_tmp="$(mktemp)"
  cat > "${wrapper_tmp}" <<EOF
#!/usr/bin/env bash
export XRAY_WARP_TEAM_COMMAND_NAME="\$(basename "\$0")"
exec "${target_entry}" "\$@"
EOF
  install -m 0755 "${wrapper_tmp}" "${SELF_COMMAND_PATH}"
  rm -f "${wrapper_tmp}"
}

download_latest_script_bundle() {
  local target_dir="${1}"
  local archive_url=""
  local archive_path="${target_dir}/xray-warp-team.tar.gz"
  local bundle_root=""

  archive_url="$(bootstrap_resolve_archive_url)"
  printf '[信息] %s\n' "下载来源：${archive_url}" >&2
  curl -fsSL "${archive_url}" -o "${archive_path}" || return 1
  tar -xzf "${archive_path}" -C "${target_dir}" || return 1
  bundle_root="$(find "${target_dir}" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  bundle_root_ready "${bundle_root}" || return 1
  printf '%s' "${bundle_root}"
}

update_script_cmd() {
  local previous_version=""
  local current_version=""
  local tmp_dir=""
  local bundle_root=""

  need_root
  start_backup_session
  previous_version="$(
    if [[ -f "${SELF_INSTALL_DIR}/xray-warp-team.sh" ]]; then
      bundle_script_version "${SELF_INSTALL_DIR}"
    else
      printf '%s' "${SCRIPT_VERSION}"
    fi
  )"

  tmp_dir="$(mktemp -d)"
  log_step "下载最新脚本 bundle。"
  if ! bundle_root="$(download_latest_script_bundle "${tmp_dir}")"; then
    rm -rf "${tmp_dir}"
    die "下载最新脚本 bundle 失败。"
  fi

  current_version="$(bundle_script_version "${bundle_root}")"
  log_step "安装脚本 bundle。"
  if ! install_bundle_root_to_self "${bundle_root}"; then
    warn "脚本 bundle 安装失败，正在回滚持久化脚本文件。"
    restore_backup_path "${SELF_INSTALL_DIR}" || true
    restore_backup_path "${SELF_COMMAND_PATH}" || true
    rm -rf "${tmp_dir}"
    return 1
  fi

  rm -rf "${tmp_dir}"
  log_success "脚本 bundle 已更新。"
  log "备份目录：${BACKUP_DIR}"
  [[ -n "${previous_version}" ]] && log "更新前版本：${previous_version}"
  [[ -n "${current_version}" ]] && log "当前版本：${current_version}"
  reload_updated_script_if_needed "${current_version}"
}

reload_updated_script_if_needed() {
  local current_version="${1:-}"

  [[ -n "${current_version}" ]] || return 0
  SCRIPT_VERSION="${current_version}"

  if [[ "${IN_MAIN_MENU:-0}" == "1" && -x "${SELF_COMMAND_PATH}" ]]; then
    log "已更新到 ${current_version}，正在重新载入脚本。"
    exec "${SELF_COMMAND_PATH}"
  fi

  log "已更新到 ${current_version}。当前进程仍使用旧代码路径时，请重新运行脚本以完整载入新版本。"
}

. "${SCRIPT_ROOT}/lib/install/certs.sh"
. "${SCRIPT_ROOT}/lib/install/network.sh"
. "${SCRIPT_ROOT}/lib/install/warp.sh"
