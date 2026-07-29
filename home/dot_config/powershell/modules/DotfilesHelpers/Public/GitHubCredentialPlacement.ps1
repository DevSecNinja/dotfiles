# Decide where a credential may safely live, and detect who needs it.
#
# Placement is a security decision, not a preference: an environment secret
# is only safer than a repository secret when the environment is pinned to
# the default branch, and the GitHub Free plan withholds that on private
# repositories. These helpers make that determination explicit so the
# callers can fail closed.
#
# Part of the GitHub repository configuration tooling; see
# GitHubRepoConfig.ps1 for the public commands and docs/github-repo-config.md
# for the user-facing guide.

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
        return [PSCustomObject]@{ Exists = $false; PinnedToDefaultBranch = $false; ExtraBranchPolicies = @() }
    }

    # Pinned means the default branch and *nothing else*. A policy list of
    # main + feature/* would still let a workflow on an attacker-controlled
    # branch read the secret, so merely containing the default branch is not
    # enough - the extra policies are reported so remediation can remove them.
    $pinned = $false
    $extraPolicies = @()
    if ($null -ne $env.deployment_branch_policy -and $env.deployment_branch_policy.custom_branch_policies) {
        $policies = Invoke-GitHubApi -Endpoint "repos/$Repository/environments/$Environment/deployment-branch-policies" -AllowFailure
        if ($null -ne $policies -and -not [string]::IsNullOrWhiteSpace($DefaultBranch)) {
            $branchPolicies = @($policies.branch_policies)
            $matching = @($branchPolicies | Where-Object { $_.name -eq $DefaultBranch })
            $extraPolicies = @($branchPolicies | Where-Object { $_.name -ne $DefaultBranch })
            $pinned = ($matching.Count -eq 1) -and ($extraPolicies.Count -eq 0)
        }
    }

    return [PSCustomObject]@{
        Exists                = $true
        PinnedToDefaultBranch = $pinned
        ExtraBranchPolicies   = $extraPolicies
    }
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
