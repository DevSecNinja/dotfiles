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

**TL;DR:** you no longer cut releases by running `cog bump` locally.
Bumping is owned by [release-please][rp]. Your job is to **review and
merge the auto-opened release PR**.

[rp]: https://github.com/googleapis/release-please-action

### How the flow works

1. You merge `feat`/`fix`/`chore` PRs to `main` as usual.
2. [`.github/workflows/release-please.yml`](../../workflows/release-please.yml)
   runs on every push to `main` and **opens (or force-updates) a release
   PR** titled `chore(main): release vX.Y.Z` containing:
   - The next semver derived from Conventional Commits since the last tag
   - The corresponding `CHANGELOG.md` bump
   - An updated `.release-please-manifest.json`
3. CI runs on the release PR like any other PR. Branch protection is
   fully respected — there is no bypass.
4. When you're ready to ship, **review the release PR and merge it**.
5. release-please then **creates the `vX.Y.Z` tag** pointing at the
   merge commit and pushes it.
6. The tag push triggers the existing
   [`.github/workflows/release.yml`](../../workflows/release.yml), which:
   - Builds the `log.sh` distribution artifacts via
     [`script/build-log-sh-release.sh`](../../../script/build-log-sh-release.sh):
     `log.sh`, `log.sh.sha256`, `log-sh-<tag>.tar.gz`, and the tarball's
     `.sha256`.
   - Generates Sigstore [build-provenance attestations][attest] for
     `log.sh` and the tarball via `actions/attest-build-provenance`.
     Verifiable with `gh attestation verify <file> --repo DevSecNinja/dotfiles`.
   - Calls the central
     [`actions/release-publish`](https://github.com/DevSecNinja/.github/tree/main/actions/release-publish)
     composite action which generates Conventional-Commit notes via
     `git-cliff --latest --strip all`, appends the `log.sh` consumption
     snippet (preset `extra-notes: log-sh`), and creates the GitHub
     Release in a single `gh release create` call. Because nothing is
     edited or uploaded post-publish, the release is compatible with
     the repo's **Immutable Releases** setting.

[attest]: https://docs.github.com/actions/security-guides/using-artifact-attestations-to-establish-provenance-for-builds

The repository also has tag protection on `v*` (no force-push, no
deletion) and Immutable Releases enabled, so once a release is cut the
tag and asset bytes are frozen for life.

### Two CHANGELOGs, by design

- **In-tree `CHANGELOG.md`** is owned by release-please. Style: simple
  sectioned per-PR notes. Lives in the release PR commit.
- **GitHub Release notes** are owned by `git-cliff` (driven by
  [`cliff.toml`](../../../cliff.toml)) via the `release-publish`
  composite action. Style: scope-prefixed, commit-linked.

This split is intentional. The in-tree changelog is for browsers of the
repo; the Release body is for asset consumers and includes the `log.sh`
distribution snippet and attestation-verification commands.

### Local previews (optional)

Before merging the release PR you can preview what the GitHub Release
body will look like:

```sh
task release:notes      # git-cliff --unreleased --strip all
```

To build the log.sh distribution artifacts locally for inspection:

```sh
task release:build -- v0.1.0
```

There is intentionally **no `task release:bump`** — release-please
owns bumping.

### What if release-please's PR looks wrong?

- **Wrong version**: override by adding a `Release-As: X.Y.Z` footer to
  a commit on main. release-please picks it up on the next push.
- **Wrong changelog grouping**: edit
  [`release-please-config.json`](../../../release-please-config.json)
  (`changelog-sections`).
- **Force a release** when only `chore` commits exist since the last
  tag: push an empty commit with a `Release-As: X.Y.Z` footer.

### Release-pinned devcontainer image

A `v*` tag push also triggers
[`.github/workflows/devcontainer-prebuild.yaml`](../../workflows/devcontainer-prebuild.yaml),
which rebuilds the dev container image from the tagged source tree
(cache-warm via the `:amd64` / `:arm64` cache tags) and publishes
release-pinned tags alongside the rolling `:latest`:

- `ghcr.io/devsecninja/dotfiles-devcontainer:vX.Y.Z`
- `ghcr.io/devsecninja/dotfiles-devcontainer:X.Y.Z`

Both release tags are manifest lists pinned to the per-arch digests
pushed in the same run, so the release tags remain stable even after
the rolling `:amd64` / `:arm64` tags get overwritten by a future main
build.

The multi-arch manifest digest gets a Sigstore build-provenance
attestation pushed to the registry. Consumers can verify with:

```sh
gh attestation verify \
  oci://ghcr.io/devsecninja/dotfiles-devcontainer:vX.Y.Z \
  --repo DevSecNinja/dotfiles
```

GitHub Pages deployments (docs site) are signed transparently by
`actions/deploy-pages` via GitHub's trusted-publisher mechanism — no
extra attestation step is required.

### Pitfalls and lessons (learned the hard way)

These are real failure modes hit while building this pipeline. Reread
this list before changing anything in the release flow.

1. **Never write `[skip ci]` / `[ci skip]` / `[no ci]` /
   `[skip actions]` / `[actions skip]` in commit subject OR body** —
   GitHub Actions scans the entire commit message and silently skips
   the run. This even applies to commits that *document* those
   markers. When you must reference them, escape: backticks alone
   aren't enough — break the bracket pair.

2. **Cutting a release on red main ships broken bytes forever.**
   Immutable Releases means you cannot retract or rebuild — only cut a
   new version. With release-please this is naturally guarded: the
   release PR can't merge until required CI is green.

3. **`devcontainers/ci@v0.3` does NOT honour comma-separated values
   in `imageTag`.** Despite documentation suggesting otherwise, only
   the first tag is pushed. If you need multiple tags per build, use
   a single `imageTag` and derive additional tags via
   `docker manifest create` in a follow-up step.

4. **`gh release create` is single-shot for Immutable Releases.**
   Any subsequent `gh release upload --clobber` or `gh release edit`
   is rejected. The `release-publish` composite action assembles all
   assets, notes, title, and attestations in one step — don't add
   post-publish steps. release-please's own GitHub Release creation
   is **disabled** in
   [`release-please-config.json`](../../../release-please-config.json)
   (`"skip-github-release": true`) so it doesn't clash with the
   tag-triggered publish.

5. **Reusable workflows can't host attestations.**
   `attest-build-provenance` needs the OIDC token from the same job
   that produced the artifact. A reusable workflow inherits a
   different OIDC subject, so attestations created from inside the
   reusable workflow won't verify against the caller's source repo.
   The `release-publish` composite action lives in
   `DevSecNinja/.github` but **runs in the caller's job** (composite
   actions do, reusable workflows don't), which is why
   `attest-build-provenance` and the artifact build remain inline in
   `release.yml` even after consolidation.

6. **The OCI manifest digest comes from `docker manifest push` stdout**
   (e.g. `sha256:bb91…`). Capture it and pass it to
   `attest-build-provenance` as `subject-digest`; never compute a
   digest yourself with `sha256sum` on the manifest body — that's the
   wrong digest format for OCI.

7. **Verify attestations work after every release**:

   ```sh
   gh attestation verify \
     oci://ghcr.io/devsecninja/dotfiles-devcontainer:vX.Y.Z \
     --repo DevSecNinja/dotfiles
   gh attestation verify <log.sh-download> --repo DevSecNinja/dotfiles
   ```

   A passing release pipeline that fails verification means consumers
   can't trust your bytes. Run both spot-checks before the celebration.

8. **Direct `git push` to main is forbidden.** Branch protection
   requires all status checks. The legacy `cog bump` flow needed a
   per-release bypass; release-please does not. If a release-please
   PR somehow gets stuck, fix the underlying blocker (CI red, missing
   review) rather than reaching for a bypass.

---

## Release complete

After every successful release, end with a celebrative message. Be
enthusiastic, reference the version number, and congratulate on shipping.
Make it fun — this is a milestone worth celebrating! Example:

> "SHIP IT! v0.2.0 is now LIVE — log.sh tarball published, changelog
> regenerated, CI green. Time to crack open a cold one — you've earned it!"
