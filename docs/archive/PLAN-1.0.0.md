# xtun 瘦身与推进方案（0.11.14 → 1.0.0）

> 本文是交给实施者（人或 AI）的施工图。它假定读者没有看过本仓库任何一行代码，
> 所以每一处改动都点到文件、函数、变量名；每个阶段都有可机械核对的验收标准。
> 文中「必须 / 不得 / 一律」是硬约束；「建议」可由实施者裁量。
>
> 基线：`main` 分支 `b6eb98b`，`SCRIPT_VERSION="0.11.14"`。
> 工作区另有 4 个文件未提交（见 §3 阶段 0）。

---

## 0. 目标与非目标

### 0.1 面向谁

xtun 只服务一个人、一台或几台自建 VPS。不再面向「机场」、多租户、多客户端分发。
一切为「多人共用一台节点」设计的东西全部剔除。

### 0.2 最终形态（1.0.0）

同一台 Debian / Ubuntu VPS，`443` 端口，导出以下节点（默认 5 条，IPv6 / H3 阶段各追加 2 条）：

| # | 节点 | 用途 |
| --- | --- | --- |
| 1 | VLESS + REALITY + Vision（直连） | 主力直连 |
| 2 | VLESS + XHTTP + REALITY（上下行不分离） | 直连备用 |
| 3 | VLESS + XHTTP + TLS + CDN | 日常用，走 Cloudflare |
| 4 | 上行 XHTTP + TLS + CDN ｜ 下行 XHTTP + REALITY | 上下行分离，备用 |
| 5 | 上行 XHTTP + REALITY ｜ 下行 XHTTP + TLS + CDN | 反向分离，备用 |

Reality 的目标域名是用户指定的第三方权威站点（不是自己的域名），因此安装前必须
对它做一次合规探测（§5.1–5.6）；鉴权失败的回落流量按 Xray 官方模板经本机 dokodemo-door
过滤 SNI 后再放行，防止服务器被扫描者当成到目标站的端口转发（§5.7）。

服务器侧：BBR（发行版内核 bbr 或 Joey BBRv3 内核，二选一）、fq、sysctl 全套、
RPS/XPS、MTU 夹紧、nginx 主配置接管（worker_connections / rlimit）、fd 限额、
服务崩溃自动重启（systemd 原生，不再自带巡检 timer）。

客户端侧：VLESS 分享链接、mihomo 节点 yaml、经 CDN 域名 HTTPS 分发的订阅地址、
终端二维码。

### 0.3 明确不做

- 不支持 Debian / Ubuntu 之外的发行版；不支持 openrc。
- 不做 Hysteria2、不做上下行不同 CDN 域名（双 CDN）。
- 不做 sing-box 输出（sing-box 不支持 XHTTP 传输，输出一半没意义）。
- 不做 Reality「自偷」（目标指向本机 nginx）。用户要的是权威第三方域名。
- 不替换 haproxy（见 §1.3 决策 D）。

---

## 1. 决策清单（已定，实施时不要再议）

### 1.1 删除

| 功能 | 现状 | 决策 | 理由 |
| --- | --- | --- | --- |
| 多客户端（`add-client` / `list-clients` / `show-links --client` / `NODE_CLIENTS_TEXT`） | `lib/state.sh:433-584`、`lib/cli/core.sh:23-217`、`lib/ui/output.sh:44-96` | **删** | 单人使用，只有 `default` 一个客户端 |
| 核心巡检 timer（`xtun-core-health.*`、`health-state.env`、`health-history.log`、稳定性信号） | `lib/base/runtime.sh:66-192`、`lib/ui/health.sh` 全文 | **删**，改用 systemd `Restart=` drop-in | 3 分钟轮询 + 历史统计对个人节点是负担；xray 已有 `Restart=always`，haproxy 发行版单元也是 `Restart=always`，只有 nginx 缺（实测 `systemctl show nginx -p Restart` = `no`） |
| `change-label-prefix` 命令（含 `begin_managed_output_change`、`run_single_value_change_cmd` 的 `output` 模式） | `lib/change/commands.sh:105-116`、`lib/change/workflow.sh:83-91` | **删** | 前缀在安装时定一次即可；要改就 `install` 重装或改状态文件后 `apply-config` |
| 证书模式 `cf-origin-ca` | `lib/install/certs.sh:15-52`、`normalize_cert_mode` | **合并进 `existing`** | 代码路径完全相同（都走 `write_existing_tls_assets`），只是多一个菜单项和一套死变量 |
| 死状态键 `CF_ZONE_ID` / `CF_API_TOKEN` / `CF_CERT_VALIDITY` 及 `--cf-zone-id` / `--cf-api-token` / `--cf-cert-validity` | 全仓库只被清空、从未被消费 | **删** | 没有 Origin CA API 签发流程，这些是半成品残骸 |
| WARP Team 旧版迁移代码（`warp_teardown_legacy`、`legacy_warp_paths`、`warp_legacy_team_detected`、uninstall 里的 `cloudflare-warp` 清理） | `lib/install/warp.sh:190-241` | **删**，路径并入统一的 `legacy_managed_paths`（§4.6） | 迁移期已过 |
| WARP 规则交互编辑器（`prompt_warp_rules_editor`、`warp_rules_editor_*`、`show_warp_rules_list`） | `lib/install/input.sh:247-393` | **删** | 菜单项改为打印当前规则 + 提示 CLI 用法 |
| `/root/xtun-subscriptions/` 目录、订阅二维码 PNG | `lib/ui/output.sh:442-502` | **删**，订阅改为 nginx 托管（§6.2） | 本地文件订阅没人拉得到；PNG 二维码被终端二维码覆盖 |
| `purge` 顶层命令别名 | `lib/cli/core.sh:740-742` | **删**，保留 `uninstall --purge` | 少一个入口 |
| `status --raw` 菜单项、`help` 菜单项 | 菜单 19、20 | **删**（CLI 保留） | 菜单只留日常动作 |

### 1.2 保留（并瘦身）

| 功能 | 决策 | 说明 |
| --- | --- | --- |
| WARP 选择性出站（Xray 原生 wireguard） | **保留** | 本机状态 `ENABLE_WARP=yes`，AI 站点出口是真实个人需求。只删旧版迁移和交互编辑器 |
| ECH、xpadding、VLESS Encryption 开关 | **保留** | 都是 CDN 节点的抗探测手段，代码量小 |
| 证书模式 `self-signed` / `existing` / `acme-dns-cf` | **保留** | `existing` 同时接受文件路径和 PEM 粘贴（原 cf-origin-ca 的输入方式） |
| 安装草稿（`/root/.xtun-install-draft.env`） | **保留** | 交互安装中断续填 |
| 脚本锁、备份会话、回滚、操作日志、用户自定义块（`xtun-user:*`） | **保留** | 这是 xtun 相对同类项目的核心价值 |
| bootstrap 单文件拉取、`update-script`、`upgrade`、`repair-perms`、`apply-config`、`apply-net-opt` | **保留** | |
| Joey BBRv3 内核安装 | **保留，但拆成独立开关** | 见 §7.3 |

### 1.3 关键设计决策

- **A. Reality 目标域名预检是硬门禁。** 安装与 `change-sni` 都跑 `check-sni`；有 FAIL 项时非交互直接失败，交互模式给「重填 / 忽略 / 退出」三选一。可用 `--skip-sni-check` 跳过，但必须在输出里留下警告。
- **A2. Reality 防跑流量按官方 dokodemo-door 模式无条件开启。** Reality 入站的 `target` 不再直连远端站点，而是指向本机 `dokodemo-door` 入站；由路由只放行 SNI 等于 `REALITY_SNI` 的回落流量，其余 blackhole。不启用 `limitFallbackUpload/Download`（官方文档明言限速是特征，一键脚本若用必须随机化；有了 SNI 过滤，剩余风险只剩「借你转发到目标站本身」，靠 `check-sni` 第 9 项劝阻 CDN 目标即可）。详见 §5.7。
- **B. 路由卫生不可配置地开启。** `geoip:private` + `geosite:private` 一律 blackhole；`geoip:cn` + `geosite:cn` 由 `--block-cn` 控制，默认关。
- **C. 订阅走 nginx 托管，路径 `/sub/<32 位 hex token>/`。** 通过 CDN 域名 HTTPS 访问，`Cache-Control: no-store`。
- **D. 保留 haproxy 做 SNI 分流。** Reality 目标是远端第三方站点，xray 的 reality 入站收到 SNI=CDN 域名的流量会转给远端目标而不是本机 nginx，所以必须有前置 SNI 分流。haproxy 已有 reload、splice、用户块与测试，换 nginx stream 模块收益不抵风险。
- **E. xtun 接管 `/etc/nginx/nginx.conf`。** `worker_connections`、`worker_rlimit_nofile` 只能写在主配置里；README 早已声明「已有复杂 nginx 站点的机器不适合」。接管受状态键 `NGINX_MAIN_MANAGED` 控制，升级上来的旧节点默认不接管，直到用户显式打开。
- **F. 状态文件升到 `STATE_VERSION=2`。** 旧键只读不写，加载时给迁移提示。
- **G. 版本节奏。** 阶段 1–3 合并发 `0.12.0`；阶段 4 发 `0.13.0`；阶段 5、6 可选，各发一个小版本；阶段 7 发 `1.0.0`。每个阶段独立可合并、独立全绿。

