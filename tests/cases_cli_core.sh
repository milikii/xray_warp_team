run_usage_case() {
  local workdir=""
  local output=""

  workdir="$(mktemp -d)"
  ln -s "${ROOT_DIR}/xray-warp-team.sh" "${workdir}/xray-warp-team"
  output="$("${workdir}/xray-warp-team" help)"

  [[ "${output}" == *$'\n  xray-warp-team help'* ]]
  [[ "${output}" == *$'\n  xray-warp-team install [参数]'* ]]
  [[ "${output}" == *$'\n  xray-warp-team update-script'* ]]
  [[ "${output}" == *$'\n  xray-warp-team renew-cert [参数]'* ]]
  [[ "${output}" == *$'\n  xray-warp-team change-warp-rules [参数]'* ]]
  [[ "${output}" == *$'\n  xray-warp-team diagnose'* ]]
}

run_show_links_without_state_case() {
  local workdir=""
  local output=""

  workdir="$(mktemp -d)"
  OUTPUT_FILE="${workdir}/output.md"
  STATE_FILE="${workdir}/missing-state.env"
  cat > "${OUTPUT_FILE}" <<'EOF'
vless://example-link
EOF

  output="$(show_links)"
  [[ "${output}" == "vless://example-link" ]]
}

run_single_file_bootstrap_case() {
  local workdir=""
  local output=""
  local old_bundle=""

  workdir="$(mktemp -d)"
  cp "${ROOT_DIR}/xray-warp-team.sh" "${workdir}/xray-warp-team.sh"
  old_bundle="${workdir}/old-bundle"
  mkdir -p "${old_bundle}/lib/base"
  cp "${ROOT_DIR}/xray-warp-team.sh" "${old_bundle}/xray-warp-team.sh"
  printf '# helper\n' > "${old_bundle}/lib/base/helpers.sh"

  output="$(XRAY_WARP_TEAM_SELF_INSTALL_DIR="${old_bundle}" XRAY_WARP_TEAM_SELF_COMMAND_PATH="${workdir}/bin/xray-warp-team" XRAY_WARP_TEAM_BOOTSTRAP_ROOT="${ROOT_DIR}" bash "${workdir}/xray-warp-team.sh" help)"
  [[ "${output}" == *$'\n  xray-warp-team.sh help'* ]]
  [[ "${output}" == *$'\n  xray-warp-team.sh diagnose'* ]]
}

run_bootstrap_archive_resolve_case() {
  local archive_url=""
  local original_bootstrap_archive_url="${BOOTSTRAP_ARCHIVE_URL:-}"
  local original_repo_owner="${BOOTSTRAP_REPO_OWNER:-}"
  local original_repo_name="${BOOTSTRAP_REPO_NAME:-}"
  local original_branch_ref="${BOOTSTRAP_BRANCH_REF:-}"

  BOOTSTRAP_ARCHIVE_URL=""
  BOOTSTRAP_REPO_OWNER="milikii"
  BOOTSTRAP_REPO_NAME="xray_warp_team"
  BOOTSTRAP_BRANCH_REF="main"

  curl() {
    printf '%s' '{"sha":"0123456789abcdef0123456789abcdef01234567"}'
  }
  archive_url="$(bootstrap_resolve_archive_url)"
  [[ "${archive_url}" == "https://codeload.github.com/milikii/xray_warp_team/tar.gz/0123456789abcdef0123456789abcdef01234567" ]]

  curl() {
    return 99
  }
  archive_url="$(bootstrap_resolve_archive_url)"
  [[ "${archive_url}" == "https://codeload.github.com/milikii/xray_warp_team/tar.gz/main" ]]

  BOOTSTRAP_ARCHIVE_URL="https://example.invalid/custom.tar.gz"
  archive_url="$(bootstrap_resolve_archive_url)"
  [[ "${archive_url}" == "https://example.invalid/custom.tar.gz" ]]

  BOOTSTRAP_ARCHIVE_URL="${original_bootstrap_archive_url}"
  BOOTSTRAP_REPO_OWNER="${original_repo_owner}"
  BOOTSTRAP_REPO_NAME="${original_repo_name}"
  BOOTSTRAP_BRANCH_REF="${original_branch_ref}"
  unset -f curl
}

