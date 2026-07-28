# GitHub Repository Configuration

Audit and enforce a shared configuration baseline across your GitHub
repositories, so settings that were configured once by hand don't silently
drift apart across dozens of repos.

Four functions in the `DotfilesHelpers` module:

| Function                  | Purpose                                                |
| ------------------------- | ------------------------------------------------------ |
| `Get-GitHubRepoBaseline`  | The desired state — a single, editable source of truth |
| `Get-GitHubRepoConfig`    | Read-only audit of one, several or all repositories    |
| `Set-GitHubRepoConfig`    | Remediation, with `-WhatIf` dry runs                   |
| `Get-GitHubAppCredential` | Reads a GitHub App ID and private key from 1Password   |

## Requirements

- The [GitHub CLI](https://cli.github.com/) (`gh`), authenticated with
  `gh auth login`. All authentication is delegated to `gh`; no token is read,
  stored or logged by these functions.
- The [1Password CLI](https://developer.1password.com/docs/cli/) (`op`), only
  when rolling out GitHub App credentials.

Your `gh` token needs these fine-grained permissions:

| Category        | Permission                                     |
| --------------- | ---------------------------------------------- |
| `Settings`      | Administration: read & write                   |
| `Actions`       | Administration: read & write                   |
| `Ruleset`       | Administration: read & write                   |
| `AppCredential` | Secrets: read & write, Variables: read & write |

Categories whose permissions are missing are skipped with a warning rather than
failing the run, so a token with narrower scopes still produces a useful audit.

## Quick start

Audit everything and list what drifted:

```powershell
Get-GitHubRepoConfig -All |
    Where-Object { -not $_.IsCompliant } |
    Select-Object Repository, DriftCount
```

Inspect one repository in detail:

```powershell
(Get-GitHubRepoConfig -Repository docker).Drift | Format-Table
```

```text
Category Setting                     Current            Desired
-------- -------                     -------            -------
Settings allow_merge_commit          True               False
Settings allow_rebase_merge          True               False
Settings delete_branch_on_merge      False              True
Settings squash_merge_commit_title   COMMIT_OR_PR_TITLE PR_TITLE
Ruleset  ruleset_present             False              True
```

Dry run the fix, then apply it:

```powershell
Get-GitHubRepoConfig -All | Set-GitHubRepoConfig -WhatIf
Get-GitHubRepoConfig -All | Set-GitHubRepoConfig
```

`Get-GitHubRepoConfig` is strictly read-only, and `Set-GitHubRepoConfig` only
writes the fields that actually differ — so re-running is cheap and idempotent.

## The baseline

`Get-GitHubRepoBaseline` is the single place to change the standard. Both the
audit and the remediation read from it, so an edit propagates to both.

### Settings

| Setting                       | Value      | Why                                            |
| ----------------------------- | ---------- | ---------------------------------------------- |
| `allow_squash_merge`          | `true`     | Linear history                                 |
| `allow_merge_commit`          | `false`    |                                                |
| `allow_rebase_merge`          | `false`    |                                                |
| `allow_auto_merge`            | `true`     | Lets Renovate and release PRs land on green    |
| `delete_branch_on_merge`      | `true`     | Stops automation branches accumulating         |
| `allow_update_branch`         | `true`     |                                                |
| `squash_merge_commit_title`   | `PR_TITLE` | release-please parses the PR title for semver  |
| `squash_merge_commit_message` | `BLANK`    | Keeps WIP commit messages out of the changelog |
| `has_issues`                  | `true`     |                                                |
| `has_wiki`                    | `false`    |                                                |
| `has_projects`                | `false`    |                                                |
| `has_discussions`             | `false`    |                                                |
| `web_commit_signoff_required` | `false`    |                                                |

### Actions

| Setting                            | Value   | Why                                                  |
| ---------------------------------- | ------- | ---------------------------------------------------- |
| `default_workflow_permissions`     | `read`  | Least privilege; workflows opt in via `permissions:` |
| `can_approve_pull_request_reviews` | `false` | See the warning below                                |

!!! warning "Why `can_approve_pull_request_reviews` stays false"

    That repository toggle is a single switch for two capabilities: letting
    Actions **create** pull requests and letting Actions **approve** them. The
    approval half is the dangerous one — a `GITHUB_TOKEN` approval counts
    toward required reviews, so any workflow with `pull-requests: write` could
    rubber-stamp its own PR and satisfy branch protection on its own.

    If you need automation to open PRs, use a GitHub App token instead
    (see [App credentials](#app-credentials)). App-opened PRs also trigger
    `pull_request` workflows, which `GITHUB_TOKEN`-opened PRs deliberately do
    not — so required status checks actually run.

### Ruleset

Protects the default branch while keeping **you** able to bypass it.

| Setting                    | Value     |
| -------------------------- | --------- |
| `Name`                     | `Default` |
| `RequirePullRequest`       | `true`    |
| `RequiredApprovingReviews` | `0`       |
| `BlockDeletion`            | `true`    |
| `BlockForcePush`           | `true`    |
| `AllowedMergeMethods`      | `squash`  |
| `AdminCanBypass`           | `true`    |

The name matches what GitHub's own UI creates, so a repository that already has
a ruleset is updated in place rather than gaining a second, competing one. If
yours is named differently, override it:

```powershell
Get-GitHubRepoConfig -All -Baseline @{ Ruleset = @{ Name = 'Protect main branch' } }
```

`AdminCanBypass` adds the **Repository admin** role (`actor_id: 5`) as a
`bypass_mode: always` actor. On a personal account that is you, so you keep the
ability to push directly to `main` and merge without a PR.

Automation does **not** get that bypass, and that is the point: it means
`contents: write` held by a workflow — or a leaked GitHub App key — stops being
equivalent to "push straight to `main`".

Set `RequiredApprovingReviews` above zero only if someone other than you
reviews; on a solo repository a required approval you cannot self-grant will
block your own PRs.

### Existing rules are preserved

The rulesets API replaces the whole object on update, which makes a naive PUT
destructive. When updating in place, only the three rules this baseline
owns — `deletion`, `non_fast_forward` and `pull_request` — are replaced.
Everything else is carried over verbatim:

- `required_status_checks` keeps its full context list
- `copilot_code_review` and any other rule type is left alone
- Existing bypass actors (GitHub Apps, teams) are kept; the admin role is added
  only if it is missing
- A custom `ref_name` condition is preserved rather than being retargeted to
  `~DEFAULT_BRANCH`

!!! note "Private repositories need GitHub Pro"

    Rulesets are unavailable on private repositories on the Free plan. Those
    repositories are skipped with a warning instead of failing the run.

## Overriding the baseline

Pass `-Baseline` to override individual keys. Sections merge, so a partial
override does not discard the rest:

```powershell
# Permit wikis everywhere
Get-GitHubRepoConfig -All -Baseline @{ Settings = @{ has_wiki = $true } }

# Require one approving review
Get-GitHubRepoConfig -All -Baseline @{ Ruleset = @{ RequiredApprovingReviews = 1 } }
```

## Scoping a run

```powershell
# Fix merge strategies only, leaving Actions permissions and rulesets alone
Get-GitHubRepoConfig -All | Set-GitHubRepoConfig -Category Settings

# Audit a subset
Get-GitHubRepoConfig -Repository docker, blog, dotfiles

# Roll out branch protection everywhere, previewing first
Get-GitHubRepoConfig -All -Check Ruleset | Set-GitHubRepoConfig -WhatIf
```

### Forks

Forks are **included by default**, because a fork you have adopted as your own
project still wants the baseline. Skip them with `-ExcludeForks`:

```powershell
Get-GitHubRepoConfig -All -ExcludeForks | Set-GitHubRepoConfig -WhatIf
```

Every result also carries an `IsFork` property, so they can be filtered after
the fact:

```powershell
Get-GitHubRepoConfig -All | Where-Object { $_.IsFork }        # only forks
Get-GitHubRepoConfig -All | Where-Object { -not $_.IsFork }   # same as -ExcludeForks
```

Unlike archived repositories — which reject writes and are therefore excluded
by default — forks are perfectly writable, so excluding them is a judgement
call rather than a technical constraint.

`-Check` selects what to audit; `-Category` selects what to remediate.
Repository names may be bare (`docker`), qualified (`DevSecNinja/docker`) or a
full URL. Bare names are qualified with `-Owner`, which defaults to
`$env:CHEZMOI_GITHUB_USERNAME` and then to the authenticated `gh` user.

Archived repositories are excluded from `-All` and are skipped by
`Set-GitHubRepoConfig`, since they reject writes.

## App credentials

`AppCredential` is opt-in via `-Check AppCredential`, because listing secrets
needs extra token scopes. It verifies that the Actions variable
`AUTOMATION_APP_ID` and the secret `AUTOMATION_APP_PRIVATE_KEY` exist.

### The 1Password entry

Create this once — the defaults expect it, so no configuration is needed:

|                     |                                                          |
| ------------------- | -------------------------------------------------------- |
| Vault               | `Private`                                                |
| Item                | `GitHub Automation App` (category: **API Credential**)   |
| Field `app-id`      | The numeric **App ID** from the App's settings page      |
| Field `private-key` | The full PEM, including the `-----BEGIN ... -----` lines |

In the 1Password app, or from the CLI:

```powershell
op item create --category 'API Credential' --vault Private --title 'GitHub Automation App' `
    'app-id[text]=123456' `
    "private-key[password]=$(Get-Content .\your-app.private-key.pem -Raw)"
```

Use the **App ID**, not the client ID or the slug — the value is validated.

To keep the credential somewhere else, override per call or via environment
variables. Secret references are non-secret identifiers, useless without
authenticating to 1Password:

```powershell
Get-GitHubAppCredential -AppIdReference 'op://Work/Bot/app-id' -PrivateKeyReference 'op://Work/Bot/private-key'

$env:OP_GITHUB_APP_ID_REF  = 'op://Work/Bot/app-id'
$env:OP_GITHUB_APP_KEY_REF = 'op://Work/Bot/private-key'
```

### Where the credential is stored

By default the credential goes into a GitHub Actions **environment** named
`production`, pinned to the default branch:

| Baseline key                | Default                                         |
| --------------------------- | ----------------------------------------------- |
| `AppCredential.Environment` | `production` (set to `''` for repository-level) |

The pin is the entire point. An environment secret is only safer than a
repository secret because the deployment branch policy stops a workflow running
on an attacker-controlled PR branch from reading it. `Get-GitHubRepoConfig`
therefore reports an environment without that policy as drift
(`environment_pinned_to_default_branch`), not just a missing environment.

Your workflow must opt in, or the secret is simply invisible to it:

```yaml
jobs:
  sync:
    environment: production   # required to see environment secrets
```

!!! warning "Private repositories fall back automatically"

    Environments, environment secrets and deployment branch policies are
    public-repository-only on the GitHub Free plan. Private repositories
    transparently fall back to repository-level secrets with a warning.

    Nothing is lost by that fallback: the branch policy is exactly what the
    Free plan withholds, and without it an environment secret is no safer than
    a repository secret. Upgrading to GitHub Pro enables environments on private
    repositories, after which a re-run moves them across.

### Rolling it out

```powershell
$cred = Get-GitHubAppCredential
Get-GitHubRepoConfig -All -Check AppCredential | Set-GitHubRepoConfig -AppCredential $cred -WhatIf
```

Remediation creates the environment, enables custom branch policies, pins it to
the default branch, then writes the variable and secret into it — in that order,
since each step depends on the previous one.

`Get-GitHubAppCredential` checks everything before reading a value, so a
missing entry fails immediately with a message naming what to fix rather than
surfacing as an empty secret partway through the rollout. It verifies that
`op` is installed, that 1Password is unlocked, that the item exists in the
vault, and that both fields exist on it — listing the fields that _are_ present
when one is missing.

The private key is held as a `SecureString` and piped to `gh secret set` on
standard input, so the PEM never appears in a process argument list or on disk.

!!! danger "Never give this credential `administration` permissions"

    The App's private key ends up as an Actions secret in every repository it is
    installed on. Anyone who can edit a workflow in **any** of those
    repositories can mint a token with the App's **full** installation
    permissions — the `permission-*` downscoping in
    `actions/create-github-app-token` is a self-imposed request, not a platform
    constraint.

    Keep the installation to Contents, Pull requests and Issues `write`. Drive
    repository settings from your own `gh` login instead, so the
    `administration` permission never lives inside CI.

## Output

`Get-GitHubRepoConfig` emits one object per repository:

| Property                             | Description                                              |
| ------------------------------------ | -------------------------------------------------------- |
| `Repository`                         | `owner/name`                                             |
| `IsCompliant`                        | `$true` when nothing drifted                             |
| `DriftCount`                         | Number of drifted settings                               |
| `Drift`                              | Records with `Category`, `Setting`, `Current`, `Desired` |
| `Current`                            | The values read from GitHub                              |
| `Baseline`                           | The desired state used for this comparison               |
| `RulesetId`                          | Existing ruleset id, so `Set` updates in place           |
| `Visibility`, `IsArchived`, `IsFork` | Repository metadata                                      |

`Set-GitHubRepoConfig -PassThru` reports `Applied` and `Skipped` per repository.

## Testing

```powershell
./tests/powershell/Invoke-PesterTests.ps1 -Tag Unit
```

Every external dependency is mocked at the module's own CLI wrappers, so the
suite runs on any platform without `gh` or `op` installed and never touches a
real repository.