---

## 2. 实施者必读：仓库约定与陷阱

读完这一节再动手。这些都是仓库里已经踩过并写进注释和测试的坑。

### 2.1 目录与加载顺序

```
xtun.sh                      入口：bootstrap、全局默认值、按顺序 source lib/
lib/base/helpers.sh          日志、die、锁；再 source base/input.sh、base/env.sh
lib/install.sh               安装副作用；末尾 source install/{input,self,certs,network,warp}.sh
lib/generators.sh            所有托管文件的文本生成器（xray json / haproxy / nginx / 用户块）
lib/state.sh                 状态文件读写、config.json 回填
lib/base/runtime.sh          systemd 单元、校验、重启、回滚编排
lib/ui.sh → ui/{core,health,output}.sh   面板、探测、链接与输出文件
lib/commands.sh → change.sh + cli.sh     命令层
tests/smoke.sh               唯一测试入口；用例函数按 tests/cases_*.sh 分文件
static/fallback/             nginx 伪装站静态文件
```

`xtun.sh` 顶部的全局变量是「所有键的总表」，新增状态键要同时改：`xtun.sh` 默认值、
`lib/state.sh` 的 `state_file_key_allowed` / `reset_loaded_runtime_context` /
`state_file_text`、`lib/install.sh` 的 `install_draft_file_text`（若需要续填）、
`tests/common.sh` 的 `sandbox_managed_paths`（若是路径）。少一处，
`run_dead_global_lint_case` 或 `run_state_context_case` 会红。

### 2.2 errexit 在命令层是失效的

`run_cli_command` 里 `dispatch_cli_command ... || status=$?` 和菜单里的 `|| true`
把整条动态调用链的 `set -e` 关掉了（`lib/cli/core.sh:672-684` 有完整说明）。因此：

- 每一步可能失败的调用都要显式 `|| return 1`。测试 `run_errexit_guard_lint_case`
  会扫描指定函数，漏写就红。
- `die` 是 `exit`。在 `$( )` 里调用的函数若可能 `die`，赋值语句后必须接 `|| exit 1`
  （见 `lib/install/input.sh:8-18`）。不要写成 `local x="$(...)"`（SC2155 会吞退出码）。
- 不要在函数里挂 `trap ... RETURN`（`lib/install/certs.sh:374-382` 记录了为什么）。
- 管道下游提前退出会让上游吃 SIGPIPE，`pipefail` 把 141 抬成整条管道失败
  （`lib/install/network.sh:16-32`）。读 `/proc/sys` 直接 `cat`，不要 `sysctl -a | grep`。

### 2.3 测试怎么跑、怎么写

```bash
bash tests/smoke.sh            # 全部用例；需要宿主机有 /usr/local/bin/xray、jq、openssl
shellcheck xtun.sh $(find lib tests -type f -name '*.sh' | sort)   # 必须零发现
```

- 所有托管路径在 `tests/common.sh::sandbox_managed_paths` 里被改写到临时沙箱；
  新增任何落盘路径变量都要加进去，否则用例会写到真机。`tests/smoke.sh` 末尾的
  `REAL_MANAGED_CANARY` 会在真实文件消失时让整套测试失败。
- 单跑一个用例：`bash -c '. tests/common.sh; . tests/cases_xxx.sh; load_functions; stub_side_effects; run_xxx_case'`。
  不先 `load_functions` 会「静默通过」。
- 用例里的反向断言用 `assert_false` / `assert_absent`，不要写 `! cmd`（SC2251）。
- 网络探测类函数（本方案新增的 `sni_probe_*`）在用例里用同名函数覆盖成返回固定文本，
  解析与判定函数必须是纯函数，只吃字符串、只吐字符串。
- CI（`.github/workflows/ci.yml`）钉死 Xray `v26.3.27` 并校验 sha256；升级要一起改两行。

### 2.4 提交约定

- 一个阶段可以拆多个提交，但每个提交 `shellcheck` 零发现、`smoke ok`。
- 提交信息沿用仓库风格：中文、`fix:` / `feat:` / `refactor:` / `docs:` / `test:` 前缀、
  一句话说清「什么坏了 / 什么变了」。
- 不要在这台生产节点上跑 `install` / `uninstall` / `apply-config` 来「试一下」；
  只跑 `tests/smoke.sh` 和只读命令（`status` / `diagnose` / `check-sni`）。
  升级生产节点走附录 D 的步骤，由用户执行。

---

## 3. 阶段 0：收口现有工作区

工作区已有一组完成度很高的未提交改动（`git diff --stat`：4 个文件，+210/−27）：

- `lib/base/input.sh`：新增 `sanitize_indirect_value`，在 `resolve_value_source` /
  `prompt_secret` / `prompt_multiline_value` 里剥掉 `\r` 和首尾空白；`prompt_multiline_value`
  的结束标记比对前先去 `\r`。
- `lib/install/input.sh`：`verify_cloudflare_token` 改为不带 `-f`、单独取 http_code，
  新增 `cloudflare_error_message`。
- `tests/cases_cli_core.sh`、`tests/smoke.sh`：对应用例。

动作：

1. `bash tests/smoke.sh` 与 shellcheck 全绿。
2. 单独提交，信息建议：`fix: 间接来源的密钥值剥掉 \r 与首尾空白；Cloudflare 令牌预检不再把 401 当成网络不通`。

不要把阶段 0 的改动混进后面的瘦身提交。

---

## 4. 阶段 1：瘦身（0.12.0 第一部分）

目标：删掉 §1.1 列出的全部功能，状态文件升到 v2，行为对单客户端节点零变化。

### 4.1 `xtun.sh`

- `SCRIPT_VERSION="0.12.0"`；`STATE_VERSION_CURRENT="2"`。
- 删除全局：`DEFAULT_CF_CERT_VALIDITY`、`CF_ZONE_ID`、`CF_API_TOKEN`、`CF_CERT_VALIDITY`、
  `NODE_CLIENTS_TEXT`、`OUTPUT_CLIENT_NAME`、`LINK_CLIENT_NAME`、`LINK_REALITY_UUID`、
  `LINK_XHTTP_UUID`、`HEALTH_STATE_FILE`、`HEALTH_HISTORY_FILE`、`CORE_HEALTH_HELPER`、
  `CORE_HEALTH_SERVICE_NAME/FILE`、`CORE_HEALTH_TIMER_NAME/FILE`、
  `SUBSCRIPTION_DIR_DEFAULT`、`SUBSCRIPTION_DIR`、`SUBSCRIPTION_RAW_FILE`、
  `SUBSCRIPTION_BASE64_FILE`、`SUBSCRIPTION_MANIFEST_FILE`、`SUBSCRIPTION_QR_DIR`、
  `SUBSCRIPTION_RAW_QR_FILE`、`SUBSCRIPTION_BASE64_QR_FILE`。
- 新增全局（本阶段先占位，后续阶段使用）：`REALITY_FALLBACK_PORT="2444"`（阶段 2）、
  `SUB_WEB_ROOT="/var/www/xtun-sub"`、`SUB_TOKEN=""`、`ROUTE_BLOCK_CN="no"`（阶段 3）、
  `NGINX_MAIN_MANAGED=""`、`NET_BBR_KERNEL=""`（阶段 4）。
- `bundle_root_ready` 不变。

### 4.2 `lib/state.sh`

- `state_file_key_allowed`：
  - 删除写入键：`CF_ZONE_ID|CF_API_TOKEN|CF_CERT_VALIDITY|NODE_CLIENTS_TEXT|CORE_HEALTH_LAST_CHECK_AT|CORE_HEALTH_LAST_ACTION|CORE_HEALTH_LAST_REASON`。
  - 新增函数 `state_file_legacy_key()`：只认 `NODE_CLIENTS_TEXT`；`load_shell_kv_file` 对 legacy 键照常赋值（用于迁移提示），`state_file_text` 永不写出。
  - 新增键：`SUB_TOKEN`、`ROUTE_BLOCK_CN`、`NGINX_MAIN_MANAGED`、`NET_BBR_KERNEL`。
- `load_existing_state`：在版本比对之后加 `migrate_state_v1_to_v2`：
  - `CERT_MODE=cf-origin-ca` → `existing`，`log` 一行说明。
  - `NODE_CLIENTS_TEXT` 非空 → `warn "多客户端功能已移除；以下客户端将在下一次 apply-config 时从 config.json 中移除：a, b"`，随后置空。
  - 不再加载 `HEALTH_STATE_FILE`。
- 删除函数：`default_node_client_name`、`ensure_node_client_name_format`、
  `ensure_new_node_client_name_format`、`node_client_record_line`、`node_extra_clients_text`、
  `node_clients_text`、`node_client_record_for_name`、`node_client_exists`、`node_client_count`、
  `node_client_names_text`、`node_client_names_csv`、`append_node_client_record`。
