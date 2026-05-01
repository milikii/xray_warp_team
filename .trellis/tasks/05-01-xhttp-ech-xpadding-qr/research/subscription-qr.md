# Research: subscription QR

- Query: Research subscription file and QR output conventions for shell-based Xray/VLESS installers, including file layout options, text vs YAML subscriptions, qrencode behavior, best-effort dependency handling, and integration with this repo's OUTPUT_FILE/show-links flow.
- Scope: mixed
- Date: 2026-05-01

## Findings

### Files Found

- `.trellis/workflow.md` - Trellis requires research artifacts to be persisted under the task's `research/` directory.
- `.trellis/spec/backend/index.md` - Backend spec index exists but is still a placeholder with no concrete shell/export conventions.
- `.trellis/spec/frontend/index.md` - Frontend spec index exists but is not relevant to this shell-output task.
- `.trellis/tasks/05-01-xhttp-ech-xpadding-qr/prd.md` - Requirements explicitly call for subscription text/YAML outputs, PNG QR files when `qrencode` is available, and non-failing behavior when it is missing.
- `xray-warp-team.sh` - Defines the current default human-readable output path as `OUTPUT_FILE="/root/xray-warp-team-output.md"`.
- `lib/ui/output.sh` - Builds the three current VLESS share links, renders the Markdown output file, and writes it atomically.
- `lib/cli/core.sh` - Implements `show-links` and terminal QR rendering for `vless://` lines in `OUTPUT_FILE`.
- `lib/cli/install.sh` - Logs the output file path and calls `show_links` after installation completes.
- `lib/generators.sh` - Provides `write_generated_file_atomically`, which should be reused for generated text/YAML subscription files.
- `README.md` - Documents `show-links --qr` and says the human output currently keeps only three raw `vless://` share links, without structured client snippets.
- `tests/cases_output.sh` - Existing tests intentionally reject reintroducing embedded Clash/Mihomo/sing-box snippets into `OUTPUT_FILE`.
- `/tmp/my-xhttp-cdn-config/src/11-subscription.sh` - Reference installer generates raw, base64, YAML subscription files and subscription URL QR PNGs.
- `/tmp/my-xhttp-cdn-config/src/12-final-output.sh` - Reference installer prints subscription URLs and best-effort QR output after deployment.
- `/tmp/my-xhttp-cdn-config/templates/mihomo.yaml.tmpl` - Reference installer uses a dedicated Mihomo YAML file with `proxies:` entries and XHTTP-specific YAML options.

### Code Patterns

