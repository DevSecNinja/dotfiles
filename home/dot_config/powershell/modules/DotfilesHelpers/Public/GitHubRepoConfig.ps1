# GitHub repository configuration helpers
#
# Audits and enforces a shared "best practices" baseline across GitHub
# repositories, so settings that were configured once by hand don't silently
# drift apart across dozens of repos.
#
# Design notes:
#   - Authentication is delegated entirely to the `gh` CLI. Whatever scopes
#     your `gh` login has are the scopes these functions get; no token is ever
#     read, stored or logged here. Repository settings require the fine-grained
#     `administration:write` permission; Actions variables/secrets require
#     `secrets:write` / `variables:write`.
#   - The GitHub App credentials pushed to repositories are read from 1Password
#     via `op read`, so the private key never lands on disk.
#   - Get-GitHubRepoConfig is read-only and pipes straight into
#     Set-GitHubRepoConfig, which supports -WhatIf for dry runs.
#
# Examples:
#   Get-GitHubRepoConfig -All | Where-Object { -not $_.IsCompliant }
#   Get-GitHubRepoConfig -Repository docker | Set-GitHubRepoConfig -WhatIf
#   Get-GitHubRepoConfig -All | Set-GitHubRepoConfig -Confirm:$false
#
# Author: Jean-Paul van Ravensberg

#region Private helpers

function Invoke-GitHubCli {
    <#
    .SYNOPSIS
        Invoke the `gh` CLI and return its stdout.
    .DESCRIPTION
        Single choke point for every `gh` invocation in this file. Keeping the
        process launch in one place means error handling is uniform and the
        whole module can be unit-tested by mocking this one function, without
        `gh` being installed on the test machine.
    .PARAMETER Arguments
        Argument array passed verbatim to `gh`.
    .PARAMETER StdIn
        Optional string piped to the process on standard input. Used for
        request bodies and secret values so they never appear in a process
        argument list, which is world-readable on most systems.
    .PARAMETER AllowFailure
        Return $null on a non-zero exit code instead of throwing.
    .PARAMETER ErrorContext
        Human-readable description of the operation, used in the error message.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $false)]
        [string]$StdIn,

        [Parameter(Mandatory = $false)]
        [switch]$AllowFailure,

        [Parameter(Mandatory = $false)]
        [string]$ErrorContext
    )

    if ([string]::IsNullOrWhiteSpace($ErrorContext)) {
        $ErrorContext = "gh $($Arguments -join ' ')"
    }

    if ($PSBoundParameters.ContainsKey('StdIn')) {
        $output = $StdIn | & gh @Arguments 2>&1
    }
    else {
        $output = & gh @Arguments 2>&1
    }

    if ($LASTEXITCODE -ne 0) {
        if ($AllowFailure) {
            Write-Verbose "$ErrorContext failed (exit $LASTEXITCODE): $output"
            return $null
        }
        throw "$ErrorContext failed (exit $LASTEXITCODE): $output"
    }

    return ($output | Out-String).Trim()
}

function Invoke-OnePasswordCli {
    <#
    .SYNOPSIS
        Resolve a 1Password secret reference with `op read`.
    .DESCRIPTION
        Wraps the single `op` invocation this module makes, so tests can mock
        it without 1Password being installed or unlocked.
    .PARAMETER Reference
        Secret reference in `op://Vault/Item/field` form.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Reference
    )

    $output = & op read $Reference 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "op read '$Reference' failed (exit $LASTEXITCODE)."
    }

    return ($output | Out-String).Trim()
}

function Test-GitHubCliReady {
    <#
    .SYNOPSIS
        Throw unless the `gh` CLI is installed and authenticated.
    .DESCRIPTION
        Central pre-flight for every function in this file. Failing fast here
        produces a single actionable error instead of a cascade of confusing
        API failures halfway through a bulk operation.
    #>
    [CmdletBinding()]
    param()

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "The GitHub CLI (gh) was not found on PATH. Install it from https://cli.github.com/ and run 'gh auth login'."
    }

    $null = & gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "The GitHub CLI is not authenticated. Run 'gh auth login' first."
    }
}

function Invoke-GitHubApi {
    <#
    .SYNOPSIS
        Invoke `gh api` and return the parsed JSON response.
    .DESCRIPTION
        Thin wrapper that centralises argument construction, error handling and
        JSON parsing. Request bodies are passed on stdin rather than as `-f`
        flags so that booleans and nulls survive with their real JSON types.
    .PARAMETER Endpoint
        API path, e.g. 'repos/OWNER/REPO'.
    .PARAMETER Method
        HTTP method. Defaults to GET.
    .PARAMETER Body
        Hashtable serialised to JSON and sent on stdin.
    .PARAMETER AllowFailure
        Return $null on a non-zero exit code instead of throwing. Used for
        endpoints that legitimately 404 (an absent ruleset) or 403 (a plan that
        does not include the feature).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Endpoint,

        [Parameter(Mandatory = $false)]
        [ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')]
        [string]$Method = 'GET',

        [Parameter(Mandatory = $false)]
        [hashtable]$Body,

        [Parameter(Mandatory = $false)]
        [switch]$AllowFailure
    )

    $ghArgs = @('api', $Endpoint, '--method', $Method)
    $cliArgs = @{
        Arguments    = $ghArgs
        ErrorContext = "gh api $Endpoint"
        AllowFailure = [bool]$AllowFailure
    }

    if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body -and $Body.Count -gt 0) {
        $cliArgs['Arguments'] = $ghArgs + @('--input', '-')
        $cliArgs['StdIn'] = ($Body | ConvertTo-Json -Depth 10 -Compress)
    }

    $text = Invoke-GitHubCli @cliArgs

    if ($null -eq $text -or [string]::IsNullOrWhiteSpace($text)) { return $null }

    try {
        $parsed = $text | ConvertFrom-Json
    }
    catch {
        throw "Could not parse the response from gh api $Endpoint as JSON: $_"
    }

    # Wrapped in a single-element array so that an empty JSON list survives the
    # return unrolled as an empty array rather than collapsing to $null, which
    # would be indistinguishable from a failed call.
    return , $parsed
}

