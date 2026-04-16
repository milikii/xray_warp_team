# xray_warp_team

用于快速部署一套和当前机器同思路的方案：

- `VLESS + REALITY + Vision` 直连节点
- `VLESS + XHTTP + TLS + CDN` 节点
- `HAProxy :443` 基于 SNI 分流
- 可选 `Cloudflare Origin CA API` 自动签发并导入证书
- 可选 `acme.sh + Cloudflare DNS API` 公有证书模式
- 默认生成 `XHTTP + CDN + ECH` 的 Xray 客户端 JSON 片段
- 可选 `Cloudflare WARP` 选择性出站
- 可选 `BBR + fq + RPS/XPS` 网络优化

当前仓库主入口是 `xray-warp-team.sh`。

## 适用范围

- Debian / Ubuntu
- root 用户执行
- XHTTP 节点需要一个 Cloudflare 域名
- 如果使用 `cf-origin-ca`，需要 Cloudflare API token 和 zone id
- 如果使用 `acme-dns-cf`，需要 Cloudflare DNS API token 和 acme 邮箱
- 如果启用 WARP，需要 Cloudflare Zero Trust 的 `team name`、`client id`、`client secret`

## 快速使用

先把脚本拉到新 VPS：

```bash
curl -fsSL https://raw.githubusercontent.com/milikii/xray_warp_team/main/xray-warp-team.sh -o xray-warp-team.sh
bash xray-warp-team.sh
```

不带参数会进入一个简单菜单，选择 `Install or reinstall` 后按提示填写参数。

也可以直接进入安装：

```bash
bash xray-warp-team.sh install
```

常用维护命令：

```bash
bash xray-warp-team.sh status
bash xray-warp-team.sh status --raw
bash xray-warp-team.sh upgrade
bash xray-warp-team.sh change-uuid
bash xray-warp-team.sh change-sni --reality-sni www.stanford.edu
bash xray-warp-team.sh change-path --xhttp-path /cfup-new
bash xray-warp-team.sh change-cert-mode --cert-mode self-signed
bash xray-warp-team.sh uninstall --yes
```

## 非交互示例

```bash
bash xray-warp-team.sh install --non-interactive \
  --server-ip 203.0.113.10 \
  --reality-sni www.scu.edu \
  --reality-target www.scu.edu:443 \
  --xhttp-domain cdn.example.com \
  --xhttp-path /cfup-demo \
  --cert-mode self-signed \
  --enable-net-opt \
  --disable-warp
```

如果启用 WARP：

```bash
bash xray-warp-team.sh install --non-interactive \
  --server-ip 203.0.113.10 \
  --reality-sni www.scu.edu \
  --reality-target www.scu.edu:443 \
  --xhttp-domain cdn.example.com \
  --xhttp-path /cfup-demo \
  --cert-mode self-signed \
  --enable-warp \
  --warp-team your-team \
  --warp-client-id xxxxxxxxx.access \
  --warp-client-secret xxxxxxxxx
```

如果使用 `acme-dns-cf`：

```bash
bash xray-warp-team.sh install --non-interactive \
  --server-ip 203.0.113.10 \
  --reality-sni www.scu.edu \
  --reality-target www.scu.edu:443 \
  --xhttp-domain cdn.example.com \
  --xhttp-path /cfup-demo \
  --cert-mode acme-dns-cf \
  --acme-email you@example.com \
  --cf-dns-token your_cloudflare_dns_token \
  --enable-net-opt \
  --disable-warp
```

## 证书模式

- `self-signed`
  适合先快速起机。Cloudflare SSL/TLS 模式设为 `Full`。
- `existing`
  使用你已经准备好的证书和私钥文件。比如 Cloudflare Origin CA 或 Let's Encrypt。Cloudflare SSL/TLS 模式可设为 `Full (strict)`。
- `cf-origin-ca`
  脚本在 VPS 上本地生成私钥和 CSR，再调用 Cloudflare Origin CA API 自动签发证书并落到 Xray 使用的位置。脚本会尝试把该 zone 的 SSL/TLS 模式切到 `Full (strict)`。
- `acme-dns-cf`
  使用 `acme.sh + Cloudflare DNS API` 做 DNS-01 验证，向公有 ACME CA 申请证书，默认为 `Let's Encrypt`。脚本会把证书安装到 Xray 使用路径，并配置自动续期后的 reload。

示例：

```bash
bash xray-warp-team.sh install \
  --cert-mode existing \
  --cert-file /root/cert.pem \
  --key-file /root/key.pem
```

`cf-origin-ca` 示例：

```bash
bash xray-warp-team.sh install \
  --cert-mode cf-origin-ca \
  --cf-zone-id your_zone_id \
  --cf-api-token your_cloudflare_api_token
```

建议给 token 至少这些权限：

- `Zone / SSL and Certificates / Edit`
- `Zone / Zone Settings / Edit`

`acme-dns-cf` 示例：

```bash
bash xray-warp-team.sh install \
  --cert-mode acme-dns-cf \
  --acme-email you@example.com \
  --cf-dns-token your_cloudflare_dns_token
```

如果你想显式指定 ACME CA：

