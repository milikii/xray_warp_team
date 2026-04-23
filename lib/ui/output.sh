# shellcheck shell=bash

# ------------------------------
# 节点输出层
# 负责链接导出、客户端片段与输出文件落盘
# ------------------------------

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

  printf 'vless://%s@%s:443?mode=auto&path=%s&security=tls&alpn=%s&encryption=%s&insecure=0&host=%s&fp=%s&fingerprint=%s&type=xhttp&allowInsecure=0&sni=%s%s%s#%s' \
    "${XHTTP_UUID}" \
    "${XHTTP_DOMAIN}" \
    "${path_component}" \
    "${TLS_ALPN}" \
    "${encryption_value}" \
    "${XHTTP_DOMAIN}" \
    "${FINGERPRINT}" \
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

cloudflare_xhttp_cache_bypass_expression() {
  printf '(http.host eq "%s") or (http.request.uri.path contains "%s")' \
    "${XHTTP_DOMAIN}" \
    "${XHTTP_PATH}"
}

build_reality_uri() {
  local label="${1}"

  printf 'vless://%s@%s:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=%s&fp=%s&fingerprint=%s&pbk=%s&sid=%s&type=tcp&headerType=none#%s' \
    "${REALITY_UUID}" \
    "${SERVER_IP}" \
    "${REALITY_SNI}" \
    "${FINGERPRINT}" \
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

## Cloudflare Cache Rules（建议）
- 建议为 XHTTP 请求配置 Cache Rules -> Cache eligibility: Bypass cache，避免请求被 Cloudflare 边缘缓存。
- 可直接使用下面这条表达式：
  $(cloudflare_xhttp_cache_bypass_expression)
- 如果 ${XHTTP_DOMAIN} 是专门给 XHTTP 使用的独立子域名，直接按整个 Host 绕过缓存通常也没有问题。

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

clash_reality_proxy_yaml() {
  local label="${1}"

  cat <<EOF
- name: ${label}
  type: vless
  server: ${SERVER_IP}
  port: 443
  uuid: ${REALITY_UUID}
  network: tcp
  udp: true
  tls: true
  servername: ${REALITY_SNI}
  flow: xtls-rprx-vision
  client-fingerprint: ${FINGERPRINT}
  reality-opts:
    public-key: ${REALITY_PUBLIC_KEY}
    short-id: ${REALITY_SHORT_ID}
EOF
}

clash_xhttp_proxy_yaml() {
  local label="${1}"

  cat <<EOF
- name: ${label}
  type: vless
  server: ${XHTTP_DOMAIN}
  port: 443
  uuid: ${XHTTP_UUID}
  network: xhttp
  udp: true
  tls: true
  servername: ${XHTTP_DOMAIN}
  client-fingerprint: ${FINGERPRINT}
  alpn:
    - ${TLS_ALPN}
  xhttp-opts:
    path: ${XHTTP_PATH}
    mode: auto
EOF
}

singbox_reality_outbound_json() {
  local label="${1}"

  jq -cn \
    --arg tag "${label}" \
    --arg server "${SERVER_IP}" \
    --arg uuid "${REALITY_UUID}" \
    --arg server_name "${REALITY_SNI}" \
    --arg public_key "${REALITY_PUBLIC_KEY}" \
    --arg short_id "${REALITY_SHORT_ID}" \
    --arg fingerprint "${FINGERPRINT}" \
    '{
      type: "vless",
      tag: $tag,
      server: $server,
      server_port: 443,
      uuid: $uuid,
      flow: "xtls-rprx-vision",
      tls: {
        enabled: true,
        server_name: $server_name,
        reality: {
          enabled: true,
          public_key: $public_key,
          short_id: $short_id
        },
        utls: {
          enabled: true,
          fingerprint: $fingerprint
        }
      }
    }'
}

singbox_xhttp_outbound_json() {
  local label="${1}"

  jq -cn \
    --arg tag "${label}" \
    --arg server "${XHTTP_DOMAIN}" \
    --arg uuid "${XHTTP_UUID}" \
    --arg server_name "${XHTTP_DOMAIN}" \
    --arg alpn "${TLS_ALPN}" \
    --arg path "${XHTTP_PATH}" \
    --arg fingerprint "${FINGERPRINT}" \
    '{
      type: "vless",
      tag: $tag,
      server: $server,
      server_port: 443,
      uuid: $uuid,
      tls: {
        enabled: true,
        server_name: $server_name,
        alpn: [$alpn],
        utls: {
          enabled: true,
          fingerprint: $fingerprint
        }
      },
      transport: {
        type: "xhttp",
        path: $path
      }
    }'
}

output_client_snippets_block() {
  local reality_label="${1}"
  local xhttp_label="${2}"
  local split_label="${3}"

  cat <<EOF
## Clash Meta / Mihomo 片段

~~~yaml
proxies:
$(clash_reality_proxy_yaml "${reality_label}")
$(clash_xhttp_proxy_yaml "${xhttp_label}")
~~~

说明：
- 上面直接给出 REALITY 和 XHTTP-CDN 两个结构化片段
- XHTTP-SPLIT 的不同客户端支持差异较大，建议继续直接导入上面的分享链接：${split_label}

## sing-box outbound 片段

~~~json
[
  $(singbox_reality_outbound_json "${reality_label}"),
  $(singbox_xhttp_outbound_json "${xhttp_label}")
]
~~~

说明：
- 上面直接给出 REALITY 和 XHTTP-CDN 两个 outbound 片段
- XHTTP-SPLIT 仍建议优先使用分享链接导入，避免不同客户端对分离下载链路字段的兼容差异
EOF
}

output_file_text() {
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

  cat <<EOF
# Xray WARP Team 部署信息

$(output_reality_block "${reality_uri}")

$(output_xhttp_cdn_block "${xhttp_uri}")

$(output_xhttp_split_block "${xhttp_split_uri}")

$(output_runtime_summary_block "${cf_ssl_mode}")

$(output_client_snippets_block "${reality_label}" "${xhttp_label}" "${xhttp_split_label}")
EOF
}

write_output_file() {
  write_generated_file_atomically "${OUTPUT_FILE}" output_file_text
  chmod 0644 "${OUTPUT_FILE}"
}
