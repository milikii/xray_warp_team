# Add ECH, xpadding, and Subscription QR Support

## Goal

Add user-visible parity with stronger XHTTP client features from comparable XHTTP/CDN setup tools while preserving this project's stronger operational guarantees: safe defaults, validation, rollback, state persistence, tests, and clear docs.

## What I already know

* User asked to add ECH, xpadding, and subscription QR after comparing this project with `Yulinanami/my-xhttp-cdn-config`.
* Current project already has partial ECH plumbing:
  * `XHTTP_ECH_CONFIG_LIST` and `XHTTP_ECH_FORCE_QUERY` exist in state/defaults.
  * Output link generation adds `ech=` when `XHTTP_ECH_CONFIG_LIST` is non-empty.
  * README currently says XHTTP does not enable ECH by default.
* Current project already has terminal QR support for node links via `xray-warp-team show-links --qr`.
* Current project does not appear to have xpadding config generation.
* Current project does not appear to generate persistent subscription files or PNG QR files for subscriptions.
* Reference project generates xpadding/ECH variants and subscription/QR outputs, but uses a simpler and riskier operational model.

## Assumptions

* Preserve the current default install path as the stable path; new XHTTP masking features should be opt-in unless the user says otherwise.
* Do not replace the existing `OUTPUT_FILE`; add subscription files/QRs alongside it.
* QR generation should be best-effort if `qrencode` exists, and should not fail install when unavailable.
* Client output should remain compatible with existing VLESS URI consumers.

## Open Questions

* None.

## Requirements

* Add install-time CLI flags and interactive prompts for ECH.
* Keep ECH disabled by default; enable only via explicit flag or affirmative interactive answer.
* Persist ECH settings in state and restore them during change/reinstall flows.
* Add install-time CLI flags and interactive prompts for xpadding.
* Keep xpadding disabled by default; enable only via explicit flag or affirmative interactive answer.
* Generate Xray XHTTP inbound settings with xpadding only when enabled.
* Include ECH/xpadding details in exported node links and output summaries where clients need them.
* Generate separate subscription files alongside the human Markdown output:
  * raw LF-separated `vless://` URI text
  * base64-encoded raw URI text
  * human manifest listing generated paths and QR availability
* Generate QR PNG files for subscription outputs when `qrencode` is available.
* Keep `show-links --qr` working for terminal QR display.
* Update README with the new flags, behavior, dependencies, and compatibility notes.
* Add or update tests covering enabled/disabled ECH, xpadding JSON generation, subscription file creation, QR best-effort behavior, and backward-compatible defaults.

## Acceptance Criteria

* [ ] Existing smoke tests still pass.
* [ ] A default install with no new flags keeps ECH/xpadding disabled.
* [ ] `--enable-xhttp-ech` or equivalent writes ECH settings to state and exported XHTTP links.
* [ ] `--enable-xhttp-xpadding` or equivalent writes the expected Xray xhttp padding settings.
* [ ] Generated output includes raw/base64 subscription file paths and QR file paths when generated.
* [ ] Missing `qrencode` produces a warning or skips PNG QR generation without failing install.
* [ ] README documents the new options and compatibility requirements.

## Definition of Done

* Tests added/updated for new behavior.
* Shellcheck/smoke checks pass where available.
* Docs updated for behavior changes.
* Rollback/safe-write behavior preserved for generated files.

## Out of Scope

* Replacing this project with the reference project's one-shot installer model.
* Enabling ECH/xpadding by default unless explicitly confirmed.
* Supporting Alpine in this task.
* Adding a web UI.
* Serving subscription files over nginx/tokenized URLs unless it falls out naturally from existing config without expanding risk.
* Full native Mihomo YAML subscription generation; raw/base64 VLESS subscriptions are the MVP. Mihomo YAML can be added later once client field coverage is designed and tested.

## Technical Notes

* Likely impacted local files:
  * `xray-warp-team.sh`
  * `lib/cli/install.sh`
  * `lib/install/input.sh`
  * `lib/generators.sh`
  * `lib/ui/output.sh`
  * `lib/cli/core.sh`
  * `lib/state.sh`
  * `README.md`
  * `tests/*.sh`
* Existing QR path:
  * `lib/cli/core.sh` implements `show-links --qr`.
* Existing ECH path:
  * `lib/ui/output.sh` emits `ech=` when `XHTTP_ECH_CONFIG_LIST` is set.
  * `lib/state.sh` already persists `XHTTP_ECH_CONFIG_LIST` and `XHTTP_ECH_FORCE_QUERY`.
* Reference project paths inspected:
  * `/tmp/my-xhttp-cdn-config/src/04-input.sh`
  * `/tmp/my-xhttp-cdn-config/templates/xray-config.json.tmpl`
  * `/tmp/my-xhttp-cdn-config/templates/mihomo.yaml.tmpl`
  * `/tmp/my-xhttp-cdn-config/src/11-subscription.sh`
  * `/tmp/my-xhttp-cdn-config/src/12-final-output.sh`
* Research references:
  * [`research/xhttp-ech-xpadding.md`](research/xhttp-ech-xpadding.md) — Xray/Mihomo ECH and xpadding field conventions, URI behavior, and version caveats.
  * [`research/subscription-qr.md`](research/subscription-qr.md) — Subscription file/QR conventions and the recommended local raw/base64 MVP.

## Decision (ADR-lite)

**Context**: ECH and xpadding can improve XHTTP/CDN masking, but they also increase client compatibility and DNS/DoH troubleshooting risk.

**Decision**: Use conservative defaults. ECH and xpadding are opt-in through CLI flags or interactive prompts. Subscription QR generation is best-effort: generate raw/base64 subscription files every time, generate PNG/terminal QR output when `qrencode` exists, otherwise warn/skip without failing install.

**Consequences**: Default installs remain compatible and easier to debug. Users who want stronger masking can enable the advanced options explicitly. Native Mihomo YAML stays out of the MVP to avoid shipping a half-correct client profile.
