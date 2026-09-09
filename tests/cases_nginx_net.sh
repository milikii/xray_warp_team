# shellcheck shell=bash

run_nginx_main_config_case() {
  local workdir=""
  local main_conf=""
  local conf_d=""

  workdir="$(mktemp -d)"
  main_conf="${workdir}/nginx.conf"
  conf_d="${workdir}/conf.d"
  NGINX_MAIN_CONFIG="${main_conf}"
  NGINX_CONF_DIR="${conf_d}"
  NGINX_CONFIG_FILE="${conf_d}/xtun.conf"
  mkdir -p "${conf_d}"
  reset_feature_defaults
  XHTTP_DOMAIN="cdn.example.com"
  XHTTP_PATH="/assets/v3"
  XHTTP_LOCAL_PORT="8001"
  NGINX_TLS_PORT="8443"
  TLS_CERT_FILE="/etc/ssl/xtun/cert.pem"
  TLS_KEY_FILE="/etc/ssl/xtun/key.pem"
  SUB_WEB_ROOT="/var/www/xtun-sub"
  nginx_version_at_least() { return 0; }

  # 未接管时不写主配置
  NGINX_MAIN_MANAGED="no"
  write_nginx_main_config
  [[ ! -e "${main_conf}" ]]

  # 接管：模板含 rlimit / worker_connections / 两个用户块
  NGINX_MAIN_MANAGED="yes"
  write_nginx_main_config

  assert_contains 'worker_rlimit_nofile 1048576;' "${main_conf}"
  assert_contains 'worker_connections 65535;' "${main_conf}"
  assert_contains 'worker_cpu_affinity auto;' "${main_conf}"
  assert_contains 'xtun-user:nginx-main' "${main_conf}"
  assert_contains 'xtun-user:nginx-http' "${main_conf}"
  # 用户块位置：nginx-main 在 events 之后、http 之前；nginx-http 在 http 内末尾
  [[ "$(awk '/xtun-user:nginx-main >>>/ { print NR; exit }' "${main_conf}")" -lt \
     "$(awk '/^http \{/ { print NR; exit }' "${main_conf}")" ]]
  [[ "$(awk '/xtun-user:nginx-http >>>/ { print NR; exit }' "${main_conf}")" -gt \
     "$(awk '/sites-enabled/ { print NR; exit }' "${main_conf}")" ]]

  # 用户块内容跨重写保留
  sed -i '/>>> xtun-user:nginx-main >>>/a\worker_priority -5;' "${main_conf}"
  sed -i '/>>> xtun-user:nginx-http >>>/a\    map $http_upgrade $connection_upgrade { default upgrade; }' "${main_conf}"
  write_nginx_main_config
  assert_contains 'worker_priority -5;' "${main_conf}"
  assert_contains 'connection_upgrade' "${main_conf}"
  # 不重复复制
  [[ "$(grep -c 'worker_priority -5;' "${main_conf}")" -eq 1 ]]

  rm -rf "${workdir}"
  load_functions
}

run_nginx_http2_compat_case() {
  local workdir=""

  workdir="$(mktemp -d)"
  NGINX_CONF_DIR="${workdir}/conf.d"
  NGINX_CONFIG_FILE="${NGINX_CONF_DIR}/xtun.conf"
  mkdir -p "${NGINX_CONF_DIR}"
  reset_feature_defaults
  XHTTP_DOMAIN="cdn.example.com"
  XHTTP_PATH="/assets/v3"
  XHTTP_LOCAL_PORT="8001"
  NGINX_TLS_PORT="8443"
  TLS_CERT_FILE="/etc/ssl/xtun/cert.pem"
  TLS_KEY_FILE="/etc/ssl/xtun/key.pem"
  SUB_WEB_ROOT="/var/www/xtun-sub"

  # >= 1.25.1：独立 http2 on;
  nginx_version_at_least() { return 0; }
  write_nginx_config
  assert_contains 'http2 on;' "${NGINX_CONFIG_FILE}"
  assert_absent 'listen 127.0.0.1:8443 ssl http2;' "${NGINX_CONFIG_FILE}"

  # < 1.25.1（Ubuntu 24.04 的 1.24）：listen 行老语法
  nginx_version_at_least() { return 1; }
  write_nginx_config
  assert_contains 'listen 127.0.0.1:8443 ssl http2;' "${NGINX_CONFIG_FILE}"
  assert_absent 'http2 on;' "${NGINX_CONFIG_FILE}"

  rm -rf "${workdir}"
  load_functions
}