- The PRD says not to replace `OUTPUT_FILE`, to add subscription files/QRs alongside it, and to make QR generation best-effort (`.trellis/tasks/05-01-xhttp-ech-xpadding-qr/prd.md:21`, `.trellis/tasks/05-01-xhttp-ech-xpadding-qr/prd.md:22`, `.trellis/tasks/05-01-xhttp-ech-xpadding-qr/prd.md:23`).
- The PRD acceptance criteria require generated output to include subscription file paths and QR file paths when generated, and require missing `qrencode` to warn/skip without failing install (`.trellis/tasks/05-01-xhttp-ech-xpadding-qr/prd.md:50`, `.trellis/tasks/05-01-xhttp-ech-xpadding-qr/prd.md:51`).
- `OUTPUT_FILE` is currently a single human report at `/root/xray-warp-team-output.md`, not a machine subscription file (`xray-warp-team.sh:182`).
- `build_xhttp_uri` already emits VLESS/XHTTP URI parameters, including optional `ech=` and `extra=` query parameters (`lib/ui/output.sh:54`, `lib/ui/output.sh:65`, `lib/ui/output.sh:66`, `lib/ui/output.sh:68`).
- `output_file_text` derives the three URI strings once, then embeds them in the Markdown report (`lib/ui/output.sh:304`, `lib/ui/output.sh:310`, `lib/ui/output.sh:311`, `lib/ui/output.sh:314`, `lib/ui/output.sh:317`).
- `write_output_file` already uses `write_generated_file_atomically` and then sets mode `0644` (`lib/ui/output.sh:332`, `lib/ui/output.sh:333`, `lib/ui/output.sh:334`).
- `write_generated_file_atomically` creates a temporary file in the target directory and moves it into place, so it is the right pattern for `.txt`, `.b64`, `.yaml`, and manifest files (`lib/generators.sh:9`, `lib/generators.sh:17`, `lib/generators.sh:24`, `lib/generators.sh:25`).
- `show_links` currently prints the whole `OUTPUT_FILE`, then, only for `--qr`, scans the same file for lines beginning with `vless://` and renders terminal QR codes (`lib/cli/core.sh:27`, `lib/cli/core.sh:28`, `lib/cli/core.sh:36`, `lib/cli/core.sh:37`, `lib/cli/core.sh:38`, `lib/cli/core.sh:40`).
- `show_links --qr` already has the right optional dependency shape: `command -v qrencode`, warn, return without failing (`lib/cli/core.sh:30`, `lib/cli/core.sh:31`, `lib/cli/core.sh:32`, `lib/cli/core.sh:33`).
- Installation currently logs the output file and calls `show_links` without QR output, so persistent PNG generation should not be coupled to terminal QR display (`lib/cli/install.sh:189`, `lib/cli/install.sh:190`).
- Usage text already documents `--qr` as requiring installed `qrencode` (`lib/base/input.sh:151`, `lib/base/input.sh:152`).
- README documents `xray-warp-team show-links --qr` only as terminal QR output when `qrencode` is installed (`README.md:553`, `README.md:556`, `README.md:559`).
- README says `OUTPUT_FILE` currently keeps only three raw `vless://` links and does not include other structured client snippets (`README.md:841`, `README.md:849`, `README.md:850`).
- Existing output tests explicitly fail if the old `## Clash Meta / Mihomo 片段` or `## sing-box outbound 片段` sections reappear in `OUTPUT_FILE`, so any YAML subscription must be a separate generated file, not an embedded section (`tests/cases_output.sh:61`, `tests/cases_output.sh:64`).
- `output_field_value` parses `- Field: value` rows out of `OUTPUT_FILE`, so adding new file path rows to the existing "本地文件" block is compatible with current state recovery patterns (`lib/state.sh:23`, `lib/state.sh:27`).

### External References

- Xray's VLESS protocol page describes VLESS as an Xray client/server transport and links to the sharing-link proposal for details. It also says the default VLESS `encryption` value should be `none` when empty. Reference: https://xtls.github.io/en/development/protocols/vless.html
- The Xray-core VLESS sharing-link proposal says share links should be valid URLs, URI values should be `encodeURIComponent`-escaped, `type=xhttp` is the XHTTP transport marker, XHTTP `path`, `host`, `mode`, and `extra` are transport parameters, and TLS `ech` maps to `echConfigList`. Reference: https://github.com/XTLS/Xray-core/discussions/716
- Xray's XHTTP discussion explains that `extra` is intended to carry detailed, low-frequency XHTTP JSON settings for clients, while the normal visible link fields stay limited to address/host/path/mode-style fields. Reference: https://github.com/XTLS/Xray-core/discussions/4113
- Mihomo proxy-provider docs recognize three provider file contents: YAML, raw URI lines, and base64. They explicitly say `YAML` / `uri` / `base64` cannot be mixed in the same file, and raw/base64 URI files do not use a `proxies:` field. Reference: https://wiki.metacubex.one/en/config/proxy-providers/content/
- V2Fly v5 subscription manager supports HTTP(S) subscription URLs and multiple containers, including base64-encoded newline-separated server definitions and plain newline-separated URL lines. It recommends native outbound format for predictable parsing, but also supports non-native link conversion. Reference: https://www.v2fly.org/en_US/v5/config/service/subscription.html
- A draft XTLS Subscription Standards discussion proposes HTTPS delivery, `Content-Type`-driven parsing, JSON-array subscriptions, and headers such as `profile-title`, `profile-update-interval`, and `subscription-userinfo`. This is useful context but not a safe compatibility baseline for common clients yet. Reference: https://github.com/XTLS/Xray-core/discussions/4877
- `qrencode` accepts either a command-line string or stdin, defaults to PNG output, supports `-o/--output`, supports terminal formats including `ANSIUTF8`, and exits non-zero if strict version constraints cannot fit the input. References: https://www.mankier.com/1/qrencode and https://manpages.ubuntu.com/manpages/resolute/man1/qrencode.1.html

