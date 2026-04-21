#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

load_functions() {
  # ------------------------------
  # 只加载函数定义，不执行 main
  # 这样 smoke test 可以直接调用内部生成器
  # ------------------------------
  # shellcheck disable=SC1090
  source <(sed '$d' "${ROOT_DIR}/xray-warp-team.sh")
}

prepare_workspace() {
  local workdir="${1}"

  XRAY_CONFIG_DIR="${workdir}/xray"
  XRAY_CONFIG_FILE="${XRAY_CONFIG_DIR}/config.json"
  STATE_FILE="${XRAY_CONFIG_DIR}/node-meta.env"
  OUTPUT_FILE="${workdir}/output.md"
  mkdir -p "${XRAY_CONFIG_DIR}"
}

stub_side_effects() {
  ensure_managed_permissions() { :; }
  backup_path() { :; }
}

assert_contains() {
  local pattern="${1}"
  local path="${2}"

  grep -q -- "${pattern}" "${path}"
}

run_warp_enabled_case() {
  local workdir=""

  workdir="$(mktemp -d)"
  prepare_workspace "${workdir}"

  SERVER_IP="203.0.113.10"
  NODE_LABEL_PREFIX="HKG"
  REALITY_UUID="11111111-1111-1111-1111-111111111111"
  REALITY_SNI="reality.example.com"
  REALITY_TARGET="www.scu.edu:443"
  REALITY_SHORT_ID="abcd1234"
  REALITY_PRIVATE_KEY="private-key-value"
  REALITY_PUBLIC_KEY="public-key-value"
  XHTTP_UUID="22222222-2222-2222-2222-222222222222"
  XHTTP_DOMAIN="cdn.example.com"
  XHTTP_PATH="/assets/v3"
  XHTTP_VLESS_ENCRYPTION_ENABLED="yes"
  XHTTP_VLESS_ENCRYPTION="enc-value-+=?&"
  XHTTP_VLESS_DECRYPTION="enc-value-+=?&"
  TLS_ALPN="h2"
  FINGERPRINT="chrome"
  ENABLE_WARP="yes"
  ENABLE_NET_OPT="no"
  WARP_PROXY_PORT="40000"
  WARP_TEAM_NAME="team-name"
  WARP_CLIENT_ID="client-id.access"
  WARP_CLIENT_SECRET=$'sec\'ret $? []'
  CERT_MODE="existing"
  CF_ZONE_ID="zone-id"
  CF_CERT_VALIDITY="5475"
  ACME_EMAIL="ops@example.com"
  ACME_CA="letsencrypt"
  CF_DNS_ACCOUNT_ID="account-id"
  CF_DNS_ZONE_ID="dns-zone-id"
  XHTTP_ECH_CONFIG_LIST="https://1.1.1.1/dns-query"
  XHTTP_ECH_FORCE_QUERY="ipv4"

  write_xray_config
  write_state_file
  write_output_file

  jq -e '.routing.rules | length == 2' "${XRAY_CONFIG_FILE}" >/dev/null
  jq -e '.outbounds[] | select(.tag == "WARP") | .settings.servers[0].port == 40000' "${XRAY_CONFIG_FILE}" >/dev/null
  bash -n "${STATE_FILE}"

  # shellcheck disable=SC1090
  source "${STATE_FILE}"
  [[ "${WARP_CLIENT_SECRET}" == $'sec\'ret $? []' ]]

  assert_contains '&ech=' "${OUTPUT_FILE}"
  assert_contains 'extra=' "${OUTPUT_FILE}"
  assert_contains 'encryption=enc-value-%2B%3D%3F%26' "${OUTPUT_FILE}"
  assert_contains '已启用: 是' "${OUTPUT_FILE}"
}

