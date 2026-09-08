# shellcheck shell=bash

# ------------------------------
# 运行时编排层
# 负责服务、托管文件与重启流程
# ------------------------------

write_xray_service() {
  local tmp_file=""

  tmp_file="$(mktemp)"
  cat > "${tmp_file}" <<EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=xray
Group=xray
Environment=XRAY_LOCATION_ASSET=${XRAY_ASSET_DIR}
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
ExecStartPre=${XRAY_BIN} run -test -config ${XRAY_CONFIG_FILE}
ExecStart=${XRAY_BIN} run -config ${XRAY_CONFIG_FILE}
Restart=always
RestartSec=3s
TimeoutStartSec=30s
TimeoutStopSec=15s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  backup_path "${XRAY_SERVICE_FILE}" || return 1
  install -m 0644 "${tmp_file}" "${XRAY_SERVICE_FILE}" || return 1
  rm -f "${tmp_file}"
}

write_xray_logrotate_config() {
  local tmp_file=""

  tmp_file="$(mktemp)"
  cat > "${tmp_file}" <<'EOF'
/var/log/xray/access.log /var/log/xray/error.log /var/log/xtun/operations.log {
  daily
  rotate 7
  missingok
  notifempty
  compress
  delaycompress
  copytruncate
  create 0640 xray xray
}
EOF

  backup_path "${XRAY_LOGROTATE_FILE}" || return 1
  install -m 0644 "${tmp_file}" "${XRAY_LOGROTATE_FILE}" || return 1
  rm -f "${tmp_file}"
}

service_exists() {
  local unit_name="${1}"
  local path=""

  for path in /etc/systemd/system/"${unit_name}" /lib/systemd/system/"${unit_name}" /usr/lib/systemd/system/"${unit_name}"; do
    if [[ -f "${path}" || -L "${path}" ]]; then
      return 0
    fi
  done

  return 1
}

stop_and_disable_service_if_present() {
  local unit_name="${1}"

  if service_exists "${unit_name}"; then
    systemctl disable --now "${unit_name}" >/dev/null 2>&1 || systemctl stop "${unit_name}" >/dev/null 2>&1 || true
  fi
}

remove_managed_paths() {
  local path=""

  for path in "$@"; do
    if [[ -e "${path}" || -L "${path}" ]]; then
      backup_path "${path}" || return 1
      rm -rf "${path}" || return 1
    fi
  done
}

# 0.11 及更早版本写盘、现在已废弃的路径。
# 统一从这里列出来，升级 / 卸载 / 重装时兜底清一遍。
# LEGACY_PATH_ROOT 供测试沙箱改写；生产环境留空，路径就是字面的绝对路径。
legacy_managed_paths() {
  local prefix="${LEGACY_PATH_ROOT:-}"

  printf '%s\n' \
    "${prefix}/usr/local/sbin/xtun-core-health.sh" \
    "${prefix}/etc/systemd/system/xtun-core-health.service" \
    "${prefix}/etc/systemd/system/xtun-core-health.timer" \
    "${prefix}/usr/local/etc/xray/health-state.env" \
    "${prefix}/usr/local/etc/xray/health-history.log" \
    "${prefix}/root/xtun-subscriptions" \
    "${prefix}/var/lib/cloudflare-warp/mdm.xml" \
    "${prefix}/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg" \
    "${prefix}/etc/apt/sources.list.d/cloudflare-client.list" \
    "${prefix}/usr/local/sbin/xtun-warp-health.sh" \
    "${prefix}/etc/systemd/system/xtun-warp-health.service" \
    "${prefix}/etc/systemd/system/xtun-warp-health.timer"
}

# 下面这几个「校验 / 重启」函数都是在 `if ! xxx; then 回滚; fi` 里被调用的，
# 而 `if !` 会把整条调用链上的 set -e 关掉。所以每一步都得显式 `|| return 1`：
# 少写一个，前一步失败后函数会接着往下跑，最终返回最后一条命令（多半是
# log_success）的 0，调用方看到成功，回滚一次都不会触发。
validate_xray_config() {
  log_step "校验 Xray 配置。"
  "${XRAY_BIN}" run -test -config "${XRAY_CONFIG_FILE}" || return 1
  log_success "Xray 配置校验通过。"
}

validate_configs() {
  validate_xray_config || return 1

  log_step "校验 Nginx 配置。"
  nginx -t || return 1
  log_success "Nginx 配置校验通过。"

  log_step "校验 HAProxy 配置。"
  haproxy -c -f "${HAPROXY_CONFIG}" || return 1
  log_success "HAProxy 配置校验通过。"
}

