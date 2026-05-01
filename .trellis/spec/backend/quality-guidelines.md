# Quality Guidelines

> Code quality standards for backend development.

---

## Overview

This repo is shell-heavy backend/infra code. Quality rules here should prefer:

- explicit CLI/env/state contracts over implicit behavior
- safe file generation via temp file + atomic move
- defaults that preserve compatibility until the user opts into advanced behavior
- smoke-test coverage for every new branch that changes generated config or output

---

## Scenario: XHTTP Advanced Transport And Subscription Export

### 1. Scope / Trigger

- Trigger: new install CLI flags, new persisted state keys, generated Xray transport fields, and generated subscription artifacts.
- Why this requires code-spec depth: the behavior spans CLI parsing, interactive prompts, state persistence, config generation, human output, and test coverage.

### 2. Signatures

- Install flags:
  - `--enable-xhttp-ech`
  - `--disable-xhttp-ech`
  - `--xhttp-ech-config-list VALUE`
  - `--xhttp-ech-force-query VALUE`
  - `--enable-xhttp-xpadding`
  - `--disable-xhttp-xpadding`
  - `--xhttp-xpadding-key VALUE`
  - `--xhttp-xpadding-header VALUE`
  - `--xhttp-xpadding-placement VALUE`
  - `--xhttp-xpadding-method VALUE`
- Output writers:
  - `write_output_file`
  - `write_subscription_files`
  - `subscription_raw_text`
  - `subscription_base64_text`
- Generated local artifacts:
  - `${OUTPUT_FILE}`
  - `${SUBSCRIPTION_RAW_FILE}`
  - `${SUBSCRIPTION_BASE64_FILE}`
  - `${SUBSCRIPTION_MANIFEST_FILE}`
  - `${SUBSCRIPTION_RAW_QR_FILE}`
  - `${SUBSCRIPTION_BASE64_QR_FILE}`

### 3. Contracts

- State/env keys:
  - `XHTTP_ECH_CONFIG_LIST`
  - `XHTTP_ECH_FORCE_QUERY`
  - `XHTTP_XPADDING_ENABLED`
  - `XHTTP_XPADDING_KEY`
  - `XHTTP_XPADDING_HEADER`
  - `XHTTP_XPADDING_PLACEMENT`
  - `XHTTP_XPADDING_METHOD`
- Default behavior:
  - ECH is disabled by default.
  - xpadding is disabled by default.
  - Raw/base64 subscription files are always generated.
  - QR PNG generation is best-effort and must not fail install when `qrencode` is missing.
- Output contract:
  - `OUTPUT_FILE` stays human-readable Markdown and is not itself a machine subscription.
  - Raw/base64 subscriptions are written as separate files under the subscription directory.

### 4. Validation & Error Matrix

- `XHTTP_PATH` contains whitespace/newline/quote/backslash -> fail validation.
- `XHTTP_XPADDING_ENABLED=yes` with empty key/header -> fail validation.
- `XHTTP_XPADDING_PLACEMENT` outside `cookie|header|query|queryInHeader` -> fail validation.
- `XHTTP_XPADDING_METHOD` outside `repeat-x|tokenish` -> fail validation.
- `XHTTP_ECH_CONFIG_LIST` or `XHTTP_ECH_FORCE_QUERY` contains newline -> fail validation.
- `qrencode` missing -> warn and skip QR PNG generation.
- QR PNG generation failure for one file -> warn and continue; do not abort install.

### 5. Good / Base / Bad Cases

- Good:
  - Default install keeps ECH/xpadding off and emits clean legacy-compatible links.
  - Opt-in install adds ECH to top-level TLS+CDN links and xpadding to server/client XHTTP settings.
  - Subscription directory contains raw/base64/manifest files even when QR support is absent.
- Base:
  - `show-links --qr` continues to render terminal QR for `vless://` lines found in `OUTPUT_FILE`.
  - Dashboard shows subscription directory and xpadding/ECH status.
- Bad:
  - Reusing `OUTPUT_FILE` as a mixed Markdown + YAML/base64 subscription blob.
  - Turning missing `qrencode` into an install failure.
  - Adding advanced transport defaults that silently change old install behavior.

### 6. Tests Required

- Smoke assertions for:
  - default no-ECH/no-xpadding path
  - xpadding server JSON fields
  - ECH link emission
  - raw/base64 subscription file generation
  - QR best-effort skip when `qrencode` is missing
  - QR PNG success path with stubbed `qrencode`
  - non-interactive parsing for ECH/xpadding flags
  - install-prepare path preserving explicit ECH enablement
- Assertion points:
  - generated Xray JSON
  - generated state file
  - generated Markdown output
  - generated subscription files

### 7. Wrong vs Correct

#### Wrong

- Add client-specific structured snippets back into `OUTPUT_FILE`.
- Encode ECH/xpadding defaults by mutating unrelated legacy flags.
- Write subscription files with ad hoc `printf > file` flows in multiple places.

#### Correct

- Keep one canonical link-construction path, then reuse it for Markdown and subscriptions.
- Persist transport toggles in state with explicit defaults.
- Write generated files through shared atomic helpers and keep QR generation best-effort.

---

## Forbidden Patterns

- Mixing human docs and machine subscription formats into one generated file.
- Adding new CLI flags without a smoke test covering parse + validation or downstream effect.
- Writing config/output files directly in place when an atomic helper already exists.

---

## Required Patterns

- New generated artifacts must use shared atomic write helpers when feasible.
- New opt-in transport features must default to off unless there is a compatibility-safe reason otherwise.
- New CLI/install behavior must be reflected in README and smoke coverage together.

---

## Testing Requirements

- `bash tests/smoke.sh` is the baseline required check for generated-output or config-assembly changes.
- If a new helper introduces a success/failure branch, add a targeted smoke case for both paths when practical.

---

## Code Review Checklist

- Are advanced transport features opt-in instead of silently changing defaults?
- Does the same canonical link data feed all generated outputs?
- Are subscription files separate from the human Markdown report?
- Does missing optional tooling degrade with warnings instead of aborting?
