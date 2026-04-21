# shellcheck shell=bash

# ------------------------------
# CLI 核心层
# 负责状态、菜单、分发与通用维护命令
# ------------------------------

show_links() {
  [[ -f "${STATE_FILE}" ]] || die "找不到状态文件：${STATE_FILE}"
  [[ -f "${OUTPUT_FILE}" ]] || die "找不到输出文件：${OUTPUT_FILE}"
  cat "${OUTPUT_FILE}"
}

xray_managed_service_units() {
  printf '%s\n' \
    "xray.service" \
    "haproxy.service" \
    "nginx.service" \
    "warp-svc.service" \
    "${NET_SERVICE_NAME}"
}

restart_service_if_present() {
  local unit_name="${1}"

  if service_exists "${unit_name}"; then
    systemctl restart "${unit_name}" >/dev/null 2>&1 || true
  fi
}

status_raw_cmd() {
  local units=()

  mapfile -t units < <(xray_managed_service_units)
  systemctl --no-pager --full status "${units[@]}" 2>/dev/null || true
}

status_cmd() {
  local raw=0

  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --raw)
        raw=1
        ;;
      --help|-h|help)
        usage
        exit 0
        ;;
      *)
        die "未知的 status 参数：${1}"
        ;;
    esac
    shift
  done

  if [[ "${raw}" -eq 1 ]]; then
    status_raw_cmd
    return
  fi

  show_dashboard
}

restart_cmd() {
  local unit_name=""

  while IFS= read -r unit_name; do
    restart_service_if_present "${unit_name}"
  done < <(xray_managed_service_units)
  log "服务已重启。"
}

repair_perms_cmd() {
  need_root
  ensure_xray_user
  ensure_managed_permissions
  systemctl daemon-reload
  systemctl restart xray haproxy nginx >/dev/null 2>&1 || true
  log "已修复脚本托管文件权限，并尝试重启 xray、haproxy 与 nginx。"
}

uninstall_cmd() {
  local assume_yes=0
  local answer=""
  local unit_name=""
  local units=()

  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --yes|-y)
        assume_yes=1
        ;;
      --help|-h|help)
        usage
        exit 0
        ;;
      *)
        die "未知的 uninstall 参数：${1}"
        ;;
    esac
    shift
  done

  need_root
  start_backup_session
  load_existing_state

  if [[ "${assume_yes}" -ne 1 ]]; then
    read -r -p "该操作会停止服务并删除脚本托管文件，但保留已安装的软件包。是否继续？ [y/N]: " answer
    answer="$(printf '%s' "${answer}" | tr 'A-Z' 'a-z')"
    if [[ "${answer}" != "y" && "${answer}" != "yes" ]]; then
      die "已取消卸载。"
    fi
  fi

  while IFS= read -r unit_name; do
    stop_and_disable_service_if_present "${unit_name}"
  done < <(xray_managed_service_units)

  if [[ "${CERT_MODE:-}" == "acme-dns-cf" && -x "${ACME_SH_BIN}" && -n "${XHTTP_DOMAIN:-}" ]]; then
    "${ACME_SH_BIN}" --remove -d "${XHTTP_DOMAIN}" --ecc >/dev/null 2>&1 || true
  fi

  remove_managed_paths \
    "${SELF_COMMAND_PATH}" \
    "${SELF_INSTALL_DIR}" \
    "${XRAY_BIN}" \
    "${XRAY_CONFIG_DIR}" \
    "${XRAY_ASSET_DIR}" \
    "${XRAY_SERVICE_FILE}" \
    "${HAPROXY_CONFIG}" \
    "${NGINX_CONFIG_FILE}" \
    "${SSL_DIR}" \
    "${WARP_MDM_FILE}" \
    "${NET_SYSCTL_CONF}" \
    "${NET_HELPER_PATH}" \
    "${NET_SERVICE_FILE}" \
    "${ACME_RELOAD_HELPER}" \
    "${OUTPUT_FILE}" \
    "/var/log/xray" \
    "/var/lib/xray"

  systemctl daemon-reload
  mapfile -t units < <(xray_managed_service_units)
  systemctl reset-failed "${units[@]}" >/dev/null 2>&1 || true
  sysctl --system >/dev/null 2>&1 || true

  log "脚本托管文件已删除。"
  log "备份目录：${BACKUP_DIR}"
  log "已安装的软件包已保留。"
}

show_main_menu() {
  cat <<'EOF'
  1. 安装或重装
  2. 查看节点链接
  3. 刷新状态面板
  4. 重启服务
  5. 升级 Xray 核心
  6. 轮换节点 UUID
  7. 修改 REALITY SNI
  8. 修改 XHTTP 路径
  9. 修改节点名前缀
  10. 开关 WARP 分流
  11. 修改证书模式 / CDN 域名
  12. 抢修文件权限
  13. 卸载托管文件
  14. 查看原始服务详情
  15. 帮助
  0. 退出
EOF
}

pause_after_menu_action() {
  printf '\n'
  read -r -p "按回车继续..." _
}

run_cli_command() {
  local command="${1:-menu}"

  if [[ $# -gt 0 ]]; then
    shift
  fi

  case "${command}" in
    menu)
      main_menu
      ;;
    install)
      install_cmd "$@"
      ;;
    upgrade)
      upgrade_cmd "$@"
      ;;
    change-uuid)
      change_uuid_cmd "$@"
      ;;
    change-sni)
      change_sni_cmd "$@"
      ;;
    change-path)
      change_path_cmd "$@"
      ;;
    change-label-prefix)
      change_label_prefix_cmd "$@"
      ;;
    change-warp)
      change_warp_cmd "$@"
      ;;
    change-cert-mode)
      change_cert_mode_cmd "$@"
      ;;
    uninstall)
      uninstall_cmd "$@"
      ;;
    show-links)
      show_links
      ;;
    status)
      status_cmd "$@"
      ;;
    restart)
      restart_cmd
      ;;
    repair-perms)
      repair_perms_cmd
      ;;
    help|--help|-h)
      usage
      ;;
    *)
      die "未知命令：${command}"
      ;;
  esac
}

run_menu_choice() {
  case "${1}" in
    1) run_cli_command install ;;
    2) run_cli_command show-links ;;
    3) run_cli_command status ;;
    4) run_cli_command restart ;;
    5) run_cli_command upgrade ;;
    6) run_cli_command change-uuid ;;
    7) run_cli_command change-sni ;;
    8) run_cli_command change-path ;;
    9) run_cli_command change-label-prefix ;;
    10) run_cli_command change-warp ;;
    11) run_cli_command change-cert-mode ;;
    12) run_cli_command repair-perms ;;
    13) run_cli_command uninstall ;;
    14) run_cli_command status --raw ;;
    15) run_cli_command help ;;
    *)
      warn "未知的菜单项：${1}"
      return 1
      ;;
  esac
}

main_menu() {
  local choice=""

  while true; do
    if [[ -t 1 ]]; then
      clear >/dev/null 2>&1 || true
    fi
    show_dashboard
    show_main_menu
    read -r -p "请选择: " choice
    if [[ "${choice}" == "0" ]]; then
      exit 0
    fi
    run_menu_choice "${choice}" || true
    pause_after_menu_action
  done
}
