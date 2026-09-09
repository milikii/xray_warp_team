---
name: xray-core-official-knowledge
description: >
  Xray Core Official Knowledge Skill. A versioned knowledge base built from
  official Xray Core documentation, source code, releases, commits, and
  maintainer discussions. Use this skill when answering questions about Xray
  Core configuration, protocol parameters (VLESS, VMess, Trojan, XHTTP,
  REALITY, TLS, WebSocket, gRPC), transport settings, routing, DNS, defaults,
  deprecations, version changes, or when generating server/client configs.
  This skill ensures answers are grounded in official sources rather than
  community templates or guesswork.
license: MIT
metadata:
  snapshot_policy: versioned
  current_stable: v26.3.27
  current_beta: v26.9.9
  last_sync: "2026-09-09"
  repository: https://github.com/XTLS/Xray-core
---

# Xray Core Official Knowledge Skill

> **Purpose**: Enable the agent to answer Xray Core questions at the level of
> an official engineering knowledge assistant — citing documentation, source
> code, release notes, and commit history — rather than relying on generic
> community tutorials or hallucinated defaults.

---

## When to Use This Skill

Load this skill when the user asks anything related to:

- Xray Core configuration fields, structures, or semantics
- Protocol specifics: VLESS, VMess, Trojan, Socks, HTTP, Shadowsocks
- Transport specifics: XHTTP, REALITY, TLS, WebSocket, gRPC, TCP, mKCP, QUIC
- Routing, DNS, observability, or API settings
- Parameter defaults, validation rules, or deprecation status
- Version-specific behavior, compatibility, or migration
- Server/client symmetric requirements for any setting
- Troubleshooting based on source-code behavior

Do **not** use this skill to claim a configuration is "optimal" for a specific
network path unless you also note that real-world testing is required.

---

## Knowledge Base Architecture

This skill is organized into four layers. When answering, prefer lower-numbered
layers for factual claims; use higher layers only when lower layers are silent.

### Confidence tiers (read this first)

- **Primary sources (ground truth):** `docs/` (official documentation snapshot)
  and `source/` (Xray-core source code snapshot). Every factual claim should
  trace back here.
- **Human summaries (verify before citing):** `extracted/`, `changelog/`, and
  `citations/` are hand-written digests. Historical revisions of these files
  contained errors (e.g. reversed `dest`/`target` and `publicKey`/`password`
  rename directions, and `allowInsecure` described as removed when it is only
  deprecated). Before citing anything from these layers, confirm it against
  `docs/stable/config/` or `source/`.

### Layer 1 — Official Documentation (`docs/`)

- `docs/stable/` — Documentation matching the latest **stable** release.
- `docs/beta/` — Documentation matching the latest **beta** or pre-release.
- `docs/archived/` — Snapshots of documentation for past major versions.

Usage: Primary source for "what does this field do?" and "how is the config
structured?"

### Layer 2 — Source Code (`source/`)

- `source/config/` — Configuration struct definitions, default values, and
  validation logic extracted from `XTLS/Xray-core`.
- `source/transport/` — Transport layer implementations (XHTTP, REALITY, etc.).
- `source/releases/` — Release metadata and asset notes.
- `source/commits/` — Relevant commit messages and diffs for key changes.

Usage: Use this layer to answer:
- What is the actual default value in code?
- Does this parameter affect client, server, or both?
- What is the validation logic?
- Are there hidden constraints between fields?

### Layer 3 — Version & Changelog (`changelog/`)

- Per-version changelogs generated from release notes and commit history.
- Tracks: field additions, removals, default changes, behavior changes,
  compatibility breaks, performance changes, security fixes.

Usage: Bind every claim to a version or commit range. Avoid stating behavior
without noting the version it applies to.

### Layer 4 — Maintainer Intent (`citations/`)

- Extracted maintainer notes from PRs, Issues, release notes, and code comments.
- Every entry is tagged with confidence level:
  - `official-statement` — Directly stated by maintainers in official channels.
  - `source-confirmed` — Behavior is unambiguous in source code.
  - `maintainer-suggestion` — Recommended by maintainers but not enforced.
  - `inferred-from-source` — Reasonable inference; note uncertainty.
  - `community-experience` — Community report; do not present as official fact.

Usage: Distinguish "the author said this" from "the code does this" from
"people online report this."

---

## Extracted Reference Data (`extracted/`)

Pre-structured data for fast lookup. Each parameter should eventually have a
YAML record in `extracted/parameters/` following this schema:

```yaml
name: exampleParameter
version_introduced: vX.X.X
version_deprecated: ""
version_removed: ""
default: "official-default"
server_client: server-and-client  # server-only | client-only | server-and-client
status: stable  # stable | experimental | deprecated | removed
effect:
  - transport
  - performance
compatibility:
  - requires-other-setting
source:
  docs: "official-doc-url"
  code: "repository-path"
  commit: "commit-sha"
notes:
  - "official-maintainer-note"
confidence: source-confirmed
```

Additional directories:
- `extracted/defaults/` — Aggregated default values per version.
- `extracted/compatibility/` — Cross-parameter constraints and requirements.
- `extracted/deprecations/` — Timeline of deprecated and removed fields.

---

## Sources Index (`sources.yaml`)

The `sources.yaml` file at the skill root records:
- Official documentation URLs and their snapshot dates.
- Source code repository state (branch, tag, commit) used for extraction.
- Release versions currently represented in this knowledge base.
- Known gaps (e.g., "XHTTP extra headers not yet extracted").

Always check `sources.yaml` before making claims about currency.

---

## Answering Guidelines

When using this knowledge base to answer a user question, structure the response
with source grounding:

```text
Parameter含义：……
适用版本：……
默认值：……（来源：源码/文档）
服务端要求：……
客户端要求：……
与其他参数的关系：……
源码位置：……
官方文档：……
版本变化：……
注意事项：……
置信度：official-statement / source-confirmed / ……
```

If generating a configuration:
1. State which version the config targets.
2. Mark every field as: `required` | `recommended` | `optional` | `default-kept`.
3. Note which fields are server-only, client-only, or must match.
4. Flag any experimental or version-locked features.
5. Reference the source of each non-obvious choice.

---

## Currency & Limitations

This knowledge base is a **snapshot**, not a live sync. Before answering:

1. Check `sources.yaml` for the `last_sync` date and represented versions.
2. If the user asks about a newer release than recorded, state clearly:
   > "Current knowledge base snapshot covers up to vX.X.X. Information about
   > vY.Y.Y may be incomplete or missing."
3. Do not fabricate defaults, version introductions, or maintainer quotes.
4. If a parameter is not in the knowledge base, say so rather than guessing.

---

## Maintenance & Update Workflow

Three update tracks are defined:

- **Stable track**: Follows official Stable Releases. Updates `docs/stable/`,
  `changelog/`, and `extracted/`.
- **Beta track**: Follows Beta/Pre-releases. Updates `docs/beta/`.
- **Dev track**: Follows `main` branch or specific commits. Updates
  `source/commits/` and experimental parameter records.

Update steps (automated or manual):
1. Pull new docs/release/source snapshot.
2. Diff against previous snapshot.
3. Generate changelog entries: added fields, removed fields, default changes,
   incompatible changes, experimental promotions.
4. Update `extracted/parameters/` YAML records.
5. Update `sources.yaml` with new snapshot metadata.
6. Tag the skill directory with the covered version range.

---

## File Layout

```
skills/xray-core-official-knowledge/
├── SKILL.md              # This file
├── sources.yaml          # Source index and currency metadata
├── scripts/              # Helper scripts for extraction and diffing
├── references/           # Additional deep-dive docs loaded on demand
├── assets/               # Templates, JSON schemas, etc.
├── docs/
│   ├── stable/           # Stable release docs
│   ├── beta/             # Beta/pre-release docs
│   └── archived/         # Past major version docs
├── source/
│   ├── releases/         # Release notes and metadata
│   ├── commits/          # Key commit extracts
│   ├── config/           # Config struct and validation extracts
│   └── transport/        # Transport implementation extracts
├── extracted/
│   ├── parameters/       # Per-parameter YAML records
│   ├── defaults/         # Default value tables per version
│   ├── compatibility/    # Cross-parameter constraints
│   └── deprecations/     # Deprecation/removal timeline
├── changelog/            # Generated version changelogs
├── examples/             # Official and verified config examples
└── citations/            # Maintainer statements and PR/issue notes
```

---

## Quick Reference

| If the user asks … | Consult first … | Then … |
|---|---|---|
| "What does X do?" | `docs/stable/` | `extracted/parameters/` |
| "What is the default?" | `extracted/defaults/` | `source/config/` |
| "Do I set this on client or server?" | `extracted/parameters/` | `source/config/` |
| "When was X added?" | `source/commits/` + upstream git history | `changelog/` (summary only; `source/releases/` notes are sparse for pre-releases) |
| "Why does X behave this way?" | `source/config/` or `source/transport/` | `citations/` |
| "Is X deprecated?" | `extracted/deprecations/` | `changelog/` |
| "Generate a config" | `examples/` + `extracted/parameters/` | `docs/stable/` |

---

## License

This skill structure and extraction methodology are provided under the same
license as the parent project. All official Xray Core content belongs to its
respective authors and licenses.