function Get-GitHubRulesetList {
    <#
    .SYNOPSIS
        List the rulesets on a repository, distinguishing empty from unreadable.
    .DESCRIPTION
        `GET /repos/{owner}/{repo}/rulesets` returns `[]` for a repository with
        no rulesets and fails outright when the caller lacks the administration
        permission or the repository is private on a plan without rulesets.
        Those two cases require opposite handling - one is drift to remediate,
        the other must be skipped - so this returns an explicit Available flag
        rather than relying on $null.
    .PARAMETER Repository
        Repository in 'owner/name' form.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository
    )

    $response = Invoke-GitHubCli -Arguments @('api', "repos/$Repository/rulesets", '--method', 'GET') `
        -AllowFailure -ErrorContext "gh api repos/$Repository/rulesets"

    if ($null -eq $response) {
        return [PSCustomObject]@{ Available = $false; Rulesets = @() }
    }

    if ([string]::IsNullOrWhiteSpace($response)) {
        return [PSCustomObject]@{ Available = $true; Rulesets = @() }
    }

    try {
        return [PSCustomObject]@{ Available = $true; Rulesets = @($response | ConvertFrom-Json) }
    }
    catch {
        throw "Could not parse the ruleset list for ${Repository} as JSON: $_"
    }
}

function Resolve-GitHubRepoName {
    <#
    .SYNOPSIS
        Normalise a repository reference to 'owner/name'.
    .DESCRIPTION
        Accepts a bare name ('docker'), a qualified name ('DevSecNinja/docker')
        or a full URL and always returns 'owner/name'. Bare names are qualified
        with -Owner.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Repository,

        [Parameter(Mandatory = $false)]
        [string]$Owner
    )

    $name = $Repository.Trim()
    $name = $name -replace '^https?://github\.com/', ''
    $name = $name -replace '\.git$', ''
    $name = $name.Trim('/')

    if ($name -match '/') {
        $parts = $name -split '/'
        if ($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[0]) -or [string]::IsNullOrWhiteSpace($parts[1])) {
            throw "'$Repository' is not a valid repository reference. Use 'name' or 'owner/name'."
        }
        return "$($parts[0])/$($parts[1])"
    }

    if ([string]::IsNullOrWhiteSpace($Owner)) {
        throw "Repository '$Repository' has no owner. Pass 'owner/name' or supply -Owner."
    }

    return "$Owner/$name"
}

function Get-GitHubCurrentOwner {
    <#
    .SYNOPSIS
        Return the login of the authenticated GitHub user.
    .DESCRIPTION
        Prefers CHEZMOI_GITHUB_USERNAME (exported by the chezmoi-rendered
        PowerShell config) to save an API round-trip, and falls back to the
        authenticated user behind the `gh` CLI.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (-not [string]::IsNullOrWhiteSpace($env:CHEZMOI_GITHUB_USERNAME)) {
        return $env:CHEZMOI_GITHUB_USERNAME
    }

    $user = Invoke-GitHubApi -Endpoint 'user'
    if ($null -eq $user -or [string]::IsNullOrWhiteSpace($user.login)) {
        throw "Could not determine the authenticated GitHub user. Run 'gh auth login' or pass -Owner."
    }

    return $user.login
}

function ConvertFrom-DotfilesSecureString {
    <#
    .SYNOPSIS
        Convert a SecureString to plain text (Windows PowerShell 5.1 safe).
    .DESCRIPTION
        ConvertFrom-SecureString -AsPlainText only exists on PowerShell 7+, and
        this module targets 5.1. The unmanaged buffer is always freed in the
        finally block so the plaintext is not left on the heap.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '', Justification = 'Deliberate, scoped conversion required to hand the key to the gh CLI on stdin.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]$SecureString
    )

    $bstr = [IntPtr]::Zero
    try {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

# Repository role IDs used as ruleset bypass actors. GitHub does not expose
# these by name on the rulesets API, so the admin role is pinned by ID.
# 5 = Repository admin, i.e. the repository owner on a personal account.
$script:GitHubRepositoryRoleAdmin = 5

function New-GitHubRulesetPayload {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds and returns a hashtable; does not change system state.')]
    <#
    .SYNOPSIS
        Build the rulesets API payload for the desired branch protection.
    .DESCRIPTION
        Translates the Ruleset section of the baseline into the request body
        accepted by POST/PUT /repos/{owner}/{repo}/rulesets. The payload is
        always complete, because the rulesets API replaces the whole object on
        update and a partial body would silently drop rules.

        That same replace-everything behaviour makes updates destructive, so
        when -ExistingRuleset is supplied any rule this baseline does not manage
        (required_status_checks and its context list, copilot_code_review, and
        so on) is carried over verbatim, and existing bypass actors are kept.
        Only the managed rules - deletion, non_fast_forward and pull_request -
        are replaced.
    .PARAMETER Ruleset
        The Ruleset section of a baseline hashtable.
    .PARAMETER ExistingRuleset
        The current ruleset as returned by the API, when updating in place.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        $Ruleset,

        [Parameter(Mandatory = $false)]
        $ExistingRuleset
    )

    # Rule types this baseline owns. Anything else found on an existing ruleset
    # is preserved untouched.
    $managedRuleTypes = @('deletion', 'non_fast_forward', 'pull_request')

    $rules = [System.Collections.Generic.List[object]]::new()

    if ($null -ne $ExistingRuleset -and $null -ne $ExistingRuleset.rules) {
        foreach ($rule in $ExistingRuleset.rules) {
            if ($managedRuleTypes -notcontains $rule.type) {
                $rules.Add($rule)
            }
        }
    }

    if ($Ruleset.BlockDeletion) {
        $rules.Add(@{ type = 'deletion' })
    }

    if ($Ruleset.BlockForcePush) {
        $rules.Add(@{ type = 'non_fast_forward' })
    }

    if ($Ruleset.RequirePullRequest) {
        $rules.Add(@{
                type       = 'pull_request'
                parameters = @{
                    allowed_merge_methods             = @($Ruleset.AllowedMergeMethods)
                    dismiss_stale_reviews_on_push     = $false
                    require_code_owner_review         = $false
                    require_last_push_approval        = $false
                    required_approving_review_count   = $Ruleset.RequiredApprovingReviews
                    required_review_thread_resolution = $false
                }
            })
    }

    $bypassActors = [System.Collections.Generic.List[object]]::new()
    $hasAdminBypass = $false

    if ($null -ne $ExistingRuleset -and $null -ne $ExistingRuleset.bypass_actors) {
        foreach ($actor in $ExistingRuleset.bypass_actors) {
            if ($actor.actor_type -eq 'RepositoryRole' -and $actor.actor_id -eq $script:GitHubRepositoryRoleAdmin) {
                $hasAdminBypass = $true
                if (-not $Ruleset.AdminCanBypass) { continue }
            }
            $bypassActors.Add($actor)
        }
    }

    if ($Ruleset.AdminCanBypass -and -not $hasAdminBypass) {
        # Lets the repository admin (you) push directly to the default branch
        # and merge without a PR when needed, while everything else - including
        # GitHub Actions - stays subject to the rules.
        $bypassActors.Add(@{
                actor_id    = $script:GitHubRepositoryRoleAdmin
                actor_type  = 'RepositoryRole'
                bypass_mode = 'always'
            })
    }

    $conditions = @{
        ref_name = @{
            include = @('~DEFAULT_BRANCH')
            exclude = @()
        }
    }

    # Keep a deliberately narrower or broader ref condition if one is already
    # configured; retargeting someone's ruleset is not this tool's job.
    if ($null -ne $ExistingRuleset -and $null -ne $ExistingRuleset.conditions -and $null -ne $ExistingRuleset.conditions.ref_name) {
        $conditions = @{
            ref_name = @{
                include = @($ExistingRuleset.conditions.ref_name.include)
                exclude = @($ExistingRuleset.conditions.ref_name.exclude)
            }
        }
    }

    return @{
        name          = $Ruleset.Name
        target        = 'branch'
        enforcement   = $Ruleset.Enforcement
        bypass_actors = $bypassActors.ToArray()
        conditions    = $conditions
        rules         = $rules.ToArray()
    }
}

function New-GitHubConfigDrift {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds and returns an object; does not change system state.')]
    <#
    .SYNOPSIS
        Build a single drift record.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Setting,
        [Parameter(Mandatory = $false)]$Current,
        [Parameter(Mandatory = $false)]$Desired
    )

    return [PSCustomObject]@{
        PSTypeName = 'Dotfiles.GitHubRepoConfigDrift'
        Category   = $Category
        Setting    = $Setting
        Current    = $Current
        Desired    = $Desired
    }
}

#endregion Private helpers

function Get-GitHubRepoBaseline {
    <#
    .SYNOPSIS
        Return the desired-state baseline for GitHub repository configuration.

    .DESCRIPTION
        Single source of truth for "our best practices". Edit this function to
        change the standard; Get-GitHubRepoConfig and Set-GitHubRepoConfig both
        read from it, so a change here propagates to auditing and remediation
        at the same time.

        The Settings keys map 1:1 onto the fields accepted by
        `PATCH /repos/{owner}/{repo}`, and Actions keys onto
        `PUT /repos/{owner}/{repo}/actions/permissions/workflow`.

        Rationale for the defaults:
          - Squash-only merges keep a linear history and make the PR title the
            commit subject, which is what release-please parses for semver.
          - squash_merge_commit_message = BLANK stops individual WIP commit
            messages leaking into the changelog.
          - delete_branch_on_merge keeps stale automation branches (such as
            chore/config-sync) from accumulating.
          - can_approve_pull_request_reviews stays false: that toggle also
            grants workflows the ability to approve their own pull requests,
            which would let automation satisfy required reviews on its own.
          - default_workflow_permissions = read follows least privilege;
            workflows that need more request it explicitly via `permissions:`.
          - The Ruleset name matches what GitHub's UI creates ('Default'), so
            a repository that already has one is updated in place instead of
            gaining a second, competing ruleset. Override Name if yours differs.
          - The Ruleset section protects the default branch while listing the
            repository admin role as a bypass actor, so you keep the ability to
            push directly or merge without a PR. Automation does not get that
            bypass, which is the point: `contents: write` held by a workflow or
            a leaked App key stops being equivalent to "push to main".

    .PARAMETER Override
        Hashtable merged over the defaults. Top-level keys are 'Settings',
        'Actions', 'Ruleset' and 'AppCredential'; nested keys are merged
        individually so a partial override does not discard the rest of the
        baseline.

    .EXAMPLE
        Get-GitHubRepoBaseline

        Return the default baseline.

    .EXAMPLE
        Get-GitHubRepoBaseline -Override @{ Settings = @{ has_wiki = $true } }

        Return the baseline with wikis permitted.

    .EXAMPLE
        Get-GitHubRepoBaseline -Override @{ Ruleset = @{ RequiredApprovingReviews = 1 } }

        Require one approving review on the default branch.

    .OUTPUTS
        System.Collections.Hashtable
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Returns a new hashtable; does not change system state.')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $false)]
        [hashtable]$Override
    )

    $baseline = @{
        Settings      = [ordered]@{
            allow_squash_merge           = $true
            allow_merge_commit           = $false
            allow_rebase_merge           = $false
            allow_auto_merge             = $true
            delete_branch_on_merge       = $true
            allow_update_branch          = $true
            squash_merge_commit_title    = 'PR_TITLE'
            squash_merge_commit_message  = 'BLANK'
            has_issues                   = $true
            has_wiki                     = $false
            has_projects                 = $false
            has_discussions              = $false
            web_commit_signoff_required  = $false
        }
        Actions       = [ordered]@{
            default_workflow_permissions       = 'read'
            can_approve_pull_request_reviews   = $false
        }
        Ruleset       = [ordered]@{
            Name                     = 'Default'
            Enforcement              = 'active'
            RequirePullRequest       = $true
            RequiredApprovingReviews = 0
            BlockDeletion            = $true
            BlockForcePush           = $true
            AllowedMergeMethods      = @('squash')
            AdminCanBypass           = $true
        }
        AppCredential = [ordered]@{
            VariableName = 'AUTOMATION_APP_ID'
            SecretName   = 'AUTOMATION_APP_PRIVATE_KEY'
        }
    }

    if ($PSBoundParameters.ContainsKey('Override') -and $null -ne $Override) {
        foreach ($section in $Override.Keys) {
            if (-not $baseline.ContainsKey($section)) {
                throw "Unknown baseline section '$section'. Valid sections: $($baseline.Keys -join ', ')."
            }
            foreach ($key in $Override[$section].Keys) {
                $baseline[$section][$key] = $Override[$section][$key]
            }
        }
    }

    return $baseline
}

function Get-GitHubAppCredential {
    <#
    .SYNOPSIS
        Read a GitHub App ID and private key from 1Password.

    .DESCRIPTION
        Resolves two 1Password secret references with `op read` and returns
        them as an object. The private key is returned as a SecureString so it
        is not left as a plain string in the session, and the App ID is
        returned as plain text because it is a non-secret identifier.

        Requires the 1Password CLI (`op`) to be installed and unlocked (the
        desktop app integration, or `op signin`).

    .PARAMETER AppIdReference
        1Password secret reference for the App ID, in `op://Vault/Item/field`
        form. Defaults to $env:OP_GITHUB_APP_ID_REF.

    .PARAMETER PrivateKeyReference
        1Password secret reference for the PEM-encoded private key. Defaults
        to $env:OP_GITHUB_APP_KEY_REF.

    .EXAMPLE
        Get-GitHubAppCredential -AppIdReference 'op://Private/GitHub Automation App/app id' -PrivateKeyReference 'op://Private/GitHub Automation App/private key'

        Read the credential explicitly.

    .EXAMPLE
        $cred = Get-GitHubAppCredential
        Get-GitHubRepoConfig -All -Check AppCredential | Set-GitHubRepoConfig -AppCredential $cred

        Read from the environment-configured references and roll the App
        credential out to every repository that is missing it.

    .OUTPUTS
        PSCustomObject with AppId (string) and PrivateKey (SecureString).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Read-only; does not change system state.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'The 1Password CLI returns the PEM as plain text; converting it to a SecureString immediately is the hardening step, not a weakness.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$AppIdReference = $env:OP_GITHUB_APP_ID_REF,

        [Parameter(Mandatory = $false)]
        [string]$PrivateKeyReference = $env:OP_GITHUB_APP_KEY_REF
    )

    if (-not (Get-Command op -ErrorAction SilentlyContinue)) {
        throw "The 1Password CLI (op) was not found on PATH. Install it from https://developer.1password.com/docs/cli/ first."
    }

    if ([string]::IsNullOrWhiteSpace($AppIdReference)) {
        throw "No App ID secret reference. Pass -AppIdReference or set OP_GITHUB_APP_ID_REF (e.g. 'op://Private/GitHub Automation App/app id')."
    }

    if ([string]::IsNullOrWhiteSpace($PrivateKeyReference)) {
        throw "No private key secret reference. Pass -PrivateKeyReference or set OP_GITHUB_APP_KEY_REF (e.g. 'op://Private/GitHub Automation App/private key')."
    }

    Write-Verbose "Reading App ID from $AppIdReference"
    $appId = Invoke-OnePasswordCli -Reference $AppIdReference
    if ([string]::IsNullOrWhiteSpace($appId)) {
        throw "op read '$AppIdReference' returned an empty value."
    }

    Write-Verbose "Reading private key from $PrivateKeyReference"
    $privateKey = Invoke-OnePasswordCli -Reference $PrivateKeyReference
    if ([string]::IsNullOrWhiteSpace($privateKey)) {
        throw "op read '$PrivateKeyReference' returned an empty value."
    }
    if ($privateKey -notmatch 'BEGIN [A-Z ]*PRIVATE KEY') {
        throw "The value at '$PrivateKeyReference' does not look like a PEM-encoded private key."
    }

    $secure = ConvertTo-SecureString -String $privateKey -AsPlainText -Force
    $privateKey = $null

    return [PSCustomObject]@{
        PSTypeName = 'Dotfiles.GitHubAppCredential'
        AppId      = $appId
        PrivateKey = $secure
    }
}

