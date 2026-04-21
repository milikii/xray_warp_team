# shellcheck shell=bash

# ------------------------------
# 输入与交互层
# 负责交互式输入、多行输入与帮助文本
# ------------------------------

usage() {
  local command_name=""

  command_name="${XRAY_WARP_TEAM_COMMAND_NAME:-$(basename "${0}")}"
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
