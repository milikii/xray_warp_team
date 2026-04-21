# shellcheck shell=bash

# ------------------------------
# 变更命令层
# 负责具体 change-* 与 upgrade 命令
# ------------------------------

upgrade_cmd() {
  local previous_version=""
  local current_version=""

  need_root
  ensure_debian_family
  [[ -x "${XRAY_BIN}" ]] || die "找不到当前 Xray 可执行文件：${XRAY_BIN}"

  start_backup_session
  backup_path "${XRAY_BIN}"
  backup_path "${XRAY_ASSET_DIR}"
  previous_version="$("${XRAY_BIN}" version 2>/dev/null | head -n 1 || true)"
  [[ -n "${previous_version}" ]] && log "升级前版本：${previous_version}"

  log_step "升级 Xray 核心。"
  install_xray
  ensure_xray_bind_capability
  if ! validate_configs; then
    warn "升级后的配置校验失败，正在回滚 Xray 核心文件。"
    restore_backup_path "${XRAY_BIN}" || true
    restore_backup_path "${XRAY_ASSET_DIR}" || true
    return 1
  fi
  log_step "重启 xray 服务。"
  if ! systemctl restart xray; then
    warn "xray 重启失败，正在回滚 Xray 核心文件。"
    restore_backup_path "${XRAY_BIN}" || true
    restore_backup_path "${XRAY_ASSET_DIR}" || true
    systemctl restart xray >/dev/null 2>&1 || true
    return 1
  fi

  current_version="$("${XRAY_BIN}" version 2>/dev/null | head -n 1 || true)"
  log_success "升级完成。"
  log "备份目录：${BACKUP_DIR}"
  [[ -n "${current_version}" ]] && log "当前版本：${current_version}"
}

change_uuid_cmd() {
  local -A request=()

  init_change_uuid_request request
  parse_change_uuid_args request "$@"

  if [[ "${request[rotate_reality]}" -eq 0 && "${request[rotate_xhttp]}" -eq 0 ]]; then
    die "没有需要修改的内容。请使用默认行为，或传入 --reality-only / --xhttp-only。"
  fi

  begin_managed_change

  if [[ "${request[rotate_reality]}" -eq 1 ]]; then
    REALITY_UUID="${request[reality_uuid]:-$(random_uuid)}"
  fi

  if [[ "${request[rotate_xhttp]}" -eq 1 ]]; then
    XHTTP_UUID="${request[xhttp_uuid]:-$(random_uuid)}"
  fi

  log_step "写入新的 UUID 配置。"
  write_xray_config
  log_step "校验并重启 xray。"
  validate_configs
  systemctl restart xray
  write_state_file
  write_output_file

  finish_managed_change "UUID 轮换完成。"
}

change_sni_cmd() {
  run_single_value_change_cmd \
    "--reality-sni" \
    "REALITY_SNI" \
    "新的 REALITY 可见 SNI" \
    "REALITY SNI 已更新。" \
    "未知的 change-sni 参数：" \
    "runtime" \
    "" \
    "ensure_reality_sni_format" \
    "$@"
}

change_path_cmd() {
  run_single_value_change_cmd \
    "--xhttp-path" \
    "XHTTP_PATH" \
    "新的 XHTTP 路径" \
    "XHTTP 路径已更新。" \
    "未知的 change-path 参数：" \
    "runtime" \
    "" \
    "ensure_xhttp_path_format" \
    "$@"
}

change_label_prefix_cmd() {
  run_single_value_change_cmd \
    "--node-label-prefix" \
    "NODE_LABEL_PREFIX" \
    "新的节点名前缀" \
    "节点名前缀已更新。" \
    "未知的 change-label-prefix 参数：" \
    "output" \
    "normalize_node_label_prefix" \
    "" \
    "$@"
}

change_warp_cmd() {
  local -A request=()

  init_change_warp_request request
  parse_change_warp_args request "$@"
  ensure_debian_family
  begin_managed_change

  apply_warp_change_request request
  run_change_warp_action "$(resolve_change_warp_target_mode "${request[target_mode]}")"
}

change_cert_mode_cmd() {
  local old_cert_mode=""
  local old_xhttp_domain=""
  local -A request=()

  init_change_cert_mode_request request
  parse_change_cert_mode_args request "$@"
  begin_managed_change
  old_cert_mode="${CERT_MODE}"
  old_xhttp_domain="${XHTTP_DOMAIN}"

  apply_cert_mode_change_request request "${old_cert_mode}" "${old_xhttp_domain}"
  prompt_cert_mode_inputs
  validate_install_inputs
  apply_managed_update
  cleanup_previous_acme_cert "${old_cert_mode}" "${old_xhttp_domain}"

  finish_managed_change "证书模式已更新。"
}