rollback_managed_paths() {
  local path=""

  for path in "$@"; do
    if [[ -n "${BACKUP_DIR:-}" && ( -e "${BACKUP_DIR}${path}" || -L "${BACKUP_DIR}${path}" ) ]]; then
      warn "回滚文件：${path}"
    else
      warn "移除本次新增文件：${path}"
    fi
    restore_backup_path "${path}" || true
  done
}

attempt_runtime_service_recovery() {
  # 这条是回滚之后的抢救路径，尽力而为：任何一步失败都不该拦住后面的重启。
  ensure_xray_user || true
  ensure_managed_permissions || true
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl restart xray >/dev/null 2>&1 || true
  systemctl restart haproxy >/dev/null 2>&1 || true
  systemctl restart nginx >/dev/null 2>&1 || true
}

attempt_xray_service_recovery() {
  ensure_xray_user || true
  ensure_managed_permissions || true
  systemctl restart xray >/dev/null 2>&1 || true
}

rollback_managed_runtime_state() {
  local include_tls_assets="${1:-no}"
  local include_service_file="${2:-no}"
  local paths=(
    "${XRAY_CONFIG_FILE}"
    "${HAPROXY_CONFIG}"
    "${NGINX_CONFIG_FILE}"
    "${NGINX_LIMITS_DROPIN_FILE}"
    "${WARP_RULES_FILE}"
    "${XRAY_LOGROTATE_FILE}"
    "${FALLBACK_SITE_DIR}"
  )

  # 健康状态、恢复历史与操作日志不进回滚清单：
  # 它们从来不进 backup_path，而 restore_backup_path 对没有备份条目的路径是直接 rm -rf。
  # 一次回滚会连带删掉排障时最需要的现场记录。

  if [[ "${include_tls_assets}" == "yes" ]]; then
    paths+=("${TLS_CERT_FILE}" "${TLS_KEY_FILE}" "${ACME_RELOAD_HELPER}")
  fi

  if [[ "${include_service_file}" == "yes" ]]; then
    paths+=("${XRAY_SERVICE_FILE}")
  fi

  warn "检测到托管配置应用失败，正在回滚最近一次变更。"
  rollback_managed_paths "${paths[@]}"
  attempt_runtime_service_recovery
}

rollback_xray_config_state() {
  warn "检测到 Xray 配置应用失败，正在回滚最近一次 Xray 配置变更。"
  rollback_managed_paths "${XRAY_CONFIG_FILE}"
  attempt_xray_service_recovery
}

rollback_xray_only_managed_state() {
  local paths=(
    "${XRAY_CONFIG_FILE}"
    "${STATE_FILE}"
    "${OUTPUT_FILE}"
  )

  warn "检测到 Xray-only 变更应用失败，正在回滚最近一次变更。"
  rollback_managed_paths "${paths[@]}"
  attempt_xray_service_recovery
}

rollback_install_runtime_state() {
  local paths=(
    "${SELF_COMMAND_PATH}"
    "${SELF_INSTALL_DIR}"
    "${XRAY_BIN}"
    "${XRAY_ASSET_DIR}"
    "${FALLBACK_SITE_DIR}"
  )

  warn "检测到安装运行时应用失败，正在回滚管理命令与 Xray 核心文件。"
  rollback_managed_paths "${paths[@]}"
}

rollback_optional_component_state() {
  local paths=()

  if [[ "${ENABLE_NET_OPT:-no}" == "yes" ]]; then
    stop_and_disable_service_if_present "${NET_SERVICE_NAME}"
    paths+=(
      "${NET_SYSCTL_CONF}"
      "${NET_HELPER_PATH}"
      "${NET_SERVICE_FILE}"
    )
  fi

  [[ "${#paths[@]}" -gt 0 ]] || return 0

  warn "检测到可选组件应用失败，正在回滚网络优化托管文件。"
  rollback_managed_paths "${paths[@]}"
  systemctl daemon-reload >/dev/null 2>&1 || true

  if [[ "${ENABLE_NET_OPT:-no}" == "yes" ]]; then
    sysctl --system >/dev/null 2>&1 || true
  fi
}

# nginx 和 haproxy 都能热重载，而且这三类改动（改 SNI / 改路径 / 换证书）没有一个
# 需要断连接：nginx 收到 SIGHUP 会重读配置和证书，老 worker 把在飞的请求做完再退；
# haproxy 先自检配置再给 master 发 USR2，老进程继续伺候已建立的连接。
# restart 则是把这台机上所有在跑的代理连接一次性掐断。没在跑时才退回 restart。
reload_or_restart_service() {
  local unit="${1}"

  if systemctl is-active --quiet "${unit}"; then
    systemctl reload "${unit}" || return 1
    log_success "${unit} 已重载。"
    return 0
  fi

  systemctl restart "${unit}" || return 1
  log_success "${unit} 已启动。"
}

