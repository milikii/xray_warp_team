# shellcheck shell=bash

# ------------------------------
# WARP 安装层
# 负责 Cloudflare WARP 客户端与 MDM 配置
# ------------------------------

xml_escape() {
  printf '%s' "${1}" \
    | sed \
      -e 's/&/\&amp;/g' \
      -e 's/</\&lt;/g' \
      -e 's/>/\&gt;/g' \
      -e 's/"/\&quot;/g' \
      -e "s/'/\&apos;/g"
}

write_warp_mdm_file() {
  local escaped_client_id=""
  local escaped_client_secret=""
  local escaped_team_name=""
  local tmp_file=""

  ensure_warp_proxy_port_format
  mkdir -p /var/lib/cloudflare-warp
  backup_path "${WARP_MDM_FILE}"
  escaped_client_id="$(xml_escape "${WARP_CLIENT_ID}")"
  escaped_client_secret="$(xml_escape "${WARP_CLIENT_SECRET}")"
  escaped_team_name="$(xml_escape "${WARP_TEAM_NAME}")"
  tmp_file="$(mktemp "$(dirname "${WARP_MDM_FILE}")/.mdm.xml.tmp.XXXXXX")"
  cat > "${tmp_file}" <<EOF
<dict>
    <key>auth_client_id</key>
    <string>${escaped_client_id}</string>
    <key>auth_client_secret</key>
    <string>${escaped_client_secret}</string>
    <key>organization</key>
    <string>${escaped_team_name}</string>
    <key>auto_connect</key>
    <integer>1</integer>
    <key>onboarding</key>
    <false/>
    <key>service_mode</key>
    <string>proxy</string>
    <key>proxy_port</key>
    <integer>${WARP_PROXY_PORT}</integer>
    <key>warp_tunnel_protocol</key>
    <string>masque</string>
</dict>
EOF

  chmod 0600 "${tmp_file}"
  mv -f "${tmp_file}" "${WARP_MDM_FILE}"
}

install_warp_apt_repo() {
  local repo_codename="${1}"
  local key_tmp=""
  local keyring_tmp=""
  local source_tmp=""

  key_tmp="$(mktemp)"
  keyring_tmp="$(mktemp "$(dirname "${WARP_APT_KEYRING}")/.cloudflare-warp-archive-keyring.gpg.tmp.XXXXXX")"
  source_tmp="$(mktemp "$(dirname "${WARP_APT_SOURCE_LIST}")/.cloudflare-client.list.tmp.XXXXXX")"
  backup_path "${WARP_APT_KEYRING}"
  backup_path "${WARP_APT_SOURCE_LIST}"
  curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg -o "${key_tmp}"
  gpg --yes --dearmor --output "${keyring_tmp}" "${key_tmp}"
  rm -f "${key_tmp}"

  cat > "${source_tmp}" <<EOF
deb [signed-by=${WARP_APT_KEYRING}] https://pkg.cloudflareclient.com/ ${repo_codename} main
EOF
  mv -f "${keyring_tmp}" "${WARP_APT_KEYRING}"
  mv -f "${source_tmp}" "${WARP_APT_SOURCE_LIST}"

  apt-get update
  apt-get install -y cloudflare-warp
}