run_warp_disabled_case() {
  local workdir=""

  workdir="$(mktemp -d)"
  prepare_workspace "${workdir}"

  SERVER_IP="203.0.113.11"
  NODE_LABEL_PREFIX="SFO"
  REALITY_UUID="33333333-3333-3333-3333-333333333333"
  REALITY_SNI="reality2.example.com"
  REALITY_TARGET="www.stanford.edu:443"
  REALITY_SHORT_ID="efgh5678"
  REALITY_PRIVATE_KEY="private-key-2"
  REALITY_PUBLIC_KEY="public-key-2"
  XHTTP_UUID="44444444-4444-4444-4444-444444444444"
  XHTTP_DOMAIN="cdn2.example.com"
  XHTTP_PATH="/x"
  XHTTP_VLESS_ENCRYPTION_ENABLED="no"
  XHTTP_VLESS_ENCRYPTION=""
  XHTTP_VLESS_DECRYPTION="none"
  TLS_ALPN="h2"
  FINGERPRINT="chrome"
  ENABLE_WARP="no"
  ENABLE_NET_OPT="no"
  WARP_PROXY_PORT="40000"
  CERT_MODE="self-signed"
  XHTTP_ECH_CONFIG_LIST=""
  XHTTP_ECH_FORCE_QUERY=""

  write_xray_config
  write_output_file

  jq -e '.routing.rules | length == 0' "${XRAY_CONFIG_FILE}" >/dev/null
  jq -e '.outbounds | length == 2' "${XRAY_CONFIG_FILE}" >/dev/null

  if grep -q '&ech=' "${OUTPUT_FILE}"; then
    return 1
  fi

  assert_contains 'Cloudflare SSL/TLS 模式设置为 Full。' "${OUTPUT_FILE}"
  assert_contains 'encryption=none' "${OUTPUT_FILE}"
}

run_output_helper_case() {
  SERVER_IP="203.0.113.12"
  NODE_LABEL_PREFIX="hkg"
  REALITY_UUID="55555555-5555-5555-5555-555555555555"
  REALITY_SNI="reality3.example.com"
  REALITY_PUBLIC_KEY="public-key-3"
  REALITY_SHORT_ID="ijkl9012"
  FINGERPRINT="chrome"

  [[ "$(prefixed_node_label "REALITY")" == "HKG-REALITY" ]]

  CERT_MODE="self-signed"
  [[ "$(cloudflare_ssl_mode_text)" == "Full" ]]

  CERT_MODE="existing"
  [[ "$(cloudflare_ssl_mode_text)" == "Full (strict)" ]]

  [[ "$(build_reality_uri "HKG-REALITY")" == *"vless://${REALITY_UUID}@${SERVER_IP}:443"* ]]
  [[ "$(build_reality_uri "HKG-REALITY")" == *"#HKG-REALITY" ]]
  [[ "$(xray_sniffing_json)" == *'"routeOnly": true'* ]]
}

run_usage_case() {
  local workdir=""
  local output=""

  workdir="$(mktemp -d)"
  ln -s "${ROOT_DIR}/xray-warp-team.sh" "${workdir}/xray-warp-team"
  output="$("${workdir}/xray-warp-team" help)"

  [[ "${output}" == *$'\n  xray-warp-team help'* ]]
  [[ "${output}" == *$'\n  xray-warp-team install [参数]'* ]]
}