run_install_self_command_case() {
  local workdir=""
  local output=""
  local source_bundle=""

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

  source_bundle="${workdir}/source-bundle"
  cp -a "${SELF_INSTALL_DIR}" "${source_bundle}"
  SELF_INSTALL_DIR="${source_bundle}"
  SELF_COMMAND_PATH="${workdir}/bin/xray-warp-team-reinstall"
  SCRIPT_SELF="${source_bundle}/xray-warp-team.sh"
  SCRIPT_ROOT="${source_bundle}"

  install_self_command
  [[ -x "${SELF_COMMAND_PATH}" ]]
  [[ -f "${SELF_INSTALL_DIR}/xray-warp-team.sh" ]]
  [[ -f "${SELF_INSTALL_DIR}/lib/ui/output.sh" ]]
}

run_update_script_command_case() {
  local workdir=""
  local logged=""
  local stdout_output=""
  local installs=0
  local original_install_bundle_fn=""
  local original_log_step_fn=""
  local original_log_success_fn=""
  local original_log_fn=""

  workdir="$(mktemp -d)"
  SELF_INSTALL_DIR="${workdir}/bundle"
  SELF_COMMAND_PATH="${workdir}/bin/xray-warp-team"
  SCRIPT_VERSION="0.4.5"
  original_install_bundle_fn="$(capture_function_definition install_bundle_root_to_self)"
  original_log_step_fn="$(capture_function_definition log_step)"
  original_log_success_fn="$(capture_function_definition log_success)"
  original_log_fn="$(capture_function_definition log)"

  need_root() { :; }
  start_backup_session() { BACKUP_DIR="${workdir}/backup"; }
  bootstrap_resolve_archive_url() {
    printf '%s' "https://example.invalid/xray-warp-team.tar.gz"
  }
  curl() {
    local output_path=""

    while [[ $# -gt 0 ]]; do
      case "${1}" in
        -o)
          output_path="${2}"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done

    printf 'archive' > "${output_path}"
  }
  tar() {
    local target_dir=""

    while [[ $# -gt 0 ]]; do
      case "${1}" in
        -C)
          target_dir="${2}"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done

    mkdir -p "${target_dir}/bundle/lib/base"
    cat > "${target_dir}/bundle/xray-warp-team.sh" <<'EOF'
#!/usr/bin/env bash
SCRIPT_VERSION="9.9.9"
EOF
    printf '# helper\n' > "${target_dir}/bundle/lib/base/helpers.sh"
  }
  log_step() {
    logged+="STEP:${1}"$'\n'
  }
  log_success() {
    logged+="DONE:${1}"$'\n'
  }
  log() {
    logged+="${1}"$'\n'
  }
  backup_path() { :; }
  eval "${original_install_bundle_fn/install_bundle_root_to_self/real_install_bundle_root_to_self}"
  install_bundle_root_to_self() {
    installs=$((installs + 1))
    real_install_bundle_root_to_self "${1}"
  }
  reload_updated_script_if_needed() {
    SCRIPT_VERSION="${1}"
    logged+="RELOAD:${1}"$'\n'
  }

  update_script_cmd

  [[ -x "${SELF_COMMAND_PATH}" ]]
  [[ -f "${SELF_INSTALL_DIR}/xray-warp-team.sh" ]]
  grep -q 'SCRIPT_VERSION="9.9.9"' "${SELF_INSTALL_DIR}/xray-warp-team.sh"
  grep -q 'STEP:下载最新脚本 bundle。' <<< "${logged}"
  grep -q 'STEP:安装脚本 bundle。' <<< "${logged}"
  grep -q '当前版本：9.9.9' <<< "${logged}"
  grep -q 'RELOAD:9.9.9' <<< "${logged}"
  [[ "${SCRIPT_VERSION}" == "9.9.9" ]]
  [[ "${installs}" -eq 1 ]]

  restore_function_definition "${original_log_step_fn}"
  restore_function_definition "${original_log_success_fn}"
  restore_function_definition "${original_log_fn}"
  stdout_output="$(update_script_cmd 2>&1)"
  [[ -x "${SELF_COMMAND_PATH}" ]]
  [[ -f "${SELF_INSTALL_DIR}/xray-warp-team.sh" ]]
  grep -q '下载来源：' <<< "${stdout_output}"
  grep -q '当前已经是最新脚本 bundle。' <<< "${stdout_output}"

  tar() {
    local target_dir=""

    while [[ $# -gt 0 ]]; do
      case "${1}" in
        -C)
          target_dir="${2}"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done

    mkdir -p "${target_dir}/bundle/lib/base"
    cat > "${target_dir}/bundle/xray-warp-team.sh" <<'EOF'
#!/usr/bin/env bash
SCRIPT_VERSION="9.9.9"
echo changed
EOF
    printf '# helper\n' > "${target_dir}/bundle/lib/base/helpers.sh"
  }
  stdout_output="$(update_script_cmd 2>&1)"
  grep -q '脚本内容已更新，但版本号保持为 9.9.9。' <<< "${stdout_output}"
}

run_install_validation_case() {
  local output=""

  if output="$(bash <<EOF 2>&1
set -Eeuo pipefail
ROOT_DIR="${ROOT_DIR}"
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
ROOT_DIR="${ROOT_DIR}"
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
ROOT_DIR="${ROOT_DIR}"
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

run_prompt_reuse_case() {
  local output=""
  local script_file=""

  script_file="$(mktemp)"
  cat > "${script_file}" <<EOF
set -Eeuo pipefail
ROOT_DIR="${ROOT_DIR}"
source <(sed '\$d' "${ROOT_DIR}/xray-warp-team.sh")
NON_INTERACTIVE=0
SERVER_IP="203.0.113.10"
prompt_with_default SERVER_IP "REALITY 直连节点地址或 IP" "198.51.100.10"
printf '%s' "\${SERVER_IP}"
EOF
  output="$(printf '203.0.113.11\n' | bash "${script_file}")"
  rm -f "${script_file}"
  [[ "${output}" == "203.0.113.11" ]]

  script_file="$(mktemp)"
  cat > "${script_file}" <<EOF
set -Eeuo pipefail
ROOT_DIR="${ROOT_DIR}"
source <(sed '\$d' "${ROOT_DIR}/xray-warp-team.sh")
NON_INTERACTIVE=0
SERVER_IP="203.0.113.10"
prompt_with_default SERVER_IP "REALITY 直连节点地址或 IP" "198.51.100.10"
printf '%s' "\${SERVER_IP}"
EOF
  output="$(printf '\n' | bash "${script_file}")"
  rm -f "${script_file}"
  [[ "${output}" == "203.0.113.10" ]]

  script_file="$(mktemp)"
  cat > "${script_file}" <<EOF
set -Eeuo pipefail
ROOT_DIR="${ROOT_DIR}"
source <(sed '\$d' "${ROOT_DIR}/xray-warp-team.sh")
NON_INTERACTIVE=0
ENABLE_WARP="yes"
prompt_yes_no ENABLE_WARP "是否启用选择性 WARP 出站？ [y/n]" "y"
printf '%s' "\${ENABLE_WARP}"
EOF
  output="$(printf 'n\n' | bash "${script_file}")"
  rm -f "${script_file}"
  [[ "${output}" == "n" ]]

  script_file="$(mktemp)"
  cat > "${script_file}" <<EOF
set -Eeuo pipefail
ROOT_DIR="${ROOT_DIR}"
source <(sed '\$d' "${ROOT_DIR}/xray-warp-team.sh")
NON_INTERACTIVE=0
WARP_CLIENT_SECRET="secret-old"
prompt_secret WARP_CLIENT_SECRET "Cloudflare 服务令牌 Client Secret"
printf '%s' "\${WARP_CLIENT_SECRET}"
EOF
  output="$(printf '\n' | bash "${script_file}")"
  rm -f "${script_file}"
  [[ "${output##*$'\n'}" == "secret-old" ]]
}

run_xray_digest_parse_case() {
  local workdir=""
  local dgst_file=""
  local hash_value=""
  local metadata_json=""

  workdir="$(mktemp -d)"
  dgst_file="${workdir}/Xray-linux-64.zip.dgst"
  cat > "${dgst_file}" <<'EOF'
SHA256 (Xray-linux-64.zip) = 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
SHA512 (Xray-linux-64.zip) = deadbeef
EOF

  hash_value="$(parse_xray_dgst_sha256 "${dgst_file}" "Xray-linux-64.zip")"
  [[ "${hash_value}" == "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" ]]

  cat > "${dgst_file}" <<'EOF'
Xray-linux-64.zip
sha256: 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
sha512: deadbeef
EOF

  hash_value="$(parse_xray_dgst_sha256 "${dgst_file}" "Xray-linux-64.zip")"
  [[ "${hash_value}" == "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" ]]

  metadata_json='{"assets":[{"name":"Xray-linux-64.zip","browser_download_url":"https://example.invalid/Xray-linux-64.zip","digest":"sha256:0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF"}]}'
  hash_value="$(normalize_xray_sha256_value "$(xray_release_asset_field_from_metadata "${metadata_json}" "Xray-linux-64.zip" "digest")")"
  [[ "${hash_value}" == "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" ]]
  [[ "$(xray_release_asset_field_from_metadata "${metadata_json}" "Xray-linux-64.zip" "browser_download_url")" == "https://example.invalid/Xray-linux-64.zip" ]]
}

run_install_xray_checksum_failure_case() {
  local output=""

  if output="$(bash <<EOF 2>&1
set -Eeuo pipefail
ROOT_DIR="${ROOT_DIR}"
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
  local workdir=""

  workdir="$(mktemp -d)"
  printf 'client-secret\n' > "${workdir}/warp-secret.txt"
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
    --cert-mode 2 \
    --cert-file /tmp/cert.pem \
    --key-file /tmp/key.pem \
    --enable-warp \
    --warp-team team-name \
    --warp-client-id client-id \
    --warp-client-secret "@${workdir}/warp-secret.txt" \
    --warp-proxy-port 41000 \
    --disable-net-opt

  resolve_install_input_sources
  [[ "${NON_INTERACTIVE}" -eq 1 ]]
  [[ "${SERVER_IP}" == "198.51.100.10" ]]
  [[ "${NODE_LABEL_PREFIX}" == "hkg" ]]
  [[ "${REALITY_SNI}" == "reality.example.com" ]]
  [[ "${REALITY_TARGET}" == "reality.example.com:443" ]]
  [[ "${XHTTP_DOMAIN}" == "cdn.example.com" ]]
  [[ "${XHTTP_PATH}" == "/edge" ]]
  [[ "${XHTTP_VLESS_ENCRYPTION_ENABLED}" == "no" ]]
  [[ "${CERT_MODE}" == "2" ]]
  [[ "$(validate_cert_mode_value "${CERT_MODE}")" == "existing" ]]
  [[ "${CERT_SOURCE_FILE}" == "/tmp/cert.pem" ]]
  [[ "${KEY_SOURCE_FILE}" == "/tmp/key.pem" ]]
  [[ "${ENABLE_WARP}" == "yes" ]]
  [[ "${WARP_TEAM_NAME}" == "team-name" ]]
  [[ "${WARP_CLIENT_ID}" == "client-id" ]]
  [[ "${WARP_CLIENT_SECRET}" == "client-secret" ]]
  [[ "${WARP_PROXY_PORT}" == "41000" ]]
  [[ "${ENABLE_NET_OPT}" == "no" ]]
}

run_sensitive_option_reject_case() {
  local output=""

  if output="$(bash <<EOF 2>&1
set -Eeuo pipefail
ROOT_DIR="${ROOT_DIR}"
source <(sed '\$d' "${ROOT_DIR}/xray-warp-team.sh")
parse_install_args --warp-client-secret direct-secret
EOF
)"; then
    return 1
  fi
  printf '%s' "${output}" | grep -q '不支持直接明文传值'
}

run_preflight_token_verify_case() {
  local output=""

  if ! output="$(bash <<EOF 2>&1
set -Eeuo pipefail
ROOT_DIR="${ROOT_DIR}"
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
ROOT_DIR="${ROOT_DIR}"
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

run_warp_rule_normalize_case() {
  local output=""

  output="$(normalize_warp_rules_text $' chat.openai.com \n# comment\ngeosite:google\ndomain:chat.openai.com\n')"
  [[ "${output}" == $'domain:chat.openai.com\ngeosite:google' ]]

  if output="$(bash <<EOF 2>&1
set -Eeuo pipefail
ROOT_DIR="${ROOT_DIR}"
source <(sed '\$d' "${ROOT_DIR}/xray-warp-team.sh")
normalize_warp_rules_text \$'bad rule with space'
EOF
)"; then
    return 1
  fi
  printf '%s' "${output}" | grep -q 'WARP 分流规则不能包含空白字符'
}

run_optional_component_skip_case() {
  ENABLE_NET_OPT="no"
  ENABLE_WARP="no"

  install_network_optimization
  install_warp
}

run_warp_repo_file_mode_case() {
  local output=""

  if ! output="$(bash <<EOF 2>&1
set -Eeuo pipefail
ROOT_DIR="${ROOT_DIR}"
source <(sed '\$d' "${ROOT_DIR}/xray-warp-team.sh")
tmp_dir="\$(mktemp -d)"
WARP_APT_KEYRING="\${tmp_dir}/cloudflare-warp-archive-keyring.gpg"
WARP_APT_SOURCE_LIST="\${tmp_dir}/cloudflare-client.list"
backup_path() { :; }
curl() {
  printf '%s' 'pubkey' > "\${4}"
}
gpg() {
  printf '%s' 'keyring' > "\${4}"
}
apt-get() { :; }
install_warp_apt_repo "trixie"
[[ "\$(stat -c '%a' "\${WARP_APT_KEYRING}")" == "644" ]]
[[ "\$(stat -c '%a' "\${WARP_APT_SOURCE_LIST}")" == "644" ]]
EOF
)"; then
    return 1
  fi
}

run_install_warp_failure_case() {
  local mdm_written=0
  local monitor_written=0

  ENABLE_WARP="yes"
  install_warp_apt_repo() {
    return 1
  }
  write_warp_mdm_file() {
    mdm_written=$((mdm_written + 1))
  }
  install_warp_health_monitor() {
    monitor_written=$((monitor_written + 1))
  }

  if install_warp; then
    return 1
  fi
  [[ "${mdm_written}" -eq 0 ]]
  [[ "${monitor_written}" -eq 0 ]]
  load_functions
}

run_install_warp_retry_daemon_ready_case() {
  local mdm_written=0
  local monitor_written=0
  local refresh_attempts=0
  local sleep_calls=0
  local active_checks=0
  local systemctl_calls=""

  ENABLE_WARP="yes"
  WARP_SERVICE_READY_RETRIES=3
  WARP_SERVICE_READY_DELAY_SECONDS=0
  WARP_MDM_REFRESH_RETRIES=3
  WARP_MDM_REFRESH_DELAY_SECONDS=0

  install_warp_apt_repo() { :; }
  service_exists() { return 0; }
  write_warp_mdm_file() {
    mdm_written=$((mdm_written + 1))
  }
  install_warp_health_monitor() {
    monitor_written=$((monitor_written + 1))
  }
  systemctl() {
    systemctl_calls+="$*"$'\n'
    case "$*" in
      "is-active --quiet warp-svc")
        active_checks=$((active_checks + 1))
        [[ "${active_checks}" -ge 2 ]]
        ;;
      *)
        return 0
        ;;
    esac
  }
  warp-cli() {
    refresh_attempts=$((refresh_attempts + 1))
    if [[ "${refresh_attempts}" -lt 3 ]]; then
      printf '%s\n' 'Unable to connect to the CloudflareWARP daemon: No such file or directory (os error 2)' >&2
      printf '%s\n' 'Maybe the daemon is not running?' >&2
      return 1
    fi
  }
  sleep() {
    sleep_calls=$((sleep_calls + 1))
  }

  install_warp

  [[ "${mdm_written}" -eq 1 ]]
  [[ "${monitor_written}" -eq 1 ]]
  [[ "${refresh_attempts}" -eq 3 ]]
  [[ "${sleep_calls}" -eq 3 ]]
  printf '%s' "${systemctl_calls}" | grep -q '^enable --now warp-svc$'
  printf '%s' "${systemctl_calls}" | grep -q '^restart warp-svc$'
}