function Get-GitHubRepoConfig {
    <#
    .SYNOPSIS
        Audit GitHub repositories against the best-practices baseline.

    .DESCRIPTION
        Reads the current configuration of one, several or all repositories and
        compares it to Get-GitHubRepoBaseline. Emits one object per repository
        describing what drifted, which pipes directly into
        Set-GitHubRepoConfig.

        This function is strictly read-only.

        Checked categories:
          Settings      merge strategies and repository features
          Actions       default workflow token permissions, PR-approval toggle
          Ruleset       default-branch protection, including your admin bypass
          AppCredential presence of the GitHub App variable and secret

    .PARAMETER Repository
        One or more repositories as 'name', 'owner/name' or a GitHub URL. Bare
        names are qualified with -Owner.

    .PARAMETER All
        Audit every repository owned by -Owner. Archived repositories are
        skipped unless -IncludeArchived is supplied.

    .PARAMETER Owner
        Account that owns the repositories. Defaults to
        $env:CHEZMOI_GITHUB_USERNAME, then the authenticated `gh` user.

    .PARAMETER IncludeArchived
        Include archived repositories when used with -All. Archived
        repositories reject writes, so they are excluded by default.

    .PARAMETER Check
        Categories to audit. Defaults to Settings, Actions and Ruleset.
        AppCredential is opt-in because listing secrets needs extra token
        scopes.

    .PARAMETER Baseline
        Hashtable passed to Get-GitHubRepoBaseline -Override to adjust the
        desired state for this run.

    .EXAMPLE
        Get-GitHubRepoConfig -Repository docker

        Audit a single repository owned by the default owner.

    .EXAMPLE
        Get-GitHubRepoConfig -All | Where-Object { -not $_.IsCompliant } | Select-Object Repository, DriftCount

        List every non-compliant repository.

    .EXAMPLE
        (Get-GitHubRepoConfig -Repository docker).Drift | Format-Table

        Inspect exactly which settings differ.

    .EXAMPLE
        Get-GitHubRepoConfig -All -Check Settings, Actions, Ruleset, AppCredential

        Audit everything, including whether the App credential is present.

    .OUTPUTS
        PSCustomObject (Dotfiles.GitHubRepoConfig)
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByName', Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('Name', 'FullName')]
        [string[]]$Repository,

        [Parameter(Mandatory = $true, ParameterSetName = 'All')]
        [switch]$All,

        [Parameter(Mandatory = $false)]
        [string]$Owner,

        [Parameter(Mandatory = $false, ParameterSetName = 'All')]
        [switch]$IncludeArchived,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Settings', 'Actions', 'Ruleset', 'AppCredential')]
        [string[]]$Check = @('Settings', 'Actions', 'Ruleset'),

        [Parameter(Mandatory = $false)]
        [hashtable]$Baseline
    )

    begin {
        Test-GitHubCliReady

        $desired = if ($PSBoundParameters.ContainsKey('Baseline')) {
            Get-GitHubRepoBaseline -Override $Baseline
        }
        else {
            Get-GitHubRepoBaseline
        }

        if ([string]::IsNullOrWhiteSpace($Owner)) {
            $Owner = Get-GitHubCurrentOwner
        }

        $targets = [System.Collections.Generic.List[string]]::new()

        if ($PSCmdlet.ParameterSetName -eq 'All') {
            Write-Verbose "Listing repositories for $Owner"
            $listed = Invoke-GitHubCli -Arguments @('repo', 'list', $Owner, '--limit', '1000', '--json', 'nameWithOwner,isArchived') -ErrorContext "gh repo list $Owner"
            $repos = $listed | ConvertFrom-Json
            foreach ($repo in $repos) {
                if ($repo.isArchived -and -not $IncludeArchived) {
                    Write-Verbose "Skipping archived repository $($repo.nameWithOwner)"
                    continue
                }
                $targets.Add($repo.nameWithOwner)
            }
        }
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            foreach ($item in $Repository) {
                $targets.Add((Resolve-GitHubRepoName -Repository $item -Owner $Owner))
            }
        }
    }

    end {
        foreach ($target in $targets) {
            Write-Verbose "Auditing $target"

            $repo = Invoke-GitHubApi -Endpoint "repos/$target" -AllowFailure
            if ($null -eq $repo) {
                Write-Error "Could not read $target. Check that it exists and that your gh token can see it."
                continue
            }

            $drift = [System.Collections.Generic.List[PSObject]]::new()
            $current = [ordered]@{}

            if ($Check -contains 'Settings') {
                foreach ($key in $desired.Settings.Keys) {
                    $currentValue = $repo.$key
                    $current[$key] = $currentValue
                    if ($currentValue -ne $desired.Settings[$key]) {
                        $drift.Add((New-GitHubConfigDrift -Category 'Settings' -Setting $key -Current $currentValue -Desired $desired.Settings[$key]))
                    }
                }
            }

            if ($Check -contains 'Actions') {
                $perms = Invoke-GitHubApi -Endpoint "repos/$target/actions/permissions/workflow" -AllowFailure
                if ($null -eq $perms) {
                    Write-Warning "Could not read Actions workflow permissions for $target. The gh token likely lacks the 'administration' permission; skipping the Actions category."
                }
                else {
                    foreach ($key in $desired.Actions.Keys) {
                        $currentValue = $perms.$key
                        $current[$key] = $currentValue
                        if ($currentValue -ne $desired.Actions[$key]) {
                            $drift.Add((New-GitHubConfigDrift -Category 'Actions' -Setting $key -Current $currentValue -Desired $desired.Actions[$key]))
                        }
                    }
                }
            }

            $rulesetId = $null
            $rulesetDetail = $null
            if ($Check -contains 'Ruleset') {
                $wanted = $desired.Ruleset
                $rulesetList = Get-GitHubRulesetList -Repository $target

                if (-not $rulesetList.Available) {
                    Write-Warning "Could not list rulesets for $target. Private repositories need GitHub Pro for rulesets, and reading them needs the 'administration' permission; skipping the Ruleset category."
                }
                else {
                    $existing = @($rulesetList.Rulesets | Where-Object { $_.name -eq $wanted.Name })[0]

                    if ($null -eq $existing) {
                        $current['ruleset_present'] = $false
                        $drift.Add((New-GitHubConfigDrift -Category 'Ruleset' -Setting 'ruleset_present' -Current $false -Desired $true))
                    }
                    else {
                        $rulesetId = $existing.id
                        $current['ruleset_present'] = $true

                        $detail = Invoke-GitHubApi -Endpoint "repos/$target/rulesets/$rulesetId" -AllowFailure
                        $rulesetDetail = $detail
                        if ($null -eq $detail) {
                            Write-Warning "Could not read ruleset $rulesetId on $target; skipping its rule comparison."
                        }
                        else {
                            $ruleTypes = @($detail.rules | ForEach-Object { $_.type })

                            $current['ruleset_enforcement'] = $detail.enforcement
                            if ($detail.enforcement -ne $wanted.Enforcement) {
                                $drift.Add((New-GitHubConfigDrift -Category 'Ruleset' -Setting 'ruleset_enforcement' -Current $detail.enforcement -Desired $wanted.Enforcement))
                            }

                            $expectedRules = [ordered]@{
                                pull_request     = [bool]$wanted.RequirePullRequest
                                deletion         = [bool]$wanted.BlockDeletion
                                non_fast_forward = [bool]$wanted.BlockForcePush
                            }
                            foreach ($ruleType in $expectedRules.Keys) {
                                $present = $ruleTypes -contains $ruleType
                                $current["ruleset_$ruleType"] = $present
                                if ($present -ne $expectedRules[$ruleType]) {
                                    $drift.Add((New-GitHubConfigDrift -Category 'Ruleset' -Setting "ruleset_$ruleType" -Current $present -Desired $expectedRules[$ruleType]))
                                }
                            }

                            # The admin bypass is what keeps you able to push
                            # directly to the default branch; verify it explicitly.
                            $hasAdminBypass = @($detail.bypass_actors | Where-Object {
                                    $_.actor_type -eq 'RepositoryRole' -and $_.actor_id -eq $script:GitHubRepositoryRoleAdmin
                                }).Count -gt 0
                            $current['ruleset_admin_bypass'] = $hasAdminBypass
                            if ($hasAdminBypass -ne [bool]$wanted.AdminCanBypass) {
                                $drift.Add((New-GitHubConfigDrift -Category 'Ruleset' -Setting 'ruleset_admin_bypass' -Current $hasAdminBypass -Desired ([bool]$wanted.AdminCanBypass)))
                            }

                            if ($wanted.RequirePullRequest -and ($ruleTypes -contains 'pull_request')) {
                                $prRule = @($detail.rules | Where-Object { $_.type -eq 'pull_request' })[0]

                                $currentReviews = $prRule.parameters.required_approving_review_count
                                $current['ruleset_required_approving_review_count'] = $currentReviews
                                if ($currentReviews -ne $wanted.RequiredApprovingReviews) {
                                    $drift.Add((New-GitHubConfigDrift -Category 'Ruleset' -Setting 'ruleset_required_approving_review_count' -Current $currentReviews -Desired $wanted.RequiredApprovingReviews))
                                }

                                $currentMethods = @($prRule.parameters.allowed_merge_methods) | Sort-Object
                                $wantedMethods = @($wanted.AllowedMergeMethods) | Sort-Object
                                $current['ruleset_allowed_merge_methods'] = ($currentMethods -join ',')
                                if (($currentMethods -join ',') -ne ($wantedMethods -join ',')) {
                                    $drift.Add((New-GitHubConfigDrift -Category 'Ruleset' -Setting 'ruleset_allowed_merge_methods' -Current ($currentMethods -join ',') -Desired ($wantedMethods -join ',')))
                                }
                            }
                        }
                    }
                }
            }

            if ($Check -contains 'AppCredential') {
                $variableName = $desired.AppCredential.VariableName
                $secretName = $desired.AppCredential.SecretName

                $variables = Invoke-GitHubApi -Endpoint "repos/$target/actions/variables" -AllowFailure
                $secrets = Invoke-GitHubApi -Endpoint "repos/$target/actions/secrets" -AllowFailure

                if ($null -eq $variables -or $null -eq $secrets) {
                    Write-Warning "Could not list Actions variables/secrets for $target. The gh token likely lacks the 'secrets'/'variables' permissions; skipping the AppCredential category."
                }
                else {
                    $hasVariable = @($variables.variables | Where-Object { $_.name -eq $variableName }).Count -gt 0
                    $hasSecret = @($secrets.secrets | Where-Object { $_.name -eq $secretName }).Count -gt 0

                    $current[$variableName] = $hasVariable
                    $current[$secretName] = $hasSecret

                    if (-not $hasVariable) {
                        $drift.Add((New-GitHubConfigDrift -Category 'AppCredential' -Setting $variableName -Current $false -Desired $true))
                    }
                    if (-not $hasSecret) {
                        $drift.Add((New-GitHubConfigDrift -Category 'AppCredential' -Setting $secretName -Current $false -Desired $true))
                    }
                }
            }

            [PSCustomObject]@{
                PSTypeName  = 'Dotfiles.GitHubRepoConfig'
                Repository  = $target
                Owner       = ($target -split '/')[0]
                Name        = ($target -split '/')[1]
                Visibility  = $repo.visibility
                IsArchived  = [bool]$repo.archived
                IsCompliant = ($drift.Count -eq 0)
                DriftCount  = $drift.Count
                Drift       = $drift.ToArray()
                Current     = $current
                Baseline    = $desired
                Checked     = $Check
                RulesetId   = $rulesetId
                RulesetDetail = $rulesetDetail
            }
        }
    }
}

