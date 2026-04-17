# xray_warp_team

一个面向 Debian / Ubuntu VPS 的一键部署脚本，用来快速搭一套：

- `VLESS + REALITY + Vision` 直连节点
- `VLESS + XHTTP + TLS + CDN` 节点
- `HAProxy :443` 基于 SNI 分流
- 可选 `Cloudflare WARP Team` 选择性出站
- 可选 `Cloudflare Origin CA` / `acme.sh + Cloudflare DNS` 证书模式
- 可选 `BBR + fq + RPS/XPS` 网络优化

脚本主入口：

```bash
xray-warp-team.sh
```

安装完成后，脚本会自动落到：

```bash
/usr/local/sbin/xray-warp-team
```

后续维护直接用这个命令即可。

## 这套脚本适合什么场景

适合：

- 你想在一台 VPS 上同时提供 `REALITY` 和 `XHTTP CDN`
- 你希望脚本统一生成配置、systemd 服务、HAProxy 分流、节点链接
- 你需要 `Cloudflare WARP Team` 作为一部分出站
- 你希望后续可以直接改 `SNI / 路径 / UUID / WARP / 证书模式`

不适合：

- 非 Debian / Ubuntu 系统
- 不想使用 root
- 想做复杂多站点反代编排

## 安装前准备

最少需要：

- 一台 Debian / Ubuntu VPS
- root 权限
- 一个用于 `XHTTP CDN` 的 Cloudflare 域名

如果你要启用 WARP Team，还需要：

- Cloudflare Zero Trust 团队名
- Service Token 的 `Client ID`
- Service Token 的 `Client Secret`

如果你要用证书模式：

- `self-signed`
  不需要额外准备，Cloudflare SSL/TLS 设为 `Full`
- `existing`
  你已经有证书和私钥，比如 Cloudflare Origin CA 或 Let’s Encrypt
- `cf-origin-ca`
  需要 Cloudflare API Token 和 Zone ID
- `acme-dns-cf`
  需要 Cloudflare DNS API Token 和 ACME 邮箱

## 快速开始

拉脚本并运行：

```bash
curl -fsSL https://raw.githubusercontent.com/milikii/xray_warp_team/main/xray-warp-team.sh -o xray-warp-team.sh
bash xray-warp-team.sh
```

不带参数时会进入菜单。第一次安装一般直接选：

```text
1. 安装或重装
```

如果你偏好非交互安装，也可以：

```bash
bash xray-warp-team.sh install --non-interactive \
  --server-ip 203.0.113.10 \
  --node-label-prefix HKG \
  --reality-sni www.scu.edu \
  --reality-target www.scu.edu:443 \
  --xhttp-domain cdn.example.com \
  --xhttp-path /assets/v3 \
  --cert-mode existing \
  --cert-file /etc/ssl/cloudflare/cert.pem \
  --key-file /etc/ssl/cloudflare/key.pem \
  --warp-team your-team \
  --warp-client-id xxxxxxxxx.access \
  --warp-client-secret xxxxxxxxx
```

如果你明确不想启用 WARP：

```bash
bash xray-warp-team.sh install --non-interactive \
  ... \
  --disable-warp
```

## 安装完成后会得到什么

脚本会生成并托管：

- `/usr/local/etc/xray/config.json`
- `/etc/haproxy/haproxy.cfg`
- `/etc/systemd/system/xray.service`
- `/usr/local/etc/xray/node-meta.env`
- `/root/xray-warp-team-output.md`

安装成功后，你会得到两条分享链接：

- `REALITY`
- `XHTTP CDN`

默认说明：

- `XHTTP` 默认不启用 `ECH`
- 导出的 `XHTTP` 分享链接默认不带 `ech=` 参数
- 默认会给节点名加统一前缀，便于在客户端区分机器

## WARP Team 教程

这是本 README 里最重要的补充部分。

### WARP Team 是做什么的

这套脚本里的 WARP 不是“全局代理整台机器”，而是：

- 让 `Xray` 的部分目标域名走 `Cloudflare WARP Team`
- 其它流量仍按原本规则直连

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

Telegram 相关域名默认直连。

### 你需要准备什么

需要 3 个值：

- `团队名`
- `Client ID`
- `Client Secret`

### 在哪里获取

在 Cloudflare Zero Trust 后台创建一个 Service Token，拿到：

- `Client ID`
- `Client Secret`

团队名就是你 Zero Trust 的组织名。

### 安装时怎么填

交互安装时，脚本会问：

- `是否启用选择性 WARP 出站`
- `Cloudflare Zero Trust 团队名`
- `Cloudflare 服务令牌 Client ID`
- `Cloudflare 服务令牌 Client Secret`
- `本地 WARP SOCKS5 端口`

非交互安装时直接传：

```bash
--warp-team your-team
--warp-client-id xxxxx.access
--warp-client-secret xxxxx
--warp-proxy-port 40000
```

### 装好后如何验证

先看服务状态：

```bash
xray-warp-team status
```

