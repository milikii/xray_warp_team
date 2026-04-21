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
  jq -e '.routeOnly == true' <<<"$(xray_sniffing_json)" >/dev/null
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

run_xray_config_escape_case() {
  local workdir=""

  workdir="$(mktemp -d)"
  prepare_workspace "${workdir}"

  SERVER_IP="203.0.113.13"
  REALITY_UUID="66666666-6666-6666-6666-666666666666"
  REALITY_SNI="reality4.example.com"
  REALITY_TARGET='mirror"host.example.com:443'
  REALITY_SHORT_ID="mnop3456"
  REALITY_PRIVATE_KEY='private"key'
  XHTTP_UUID="77777777-7777-7777-7777-777777777777"
  XHTTP_PATH='/assets/"quoted"'
  XHTTP_VLESS_ENCRYPTION_ENABLED="yes"
  XHTTP_VLESS_DECRYPTION='enc"value'
  XHTTP_VLESS_ENCRYPTION='enc"value'
  ENABLE_WARP="no"
  WARP_PROXY_PORT="40000"

  write_xray_config

  jq -e '.inbounds[] | select(.tag == "reality-vision") | .streamSettings.realitySettings.target == "mirror\"host.example.com:443"' "${XRAY_CONFIG_FILE}" >/dev/null
  jq -e '.inbounds[] | select(.tag == "reality-vision") | .streamSettings.realitySettings.privateKey == "private\"key"' "${XRAY_CONFIG_FILE}" >/dev/null
  jq -e '.inbounds[] | select(.tag == "xhttp-cdn") | .streamSettings.xhttpSettings.path == "/assets/\"quoted\""' "${XRAY_CONFIG_FILE}" >/dev/null
  jq -e '.inbounds[] | select(.tag == "xhttp-cdn") | .settings.decryption == "enc\"value"' "${XRAY_CONFIG_FILE}" >/dev/null
}

run_generated_file_atomic_failure_case() {
  local workdir=""
  local status=0

  workdir="$(mktemp -d)"
  prepare_workspace "${workdir}"
  NGINX_CONF_DIR="${workdir}/nginx"
  NGINX_CONFIG_FILE="${NGINX_CONF_DIR}/xray-warp-team.conf"
  HAPROXY_CONFIG="${workdir}/haproxy.cfg"
  mkdir -p "${NGINX_CONF_DIR}"

  printf 'old-xray\n' > "${XRAY_CONFIG_FILE}"
  printf 'old-nginx\n' > "${NGINX_CONFIG_FILE}"
  printf 'old-haproxy\n' > "${HAPROXY_CONFIG}"

  fail_producer() {
    return 1
  }

  set +e
  write_generated_file_atomically "${XRAY_CONFIG_FILE}" fail_producer >/dev/null 2>&1
  status=$?
  set -e
  [[ "${status}" -ne 0 ]]
  [[ "$(cat "${XRAY_CONFIG_FILE}")" == "old-xray" ]]

  set +e
  write_generated_file_atomically "${NGINX_CONFIG_FILE}" fail_producer >/dev/null 2>&1
  status=$?
  set -e
  [[ "${status}" -ne 0 ]]
  [[ "$(cat "${NGINX_CONFIG_FILE}")" == "old-nginx" ]]

  set +e
  write_generated_file_atomically "${HAPROXY_CONFIG}" fail_producer >/dev/null 2>&1
  status=$?
  set -e
  [[ "${status}" -ne 0 ]]
  [[ "$(cat "${HAPROXY_CONFIG}")" == "old-haproxy" ]]

  if find "${workdir}" -name '.*.tmp.*' | grep -q .; then
    return 1
  fi
}
