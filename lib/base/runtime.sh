# shellcheck shell=bash

# ------------------------------
# 运行时编排层
# 负责服务、托管文件与重启流程
# ------------------------------

write_xray_service() {
  backup_path "${XRAY_SERVICE_FILE}"

  cat > "${XRAY_SERVICE_FILE}" <<EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=xray
Group=xray
Environment=XRAY_LOCATION_ASSET=${XRAY_ASSET_DIR}
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
ExecStart=${XRAY_BIN} run -config ${XRAY_CONFIG_FILE}
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
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
      backup_path "${path}"
      rm -rf "${path}"
    fi
  done
}

validate_configs() {
  log_step "校验 Xray 配置。"
  "${XRAY_BIN}" run -test -config "${XRAY_CONFIG_FILE}"
  log_success "Xray 配置校验通过。"

  log_step "校验 Nginx 配置。"
  nginx -t
  log_success "Nginx 配置校验通过。"

  log_step "校验 HAProxy 配置。"
  haproxy -c -f "${HAPROXY_CONFIG}"
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
  ensure_xray_user
  ensure_managed_permissions
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl restart xray >/dev/null 2>&1 || true
  systemctl restart haproxy >/dev/null 2>&1 || true
  systemctl restart nginx >/dev/null 2>&1 || true
}

rollback_managed_runtime_state() {
  local include_tls_assets="${1:-no}"
  local include_service_file="${2:-no}"
  local paths=(
    "${XRAY_CONFIG_FILE}"
    "${HAPROXY_CONFIG}"
    "${NGINX_CONFIG_FILE}"
  )

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

restart_services() {
  log_step "重载 systemd 并重启核心服务。"
  ensure_xray_user
  ensure_managed_permissions
  systemctl daemon-reload
  systemctl enable --now xray
  log_success "xray 已启动。"
  systemctl enable --now haproxy
  log_success "haproxy 已启动。"
  systemctl enable --now nginx
  log_success "nginx 已启动。"
  systemctl restart xray
  systemctl restart haproxy
  systemctl restart nginx

  if [[ "${ENABLE_WARP}" == "yes" ]]; then
    systemctl enable --now warp-svc
    log_success "warp-svc 已启动。"
  fi
}

finalize_installation() {
  if ! validate_configs; then
    rollback_managed_runtime_state "yes" "yes"
    return 1
  fi

  if ! restart_services; then
    rollback_managed_runtime_state "yes" "yes"
    return 1
  fi

  write_state_file
  write_output_file
}

restart_core_services() {
  log_step "重启托管服务。"
  ensure_xray_user
  ensure_managed_permissions
  systemctl restart xray
  log_success "xray 已重启。"
  systemctl restart haproxy
  log_success "haproxy 已重启。"
  systemctl restart nginx
  log_success "nginx 已重启。"
}

write_runtime_managed_files() {
  write_xray_config
  write_haproxy_config
  write_nginx_config
}

apply_managed_files() {
  local include_tls_assets="${1:-no}"

  if [[ "${include_tls_assets}" == "yes" ]]; then
    write_tls_assets
  fi

  write_runtime_managed_files
  if ! validate_configs; then
    rollback_managed_runtime_state "${include_tls_assets}" "no"
    return 1
  fi

  if ! restart_core_services; then
    rollback_managed_runtime_state "${include_tls_assets}" "no"
    return 1
  fi

  write_state_file
  write_output_file
}