### File Layout Options

1. Minimal local-only export, recommended first step:
   - Keep `OUTPUT_FILE` as the human-readable Markdown report.
   - Add a separate subscription directory, for example `/root/xray-warp-team-subscriptions`.
   - Generate:
     - `links.txt` or `vless.txt`: raw LF-separated `vless://` lines only.
     - `links-base64.txt`: base64 of the raw URI file with line wraps removed.
     - `mihomo.yaml`: optional Mihomo provider/full profile YAML, only if the project is willing to maintain native YAML compatibility for XHTTP/ECH/xpadding.
     - `manifest.txt` or `subscription-links.txt`: local file paths, optional served URLs, and QR PNG paths.
     - `qr/*.png`: PNG QR files only for subscription URLs when a served URL exists; otherwise PNGs for individual `vless://` links may be useful, but they are not subscription QR codes.
   - Add the generated file paths to the existing `## 本地文件` section in `OUTPUT_FILE`; do not paste full subscription content into `OUTPUT_FILE`.

2. Tokenized HTTP subscription export, useful if mobile clients need scan/import:
   - Persist a token file with mode `0600`, e.g. under the existing managed config/state area.
   - Serve static files under a hard-to-guess path such as `/sub/<token>/links-base64.txt` and `/sub/<token>/mihomo.yaml`.
   - Generate QR PNGs that encode the HTTPS subscription URLs, not the full base64 payload.
   - Requires an nginx static location and cache-bypass/no-store headers for subscription paths. This is more operational surface than local-only files, so it should be opt-in or clearly documented.

3. Single combined file, not recommended:
   - A Markdown report containing human text, raw links, base64, and YAML will not be a valid subscription for clients.
   - This conflicts with current repo docs/tests that intentionally keep `OUTPUT_FILE` human-readable and avoid embedded Clash/Mihomo/sing-box snippets.

### Text vs YAML Subscriptions

- Raw URI text subscription:
  - Best fit for current repo because it can reuse the three URI strings already generated for `OUTPUT_FILE`.
  - File content should be exactly LF-separated `vless://...` lines, with a final newline acceptable.
  - Use labels already produced by `prefixed_node_label` so imported client names match the Markdown output.

- Base64 URI subscription:
  - Common V2Ray/Xray subscription convention and supported by V2Fly's `Base64URLLine` container.
  - Generate from the raw URI text file and remove line wraps: either GNU `base64 -w 0` or portable `base64 file | tr -d '\n'`.
  - Do not include Markdown headings, blank prose, or a `proxies:` wrapper.

- Mihomo YAML subscription:
  - Must be a separate file because Mihomo docs say YAML, URI, and base64 formats cannot be mixed.
  - Native YAML is more expressive for XHTTP options than URI-provider parsing, but it creates a compatibility and maintenance burden.
  - Given README/tests currently avoid structured client snippets in `OUTPUT_FILE`, YAML should be generated as `mihomo.yaml` only and referenced by path/URL in the report.

- JSON subscription:
  - XTLS JSON subscription discussions exist, but common client support is less clear than raw/base64 URI and Mihomo YAML. Treat JSON as future work unless a target client matrix requires it.

### qrencode Behavior and Conventions

- Terminal QR:
  - Current `show-links --qr` behavior matches standard `qrencode -t ANSIUTF8 <string>` usage.
  - It should remain terminal-only and should keep scanning only `vless://` lines from `OUTPUT_FILE` unless a new option is explicitly introduced for subscription URL QR display.

- PNG QR:
  - Use `qrencode -o "$tmp_png" -s 8 -m 2 "$url"` for subscription URL PNGs, then atomically move into the final path.
  - Encode subscription URLs rather than full raw/base64/YAML subscription content. Full content can exceed QR capacity, becomes unreadable, and leaks all node details into the image.
  - If using stdin, prefer `printf '%s' "$url" | qrencode ...` so a trailing newline is not accidentally included. Passing the URL as the string argument is also acceptable for this project's generated `https://...` URLs.
  - Capture failures per file and warn. A too-long URL, bad output path, or unsupported terminal can fail independently of subscription text generation.