- 保留并改名：`ensure_node_client_uuid_format` → `ensure_uuid_format LABEL UUID`
  （`change-uuid --reality-uuid/--xhttp-uuid` 仍需校验）。
- `reset_loaded_runtime_context`、`state_file_text`、`load_output_runtime_context` 同步删键。
- `normalize_runtime_defaults`：`CERT_MODE="${CERT_MODE:-existing}"` 不变；补
  `ROUTE_BLOCK_CN="${ROUTE_BLOCK_CN:-no}"`、`NGINX_MAIN_MANAGED="${NGINX_MAIN_MANAGED:-no}"`
  （旧节点默认不接管）、`NET_BBR_KERNEL="${NET_BBR_KERNEL:-joey}"`（旧节点保持现状）。

### 4.3 `lib/generators.sh`

- `xray_clients_json` 改为不读客户端表：

```bash
xray_reality_clients_json() {
  jq -cn --arg id "${REALITY_UUID}" '[{id: $id, flow: "xtls-rprx-vision", email: "reality-vision"}]'
}
xray_xhttp_clients_json() {
  jq -cn --arg id "${XHTTP_UUID}" '[{id: $id, email: "xhttp-cdn"}]'
}
```

- 其余生成器本阶段不动（路由与 nginx 订阅 location 在阶段 3，nginx 主配置在阶段 4）。

### 4.4 `lib/ui/output.sh`

- 删除：`selected_output_client_name`、`current_link_client_name`、`current_link_reality_uuid`、
  `current_link_xhttp_uuid`、`client_scoped_node_label`、`output_client_detail_line`、
  `output_client_summary_block`、`subscription_*`（`subscription_raw_text` 保留并重命名为
  `vless_links_text`，供阶段 3 的订阅文件使用）、`write_subscription_qr_png`、
  `write_subscription_files`、`subscription_manifest_text`、`subscription_qr_status_text`。
- `build_link_context` 去掉 `requested_client_name` 参数与 `node_client_record_for_name`；
  标签统一用 `prefixed_node_label`。
- 所有 `$(current_link_reality_uuid)` → `${REALITY_UUID}`，`$(current_link_xhttp_uuid)` → `${XHTTP_UUID}`。
- `output_runtime_summary_block` 删掉「Raw/Base64 订阅、清单、二维码」五行；阶段 3 会加订阅 URL。
- `write_output_file` 去掉参数，只写 `OUTPUT_FILE`。

### 4.5 `lib/cli/core.sh`

- 删除：`prompt_node_client_selection`、`list_clients_cmd`、`select_output_client_if_requested`、
  `add_client_cmd`。
- `show_links`：只剩 `--qr`；不再重写任何文件；`OUTPUT_FILE` 不存在则 `die`。
- `xray_managed_service_units` / `restart_service_units`：去掉 `${CORE_HEALTH_TIMER_NAME}`。
- `diagnose_cmd`：删掉「核心巡检 / 核心自恢复 / 最近恢复记录 / 近 1h / 近 24h / 稳定性信号」六行及其失败判定。
- `uninstall_cmd`：
  - 删掉 `warp_teardown_legacy` 调用和 `/var/lib/cloudflare-warp`；
  - `remove_managed_paths` 清单去掉 health 三个文件、`CORE_HEALTH_*` 三个单元、订阅目录；
  - 末尾追加 `remove_legacy_managed_paths`（§4.6），保证从 0.11 升上来再卸载也干净；
  - 交互流程：先问「停止服务并删除托管文件？[y/N]」，再问「是否同时卸载软件包？输入 purge 确认，其它任何输入只删托管文件」。`--purge` / `--yes` 语义不变。
- `show_main_menu` / `run_menu_choice` 改为附录 A 的编号表。
- `dispatch_cli_command`：删 `change-label-prefix`、`purge`、`add-client`、`list-clients`；
  阶段 2、3、4 再加 `check-sni`、`change-sub-token`。
- `script_lock_command_needs_lock`：去掉 `list-clients` 和 `show-links --client` 分支；
  `show-links` 一律不加锁。

### 4.6 `lib/base/runtime.sh`

- 删除：`write_core_health_helper`、`write_core_health_service`、`write_core_health_timer`、
  `write_core_health_monitor`。
- `restart_services`：删掉 `systemctl enable --now "${CORE_HEALTH_TIMER_NAME}"` 两行。
- `rollback_managed_runtime_state`：paths 去掉 `WARP_RULES_FILE` 以外的 health / core 三项。
- 新增（阶段 1 就要有，因为 nginx 缺 `Restart=`）：

```bash
# /etc/systemd/system/nginx.service.d/xtun-limits.conf（文件名不变，内容扩展）
[Service]
LimitNOFILE=1048576
Restart=on-failure
RestartSec=3s
```

  写入函数仍是 `lib/generators.sh::nginx_limits_dropin_text` / `write_nginx_limits_dropin`。
  `Restart=` 变化同样只能靠 `daemon-reload + restart` 生效，现有 `NGINX_RESTART_REQUIRED` 逻辑已覆盖。
  haproxy 不加 drop-in：Debian 单元自带 `Restart=always`（本机实测）。

- 新增 `legacy_managed_paths()` 与 `remove_legacy_managed_paths()`（放在 runtime.sh）：

```
/usr/local/sbin/xtun-core-health.sh
/etc/systemd/system/xtun-core-health.service
/etc/systemd/system/xtun-core-health.timer
/usr/local/etc/xray/health-state.env
/usr/local/etc/xray/health-history.log
/root/xtun-subscriptions
/var/lib/cloudflare-warp/mdm.xml
/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
/etc/apt/sources.list.d/cloudflare-client.list
/usr/local/sbin/xtun-warp-health.sh
/etc/systemd/system/xtun-warp-health.service
/etc/systemd/system/xtun-warp-health.timer
```

  `remove_legacy_managed_paths` 先 `stop_and_disable_service_if_present` 三个 timer/service
  （`xtun-core-health.timer`、`xtun-warp-health.timer`、`warp-svc.service`），再
  `remove_managed_paths`，再 `systemctl daemon-reload`。存在任一路径时打印一行 `log_step`。
  调用点：`apply_config_cmd`（`load_current_install_context` 之后）、`install_cmd`
  （`write_install_managed_files` 之前）、`uninstall_cmd`。全部路径进 `sandbox_managed_paths`
  （用一个 `LEGACY_PATH_ROOT` 前缀变量实现，测试里指向沙箱）。

### 4.7 `lib/ui/health.sh` → 删除文件

- `show_dashboard_brief` / `show_dashboard` 移到新文件 `lib/ui/dashboard.sh`，删掉
  「核心巡检 / 自恢复 / 稳定性」相关行；`lib/ui.sh` 改 source。
- 删除 `health_*` 全部函数与 `stability_signal_text`。

### 4.8 WARP 瘦身

- `lib/install/warp.sh`：删除 `legacy_warp_paths`、`warp_legacy_team_detected`、`warp_teardown_legacy`；
  `ensure_warp_credentials` 里去掉 `warp_legacy_team_detected` 分支。
- `lib/change/workflow.sh::run_change_warp_action`：删掉两处 `warp_teardown_legacy`。
- `lib/cli/install.sh::install_optional_components`：只剩 `install_network_optimization`。
- `lib/install/input.sh`：删除 `show_warp_rules_list`、`warp_rules_editor_normalize`、
  `warp_rules_editor_delete`、`prompt_warp_rules_editor`。
- `lib/change/commands.sh::change_warp_rules_cmd`：交互终端且无修改参数时，改为
  打印当前规则 + 一段用法提示后 `return 0`（不再进编辑器）。

### 4.9 证书模式合并

- `lib/base/env.sh::normalize_cert_mode`：`3` 与全部 `cf-origin-ca*` 别名 → `existing`；
  `4`/`acme*` → `acme-dns-cf`；`cert_mode_choice_value` 输出 1/2/3。
- `lib/install/input.sh::show_cert_mode_menu`：三项（自签名 / 现有证书或 Cloudflare Origin CA / ACME DNS）。
- `lib/install/certs.sh`：删除 `clear_cf_origin_ca_settings`、`prompt_cf_origin_ca_inputs`；
  `prompt_cert_mode_inputs` 只剩三个分支；`stage_and_promote_tls_assets` 去掉 `cf-origin-ca` case。
- `lib/change/requests.sh`：`init_change_cert_mode_request` / `parse_change_cert_mode_args` /
  `apply_cert_mode_change_request` 去掉 `cf_zone_id` / `cf_api_token` / `cf_cert_validity`。
- `lib/cli/install.sh::install_value_specs`：去掉 `--cf-zone-id` / `--cf-api-token` / `--cf-cert-validity`。
- `lib/base/input.sh`：`option_secret_env_name` / `option_requires_indirect_value` 去掉 `--cf-api-token`；
  `usage` 同步。
- `lib/ui/core.sh::pretty_cert_mode` 去掉 `cf-origin-ca` 分支。

### 4.10 `lib/change/*`

- 删除 `change_label_prefix_cmd`；`run_single_value_change_cmd` 去掉 `apply_mode` 参数与 `output` 分支
  （签名变为 7 个固定参数），`begin_managed_output_change` 删除。
