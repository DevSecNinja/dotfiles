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
        Invoke the `op` CLI and return its stdout.
    .DESCRIPTION
        Wraps every `op` invocation this module makes, so tests can mock it
        without 1Password being installed or unlocked.
    .PARAMETER Arguments
        Argument array passed verbatim to `op`.
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
        [switch]$AllowFailure,

        [Parameter(Mandatory = $false)]
        [string]$ErrorContext
    )

    if ([string]::IsNullOrWhiteSpace($ErrorContext)) {
        $ErrorContext = "op $($Arguments -join ' ')"
    }

    $output = & op @Arguments 2>&1

    if ($LASTEXITCODE -ne 0) {
        if ($AllowFailure) {
            Write-Verbose "$ErrorContext failed (exit $LASTEXITCODE)."
            return $null
        }
        throw "$ErrorContext failed (exit $LASTEXITCODE): $output"
    }

    return ($output | Out-String).Trim()
}

function ConvertFrom-OnePasswordReference {
    <#
    .SYNOPSIS
        Split an `op://Vault/Item/field` secret reference into its parts.
    .DESCRIPTION
        Parsing the reference up front lets the pre-flight checks name the exact
        vault, item and field that are missing, rather than surfacing op's
        generic "isn't an item" error.
    .PARAMETER Reference
        Secret reference in `op://Vault/Item/field` form.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Reference
    )

    if ($Reference -notmatch '^op://([^/]+)/([^/]+)/(.+)$') {
        throw "'$Reference' is not a valid 1Password secret reference. Expected the form 'op://Vault/Item/field'."
    }

    return [PSCustomObject]@{
        Vault     = $Matches[1]
        Item      = $Matches[2]
        Field     = $Matches[3]
        Reference = $Reference
    }
}

function Test-OnePasswordSession {
    <#
    .SYNOPSIS
        Throw unless the 1Password CLI is installed and unlocked.
    .DESCRIPTION
        Separating "not installed" from "not signed in" means the error names
        which of the two to fix, instead of failing later with an opaque op
        error partway through a bulk rollout.
    #>
    [CmdletBinding()]
    param()

    if (-not (Get-Command op -ErrorAction SilentlyContinue)) {
        throw "The 1Password CLI (op) was not found on PATH. Install it from https://developer.1password.com/docs/cli/ first."
    }

    $whoami = Invoke-OnePasswordCli -Arguments @('whoami') -AllowFailure -ErrorContext 'op whoami'
    if ($null -eq $whoami) {
        throw "The 1Password CLI is not signed in. Unlock the 1Password app with the CLI integration enabled (Settings -> Developer -> 'Integrate with 1Password CLI'), or run 'op signin'."
    }
}

