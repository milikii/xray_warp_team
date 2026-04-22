# xray_warp_team

一个面向 Debian / Ubuntu VPS 的一键部署脚本，用来在一台机器上稳定搭建：

- `VLESS + REALITY + Vision` 直连节点
- `VLESS + XHTTP + TLS + CDN + VLESS Encryption` 节点
- `上行 XHTTP + TLS + CDN ｜ 下行 XHTTP + Reality` 上下行分离节点
- `Cloudflare WARP Team` 选择性出站
- `haproxy + nginx + xray` 的混合前置与 `443` 端口复用架构
- 可选 `Cloudflare Origin CA` / `acme.sh + Cloudflare DNS` 证书模式
- 可选 `BBR + fq + RPS/XPS` 网络优化

脚本主入口：

```bash
xray-warp-team.sh
```

安装完成后会自动落到：

```bash
/usr/local/sbin/xray-warp-team
```

对应的脚本 bundle 会放到：

```bash
/usr/local/lib/xray-warp-team
```

命令约定：

- 第一次安装：`bash xray-warp-team.sh`
- 安装完成后的维护：`xray-warp-team`

## 当前脚本架构

当前是“混合前置”架构：

- `haproxy :443`
  - 只负责按 `SNI` 做 TCP 分流
  - `CDN 域名 -> nginx 127.0.0.1:8443`
  - 其它域名 -> `xray reality 127.0.0.1:2443`
- `xray 127.0.0.1:2443`
  - `REALITY + Vision`
  - `fallback -> 127.0.0.1:8001`
  - `target -> 你设置的 Reality 伪装站，比如 www.harvard.edu:443`
- `xray 127.0.0.1:8001`
  - `VLESS + XHTTP`
  - 默认开启 `VLESS Encryption`
- `nginx 127.0.0.1:8443`
  - 给 `CDN 域名` 提供 TLS / HTTP2
  - `/XHTTP_PATH -> grpc_pass 127.0.0.1:8001`
  - `/ -> 伪装站`

也就是说，三节点共享同一个 `443`，但实现方式是：

- `Reality` 由 `haproxy:443 -> xray:2443`
- `XHTTP CDN` 由 `haproxy:443 -> nginx:8443 -> xray:8001`
- `XHTTP 上下行分离` 仍然复用同一套服务端，只是在客户端通过 `downloadSettings` 实现上下行拆分

## 这套脚本适合什么场景

适合：

- 你想一台 VPS 同时提供 `Reality`、`xhttp CDN`、`xhttp split`
- 你需要 `WARP Team` 作为一部分出站
- 你希望后续直接改：
  - `Reality 域名/SNI`
  - `XHTTP 路径`
  - `节点名前缀`
  - `UUID`
  - `WARP 开关`
  - `证书模式`

不适合：

- 非 Debian / Ubuntu 系统
- 不想使用 root
- 想保留自己已有的复杂 `nginx` 网站体系且不希望脚本接管 `nginx`

## 安装前准备

最少需要：

- 一台 Debian / Ubuntu VPS
- root 权限
- 一个用于 `XHTTP CDN` 的 Cloudflare 橙云域名
- 一个证书可覆盖的 `Reality` 域名
  - 推荐同一张通配证书下的灰云子域名
  - 例如：
    - `cdn.example.com` 用于 CDN
    - `reality.example.com` 用于 Reality

如果你要启用 WARP Team，还需要：

- Cloudflare Zero Trust 团队名
- Service Token 的 `Client ID`
- Service Token 的 `Client Secret`

敏感参数建议不要直接写在 shell history 里。当前脚本已经支持：

- 直接用环境变量，例如：`WARP_CLIENT_SECRET=xxx bash xray-warp-team.sh install ...`
- 用 `@文件路径` 读取，例如：`--warp-client-secret @/root/secret.txt`

## 快速开始

现在可以直接用单文件入口启动，脚本会自动处理 bundle：

```bash
curl -fsSL https://raw.githubusercontent.com/milikii/xray_warp_team/main/xray-warp-team.sh -o xray-warp-team.sh
bash xray-warp-team.sh
```

不带参数时会进入菜单。第一次安装一般直接选：

```text
1. 安装或重装
```

说明：

- 如果当前目录已经有完整 `lib/`，脚本会直接本地运行
- 如果当前目录只有单文件入口，脚本会自动拉取完整 bundle 后再执行
- 如果机器上已经装过 `/usr/local/lib/xray-warp-team`，也会优先复用已安装 bundle

### 交互安装失败后怎么继续

