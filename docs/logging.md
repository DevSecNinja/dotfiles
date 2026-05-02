# Shell Logging

A reusable POSIX-sh logging library used by every shell script in this repo.
Source it from Bash, Zsh, or POSIX `sh` — Fish gets an auto-generated wrapper
from `config.fish`.

The implementation lives in
[`home/dot_config/shell/functions/log.sh`](https://github.com/DevSecNinja/dotfiles/blob/main/home/dot_config/shell/functions/log.sh).

## Quick start

```sh
. "${HOME}/.config/shell/functions/log.sh"

log_info   "starting"                # plain fact
log_state  "Deploying app"           # cyan, action in progress
log_result "30 deployed, 0 failed"   # green, outcome
log_hint   "Re-run to fix"           # magenta, suggested next step
log_step   "Pulling images"          # dim, numbered/wizard step
log_warn   "fallback used"
log_error  "connection failed"
log_kv     duration=12s app=adguard status=ok
log_banner "Phase 1 complete" RESULT

# Wrap noisy subcommand output so each line stays grep-able and
# visually grouped under one header line:
docker compose pull 2>&1 | log_data INFO "Pulling images for adguard"
```

## Choosing a helper

Reach for the helper that best matches **what you're saying**, not just the
severity:

| You want to log…                                | Helper                            |
| ----------------------------------------------- | --------------------------------- |
| A plain informational fact                      | `log_info`                        |
| The action the script is currently taking       | `log_state "Deploying app"`       |
| The outcome of an operation (counts, totals)    | `log_result "30 deployed, 0 failed"` |
| A suggestion for the reader                     | `log_hint "Re-run with -v"`       |
| One step in a numbered / wizard-style sequence  | `log_step "Pulling images"`       |
| A noteworthy event that isn't a problem         | `log_notice`                      |
| A recoverable problem / fallback engaged        | `log_warn`                        |
| A failed operation; script may continue         | `log_error`                       |
| A failure the script will exit on               | `log_fatal`                       |
| An implementation detail (off by default)       | `log_debug` / `log_trace`         |
| Telemetry as flat key/value pairs               | `log_kv k=v k=v …`                |
| Multi-line payload (YAML/JSON/command output)   | `… \| log_data KIND "header"`     |
| Unbroken divider between groups                 | `log_sep`                         |
| Titled divider for a phase change               | `log_rule KIND "phase 1"`         |
| Boxed/wrapped title for a top-level boundary    | `log_banner "Done" RESULT`        |

`STATE` / `RESULT` / `HINT` / `STEP` are info-priority kinds — they never
change filtering behaviour, only color and label. Use them so `grep RESULT`
finds outcomes and `grep HINT` finds suggestions.

## Severity levels vs kinds

The library separates **severity** (controls filtering) from **kind**
(controls visual category). Both are first-class concepts.

| Concept  | Examples                              | Filtered by `LOG_LEVEL`? | Syslog priority |
| -------- | ------------------------------------- | ------------------------ | --------------- |
| Severity | `TRACE` `DEBUG` `INFO` `NOTICE` `WARN` `ERROR` `FATAL` | yes                      | matches         |
| Kind     | `STATE` `RESULT` `HINT` `STEP`        | rendered at `INFO`       | always `info`   |

Helpers:

| Function       | Severity | Kind     | Stream | Color (default)  |
| -------------- | -------- | -------- | ------ | ---------------- |
| `log_trace`    | TRACE    | TRACE    | stdout | dim              |
| `log_debug`    | DEBUG    | DEBUG    | stdout | dim cyan         |
| `log_info`     | INFO     | INFO     | stdout | none             |
| `log_notice`   | NOTICE   | NOTICE   | stdout | bold blue        |
| `log_warn`     | WARN     | WARN     | stderr | bold yellow      |
| `log_error`    | ERROR    | ERROR    | stderr | bold red         |
| `log_fatal`    | FATAL    | FATAL    | stderr | white on red     |
| `log_state`    | INFO     | STATE    | stdout | cyan             |
| `log_result`   | INFO     | RESULT   | stdout | green            |
| `log_hint`     | INFO     | HINT     | stdout | magenta          |
| `log_step`     | INFO     | STEP     | stdout | dim white        |
| `log_kv`       | INFO     | INFO     | stdout | none             |
| `log_data`     | (any)    | (any)    | stdout | per kind         |
| `log_sep`      | (any)    | (any)    | stdout | per kind         |
| `log_rule`     | (any)    | (any)    | stdout | per kind         |
| `log_banner`   | (any)    | STATE\*  | stdout | per kind         |

\* `log_banner` defaults to `STATE` kind; pass an explicit kind as the second
argument to override.

## Output format

### Text mode (default)

Human timestamp on a TTY, ISO-8601 UTC in log files and journald. The label
column is right-padded to 6 characters so output stays aligned:

```text
2026-04-29 20:27:28 INFO   [deploy] starting
2026-04-29 20:27:28 STATE  [deploy] Deploying app
2026-04-29 20:27:28 RESULT [deploy] 30 deployed, 0 failed
```

In a `LOG_FILE` (and in journald) the same call writes:

```text
2026-04-29T18:27:28Z STATE  [deploy] Deploying app
```

### JSON mode

Set `LOG_FORMAT=json` to emit one JSON object per call. Useful for piping
into `jq`, log shippers, or test assertions.

```json
{"timestamp":"2026-04-29T18:27:28Z","level":"INFO","kind":"STATE","tag":"deploy","message":"Deploying app"}
{"timestamp":"2026-04-29T18:27:28Z","level":"INFO","kind":"INFO","tag":"deploy","message":"config","data":"key: value\nlist:\n  - a"}
```

Keys are always present in the order: `timestamp`, `level`, `kind`, `tag`,
`message`, and optionally `data`. Empty `tag` becomes the empty string.

## Tag handling

The optional `[tag]` segment helps you tell scripts apart in log files. In
priority order:

1. **Explicit `LOG_TAG`** — validated against `^[A-Za-z0-9._-]{1,32}$`. Tags
   starting with `-` or `.` are rejected (would resemble flags or hidden
   files).
2. **Auto-detected basename** — when `log.sh` is sourced from a real script,
   the script's `$0` basename (without `.sh`/`.bash`/`.zsh`/`.ksh`) is used.
   Common shell names (`bash`, `zsh`, `log`, `log.sh`, …) are filtered out.
3. **Empty** — no tag rendered. This is the default for interactive shells.

This means `log_info hello` from a fish/zsh/bash prompt produces identical
output (no spurious `log.sh:` or shell-name prefix), while a real script
`deploy.sh` automatically tags its lines `[deploy]`.

## Banners and rules

```sh
log_sep STATE
log_rule STATE "phase 1"
log_banner "Deploying app" STATE
```

The `LOG_BANNER_STYLE` env var selects the visual style:

| Style     | Sample (40-wide)                                                   |
| --------- | ------------------------------------------------------------------ |
| `unicode` (default) | `━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`             |
| `ascii`   | `========================================`                         |
| `heavy`   | `########################################`                         |
| `box`     | `┌──────────────────────────────────────┐` … `└──────────────────┘` |
| `rule`    | `────────────────────────────────────────`                         |

Multi-byte styles (`unicode`, `box`, `rule`) automatically fall back to
`ascii` when:

- output is not a TTY (e.g. when piped to a file or used in CI),
- `LANG=C` / `LC_ALL=C` (no UTF-8 locale),
- `TERM=dumb`,
- `LOG_FORMAT=json` (banners collapse to a single JSON object with
  `kind=BANNER`).

This guarantees `LOG_FILE` output stays grep-friendly and pure ASCII.

Width is controlled by `LOG_RULE_WIDTH` (default 40, capped at `COLUMNS` or
80). Per-style override via `LOG_RULE_CHAR`.

## Structured payloads (JSON / YAML / logfmt)

Logging multi-line objects is messy by default — newlines break grep, ANSI
codes leak through, and the relationship between header and body is lost.
Three helpers solve this:

### `log_kv` — logfmt for flat key/value pairs

```sh
log_kv app=adguard duration=12s status=ok
log_kv "msg=hello world" status=ok           # values with spaces auto-quoted
```

```text
2026-04-29 20:27:28 INFO   app=adguard duration=12s status=ok
2026-04-29 20:27:28 INFO   msg="hello world" status=ok
```

### `log_data` — multiline payloads with continuation prefix

Reads the payload from stdin. On a TTY the payload lines are prefixed with
`│ ` so they visually belong to the previous header line; in `LOG_FILE` the
prefix is `| ` (ASCII). The whole block shares **one timestamp**, which is
what groups it.

The primary use case is wrapping the output of another command without
losing the rest of the log's structure:

```sh
docker compose pull 2>&1 | log_data INFO "Pulling images for adguard"
```

```text
2026-04-30 19:36:02 INFO   [deploy] Pulling images for adguard
2026-04-30 19:36:02 INFO   [deploy] │ [+] Pulling 6/6
2026-04-30 19:36:02 INFO   [deploy] │  ✔ adguard-redis Pulled    0.3s
2026-04-30 19:36:02 INFO   [deploy] │  ✔ adguard Pulled          0.4s
```

It also works for any payload variable:

```sh
printf '%s\n' "$yaml" | log_data INFO "config"
```

```text
2026-04-29 20:27:28 INFO   config
2026-04-29 20:27:28 INFO   │ name: my-app
2026-04-29 20:27:28 INFO   │ version: 1.2
2026-04-29 20:27:28 INFO   │ env:
2026-04-29 20:27:28 INFO   │   - PROD=1
```

Each line is independently grep-able and timestamped. In `LOG_FORMAT=json`
mode, the entire payload is emitted as the `data` field of a single JSON
object (newlines preserved as the literal two-char sequence `\n` so the
entry stays one JSON Line).

### `log_data <kind>` for visual emphasis

```sh
printf '%s\n' "$compose_diff" | log_data RESULT "image diff"
```

renders the header and continuation lines in green.

## Configuration env vars

| Var                  | Default      | Purpose                                                |
| -------------------- | ------------ | ------------------------------------------------------ |
| `LOG_LEVEL`          | `INFO`       | Minimum severity to emit                               |
| `LOG_TAG`            | (auto)       | Explicit tag, `[A-Za-z0-9._-]{1,32}`                   |
| `LOG_FORMAT`         | `text`       | `text` or `json`                                       |
| `LOG_COLOR`          | `auto`       | `auto`, `always`, `never` (also `NO_COLOR`)            |
| `LOG_BANNER_STYLE`   | `unicode`    | `unicode`, `ascii`, `heavy`, `box`, `rule`             |
| `LOG_RULE_WIDTH`     | `40`         | Banner / rule width                                    |
| `LOG_RULE_CHAR`      | per style    | Override the separator character                       |
| `LOG_MAX_BYTES`      | `8192`       | Per-line byte cap; longer lines are truncated         |
| `LOG_FILE`           | (none)       | Optional log file path                                 |
| `LOG_FILE_MAX_BYTES` | (none)       | Rotate when file exceeds this size                     |
| `LOG_FILE_TTL_DAYS`  | (none)       | Delete file when older than N days                     |
| `LOG_JOURNAL`        | `auto`       | `auto`, `always`, `never` — `logger(1)` integration   |
| `LOG_TO_STDIO`       | `1`          | Set to `0` to suppress stdout/stderr writes           |

`LOG_FILE` is only created when at least one of `LOG_FILE_MAX_BYTES` or
`LOG_FILE_TTL_DAYS` is set, so every log file has an explicit lifecycle.

## Security model

The logger is hardened against the following classes of attack — relevant
when log content is influenced by untrusted input (CI artifacts, container
labels, web requests, etc.).

| Risk                                            | Mitigation                                                          |
| ----------------------------------------------- | ------------------------------------------------------------------- |
| ANSI escape injection (terminal hijacking)      | `\033`, `\007`, `\000` stripped from messages before output         |
| Newline / CR smuggling (multi-line forge)       | `\n` and `\r` escaped to literal two-char sequences; one entry = one line |
| Format-string attacks (`%s`, `%n`, …)           | Every emitter uses `printf '%s'`; user data never becomes a format  |
| `logger -t` flag injection via `LOG_TAG`        | Tag validated against strict regex; bad values silently dropped     |
| Bash-style flag injection (`--inject` as tag)   | Tags starting with `-` or `.` rejected                              |
| `LOG_FILE` symlink redirection                  | Refused if the path resolves through a symlink                      |
| DoS via huge payload                            | Lines truncated at `LOG_MAX_BYTES` (default 8 KiB) with marker      |

These guarantees apply to **the message and tag**. Environment variables
(LOG_FILE, LOG_FORMAT, …) are configuration surface — keep them under your
control.

## Examples

### A typical setup script

```sh
#!/bin/sh
. "$HOME/.config/shell/functions/log.sh"
LOG_TAG="bootstrap"

log_step "Detecting platform"
log_state "Installing packages"

if ! sudo apt-get update >/tmp/apt.log 2>&1; then
    log_data ERROR "apt-get update failed" </tmp/apt.log
    log_hint "Check your network connection or run 'apt-get update' manually"
    exit 1
fi

log_result "All packages installed"
log_banner "Setup complete" RESULT
```

### Switching to JSON for CI

```sh
LOG_FORMAT=json LOG_TAG=ci ./script.sh | jq 'select(.level == "ERROR")'
```

### File logging with rotation

```sh
LOG_FILE=/var/log/myjob.log LOG_FILE_MAX_BYTES=$((10*1024*1024)) ./myjob.sh
```

## Tab completion

Shell completions for the `log` dispatcher are installed for **Fish**,
**Bash**, and **Zsh**. Tab on the first argument lists all severities and
kinds with descriptions:

```text
$ log <TAB>
banner  debug   error   fatal   hint    info    notice  result  state   step    trace   warn
```

Completion files:

- Fish: [`home/dot_config/fish/completions/log.fish`](https://github.com/DevSecNinja/dotfiles/blob/main/home/dot_config/fish/completions/log.fish)
- Bash: [`home/dot_config/shell/completions.d/log.bash`](https://github.com/DevSecNinja/dotfiles/blob/main/home/dot_config/shell/completions.d/log.bash)
- Zsh: [`home/dot_config/shell/completions.d/log.zsh`](https://github.com/DevSecNinja/dotfiles/blob/main/home/dot_config/shell/completions.d/log.zsh)

The per-helper functions (`log_info`, `log_warn`, …) are completed by the
shell's built-in function-name completion in Bash and Zsh.

## Consuming `log.sh` from other repositories

Other projects can vendor `log.sh` from a tagged GitHub Release of this
repository — no `chezmoi`, submodule, or package manager required.

### Prefix install (recommended for machines)

Install the packaged tarball into a prefix. This installs the library,
README, license, and shell completions without copying release assets by hand:

```sh
tmp="$(mktemp -d)"
curl -fsSL https://github.com/DevSecNinja/dotfiles/releases/download/v0.1.0/install-log-sh.sh \
  -o "$tmp/install-log-sh.sh"
curl -fsSL https://github.com/DevSecNinja/dotfiles/releases/download/v0.1.0/install-log-sh.sh.sha256 \
  -o "$tmp/install-log-sh.sh.sha256"
( cd "$tmp" && sha256sum -c install-log-sh.sh.sha256 )
sh "$tmp/install-log-sh.sh" --version v0.1.0 --prefix "$HOME/.local"
rm -rf "$tmp"
```

Then source it from scripts or shell startup files:

```sh
. "$HOME/.local/lib/log-sh/log.sh"
```

Omit `--version` to install the latest release, or keep the explicit tag for
reproducible installs.

### Vendored single-file install

```sh
mkdir -p scripts/lib
curl -fsSL https://github.com/DevSecNinja/dotfiles/releases/download/v0.1.0/log.sh \
  -o scripts/lib/log.sh
curl -fsSL https://github.com/DevSecNinja/dotfiles/releases/download/v0.1.0/log.sh.sha256 \
  -o scripts/lib/log.sh.sha256
( cd scripts/lib && sha256sum -c log.sh.sha256 )
```

Replace `v0.1.0` with the latest release tag. The release page also ships an
`install-log-sh.sh` installer and `log-sh-<version>.tar.gz` (library +
installer + completions + LICENSE + README) for projects that want a
prefix-style package.

### Verifying provenance (recommended)

Releases are signed via [GitHub Artifact Attestations][attest] (Sigstore
under the hood). The signing identity is the dotfiles release workflow
itself, so a tampered asset fails verification:

```sh
gh attestation verify ./scripts/lib/log.sh --repo DevSecNinja/dotfiles
```

Tag protection on `v*` plus the "Immutable releases" repository setting
mean a published release tag cannot be re-pointed and its assets cannot
be rewritten — your pinned `curl` URL is stable for the life of the tag.

[attest]: https://docs.github.com/actions/security-guides/using-artifact-attestations-to-establish-provenance-for-builds

### Use it

```sh
. scripts/lib/log.sh
LOG_TAG=mytool
log_info "ready"
log_state "Phase 1"
log_result "done"
```

### Auto-update with Renovate

Renovate's regex manager can keep the pinned tag fresh. Add this to your
consumer repo's `renovate.json5`:

```json5
{
  customManagers: [
    {
      customType: "regex",
      description: "Update DevSecNinja/dotfiles log.sh release pin",
      managerFilePatterns: ["/(^|/)scripts/lib/log\\.sh$/", "/\\.sh$/", "/\\.sh\\.tmpl$/"],
      matchStrings: [
        "DevSecNinja/dotfiles/releases/download/(?<currentValue>v[^/]+)/log\\.sh",
      ],
      depNameTemplate: "DevSecNinja/dotfiles",
      datasourceTemplate: "github-releases",
    },
  ],
}
```

Pair with a small refresher script (committed in the consumer repo) that
re-downloads the file when the pinned URL changes — Renovate opens a PR,
the script runs in CI, and the vendored copy is updated.

### Packaging choice

The supported packaging path is GitHub Release assets: a raw vendorable
`log.sh`, a prefix installer, and a tarball containing the library,
completions, README, and license.

Why not GitHub Packages, npm, or Homebrew?

- **GitHub Packages** does not host plain shell tarballs; the available
  formats (npm / NuGet / Maven / OCI) all add a client-tooling dependency
  that conflicts with the "works in offline / locked-down containers"
  constraint.
- **npm / pip** are the wrong ecosystem for POSIX shell.
- **Homebrew** is great for dev machines but useless on minimal
  containers and most servers.

GitHub Release assets (`https://github.com/.../releases/download/...`) are
versioned, immutable, public, cacheable, and require nothing more than
`curl`. That's the recommended channel.

If you later want an OCI artifact too, `oras push ghcr.io/devsecninja/log-sh:<tag>`
can be layered on top of the existing release flow as a follow-up.

## Troubleshooting

**No tag is shown when I run `log_info`.**
That's intentional when called interactively. Set `LOG_TAG` explicitly, or
run from a real script — the basename will be auto-detected.

**Why is my banner ASCII even with `LOG_BANNER_STYLE=unicode`?**
Banners auto-fall-back to ASCII when not on a TTY (CI, file output, piped
to another command) or when the locale is `C`. Set `LANG=en_US.UTF-8` and
ensure stdout is a terminal.

**My JSON line is invalid.**
Open an issue. JSON output goes through a strict escaper covering
`\`, `"`, control bytes, and tabs. Provide the input that produced the
broken line.

**Performance.**
Sourced calls average <1 ms per call; standalone (script invocation per
line) adds ~5 ms of process startup. For very high-volume loops, source the
library and call helpers in-process.
