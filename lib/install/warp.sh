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

  ensure_warp_proxy_port_format
  mkdir -p /var/lib/cloudflare-warp
  backup_path "${WARP_MDM_FILE}"
  escaped_client_id="$(xml_escape "${WARP_CLIENT_ID}")"
  escaped_client_secret="$(xml_escape "${WARP_CLIENT_SECRET}")"
  escaped_team_name="$(xml_escape "${WARP_TEAM_NAME}")"
  cat > "${WARP_MDM_FILE}" <<EOF
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

  chmod 0600 "${WARP_MDM_FILE}"
}

install_warp_apt_repo() {
  local repo_codename="${1}"
  local key_tmp=""

  key_tmp="$(mktemp)"
  curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg -o "${key_tmp}"
  gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg "${key_tmp}"
  rm -f "${key_tmp}"

  cat > /etc/apt/sources.list.d/cloudflare-client.list <<EOF
deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ ${repo_codename} main
EOF

  apt-get update
  apt-get install -y cloudflare-warp
}

install_warp() {
  local repo_codename=""

  [[ "${ENABLE_WARP}" == "yes" ]] || return

  # shellcheck disable=SC1091
  . /etc/os-release
  repo_codename="${VERSION_CODENAME:-}"
  [[ -n "${repo_codename}" ]] || die "VERSION_CODENAME 为空，无法安装 Cloudflare WARP。"

  log "正在安装 Cloudflare WARP 客户端。"
  install_warp_apt_repo "${repo_codename}"
  write_warp_mdm_file
  systemctl enable --now warp-svc
  warp-cli --accept-tos mdm refresh || true
  systemctl restart warp-svc
}
