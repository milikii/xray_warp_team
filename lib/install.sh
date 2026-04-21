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

xray_archive_name() {
  local arch="${1}"
  printf 'Xray-linux-%s.zip' "${arch}"
}

xray_digest_name() {
  local archive_name="${1}"
  printf '%s.dgst' "${archive_name}"
}

parse_xray_dgst_sha256() {
  local dgst_file="${1}"
  local asset_name="${2}"
  local value=""

  value="$(awk -v asset="${asset_name}" '
    {
      line=$0
      lower=line
      gsub(/[A-Z]/, "", lower)
    }
    index(tolower($0), "sha256") && index($0, asset) {
      if (match($0, /[0-9a-fA-F]{64}/)) {
        print substr($0, RSTART, RLENGTH)
        exit
      }
    }
    index($0, asset) {
      if (match($0, /[0-9a-fA-F]{64}/)) {
        print substr($0, RSTART, RLENGTH)
        exit
      }
    }
    /^[0-9a-fA-F]{64}([[:space:]]|$)/ {
      print substr($1, 1, 64)
      exit
    }
    /^sha256:[0-9a-fA-F]{64}$/ {
      sub(/^sha256:/, "", $0)
      print
      exit
    }
  ' "${dgst_file}")"

  printf '%s' "${value,,}"
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
  local archive_path=""
  local digest_path=""
  local expected_sha256=""

  arch="$(detect_xray_arch)"
  archive_name="$(xray_archive_name "${arch}")"
  digest_name="$(xray_digest_name "${archive_name}")"
  base_url="$(xray_release_base_url)"
  tmp_dir="$(mktemp -d)"
  archive_path="${tmp_dir}/${archive_name}"
  digest_path="${tmp_dir}/${digest_name}"

  log_step "下载 Xray-core 最新版本。"
  log "资源文件：${archive_name}"
  log "校验文件：${digest_name}"
  curl -fsSL "${base_url}/${archive_name}" -o "${archive_path}"
  curl -fsSL "${base_url}/${digest_name}" -o "${digest_path}"
  expected_sha256="$(parse_xray_dgst_sha256 "${digest_path}" "${archive_name}")"
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
  local target_entry="${SELF_INSTALL_DIR}/xray-warp-team.sh"

  if [[ ! -f "${source_path}" ]]; then
    warn "无法写入持久化管理命令，因为当前脚本路径不可用。"
    return
  fi

  source_real="$(readlink -f "${source_path}" 2>/dev/null || printf '%s' "${source_path}")"
  source_root="$(cd "$(dirname "${source_real}")" && pwd)"
  [[ -d "${source_root}/lib" ]] || die "当前脚本目录缺少 lib/，无法安装持久化管理命令。"

  backup_path "${SELF_INSTALL_DIR}"
  backup_path "${SELF_COMMAND_PATH}"

  rm -rf "${SELF_INSTALL_DIR}"
  install -d -m 0755 "${SELF_INSTALL_DIR}"
  install -d -m 0755 "$(dirname "${SELF_COMMAND_PATH}")"
  install -m 0755 "${source_root}/xray-warp-team.sh" "${target_entry}"
  cp -a "${source_root}/lib" "${SELF_INSTALL_DIR}/lib"

  cat > "${SELF_COMMAND_PATH}" <<EOF
#!/usr/bin/env bash
export XRAY_WARP_TEAM_COMMAND_NAME="\$(basename "\$0")"
exec "${target_entry}" "\$@"
EOF
  chmod 0755 "${SELF_COMMAND_PATH}"
}

. "${SCRIPT_ROOT}/lib/install/certs.sh"
. "${SCRIPT_ROOT}/lib/install/network.sh"
. "${SCRIPT_ROOT}/lib/install/warp.sh"
