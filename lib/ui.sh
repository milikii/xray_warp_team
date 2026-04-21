# shellcheck shell=bash

# ------------------------------
# 展示与输出层
# 负责状态面板与节点输出文本
# ------------------------------

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