或者看原始状态：

```bash
systemctl status --no-pager warp-svc
```

如果需要看当前 MDM 配置：

```bash
sed -n '1,200p' /var/lib/cloudflare-warp/mdm.xml
```

### 以后怎么开关 WARP

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

## 证书模式说明

### 1. self-signed

适合快速启动测试环境。

要求：

- Cloudflare SSL/TLS 模式设为 `Full`

### 2. existing

适合你已经准备好证书的情况，比如：

- Cloudflare Origin CA
- Let’s Encrypt

要求：

- Cloudflare SSL/TLS 模式设为 `Full (strict)`

支持两种输入方式：

1. 直接给本机文件路径
2. 直接粘贴 PEM 内容，由脚本写入

本机已有文件：

```bash
bash xray-warp-team.sh install \
  --cert-mode existing \
  --cert-file /etc/ssl/cloudflare/cert.pem \
  --key-file /etc/ssl/cloudflare/key.pem
```

直接传 PEM 内容：

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

脚本不会替你自动把整套 DNS 记录和代理状态都配好，所以还要手动确认：

1. 给 `XHTTP` 域名添加 `A` 记录，指向 VPS 公网 IP
2. 打开橙云代理
3. 根据证书模式设置 Cloudflare SSL/TLS：
   - `self-signed` -> `Full`
   - `existing` -> `Full (strict)`
   - `cf-origin-ca` -> `Full (strict)`
   - `acme-dns-cf` -> `Full (strict)`

## 常用命令

### 查看状态

```bash
xray-warp-team status
```

### 查看原始 systemd 输出

```bash
xray-warp-team status --raw
```

### 查看节点链接

```bash
xray-warp-team show-links
```

### 修改 REALITY 的 SNI

```bash
xray-warp-team change-sni --reality-sni www.stanford.edu
```

### 修改 XHTTP 路径

```bash
xray-warp-team change-path --xhttp-path /assets/v3
```

### 修改节点名称前缀

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

### 切换证书模式

```bash
xray-warp-team change-cert-mode --cert-mode existing \
  --cert-file /etc/ssl/cloudflare/cert.pem \
  --key-file /etc/ssl/cloudflare/key.pem
```

### 升级 Xray 核心

```bash
xray-warp-team upgrade
```

### 重启服务

```bash
xray-warp-team restart
```

### 抢修权限

这是这套脚本里非常重要的维护命令。

如果你遇到：

- `xray.service` 启不来
- `status=23`
- `haproxy` 里看到 `<NOSRV>`
- `config.json` / `cert.pem` / `key.pem` / `access.log` 权限不对

直接先跑：

```bash
xray-warp-team repair-perms
```

这个命令会：

- 修正 `config.json`
- 修正证书目录和证书文件
- 修正 `/var/log/xray`
- 修正 `access.log` / `error.log`
- 然后尝试重启 `xray` 和 `haproxy`

### 卸载脚本托管文件

```bash
xray-warp-team uninstall --yes
```

## 常见问题

### 1. REALITY 用 IP 还是域名

建议：

- 稳定优先：直接用公网 IP
- 维护优先：用灰云域名

不要：

- 让 REALITY 走 Cloudflare 橙云代理
- 让 REALITY 和 XHTTP CDN 共用橙云域名

### 2. XHTTP 默认路径为什么像正常网站资源

脚本默认会从几条更像正常站点资源路径的候选里随机选一个，例如：

- `/assets/v3`
- `/static/app`
- `/images/webp`
- `/fonts/inter`
- `/media/cache`

这样比早期那种 `/cfup-随机串` 更好记，也更自然。

### 3. 为什么默认不启用 ECH

因为在很多网络环境里，尤其中国网络下：

- `ECH` 依赖额外的 DNS / DoH 查询
- 容易引入额外的不稳定性

所以现在脚本默认：

- `XHTTP` 不启用 `ECH`
- 导出的分享链接不带 `ech=`

如果你后续明确要测，再自己手动加。

### 4. Cloudflare 返回 525 怎么办

`525` 的意思通常是：

- Cloudflare 到你的源站 TLS 握手失败

优先检查：

1. 本机 `xray` 是否真的运行
2. `haproxy` 是否真的运行
3. 证书是否覆盖 `XHTTP` 域名
4. Cloudflare SSL/TLS 模式是否正确
5. 本机权限是否异常

建议第一步先跑：

```bash
xray-warp-team repair-perms
xray-warp-team status
```

### 5. 为什么 change-* 依赖状态文件

因为脚本需要从：

- `/usr/local/etc/xray/node-meta.env`
- `/root/xray-warp-team-output.md`

回读当前参数，才能安全地做增量修改。

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

## 参考

- Cloudflare 官方无头 Linux 部署文档  
  https://developers.cloudflare.com/cloudflare-one/tutorials/deploy-client-headless-linux/
- Cloudflare One Client 文档  
  https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/cloudflare-one-client/
- Xray 官方仓库  
  https://github.com/XTLS/Xray-core