- `handle_change_common_arg`、`require_option_value`、`assign_option_value` 不变。

### 4.11 `lib/install.sh`

- `install_draft_file_text` 去掉 `CF_ZONE_ID/CF_API_TOKEN/CF_CERT_VALIDITY`。
- `ensure_managed_permissions` 去掉 `HEALTH_*` 两段。
- `resolve_install_input_sources` 去掉 `CF_API_TOKEN`。

### 4.12 测试

删除用例（同时从 `tests/smoke.sh` 的 `cases` 数组移除）：
`run_multi_client_config_output_case`、`run_node_client_state_case`、`run_client_cli_case`、
`run_show_links_stale_output_case`、`run_health_history_count_without_python_case`、
`run_warp_rules_editor_case`、`run_warp_legacy_teardown_case`、`run_subscription_qr_success_case`。

改用例：`run_dispatch_case`（菜单编号）、`run_usage_case`、`run_state_context_case`、
`run_state_version_case`（v1→v2 迁移：cf-origin-ca 变 existing、NODE_CLIENTS_TEXT 触发 warn）、
`run_cert_mode_input_case`、`run_nginx_limits_dropin_case`（断言含 `Restart=on-failure`）、
`run_diagnose_command_case`。

新增用例：`run_legacy_cleanup_case`（沙箱里放 5 个遗留文件，调 `remove_legacy_managed_paths`，全部消失且 `stop_and_disable_service_if_present` 被调用）。

`tests/smoke.sh::REAL_MANAGED_CANARY`：去掉 `xtun-core-health.sh`、`/root/xtun-subscriptions`。

### 4.13 README

删掉「多客户端」「Cloudflare Origin CA」模式行、「WARP 从旧版本升级」段、
「订阅文件 / 二维码 PNG」路径行、菜单 17/18 说明；命令表按附录 A 更新。

### 4.14 验收

- `shellcheck` 零发现；`smoke ok`。
- `grep -rn 'NODE_CLIENTS_TEXT\|CORE_HEALTH\|cf-origin-ca\|CF_ZONE_ID\|add-client\|list-clients' lib xtun.sh`
  只剩迁移函数与 `normalize_cert_mode` 别名两处。
- 用 v1 状态文件（含 `CERT_MODE=cf-origin-ca`、`NODE_CLIENTS_TEXT='phone|u1|u2'`）跑
  `load_existing_state`：CERT_MODE 变 existing、出现 warn、写回后 `STATE_VERSION=2` 且不含 legacy 键。
- 单客户端安装态生成的 `config.json` 与 0.11.14 逐字节一致（除 clients 数组顺序）。

---

## 5. 阶段 2：Reality 加固：目标域名预检 `check-sni` 与防跑流量（0.12.0 第二部分）

### 5.1 用户可见行为

```bash
xtun check-sni www.stanford.edu                 # 独立检查，不需要 root，不加锁
xtun check-sni www.stanford.edu --target 1.2.3.4:443 --timeout 8
xtun install ... --reality-sni www.stanford.edu # 预检自动跑；有 FAIL 就停
xtun install ... --skip-sni-check               # 跳过，但输出里留 warn
xtun change-sni --reality-sni www.example.com   # 同样先预检
```

输出（示例，见附录 G）：一行一个检查项，`PASS` / `WARN` / `FAIL` 三级，末尾一行结论。
退出码：`0` 无 FAIL；`2` 有 FAIL；`1` 参数错误。

### 5.2 检查项定义

所有探测从 VPS 本机发起。`target` 默认 `REALITY_SNI:443`，`--target` 可覆盖
（对应 `REALITY_TARGET`）。`servername` 永远是 SNI 域名。超时默认 10s，`timeout` 命令包裹。

| # | 名称 | 方法 | PASS | WARN | FAIL |
| --- | --- | --- | --- | --- | --- |
| 1 | 域名格式 | `is_valid_hostname` | 合法 | — | 非法 |
| 2 | DNS 解析 | `getent ahostsv4 <target_host>` | ≥1 个公网 IPv4 | 只解析出 IPv6 | 无记录；或解析到私网；或解析到 `SERVER_IP` 本机（会形成回环） |
| 3 | TLS 1.3 | `openssl s_client -connect target -servername sni -tls1_3 -groups X25519 -alpn h2 </dev/null` | 输出含 `Protocol  : TLSv1.3` | — | 连接失败或非 1.3 |
| 4 | X25519 | 同一份输出 | 含 `Peer Temp Key: X25519` 或 `Server Temp Key: X25519` | — | 否 |
| 5 | HTTP/2 ALPN | 同一份输出 | 含 `ALPN protocol: h2` | — | 否（Reality + Vision 要求目标支持 h2） |
| 6 | 证书链 | 同一份输出 | `Verify return code: 0 (ok)` | — | 其它 |
| 7 | 证书 SAN | `openssl x509 -noout -ext subjectAltName` | 精确匹配或通配符匹配 SNI | — | 不含 |
| 8 | 证书到期 | `-enddate` | ≥ 30 天 | 14–30 天 | < 14 天 |
| 9 | 目标是否在 CDN 后 | 证书 issuer / `server:` 头含 `cloudflare` 等 | 否 | 是（偷到的是 CF 边缘握手，可用但不理想） | — |
| 10 | HTTP 跳转 | `curl -sS -o /dev/null --max-time T --http2 -A "<Chrome UA>" -w '%{http_code} %{http_version} %{redirect_url} %{time_appconnect}' https://sni/`（target≠sni 时加 `--resolve sni:443:targetIP`） | 2xx，redirect 为空 | 3xx 且 Location 主机 == sni；或 403/429（反爬）；或 5xx | 3xx 且 Location 主机 ≠ sni（例：`stanford.edu` → `www.stanford.edu`，应改用 www）；或 `000` |
| 11 | 实际 HTTP 版本 | 同上 `%{http_version}` | `2` | 其它 | — |
| 12 | 握手耗时 | 同上 `%{time_appconnect}` | ≤ 0.30s | 0.30–1.00s | > 1.00s（每条新连接都要先把这个 RTT 付给远端） |

实测参考（本机 → `www.stanford.edu`）：OpenSSL 3.5 打印 `Peer Temp Key: X25519, 253 bits`
和 `ALPN protocol: h2`；curl 默认 UA 得 403、Chrome UA 得 200；`https://stanford.edu/` 301 到
`www.stanford.edu`。判定规则必须覆盖这三种真实情况。

### 5.3 代码结构（新文件 `lib/cli/sni.sh`，由 `lib/cli.sh` source）

探测层（有网络副作用，测试中被覆盖）：

```bash
sni_probe_dns HOST                  # stdout: 每行一个 IPv4；无则空
sni_probe_tls TARGET SNI TIMEOUT    # stdout: s_client 完整输出（stderr 合并）
sni_probe_cert TARGET SNI TIMEOUT   # stdout: "SAN=DNS:a,DNS:b\nNOTAFTER=<date>\nISSUER=<line>"
sni_probe_http SNI TARGET_IP TIMEOUT # stdout: "<code> <httpver> <redirect_url> <time_appconnect> <server_header>"
```

判定层（纯函数，输入字符串，输出 `LEVEL|名称|说明` 行）：

```bash
sni_judge_hostname SNI
sni_judge_dns SNI TARGET_HOST "<dns 输出>" SERVER_IP
sni_judge_tls "<s_client 输出>"          # 一次吐 3/4/5/6 四行
sni_judge_cert SNI "<cert 输出>" NOW_EPOCH # 7/8/9 三行
sni_judge_http SNI "<http 输出>"          # 10/11/12 三行
```

聚合：

```bash
run_sni_checks SNI TARGET SERVER_IP TIMEOUT   # 打印表格；有 FAIL 返回 2，否则 0
sni_check_cmd "$@"                            # CLI 入口，解析 --target/--timeout/--server-ip
preflight_check_reality_sni                   # 供 install / change-sni 调用（§5.4）
```

`run_sni_checks` 的表格用 `printf '%-4s %-14s %s\n'`，颜色沿用 `style_text`；
非 tty 不着色（`C_*` 已按 `-t 1` 处理）。

### 5.4 集成点

- `lib/install/input.sh::run_install_preflight_checks`：在 443 端口检查之后调用
  `preflight_check_reality_sni`。行为：
  - `SKIP_SNI_CHECK=1`（新 flag `--skip-sni-check`，进 `install_flag_specs`；不持久化）：
    只 `warn "已按要求跳过 Reality 目标域名预检"`，返回 0。
  - 结果无 FAIL：返回 0。
  - 有 FAIL 且 `NON_INTERACTIVE=1`：`die "预检失败：Reality 目标域名不满足要求；确认无误可加 --skip-sni-check"`。
  - 有 FAIL 且交互：`read -r -p "重新输入 SNI (r) / 忽略继续 (i) / 退出 (q) [r]: "`；
    `r` 重新 `prompt_with_default REALITY_SNI` 与 `REALITY_TARGET` 后重跑（最多 3 轮）；`i` warn 后继续；`q` die。
