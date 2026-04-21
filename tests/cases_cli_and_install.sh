run_usage_case() {
  local workdir=""
  local output=""

  workdir="$(mktemp -d)"
  ln -s "${ROOT_DIR}/xray-warp-team.sh" "${workdir}/xray-warp-team"
  output="$("${workdir}/xray-warp-team" help)"

  [[ "${output}" == *$'\n  xray-warp-team help'* ]]
  [[ "${output}" == *$'\n  xray-warp-team install [参数]'* ]]
  [[ "${output}" == *$'\n  xray-warp-team renew-cert [参数]'* ]]
  [[ "${output}" == *$'\n  xray-warp-team change-warp-rules [参数]'* ]]
  [[ "${output}" == *$'\n  xray-warp-team diagnose'* ]]
}

run_install_self_command_case() {
  local workdir=""
  local output=""

  workdir="$(mktemp -d)"
  SELF_COMMAND_PATH="${workdir}/bin/xray-warp-team"
  SELF_INSTALL_DIR="${workdir}/bundle"
  SCRIPT_SELF="${ROOT_DIR}/xray-warp-team.sh"
  SCRIPT_ROOT="${ROOT_DIR}"

  install_self_command

  [[ -x "${SELF_COMMAND_PATH}" ]]
  [[ -f "${SELF_INSTALL_DIR}/xray-warp-team.sh" ]]
  [[ -f "${SELF_INSTALL_DIR}/lib/install.sh" ]]

  output="$("${SELF_COMMAND_PATH}" help)"
  [[ "${output}" == *$'\n  xray-warp-team help'* ]]
  [[ "${output}" == *$'\n  xray-warp-team install [参数]'* ]]
}

run_install_validation_case() {
  local output=""

  if output="$(bash <<EOF 2>&1
set -Eeuo pipefail
source <(sed '\$d' "${ROOT_DIR}/xray-warp-team.sh")
ENABLE_WARP="no"
REALITY_SNI='bad"host'
REALITY_TARGET='www.scu.edu:443'
XHTTP_DOMAIN='cdn.example.com'
XHTTP_PATH='/assets/v3'
validate_install_inputs
EOF
)"; then
    return 1
  fi
  printf '%s' "${output}" | grep -q 'REALITY SNI 不是合法域名'

  if output="$(bash <<EOF 2>&1
set -Eeuo pipefail
source <(sed '\$d' "${ROOT_DIR}/xray-warp-team.sh")
ENABLE_WARP="no"
REALITY_SNI='reality.example.com'
REALITY_TARGET='www.scu.edu:bad'
XHTTP_DOMAIN='cdn.example.com'
XHTTP_PATH='/assets/v3'
validate_install_inputs
EOF
)"; then
    return 1
  fi
  printf '%s' "${output}" | grep -q 'REALITY 目标地址 必须是 1-65535 之间的端口'

  if output="$(bash <<EOF 2>&1
set -Eeuo pipefail
source <(sed '\$d' "${ROOT_DIR}/xray-warp-team.sh")
ENABLE_WARP="no"
REALITY_SNI='reality.example.com'
REALITY_TARGET='www.scu.edu:443'
XHTTP_DOMAIN='cdn.example.com'
XHTTP_PATH='/bad path'
validate_install_inputs
EOF
)"; then
    return 1
  fi
  printf '%s' "${output}" | grep -q 'XHTTP 路径不能包含空白字符'
}

run_value_source_case() {
  local workdir=""

  workdir="$(mktemp -d)"
  printf 'secret-from-file\n' > "${workdir}/secret.txt"

  WARP_CLIENT_SECRET="@${workdir}/secret.txt"
  resolve_value_source WARP_CLIENT_SECRET
  [[ "${WARP_CLIENT_SECRET}" == "secret-from-file" ]]

  WARP_CLIENT_ID=""
  export WARP_CLIENT_ID="client-from-env"
  resolve_value_source WARP_CLIENT_ID
  [[ "${WARP_CLIENT_ID}" == "client-from-env" ]]
  unset WARP_CLIENT_ID
}

run_xray_digest_parse_case() {
  local workdir=""
  local dgst_file=""
  local hash_value=""

  workdir="$(mktemp -d)"
  dgst_file="${workdir}/Xray-linux-64.zip.dgst"
  cat > "${dgst_file}" <<'EOF'
SHA256 (Xray-linux-64.zip) = 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
SHA512 (Xray-linux-64.zip) = deadbeef
EOF

  hash_value="$(parse_xray_dgst_sha256 "${dgst_file}" "Xray-linux-64.zip")"
  [[ "${hash_value}" == "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" ]]
}

