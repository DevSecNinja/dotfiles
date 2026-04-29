---
name: shell-logging
description: Shell logging library (log.sh) usage. Use this when writing or modifying shell scripts under home/ that emit diagnostic output.
---

# Shell Logging with `log.sh`

This skill applies whenever you write or modify shell code (Bash / Zsh / POSIX
sh) under `home/` that prints status, progress, or error messages. Use the
`log.sh` helpers instead of raw `echo` / `printf`.

Library: [`home/dot_config/shell/functions/log.sh`](../../../home/dot_config/shell/functions/log.sh)
Reference docs: [`docs/logging.md`](../../../docs/logging.md)

## When to use

- New scripts under `home/` (Chezmoi-managed) that emit any diagnostic line.
- Existing scripts being touched: replace ad-hoc `echo "[INFO] ..."` /
  `echo "===="` patterns with the helpers.
- Anywhere you need consistent formatting across Bash, Zsh, and Fish.

Do **not** introduce a separate logging style or wrapper. The library is
already sourced by `dot_zshrc` / `dot_bashrc` / `config.fish` for
interactive use, and any sourced/standalone script can use it directly.

## Sourcing

```sh
. "$HOME/.config/shell/functions/log.sh"
LOG_TAG="my-script"   # optional; auto-detected from $0 otherwise
```

In Fish scripts, prefer running the standalone executable:

```fish
~/.config/shell/functions/log.sh INFO "starting"
```

The auto-loaded Fish wrapper also exposes `log` as a function.

## Severity vs kind

| Concern                  | Helper(s)                                               |
| ------------------------ | ------------------------------------------------------- |
| Filtering by severity    | `log_trace` `log_debug` `log_info` `log_notice` `log_warn` `log_error` `log_fatal` |
| Visual category (info)   | `log_state` (cyan) `log_result` (green) `log_hint` (magenta) `log_step` (dim) |
| Structure / grouping     | `log_sep` `log_rule "<title>"` `log_banner "<title>" [KIND]` |
| Structured data          | `log_kv key=value …` `log_data <KIND> <message>` (stdin) |

`STATE`/`RESULT`/`HINT`/`STEP` are info-priority — they never affect
filtering, only color/label. Reach for them when scanning logs by eye.

## Idiomatic patterns

### Phased operation

```sh
log_step  "Pulling images"
docker compose pull >/tmp/pull.log 2>&1 || {
    log_data ERROR "docker pull failed" </tmp/pull.log
    exit 1
}
log_state "Deploying"
docker compose up -d --wait
log_result "Deployed in $((SECONDS))s"
log_banner "Done" RESULT
```

### Telemetry as logfmt

```sh
log_kv app="$app" image="$image" duration="${dur}s" status=ok
```

### Structured payload

```sh
printf '%s\n' "$compose_diff" | log_data STATE "compose changes"
```

### Switching to JSON for CI / automation

```sh
LOG_FORMAT=json LOG_TAG=ci ./script.sh | jq 'select(.level == "ERROR")'
```

## Security / correctness rules

1. **Never** pass untrusted data through `printf "$msg"` directly. Use the
   helpers; they always go through `printf '%s'`. The library strips ANSI,
   CR, LF, NUL, and truncates to `LOG_MAX_BYTES`.
2. **Multi-line content** (YAML, JSON, command output) goes through
   `log_data` so each payload line stays its own grep-able log entry.
3. **Tag naming**: stick to `[A-Za-z0-9._-]{1,32}` — anything else is
   rejected and the line falls back to no tag. Tags starting with `-` or
   `.` are rejected to prevent flag-injection into `logger(1)`.
4. **`LOG_FILE`** requires either `LOG_FILE_MAX_BYTES` or
   `LOG_FILE_TTL_DAYS`. Symlinks are refused.

## Testing changes

Tests live in `tests/bash/log-*.bats`, one file per concern:

| File                          | Concern                                              |
| ----------------------------- | ---------------------------------------------------- |
| `log-format.bats`             | Timestamps, padding, tag auto-detection              |
| `log-kinds.bats`              | STATE/RESULT/HINT/STEP, color, syslog mapping        |
| `log-banner.bats`             | All banner styles, fallback rules, file-flattening   |
| `log-injection.bats`          | ANSI / newline / format-string / tag / symlink       |
| `log-structured.bats`         | `log_kv`, `log_data`, JSON output                    |
| `log-shells.bats`             | sh / bash / zsh / fish wrapper consistency           |

When adding behaviour, add the corresponding test there. Run focused tests
with:

```bash
./tests/bash/run-tests.sh --test log-banner.bats
```

Always finish with `./tests/bash/run-tests.sh --ci` to catch regressions.

## Anti-patterns to avoid

- `echo "[INFO] ..."` — use `log_info` instead.
- `echo "===================="` — use `log_sep` / `log_banner` / `log_rule`.
- `echo "DEBUG: $var"` — use `log_debug "var=$var"` or
  `log_kv var="$var"`.
- Custom shell-specific colorization — the library handles `LOG_COLOR`,
  `NO_COLOR`, and TTY detection consistently.
- Writing structured data inline in the message — use `log_kv` /
  `log_data` so log readers (and test assertions) can parse it.
