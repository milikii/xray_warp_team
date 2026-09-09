# Defaults Template

## Version: vX.X.X

### Global Defaults
| Parameter | Default | Source File | Notes |
|-----------|---------|-------------|-------|
| `log.loglevel` | `warning` | `infra/conf/log.go` | — |

### Inbound Defaults
| Parameter | Default | Source File | Notes |
|-----------|---------|-------------|-------|
| `inbound.listen` | `127.0.0.1` | `infra/conf/router.go` | — |

### Outbound Defaults
| Parameter | Default | Source File | Notes |
|-----------|---------|-------------|-------|
| `outbound.protocol` | `freedom` | `infra/conf/router.go` | — |

### Transport Defaults
| Parameter | Default | Source File | Notes |
|-----------|---------|-------------|-------|
| `transport.tcp.mtu` | `1500` | `transport/internet/tcp/config.go` | Example |

*Populate this file per stable/beta release to track default value evolution.*