交互安装时，脚本会把你已经填过的值先保存到：

```bash
/root/.xray-warp-team-install-draft.env
```

如果中途在预检、下载、证书、WARP 或配置校验阶段失败，再次执行：

```bash
bash xray-warp-team.sh
```

脚本会自动带回上次已经填过的值，不需要从头重新输入。安装成功后，这个 draft 文件会自动删除。

## 最小非交互示例

下面是推荐的最小安装方式：

```bash
bash xray-warp-team.sh install --non-interactive \
  --server-ip 203.0.113.10 \
  --node-label-prefix HKG \
  --reality-sni reality.example.com \
  --xhttp-domain cdn.example.com \
  --xhttp-path /assets/v3 \
  --cert-mode existing \
  --cert-file /etc/ssl/cloudflare/cert.pem \
  --key-file /etc/ssl/cloudflare/key.pem \
  --enable-warp \
  --warp-team your-team \
  --warp-client-id xxxxxxxxx.access \
  --warp-client-secret xxxxxxxxx
```

等价的更安全写法：

```bash
export WARP_CLIENT_SECRET=xxxxxxxxx
bash xray-warp-team.sh install --non-interactive \
  --server-ip 203.0.113.10 \
  --node-label-prefix HKG \
  --reality-sni reality.example.com \
  --xhttp-domain cdn.example.com \
  --xhttp-path /assets/v3 \
  --cert-mode existing \
  --cert-file /etc/ssl/cloudflare/cert.pem \
  --key-file /etc/ssl/cloudflare/key.pem \
  --enable-warp \
  --warp-team your-team \
  --warp-client-id xxxxxxxxx.access
```

如果你明确不需要 WARP：

```bash
bash xray-warp-team.sh install --non-interactive \
  ... \
  --disable-warp
```

如果你明确不想启用 `XHTTP VLESS Encryption`：

```bash
bash xray-warp-team.sh install --non-interactive \
  ... \
  --disable-xhttp-vless-encryption
```

## 当前脚本的运行保证

当前版本已经补上的几个关键行为：

- 持久化管理命令不是单文件裸拷贝，而是 `wrapper + bundle` 结构
- 单文件入口会自动 bootstrap 到完整 bundle，不再要求手动先解压仓库
- `Xray` 核心仍然优先安装最新版本，但会同时下载 release 的 `.dgst` 并校验 `SHA256`
- `Xray / nginx / haproxy` 托管配置使用临时文件生成后再原子替换
- `TLS` 证书和私钥先写 staging，再校验匹配后替换正式文件
- 配置校验或服务重启失败时，会自动回滚最近一次托管变更
- 安装、升级、校验、重启、回滚都会输出阶段日志，便于直接判断卡在哪一步
- 状态文件带 `STATE_VERSION`，脚本读取旧版本状态文件时会给出提示
- 交互安装失败后会保留一份安装 draft，方便再次进入时继续填写
- 安装前会做预检：443 端口占用、CDN 域名解析、Cloudflare Token 在线校验（在相关模式下）
- 启用 WARP 时会额外安装一个健康检查 timer，定期验证本地 WARP SOCKS5 是否可用

## 安装完成后会得到什么

脚本会托管：

- `/usr/local/sbin/xray-warp-team`
- `/usr/local/lib/xray-warp-team`
- `/usr/local/etc/xray/config.json`
- `/etc/nginx/conf.d/xray-warp-team.conf`
- `/etc/systemd/system/xray.service`
- `/usr/local/etc/xray/node-meta.env`
- `/root/xray-warp-team-output.md`

安装成功后会导出 3 个节点：

1. `REALITY + Vision`
2. `XHTTP + TLS + CDN + VLESS Encryption`
3. `上行 XHTTP + TLS + CDN ｜ 下行 XHTTP + Reality`

默认说明：

- `XHTTP` 默认不启用 `ECH`
- 导出的两个 `XHTTP` 分享链接默认不带 `ech=`
- `XHTTP VLESS Encryption` 默认开启
- 默认会给节点名加统一前缀，便于客户端区分机器

## WARP Team 教程

### WARP Team 在这套脚本里做什么

这套脚本里的 WARP 不是“整机全局代理”，而是：

- 让 `Xray` 的一部分目标域名走 `Cloudflare WARP Team`
- 其它流量仍按原规则直连

默认会走 WARP 的目标包括：

