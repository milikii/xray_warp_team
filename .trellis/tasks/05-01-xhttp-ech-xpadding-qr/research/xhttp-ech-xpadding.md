# Research: Xray XHTTP ECH and xpadding conventions

- Query: Research Xray XHTTP ECH and xpadding implementation conventions for this task, including expected Xray xhttpSettings fields, VLESS URI/query conventions for ECH, Mihomo/client compatibility notes, and how `/tmp/my-xhttp-cdn-config` represents these settings.
- Scope: mixed
- Date: 2026-05-01

## Findings

### Files found

- `.trellis/tasks/05-01-xhttp-ech-xpadding-qr/prd.md` - Task requirements for opt-in ECH, opt-in xpadding, subscription outputs, QR best-effort behavior, tests, and README updates.
- `lib/generators.sh` - Generates the current Xray inbound JSON. The XHTTP inbound currently emits only `host`, `path`, and `mode` under `streamSettings.xhttpSettings` (`lib/generators.sh:96`).
- `lib/ui/output.sh` - Builds VLESS share links, conditionally appends `ech=`, conditionally appends `extra=`, and builds the split `downloadSettings` JSON (`lib/ui/output.sh:54`, `lib/ui/output.sh:83`, `lib/ui/output.sh:290`).
- `lib/state.sh` - Persists and normalizes existing ECH state keys, but has no xpadding state keys yet (`lib/state.sh:63`, `lib/state.sh:316`, `lib/state.sh:365`).
- `tests/cases_output.sh` - Existing output tests assert that ECH links contain `&ech=`, split links contain `extra=`, and legacy Mihomo snippets are absent (`tests/cases_output.sh:51`, `tests/cases_output.sh:61`).
- `/tmp/my-xhttp-cdn-config/docs/3.xpadding配置.md` - Reference xpadding documentation for Xray/v2rayN and Mihomo field spellings and nested `downloadSettings` behavior.
- `/tmp/my-xhttp-cdn-config/docs/4.ECH配置.md` - Reference ECH documentation for CDN-TLS nodes, `echConfigList`, VLESS `ech=`, and Mihomo `ech-opts`.
- `/tmp/my-xhttp-cdn-config/src/04-input.sh` - Reference interactive prompts and defaults for xpadding header/key and CDN ECH opt-in.
- `/tmp/my-xhttp-cdn-config/src/05-base-env.sh` - Reference runtime variables and encoded URI/query fragments for xpadding and ECH.
- `/tmp/my-xhttp-cdn-config/src/10-client-config.sh` - Reference VLESS `extra` JSON, nested `downloadSettings`, Mihomo xpadding blocks, and Mihomo ECH blocks.
- `/tmp/my-xhttp-cdn-config/templates/xray-config.json.tmpl` - Reference server-side Xray XHTTP inbound template.
- `/tmp/my-xhttp-cdn-config/templates/mihomo.yaml.tmpl` - Reference Mihomo YAML export template.
- `/tmp/my-xhttp-cdn-config/templates/client-config.txt.tmpl` - Reference VLESS URI template for normal and split XHTTP nodes.

### Current project patterns

- `xray_xhttp_inbound_json` currently produces a server XHTTP inbound with:
  - `streamSettings.network: "xhttp"`
  - `xhttpSettings.host: ""`
  - `xhttpSettings.path: $XHTTP_PATH`
  - `xhttpSettings.mode: "auto"`
  It does not add xpadding fields (`lib/generators.sh:96`).
- `build_xhttp_uri` already supports optional `ech_component` and `extra_component`: non-empty ECH becomes `&ech=...`; non-empty extra JSON becomes `&extra=...` (`lib/ui/output.sh:54`).
- The current non-split XHTTP CDN node receives ECH when `XHTTP_ECH_CONFIG_LIST` is non-empty. The split node currently passes an empty ECH component even though its top-level uplink is TLS+CDN (`lib/ui/output.sh:311`, `lib/ui/output.sh:314`). The reference repo includes top-level `ech=` on its analogous split TLS+CDN uplink node.
- `build_xhttp_split_extra_json` currently emits only `downloadSettings` with downlink `security: "reality"` and nested `xhttpSettings.host/path/mode`; no nested xpadding `extra` exists yet (`lib/ui/output.sh:83`).
- State already allows `XHTTP_ECH_CONFIG_LIST` and `XHTTP_ECH_FORCE_QUERY` (`lib/state.sh:63`) and normalizes old default test values to empty (`lib/state.sh:316`). xpadding will need new state keys if it is configurable/persistent.