- `lib/change/commands.sh::change_sni_cmd`：`run_single_value_change_cmd` 的 `post_update_fn`
  从 `ensure_reality_sni_format` 换成新函数 `ensure_reality_sni_ready`：先格式校验，再
  `REALITY_TARGET="$(default_reality_target_for_sni "${REALITY_SNI}")"`（改 SNI 时目标跟着换，
  这是现状里的一个隐性缺陷：0.11 只改 SNI 不改 target），再 `preflight_check_reality_sni`。
  `change-sni` 同样接受 `--skip-sni-check`。
- 菜单新增「检查 REALITY SNI 域名」，运行 `check-sni`，域名默认取当前 `REALITY_SNI`。
- `usage` 增补命令与参数说明。

### 5.5 测试（`tests/cases_sni.sh`，在 `tests/smoke.sh` 加 source 与用例名）

- `run_sni_judge_tls_case`：三段夹具文本（正常 / 无 h2 / `Protocol  : TLSv1.2`），断言三行判定。
- `run_sni_judge_http_case`：`200 2  0.02` → 全 PASS；`301 2 https://www.x.com/ 0.02`（sni=x.com）→ FAIL；
  `301 2 https://x.com/path 0.02` → WARN；`403 2  0.02` → WARN；`000 0  0` → FAIL；`200 2  1.4` → 耗时 FAIL。
- `run_sni_judge_cert_case`：SAN 通配符匹配、到期 10 天 → FAIL、issuer 含 Cloudflare → WARN。
- `run_sni_judge_dns_case`：解析到 `SERVER_IP` → FAIL；私网 → FAIL；空 → FAIL。
- `run_sni_check_cmd_case`：覆盖 4 个 `sni_probe_*` 为固定输出，`run_sni_checks` 退出码 0/2 正确；
  `sni_check_cmd --timeout abc` 退出码 1。
- `run_install_preflight_sni_case`：`NON_INTERACTIVE=1` + 覆盖 `run_sni_checks` 返回 2 → `preflight_check_reality_sni`
  以 `die` 结束（用 `assert_false` 包在子 shell）；加 `SKIP_SNI_CHECK=1` → 返回 0 且 stderr 含「跳过」。
- 现有 `run_install_flow_case` 需要覆盖 `preflight_check_reality_sni() { :; }`。

### 5.6 README

新增「Reality 目标域名要求与预检」一节：列 12 项检查、给 `stanford.edu` 对 `www.stanford.edu`
的反例、说明 `--skip-sni-check`。

### 5.7 防跑流量：官方 dokodemo-door 模式

**问题**（Xray 官方 REALITY 文档原文）：「Xray 对于鉴权失败（非合法 REALITY 请求）的流量，会直接转发至 target。
如果 target 网站的 IP 地址特殊（如使用了 Cloudflare CDN 的网站）则相当于你的服务器充当了 Cloudflare 的端口转发，
可能造成被扫描后偷跑流量的情况。为了杜绝这种情况，可以考虑前置 Nginx 等方法过滤掉不符合要求的 SNI。
或者也可以考虑配置 `limitFallbackUpload` 和 `limitFallbackDownload`，限制其速率。」

xtun 现状：haproxy 的 `default_backend be_reality_vision` 把所有非 CDN 域名的 SNI（包括无 SNI、随机 SNI、扫描器）
都送进 Reality 入站，鉴权失败后原样转发到 `REALITY_TARGET`。目标站是普通站点时浪费的是带宽；目标站在 CDN 后时
就是官方说的端口转发。

**采用方案**：Xray-examples 仓库 `VLESS-TCP-REALITY (without being stolen)` 的官方模板，不依赖 haproxy 改动：

1. Reality 入站的 `realitySettings.target` 固定为 `127.0.0.1:${REALITY_FALLBACK_PORT}`
   （新全局常量 `REALITY_FALLBACK_PORT="2444"`，写进 `xtun.sh`；与 2443 / 8001 / 8443 不冲突）。
   `serverNames` 照常填 `REALITY_SNI`。
2. 新增 `dokodemo-door` 入站（`lib/generators.sh` 新函数 `xray_reality_fallback_inbound_json`）：

```json
{
  "tag": "reality-fallback",
  "listen": "127.0.0.1",
  "port": 2444,
  "protocol": "dokodemo-door",
  "settings": {
    "address": "<REALITY_TARGET 的 host>",
    "port": <REALITY_TARGET 的 port>,
    "network": "tcp"
  },
  "sniffing": {
    "enabled": true,
    "destOverride": ["tls"],
    "routeOnly": true
  }
}
```

   `sniffing` 是必需的（官方注释「这里的 sniffing 不是多余的，别乱动」）：路由要靠嗅探出的 SNI 做域名匹配；
   `routeOnly: true` 保证实际连接目标仍是 `settings.address`，嗅探结果只参与路由。

3. 路由规则（`xray_routing_rules_json`）**最前面**两条，先于 §6.1 的 private / cn 拦截：

```json
{ "type": "field", "inboundTag": ["reality-fallback"], "domain": ["full:<REALITY_SNI>"], "outboundTag": "direct" },
{ "type": "field", "inboundTag": ["reality-fallback"], "outboundTag": "block" }
```

   官方模板用的是不带前缀的 `"speed.cloudflare.com"`（子域匹配）；这里用 `full:` 精确匹配，
   因为 `serverNames` 本来就只有一个精确值。若将来 `serverNames` 支持多值，这里同步展开成多条 `full:`。

4. `xray_inbounds_json` 顺序：`[reality_inbound, reality_fallback_inbound, xhttp_inbound]`。
   Reality 入站的 VLESS `fallbacks`（转 8001 给 XHTTP-over-Reality）不受影响：那是 REALITY 鉴权通过之后的事。

5. 状态与回填：
   - `REALITY_TARGET` 状态键语义不变，仍是「真实目标 host:port」，只是消费者从 reality 入站换成了 dokodemo 入站。
   - `lib/state.sh::load_config_runtime_context` 读 `REALITY_TARGET` 改为：
     `.inbounds[] | select(.tag=="reality-fallback") | "\(.settings.address):\(.settings.port)"`；
     读不到（v1 生成的 config.json）再退回 `.realitySettings.target`，且该值等于 `127.0.0.1:2444` 时视为无效。
   - `require_current_install_context` 不变。
   - 新增 `reality_target_host()` / `reality_target_port()` 两个拆分函数（`lib/install/input.sh`，
     复用 `validate_hostport_value` 的拆分逻辑），生成器与 `check-sni` 共用。

6. `diagnose` / `status` 增加「监听 2444」；`REAL_MANAGED_CANARY` 无需变化。

7. `check-sni`（§5.2）第 2 项 DNS 检查中「解析到 SERVER_IP 形成回环」的判定保留：dokodemo 的 address
   若指回本机，回落流量会打到 haproxy 再进 Reality，形成环。

8. 不做的事及理由：
   - 不在 haproxy 层 `tcp-request content reject` 非法 SNI。TCP 层直接 RST 与「真实站点收到陌生 SNI 仍完成握手」
     的外观不同，官方模板也没有这么做；dokodemo 层的 blackhole 已经足够。
   - 不配置 `limitFallbackUpload/Download`。官方原文：「回落限速是一种特征，不建议启用，如果您是面板/一键脚本开发者，
     务必让这些参数随机化。」xtun 不引入这个特征。

**测试**：`run_reality_fallback_inbound_case`（新增到 `tests/cases_output.sh` 或 `cases_state_runtime.sh`）：

- 生成的 `config.json`：`.inbounds[1].protocol == "dokodemo-door"`、`.settings.address/port` 等于拆分后的 `REALITY_TARGET`、
  `.sniffing.destOverride == ["tls"]`、`.sniffing.routeOnly == true`；
  `.inbounds[0].streamSettings.realitySettings.target == "127.0.0.1:2444"`；
  `.routing.rules[0]` 为 `inboundTag=reality-fallback + domain=full:<sni> → direct`，`.routing.rules[1]` 为 `→ block`。
- `xray run -test` 通过（并入现有 `run_warp_config_json_valid_case` 的断言）。
- `load_config_runtime_context` 从新版 config 读回 `REALITY_TARGET`；从 v1 形状的 config（target 为远端 host:port）也能读回。
- `REALITY_TARGET="203.0.113.10:8443"`（IP 目标、非 443 端口）时 dokodemo 的 address/port 正确。

**README**：「架构说明」的请求流图补一层：

```
haproxy :443 --其它 SNI--> xray Reality 127.0.0.1:2443
                             |-- 鉴权通过 --> VLESS / fallbacks 8001
                             `-- 鉴权失败 --> dokodemo 127.0.0.1:2444 --SNI==REALITY_SNI--> 真实目标站
                                                                      `--其它 SNI--> blackhole
```

---

## 6. 阶段 3：路由卫生、订阅托管、mihomo 输出（0.12.0 第三部分）

### 6.1 路由卫生

`lib/generators.sh::xray_routing_rules_json` 改为无条件输出前置规则，再拼 WARP 规则
（§5.7 的两条 dokodemo 规则永远排在最前）：