```bash
bash xray-warp-team.sh install \
  --cert-mode acme-dns-cf \
  --acme-email you@example.com \
  --acme-ca letsencrypt \
  --cf-dns-token your_cloudflare_dns_token
```

`acme-dns-cf` 模式建议 token 至少具备：

- `Zone / DNS / Edit`
- `Zone / Zone / Read`

## 安装结果

安装完成后，脚本会：

- 输出 `REALITY` 和 `XHTTP` 两个节点 URI
- 写入 Xray 配置到 `/usr/local/etc/xray/config.json`
- 写入 HAProxy 配置到 `/etc/haproxy/haproxy.cfg`
- 写入节点元数据到 `/usr/local/etc/xray/node-meta.env`
- 写入总结文件到 `/root/xray-warp-team-output.md`
- 额外生成 `REALITY` 客户端 JSON：`/root/xray-reality-client.json`
- 额外生成 `XHTTP + CDN + ECH` 客户端 JSON：`/root/xray-xhttp-cdn-ech-client.json`

你后续可以用下面命令再次查看节点：

```bash
bash xray-warp-team.sh show-links
```

注意：

- 标准 `VLESS URI` 不能完整表达 `ECH` 参数。
- 所以如果你要在 `Xray` 客户端里用 `XHTTP + CDN + ECH`，优先使用脚本生成的 `/root/xray-xhttp-cdn-ech-client.json`。

也可以直接做后续维护：

- `bash xray-warp-team.sh upgrade`
  更新 Xray-core 二进制和 `geoip/geosite` 资源。
- `bash xray-warp-team.sh change-uuid`
  重新生成 `REALITY` 和 `XHTTP` 两个 UUID，并自动重写配置和输出链接。
- `bash xray-warp-team.sh change-uuid --reality-only`
  只轮换 REALITY UUID。
- `bash xray-warp-team.sh change-uuid --xhttp-only`
  只轮换 XHTTP UUID。
- `bash xray-warp-team.sh change-sni --reality-sni www.stanford.edu`
  修改 REALITY 的可见 SNI；如果原来的 target 跟着旧 SNI，脚本会默认一起改成新 SNI 的 `:443`。
- `bash xray-warp-team.sh change-path --xhttp-path /cfup-new`
  修改 XHTTP 的路径。
- `bash xray-warp-team.sh change-cert-mode --cert-mode acme-dns-cf --xhttp-domain cdn.example.com`
  切换证书模式，也可以顺手改 XHTTP CDN 域名。
- `bash xray-warp-team.sh uninstall --yes`
  停掉服务并删除脚本托管的文件，但默认保留已安装的系统包。

`change-uuid` 依赖脚本之前生成的状态文件和当前配置，适合这套脚本安装出来的节点。

脚本当前对 `XHTTP CDN` 默认按 `ECH` 思路导出客户端配置，使用：

- `echConfigList = https://1.1.1.1/dns-query`
- `echForceQuery = none`

这是按官方文档取的更稳默认值：

- `echForceQuery = full`
  没拿到有效 ECH Config 时会直接失败。
- `echForceQuery = none`
  查询失败时会回退，不会因为 ECH 查询失败直接断开。

`change-cert-mode` 如果切到：

- `existing`
  需要同时提供新的 `--cert-file` 和 `--key-file`。
- `cf-origin-ca`
  需要提供 `--cf-zone-id` 和 `--cf-api-token`。
- `acme-dns-cf`
  需要提供 `--acme-email` 和 `--cf-dns-token`。

## Cloudflare 侧还需要做的事

XHTTP CDN 节点不是“脚本跑完就全自动生效”，Cloudflare 侧仍然要做：

1. 给你的 `XHTTP` 域名添加 `A` 记录，指向 VPS 公网 IP。
2. 打开 orange-cloud 代理。
3. 根据你的证书模式设置 SSL/TLS：
   `self-signed` 用 `Full`
   `existing` 用 `Full (strict)`
   `cf-origin-ca` 用 `Full (strict)`，脚本会尝试自动设置
   `acme-dns-cf` 用 `Full (strict)`

## WARP 说明

启用 WARP 时，脚本会安装 `cloudflare-warp`，并按当前方案写入 MDM 配置，默认本地 SOCKS5 端口为 `40000`。

脚本当前默认把这些域名流量走 WARP：

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

## 网络优化

脚本默认可开启一套偏保守的优化：

- `tcp_congestion_control = bbr`
- `default_qdisc = fq`，如果内核暴露该项
- 调整 `rmem/wmem/somaxconn/tcp_fastopen/tcp_mtu_probing`
- 通过 systemd oneshot 在开机后重新应用 `fq`、`RPS`、`XPS`

相关文件：

- `/etc/sysctl.d/98-xray-warp-team-net.conf`
- `/usr/local/sbin/xray-warp-team-net-optimize.sh`
- `xray-warp-team-net-optimize.service`

## 参考

- Cloudflare 官方无头 Linux 部署文档：
  https://developers.cloudflare.com/cloudflare-one/tutorials/deploy-client-headless-linux/
- Cloudflare One Client 文档：
  https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/cloudflare-one-client/
- Xray 官方仓库：
  https://github.com/XTLS/Xray-core