# 刚写下的 systemd drop-in 改的是进程 rlimit，reload 套不上，这一次得走重启。
apply_nginx_service_change() {
  if [[ "${NGINX_RESTART_REQUIRED:-no}" != "yes" ]]; then
    reload_or_restart_service nginx || return 1
    return 0
  fi

  systemctl daemon-reload || return 1
  systemctl restart nginx || return 1
  log_success "nginx 已重启（套用新的 fd 限额）。"
  NGINX_RESTART_REQUIRED="no"
}

restart_services() {
  log_step "重载 systemd 并重启核心服务。"
  ensure_xray_user || return 1
  ensure_managed_permissions || return 1
  systemctl daemon-reload || return 1
  # enable 只负责开机自启。原来写的是 `enable --now` 之后紧跟一次 restart，
  # 等于把三个服务各起两遍；启动统一交给下面一段。
  systemctl enable xray haproxy nginx || return 1
  systemctl restart xray || return 1
  log_success "xray 已启动。"
  reload_or_restart_service haproxy || return 1
  apply_nginx_service_change || return 1
}

remove_legacy_managed_paths() {
  local path=""
  local had_legacy="no"
  local -a paths=()

  stop_and_disable_service_if_present "xtun-core-health.timer"
  stop_and_disable_service_if_present "xtun-warp-health.timer"
  stop_and_disable_service_if_present "warp-svc.service"

  while IFS= read -r path; do
    if [[ -e "${path}" || -L "${path}" ]]; then
      paths+=("${path}")
      had_legacy="yes"
    fi
  done < <(legacy_managed_paths)

  [[ "${had_legacy}" == "yes" ]] || return 0

  log_step "清理旧版本遗留的托管文件。"
  if [[ "${#paths[@]}" -gt 0 ]]; then
    # 与 warp_teardown_legacy 同一个取舍：升级路径上删不掉旧文件不该把整次
    # 变更判成失败，但也不能闷声跳过——下面那句 log 会说「已清理」。
    remove_managed_paths "${paths[@]}" || warn "旧版本遗留的托管文件未能全部清理，请手工检查。"
  fi
  systemctl daemon-reload >/dev/null 2>&1 || true
  log "旧版本遗留的巡检、WARP Team 与本地订阅目录文件已清理。"
}

finalize_installation() {
  if ! validate_configs; then
    rollback_managed_runtime_state "yes" "yes"
    rollback_optional_component_state
    return 1
  fi

  if ! restart_services; then
    rollback_managed_runtime_state "yes" "yes"
    rollback_optional_component_state
    return 1
  fi

  write_state_file || return 1
  write_output_file
}

restart_core_services() {
  log_step "应用托管服务变更。"
  ensure_xray_user || return 1
  ensure_managed_permissions || return 1
  # xray 没有配置热重载，只能重启。
  systemctl restart xray || return 1
  log_success "xray 已重启。"
  reload_or_restart_service haproxy || return 1
  apply_nginx_service_change || return 1
}

restart_xray_service() {
  log_step "重启 Xray 服务。"
  ensure_xray_user || return 1
  ensure_managed_permissions || return 1
  systemctl restart xray || return 1
  log_success "xray 已重启。"
}

write_runtime_managed_files() {
  deploy_fallback_site || return 1
  write_warp_rules_file || return 1
  write_xray_config || return 1
  write_haproxy_config || return 1
  write_nginx_config || return 1
  write_nginx_limits_dropin || return 1
}

apply_managed_files() {
  local include_tls_assets="${1:-no}"

  if [[ "${include_tls_assets}" == "yes" ]]; then
    if ! write_tls_assets; then
      rollback_managed_runtime_state "${include_tls_assets}" "no"
      return 1
    fi
  fi

  # 写到一半失败也要回滚：几个托管文件是分别落盘的，
  # 半份新配置 + 半份旧配置比整份旧配置更难查。
  if ! write_runtime_managed_files; then
    rollback_managed_runtime_state "${include_tls_assets}" "no"
    return 1
  fi

  if ! validate_configs; then
    rollback_managed_runtime_state "${include_tls_assets}" "no"
    return 1
  fi

  if ! restart_core_services; then
    rollback_managed_runtime_state "${include_tls_assets}" "no"
    return 1
  fi

  write_state_file || return 1
  write_output_file
}

apply_xray_only_managed_update() {
  if ! write_xray_config; then
    rollback_xray_config_state
    return 1
  fi

  if ! validate_xray_config; then
    rollback_xray_config_state
    return 1
  fi

  write_state_file || return 1
  write_output_file || return 1

  log "客户端配置、状态文件和输出文件已写入；接下来只重启 Xray。"
  if ! restart_xray_service; then
    rollback_xray_only_managed_state
    return 1
  fi
}