function Set-GitHubRepoConfig {
    <#
    .SYNOPSIS
        Apply the best-practices baseline to GitHub repositories.

    .DESCRIPTION
        Remediates the drift reported by Get-GitHubRepoConfig. Only settings
        that actually differ are written, so re-running is cheap and idempotent.

        Supports -WhatIf for a dry run: every change is printed, nothing is
        sent. This is the recommended way to preview a bulk change.

        Authentication is delegated to the `gh` CLI. Writing repository
        settings requires a token with the fine-grained `administration:write`
        permission; writing the App credential additionally requires
        `secrets:write` and `variables:write`.

    .PARAMETER InputObject
        Objects emitted by Get-GitHubRepoConfig, normally supplied through the
        pipeline. Their recorded drift is applied as-is.

    .PARAMETER Repository
        Repositories to remediate by name, when not piping from
        Get-GitHubRepoConfig. Each is audited first and then remediated.

    .PARAMETER Owner
        Account that owns the repositories. Defaults to
        $env:CHEZMOI_GITHUB_USERNAME, then the authenticated `gh` user.

    .PARAMETER Baseline
        Hashtable passed to Get-GitHubRepoBaseline -Override. Used only with
        -Repository; piped objects carry their own baseline.

    .PARAMETER AppCredential
        Credential from Get-GitHubAppCredential. Required to remediate drift in
        the AppCredential category; without it those items are skipped with a
        warning.

    .PARAMETER Category
        Restrict remediation to specific categories, e.g. -Category Settings to
        fix merge strategies while leaving Actions permissions alone.

    .PARAMETER PassThru
        Emit a result object per repository describing what was applied.

    .EXAMPLE
        Get-GitHubRepoConfig -All | Set-GitHubRepoConfig -WhatIf

        Dry run: show every change that would be made across all repositories.

    .EXAMPLE
        Get-GitHubRepoConfig -All | Where-Object { -not $_.IsCompliant } | Set-GitHubRepoConfig

        Remediate every non-compliant repository, prompting for each.

    .EXAMPLE
        Get-GitHubRepoConfig -Repository docker, blog | Set-GitHubRepoConfig -Confirm:$false -PassThru

        Remediate two repositories without prompting and report what changed.

    .EXAMPLE
        $cred = Get-GitHubAppCredential
        Get-GitHubRepoConfig -All -Check AppCredential | Set-GitHubRepoConfig -AppCredential $cred

        Roll the GitHub App ID and private key out to every repository missing
        them.

    .EXAMPLE
        Get-GitHubRepoConfig -All -Check Ruleset | Set-GitHubRepoConfig -Category Ruleset -WhatIf

        Preview default-branch protection across all repositories. The created
        ruleset keeps the repository admin role as a bypass actor, so you can
        still push directly while automation cannot.

    .OUTPUTS
        PSCustomObject when -PassThru is supplied; otherwise nothing.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByObject')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [PSTypeName('Dotfiles.GitHubRepoConfig')]
        [PSCustomObject]$InputObject,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByName', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Repository,

        [Parameter(Mandatory = $false, ParameterSetName = 'ByName')]
        [string]$Owner,

        [Parameter(Mandatory = $false, ParameterSetName = 'ByName')]
        [hashtable]$Baseline,

        [Parameter(Mandatory = $false)]
        [PSTypeName('Dotfiles.GitHubAppCredential')]
        [PSCustomObject]$AppCredential,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Settings', 'Actions', 'Ruleset', 'AppCredential')]
        [string[]]$Category,

        [Parameter(Mandatory = $false)]
        [switch]$PassThru
    )

    begin {
        Test-GitHubCliReady
        $pending = [System.Collections.Generic.List[PSObject]]::new()
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ByObject') {
            $pending.Add($InputObject)
            return
        }

        $auditArgs = @{ Repository = $Repository; Check = @('Settings', 'Actions', 'Ruleset', 'AppCredential') }
        if (-not [string]::IsNullOrWhiteSpace($Owner)) { $auditArgs['Owner'] = $Owner }
        if ($PSBoundParameters.ContainsKey('Baseline')) { $auditArgs['Baseline'] = $Baseline }

        foreach ($config in (Get-GitHubRepoConfig @auditArgs)) {
            $pending.Add($config)
        }
    }

    end {
        foreach ($config in $pending) {
            $target = $config.Repository

            if ($config.IsArchived) {
                Write-Warning "Skipping $target because it is archived and rejects writes."
                continue
            }

            $drift = @($config.Drift)
            if ($PSBoundParameters.ContainsKey('Category')) {
                $drift = @($drift | Where-Object { $Category -contains $_.Category })
            }

            if ($drift.Count -eq 0) {
                Write-Verbose "$target is already compliant; nothing to do."
                if ($PassThru) {
                    [PSCustomObject]@{
                        PSTypeName = 'Dotfiles.GitHubRepoConfigResult'
                        Repository = $target
                        Applied    = @()
                        Skipped    = @()
                    }
                }
                continue
            }

            $applied = [System.Collections.Generic.List[string]]::new()
            $skipped = [System.Collections.Generic.List[string]]::new()

            # --- Repository settings: one PATCH for every drifted field ---
            $settingsDrift = @($drift | Where-Object { $_.Category -eq 'Settings' })
            if ($settingsDrift.Count -gt 0) {
                $body = @{}
                foreach ($item in $settingsDrift) { $body[$item.Setting] = $item.Desired }

                $description = ($settingsDrift | ForEach-Object { "$($_.Setting): $($_.Current) -> $($_.Desired)" }) -join ', '
                if ($PSCmdlet.ShouldProcess($target, "Update repository settings ($description)")) {
                    $null = Invoke-GitHubApi -Endpoint "repos/$target" -Method 'PATCH' -Body $body
                    foreach ($item in $settingsDrift) { $applied.Add("Settings/$($item.Setting)") }
                    Write-Verbose "Updated $($settingsDrift.Count) setting(s) on $target"
                }
            }

            # --- Actions workflow permissions: PUT requires the full object ---
            $actionsDrift = @($drift | Where-Object { $_.Category -eq 'Actions' })
            if ($actionsDrift.Count -gt 0) {
                $body = @{}
                foreach ($key in $config.Baseline.Actions.Keys) {
                    $body[$key] = $config.Baseline.Actions[$key]
                }

                $description = ($actionsDrift | ForEach-Object { "$($_.Setting): $($_.Current) -> $($_.Desired)" }) -join ', '
                if ($PSCmdlet.ShouldProcess($target, "Update Actions workflow permissions ($description)")) {
                    $null = Invoke-GitHubApi -Endpoint "repos/$target/actions/permissions/workflow" -Method 'PUT' -Body $body
                    foreach ($item in $actionsDrift) { $applied.Add("Actions/$($item.Setting)") }
                    Write-Verbose "Updated Actions workflow permissions on $target"
                }
            }

            # --- Default-branch ruleset: created or replaced wholesale ---
            $rulesetDrift = @($drift | Where-Object { $_.Category -eq 'Ruleset' })
            if ($rulesetDrift.Count -gt 0) {
                $payloadArgs = @{ Ruleset = $config.Baseline.Ruleset }
                if ($null -ne $config.RulesetDetail) {
                    $payloadArgs['ExistingRuleset'] = $config.RulesetDetail
                }
                $payload = New-GitHubRulesetPayload @payloadArgs
                $description = ($rulesetDrift | ForEach-Object { "$($_.Setting): $($_.Current) -> $($_.Desired)" }) -join ', '

                if ($null -eq $config.RulesetId) {
                    if ($PSCmdlet.ShouldProcess($target, "Create ruleset '$($config.Baseline.Ruleset.Name)' ($description)")) {
                        $null = Invoke-GitHubApi -Endpoint "repos/$target/rulesets" -Method 'POST' -Body $payload
                        foreach ($item in $rulesetDrift) { $applied.Add("Ruleset/$($item.Setting)") }
                        Write-Verbose "Created ruleset '$($config.Baseline.Ruleset.Name)' on $target"
                    }
                }
                else {
                    if ($PSCmdlet.ShouldProcess($target, "Update ruleset '$($config.Baseline.Ruleset.Name)' ($description)")) {
                        $null = Invoke-GitHubApi -Endpoint "repos/$target/rulesets/$($config.RulesetId)" -Method 'PUT' -Body $payload
                        foreach ($item in $rulesetDrift) { $applied.Add("Ruleset/$($item.Setting)") }
                        Write-Verbose "Updated ruleset $($config.RulesetId) on $target"
                    }
                }
            }

            # --- GitHub App credential: variable + secret from 1Password ---
            $credentialDrift = @($drift | Where-Object { $_.Category -eq 'AppCredential' })
            if ($credentialDrift.Count -gt 0) {
                if ($null -eq $AppCredential) {
                    Write-Warning "$target is missing the GitHub App credential but -AppCredential was not supplied. Run Get-GitHubAppCredential and pass the result to remediate."
                    foreach ($item in $credentialDrift) { $skipped.Add("AppCredential/$($item.Setting)") }
                }
                else {
                    $variableName = $config.Baseline.AppCredential.VariableName
                    $secretName = $config.Baseline.AppCredential.SecretName

                    foreach ($item in $credentialDrift) {
                        if ($item.Setting -eq $variableName) {
                            if ($PSCmdlet.ShouldProcess($target, "Set Actions variable $variableName")) {
                                $result = Invoke-GitHubCli -Arguments @('variable', 'set', $variableName, '--repo', $target, '--body', $AppCredential.AppId) -AllowFailure -ErrorContext "gh variable set $variableName on $target"
                                if ($null -eq $result) {
                                    Write-Error "Could not set variable $variableName on ${target}."
                                    $skipped.Add("AppCredential/$variableName")
                                }
                                else {
                                    $applied.Add("AppCredential/$variableName")
                                }
                            }
                        }
                        elseif ($item.Setting -eq $secretName) {
                            if ($PSCmdlet.ShouldProcess($target, "Set Actions secret $secretName")) {
                                $plain = ConvertFrom-DotfilesSecureString -SecureString $AppCredential.PrivateKey
                                try {
                                    # Piped on stdin so the PEM never appears in
                                    # a process argument list.
                                    $result = Invoke-GitHubCli -Arguments @('secret', 'set', $secretName, '--repo', $target) -StdIn $plain -AllowFailure -ErrorContext "gh secret set $secretName on $target"
                                    if ($null -eq $result) {
                                        Write-Error "Could not set secret $secretName on ${target}."
                                        $skipped.Add("AppCredential/$secretName")
                                    }
                                    else {
                                        $applied.Add("AppCredential/$secretName")
                                    }
                                }
                                finally {
                                    $plain = $null
                                }
                            }
                        }
                    }
                }
            }

            if ($PassThru) {
                [PSCustomObject]@{
                    PSTypeName = 'Dotfiles.GitHubRepoConfigResult'
                    Repository = $target
                    Applied    = $applied.ToArray()
                    Skipped    = $skipped.ToArray()
                }
            }
        }
    }
}
