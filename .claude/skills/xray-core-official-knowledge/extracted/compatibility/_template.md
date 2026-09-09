# Compatibility Matrix Template

## Version: vX.X.X

### Cross-Parameter Constraints

| Parameter A | Parameter B | Relationship | Error if Violated | Source |
|-------------|-------------|--------------|-------------------|--------|
| `security: reality` | `network: ws` | Incompatible | Yes | `infra/conf/transport.go` |
| `security: xtls` | `flow: xtls-rprx-vision` | Required | Yes | `infra/conf/vless.go` |

### Client-Server Symmetry Requirements

| Parameter | Must Match | Server-Only | Client-Only | Notes |
|-----------|------------|-------------|-------------|-------|
| `id` (VLESS) | Yes | No | No | UUID must match |
| `privateKey` (REALITY) | No | Yes | No | Server holds private key |
| `publicKey` (REALITY) | Yes* | No | Yes* | Client needs server's public key |

### Version Compatibility

| Config Feature | Minimum Server Version | Minimum Client Version | Notes |
|----------------|------------------------|------------------------|-------|
| XHTTP `stream-one` | v24.11.x | v24.11.x | Both must support |
| REALITY | v1.8.0 | v1.8.0 | Initial support version |