run_install_warp_retry_exhausted_case() {
  local refresh_attempts=0
  local sleep_calls=0

  ENABLE_WARP="yes"
  WARP_SERVICE_READY_RETRIES=1
  WARP_SERVICE_READY_DELAY_SECONDS=0
  WARP_MDM_REFRESH_RETRIES=3
  WARP_MDM_REFRESH_DELAY_SECONDS=0

  install_warp_apt_repo() { :; }
  service_exists() { return 0; }
  write_warp_mdm_file() { :; }
  install_warp_health_monitor() { :; }
  systemctl() {
    case "$*" in
      "is-active --quiet warp-svc")
        return 0
        ;;
      *)
        return 0
        ;;
    esac
  }
  warp-cli() {
    refresh_attempts=$((refresh_attempts + 1))
    printf '%s\n' 'Unable to connect to the CloudflareWARP daemon: No such file or directory (os error 2)' >&2
    printf '%s\n' 'Maybe the daemon is not running?' >&2
    return 1
  }
  sleep() {
    sleep_calls=$((sleep_calls + 1))
  }

  if install_warp; then
    return 1
  fi

  [[ "${refresh_attempts}" -eq 3 ]]
  [[ "${sleep_calls}" -eq 2 ]]
}

run_install_draft_case() {
  local workdir=""

  workdir="$(mktemp -d)"
  INSTALL_DRAFT_FILE="${workdir}/install-draft.env"
  SERVER_IP="203.0.113.10"
  NODE_LABEL_PREFIX="HKG"
  REALITY_SNI="reality.example.com"
  XHTTP_DOMAIN="cdn.example.com"
  ENABLE_WARP="yes"
  WARP_CLIENT_SECRET="secret-value"

  write_install_draft_file

  SERVER_IP=""
  NODE_LABEL_PREFIX=""
  REALITY_SNI=""
  XHTTP_DOMAIN=""
  ENABLE_WARP=""
  WARP_CLIENT_SECRET=""
  load_install_draft_file
  [[ "${SERVER_IP}" == "203.0.113.10" ]]
  [[ "${NODE_LABEL_PREFIX}" == "HKG" ]]
  [[ "${REALITY_SNI}" == "reality.example.com" ]]
  [[ "${XHTTP_DOMAIN}" == "cdn.example.com" ]]
  [[ "${ENABLE_WARP}" == "yes" ]]
  [[ "${WARP_CLIENT_SECRET}" == "secret-value" ]]

  clear_install_draft_file
  [[ ! -f "${INSTALL_DRAFT_FILE}" ]]
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
