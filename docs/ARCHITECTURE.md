# xtun 架构说明

本文讲「为什么这么设计」。操作步骤见 README。

## 请求流图

```text
公网 TCP :443
  |
  v
haproxy（SNI TCP 分流）
  |-- SNI = XHTTP CDN 域名 --> nginx 127.0.0.1:8443 --> xray 127.0.0.1:8001（VLESS + XHTTP）
  `-- 其它 SNI -------------> xray Reality 127.0.0.1:2443
                                |-- 鉴权通过 --> VLESS + Vision / fallbacks 8001
                                `-- 鉴权失败 --> dokodemo 127.0.0.1:2444
                                                  |-- SNI == REALITY_SNI --> 真实目标站
                                                  `-- 其它 SNI --> blackhole

公网 UDP :443（H3 启用时）
  |
  v
nginx（QUIC，TLS 在 nginx 终结）--> xray 127.0.0.1:8001
```

本机端口一览：2443 Reality 入站 / 2444 dokodemo 回落过滤 / 8001 XHTTP 入站 / 8443 nginx TLS（TCP）/ 443 haproxy（TCP）+ nginx（UDP，仅 H3）。

## 为什么有 haproxy

Reality 的目标域是用户指定的第三方权威站点。xray 的 Reality 入站收到 SNI = CDN 域名（XHTTP 域名）的流量时，会按 realitySettings 的逻辑把回落转给远端目标站而不是本机 nginx。所以必须有一个前置 SNI 分流，把「SNI 是自己 CDN 域名」的流量先摘出来交给 nginx，其余（包括无 SNI、随机 SNI 的扫描器）才进 Reality 入站。

没换 nginx stream 模块的原因：haproxy 已有 reload、splice、用户块和测试覆盖，迁移收益不抵风险。

## 为什么 Reality 目标不用自己的域名

Reality 的原理是「偷」目标的 TLS 握手。目标如果指回本机 nginx（「自偷」）：

- 握手特征是自己人，训练过的主动探测者更容易对比出异常；
- 一旦配置失误（比如 SNI 分流漏了），等于把自己的伪装站暴露成 Reality 的回落目标，探测者拿到的响应和真实用户完全一致，反而失去了「偷大站」的掩护价值。

偷权威第三方大站（Stanford 这类教育/政府背景域名）的好处：证书链、ALPN、TLS 指纹与全球真实流量混在一起，且不经过自己的任何其它服务。代价是这个域名必须满足一系列硬性条件（TLS 1.3、X25519、h2、证书覆盖、非 CDN 边缘、无跨主机跳转……），所以 xtun 把 `check-sni` 做成了安装和改 SNI 的硬门禁（12 项检查，见 README「Reality 目标域名要求与预检」）。

## 防跑流量：dokodemo-door 过滤

Xray 官方文档明确指出：Reality 对鉴权失败的流量会转发到 target。如果目标在 CDN 后面，你的服务器就充当了 CDN 的端口转发，被扫描器发现后会偷跑流量。

xtun 采用 Xray-examples 的官方「without being stolen」模板：

- Reality 入站的 `target` 固定指向本机 `dokodemo-door`（127.0.0.1:2444）；
- dokodemo 开启 `sniffing`（`destOverride: tls`，`routeOnly: true`），路由按嗅探出的 SNI 匹配；
- 路由最前两条规则：`SNI == REALITY_SNI` 的回落放行 direct 到真实目标，其余 blackhole。

不配置 `limitFallbackUpload/Download`：官方明言回落限速是一种特征，一键脚本若用必须随机化。有了 SNI 过滤，剩余风险只剩「借你转发到目标站本身」，由 `check-sni` 第 9 项劝阻 CDN 目标缓解。

## 订阅为什么要走 nginx 托管

订阅文件放在 `/root/xtun-subscriptions` 时没人拉得到（脚本是装在 VPS 上的，不是客户端）。托管在 CDN 域名下的 `/sub/<token>/` 路径后，任何客户端都能经 Cloudflare 拉；`Cache-Control: no-store` 保证订阅内容不被边缘缓存；token 可随时 `change-sub-token` 轮换，旧的立刻失效。

## nginx 主配置为什么要接管

`worker_connections` 和 `worker_rlimit_nofile` 只能写在主配置里。xtun 只接管 conf.d 的 server 段时，drop-in 抬上去的 fd 限额会被发行版默认的 `worker_connections 768` 卡死（反代一条连接占两个 fd，实际只够 384 个客户端）。接管受 `NGINX_MAIN_MANAGED` 控制，手工调优写在 `xtun-user:*` 标记之间可以跨重写保留；升级上来的旧节点默认不接管，避免覆盖已有的复杂站点。

## 状态与回滚

- 状态文件 `/usr/local/etc/xray/node-meta.env`（v2，shell 转义 kv，0600）；v1 键只读不写，加载时迁移提示。
- 所有托管变更先开备份会话（`/root/xtun-backups/<时间戳>/`，默认保留 5 份），写盘是原子的（mktemp + mv）；校验或重启失败按文件清单回滚并重启服务。
- 操作日志在 `/var/log/xtun/operations.log`，随 logrotate 轮转。