```json
[
  // §5.7 的两条 reality-fallback 规则在此之前
  { "type": "field", "outboundTag": "block", "ip": ["geoip:private"] },
  { "type": "field", "outboundTag": "block", "domain": ["geosite:private"] },
  // ROUTE_BLOCK_CN=yes 时追加：
  { "type": "field", "outboundTag": "block", "ip": ["geoip:cn"] },
  { "type": "field", "outboundTag": "block", "domain": ["geosite:cn"] },
  // ENABLE_WARP=yes 时追加现有 direct / WARP 两条
]
```

- `domainStrategy` 保持 `AsIs`：域名目标由 `geosite:*` 规则命中，IP 目标由 `geoip:*` 命中，
  不引入服务端 DNS 解析开销。
- `block` 出站已存在（`xray_block_outbound_json`），原来只是没人引用。
- 新 flag：`--block-cn` / `--no-block-cn`（`install_flag_specs`：`ROUTE_BLOCK_CN:yes|no`），
  交互安装问一次「是否拦截回国流量（geoip:cn / geosite:cn）？[y/n]」默认 `n`。
  改动走 `apply-config`（状态文件手改）即可，不单独加命令。
- `diagnose` 增加一行「路由拦截: private[+cn]」，从 `config.json` 用 jq 读 `.routing.rules[] | select(.outboundTag=="block")`。
- 测试：`run_routing_block_rules_case`（无 WARP / 有 WARP / block-cn 三种组合的 rules 数组形状），
  更新 `run_warp_config_json_valid_case` 的期望。

### 6.2 订阅 HTTPS 托管

**状态**：`SUB_TOKEN`（32 位 hex，`random_hex 16`）。安装时生成；`load_existing_state`
之后若为空（旧节点升级）则在 `apply-config` / `install` 中生成并写回。

**落盘**：

```
/var/www/xtun-sub/<SUB_TOKEN>/vless.txt        base64 一行（现 subscription_base64_text）
/var/www/xtun-sub/<SUB_TOKEN>/vless-raw.txt    每行一个 vless://
/var/www/xtun-sub/<SUB_TOKEN>/mihomo.yaml      §6.3
```

目录 `0755 root:root`，文件 `0644`。写入用 `write_generated_file_atomically`。
生成函数放 `lib/ui/output.sh`：`write_subscription_web_files`，由 `write_output_file` 调用。
写之前 `find "${SUB_WEB_ROOT}" -mindepth 1 -maxdepth 1 -type d ! -name "${SUB_TOKEN}" -exec rm -rf {} +`
清掉旧 token 目录（轮换即失效）。

**nginx**（`lib/generators.sh::nginx_server_config`，放在 xhttp location 之前）：

```nginx
    location ^~ /sub/ {
        alias /var/www/xtun-sub/;
        try_files $uri =404;
        autoindex off;
        access_log off;
        types { text/plain txt; application/yaml yaml yml; }
        default_type text/plain;
        add_header Cache-Control "no-store, max-age=0" always;
        add_header X-Robots-Tag "noindex, nofollow" always;
    }
```

**命令**：`xtun change-sub-token`：`begin_managed_change` → `SUB_TOKEN="$(random_hex 16)"` →
`write_state_file` → `write_output_file`（重写 web 目录）→ `finish_managed_change "订阅地址已轮换。"`。
不需要重启任何服务（nginx 用 alias 到父目录）。进菜单。

**输出**（`output_runtime_summary_block` 新增段）：

```
## 订阅地址（经 CDN 域名 HTTPS）
- VLESS Base64: https://<XHTTP_DOMAIN>/sub/<token>/vless.txt
- VLESS Raw:    https://<XHTTP_DOMAIN>/sub/<token>/vless-raw.txt
- mihomo:       https://<XHTTP_DOMAIN>/sub/<token>/mihomo.yaml
- 轮换: xtun change-sub-token
```

`show-links --qr` 追加打印 Base64 订阅 URL 的二维码（在 5 条链接之后）。

**自检**：`diagnose` 增加「订阅自检」：
`curl -k -sS --max-time 5 --resolve "${XHTTP_DOMAIN}:443:127.0.0.1" "https://${XHTTP_DOMAIN}/sub/${SUB_TOKEN}/vless.txt"`
与磁盘文件 `cmp`，不一致计入 `config_failures`。`self-signed` 模式下 `-k` 是必需的。

**Cloudflare 提示**：`cloudflare_xhttp_cache_bypass_expression` 追加
`or (http.request.uri.path contains "/sub/")`；缓存规则说明段同步。

**测试**：`run_subscription_web_files_case`（三文件存在、权限、旧 token 目录被清、`vless.txt` 解码后 5 行）、
`run_change_sub_token_case`（token 变化、目录切换、不调用 restart）、
`run_nginx_sub_location_case`（生成文本含 alias 与 no-store）。
`sandbox_managed_paths` 加 `SUB_WEB_ROOT`；`REAL_MANAGED_CANARY` 加 `/var/www/xtun-sub`。

### 6.3 mihomo 节点 yaml

- 生成函数 `mihomo_nodes_yaml_text`（`lib/ui/output.sh`），纯 heredoc；标量一律经
  `yaml_quote()`（双引号包裹，转义 `\` 与 `"`）输出，避免 vlessenc 字串、路径里的字符被 YAML 误读。
- 模板见附录 E。要求 mihomo ≥ 1.19.24（xhttp + x-padding + vlessenc），在文件头注释与 README 写明。
- ECH 开启时 CDN 类节点与 `download-settings` 追加 `ech-opts`；xpadding 开启时 `xhttp-opts` 与
  `download-settings` 追加 `x-padding-*` 五键；VLESS Encryption 开启时 XHTTP 类节点带 `encryption:`。
- 测试：`run_mihomo_yaml_case`：默认态 5 个 `- name:`；开 ECH/xpadding/关 vlessenc 三种变体的键存在性；
  若宿主机有 `python3`，用 `python3 -c 'import yaml'` 可用时做一次真实解析（不可用则跳过，不算失败）。

### 6.4 版本与文档

- 阶段 1–3 完成后打 tag `v0.12.0`。
- README 新增：「路由拦截」、「订阅地址」、「mihomo 导入」三节；Cloudflare 缓存规则表达式更新。

---

## 7. 阶段 4：服务器调优补全（0.13.0）

### 7.1 接管 `/etc/nginx/nginx.conf`

- 状态键 `NGINX_MAIN_MANAGED=yes|no`。新装默认 `yes`（交互安装问一次，默认 y；flag
  `--manage-nginx-main` / `--no-manage-nginx-main`）。从 v1 升级的节点默认 `no`，
  `xtun apply-config --manage-nginx-main` 打开并立即生效。
- 生成器 `nginx_main_config_text`（`lib/generators.sh`），模板见附录 F。要点：
  - `worker_rlimit_nofile 1048576;` 与 `LimitNOFILE` 对齐；
  - `events { worker_connections 65535; multi_accept on; }`；
  - 两个用户块：`nginx-main`（顶层，`http {}` 之前）、`nginx-http`（`http {}` 内末尾）；
  - 保留 Debian 的 `include /etc/nginx/modules-enabled/*.conf;`、`conf.d/*.conf`、`sites-enabled/*`；
  - `access_log` 保留主日志，xhttp location 里 `access_log off;`（每个 POST 一行日志，纯噪音）。
- `write_nginx_main_config`：`NGINX_MAIN_MANAGED=yes` 时经 `write_generated_file_atomically` 写
  `NGINX_MAIN_CONFIG`（首次接管前 `backup_path` 已由该函数保证）。`write_runtime_managed_files`
  在 `write_nginx_config` 之后调用它；`rollback_managed_runtime_state` 的 paths 条件性加入
  `NGINX_MAIN_CONFIG`。
- `nginx_worker_connections_text`（`lib/ui/core.sh`）：接管后只显示数值；未接管时保留现有提示，
  并补一句「或运行 xtun apply-config --manage-nginx-main」。
- `uninstall`：接管过的节点，用备份目录里最早的一份 `nginx.conf` 还原；找不到则写回 Debian 默认模板
  （把当前 Debian 13 默认内容以 heredoc 存为 `nginx_main_config_debian_default_text`）。
- `http2` 指令兼容：`nginx -v` 版本 < 1.25.1 时（Ubuntu 24.04 的 1.24），`nginx_server_config`
  输出 `listen 127.0.0.1:8443 ssl http2;` 而不是 `http2 on;`。新函数 `nginx_version_at_least MAJOR.MINOR.PATCH`。
  这是现状缺陷（0.11 在 Ubuntu 24.04 上 `nginx -t` 会失败），顺手修。
- 测试：`run_nginx_main_config_case`（模板含 rlimit / worker_connections / 两个用户块；用户块内容跨重写保留）、
  `run_nginx_http2_compat_case`（覆盖 `nginx_version_at_least` 两种返回）。

### 7.2 sysctl 增补

`write_net_sysctl_conf` 追加：

