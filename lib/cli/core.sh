# shellcheck shell=bash

# ------------------------------
# CLI 核心层
# 负责状态、菜单、分发与通用维护命令
# ------------------------------

show_links() {
  local show_qr=0

  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --qr)
        show_qr=1
        ;;
      --help|-h|help)
        usage
        exit 0
        ;;
      *)
        die "未知的 show-links 参数：${1}"
        ;;
    esac
    shift
  done

  [[ -f "${OUTPUT_FILE}" ]] || die "找不到输出文件：${OUTPUT_FILE}"
  cat "${OUTPUT_FILE}"

  if [[ "${show_qr}" -eq 1 ]]; then
    if ! command -v qrencode >/dev/null 2>&1; then
      warn "系统中未找到 qrencode，无法输出二维码。"
      return
    fi

    printf '\n'
    while IFS= read -r link; do
      [[ "${link}" == vless://* ]] || continue
      printf '%s\n' "二维码:"
      qrencode -t ANSIUTF8 "${link}" || true
      printf '\n'
    done < "${OUTPUT_FILE}"
  fi
}

xray_managed_service_units() {
  printf '%s\n' \
    "xray.service" \
    "haproxy.service" \
    "nginx.service" \
    "${CORE_HEALTH_TIMER_NAME}" \
    "warp-svc.service" \
    "${WARP_HEALTH_TIMER_NAME}" \
    "${NET_SERVICE_NAME}"
}

restart_service_units() {
  printf '%s\n' \
    "xray.service" \
    "haproxy.service" \
    "nginx.service" \
    "${CORE_HEALTH_TIMER_NAME}"

  if [[ "${ENABLE_WARP:-no}" == "yes" ]]; then
    printf '%s\n' \
      "warp-svc.service" \
      "${WARP_HEALTH_TIMER_NAME}"
  fi

  if [[ "${ENABLE_NET_OPT:-no}" == "yes" ]]; then
    printf '%s\n' "${NET_SERVICE_NAME}"
  fi
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

diagnose_cmd() {
  local failures=0
  local xray_state=""
  local haproxy_state=""
  local nginx_state=""
  local warp_state=""
  local core_health_state=""
  local warp_health_state=""
  local warp_exit_ip=""
  local -a service_failures=()
  local -a port_failures=()
  local -a config_failures=()
  local -a tls_failures=()
  local -a warp_failures=()

  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --help|-h|help)
        usage
        exit 0
        ;;
      *)
        die "未知的 diagnose 参数：${1}"
        ;;
    esac
    shift
  done

  load_dashboard_context

  xray_state="$(service_active_state 'xray.service')"
  haproxy_state="$(service_active_state 'haproxy.service')"
  nginx_state="$(service_active_state 'nginx.service')"
  warp_state="$(service_active_state 'warp-svc.service')"
  core_health_state="$(service_active_state "${CORE_HEALTH_TIMER_NAME}")"
  warp_health_state="$(service_active_state "${WARP_HEALTH_TIMER_NAME}")"
  warp_exit_ip="$(warp_exit_ip_text)"

  printf '%s\n' "Xray WARP 诊断"
  printf '%s\n' "脚本版本: ${SCRIPT_VERSION}"
  printf '%s\n' "xray: ${xray_state}"
  printf '%s\n' "haproxy: ${haproxy_state}"
  printf '%s\n' "nginx: ${nginx_state}"
  printf '%s\n' "warp-svc: ${warp_state}"
  printf '%s\n' "核心巡检: ${core_health_state}"
  printf '%s\n' "WARP 巡检: ${warp_health_state}"
  printf '%s\n' "监听 443: $(listening_port_text 443)"
  printf '%s\n' "监听 2443: $(listening_port_text 2443)"
  printf '%s\n' "监听 8001: $(listening_port_text 8001)"
  printf '%s\n' "监听 8443: $(listening_port_text 8443)"
  printf '%s\n' "Xray 配置: $(xray_config_check_text)"
  printf '%s\n' "Nginx 配置: $(nginx_config_check_text)"
  printf '%s\n' "HAProxy 配置: $(haproxy_config_check_text)"
  printf '%s\n' "本地 TLS 探测: $(local_tls_probe_text)"
  printf '%s\n' "证书到期: $(cert_expiry_text)"
  printf '%s\n' "WARP 出口 IP: ${warp_exit_ip}"
  printf '%s\n' "核心自恢复: $(health_event_text CORE_HEALTH)"
  printf '%s\n' "WARP 自恢复: $(health_event_text WARP_HEALTH)"
  printf '%s\n' "最近恢复记录: $(latest_health_history_text)"
  printf '%s\n' "近1小时恢复: core=$(health_history_count_text 1 core) warp=$(health_history_count_text 1 warp)"
  printf '%s\n' "近24小时恢复: core=$(health_history_count_text 24 core) warp=$(health_history_count_text 24 warp)"
  printf '%s\n' "稳定性信号: $(stability_signal_text)"

  [[ "${xray_state}" == "active" ]] || service_failures+=("xray 未运行")
  [[ "${haproxy_state}" == "active" ]] || service_failures+=("haproxy 未运行")
  [[ "${nginx_state}" == "active" ]] || service_failures+=("nginx 未运行")
  is_port_listening 443 || port_failures+=("443 未监听")
  is_port_listening 2443 || port_failures+=("2443 未监听")
  is_port_listening 8001 || port_failures+=("8001 未监听")
  is_port_listening 8443 || port_failures+=("8443 未监听")
  [[ "$(xray_config_check_state)" == "ok" ]] || config_failures+=("Xray 配置校验失败")
  [[ "$(nginx_config_check_state)" == "ok" ]] || config_failures+=("Nginx 配置校验失败")
  [[ "$(haproxy_config_check_state)" == "ok" ]] || config_failures+=("HAProxy 配置校验失败")
  [[ "$(local_tls_probe_state)" == "ok" ]] || tls_failures+=("本地 TLS 探测失败")

  if [[ "${ENABLE_WARP:-no}" == "yes" ]]; then
    [[ "${warp_state}" == "active" ]] || warp_failures+=("warp-svc 未运行")
    [[ "${warp_health_state}" == "active" ]] || warp_failures+=("WARP 巡检未运行")
    [[ "${warp_exit_ip}" != 未探测* ]] || warp_failures+=("WARP 出口 IP 未探测成功")
  fi

  failures=$(( ${#service_failures[@]} + ${#port_failures[@]} + ${#config_failures[@]} + ${#tls_failures[@]} + ${#warp_failures[@]} ))
  if [[ "${failures}" -gt 0 ]]; then
    printf '\n'
    printf '%s\n' "诊断摘要: 检测到 ${failures} 个问题"
    for item in "${service_failures[@]}"; do
      printf '%s\n' "服务: ${item}"
    done
    for item in "${port_failures[@]}"; do
      printf '%s\n' "端口: ${item}"
    done
    for item in "${config_failures[@]}"; do
      printf '%s\n' "配置: ${item}"
    done
    for item in "${tls_failures[@]}"; do
      printf '%s\n' "连接: ${item}"
    done
    for item in "${warp_failures[@]}"; do
      printf '%s\n' "WARP: ${item}"
    done
    return 1
  fi

  printf '\n'
  printf '%s\n' "诊断摘要: 未发现关键问题"
}

restart_cmd() {
  local unit_name=""

  load_dashboard_context
  while IFS= read -r unit_name; do
    restart_service_if_present "${unit_name}"
  done < <(restart_service_units)
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
  local purge_packages=0
  local answer=""
  local unit_name=""
  local units=()

  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --purge)
        purge_packages=1
        ;;
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
    if [[ "${purge_packages}" -eq 1 ]]; then
      read -r -p "该操作会停止服务、删除脚本托管文件，并尝试卸载脚本安装的软件包。是否继续？ [y/N]: " answer
    else
      read -r -p "该操作会停止服务并删除脚本托管文件，但保留已安装的软件包。是否继续？ [y/N]: " answer
    fi
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
    "${WARP_RULES_FILE}" \
    "${HEALTH_STATE_FILE}" \
    "${HEALTH_HISTORY_FILE}" \
    "${XRAY_SERVICE_FILE}" \
    "${CORE_HEALTH_HELPER}" \
    "${CORE_HEALTH_SERVICE_FILE}" \
    "${CORE_HEALTH_TIMER_FILE}" \
    "${XRAY_LOGROTATE_FILE}" \
    "${HAPROXY_CONFIG}" \
    "${NGINX_CONFIG_FILE}" \
    "${SSL_DIR}" \
    "${WARP_APT_KEYRING}" \
    "${WARP_APT_SOURCE_LIST}" \
    "${WARP_MDM_FILE}" \
    "${WARP_HEALTH_HELPER}" \
    "${WARP_HEALTH_SERVICE_FILE}" \
    "${WARP_HEALTH_TIMER_FILE}" \
    "${NET_SYSCTL_CONF}" \
    "${NET_HELPER_PATH}" \
    "${NET_SERVICE_FILE}" \
    "${ACME_RELOAD_HELPER}" \
    "${ACME_HOME}" \
    "${OUTPUT_FILE}" \
    "/var/log/xray" \
    "/var/lib/xray" \
    "${OP_LOG_DIR}" \
    "/var/lib/cloudflare-warp"

  systemctl daemon-reload
  mapfile -t units < <(xray_managed_service_units)
  systemctl reset-failed "${units[@]}" >/dev/null 2>&1 || true
  sysctl --system >/dev/null 2>&1 || true

  if [[ "${purge_packages}" -eq 1 ]]; then
    log_step "卸载脚本安装的软件包。"
    purge_managed_packages
    log "已尝试卸载脚本安装的软件包。"
  fi

  log "脚本托管文件已删除。"
  log "备份目录：${BACKUP_DIR}"
  if [[ "${purge_packages}" -eq 1 ]]; then
    log "软件包卸载流程已结束。"
  else
    log "已安装的软件包已保留。"
  fi
}

show_main_menu() {
  cat <<'EOF'
  1. 安装或重装
  2. 查看节点链接
  3. 运行诊断
  4. 刷新状态面板
  5. 重启服务
  6. 更新脚本本身
  7. 升级 Xray 核心
  8. 轮换节点 UUID
  9. 修改 REALITY SNI
  10. 修改 XHTTP 路径
  11. 修改节点名前缀
  12. 开关 WARP 分流
  13. 修改 WARP 分流规则
  14. 修改证书模式 / CDN 域名
  15. 续期 / 刷新证书
  16. 抢修文件权限
  17. 卸载托管文件
  18. 完全卸载（含软件包）
  19. 查看原始服务详情
  20. 帮助
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
    update-script)
      update_script_cmd "$@"
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
    change-warp-rules)
      change_warp_rules_cmd "$@"
      ;;
    change-cert-mode)
      change_cert_mode_cmd "$@"
      ;;
    renew-cert)
      renew_cert_cmd "$@"
      ;;
    uninstall)
      uninstall_cmd "$@"
      ;;
    purge)
      uninstall_cmd --purge "$@"
      ;;
    show-links)
      show_links "$@"
      ;;
    diagnose)
      diagnose_cmd "$@"
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
    3) run_cli_command diagnose ;;
    4) run_cli_command status ;;
    5) run_cli_command restart ;;
    6) run_cli_command update-script ;;
    7) run_cli_command upgrade ;;
    8) run_cli_command change-uuid ;;
    9) run_cli_command change-sni ;;
    10) run_cli_command change-path ;;
    11) run_cli_command change-label-prefix ;;
    12) run_cli_command change-warp ;;
    13) run_cli_command change-warp-rules ;;
    14) run_cli_command change-cert-mode ;;
    15) run_cli_command renew-cert ;;
    16) run_cli_command repair-perms ;;
    17) run_cli_command uninstall ;;
    18) run_cli_command purge --yes ;;
    19) run_cli_command status --raw ;;
    20) run_cli_command help ;;
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
    IN_MAIN_MENU=1
    run_menu_choice "${choice}" || true
    IN_MAIN_MENU=0
    pause_after_menu_action
  done
}