run_install_xray_checksum_failure_case() {
  local output=""

  if output="$(bash <<EOF 2>&1
set -Eeuo pipefail
source <(sed '\$d' "${ROOT_DIR}/xray-warp-team.sh")
detect_xray_arch() { printf '64'; }
curl() {
  case "\$*" in
    *Xray-linux-64.zip.dgst*)
      printf '%s\n' 'SHA256 (Xray-linux-64.zip) = 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' > "\${4}"
      ;;
    *Xray-linux-64.zip*)
      printf '%s' 'not-a-real-zip' > "\${4}"
      ;;
  esac
}
install_xray
EOF
)"; then
    return 1
  fi
  printf '%s' "${output}" | grep -q 'Xray-core 安装包 SHA256 校验失败'
}

run_install_parse_case() {
  NON_INTERACTIVE=0
  SERVER_IP=""
  NODE_LABEL_PREFIX=""
  REALITY_UUID=""
  REALITY_SNI=""
  REALITY_TARGET=""
  REALITY_SHORT_ID=""
  REALITY_PRIVATE_KEY=""
  XHTTP_UUID=""
  XHTTP_DOMAIN=""
  XHTTP_PATH=""
  XHTTP_VLESS_ENCRYPTION_ENABLED="yes"
  CERT_MODE=""
  CERT_SOURCE_FILE=""
  KEY_SOURCE_FILE=""
  ENABLE_WARP=""
  ENABLE_NET_OPT=""
  WARP_TEAM_NAME=""
  WARP_CLIENT_ID=""
  WARP_CLIENT_SECRET=""
  WARP_PROXY_PORT=""

  parse_install_args \
    --non-interactive \
    --server-ip 198.51.100.10 \
    --node-label-prefix hkg \
    --reality-sni reality.example.com \
    --reality-target reality.example.com:443 \
    --xhttp-domain cdn.example.com \
    --xhttp-path /edge \
    --disable-xhttp-vless-encryption \
    --cert-mode existing \
    --cert-file /tmp/cert.pem \
    --key-file /tmp/key.pem \
    --enable-warp \
    --warp-team team-name \
    --warp-client-id client-id \
    --warp-client-secret client-secret \
    --warp-proxy-port 41000 \
    --disable-net-opt

  [[ "${NON_INTERACTIVE}" -eq 1 ]]
  [[ "${SERVER_IP}" == "198.51.100.10" ]]
  [[ "${NODE_LABEL_PREFIX}" == "hkg" ]]
  [[ "${REALITY_SNI}" == "reality.example.com" ]]
  [[ "${REALITY_TARGET}" == "reality.example.com:443" ]]
  [[ "${XHTTP_DOMAIN}" == "cdn.example.com" ]]
  [[ "${XHTTP_PATH}" == "/edge" ]]
  [[ "${XHTTP_VLESS_ENCRYPTION_ENABLED}" == "no" ]]
  [[ "${CERT_MODE}" == "existing" ]]
  [[ "${CERT_SOURCE_FILE}" == "/tmp/cert.pem" ]]
  [[ "${KEY_SOURCE_FILE}" == "/tmp/key.pem" ]]
  [[ "${ENABLE_WARP}" == "yes" ]]
  [[ "${WARP_TEAM_NAME}" == "team-name" ]]
  [[ "${WARP_CLIENT_ID}" == "client-id" ]]
  [[ "${WARP_CLIENT_SECRET}" == "client-secret" ]]
  [[ "${WARP_PROXY_PORT}" == "41000" ]]
  [[ "${ENABLE_NET_OPT}" == "no" ]]
}

run_preflight_token_verify_case() {
  local output=""

  if ! output="$(bash <<EOF 2>&1
set -Eeuo pipefail
source <(sed '\$d' "${ROOT_DIR}/xray-warp-team.sh")
curl() {
  printf '%s' '{"success":true}'
}
jq() {
  return 99
}
verify_cloudflare_token "token-value" "Cloudflare API Token"
EOF
)"; then
    return 1
  fi
  printf '%s' "${output}" | grep -q 'Cloudflare API Token 校验通过'

  if output="$(bash <<EOF 2>&1
set -Eeuo pipefail
source <(sed '\$d' "${ROOT_DIR}/xray-warp-team.sh")
curl() {
  printf '%s' '{"success":false}'
}
verify_cloudflare_token "token-value" "Cloudflare API Token"
EOF
)"; then
    return 1
  fi
  printf '%s' "${output}" | grep -q 'Cloudflare API Token 校验未通过'
}