- `geosite:google`
- `geosite:youtube`
- `geosite:openai`
- `geosite:netflix`
- `geosite:disney`
- `gemini.google.com`
- `claude.ai`
- `anthropic.com` 及常用 API 域名
- `x.com / twitter.com / t.co / twimg.com`
- `github.com` 和 Copilot 相关域名

Telegram 默认直连。

### 需要准备什么

需要 3 个值：

- `团队名`
- `Client ID`
- `Client Secret`

### 安装时怎么填

交互安装时会问：

- 是否启用选择性 WARP 出站
- Cloudflare Zero Trust 团队名
- Cloudflare 服务令牌 Client ID
- Cloudflare 服务令牌 Client Secret
- 本地 WARP SOCKS5 端口

非交互安装时直接传：

```bash
--warp-team your-team
--warp-client-id xxxxx.access
--warp-client-secret xxxxx
--warp-proxy-port 40000
```

### 装好后如何验证

先看面板：

```bash
xray-warp-team status
```

再看原始服务状态：

```bash
systemctl status --no-pager warp-svc
```

如果要查看当前 MDM 配置：

```bash
sed -n '1,200p' /var/lib/cloudflare-warp/mdm.xml
```

### 以后如何开关 WARP

关闭：

```bash
xray-warp-team change-warp --disable-warp
```

重新启用：

```bash
xray-warp-team change-warp --enable-warp
```

如果要重新指定 WARP Team 参数：

```bash
xray-warp-team change-warp --enable-warp \
  --warp-team your-team \
  --warp-client-id xxxxx.access \
  --warp-client-secret xxxxx \
  --warp-proxy-port 40000
```

启用后还会自动安装：

- `/usr/local/sbin/xray-warp-team-warp-health.sh`
- `xray-warp-team-warp-health.service`
- `xray-warp-team-warp-health.timer`

它会定期探测本地 WARP SOCKS5 是否还能正常获取出口 IP；如果失败，会自动执行 `mdm refresh + restart warp-svc`。

### 维护 WARP 分流规则

查看当前生效规则：

```bash
xray-warp-team change-warp-rules --list
```

新增一个域名：

```bash
xray-warp-team change-warp-rules --add-domain chat.openai.com
```

删除一个域名：

```bash
xray-warp-team change-warp-rules --del-domain github.com
```

恢复到脚本默认规则集合：

```bash
xray-warp-team change-warp-rules --reset-defaults
```

说明：

- 裸域名会自动转成 `domain:` 规则
- 也可以直接传 `geosite:xxx`
- 规则会写入 `/usr/local/etc/xray/warp-domains.list`
- 更新后会自动重写 `xray` 配置并走现有校验 / 重启 / 回滚流程

## 证书模式

### 1. self-signed

适合快速测试。

要求：

- Cloudflare SSL/TLS 设为 `Full`

### 2. existing

适合你已经有证书的情况，比如：

- Cloudflare Origin CA
- Let’s Encrypt

要求：

- Cloudflare SSL/TLS 设为 `Full (strict)`

支持两种输入方式：

1. 直接给本机文件路径
2. 直接粘贴 PEM 内容，由脚本写入

本机已有文件示例：

```bash
bash xray-warp-team.sh install \
  --cert-mode existing \
  --cert-file /etc/ssl/cloudflare/cert.pem \
  --key-file /etc/ssl/cloudflare/key.pem
```

直接传 PEM 内容示例：

```bash
bash xray-warp-team.sh install \
  --cert-mode existing \
  --cert-pem "$(cat /etc/ssl/cloudflare/cert.pem)" \
  --key-pem "$(cat /etc/ssl/cloudflare/key.pem)"
```

### 3. cf-origin-ca

脚本自动向 Cloudflare Origin CA 申请证书。

需要：

- `--cf-zone-id`
- `--cf-api-token`

建议 Token 权限：

- `Zone / SSL and Certificates / Edit`
- `Zone / Zone Settings / Edit`

### 4. acme-dns-cf

通过 `acme.sh + Cloudflare DNS API` 申请公有证书。

需要：

- `--acme-email`
- `--cf-dns-token`

建议 Token 权限：

- `Zone / DNS / Edit`
- `Zone / Zone / Read`

## Cloudflare 侧需要做什么

请手动确认：

1. `CDN 域名`
   - 指向 VPS 公网 IP
   - 打开橙云代理
2. `Reality 域名`
   - 推荐灰云 / DNS only
   - 证书必须覆盖它
3. SSL/TLS 模式：
   - `self-signed` -> `Full`
   - `existing` -> `Full (strict)`
   - `cf-origin-ca` -> `Full (strict)`
   - `acme-dns-cf` -> `Full (strict)`
