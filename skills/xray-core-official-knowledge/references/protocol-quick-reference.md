# Protocol Quick Reference

> Loaded on demand when the user asks about protocol-specific behavior.
> This document summarizes official protocol support in Xray Core.

## Supported Protocols

| Protocol | Role | Security Layer | Notes |
|----------|------|----------------|-------|
| VLESS | Inbound / Outbound | TLS, REALITY, XTLS | Recommended; lightweight header |
| VMess | Inbound / Outbound | TLS, AEAD | Legacy; MD5 deprecation timeline |
| Trojan | Inbound / Outbound | TLS | Trojan-GFW compatible |
| Shadowsocks | Inbound / Outbound | AEAD / none | Multiple ciphers |
| Socks | Inbound / Outbound | none | 4/4a/5 support |
| HTTP | Inbound / Outbound | none | HTTP proxy |
| Dokodemo-door | Inbound only | — | Transparent proxy |
| Freedom | Outbound only | — | Direct outbound |
| Blackhole | Outbound only | — | Drop traffic |
| DNS | Outbound only | — | Internal DNS resolver |
| Loopback | Outbound only | — | Internal routing loop |

## Protocol Selection Guidance

Use **VLESS** for new deployments unless legacy compatibility requires VMess.
Use **Trojan** when upstream ecosystem expects Trojan-GFW semantics.
Use **Shadowsocks** for lightweight, non-Xray clients.

## Version Notes

- VMess MD5 was deprecated; AEAD is now default.
- VLESS `encryption` field behavior changed across versions; see `extracted/parameters/encryption.yaml`.
