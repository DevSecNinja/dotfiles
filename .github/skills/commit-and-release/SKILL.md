---
name: commit-and-release
description: >
    Guide for writing Conventional Commit messages, committing changes, and
    creating releases in this repository. Use when asked to commit, write a
    commit message, stage files, push, or create/cut a release.
---

## Commit message format

All commits follow [Conventional Commits](https://www.conventionalcommits.org):

```
<type>(<scope>): <description>
```

**Types:**

| Type       | When to use                                            |
| ---------- | ------------------------------------------------------ |
| `feat`     | New dotfile, function, helper, or capability           |
| `fix`      | Correcting a bug, misconfiguration, or broken behavior |
| `chore`    | Tooling, dependencies, version bumps                   |
| `ci`       | Changes to GitHub Actions workflows or lefthook config |
| `docs`     | Documentation only                                     |
| `refactor` | Code/config restructure without behavior change        |
| `test`     | Adding or fixing tests                                 |
| `perf`     | Performance-only changes                               |
| `build`    | Build / packaging changes (e.g. release artifacts)     |

**Scope** is the subsystem being changed. Pick whichever fits best:

- Shells: `fish`, `bash`, `zsh`, `pwsh`
- Tools: `chezmoi`, `mise`, `lefthook`, `cog`, `git-cliff`, `git`, `tmux`,
  `vim`, `nano`, `omp` (oh-my-posh), `gh`
- Library / utilities: `log`, `scripts`, `helpers`, `aliases`, `completions`
- Setup / runtime: `install`, `devcontainer`, `windows`, `linux`, `wsl`
- Repo plumbing: `release`, `renovate`, `tests`, `docs`, `extensions`,
  `pwsh-profile`

Multi-area changes may omit the scope.

**Breaking changes** are indicated in one of two ways (or both):

- `!` immediately before the colon: `feat(log)!: rename log_warn to log_warning`
- A `BREAKING CHANGE:` footer in the commit body (MUST be uppercase):

  ```
  feat(log): rename log_warn to log_warning

  BREAKING CHANGE: log_warn helper has been renamed to log_warning;
  update consumer scripts.
  ```

| Commit type       | Version bump |
| ----------------- | ------------ |
| `fix`             | PATCH        |
| `feat`            | MINOR        |
| `BREAKING CHANGE` | MAJOR        |

### Examples

```
feat(log): add log_data helper for multi-line payloads
fix(scripts): handle apt held-back packages
chore(mise): bump git-cliff to 2.13.1
ci(release): add cocogitto bump workflow
docs(logging): document log.sh consumption from other repos
refactor(fish): split aliases into conf.d files
test(log): add bats coverage for json output
```

### Verify before committing

Use `cog verify` to check a message before committing:

```sh
mise exec -- cog verify "feat(log): add log_data helper"
```

Exit code 0 = valid. The `commit-msg` lefthook runs this automatically on
every `git commit`.

---

## Commit workflow (step-by-step procedure)

Follow these steps in order every time the user asks to commit, push, or
"commit & push".

### Step 1 — Inspect what changed

```sh
git diff --stat HEAD
git status --short
```

Use this to understand the scope: which subsystems, which file types, how
many files.

### Step 2 — Stage the files

Prefer explicit paths over `git add .`:

```sh
git add home/dot_config/shell/functions/log.sh docs/logging.md
```

If the user has already staged files, skip this step.

### Step 3 — Derive and validate the commit message

Draft a message following the Conventional Commits format above. Then
validate it with `cog verify` before asking the user:

```sh
mise exec -- cog verify "feat(log): add log_data helper"
```

Exit code 0 = valid. If it fails, fix the message and retry.

### Step 4 — Ask the user to confirm the commit message

**MANDATORY**: Before committing, use the `vscode_askQuestions` tool to
present the proposed commit message and ask for confirmation. Provide the
message as an option the user can click — do not just print it in chat.

Example question structure:

- Header: "Commit message"
- Question: "Does this commit message look right?"
- Options: the proposed message as a selectable option, plus "Let me edit
  it" as a free-form alternative
- Set `allowFreeformInput: true` so the user can type a corrected message

If the user selects the proposed message, proceed. If they provide a
different message, use that one and re-run `cog verify` before continuing.

### Step 5 — Run the pre-commit hook

Run lefthook explicitly so linting errors are surfaced before the commit:

```sh
mise exec -- lefthook run pre-commit
```

If any check fails, **stop and report the errors**. Do not commit until all
checks pass. The pre-commit hook in this repo runs `shellcheck`, `shfmt`,
and `file-set-execution-bit` on staged shell files.

### Step 6 — Commit

```sh
git commit -m "<confirmed-message>"
```

The `commit-msg` hook will re-run `cog verify` automatically. Both hooks
must pass.

### Step 7 — Push

```sh
git push
```

---

## Making a commit

1. Stage the relevant files — prefer explicit paths over `git add .`:

   ```sh
   git add home/dot_config/fish/config.fish docs/customization.md
   ```

2. Commit with a Conventional Commit message:

   ```sh
   git commit -m "feat(fish): add abbreviation for chezmoi apply"
   ```

   The pre-commit hook runs all linters automatically. The commit-msg hook
   validates the message with `cog verify`. Both must pass.

3. For multi-paragraph commit bodies, write the subject line first, leave a
   blank line, then add detail:

   ```sh
   git commit -m "feat(log): add log_data helper for multi-line payloads

   - Sanitizes ANSI/CR/LF/NUL automatically
   - Keeps each payload line independently grep-able
   - Tested under sh, bash, zsh, and dash"
   ```

---

## Creating a release

**Prerequisites:** working tree must be clean (all changes committed) and
in sync with `origin`.

### Pull latest changes first

Always sync before releasing to avoid push rejections:

```sh
git pull origin main
```

### Dry-run first

Always preview before releasing:

```sh
mise exec -- cog bump --minor --dry-run   # shows next version, e.g. v0.2.0
mise exec -- cog bump --patch --dry-run
mise exec -- cog bump --auto --dry-run    # cocogitto picks the bump
```

You can also preview the upcoming release notes without bumping:

```sh
task release:notes
```

### Cut the release

```sh
mise exec -- cog bump --minor   # or --patch for bug-fix releases
# Equivalent shortcut:
task release:bump -- --minor
```

`cog bump` executes this pipeline automatically (configured in
[`cog.toml`](../../../cog.toml)):

1. Calculates the next semver version from conventional commits since the
   previous tag.
2. Runs `git-cliff` to regenerate `CHANGELOG.md` (range configured in
   `cog.toml`, template in `cliff.toml`).
3. Runs `dprint fmt CHANGELOG.md` if dprint is available (no-op otherwise).
4. Stages `CHANGELOG.md` and creates a `chore(version): <version>` commit.
5. Creates the `v<version>` git tag.
6. Pushes the commit and the tag to `origin`.

The tag push triggers
[`.github/workflows/release.yml`](../../workflows/release.yml), which:

- Generates release-scoped notes with `git-cliff --latest --strip all`.
- Builds the `log.sh` distribution artifacts via
  [`script/build-log-sh-release.sh`](../../../script/build-log-sh-release.sh):
  `log.sh`, `log.sh.sha256`, `log-sh-<tag>.tar.gz`, and the tarball's
  `.sha256`.
- Generates Sigstore [build-provenance attestations][attest] for `log.sh`
  and the tarball via `actions/attest-build-provenance`. Verifiable with
  `gh attestation verify <file> --repo DevSecNinja/dotfiles`.
- Creates the GitHub Release in a single `gh release create` call (notes
  + title + all four assets). Because nothing is edited or uploaded
  post-publish, the release is compatible with the repo's **Immutable
  Releases** setting.

[attest]: https://docs.github.com/actions/security-guides/using-artifact-attestations-to-establish-provenance-for-builds

The repository also has tag protection on `v*` (no force-push, no
deletion) and Immutable Releases enabled, so once a release is cut the
tag and asset bytes are frozen for life.

---

## Release complete

After every successful release, end with a celebrative message. Be
enthusiastic, reference the version number, and congratulate on shipping.
Make it fun — this is a milestone worth celebrating! Example:

> "SHIP IT! v0.2.0 is now LIVE — log.sh tarball published, changelog
> regenerated, CI green. Time to crack open a cold one — you've earned it!"