```
# 未发送数据超过 128KB 就不再往 socket 缓冲里塞，h2 多路复用下的小流不用排在大流后面。
# Cloudflare 边缘用 16KB；跨境高 BDP 链路上给到 128KB 更稳，不会卡住吞吐。
net.ipv4.tcp_notsent_lowat = 131072
```

测试 `run_net_sysctl_content_case` 增加断言。

### 7.3 BBR 内核开关拆分

- 状态键 `NET_BBR_KERNEL=joey|none`。flag `--bbr-kernel joey|none`；交互安装在「是否启用网络优化」
  之后问「是否安装 Joey BBRv3 第三方内核？[y/n]」默认 `y`（用户当前节点即此内核）。
- `install_network_optimization`：`NET_BBR_KERNEL=none` 时跳过 `install_joey_bbrv3_kernel_if_needed`，
  其余（sysctl / helper / service）照常；`preferred_congestion_control` 逻辑不变（有 bbr1 用 bbr1，否则 bbr）。
- `apply-net-opt` 接受 `--bbr-kernel` 覆盖并写回状态。
- README「网络优化」一节据此改写。

### 7.4 `diagnose --net`

新增子段「网络栈」，纯输出、只在拥塞控制不是 bbr 系时计一次失败：

```
内核:            7.0.3-joeyblog-bbrv3
拥塞控制:        bbr1  (可用: reno cubic bbr bbr1)
tcp_bbr 模块:    version 3
默认 qdisc:      fq
出网网卡 qdisc:  fq limit 100000p flow_limit 1000p   (tc qdisc show dev eth0 root)
MTU:             1500
tcp_notsent_lowat: 131072
fs.file-max:     2097152
nginx worker_connections / worker_rlimit_nofile:  65535 / 1048576
nginx master LimitNOFILE:  1048576   (/proc/<pid>/limits)
haproxy maxconn: 20000
已建立连接拥塞算法分布:  bbr1=37 cubic=0   (ss -tin)
```

`status` 面板加一行「拥塞控制 / qdisc」。测试：`run_diagnose_net_case` 覆盖读取函数为固定值，断言输出行。

### 7.5 版本

打 tag `v0.13.0`。

---

## 8. 阶段 5（可选）：IPv6 双栈（0.14.0）

- 探测：`guess_server_ip6`（`ip -6 route get 2606:4700:4700::1111` 取 `src`；非全局单播则空）。
  flag `--server-ip6 VALUE` / `--no-ipv6`；状态键 `SERVER_IP6`。
- haproxy：`bind :::443 v4v6`（替换 `bind :443`）。xray 两个入站仍监听 `127.0.0.1`，nginx 不动。
- 链接：`SERVER_IP6` 非空时追加两条：
  - `REALITY-V6`：与节点 1 相同，地址 `[SERVER_IP6]`；
  - `XHTTP-SPLIT-CDN-REALITY-V6`：与节点 4 相同，`downloadSettings.address` 为 IPv6。
- mihomo 同步追加两条。
- `diagnose`：`监听 [::]:443`。
- 测试：`run_ipv6_links_case`、`run_haproxy_bind_v4v6_case`。

## 9. 阶段 6（可选）：XHTTP H3 直连下行（0.15.0）

前提：nginx 编译含 `http_v3`（Debian 13 的 1.26.3 自带；Debian 12 / Ubuntu 24.04 需 nginx.org 官方源），
且证书模式为 `existing` / `acme-dns-cf`（客户端 `allowInsecure=0`，自签名不可用）。
两者任一不满足则整段功能自动关闭并在 `status` 标明原因。

- haproxy 只占 TCP 443，UDP 443 空着，nginx 直接在公网地址监听：
  `listen 443 quic reuseport;`（有 IPv6 再加 `listen [::]:443 quic reuseport;`）、
  `add_header Alt-Svc 'h3=":443"; ma=86400' always;`。TLS 终止在 nginx，`grpc_pass` 不变。
- 链接：追加 `XHTTP-TLS-H3`（地址 `SERVER_IP`，`sni=XHTTP_DOMAIN`，`alpn=h3`）与
  `XHTTP-SPLIT-CDN-H3`（上行 CDN h2，`downloadSettings` 走 H3 直连）。
- 防火墙提示：UDP 443 需放行；`diagnose` 用 `ss -lunH '( sport = :443 )'` 检查。
- 测试：`run_h3_nginx_listen_case`、`run_h3_links_case`。

---

## 10. 阶段 7：1.0.0

- README 重写为「面向自己」的手册：快速开始（3 条命令）、节点一览、Reality 域名要求、
  Cloudflare 面板步骤、命令表、故障处理、文件清单。原理性内容移到 `docs/ARCHITECTURE.md`
  （请求流图、为什么有 haproxy、为什么 Reality 目标不用自己的域名）。
- CI 增加真机冒烟 job：`debian:13` systemd 容器（`docker run --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw`），
  执行 `bash xtun.sh install --non-interactive --server-ip 127.0.0.1 --reality-sni www.stanford.edu --xhttp-domain cdn.example.test --cert-mode self-signed --disable-warp --disable-net-opt --no-manage-nginx-main`，
  然后 `xtun diagnose`（允许「订阅自检」与「本地 TLS 探测」通过，443 由 haproxy 监听）。
  网络不可达导致 `check-sni` 失败时该 job 加 `--skip-sni-check`。
- 打 tag `v1.0.0`。

---

## 附录 A：0.12.0 之后的命令与菜单

CLI（`dispatch_cli_command`）：

```
install [参数]            update-script          upgrade
check-sni [域名] [--target host:port] [--timeout N]
change-uuid [参数]        change-sni [参数]      change-path [参数]
change-warp [参数]        change-warp-rules [参数]
change-cert-mode [参数]   renew-cert [参数]      change-sub-token
show-links [--qr]         diagnose [--warp-probe] [--net]
status [--raw]            restart                repair-perms
apply-config [--manage-nginx-main]   apply-net-opt [--bbr-kernel joey|none]
uninstall [--yes] [--purge]          version      help
```

菜单：

```
  1. 安装或重装
  2. 查看节点链接与订阅地址
  3. 运行诊断
  4. 刷新状态面板
  5. 重启服务
  6. 更新脚本本身
  7. 升级 Xray 核心
  8. 轮换节点 UUID
  9. 修改 REALITY SNI（含预检）
 10. 检查 REALITY SNI 域名
 11. 修改 XHTTP 路径
 12. 开关 WARP 分流
 13. 查看 WARP 分流规则
 14. 修改证书模式 / CDN 域名
 15. 续期 / 刷新证书
 16. 轮换订阅地址
 17. 重新应用网络优化
 18. 重新生成托管配置
 19. 抢修文件权限
 20. 卸载
  0. 退出
```

新增 install flag：`--skip-sni-check`、`--block-cn` / `--no-block-cn`、
`--manage-nginx-main` / `--no-manage-nginx-main`、`--bbr-kernel joey|none`。
删除 install 选项：`--cf-zone-id`、`--cf-api-token`、`--cf-cert-validity`。

## 附录 B：状态文件 v2 键表（`/usr/local/etc/xray/node-meta.env`）

```
STATE_VERSION=2
SERVER_IP  NODE_LABEL_PREFIX
REALITY_UUID  REALITY_SNI  REALITY_TARGET  REALITY_SHORT_ID  REALITY_PRIVATE_KEY  REALITY_PUBLIC_KEY
XHTTP_UUID  XHTTP_DOMAIN  XHTTP_PATH
XHTTP_VLESS_ENCRYPTION_ENABLED  XHTTP_VLESS_DECRYPTION  XHTTP_VLESS_ENCRYPTION
TLS_ALPN  FINGERPRINT
ENABLE_WARP  WARP_PRIVATE_KEY  WARP_ADDRESS_V4  WARP_ADDRESS_V6  WARP_PEER_PUBLIC_KEY  WARP_ENDPOINT  WARP_RESERVED  WARP_MTU  WARP_RULES_TEXT
ENABLE_NET_OPT  NET_BBR_KERNEL
CERT_MODE(self-signed|existing|acme-dns-cf)  ACME_EMAIL  ACME_CA  CF_DNS_ACCOUNT_ID  CF_DNS_ZONE_ID
XHTTP_ECH_CONFIG_LIST  XHTTP_ECH_FORCE_QUERY
XHTTP_XPADDING_ENABLED  XHTTP_XPADDING_KEY  XHTTP_XPADDING_HEADER  XHTTP_XPADDING_PLACEMENT  XHTTP_XPADDING_METHOD
ROUTE_BLOCK_CN  SUB_TOKEN  NGINX_MAIN_MANAGED
SERVER_IP6（阶段 5）
```

只读的 v1 遗留键：`NODE_CLIENTS_TEXT`（触发迁移提示后丢弃）。

## 附录 C：托管文件清单（1.0.0）