run_cert_mode_input_case() {
  NON_INTERACTIVE=1

  CERT_MODE="cf-origin-ca"
  CERT_SOURCE_FILE="/tmp/old-cert.pem"
  KEY_SOURCE_FILE="/tmp/old-key.pem"
  CERT_SOURCE_PEM="old-cert-pem"
  KEY_SOURCE_PEM="old-key-pem"
  CF_ZONE_ID="zone-id"
  CF_API_TOKEN="api-token"
  CF_CERT_VALIDITY="365"
  ACME_EMAIL="ops@example.com"
  ACME_CA="zerossl"
  CF_DNS_TOKEN="dns-token"
  CF_DNS_ACCOUNT_ID="account-id"
  CF_DNS_ZONE_ID="dns-zone-id"
  prompt_cert_mode_inputs
  [[ -z "${CERT_SOURCE_FILE}" ]]
  [[ -z "${KEY_SOURCE_FILE}" ]]
  [[ -z "${CERT_SOURCE_PEM}" ]]
  [[ -z "${KEY_SOURCE_PEM}" ]]
  [[ "${CF_ZONE_ID}" == "zone-id" ]]
  [[ "${CF_API_TOKEN}" == "api-token" ]]
  [[ "${CF_CERT_VALIDITY}" == "365" ]]
  [[ -z "${ACME_EMAIL}" ]]
  [[ "${ACME_CA}" == "letsencrypt" ]]
  [[ -z "${CF_DNS_TOKEN}" ]]
  [[ -z "${CF_DNS_ACCOUNT_ID}" ]]
  [[ -z "${CF_DNS_ZONE_ID}" ]]

  CERT_MODE="acme-dns-cf"
  CERT_SOURCE_FILE="/tmp/old-cert.pem"
  KEY_SOURCE_FILE="/tmp/old-key.pem"
  CERT_SOURCE_PEM="old-cert-pem"
  KEY_SOURCE_PEM="old-key-pem"
  CF_ZONE_ID="zone-id"
  CF_API_TOKEN="api-token"
  CF_CERT_VALIDITY="365"
  ACME_EMAIL="ops@example.com"
  ACME_CA="zerossl"
  CF_DNS_TOKEN="dns-token"
  CF_DNS_ACCOUNT_ID="account-id"
  CF_DNS_ZONE_ID="dns-zone-id"
  prompt_cert_mode_inputs
  [[ -z "${CERT_SOURCE_FILE}" ]]
  [[ -z "${KEY_SOURCE_FILE}" ]]
  [[ -z "${CERT_SOURCE_PEM}" ]]
  [[ -z "${KEY_SOURCE_PEM}" ]]
  [[ -z "${CF_ZONE_ID}" ]]
  [[ -z "${CF_API_TOKEN}" ]]
  [[ "${CF_CERT_VALIDITY}" == "5475" ]]
  [[ "${ACME_EMAIL}" == "ops@example.com" ]]
  [[ "${ACME_CA}" == "zerossl" ]]
  [[ "${CF_DNS_TOKEN}" == "dns-token" ]]
  [[ "${CF_DNS_ACCOUNT_ID}" == "account-id" ]]
  [[ "${CF_DNS_ZONE_ID}" == "dns-zone-id" ]]

  CERT_MODE="self-signed"
  CERT_SOURCE_FILE="/tmp/old-cert.pem"
  KEY_SOURCE_FILE="/tmp/old-key.pem"
  CERT_SOURCE_PEM="old-cert-pem"
  KEY_SOURCE_PEM="old-key-pem"
  CF_ZONE_ID="zone-id"
  CF_API_TOKEN="api-token"
  CF_CERT_VALIDITY="365"
  ACME_EMAIL="ops@example.com"
  ACME_CA="zerossl"
  CF_DNS_TOKEN="dns-token"
  CF_DNS_ACCOUNT_ID="account-id"
  CF_DNS_ZONE_ID="dns-zone-id"
  prompt_cert_mode_inputs
  [[ -z "${CERT_SOURCE_FILE}" ]]
  [[ -z "${KEY_SOURCE_FILE}" ]]
  [[ -z "${CERT_SOURCE_PEM}" ]]
  [[ -z "${KEY_SOURCE_PEM}" ]]
  [[ -z "${CF_ZONE_ID}" ]]
  [[ -z "${CF_API_TOKEN}" ]]
  [[ "${CF_CERT_VALIDITY}" == "5475" ]]
  [[ -z "${ACME_EMAIL}" ]]
  [[ "${ACME_CA}" == "letsencrypt" ]]
  [[ -z "${CF_DNS_TOKEN}" ]]
  [[ -z "${CF_DNS_ACCOUNT_ID}" ]]
  [[ -z "${CF_DNS_ZONE_ID}" ]]
}