4. 如果走 Cloudflare CDN 的 `XHTTP`
   - 建议开启 `gRPC`

## 常用命令

### 查看状态

```bash
xray-warp-team status
```

当前状态面板除了 systemd 状态，还会额外显示：

- `443 / 2443 / 8001 / 8443` 监听情况
- 当前证书到期时间
- `WARP` 出口 IP 探测结果
- 当前 `WARP` 规则数量
- 最近一次备份目录
- `xray-warp-team-warp-health.timer` 的运行状态
- 最近一次核心 / WARP 自恢复结果
- 最近一条自恢复历史记录
- 近 1 小时 / 24 小时的核心与 WARP 自恢复次数
- 一个简化的稳定性信号：`稳定 / 观察中 / 高风险`

### 查看原始 systemd 输出

```bash
xray-warp-team status --raw
```

### 一次性运行服务端诊断

```bash
xray-warp-team diagnose
```

这个命令会集中输出：

- `xray / haproxy / nginx / warp-svc` 当前状态
- 关键监听端口 `443 / 2443 / 8001 / 8443`
- `Xray / nginx / haproxy` 配置自检结果
- 本地 `TLS` 握手探测结果
- 最近一次核心 / WARP 自恢复信息
- 最近一条自恢复历史记录
- 近 1 小时 / 24 小时恢复次数
- 稳定性信号

并且：

- 如果关键服务、关键监听端口、配置自检或本地 TLS 探测失败，`diagnose` 会以非 0 退出
- 可以直接拿它做脚本化巡检或外层监控
- 失败时会额外输出按 `服务 / 端口 / 配置 / 连接 / WARP` 分类的摘要，减少排障噪音

### 查看节点链接

```bash
xray-warp-team show-links
```

如果系统里装了 `qrencode`，也可以直接输出二维码：

```bash
xray-warp-team show-links --qr
```

### 修改 REALITY 域名 / SNI

```bash
xray-warp-team change-sni --reality-sni reality.example.com
```

### 修改 XHTTP 路径

```bash
xray-warp-team change-path --xhttp-path /assets/v3
```

### 修改节点名前缀

```bash
xray-warp-team change-label-prefix --node-label-prefix HKG
```

### 轮换 UUID

```bash
xray-warp-team change-uuid
```

只换 REALITY：

```bash
xray-warp-team change-uuid --reality-only
```

只换 XHTTP：

```bash
xray-warp-team change-uuid --xhttp-only
```

`change-*` 命令现在都会输出阶段日志；如果应用新配置后校验失败或重启失败，会自动回滚最近一次托管变更。

### 开关 WARP

```bash
xray-warp-team change-warp --disable-warp
```

```bash
xray-warp-team change-warp --enable-warp
```

### 修改 WARP 分流规则

```bash
xray-warp-team change-warp-rules --add-domain chat.openai.com
```

### 切换证书模式

```bash
xray-warp-team change-cert-mode --cert-mode existing \
  --cert-file /etc/ssl/cloudflare/cert.pem \
  --key-file /etc/ssl/cloudflare/key.pem
```

### 续期 / 刷新当前证书

```bash
xray-warp-team renew-cert
```

说明：

- `self-signed`：重新生成一张新的自签名证书
- `existing`：需要重新提供证书来源，例如 `--cert-file/--key-file` 或 `--cert-pem/--key-pem`
- `cf-origin-ca`：重新向 Cloudflare Origin CA 申请
- `acme-dns-cf`：重新执行 `acme.sh` 的申请 / 安装流程

敏感参数仍建议优先使用环境变量或 `@文件路径`：

```bash
CF_DNS_TOKEN=xxxxxxxx xray-warp-team renew-cert --non-interactive
```

### 升级 Xray 核心

```bash
xray-warp-team upgrade
```

说明：

- 仍然优先跟随 `XTLS/Xray-core` 最新 release
- 下载 zip 后会校验对应 `.dgst` 里的 `SHA256`
- 如果升级后的配置校验失败，或 `xray` 重启失败，会自动回滚 `xray` 二进制和资源文件

### 重启服务

```bash
xray-warp-team restart
```

### 更新脚本本身

```bash
xray-warp-team update-script
```

说明：

- 会下载最新脚本 bundle 并覆盖 `/usr/local/lib/xray-warp-team`
- 会同时更新 `/usr/local/sbin/xray-warp-team` wrapper
- 如果 bundle 安装失败，会自动回滚到更新前的持久化脚本文件