function Test-OnePasswordReference {
    <#
    .SYNOPSIS
        Verify that the item and field behind a secret reference exist.
    .DESCRIPTION
        Checks the vault, item and field before any value is read, so a missing
        1Password entry produces an actionable message naming exactly what to
        create instead of an empty value surfacing later in the rollout.
    .PARAMETER Reference
        Secret reference in `op://Vault/Item/field` form.
    .PARAMETER Purpose
        What the field holds, used in the error message.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Reference,

        [Parameter(Mandatory = $true)]
        [string]$Purpose
    )

    $parsed = ConvertFrom-OnePasswordReference -Reference $Reference

    $json = Invoke-OnePasswordCli -Arguments @('item', 'get', $parsed.Item, '--vault', $parsed.Vault, '--format', 'json') `
        -AllowFailure -ErrorContext "op item get '$($parsed.Item)'"

    if ($null -eq $json) {
        $create = "op item create --category 'API Credential' --vault '$($parsed.Vault)' --title '$($parsed.Item)' 'app-id[text]=YOUR_APP_ID' 'private-key[password]=PEM_CONTENTS'"
        throw "1Password item '$($parsed.Item)' was not found in vault '$($parsed.Vault)' (needed for the $Purpose). Create it in the 1Password app as an API Credential with 'app-id' and 'private-key' fields, or run: $create"
    }

    try {
        $item = $json | ConvertFrom-Json
    }
    catch {
        throw "Could not parse the 1Password item '$($parsed.Item)' as JSON: $_"
    }

    $names = @($item.fields | ForEach-Object { $_.label }) + @($item.fields | ForEach-Object { $_.id })
    $found = @($names | Where-Object { $_ -and ([string]$_).ToLowerInvariant() -eq $parsed.Field.ToLowerInvariant() }).Count -gt 0

    if (-not $found) {
        $available = (@($item.fields | ForEach-Object { $_.label } | Where-Object { $_ }) | Sort-Object -Unique) -join ', '
        throw "1Password item '$($parsed.Item)' in vault '$($parsed.Vault)' has no field named '$($parsed.Field)' (needed for the $Purpose). Fields on that item: $available"
    }
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

    # A JSON array has to be reassembled explicitly. Piping into
    # ConvertFrom-Json enumerates the result, so `$x = '[]' | ConvertFrom-Json`
    # yields $null - indistinguishable from a failed call - and a single-element
    # list would arrive as a bare object. Wrapping in @() fixes both, and the
    # unary comma on return stops the pipeline unrolling it again. (PowerShell
    # unwraps exactly one level on the way out, so the caller still receives the
    # array itself, not a nested one. ConvertFrom-Json -NoEnumerate would be
    # tidier but does not exist on Windows PowerShell 5.1, which this module
    # supports.)
    $looksLikeArray = $text.TrimStart().StartsWith('[')

    try {
        $parsed = @($text | ConvertFrom-Json)
    }
    catch {
        throw "Could not parse the response from gh api $Endpoint as JSON: $_"
    }

    if ($looksLikeArray) {
        return , $parsed
    }

    return $parsed[0]
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

function Get-GitHubCredentialScope {
    <#
    .SYNOPSIS
        Decide whether a repository's App credential lives in an environment.
    .DESCRIPTION
        Environments, environment secrets and deployment branch policies are
        public-repository-only on the GitHub Free plan. Rather than failing on a
        private repository, callers fall back to repository-level secrets.

        The fallback loses nothing in practice: an environment secret is only
        safer than a repository secret because of the deployment branch policy
        pinning it to the default branch, and that policy is exactly what the
        Free plan withholds on private repositories.
    .PARAMETER Repository
        Repository in 'owner/name' form.
    .PARAMETER Environment
        Desired environment name. Empty means repository-level by choice.
    .PARAMETER Visibility
        Repository visibility as reported by the API.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $false)][string]$Environment,
        [Parameter(Mandatory = $true)][string]$Visibility
    )

    if ([string]::IsNullOrWhiteSpace($Environment)) {
        return [PSCustomObject]@{ UseEnvironment = $false; Environment = ''; Reason = 'baseline requests repository-level credentials' }
    }

    if ($Visibility -ne 'public') {
        return [PSCustomObject]@{
            UseEnvironment = $false
            Environment    = $Environment
            Reason         = "environments are public-repository-only on the GitHub Free plan; $Repository is $Visibility"
        }
    }

    return [PSCustomObject]@{ UseEnvironment = $true; Environment = $Environment; Reason = '' }
}

function Get-GitHubEnvironmentState {
    <#
    .SYNOPSIS
        Report whether an environment exists and how its branch policy is set.
    .DESCRIPTION
        Distinguishes "environment absent" from "environment present but
        unrestricted", because only the second is a security gap worth naming:
        an environment without a deployment branch policy grants no more
        protection than a repository secret.
    .PARAMETER Repository
        Repository in 'owner/name' form.
    .PARAMETER Environment
        Environment name.
    .PARAMETER DefaultBranch
        Branch the environment should be pinned to.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$Environment,
        [Parameter(Mandatory = $false)][AllowEmptyString()][string]$DefaultBranch
    )

    $env = Invoke-GitHubApi -Endpoint "repos/$Repository/environments/$Environment" -AllowFailure
    if ($null -eq $env) {
        return [PSCustomObject]@{ Exists = $false; PinnedToDefaultBranch = $false }
    }

    # A policy of custom_branch_policies with the default branch listed is the
    # only shape that actually pins deployments to that branch.
    $pinned = $false
    if ($null -ne $env.deployment_branch_policy -and $env.deployment_branch_policy.custom_branch_policies) {
        $policies = Invoke-GitHubApi -Endpoint "repos/$Repository/environments/$Environment/deployment-branch-policies" -AllowFailure
        if ($null -ne $policies -and -not [string]::IsNullOrWhiteSpace($DefaultBranch)) {
            $names = @($policies.branch_policies | ForEach-Object { $_.name })
            $pinned = $names -contains $DefaultBranch
        }
    }

    return [PSCustomObject]@{ Exists = $true; PinnedToDefaultBranch = $pinned }
}

function Test-GitHubPagesWorkflow {
    <#
    .SYNOPSIS
        Does this repository call the central reusable Pages workflow?
    .DESCRIPTION
        Cloudflare credentials are only meaningful in repositories that deploy
        through DevSecNinja/.github's reusable pages workflow, so the audit is
        gated on the caller actually being present rather than on the secret
        merely being absent.

        Scans .github/workflows for a file referencing the reusable workflow.
        Files whose name mentions "pages" are checked first and the scan stops
        at the first hit, so the conventional layout costs two API calls.
    .PARAMETER Repository
        Repository in 'owner/name' form.
    .PARAMETER Marker
        Substring identifying the reusable workflow reference.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)][string]$Repository,

        [Parameter(Mandatory = $false)]
        [string]$Marker = 'DevSecNinja/.github/.github/workflows/pages.yml@'
    )

    $listing = Invoke-GitHubApi -Endpoint "repos/$Repository/contents/.github/workflows" -AllowFailure
    if ($null -eq $listing) { return $false }

    $candidates = @($listing | Where-Object { $_.type -eq 'file' -and $_.name -match '\.ya?ml$' })
    if ($candidates.Count -eq 0) { return $false }

    # Conventional names first so the common case exits after one fetch.
    $ordered = @($candidates | Sort-Object @{ Expression = { $_.name -notmatch 'page' } }, Name)

    foreach ($file in $ordered) {
        $content = Invoke-GitHubApi -Endpoint "repos/$Repository/contents/$($file.path)" -AllowFailure
        if ($null -eq $content -or [string]::IsNullOrWhiteSpace($content.content)) { continue }

        try {
            $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(($content.content -replace '\s', '')))
        }
        catch {
            continue
        }

        if ($decoded -like "*$Marker*") {
            Write-Verbose "$Repository calls the central Pages workflow via $($file.path)"
            return $true
        }
    }

    return $false
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
          - AppCredential.Environment scopes the App credential to a GitHub
            Actions environment instead of the repository. The security gain
            comes from the environment's deployment branch policy, which pins it
            to the default branch so a workflow on an attacker-controlled PR
            branch cannot read the key. Set it to '' to keep credentials at the
            repository level.

            Environments, environment secrets and deployment branch policies
            are public-repository-only on the GitHub Free plan, so private
            repositories transparently fall back to repository-level secrets
            (with a warning). Without a branch policy an environment secret is
            no safer than a repository secret, so the fallback loses nothing.
          - CloudflareCredential only applies to repositories that call the
            central reusable Pages workflow, so the credential is not sprayed
            across repositories that have no use for it.

            Both values are repository-level secrets, deliberately not
            environment ones. The reusable workflow's `detect-cloudflare` job
            gates every deploy on the secrets being non-empty and declares no
            `environment:`, and the caller job does not either - so an
            environment secret would read as empty and silently disable
            deploys.
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
            Environment  = 'production'
        }
        CloudflareCredential = [ordered]@{
            AccountIdSecretName = 'CLOUDFLARE_ACCOUNT_ID'
            ApiTokenSecretName  = 'CLOUDFLARE_API_TOKEN'
            WorkflowMarker      = 'DevSecNinja/.github/.github/workflows/pages.yml@'
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
        is not left as a plain string in the session; the App ID is returned as
        plain text because it is a non-secret identifier.

        Before reading anything, the 1Password CLI is checked for being
        installed and unlocked, and both the item and the fields are verified to
        exist. A missing entry therefore fails immediately with a message naming
        exactly what to create, rather than surfacing as an empty value partway
        through a rollout.

        Expected 1Password entry (create it once):

            Vault    Private
            Item     GitHub Automation App   (category: API Credential)
            Fields   app-id        the numeric App ID from the App settings page
                     private-key   the full PEM, including the BEGIN/END lines

        Override the location with -AppIdReference / -PrivateKeyReference, or
        with the OP_GITHUB_APP_ID_REF / OP_GITHUB_APP_KEY_REF environment
        variables. Secret references are non-secret identifiers, useless without
        authenticating to 1Password.

    .PARAMETER AppIdReference
        1Password secret reference for the App ID, in `op://Vault/Item/field`
        form. Defaults to $env:OP_GITHUB_APP_ID_REF, then to
        'op://Private/GitHub Automation App/app-id'.

    .PARAMETER PrivateKeyReference
        1Password secret reference for the PEM-encoded private key. Defaults to
        $env:OP_GITHUB_APP_KEY_REF, then to
        'op://Private/GitHub Automation App/private-key'.

    .EXAMPLE
        Get-GitHubAppCredential

        Read the credential from the default 1Password location.

    .EXAMPLE
        $cred = Get-GitHubAppCredential
        Get-GitHubRepoConfig -All -Check AppCredential | Set-GitHubRepoConfig -AppCredential $cred

        Roll the App credential out to every repository that is missing it.

    .EXAMPLE
        Get-GitHubAppCredential -AppIdReference 'op://Work/Automation App/app-id' -PrivateKeyReference 'op://Work/Automation App/private-key'

        Read the credential from a different vault or item.

    .OUTPUTS
        PSCustomObject with AppId (string) and PrivateKey (SecureString).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Read-only; does not change system state.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'The 1Password CLI returns the PEM as plain text; converting it to a SecureString immediately is the hardening step, not a weakness.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$AppIdReference,

        [Parameter(Mandatory = $false)]
        [string]$PrivateKeyReference
    )

    if ([string]::IsNullOrWhiteSpace($AppIdReference)) {
        $AppIdReference = $env:OP_GITHUB_APP_ID_REF
    }
    if ([string]::IsNullOrWhiteSpace($AppIdReference)) {
        $AppIdReference = 'op://Private/GitHub Automation App/app-id'
    }

    if ([string]::IsNullOrWhiteSpace($PrivateKeyReference)) {
        $PrivateKeyReference = $env:OP_GITHUB_APP_KEY_REF
    }
    if ([string]::IsNullOrWhiteSpace($PrivateKeyReference)) {
        $PrivateKeyReference = 'op://Private/GitHub Automation App/private-key'
    }

    Test-OnePasswordSession

    Write-Verbose "Verifying $AppIdReference"
    Test-OnePasswordReference -Reference $AppIdReference -Purpose 'GitHub App ID'

    Write-Verbose "Verifying $PrivateKeyReference"
    Test-OnePasswordReference -Reference $PrivateKeyReference -Purpose 'GitHub App private key'

    Write-Verbose "Reading App ID from $AppIdReference"
    $appId = Invoke-OnePasswordCli -Arguments @('read', $AppIdReference) -ErrorContext "op read '$AppIdReference'"
    if ([string]::IsNullOrWhiteSpace($appId)) {
        throw "The field at '$AppIdReference' is empty. Set it to the numeric App ID shown on the GitHub App's settings page."
    }
    if ($appId -notmatch '^\d+$') {
        throw "The value at '$AppIdReference' is not a numeric GitHub App ID. Use the 'App ID' from the App's settings page, not the client ID or slug."
    }

    Write-Verbose "Reading private key from $PrivateKeyReference"
    $privateKey = Invoke-OnePasswordCli -Arguments @('read', $PrivateKeyReference) -ErrorContext "op read '$PrivateKeyReference'"
    if ([string]::IsNullOrWhiteSpace($privateKey)) {
        throw "The field at '$PrivateKeyReference' is empty. Paste the full contents of the App's .private-key.pem file into it."
    }
    if ($privateKey -notmatch 'BEGIN [A-Z ]*PRIVATE KEY') {
        throw "The value at '$PrivateKeyReference' does not look like a PEM-encoded private key. It must include the '-----BEGIN ... PRIVATE KEY-----' header."
    }

    $secure = ConvertTo-SecureString -String $privateKey -AsPlainText -Force
    $privateKey = $null

    return [PSCustomObject]@{
        PSTypeName = 'Dotfiles.GitHubAppCredential'
        AppId      = $appId
        PrivateKey = $secure
    }
}