run_service_config_helper_case() {
  local workdir=""

  workdir="$(mktemp -d)"
  NGINX_CONF_DIR="${workdir}/nginx"
  NGINX_CONFIG_FILE="${NGINX_CONF_DIR}/xray-warp-team.conf"
  HAPROXY_CONFIG="${workdir}/haproxy.cfg"
  XHTTP_DOMAIN="cdn.example.com"
  XHTTP_PATH="/assets/v3"
  XHTTP_LOCAL_PORT="8001"
  NGINX_TLS_PORT="8443"
  TLS_CERT_FILE="/etc/ssl/xray-warp-team/cert.pem"
  TLS_KEY_FILE="/etc/ssl/xray-warp-team/key.pem"

  write_nginx_config
  write_haproxy_config

  assert_contains 'server_name cdn.example.com;' "${NGINX_CONFIG_FILE}"
  assert_contains 'proxy_pass https://www.harvard.edu;' "${NGINX_CONFIG_FILE}"
  assert_contains 'grpc_pass 127.0.0.1:8001;' "${NGINX_CONFIG_FILE}"
  assert_contains 'use_backend be_xhttp_cdn if { req.ssl_sni -i cdn.example.com }' "${HAPROXY_CONFIG}"
  assert_contains 'server nginx_cdn 127.0.0.1:8443 check' "${HAPROXY_CONFIG}"
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

run_change_helper_case() {
  local original_prompt=""
  local -A warp_request=()
  local -A cert_request=()

  original_prompt="$(declare -f prompt_with_default)"
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
  local runtime_updated=0
  local runtime_sni=""
  local runtime_target=""
  local state_written=0
  local output_written=0
  local written_prefix=""
  local shown_links=0

  need_root() { :; }
  start_backup_session() { BACKUP_DIR="/tmp/change-backup"; }
  load_current_install_context() {
    REALITY_SNI="old.example.com"
    REALITY_TARGET="old.example.com:443"
    XHTTP_PATH="/old"
    NODE_LABEL_PREFIX="HKG"
    CERT_MODE="existing"
    XHTTP_DOMAIN="cdn.old.example.com"
    ENABLE_WARP="no"
    WARP_TEAM_NAME="old-team"
    WARP_CLIENT_ID="old-id"
    WARP_CLIENT_SECRET="old-secret"
    WARP_PROXY_PORT="40000"
  }
  apply_managed_runtime_update() {
    runtime_updated=1
    runtime_sni="${REALITY_SNI}"
    runtime_target="${REALITY_TARGET}"
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

  NON_INTERACTIVE=0
  change_sni_cmd --non-interactive --reality-sni new.example.com
  [[ "${runtime_updated}" -eq 1 ]]
  [[ "${runtime_sni}" == "new.example.com" ]]
  [[ "${runtime_target}" == "new.example.com:443" ]]
  [[ "${shown_links}" -eq 1 ]]

  NON_INTERACTIVE=0
  change_label_prefix_cmd --non-interactive
  [[ "${state_written}" -eq 1 ]]
  [[ "${output_written}" -eq 1 ]]
  [[ "${written_prefix}" == "HKG" ]]
  [[ "${shown_links}" -eq 2 ]]
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
  main_menu() {
    dispatched="menu"
    dispatched_args="$*"
  }

  run_cli_command install --non-interactive --disable-warp
  [[ "${dispatched}" == "install" ]]
  [[ "${dispatched_args}" == "--non-interactive --disable-warp" ]]

  run_cli_command status --raw
  [[ "${dispatched}" == "status" ]]
  [[ "${dispatched_args}" == "--raw" ]]

  run_cli_command
  [[ "${dispatched}" == "menu" ]]

  run_menu_choice 14
  [[ "${dispatched}" == "status" ]]
  [[ "${dispatched_args}" == "--raw" ]]
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
  show_links() {
    shown=1
  }

  install_cmd --non-interactive --disable-warp

  [[ "${steps[*]}" == "prepare:--non-interactive --disable-warp runtime files optional finalize" ]]
  [[ "${shown}" -eq 1 ]]
  printf '%s' "${logged}" | grep -q '部署完成。'
  printf '%s' "${logged}" | grep -q '管理命令：'
}

main() {
  load_functions
  stub_side_effects
  run_warp_enabled_case
  run_warp_disabled_case
  run_output_helper_case
  run_usage_case
  run_service_config_helper_case
  run_managed_apply_case
  run_change_helper_case
  run_install_parse_case
  run_cert_mode_input_case
  run_change_command_case
  run_missing_option_value_case
  run_dispatch_case
  run_install_flow_case
  printf 'smoke ok\n'
}

main "$@"
