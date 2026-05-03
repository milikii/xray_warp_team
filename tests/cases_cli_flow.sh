run_missing_option_value_case() {
  local output=""

  if output="$(bash <<EOF 2>&1
set -Eeuo pipefail
ROOT_DIR="${ROOT_DIR}"
source <(sed '\$d' "${ROOT_DIR}/xtun.sh")
parse_install_args --server-ip
EOF
)"; then
    return 1
  fi
  printf '%s' "${output}" | grep -q '参数 --server-ip 需要值。'

  if output="$(bash <<EOF 2>&1
set -Eeuo pipefail
ROOT_DIR="${ROOT_DIR}"
source <(sed '\$d' "${ROOT_DIR}/xtun.sh")
change_uuid_cmd --reality-uuid
EOF
)"; then
    return 1
  fi
  printf '%s' "${output}" | grep -q '参数 --reality-uuid 需要值。'

  if output="$(bash <<EOF 2>&1
set -Eeuo pipefail
ROOT_DIR="${ROOT_DIR}"
source <(sed '\$d' "${ROOT_DIR}/xtun.sh")
change_warp_cmd --bogus
EOF
)"; then
    return 1
  fi
  printf '%s' "${output}" | grep -q '未知的 change-warp 参数：--bogus'

  if output="$(bash <<EOF 2>&1
set -Eeuo pipefail
ROOT_DIR="${ROOT_DIR}"
source <(sed '\$d' "${ROOT_DIR}/xtun.sh")
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
  update_script_cmd() {
    dispatched="update-script"
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

  run_cli_command update-script
  [[ "${dispatched}" == "update-script" ]]

  run_cli_command status --raw
  [[ "${dispatched}" == "status" ]]
  [[ "${dispatched_args}" == "--raw" ]]

  run_cli_command diagnose
  [[ "${dispatched}" == "diagnose" ]]

  run_cli_command
  [[ "${dispatched}" == "menu" ]]

  run_menu_choice 17
  [[ "${dispatched}" == "uninstall" ]]

  run_menu_choice 18
  [[ "${dispatched}" == "uninstall" ]]
  [[ "${dispatched_args}" == "--purge --yes" ]]

  run_menu_choice 19
  [[ "${dispatched}" == "status" ]]
  [[ "${dispatched_args}" == "--raw" ]]

  run_menu_choice 15
  [[ "${dispatched}" == "renew-cert" ]]

  run_menu_choice 13
  [[ "${dispatched}" == "change-warp-rules" ]]

  run_menu_choice 3
  [[ "${dispatched}" == "diagnose" ]]

  run_menu_choice 6
  [[ "${dispatched}" == "update-script" ]]
}

run_install_flow_case() {
  local steps=()
  local logged=""
  local shown=0
  local rolled_runtime=0
  local rolled_optional=0
  local rolled_install_runtime=0
  local draft_writes=0
  local draft_clears=0

  load_functions
  stub_side_effects

  prepare_install_command() {
    BACKUP_DIR="/tmp/install-backup"
    install_draft_session_begin
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
  rollback_managed_runtime_state() {
    rolled_runtime=$((rolled_runtime + 1))
  }
  rollback_install_runtime_state() {
    rolled_install_runtime=$((rolled_install_runtime + 1))
  }
  rollback_optional_component_state() {
    rolled_optional=$((rolled_optional + 1))
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
  write_install_draft_file() {
    draft_writes=$((draft_writes + 1))
  }
  clear_install_draft_file() {
    draft_clears=$((draft_clears + 1))
  }
  show_links() {
    shown=1
  }

  install_cmd --non-interactive --disable-warp

  [[ "${steps[*]}" == "prepare:--non-interactive --disable-warp runtime files optional finalize" ]]
  [[ "${shown}" -eq 1 ]]
  [[ "${draft_writes}" -eq 0 ]]
  [[ "${draft_clears}" -eq 1 ]]
  printf '%s' "${logged}" | grep -q 'STEP:准备安装参数与运行环境。'
  printf '%s' "${logged}" | grep -q 'STEP:校验并启动托管服务。'
  printf '%s' "${logged}" | grep -q '部署完成。'
  printf '%s' "${logged}" | grep -q '管理命令：'

  steps=()
  logged=""
  shown=0
  rolled_runtime=0
  rolled_optional=0
  rolled_install_runtime=0
  draft_writes=0
  draft_clears=0
  install_optional_components() {
    return 1
  }

  if install_cmd --non-interactive; then
    return 1
  fi
  [[ "${rolled_runtime}" -eq 1 ]]
  [[ "${rolled_optional}" -eq 1 ]]
  [[ "${rolled_install_runtime}" -eq 1 ]]
  [[ "${draft_writes}" -eq 1 ]]
  [[ "${draft_clears}" -eq 0 ]]
}

run_logging_case() {
  local workdir=""
  local output=""

  load_functions
  stub_side_effects

  workdir="$(mktemp -d)"
  OP_LOG_DIR="${workdir}/logs"
  OP_LOG_FILE="${OP_LOG_DIR}/operations.log"
  SESSION_LOG_FILE="${workdir}/session.log"

  output="$(log "日志测试")"
  [[ "${output}" == *"[信息] 日志测试"* ]]
  grep -q '日志测试' "${OP_LOG_FILE}"
  grep -q '日志测试' "${SESSION_LOG_FILE}"
}