### Expected Xray `xhttpSettings` fields

Primary source: Xray Go package docs expose `SplitHTTPConfig`, used by `xhttpSettings` and `splithttpSettings`, with these JSON fields: `host`, `path`, `mode`, `headers`, `xPaddingBytes`, `xPaddingObfsMode`, `xPaddingKey`, `xPaddingHeader`, `xPaddingPlacement`, `xPaddingMethod`, `uplinkHTTPMethod`, `sessionPlacement`, `sessionKey`, `seqPlacement`, `seqKey`, `uplinkDataPlacement`, `uplinkDataKey`, `uplinkChunkSize`, `noGRPCHeader`, `noSSEHeader`, `scMaxEachPostBytes`, `scMinPostsIntervalMs`, `scMaxBufferedPosts`, `scStreamUpServerSecs`, `serverMaxHeaderBytes`, `xmux`, `downloadSettings`, and `extra` (pkg.go.dev `github.com/xtls/xray-core/infra/conf`, lines 1922-1951).

Operational conventions from Xray source/docs:

- `mode` defaults to `auto`; accepted values are `auto`, `packet-up`, `stream-up`, and `stream-one` (GitHub source excerpt from `transport_internet.go`, crawled in search result for `SplitHTTPConfig`).
- `headers` must not contain `Host`; Xray derives Host from the dedicated `host` field.
- `xPaddingKey` defaults to `x_padding`, `xPaddingHeader` defaults to `X-Padding`, `xPaddingPlacement` defaults to `queryInHeader`, and `xPaddingMethod` defaults to `repeat-x`.
- Valid `xPaddingPlacement` values are `cookie`, `header`, `query`, and `queryInHeader`; valid `xPaddingMethod` values are `repeat-x` and `tokenish`.
- `downloadSettings` cannot be used with `mode: "stream-one"`.
- If `extra` is present, Xray parses it as another `SplitHTTPConfig` and then copies the outer `host`, `path`, and `mode` into it. That makes `extra` the right place for advanced share-link-only fields such as xpadding, `xmux`, `scMinPostsIntervalMs`, and `downloadSettings`, while still keeping `host/path/mode` in normal URI query parameters.
- TLS ECH is not an XHTTP field. Xray TLS settings include `echConfigList`, `echForceQuery`, and `echSockopt` in `TLSConfig` (pkg.go.dev lines 2101-2114). The Project X transport docs show `echConfigList` and `echSockopt` inside the TLS object (xtls.github.io transport docs lines 305-323).

Practical Xray server-side shape for this task:

```json
"xhttpSettings": {
  "host": "",
  "path": "/example",
  "mode": "auto",
  "xPaddingObfsMode": true,
  "xPaddingKey": "x_padding",
  "xPaddingHeader": "Referer",
  "xPaddingPlacement": "queryInHeader",
  "xPaddingMethod": "tokenish"
}
```

The five xpadding fields above match the reference repo's conservative profile. Do not use Mihomo-style `x-padding-*` keys in Xray JSON.

### VLESS URI and ECH conventions

