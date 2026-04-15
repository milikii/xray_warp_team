# xray_warp_team

用于快速部署一套和当前机器同思路的方案：

- `VLESS + REALITY + Vision` 直连节点
- `VLESS + XHTTP + TLS + CDN` 节点
- `HAProxy :443` 基于 SNI 分流
- 可选 `Cloudflare WARP` 选择性出站

当前仓库主入口是 `xray-warp-team.sh`。

## 适用范围

- Debian / Ubuntu
- root 用户执行
- XHTTP 节点需要一个 Cloudflare 域名
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

## 非交互示例

```bash
bash xray-warp-team.sh install --non-interactive \
  --server-ip 203.0.113.10 \
  --reality-sni www.scu.edu \
  --reality-target www.scu.edu:443 \
  --xhttp-domain cdn.example.com \
  --xhttp-path /cfup-demo \
  --cert-mode self-signed \
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

## 证书模式

- `self-signed`
  适合先快速起机。Cloudflare SSL/TLS 模式设为 `Full`。
- `existing`
  使用你已经准备好的证书和私钥文件。比如 Cloudflare Origin CA 或 Let's Encrypt。Cloudflare SSL/TLS 模式可设为 `Full (strict)`。

示例：

```bash
bash xray-warp-team.sh install \
  --cert-mode existing \
  --cert-file /root/cert.pem \
  --key-file /root/key.pem
```

## 安装结果

安装完成后，脚本会：

- 输出 `REALITY` 和 `XHTTP` 两个节点 URI
- 写入 Xray 配置到 `/usr/local/etc/xray/config.json`
- 写入 HAProxy 配置到 `/etc/haproxy/haproxy.cfg`
- 写入节点元数据到 `/usr/local/etc/xray/node-meta.env`
- 写入总结文件到 `/root/xray-warp-team-output.md`

你后续可以用下面命令再次查看节点：

```bash
bash xray-warp-team.sh show-links
```

## Cloudflare 侧还需要做的事

XHTTP CDN 节点不是“脚本跑完就全自动生效”，Cloudflare 侧仍然要做：

1. 给你的 `XHTTP` 域名添加 `A` 记录，指向 VPS 公网 IP。
2. 打开 orange-cloud 代理。
3. 根据你的证书模式设置 SSL/TLS：
   `self-signed` 用 `Full`
   `existing` 用 `Full (strict)`

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

## 参考

- Cloudflare 官方无头 Linux 部署文档：
  https://developers.cloudflare.com/cloudflare-one/tutorials/deploy-client-headless-linux/
- Cloudflare One Client 文档：
  https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/cloudflare-one-client/
- Xray 官方仓库：
  https://github.com/XTLS/Xray-core