### 抢修权限

如果你遇到：

- `xray.service` 起不来
- `status=23`
- `config.json / cert.pem / key.pem / access.log / error.log` 权限不对

先直接跑：

```bash
xray-warp-team repair-perms
```

这个命令会：

- 修正 `config.json`
- 修正证书目录和证书文件
- 修正 `/var/log/xray`
- 修正 `access.log / error.log`
- 尝试重启 `xray`、`haproxy` 与 `nginx`

### 卸载脚本托管文件

```bash
xray-warp-team uninstall --yes
```

说明：

- 会删除脚本托管的配置、证书、systemd unit、bundle 和输出文件
- 不会卸载已经装上的软件包
- 每次卸载前会先把托管文件备份到本次 `BACKUP_DIR`

## 常见问题

### 1. Reality 用 IP 还是域名

建议：

- 稳定优先：客户端地址直接用公网 IP
- 维护优先：客户端地址用灰云域名

当前脚本默认导出的 `Reality` 节点地址是公网 IP，`serverName/SNI` 则使用你设置的 Reality 域名。

### 2. 为什么 XHTTP 默认像正常网站资源路径

脚本默认会从这些候选里随机选一个：

- `/assets/v3`
- `/static/app`
- `/images/webp`
- `/fonts/inter`
- `/media/cache`

这样比早期 `/cfup-随机串` 更自然，也更好记。

### 3. 为什么默认不启用 ECH

因为在很多网络环境里，尤其中国网络下：

- `ECH` 依赖额外 DNS / DoH 查询
- 容易引入额外不稳定性

所以脚本默认：

- `XHTTP` 不启用 `ECH`
- 导出的分享链接不带 `ech=`

如果你后续明确要测，再自己手动加。

### 4. 现在的三节点里，split 为什么不用额外服务端入站

因为这套架构里：

- 服务端只有一套 `xhttp` 入站
- “上下行分离”是客户端通过 `downloadSettings` 实现的

也就是说：

- 节点 2 和 节点 3 共用同一个服务端 `xhttp` 入站
- 区别在客户端的下载链路选择

### 5. Cloudflare 返回 521 / 525 怎么办

先分层排查：

1. `xray` 是否真的运行
2. `haproxy` 是否真的运行
3. `nginx` 是否真的运行
4. `xray` 是否监听了 `2443` 和 `8001`
5. `nginx` 是否监听了 `127.0.0.1:8443`
6. `haproxy` 是否监听了 `:443`
7. Cloudflare SSL/TLS 模式是否正确
8. 证书是否覆盖 `CDN 域名`

建议第一步先跑：

```bash
xray-warp-team repair-perms
xray-warp-team status
```

如果刚做过 `install`、`change-*`、`upgrade`，也建议顺手看一下终端里最后几条 `[步骤] / [完成] / [警告]` 输出。当前脚本已经会明确告诉你失败是出在：

- 下载和校验 `Xray` 核心
- `Xray` 配置校验
- `nginx` 配置校验
- `haproxy` 配置校验
- 服务重启
- 自动回滚

## 网络优化说明

如果启用网络优化，脚本会尝试配置：

- `tcp_congestion_control = bbr`
- `default_qdisc = fq`
- 调整 `rmem/wmem/somaxconn/tcp_fastopen/tcp_mtu_probing`
- 通过 systemd oneshot 在开机后重新应用 `fq`、`RPS`、`XPS`

相关文件：

- `/etc/sysctl.d/98-xray-warp-team-net.conf`
- `/usr/local/sbin/xray-warp-team-net-optimize.sh`
- `xray-warp-team-net-optimize.service`

## 客户端导出

当前输出文件除了原始 `vless://` 分享链接，也会直接附带：

- `Clash Meta / Mihomo` 的结构化片段（`REALITY`、`XHTTP-CDN`）
- `sing-box` 的 `outbound` JSON 片段（`REALITY`、`XHTTP-CDN`）

说明：

- `XHTTP-SPLIT` 节点的客户端兼容差异更大，所以当前仍然建议直接使用脚本生成的原始分享链接导入

## 参考

- Cloudflare 官方无头 Linux 部署文档  
  https://developers.cloudflare.com/cloudflare-one/tutorials/deploy-client-headless-linux/
- Cloudflare One Client 文档  
  https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/cloudflare-one-client/
- Xray 官方讨论 `#4118`  
  https://github.com/XTLS/Xray-core/discussions/4118
- Xray 官方仓库  
  https://github.com/XTLS/Xray-core