- Xray VLESS share-link standard defines XHTTP `path`, `host`, `mode`, and `extra`; `path`, `host`, and `extra` must be `encodeURIComponent`-escaped (XTLS discussion #716 lines 403-417).
- TLS share-link parameter `ech` maps to Xray `tlsSettings.echConfigList` and must also be URI-component encoded. The field may be empty, but this project should omit it when disabled for backward-compatible defaults (XTLS discussion #716 lines 459-463).
- Cloudflare's shared ECH outer SNI is `cloudflare-ech.com`; Cloudflare explains that ECH masks the real SNI and makes intermediaries see the shared Cloudflare name instead (Cloudflare ECH docs lines 249-260).
- Reference repo convention for Cloudflare ECH is:
  - unencoded value: `cloudflare-ech.com+https://223.5.5.5/dns-query`
  - VLESS query value: `cloudflare-ech.com%2Bhttps%3A%2F%2F223.5.5.5%2Fdns-query`
  (`/tmp/my-xhttp-cdn-config/docs/4.ECH配置.md:21`, `/tmp/my-xhttp-cdn-config/docs/4.ECH配置.md:35`).
- For a top-level CDN-TLS XHTTP VLESS link, append `&ech=<encoded echConfigList>` alongside `security=tls`, `sni=<cdn-domain>`, `fp=chrome`, `alpn=h2`, `type=xhttp`, `host=<cdn-domain>`, `path=<encoded path>`, and `mode=auto`.
- For split links where the nested `downloadSettings` uses CDN-TLS, put `echConfigList` inside `downloadSettings.tlsSettings` within the encoded `extra` JSON. The top-level `ech=` only configures the top-level TLS connection.
- `echForceQuery` exists in Xray JSON, but the current VLESS standard section found for TLS only defines `ech` for `echConfigList`; no share-link query parameter for `echForceQuery` was found. If implemented, keep `echForceQuery` in state/output summaries or Xray JSON objects, not in VLESS URI unless a later standard is verified.
- The VLESS share-link standard says `allowInsecure` was removed and replaced by certificate pinning/name verification parameters (XTLS discussion #716 lines 464-474). This project currently emits `insecure=0&allowInsecure=0` in XHTTP URIs (`lib/ui/output.sh:68`), so avoid expanding that pattern further unless maintaining legacy importer compatibility is deliberate.

### Mihomo and client compatibility notes

- Mihomo docs state `xhttp-opts` applies only when `network: xhttp` and that xhttp transport is only supported for VLESS (Mihomo transport docs lines 566-574).
- Mihomo XHTTP defaults to HTTP/2 unless `alpn` is set to `h3` or `http/1.1` for other modes (Mihomo transport docs lines 401-410 and 566-570).
- Mihomo uses kebab-case YAML fields under `xhttp-opts`: `x-padding-obfs-mode`, `x-padding-key`, `x-padding-header`, `x-padding-placement`, `x-padding-method`, `sc-min-posts-interval-ms`, `reuse-settings`, and `download-settings` (Mihomo transport docs lines 401-450 and 595-701).
- Mihomo's `reuse-settings` has no default; if omitted, each request opens a new lower-level connection. The reference repo explicitly emits `reuse-settings` with `max-concurrency: "16-32"`, `c-max-reuse-times: "0"`, `h-max-reusable-secs: "1800-3000"`, and `h-keep-alive-period: 0` (`/tmp/my-xhttp-cdn-config/templates/mihomo.yaml.tmpl:100`, `/tmp/my-xhttp-cdn-config/templates/mihomo.yaml.tmpl:122`).
- Mihomo TLS ECH is represented by `ech-opts` with `enable: true` plus either `config` or `query-server-name`; official docs show `ech-opts.enable`, `ech-opts.config`, and `ech-opts.query-server-name` (Mihomo TLS docs lines 202-205).
- Mihomo v1.19.24 release added/converted new XHTTP options, H3 mode support, HTTP/1.1 mode support, `h-keep-alive-period`, `sc-min-posts-interval-ms`, and other XHTTP features (MetaCubeX/mihomo v1.19.24 release lines 217-225). The reference repo requires Mihomo >= 1.19.24 for xpadding/ECH parity (`/tmp/my-xhttp-cdn-config/docs/3.xpadding配置.md:7`, `/tmp/my-xhttp-cdn-config/README.md:90`).
- Xray v25.7.26 added TLS ECH support and updated VLESS share links with TLS `ech` (Xray v25.7.26 release lines 213-219). Xray v26.2.6 added XHTTP options for bypassing potential CDN detection and explicitly warned those new options were not yet fully settled for third-party implementations (Xray v26.2.6 release/search result). Xray v26.3.27 includes later XHTTP and TLS ECH fixes/enhancements (Xray v26.3.27 release lines 217-244).
- For this project, raw VLESS links should remain the primary compatibility path for Xray/v2rayN-style clients. Mihomo compatibility is better served by generated YAML if/when this task adds subscription YAML output, because Mihomo uses different field names and nested shapes.

### Reference repo representation

Server-side Xray:

- The reference server template has the XHTTP inbound under `streamSettings.network: "xhttp"` with `xhttpSettings.host`, `xhttpSettings.path`, and `xhttpSettings.mode`; it injects xpadding JSON only for the xpadding variant (`/tmp/my-xhttp-cdn-config/templates/xray-config.json.tmpl:75`).
- The generated xpadding JSON uses Xray camelCase keys: `xPaddingObfsMode`, `xPaddingKey`, `xPaddingHeader`, `xPaddingPlacement`, and `xPaddingMethod` (`/tmp/my-xhttp-cdn-config/src/05-base-env.sh:70`).
- The reference docs describe the same five-field Xray xpadding profile and warn not to use Mihomo-style `x-padding-*` names in Xray JSON (`/tmp/my-xhttp-cdn-config/docs/3.xpadding配置.md:16`, `/tmp/my-xhttp-cdn-config/docs/3.xpadding配置.md:36`, `/tmp/my-xhttp-cdn-config/docs/3.xpadding配置.md:63`).

Inputs/defaults:

- xpadding asks for a customizable header and key, defaulting to `Referer` and `x_padding` (`/tmp/my-xhttp-cdn-config/src/04-input.sh:46`).
- xpadding placement and method are fixed to `queryInHeader` and `tokenish` (`/tmp/my-xhttp-cdn-config/src/05-base-env.sh:64`).
- CDN ECH is optional; when enabled, the reference sets `CDN_ECH_QUERY` to `cloudflare-ech.com+https://223.5.5.5/dns-query` (`/tmp/my-xhttp-cdn-config/src/04-input.sh:55`).

VLESS URI output:

- ECH encoding is built by escaping `%`, `+`, `:`, and `/`, then appended as `&ech=...` (`/tmp/my-xhttp-cdn-config/src/05-base-env.sh:82`).
- For nested TLS download settings, the reference injects encoded `"echConfigList": "<encoded value>"` into nested `tlsSettings` (`/tmp/my-xhttp-cdn-config/src/05-base-env.sh:85`).
- `EXTRA_2_PARAM` encodes xpadding plus `xmux` for the non-split Reality XHTTP node; `EXTRA_4_PARAM` adds `scMinPostsIntervalMs` for a dual-CDN node; `EXTRA_3` and `EXTRA_5` build split `downloadSettings` JSON (`/tmp/my-xhttp-cdn-config/src/10-client-config.sh:21`, `/tmp/my-xhttp-cdn-config/src/10-client-config.sh:85`).
- The raw VLESS template includes:
  - node 2: Reality XHTTP with `extra=${EXTRA_2_PARAM}`
  - node 3: top-level TLS+CDN plus top-level `ech=` and split downlink Reality via `extra=${EXTRA_3}`
  - node 4: dual CDN with top-level `ech=` and `extra=${EXTRA_4_PARAM}`
  - node 5: top-level Reality plus nested downlink TLS+CDN with nested `echConfigList` via `extra=${EXTRA_5}`
  (`/tmp/my-xhttp-cdn-config/templates/client-config.txt.tmpl:2`).

Mihomo YAML:

- Top-level xpadding blocks are inserted under `xhttp-opts`; nested xpadding blocks are inserted under `download-settings` (`/tmp/my-xhttp-cdn-config/src/10-client-config.sh:33`, `/tmp/my-xhttp-cdn-config/src/10-client-config.sh:42`).
- Top-level ECH uses `ech-opts.enable: true` and `query-server-name: cloudflare-ech.com`; nested downlink ECH uses the same block inside `download-settings` (`/tmp/my-xhttp-cdn-config/src/10-client-config.sh:68`).
- The Mihomo template places top-level ECH next to `client-fingerprint` for top-level TLS+CDN nodes and nested ECH next to `client-fingerprint` inside `download-settings` for downlink TLS+CDN (`/tmp/my-xhttp-cdn-config/templates/mihomo.yaml.tmpl:108`, `/tmp/my-xhttp-cdn-config/templates/mihomo.yaml.tmpl:170`).

### Implementation conventions to carry forward

- Keep ECH and xpadding opt-in. This matches the task PRD and avoids default client-compatibility regressions.
- Use Xray camelCase field names in server JSON and VLESS `extra` JSON. Use Mihomo kebab-case field names only in Mihomo YAML.
- If xpadding is enabled, match the reference's conservative profile unless the user chooses custom values:
  - `xPaddingObfsMode: true`
  - `xPaddingKey: "x_padding"`
  - `xPaddingHeader: "Referer"`
  - `xPaddingPlacement: "queryInHeader"`
  - `xPaddingMethod: "tokenish"`
- For VLESS links, build `extra` with `jq` and the existing `uri_encode` helper instead of hand-assembling percent-encoded JSON. Existing code already uses `jq` for split extra (`lib/ui/output.sh:83`).
- Include top-level `ech=` on every top-level TLS+CDN XHTTP link when ECH is enabled. In current output this likely means both the regular XHTTP CDN node and the split TLS+CDN uplink node.
- Only use nested `tlsSettings.echConfigList` inside `extra.downloadSettings` when the nested downlink itself is TLS+CDN.
- If generating Mihomo subscription YAML, represent ECH as `ech-opts`, not `ech=`, and represent xpadding as `x-padding-*`, not Xray camelCase.
- Add tests for:
  - default disabled state has no xpadding fields and no `ech=`
  - enabled xpadding adds the five server-side Xray fields
  - enabled xpadding adds encoded `extra` fields to VLESS links
  - split `extra` retains existing `downloadSettings` while adding xpadding where needed
  - enabled ECH appears on all top-level TLS+CDN links
  - nested TLS download settings carry `echConfigList` if this project later emits such a node
  - generated Mihomo YAML, if added, uses `xhttp-opts`, `download-settings`, and `ech-opts`

### External references

- Xray Go package docs for `SplitHTTPConfig`, `StreamConfig`, and `TLSConfig`: https://pkg.go.dev/github.com/xtls/xray-core/infra/conf
- Xray VLESS share-link standard discussion #716: https://github.com/XTLS/Xray-core/discussions/716
- Xray transport/TLS object docs: https://xtls.github.io/config/transport.html
- Xray v25.7.26 release with TLS ECH support: https://github.com/XTLS/Xray-core/releases/tag/v25.7.26
- Xray v26.2.6 release with new XHTTP detection-bypass options: https://github.com/XTLS/Xray-core/releases/tag/v26.2.6
- Xray v26.3.27 release with later XHTTP/TLS ECH fixes: https://github.com/XTLS/Xray-core/releases/tag/v26.3.27
- Mihomo transport docs, `xhttp-opts`: https://wiki.metacubex.one/en/config/proxies/transport/
- Mihomo TLS docs, `ech-opts`: https://wiki.metacubex.one/en/config/proxies/tls/
- Mihomo v1.19.24 release with new XHTTP option support: https://github.com/MetaCubeX/mihomo/releases/tag/v1.19.24
- Cloudflare ECH docs: https://developers.cloudflare.com/ssl/edge-certificates/ech/

### Related specs

- `.trellis/spec/backend/index.md` - Backend guideline index exists but is still placeholder content.
- `.trellis/spec/frontend/index.md` - Frontend guideline index exists but is not directly relevant to this shell/backend research task.
- `.trellis/spec/guides/index.md` - General thinking guides apply, especially search-before-changing constants/config values.

## Caveats / Not Found

- `python3 ./.trellis/scripts/task.py current --source` returned no active task. The output path was explicit in the user request, so this research used `.trellis/tasks/05-01-xhttp-ech-xpadding-qr` as the task directory.
- I did not find a VLESS share-link parameter for Xray `echForceQuery`; only `ech` for `echConfigList` is documented in the VLESS share-link standard section reviewed.
- Xray v26.2.6 release notes warned that new XHTTP detection-bypass options were not fully settled for third-party implementations at that time. The task should treat xpadding client compatibility as version-sensitive and keep defaults disabled.
- The reference repo's `allowInsecure=0` URI usage is legacy-compatible but conflicts with the newer Xray share-link standard note that `allowInsecure` is removed/replaced. Preserve only if needed for importer compatibility.
- No code outside this research file was edited.