# §7.4 diagnose --net。读取函数全部覆盖成固定值，断言输出行与失败判定。
run_diagnose_net_case() {
  net_kernel_version() { printf '7.0.3-joeyblog-bbrv3'; }
  net_current_cc() { printf 'bbr1'; }
  available_cc() { printf 'reno cubic bbr bbr1'; }
  net_tcp_bbr_version() { printf '3'; }
  net_default_qdisc() { printf 'fq'; }
  net_default_nic() { printf 'eth0'; }
  net_nic_qdisc_line() { printf 'fq limit 100000p flow_limit 1000p'; }
  net_nic_mtu() { printf '1500'; }
  net_sysctl_value() {
    case "${1}" in
      net.ipv4.tcp_notsent_lowat) printf '131072' ;;
      fs.file-max) printf '2097152' ;;
      *) printf '' ;;
    esac
  }
  net_nginx_worker_rlimit_text() { printf '65535 / 1048576'; }
  net_nginx_master_limitnofile() { printf '1048576'; }
  net_haproxy_maxconn() { printf '20000'; }
  net_cc_distribution() { printf 'bbr1=37 cubic=0'; }

  local output=""
  output="$(net_stack_text)"
  printf '%s\n' "${output}" | grep -q '内核:            7.0.3-joeyblog-bbrv3'
  printf '%s\n' "${output}" | grep -q '拥塞控制:        bbr1'
  printf '%s\n' "${output}" | grep -q 'tcp_bbr 模块:    version 3'
  printf '%s\n' "${output}" | grep -q '默认 qdisc:      fq'
  printf '%s\n' "${output}" | grep -q '出网网卡 qdisc:  fq limit 100000p'
  printf '%s\n' "${output}" | grep -q 'MTU:             1500'
  printf '%s\n' "${output}" | grep -q 'tcp_notsent_lowat: 131072'
  printf '%s\n' "${output}" | grep -q 'fs.file-max:     2097152'
  printf '%s\n' "${output}" | grep -q 'nginx worker_connections / worker_rlimit_nofile:  65535 / 1048576'
  printf '%s\n' "${output}" | grep -q 'nginx master LimitNOFILE:  1048576'
  printf '%s\n' "${output}" | grep -q 'haproxy maxconn: 20000'
  printf '%s\n' "${output}" | grep -q '已建立连接拥塞算法分布:  bbr1=37 cubic=0'

  [[ "$(net_stack_state)" == "ok" ]]

  # 非 bbr 系 → fail（diagnose 里计入失败）
  net_current_cc() { printf 'cubic'; }
  [[ "$(net_stack_state)" == "fail" ]]

  load_functions
}

# §7.3 BBR 内核开关
run_bbr_kernel_switch_case() {
  local output=""
  local workdir=""
  local joey_called=0

  [[ "$(normalize_net_bbr_kernel_value 'y')" == "joey" ]]
  [[ "$(normalize_net_bbr_kernel_value 'none')" == "none" ]]

  local output=""
  if output="$(bash <<EOF 2>&1
set -Eeuo pipefail
ROOT_DIR="${ROOT_DIR}"
source <(sed '\$d' "${ROOT_DIR}/xtun.sh")
normalize_net_bbr_kernel_value maybe
EOF
)"; then
    return 1
  fi
  printf '%s' "${output}" | grep -q '只能是 joey 或 none'

  # install_network_optimization 在 NET_BBR_KERNEL=none 时跳过内核安装
  ENABLE_NET_OPT="yes"
  NET_BBR_KERNEL="none"
  install_joey_bbrv3_kernel_if_needed() {
    joey_called=$((joey_called + 1))
  }
  available_cc() { printf 'reno cubic bbr1'; }
  supports_default_qdisc() { return 0; }
  bbr_v3_active() { return 1; }
  modprobe() { :; }
  workdir="$(mktemp -d)"
  NET_SYSCTL_CONF="${workdir}/net.conf"
  NET_HELPER_PATH="${workdir}/helper.sh"
  NET_SERVICE_FILE="${workdir}/svc.service"
  backup_path() { :; }
  systemctl() { :; }
  sysctl() { return 0; }
  log_success() { :; }

  install_network_optimization

  [[ "${joey_called}" -eq 0 ]]
  [[ -x "${NET_HELPER_PATH}" ]]
  [[ -f "${NET_SERVICE_FILE}" ]]
  rm -rf "${workdir}"
  load_functions
}