write_warp_health_helper() {
  local tmp_file=""

  tmp_file="$(mktemp)"
  cat > "${tmp_file}" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

proxy_port='${WARP_PROXY_PORT}'
health_state_file='${HEALTH_STATE_FILE}'
health_history_file='${HEALTH_HISTORY_FILE}'

write_health_state() {
  local action="\${1}"
  local reason="\${2}"
  local tmp_file=""

  mkdir -p "\$(dirname "\${health_state_file}")"
  tmp_file="\$(mktemp "\$(dirname "\${health_state_file}")/.health-state.tmp.XXXXXX")"
  if [[ -f "\${health_state_file}" ]]; then
    grep -v '^WARP_HEALTH_' "\${health_state_file}" > "\${tmp_file}" 2>/dev/null || true
  fi
  {
    printf 'WARP_HEALTH_LAST_CHECK_AT=%q\n' "\$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'WARP_HEALTH_LAST_ACTION=%q\n' "\${action}"
    printf 'WARP_HEALTH_LAST_REASON=%q\n' "\${reason}"
  } >> "\${tmp_file}"
  mv -f "\${tmp_file}" "\${health_state_file}"
  chmod 0640 "\${health_state_file}" 2>/dev/null || true
}

append_health_history() {
  local action="\${1}"
  local reason="\${2}"
  local tmp_file=""

  mkdir -p "\$(dirname "\${health_history_file}")"
  tmp_file="\$(mktemp "\$(dirname "\${health_history_file}")/.health-history.tmp.XXXXXX")"
  if [[ -f "\${health_history_file}" ]]; then
    tail -n 49 "\${health_history_file}" > "\${tmp_file}" 2>/dev/null || true
  fi
  printf '%s | warp | %s | %s\n' "\$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "\${action}" "\${reason}" >> "\${tmp_file}"
  mv -f "\${tmp_file}" "\${health_history_file}"
  chmod 0640 "\${health_history_file}" 2>/dev/null || true
}

if ! systemctl is-active --quiet warp-svc; then
  systemctl restart warp-svc >/dev/null 2>&1 || true
  sleep 3
fi

if command -v curl >/dev/null 2>&1; then
  if ! curl --socks5-hostname "127.0.0.1:\${proxy_port}" -fsSL --max-time 8 https://api.ipify.org >/dev/null 2>&1; then
    warp-cli --accept-tos mdm refresh >/dev/null 2>&1 || true
    systemctl restart warp-svc >/dev/null 2>&1 || true
    write_health_state "restarted" "warp socks5 probe failed"
    append_health_history "restarted" "warp socks5 probe failed"
    exit 0
  fi
fi

write_health_state "ok" "warp socks5 probe passed"
append_health_history "ok" "warp socks5 probe passed"
EOF

  backup_path "${WARP_HEALTH_HELPER}"
  install -m 0755 "${tmp_file}" "${WARP_HEALTH_HELPER}"
  rm -f "${tmp_file}"
}

write_warp_health_service() {
  local tmp_file=""

  tmp_file="$(mktemp)"
  cat > "${tmp_file}" <<EOF
[Unit]
Description=Check and recover Cloudflare WARP proxy health
After=network-online.target warp-svc.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${WARP_HEALTH_HELPER}
EOF

  backup_path "${WARP_HEALTH_SERVICE_FILE}"
  install -m 0644 "${tmp_file}" "${WARP_HEALTH_SERVICE_FILE}"
  rm -f "${tmp_file}"
}

write_warp_health_timer() {
  local tmp_file=""

  tmp_file="$(mktemp)"
  cat > "${tmp_file}" <<EOF
[Unit]
Description=Run Cloudflare WARP health recovery periodically

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Unit=${WARP_HEALTH_SERVICE_NAME}

[Install]
WantedBy=timers.target
EOF

  backup_path "${WARP_HEALTH_TIMER_FILE}"
  install -m 0644 "${tmp_file}" "${WARP_HEALTH_TIMER_FILE}"
  rm -f "${tmp_file}"
}

install_warp_health_monitor() {
  write_warp_health_helper
  write_warp_health_service
  write_warp_health_timer
  systemctl daemon-reload
  systemctl enable --now "${WARP_HEALTH_TIMER_NAME}"
}

install_warp() {
  local repo_codename=""

  [[ "${ENABLE_WARP}" == "yes" ]] || return 0

  # shellcheck disable=SC1091
  . /etc/os-release
  repo_codename="${VERSION_CODENAME:-}"
  [[ -n "${repo_codename}" ]] || die "VERSION_CODENAME 为空，无法安装 Cloudflare WARP。"

  log "正在安装 Cloudflare WARP 客户端。"
  install_warp_apt_repo "${repo_codename}"
  write_warp_mdm_file
  install_warp_health_monitor
  systemctl enable --now warp-svc
  warp-cli --accept-tos mdm refresh || true
  systemctl restart warp-svc
}
