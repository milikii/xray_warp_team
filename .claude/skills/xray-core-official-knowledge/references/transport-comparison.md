# Transport Layer Comparison

> Loaded on demand when the user asks about transport selection or behavior.

## Overview

| Transport | Layer | Multiplex | Header Obfuscation | Maturity | Notes |
|-----------|-------|-----------|--------------------|----------|-------|
| TCP | L4 | No | No | Stable | Raw; often combined with TLS/REALITY |
| WebSocket | L7 | No | No | Stable | HTTP upgrade; CDN-friendly |
| HTTP/2 (h2) | L7 | Yes | No | Stable | Multiplex over single TLS connection |
| gRPC | L7 | Yes | No | Stable | HTTP/2 based; streaming semantics |
| mKCP | L4 | No | Yes | Stable | KCP-based; high overhead |
| QUIC | L4 | Yes | No | Stable | UDP-based; built-in encryption |
| XHTTP | L7 | Yes | Configurable | Stable/Experimental | Splitted/stream-one upload modes |
| REALITY | L4/L5 | No | Yes | Stable | TLS fingerprint mimicry |

## Security Pairing

| Transport | Recommended Security | Incompatible With |
|-----------|---------------------|-------------------|
| TCP | TLS, REALITY, XTLS | — |
| WebSocket | TLS | REALITY (direct) |
| gRPC | TLS | REALITY (direct) |
| XHTTP | TLS, REALITY | — |

## Key Parameters by Transport

### XHTTP
- `mode`: `auto` | `packet-up` | `stream-up` | `stream-one`
- `extra`: headers, paths, method overrides
- Server/client symmetric requirements vary by mode.

### REALITY
- `dest`: target server to mimic
- `serverNames`: SNI whitelist
- `privateKey` / `publicKey`: key pair for handshake
- `shortIds`: client authorization tokens

## Source References
- `source/transport/` for implementation details.
- `extracted/parameters/` for per-field records.