```
/usr/local/sbin/xtun                          管理命令 wrapper
/usr/local/lib/xtun/                          脚本 bundle
/usr/local/bin/xray  /usr/local/share/xray/   核心与 geo 资源
/usr/local/etc/xray/config.json               0640 root:xray
    本机端口：2443 Reality 入站 / 2444 dokodemo 回落过滤 / 8001 XHTTP 入站 / 8443 nginx TLS
/usr/local/etc/xray/node-meta.env             0600
/usr/local/etc/xray/warp-domains.list
/etc/systemd/system/xray.service
/etc/systemd/system/nginx.service.d/xtun-limits.conf   LimitNOFILE + Restart
/etc/haproxy/haproxy.cfg
/etc/nginx/nginx.conf                         仅 NGINX_MAIN_MANAGED=yes
/etc/nginx/conf.d/xtun.conf
/etc/ssl/xtun/{cert,key}.pem
/etc/sysctl.d/98-xtun-net.conf
/usr/local/sbin/xtun-net-optimize.sh  +  xtun-net-optimize.service
/usr/local/sbin/xtun-cert-reload.sh           acme 模式
/etc/logrotate.d/xtun
/var/www/xtun-fallback/                       伪装站
/var/www/xtun-sub/<token>/                    订阅
/root/xtun-output.md                          人类可读输出
/root/xtun-backups/                           变更备份
/var/log/xtun/operations.log
```

## 附录 D：把现有节点（本机）升到 0.12 / 0.13 的操作

本机现状：`ENABLE_WARP=yes`、`CERT_MODE=cf-origin-ca`、`NODE_CLIENTS_TEXT` 空、
`/etc/nginx/nginx.conf` 手工调过（`worker_rlimit_nofile 131072`、`worker_connections 65535`、`worker_cpu_affinity auto`）。

1. `xtun update-script`。
2. `xtun status`：应看到迁移提示「证书模式 cf-origin-ca 已并入 existing」。
3. `xtun apply-config`：会移除 core-health timer 与历史文件、删 `/root/xtun-subscriptions`、
   把 Reality 回落切到 dokodemo-door 过滤（新增 2444 监听）、写入路由拦截规则、生成 `SUB_TOKEN` 与订阅目录、
   nginx drop-in 加 `Restart=`（这一次 nginx 会重启）。`config.json` 中 WARP 出站与规则保持不变。
   之后 `xtun diagnose` 应看到 2444 在监听。
4. `xtun check-sni`（用当前 `REALITY_SNI`），确认现用域名过检。
5. 阶段 4 后：`xtun apply-config --manage-nginx-main`。接管模板的 `worker_connections 65535`
   与手工值相同，`worker_rlimit_nofile` 从 131072 抬到 1048576；`worker_cpu_affinity auto` 在模板里保留。
   手工 nginx.conf 会进当次备份目录。
6. `xtun diagnose --net` 核对 `bbr1 / fq / notsent_lowat`。

## 附录 E：mihomo 节点模板（`mihomo_nodes_yaml_text`）

`Q()` 表示 `yaml_quote`。`[ECH]` / `[XPAD]` / `[ENC]` 段按开关条件输出。
`PFX` = `prefixed_node_label` 的前缀。

```yaml
# 由 xtun 生成；需要 mihomo >= 1.19.24
proxies:
  - name: Q(PFX-REALITY)
    type: vless
    server: Q(SERVER_IP)
    port: 443
    uuid: Q(REALITY_UUID)
    udp: true
    tls: true
    network: tcp
    flow: xtls-rprx-vision
    servername: Q(REALITY_SNI)
    client-fingerprint: Q(FINGERPRINT)
    reality-opts:
      public-key: Q(REALITY_PUBLIC_KEY)
      short-id: Q(REALITY_SHORT_ID)

  - name: Q(PFX-XHTTP-REALITY)
    type: vless
    server: Q(SERVER_IP)
    port: 443
    uuid: Q(XHTTP_UUID)
    [ENC] encryption: Q(XHTTP_VLESS_ENCRYPTION)
    udp: true
    tls: true
    network: xhttp
    servername: Q(REALITY_SNI)
    client-fingerprint: Q(FINGERPRINT)
    reality-opts:
      public-key: Q(REALITY_PUBLIC_KEY)
      short-id: Q(REALITY_SHORT_ID)
    xhttp-opts:
      path: Q(XHTTP_PATH)
      mode: auto
      [XPAD] x-padding-obfs-mode: true
      [XPAD] x-padding-key: Q(XHTTP_XPADDING_KEY)
      [XPAD] x-padding-header: Q(XHTTP_XPADDING_HEADER)
      [XPAD] x-padding-placement: Q(XHTTP_XPADDING_PLACEMENT)
      [XPAD] x-padding-method: Q(XHTTP_XPADDING_METHOD)
      reuse-settings:
        max-concurrency: "16-32"
        c-max-reuse-times: "0"
        h-max-reusable-secs: "1800-3000"
        h-keep-alive-period: 0

  - name: Q(PFX-XHTTP-CDN)
    type: vless
    server: Q(XHTTP_DOMAIN)
    port: 443
    uuid: Q(XHTTP_UUID)
    [ENC] encryption: Q(XHTTP_VLESS_ENCRYPTION)
    udp: true
    tls: true
    network: xhttp
    alpn: [h2]
    servername: Q(XHTTP_DOMAIN)
    client-fingerprint: Q(FINGERPRINT)
    [ECH] ech-opts:
    [ECH]   enable: true
    [ECH]   query-server-name: cloudflare-ech.com
    xhttp-opts:
      host: Q(XHTTP_DOMAIN)
      path: Q(XHTTP_PATH)
      mode: auto
      sc-min-posts-interval-ms: 30
      [XPAD] x-padding-* 五键
      reuse-settings: （同上）

  - name: Q(PFX-XHTTP-SPLIT-CDN-REALITY)
    # 外层与 XHTTP-CDN 相同（上行走 CDN），追加：
    xhttp-opts:
      ...
      download-settings:
        server: Q(SERVER_IP)
        port: 443
        tls: true
        servername: Q(REALITY_SNI)
        client-fingerprint: Q(FINGERPRINT)
        reality-opts:
          public-key: Q(REALITY_PUBLIC_KEY)
          short-id: Q(REALITY_SHORT_ID)
        path: Q(XHTTP_PATH)
        mode: auto
        [XPAD] x-padding-* 五键
        reuse-settings: （同上）

  - name: Q(PFX-XHTTP-SPLIT-REALITY-CDN)
    # 外层与 XHTTP-REALITY 相同（上行走 Reality 直连），追加：
    xhttp-opts:
      ...
      download-settings:
        server: Q(XHTTP_DOMAIN)
        port: 443
        tls: true
        alpn: [h2]
        servername: Q(XHTTP_DOMAIN)
        client-fingerprint: Q(FINGERPRINT)
        [ECH] ech-opts: {enable: true, query-server-name: cloudflare-ech.com}
        host: Q(XHTTP_DOMAIN)
        path: Q(XHTTP_PATH)
        mode: auto
        [XPAD] x-padding-* 五键
        reuse-settings: （同上）
```

字段名以 mihomo wiki 为准：<https://wiki.metacubex.one/config/proxies/vless/>、
<https://wiki.metacubex.one/config/proxies/transport/>。实施前用 `mihomo -t -f mihomo.yaml`
（本地下载一份 mihomo 二进制）跑一次真实校验，把校验命令写进 README 的「验证」一节。

## 附录 F：`/etc/nginx/nginx.conf` 接管模板（`nginx_main_config_text`）

```nginx
# Generated by xtun.sh —— 这份文件由 xtun 整体重写，手工改动只在 xtun-user 标记之间保留。
user www-data;
worker_processes auto;
worker_cpu_affinity auto;
worker_rlimit_nofile 1048576;
pid /run/nginx.pid;
error_log /var/log/nginx/error.log;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 65535;
    multi_accept on;
}

$(render_user_block nginx-main "${NGINX_MAIN_CONFIG}")

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    types_hash_max_size 2048;
    server_tokens off;
    keepalive_timeout 65;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:xtun_ssl:16m;
    ssl_session_timeout 1h;

    access_log /var/log/nginx/access.log;
    gzip on;

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;

$(render_user_block nginx-http "${NGINX_MAIN_CONFIG}" "    ")
}
```

## 附录 G：`check-sni` 输出示例

```
$ xtun check-sni www.stanford.edu
Reality 目标域名预检: www.stanford.edu  (target www.stanford.edu:443)
PASS  域名格式        www.stanford.edu
PASS  DNS 解析        171.67.215.200
PASS  TLS 1.3         Protocol TLSv1.3, TLS_AES_128_GCM_SHA256
PASS  X25519          Peer Temp Key: X25519
PASS  HTTP/2 ALPN     h2
PASS  证书链          Verify return code: 0 (ok)
PASS  证书 SAN        DNS:www.stanford.edu
PASS  证书到期        76 天
PASS  CDN 前置        否
PASS  HTTP 跳转       200，无跳转
PASS  HTTP 版本       2
PASS  握手耗时        0.021s
结论: 通过（0 FAIL, 0 WARN）

$ xtun check-sni stanford.edu
...
FAIL  HTTP 跳转       301 -> https://www.stanford.edu/（跨主机跳转，请直接使用 www.stanford.edu）
结论: 不通过（1 FAIL, 0 WARN）；安装时可用 --skip-sni-check 强行跳过
```