run_missing_option_value_case() {
  local output=""

  if output="$(bash <<EOF 2>&1
set -Eeuo pipefail
source <(sed '\$d' "${ROOT_DIR}/xray-warp-team.sh")
parse_install_args --server-ip
EOF
)"; then
    return 1
  fi
  printf '%s' "${output}" | grep -q '参数 --server-ip 需要值。'

  if output="$(bash <<EOF 2>&1
set -Eeuo pipefail
source <(sed '\$d' "${ROOT_DIR}/xray-warp-team.sh")
change_uuid_cmd --reality-uuid
EOF
)"; then
    return 1
  fi
  printf '%s' "${output}" | grep -q '参数 --reality-uuid 需要值。'

  if output="$(bash <<EOF 2>&1
set -Eeuo pipefail
source <(sed '\$d' "${ROOT_DIR}/xray-warp-team.sh")
change_warp_cmd --bogus
EOF
)"; then
    return 1
  fi
  printf '%s' "${output}" | grep -q '未知的 change-warp 参数：--bogus'

  if output="$(bash <<EOF 2>&1
set -Eeuo pipefail
source <(sed '\$d' "${ROOT_DIR}/xray-warp-team.sh")
change_cert_mode_cmd --bogus
EOF
)"; then
    return 1
  fi
  printf '%s' "${output}" | grep -q '未知的 change-cert-mode 参数：--bogus'
}

run_dispatch_case() {
  local dispatched=""
  local dispatched_args=""

  install_cmd() {
    dispatched="install"
    dispatched_args="$*"
  }
  status_cmd() {
    dispatched="status"
    dispatched_args="$*"
  }
  diagnose_cmd() {
    dispatched="diagnose"
    dispatched_args="$*"
  }
  uninstall_cmd() {
    dispatched="uninstall"
    dispatched_args="$*"
  }
  change_warp_rules_cmd() {
    dispatched="change-warp-rules"
    dispatched_args="$*"
  }
  main_menu() {
    dispatched="menu"
    dispatched_args="$*"
  }
  renew_cert_cmd() {
    dispatched="renew-cert"
    dispatched_args="$*"
  }

  run_cli_command install --non-interactive --disable-warp
  [[ "${dispatched}" == "install" ]]
  [[ "${dispatched_args}" == "--non-interactive --disable-warp" ]]

  run_cli_command status --raw
  [[ "${dispatched}" == "status" ]]
  [[ "${dispatched_args}" == "--raw" ]]

  run_cli_command diagnose
  [[ "${dispatched}" == "diagnose" ]]

  run_cli_command
  [[ "${dispatched}" == "menu" ]]

  run_menu_choice 16
  [[ "${dispatched}" == "uninstall" ]]

  run_menu_choice 17
  [[ "${dispatched}" == "status" ]]
  [[ "${dispatched_args}" == "--raw" ]]

  run_menu_choice 14
  [[ "${dispatched}" == "renew-cert" ]]

  run_menu_choice 12
  [[ "${dispatched}" == "change-warp-rules" ]]

  run_menu_choice 3
  [[ "${dispatched}" == "diagnose" ]]
}

run_install_flow_case() {
  local steps=()
  local logged=""
  local shown=0

  load_functions
  stub_side_effects

  prepare_install_command() {
    steps+=("prepare:$*")
  }
  install_xray_runtime() {
    steps+=("runtime")
  }
  write_install_managed_files() {
    steps+=("files")
  }
  install_optional_components() {
    steps+=("optional")
  }
  finalize_installation() {
    steps+=("finalize")
  }
  log() {
    logged+="${1}"$'\n'
  }
  log_step() {
    logged+="STEP:${1}"$'\n'
  }
  show_links() {
    shown=1
  }

  install_cmd --non-interactive --disable-warp

  [[ "${steps[*]}" == "prepare:--non-interactive --disable-warp runtime files optional finalize" ]]
  [[ "${shown}" -eq 1 ]]
  printf '%s' "${logged}" | grep -q 'STEP:准备安装参数与运行环境。'
  printf '%s' "${logged}" | grep -q 'STEP:校验并启动托管服务。'
  printf '%s' "${logged}" | grep -q '部署完成。'
  printf '%s' "${logged}" | grep -q '管理命令：'
}