### Best-Effort Dependency Handling

- Keep `qrencode` optional. Missing `qrencode` should warn and skip terminal/PNG QR output, not fail install or rollback generated text subscriptions.
- Do not install `qrencode` implicitly from `show-links`; that command should stay read-only except for terminal output.
- If the installer already has an optional dependency phase, it can try to install `qrencode`, but failure should be recorded as "QR unavailable" rather than "install failed".
- Treat text/YAML subscription generation differently from QR generation:
  - Failure to write required subscription files should fail the export step because the output would be inconsistent.
  - Failure to write QR PNGs should not fail install; it should leave no partial PNG and should omit or mark the QR path as unavailable in the manifest/report.
- Tests should cover both paths by stubbing `qrencode` in `PATH`: one test where it writes fake PNG bytes successfully, and one where it is absent or exits non-zero.

### Fit With This Repo's OUTPUT_FILE / show-links Flow

- Do not make `OUTPUT_FILE` itself a subscription. It is Markdown and contains operational instructions.
- Add a helper that computes the current share links once, then can feed both `output_file_text` and subscription writers. This avoids duplicating URI construction logic that already exists in `output_file_text`.
- Keep side effects out of `output_file_text`; it should continue to only render text for `OUTPUT_FILE`.
- Reuse `write_generated_file_atomically` for raw/base64/YAML/manifest text files. Add a similar temp-file-and-move helper for binary PNGs.
- Add generated subscription file paths, served URLs if any, and QR PNG paths to the `## 本地文件` block in `OUTPUT_FILE`, likely near `- 链接输出文件: ${OUTPUT_FILE}`.
- Keep `show-links` default behavior as "cat the human report". Keep `show-links --qr` as terminal QR for the raw `vless://` lines it already finds.
- Persistent subscription PNG generation should happen during the export/write phase, not in `show-links --qr`, because `show-links --qr` is currently a display command and should not mutate files.
- If HTTP subscription serving is added, prefer a tokenized path and list the URLs in `OUTPUT_FILE`. The QR PNGs should encode those URLs, so mobile import works.

### Recommended Initial Implementation Direction

- Add constants/state variables for a subscription directory and generated file paths, but keep them outside `OUTPUT_FILE`.
- Refactor URI generation into a small function or producer that returns the three canonical URI lines.
- Generate at least:
  - raw URI text file for clients that accept URI-line subscriptions,
  - base64 URI file for V2Ray/Xray-style subscription import,
  - manifest text file for humans/scripts.
- Add Mihomo YAML only if the implementation can accurately represent this repo's XHTTP split and ECH/xpadding settings; otherwise document raw/base64 first and mark YAML as follow-up.
- Generate PNG QR files only when there are real subscription URLs or when explicitly documenting that the PNG encodes an individual node link.
- Preserve all existing `show-links` behavior and tests, then add tests for new files, missing `qrencode`, failing `qrencode`, and no embedded YAML sections in `OUTPUT_FILE`.

### Related Specs

- `.trellis/spec/backend/index.md` - Relevant because this is shell/backend behavior, but currently placeholder-only.
- `.trellis/spec/frontend/index.md` - Not relevant for this task.
- `.trellis/tasks/05-01-xhttp-ech-xpadding-qr/prd.md` - The active task requirement source for subscription/QR behavior.

## Caveats / Not Found

- There is no single universally accepted subscription file standard across all VLESS/Xray clients. Raw URI lines, base64 raw URI content, Mihomo YAML, and newer JSON subscription proposals overlap but target different clients.
- The Xray VLESS sharing-link source is a living GitHub discussion/proposal with fields updated over time; treat it as the best available Xray URI reference, but keep client-compatibility notes in README.
- The XTLS JSON subscription standard is a draft/discussion and should not be the default export unless a target client is explicitly selected.
- The referenced `/tmp/my-xhttp-cdn-config` pattern serves subscription files via nginx and hard-fails URL self-checks. That is useful for comparison, but this repo's PRD specifically wants QR dependency failures to be best-effort and wants to preserve rollback/safe-write behavior.
- I did not find existing persistent subscription output in this repo; current functionality is human Markdown output plus terminal QR rendering for `vless://` links.
