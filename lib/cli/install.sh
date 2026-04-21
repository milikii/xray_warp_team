# shellcheck shell=bash

# ------------------------------
# 安装 CLI 层
# 负责 install 参数解析与安装命令编排
# ------------------------------

install_flag_specs() {
  cat <<'EOF'
--non-interactive:NON_INTERACTIVE:1
--enable-xhttp-vless-encryption:XHTTP_VLESS_ENCRYPTION_ENABLED:yes
--disable-xhttp-vless-encryption:XHTTP_VLESS_ENCRYPTION_ENABLED:no
--enable-warp:ENABLE_WARP:yes
--disable-warp:ENABLE_WARP:no
--enable-net-opt:ENABLE_NET_OPT:yes
--disable-net-opt:ENABLE_NET_OPT:no
EOF
}

install_value_specs() {
  cat <<'EOF'
--server-ip:SERVER_IP
--node-label-prefix:NODE_LABEL_PREFIX
--reality-uuid:REALITY_UUID
--reality-sni:REALITY_SNI
--reality-target:REALITY_TARGET
--reality-short-id:REALITY_SHORT_ID
--reality-private-key:REALITY_PRIVATE_KEY
--xhttp-uuid:XHTTP_UUID
--xhttp-domain:XHTTP_DOMAIN
--xhttp-path:XHTTP_PATH
--cert-mode:CERT_MODE
--cert-file:CERT_SOURCE_FILE
--key-file:KEY_SOURCE_FILE
--cert-pem:CERT_SOURCE_PEM
--key-pem:KEY_SOURCE_PEM
--cf-zone-id:CF_ZONE_ID
--cf-api-token:CF_API_TOKEN
--cf-cert-validity:CF_CERT_VALIDITY
--acme-email:ACME_EMAIL
--acme-ca:ACME_CA
--cf-dns-token:CF_DNS_TOKEN
--cf-dns-account-id:CF_DNS_ACCOUNT_ID
--cf-dns-zone-id:CF_DNS_ZONE_ID
--warp-team:WARP_TEAM_NAME
--warp-client-id:WARP_CLIENT_ID
--warp-client-secret:WARP_CLIENT_SECRET
--warp-proxy-port:WARP_PROXY_PORT
EOF
}

apply_install_flag_spec() {
  local option="${1}"
  local spec="${2}"
  local spec_option=""
  local var_name=""
  local value=""

  IFS=':' read -r spec_option var_name value <<< "${spec}"
  [[ "${option}" == "${spec_option}" ]] || return 1
  printf -v "${var_name}" '%s' "${value}"
  return 0
}

apply_install_value_spec() {
  local option="${1}"
  local spec="${2}"
  local spec_option=""
  local var_name=""

  shift 2
  IFS=':' read -r spec_option var_name <<< "${spec}"
  [[ "${option}" == "${spec_option}" ]] || return 1
  assign_option_value "${var_name}" "${option}" "$@"
  return 0
}

parse_install_args() {
  local spec=""

  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --help|-h|help)
        usage
        exit 0
        ;;
    esac

    while IFS= read -r spec; do
      [[ -n "${spec}" ]] || continue
      if apply_install_flag_spec "${1}" "${spec}"; then
        shift
        continue 2
      fi
    done < <(install_flag_specs)

    while IFS= read -r spec; do
      [[ -n "${spec}" ]] || continue
      if apply_install_value_spec "${1}" "${spec}" "${@:2}"; then
        shift 2
        continue 2
      fi
    done < <(install_value_specs)

    if handle_change_common_arg "${1}"; then
      shift
      continue
    fi

    die "未知的 install 参数：${1}"
  done
}

prepare_install_command() {
  need_root
  ensure_debian_family
  start_backup_session
  parse_install_args "$@"
  prepare_install_inputs
  validate_install_inputs
}

install_xray_runtime() {
  install_packages
  install_self_command
  install_xray
  ensure_xray_bind_capability
  ensure_xray_user
  generate_reality_keys_if_needed
}

write_install_managed_files() {
  write_tls_assets
  write_xray_config
  write_haproxy_config
  write_nginx_config
  write_xray_service
}

install_optional_components() {
  install_network_optimization
  install_warp
}

install_cmd() {
  log_step "准备安装参数与运行环境。"
  prepare_install_command "$@"
  log_step "安装 Xray 运行时。"
  install_xray_runtime
  log_step "写入托管配置文件。"
  write_install_managed_files
  log_step "安装可选组件。"
  install_optional_components
  log_step "校验并启动托管服务。"
  finalize_installation

  log "部署完成。"
  log "备份目录：${BACKUP_DIR}"
  log "管理命令：${SELF_COMMAND_PATH}"
  log "节点链接已写入：${OUTPUT_FILE}"
  show_links
}