function Get-CloudflareCredential {
    <#
    .SYNOPSIS
        Read a Cloudflare account ID and API token from 1Password.

    .DESCRIPTION
        Both values are secrets used by the central reusable Pages workflow to
        deploy to Cloudflare Pages. They are returned as SecureStrings so they
        are not left as plain strings in the session.

        Note this is the Cloudflare **account** ID, not a project ID: the
        project name is a workflow input (`cloudflare-project-name`, defaulting
        to the repository name), not a secret.

        As with Get-GitHubAppCredential, everything is verified before a value
        is read, so a missing entry fails immediately with a message naming what
        to create rather than surfacing as an empty secret partway through a
        rollout.

        Expected 1Password entry (create it once):

            Vault    Private
            Item     Cloudflare Pages Deploy   (category: API Credential)
            Fields   account-id   the Account ID from the Cloudflare dashboard
                     api-token    a token with the Cloudflare Pages:Edit scope

    .PARAMETER AccountIdReference
        1Password secret reference for the account ID, in `op://Vault/Item/field`
        form. Defaults to $env:OP_CLOUDFLARE_ACCOUNT_REF, then to
        'op://Private/Cloudflare Pages Deploy/account-id'.

    .PARAMETER ApiTokenReference
        1Password secret reference for the API token. Defaults to
        $env:OP_CLOUDFLARE_TOKEN_REF, then to
        'op://Private/Cloudflare Pages Deploy/api-token'.

    .EXAMPLE
        Get-CloudflareCredential

        Read the credential from the default 1Password location.

    .EXAMPLE
        $cf = Get-CloudflareCredential
        Get-GitHubRepoConfig -All -Check CloudflareCredential | Set-GitHubRepoConfig -CloudflareCredential $cf

        Roll the Cloudflare credential out to every repository that deploys
        through the central Pages workflow and is missing it.

    .OUTPUTS
        PSCustomObject with AccountId and ApiToken (both SecureString).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Read-only; does not change system state.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'The 1Password CLI returns the values as plain text; converting them to SecureStrings immediately is the hardening step, not a weakness.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$AccountIdReference,

        [Parameter(Mandatory = $false)]
        [string]$ApiTokenReference
    )

    if ([string]::IsNullOrWhiteSpace($AccountIdReference)) { $AccountIdReference = $env:OP_CLOUDFLARE_ACCOUNT_REF }
    if ([string]::IsNullOrWhiteSpace($AccountIdReference)) { $AccountIdReference = 'op://Private/Cloudflare Pages Deploy/account-id' }

    if ([string]::IsNullOrWhiteSpace($ApiTokenReference)) { $ApiTokenReference = $env:OP_CLOUDFLARE_TOKEN_REF }
    if ([string]::IsNullOrWhiteSpace($ApiTokenReference)) { $ApiTokenReference = 'op://Private/Cloudflare Pages Deploy/api-token' }

    Test-OnePasswordSession

    Write-Verbose "Verifying $AccountIdReference"
    Test-OnePasswordReference -Reference $AccountIdReference -Purpose 'Cloudflare account ID'

    Write-Verbose "Verifying $ApiTokenReference"
    Test-OnePasswordReference -Reference $ApiTokenReference -Purpose 'Cloudflare API token'

    $accountId = Invoke-OnePasswordCli -Arguments @('read', $AccountIdReference) -ErrorContext "op read '$AccountIdReference'"
    if ([string]::IsNullOrWhiteSpace($accountId)) {
        throw "The field at '$AccountIdReference' is empty. Set it to the Account ID shown in the Cloudflare dashboard."
    }
    # Cloudflare account IDs are 32-character hex strings; catching a pasted
    # project name or zone ID here beats a 403 inside a deploy job.
    if ($accountId -notmatch '^[0-9a-fA-F]{32}$') {
        throw "The value at '$AccountIdReference' is not a Cloudflare account ID (expected 32 hex characters). Use the Account ID from the dashboard sidebar, not a project or zone ID."
    }

    $apiToken = Invoke-OnePasswordCli -Arguments @('read', $ApiTokenReference) -ErrorContext "op read '$ApiTokenReference'"
    if ([string]::IsNullOrWhiteSpace($apiToken)) {
        throw "The field at '$ApiTokenReference' is empty. Create a token with the 'Cloudflare Pages:Edit' permission and paste it in."
    }

    $result = [PSCustomObject]@{
        PSTypeName = 'Dotfiles.CloudflareCredential'
        AccountId  = (ConvertTo-SecureString -String $accountId -AsPlainText -Force)
        ApiToken   = (ConvertTo-SecureString -String $apiToken -AsPlainText -Force)
    }
    $accountId = $null
    $apiToken = $null

    return $result
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
          CloudflareCredential
                        presence of the Cloudflare Pages secrets, but only in
                        repositories that call the central Pages workflow

    .PARAMETER Repository
        One or more repositories as 'name', 'owner/name' or a GitHub URL. Bare
        names are qualified with -Owner.

    .PARAMETER All
        Audit every repository owned by -Owner. Archived repositories are
        skipped unless -IncludeArchived is supplied; forks are included unless
        -ExcludeForks is supplied.

    .PARAMETER Owner
        Account that owns the repositories. Defaults to
        $env:CHEZMOI_GITHUB_USERNAME, then the authenticated `gh` user.

    .PARAMETER IncludeArchived
        Include archived repositories when used with -All. Archived
        repositories reject writes, so they are excluded by default.

    .PARAMETER ExcludeForks
        Skip forks when used with -All. Forks are included by default, because
        a fork you maintain as your own project still wants the baseline; use
        this to leave upstream clones alone. Every result carries an IsFork
        property, so forks can also be filtered after the fact.

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

    .EXAMPLE
        Get-GitHubRepoConfig -All -ExcludeForks | Set-GitHubRepoConfig -WhatIf

        Remediate only repositories you started yourself, leaving forks of
        other people's projects untouched.

    .EXAMPLE
        Get-GitHubRepoConfig -All | Where-Object { $_.IsFork }

        Audit only the forks.

    .NOTES
        A category that cannot be evaluated - a missing token permission, or a
        plan limitation such as rulesets on a private repository - is reported
        on the SkippedChecks property rather than counted as drift. IsCompliant
        therefore means "nothing drifted among the categories that were actually
        checked", so check SkippedChecks before treating it as a clean bill.

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

        [Parameter(Mandatory = $false, ParameterSetName = 'All')]
        [switch]$ExcludeForks,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Settings', 'Actions', 'Ruleset', 'AppCredential', 'CloudflareCredential')]
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
            $listed = Invoke-GitHubCli -Arguments @('repo', 'list', $Owner, '--limit', '1000', '--json', 'nameWithOwner,isArchived,isFork') -ErrorContext "gh repo list $Owner"
            $repos = $listed | ConvertFrom-Json
            foreach ($repo in $repos) {
                if ($repo.isArchived -and -not $IncludeArchived) {
                    Write-Verbose "Skipping archived repository $($repo.nameWithOwner)"
                    continue
                }
                if ($repo.isFork -and $ExcludeForks) {
                    Write-Verbose "Skipping fork $($repo.nameWithOwner)"
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
            # Categories that could not be evaluated (missing token permission,
            # plan limitation). Tracked so a skipped category is never mistaken
            # for a compliant one.
            $skippedChecks = [System.Collections.Generic.List[string]]::new()
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
                    $skippedChecks.Add('Actions')
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
                    $skippedChecks.Add('Ruleset')
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
                            $skippedChecks.Add('Ruleset')
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

            $credentialScope = $null
            if ($Check -contains 'AppCredential') {
                $variableName = $desired.AppCredential.VariableName
                $secretName = $desired.AppCredential.SecretName

                $credentialScope = Get-GitHubCredentialScope -Repository $target `
                    -Environment $desired.AppCredential.Environment -Visibility $repo.visibility

                if (-not $credentialScope.UseEnvironment -and -not [string]::IsNullOrWhiteSpace($credentialScope.Environment)) {
                    Write-Warning "Falling back to repository-level credentials for ${target}: $($credentialScope.Reason)."
                }

                $current['credential_scope'] = if ($credentialScope.UseEnvironment) { "environment:$($credentialScope.Environment)" } else { 'repository' }

                if ($credentialScope.UseEnvironment) {
                    $envName = $credentialScope.Environment
                    $envState = Get-GitHubEnvironmentState -Repository $target -Environment $envName -DefaultBranch $repo.default_branch

                    $current['environment_present'] = $envState.Exists
                    if (-not $envState.Exists) {
                        $drift.Add((New-GitHubConfigDrift -Category 'AppCredential' -Setting 'environment_present' -Current $false -Desired $true))
                    }

                    # The branch policy is the whole point of using an
                    # environment; without it the secret is no better protected
                    # than a repository secret.
                    $current['environment_pinned_to_default_branch'] = $envState.PinnedToDefaultBranch
                    if (-not $envState.PinnedToDefaultBranch) {
                        $drift.Add((New-GitHubConfigDrift -Category 'AppCredential' -Setting 'environment_pinned_to_default_branch' -Current $envState.PinnedToDefaultBranch -Desired $true))
                    }

                    $variables = Invoke-GitHubApi -Endpoint "repos/$target/environments/$envName/variables" -AllowFailure
                    $secrets = Invoke-GitHubApi -Endpoint "repos/$target/environments/$envName/secrets" -AllowFailure

                    if (-not $envState.Exists) {
                        # An absent environment cannot hold anything; report the
                        # contents as missing rather than as unreadable.
                        $variables = [PSCustomObject]@{ variables = @() }
                        $secrets = [PSCustomObject]@{ secrets = @() }
                    }
                }
                else {
                    $variables = Invoke-GitHubApi -Endpoint "repos/$target/actions/variables" -AllowFailure
                    $secrets = Invoke-GitHubApi -Endpoint "repos/$target/actions/secrets" -AllowFailure
                }

                if ($null -eq $variables -or $null -eq $secrets) {
                    Write-Warning "Could not list Actions variables/secrets for $target. The gh token likely lacks the 'secrets'/'variables' permissions; skipping the AppCredential category."
                    $skippedChecks.Add('AppCredential')
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

            $usesPagesWorkflow = $null
            if ($Check -contains 'CloudflareCredential') {
                $cf = $desired.CloudflareCredential

                # Gate on the workflow, not just on the secret being absent:
                # these credentials are meaningless in a repo that never
                # deploys Pages, and reporting them as drift everywhere would
                # bury the repositories that genuinely need them.
                $usesPagesWorkflow = Test-GitHubPagesWorkflow -Repository $target -Marker $cf.WorkflowMarker
                $current['uses_pages_workflow'] = $usesPagesWorkflow

                if (-not $usesPagesWorkflow) {
                    Write-Verbose "$target does not call the central Pages workflow; skipping the Cloudflare credential check."
                }
                else {
                    # Repository-level on purpose: the reusable workflow's
                    # detect-cloudflare job gates deploys on these secrets and
                    # declares no environment, so an environment secret would
                    # read as empty there and silently disable deploys.
                    $secrets = Invoke-GitHubApi -Endpoint "repos/$target/actions/secrets" -AllowFailure

                    if ($null -eq $secrets) {
                        Write-Warning "Could not list Actions secrets for $target. The gh token likely lacks the 'secrets' permission; skipping the CloudflareCredential category."
                        $skippedChecks.Add('CloudflareCredential')
                    }
                    else {
                        foreach ($name in @($cf.AccountIdSecretName, $cf.ApiTokenSecretName)) {
                            $present = @($secrets.secrets | Where-Object { $_.name -eq $name }).Count -gt 0
                            $current[$name] = $present
                            if (-not $present) {
                                $drift.Add((New-GitHubConfigDrift -Category 'CloudflareCredential' -Setting $name -Current $false -Desired $true))
                            }
                        }
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
                IsFork      = [bool]$repo.fork
                # Only covers the categories that were actually evaluated;
                # consult SkippedChecks before treating this as a clean bill.
                IsCompliant = ($drift.Count -eq 0)
                DriftCount  = $drift.Count
                SkippedChecks = $skippedChecks.ToArray()
                Drift       = $drift.ToArray()
                Current     = $current
                Baseline    = $desired
                Checked     = $Check
                RulesetId   = $rulesetId
                RulesetDetail = $rulesetDetail
                CredentialScope = $credentialScope
                DefaultBranch = $repo.default_branch
                UsesPagesWorkflow = $usesPagesWorkflow
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

    .PARAMETER CloudflareCredential
        Credential from Get-CloudflareCredential. Required to remediate drift in
        the CloudflareCredential category; without it those items are skipped
        with a warning.

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
        $cf = Get-CloudflareCredential
        Get-GitHubRepoConfig -All -Check CloudflareCredential | Set-GitHubRepoConfig -CloudflareCredential $cf

        Roll the Cloudflare Pages secrets out to the repositories that deploy
        through the central Pages workflow. Repositories that do not call it are
        left untouched.

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
        [PSTypeName('Dotfiles.CloudflareCredential')]
        [PSCustomObject]$CloudflareCredential,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Settings', 'Actions', 'Ruleset', 'AppCredential', 'CloudflareCredential')]
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

        $auditArgs = @{ Repository = $Repository; Check = @('Settings', 'Actions', 'Ruleset', 'AppCredential', 'CloudflareCredential') }
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
                    $scope = $config.CredentialScope
                    $useEnv = ($null -ne $scope) -and $scope.UseEnvironment
                    $envName = if ($useEnv) { $scope.Environment } else { '' }
                    $scopeLabel = if ($useEnv) { "environment '$envName'" } else { 'repository' }

                    # Scope flags appended to every gh secret/variable call, so
                    # the credential lands in the environment when one is used.
                    $scopeArgs = @('--repo', $target)
                    if ($useEnv) { $scopeArgs += @('--env', $envName) }

                    # The environment has to exist before anything can be stored
                    # in it, and the branch policy is what makes storing it there
                    # worthwhile - so both are created up front, ahead of the
                    # secret and variable that depend on them.
                    $needsEnvironment = $useEnv -and @($credentialDrift | Where-Object { $_.Setting -eq 'environment_present' }).Count -gt 0
                    $needsPin = $useEnv -and @($credentialDrift | Where-Object { $_.Setting -eq 'environment_pinned_to_default_branch' }).Count -gt 0

                    if ($needsEnvironment -or $needsPin) {
                        # One idempotent PUT covers both cases: it creates the
                        # environment when absent and switches an existing,
                        # unrestricted one to custom branch policies, which the
                        # API requires before a branch policy can be added.
                        $action = if ($needsEnvironment) { "Create environment '$envName'" } else { "Enable branch policies on environment '$envName'" }
                        if ($PSCmdlet.ShouldProcess($target, $action)) {
                            $null = Invoke-GitHubApi -Endpoint "repos/$target/environments/$envName" -Method 'PUT' -Body @{
                                deployment_branch_policy = @{
                                    protected_branches     = $false
                                    custom_branch_policies = $true
                                }
                            }
                            if ($needsEnvironment) { $applied.Add('AppCredential/environment_present') }
                        }
                    }

                    if ($needsPin) {
                        $branch = $config.DefaultBranch
                        if ($PSCmdlet.ShouldProcess($target, "Pin environment '$envName' to branch '$branch'")) {
                            $policy = Invoke-GitHubApi -Endpoint "repos/$target/environments/$envName/deployment-branch-policies" `
                                -Method 'POST' -Body @{ name = $branch; type = 'branch' } -AllowFailure
                            if ($null -eq $policy) {
                                Write-Error "Could not pin environment '$envName' on $target to '$branch'. Without a branch policy the environment secret is no safer than a repository secret."
                                $skipped.Add('AppCredential/environment_pinned_to_default_branch')
                            }
                            else {
                                $applied.Add('AppCredential/environment_pinned_to_default_branch')
                            }
                        }
                    }

                    foreach ($item in $credentialDrift) {
                        if ($item.Setting -eq $variableName) {
                            if ($PSCmdlet.ShouldProcess($target, "Set $scopeLabel variable $variableName")) {
                                $result = Invoke-GitHubCli -Arguments (@('variable', 'set', $variableName) + $scopeArgs + @('--body', $AppCredential.AppId)) -AllowFailure -ErrorContext "gh variable set $variableName on $target"
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
                            if ($PSCmdlet.ShouldProcess($target, "Set $scopeLabel secret $secretName")) {
                                $plain = ConvertFrom-DotfilesSecureString -SecureString $AppCredential.PrivateKey
                                try {
                                    # Piped on stdin so the PEM never appears in
                                    # a process argument list.
                                    $result = Invoke-GitHubCli -Arguments (@('secret', 'set', $secretName) + $scopeArgs) -StdIn $plain -AllowFailure -ErrorContext "gh secret set $secretName on $target"
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

            # --- Cloudflare Pages secrets from 1Password ---
            $cloudflareDrift = @($drift | Where-Object { $_.Category -eq 'CloudflareCredential' })
            if ($cloudflareDrift.Count -gt 0) {
                if ($null -eq $CloudflareCredential) {
                    Write-Warning "$target is missing the Cloudflare Pages secrets but -CloudflareCredential was not supplied. Run Get-CloudflareCredential and pass the result to remediate."
                    foreach ($item in $cloudflareDrift) { $skipped.Add("CloudflareCredential/$($item.Setting)") }
                }
                else {
                    $cfBaseline = $config.Baseline.CloudflareCredential
                    $values = @{
                        $cfBaseline.AccountIdSecretName = $CloudflareCredential.AccountId
                        $cfBaseline.ApiTokenSecretName  = $CloudflareCredential.ApiToken
                    }

                    foreach ($item in $cloudflareDrift) {
                        $secure = $values[$item.Setting]
                        if ($null -eq $secure) {
                            Write-Error "No value available for $($item.Setting) on ${target}."
                            $skipped.Add("CloudflareCredential/$($item.Setting)")
                            continue
                        }

                        if ($PSCmdlet.ShouldProcess($target, "Set repository secret $($item.Setting)")) {
                            $plain = ConvertFrom-DotfilesSecureString -SecureString $secure
                            try {
                                # Piped on stdin so the value never appears in a
                                # process argument list.
                                $result = Invoke-GitHubCli -Arguments @('secret', 'set', $item.Setting, '--repo', $target) -StdIn $plain -AllowFailure -ErrorContext "gh secret set $($item.Setting) on $target"
                                if ($null -eq $result) {
                                    Write-Error "Could not set secret $($item.Setting) on ${target}."
                                    $skipped.Add("CloudflareCredential/$($item.Setting)")
                                }
                                else {
                                    $applied.Add("CloudflareCredential/$($item.Setting)")
                                }
                            }
                            finally {
                                $plain = $null
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
