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
        on the SkippedChecks property rather than counted as drift.

        IsCompliant is therefore tri-state:
          $true   every requested category was evaluated and nothing drifted
          $false  something drifted
          $null   nothing drifted, but at least one category could not be
                  checked, so compliance is unknown

        `Where-Object { -not $_.IsCompliant }` consequently surfaces both real
        drift and repositories that could not be fully audited.

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
                    # Name alone is not identity: a tag ruleset or one inherited
                    # from an organisation can share the name, and PUTting a
                    # branch payload over either would mutate the wrong object.
                    $existing = @($rulesetList.Rulesets | Where-Object {
                            $_.name -eq $wanted.Name -and
                            $_.target -eq 'branch' -and
                            ($null -eq $_.source_type -or $_.source_type -eq 'Repository')
                        })[0]

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

                            # A ruleset can carry the right name and rules while
                            # targeting release/* - in which case the default
                            # branch is not protected at all.
                            $includes = @()
                            if ($null -ne $detail.conditions -and $null -ne $detail.conditions.ref_name) {
                                $includes = @($detail.conditions.ref_name.include)
                            }
                            $coversDefault = ($includes -contains '~ALL') -or ($includes -contains '~DEFAULT_BRANCH')
                            if (-not $coversDefault -and -not [string]::IsNullOrWhiteSpace($repo.default_branch)) {
                                $coversDefault = $includes -contains "refs/heads/$($repo.default_branch)"
                            }
                            $current['ruleset_covers_default_branch'] = $coversDefault
                            if (-not $coversDefault) {
                                $drift.Add((New-GitHubConfigDrift -Category 'Ruleset' -Setting 'ruleset_covers_default_branch' -Current $false -Desired $true))
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
            $extraBranchPolicies = @()
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
                    $extraBranchPolicies = @($envState.ExtraBranchPolicies)
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
                # Tri-state on purpose. $true only when every requested
                # category was evaluated and clean; $null when something could
                # not be checked, so a caller that treats the result as a
                # boolean gets "not true" rather than a false clean bill.
                IsCompliant = if ($drift.Count -gt 0) { $false }
                elseif ($skippedChecks.Count -gt 0) { $null }
                else { $true }
                DriftCount  = $drift.Count
                SkippedChecks = $skippedChecks.ToArray()
                Drift       = $drift.ToArray()
                Current     = $current
                Baseline    = $desired
                Checked     = $Check
                RulesetId   = $rulesetId
                RulesetDetail = $rulesetDetail
                CredentialScope = $credentialScope
                ExtraBranchPolicies = $extraBranchPolicies
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

                    # The pin is the entire security value of using an
                    # environment, so it is a prerequisite: if it cannot be
                    # established the credential is not written at all. Writing
                    # it into an unrestricted environment would be strictly worse
                    # than leaving it absent, because it would look protected.
                    $environmentReady = $useEnv
                    if ($needsPin) {
                        $environmentReady = $false
                        $branch = $config.DefaultBranch
                        if ($PSCmdlet.ShouldProcess($target, "Pin environment '$envName' to branch '$branch'")) {
                            # Remove any broader policy first; leaving feature/*
                            # in place would let a PR branch read the secret.
                            foreach ($extra in @($config.ExtraBranchPolicies)) {
                                $null = Invoke-GitHubApi -Endpoint "repos/$target/environments/$envName/deployment-branch-policies/$($extra.id)" `
                                    -Method 'DELETE' -AllowFailure
                                Write-Verbose "Removed deployment branch policy '$($extra.name)' from $target/$envName"
                            }

                            $policy = Invoke-GitHubApi -Endpoint "repos/$target/environments/$envName/deployment-branch-policies" `
                                -Method 'POST' -Body @{ name = $branch; type = 'branch' } -AllowFailure
                            if ($null -eq $policy) {
                                Write-Error "Could not pin environment '$envName' on $target to '$branch'. Without a branch policy the environment secret is no safer than a repository secret."
                                $skipped.Add('AppCredential/environment_pinned_to_default_branch')
                            }
                            else {
                                $applied.Add('AppCredential/environment_pinned_to_default_branch')
                                $environmentReady = $true
                            }
                        }
                    }

                    if ($useEnv -and -not $environmentReady) {
                        Write-Warning "Not writing the App credential to ${target}: environment '$envName' is not pinned to the default branch, so an environment secret there would be no safer than a repository secret."
                        foreach ($item in $credentialDrift) {
                            if ($item.Setting -in @($variableName, $secretName)) {
                                $skipped.Add("AppCredential/$($item.Setting)")
                            }
                        }
                        $credentialDrift = @()
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

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCASxWlO+DJjxZvk
# PvvNSJQx4UeoZktIXi0S/lCDobZ3lKCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
# p05/1ElTgWD0MA0GCSqGSIb3DQEBCwUAMCMxITAfBgNVBAMMGEplYW4tUGF1bCB2
# YW4gUmF2ZW5zYmVyZzAeFw0yNjAxMTQxMjU3MjBaFw0zMTAxMTQxMzA2NDdaMCMx
# ITAfBgNVBAMMGEplYW4tUGF1bCB2YW4gUmF2ZW5zYmVyZzCCAiIwDQYJKoZIhvcN
# AQEBBQADggIPADCCAgoCggIBAMm6cmnzWkwTZJW3lpa98k2eQDQJB6Twyr5U/6cU
# bXWG2xNCGTZCxH3a/77uGX5SDh4g/6x9+fSuhkGkjVcCmP2qpfeHOqafOByrzg6p
# /oI4Zdn4eAHRdhFV+IDmP68zaLtG9oai2k4Ilsc9qINOKPesVZdJd7sxtrutZS8e
# UqBmQr3rYD96pBZXt2YpJXmqSZdS9KdrboVms6Y11naZCSoBbi+XhbyfDZzgN65i
# NZCTahRj6RkJECzU7FXsV4qhuJca4fGHue2Lc027w0A/ZxZkbXkVnTtZbP3x0Q6v
# wkH0r3lfeRcFtKisHKFfDdsIlS+H9cQ8u2NMNWK3375By4yUnQm1NJjVFDZNAZI/
# A/Os3DpRXGyW8gxlSb+CGqHUQU0+YtrSuaXaLc5x0K+QcBmNBzCB/gQArY95g5dn
# rO3m2+XWhHmP6zP/fBMZW1BPLXTFbK/tXY/rFuWZ77MRka12Enu8EbhzK+Mfn00m
# ts6TL7AtV6qksjCc+aJPhgPVABMCDkD4QXHvENbE8s99LrjgsJwSyalOxgWovQl+
# 4r4DbReaHfapy4+j/Rxba65YQBSN35dwWqhb8YxyzCEcJ7q1TTvoVEntV0SeC8Lh
# 4rhqdHhyigZUSptw6LMry3bEdDrCAJ8FeW1LdTb+00bayq/J4RTZd4OLiIf07mot
# KTmJAgMBAAGjRjBEMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcD
# AzAdBgNVHQ4EFgQUDt+a1J2KwjQ4CPd2E5gJ3OpVld4wDQYJKoZIhvcNAQELBQAD
# ggIBAFu1W92GGmGvSOOFXMIs/Lu+918MH1rX1UNYdgI1H8/2gDAwfV6eIy+Gu1MK
# rDolIGvdV8eIuu2qGbELnfoeS0czgY0O6uFf6JF1IR/0Rh9Pw1qDmWD+WdI+m4+y
# gPBGz4F/crK+1L8wgfV+tuxCfSJmtu0Ce71DFI+0wvwXWSjhTFxboldsmvOsz+Bp
# X0j4xU6qAsiZK7Tp0VrrLeJEuqE4hC2sTWCJJyP7qmxUjkCqoaiqhci6qSvpg1mJ
# qM4SYkE0FE59z+++4m4DiiNiCzSr/O3uKsfEl2MwZWoZgqLKbMC33I+e/o//EH9/
# HYPWKlEFzXbVj2c3vCRZf2hZZuvfLDoT7i8eZGg3vsTsFnC+ZXKwQTaXqS++q9f3
# rDNYAD+9+GwVyHqVVqwgSME91OgbJ6qfx7H/5VqHHhoJiifSgPiIOSyhvGu9JbcY
# mHkZS3h2P3BU8n/nuqF4eMcQ6LeZDsWCzvHOaHKisRKzSX0yWxjGygp7trqpIi3C
# A3DpBGHXa9r1fwleRfWUeyX/y7pJxT0RRlxNDip4VhK0RRxmE6PL0cq8i92Qs7HA
# csVkGkrIkSYUYhJxemehXwBnwJ1PfDqjvZVpjQdUeP1TTDSNrR3EqiVP5n+nWRYV
# NkoMe75v2tBqXHfq05ryGO9ivXORcmh/MFMgWSR9WYTjZRy3MIIFjTCCBHWgAwIB
# AgIQDpsYjvnQLefv21DiCEAYWjANBgkqhkiG9w0BAQwFADBlMQswCQYDVQQGEwJV
# UzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQu
# Y29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0EwHhcNMjIw
# ODAxMDAwMDAwWhcNMzExMTA5MjM1OTU5WjBiMQswCQYDVQQGEwJVUzEVMBMGA1UE
# ChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYD
# VQQDExhEaWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQC/5pBzaN675F1KPDAiMGkz7MKnJS7JIT3yithZwuEppz1Y
# q3aaza57G4QNxDAf8xukOBbrVsaXbR2rsnnyyhHS5F/WBTxSD1Ifxp4VpX6+n6lX
# FllVcq9ok3DCsrp1mWpzMpTREEQQLt+C8weE5nQ7bXHiLQwb7iDVySAdYyktzuxe
# TsiT+CFhmzTrBcZe7FsavOvJz82sNEBfsXpm7nfISKhmV1efVFiODCu3T6cw2Vbu
# yntd463JT17lNecxy9qTXtyOj4DatpGYQJB5w3jHtrHEtWoYOAMQjdjUN6QuBX2I
# 9YI+EJFwq1WCQTLX2wRzKm6RAXwhTNS8rhsDdV14Ztk6MUSaM0C/CNdaSaTC5qmg
# Z92kJ7yhTzm1EVgX9yRcRo9k98FpiHaYdj1ZXUJ2h4mXaXpI8OCiEhtmmnTK3kse
# 5w5jrubU75KSOp493ADkRSWJtppEGSt+wJS00mFt6zPZxd9LBADMfRyVw4/3IbKy
# Ebe7f/LVjHAsQWCqsWMYRJUadmJ+9oCw++hkpjPRiQfhvbfmQ6QYuKZ3AeEPlAwh
# HbJUKSWJbOUOUlFHdL4mrLZBdd56rF+NP8m800ERElvlEFDrMcXKchYiCd98THU/
# Y+whX8QgUWtvsauGi0/C1kVfnSD8oR7FwI+isX4KJpn15GkvmB0t9dmpsh3lGwID
# AQABo4IBOjCCATYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQU7NfjgtJxXWRM
# 3y5nP+e6mK4cD08wHwYDVR0jBBgwFoAUReuir/SSy4IxLVGLp6chnfNtyA8wDgYD
# VR0PAQH/BAQDAgGGMHkGCCsGAQUFBwEBBG0wazAkBggrBgEFBQcwAYYYaHR0cDov
# L29jc3AuZGlnaWNlcnQuY29tMEMGCCsGAQUFBzAChjdodHRwOi8vY2FjZXJ0cy5k
# aWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3J0MEUGA1UdHwQ+
# MDwwOqA4oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3Vy
# ZWRJRFJvb3RDQS5jcmwwEQYDVR0gBAowCDAGBgRVHSAAMA0GCSqGSIb3DQEBDAUA
# A4IBAQBwoL9DXFXnOF+go3QbPbYW1/e/Vwe9mqyhhyzshV6pGrsi+IcaaVQi7aSI
# d229GhT0E0p6Ly23OO/0/4C5+KH38nLeJLxSA8hO0Cre+i1Wz/n096wwepqLsl7U
# z9FDRJtDIeuWcqFItJnLnU+nBgMTdydE1Od/6Fmo8L8vC6bp8jQ87PcDx4eo0kxA
# GTVGamlUsLihVo7spNU96LHc/RzY9HdaXFSMb++hUD38dglohJ9vytsgjTVgHAID
# yyCwrFigDkBjxZgiwbJZ9VVrzyerbHbObyMt9H5xaiNrIv8SuFQtJ37YOtnwtoeW
# /VvRXKwYw02fc7cBqZ9Xql4o4rmUMIIGtDCCBJygAwIBAgIQDcesVwX/IZkuQEMi
# DDpJhjANBgkqhkiG9w0BAQsFADBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGln
# aUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhE
# aWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQwHhcNMjUwNTA3MDAwMDAwWhcNMzgwMTE0
# MjM1OTU5WjBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4x
# QTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQw
# OTYgU0hBMjU2IDIwMjUgQ0ExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKC
# AgEAtHgx0wqYQXK+PEbAHKx126NGaHS0URedTa2NDZS1mZaDLFTtQ2oRjzUXMmxC
# qvkbsDpz4aH+qbxeLho8I6jY3xL1IusLopuW2qftJYJaDNs1+JH7Z+QdSKWM06qc
# hUP+AbdJgMQB3h2DZ0Mal5kYp77jYMVQXSZH++0trj6Ao+xh/AS7sQRuQL37QXbD
# hAktVJMQbzIBHYJBYgzWIjk8eDrYhXDEpKk7RdoX0M980EpLtlrNyHw0Xm+nt5pn
# YJU3Gmq6bNMI1I7Gb5IBZK4ivbVCiZv7PNBYqHEpNVWC2ZQ8BbfnFRQVESYOszFI
# 2Wv82wnJRfN20VRS3hpLgIR4hjzL0hpoYGk81coWJ+KdPvMvaB0WkE/2qHxJ0ucS
# 638ZxqU14lDnki7CcoKCz6eum5A19WZQHkqUJfdkDjHkccpL6uoG8pbF0LJAQQZx
# st7VvwDDjAmSFTUms+wV/FbWBqi7fTJnjq3hj0XbQcd8hjj/q8d6ylgxCZSKi17y
# Vp2NL+cnT6Toy+rN+nM8M7LnLqCrO2JP3oW//1sfuZDKiDEb1AQ8es9Xr/u6bDTn
# YCTKIsDq1BtmXUqEG1NqzJKS4kOmxkYp2WyODi7vQTCBZtVFJfVZ3j7OgWmnhFr4
# yUozZtqgPrHRVHhGNKlYzyjlroPxul+bgIspzOwbtmsgY1MCAwEAAaOCAV0wggFZ
# MBIGA1UdEwEB/wQIMAYBAf8CAQAwHQYDVR0OBBYEFO9vU0rp5AZ8esrikFb2L9RJ
# 7MtOMB8GA1UdIwQYMBaAFOzX44LScV1kTN8uZz/nupiuHA9PMA4GA1UdDwEB/wQE
# AwIBhjATBgNVHSUEDDAKBggrBgEFBQcDCDB3BggrBgEFBQcBAQRrMGkwJAYIKwYB
# BQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBBBggrBgEFBQcwAoY1aHR0
# cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJvb3RHNC5j
# cnQwQwYDVR0fBDwwOjA4oDagNIYyaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0Rp
# Z2lDZXJ0VHJ1c3RlZFJvb3RHNC5jcmwwIAYDVR0gBBkwFzAIBgZngQwBBAIwCwYJ
# YIZIAYb9bAcBMA0GCSqGSIb3DQEBCwUAA4ICAQAXzvsWgBz+Bz0RdnEwvb4LyLU0
# pn/N0IfFiBowf0/Dm1wGc/Do7oVMY2mhXZXjDNJQa8j00DNqhCT3t+s8G0iP5kvN
# 2n7Jd2E4/iEIUBO41P5F448rSYJ59Ib61eoalhnd6ywFLerycvZTAz40y8S4F3/a
# +Z1jEMK/DMm/axFSgoR8n6c3nuZB9BfBwAQYK9FHaoq2e26MHvVY9gCDA/JYsq7p
# GdogP8HRtrYfctSLANEBfHU16r3J05qX3kId+ZOczgj5kjatVB+NdADVZKON/gnZ
# ruMvNYY2o1f4MXRJDMdTSlOLh0HCn2cQLwQCqjFbqrXuvTPSegOOzr4EWj7PtspI
# HBldNE2K9i697cvaiIo2p61Ed2p8xMJb82Yosn0z4y25xUbI7GIN/TpVfHIqQ6Ku
# /qjTY6hc3hsXMrS+U0yy+GWqAXam4ToWd2UQ1KYT70kZjE4YtL8Pbzg0c1ugMZyZ
# Zd/BdHLiRu7hAWE6bTEm4XYRkA6Tl4KSFLFk43esaUeqGkH/wyW4N7OigizwJWeu
# kcyIPbAvjSabnf7+Pu0VrFgoiovRDiyx3zEdmcif/sYQsfch28bZeUz2rtY/9TCA
# 6TD8dC3JE3rYkrhLULy7Dc90G6e8BlqmyIjlgp2+VqsS9/wQD7yFylIz0scmbKvF
# oW2jNrbM1pD2T7m3XDCCBu0wggTVoAMCAQICEAqA7xhLjfEFgtHEdqeVdGgwDQYJ
# KoZIhvcNAQELBQAwaTELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJ
# bmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVkIEc0IFRpbWVTdGFtcGluZyBS
# U0E0MDk2IFNIQTI1NiAyMDI1IENBMTAeFw0yNTA2MDQwMDAwMDBaFw0zNjA5MDMy
# MzU5NTlaMGMxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7
# MDkGA1UEAxMyRGlnaUNlcnQgU0hBMjU2IFJTQTQwOTYgVGltZXN0YW1wIFJlc3Bv
# bmRlciAyMDI1IDEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDQRqwt
# Esae0OquYFazK1e6b1H/hnAKAd/KN8wZQjBjMqiZ3xTWcfsLwOvRxUwXcGx8AUjn
# i6bz52fGTfr6PHRNv6T7zsf1Y/E3IU8kgNkeECqVQ+3bzWYesFtkepErvUSbf+EI
# YLkrLKd6qJnuzK8Vcn0DvbDMemQFoxQ2Dsw4vEjoT1FpS54dNApZfKY61HAldytx
# NM89PZXUP/5wWWURK+IfxiOg8W9lKMqzdIo7VA1R0V3Zp3DjjANwqAf4lEkTlCDQ
# 0/fKJLKLkzGBTpx6EYevvOi7XOc4zyh1uSqgr6UnbksIcFJqLbkIXIPbcNmA98Os
# kkkrvt6lPAw/p4oDSRZreiwB7x9ykrjS6GS3NR39iTTFS+ENTqW8m6THuOmHHjQN
# C3zbJ6nJ6SXiLSvw4Smz8U07hqF+8CTXaETkVWz0dVVZw7knh1WZXOLHgDvundrA
# tuvz0D3T+dYaNcwafsVCGZKUhQPL1naFKBy1p6llN3QgshRta6Eq4B40h5avMcpi
# 54wm0i2ePZD5pPIssoszQyF4//3DoK2O65Uck5Wggn8O2klETsJ7u8xEehGifgJY
# i+6I03UuT1j7FnrqVrOzaQoVJOeeStPeldYRNMmSF3voIgMFtNGh86w3ISHNm0Ia
# adCKCkUe2LnwJKa8TIlwCUNVwppwn4D3/Pt5pwIDAQABo4IBlTCCAZEwDAYDVR0T
# AQH/BAIwADAdBgNVHQ4EFgQU5Dv88jHt/f3X85FxYxlQQ89hjOgwHwYDVR0jBBgw
# FoAU729TSunkBnx6yuKQVvYv1Ensy04wDgYDVR0PAQH/BAQDAgeAMBYGA1UdJQEB
# /wQMMAoGCCsGAQUFBwMIMIGVBggrBgEFBQcBAQSBiDCBhTAkBggrBgEFBQcwAYYY
# aHR0cDovL29jc3AuZGlnaWNlcnQuY29tMF0GCCsGAQUFBzAChlFodHRwOi8vY2Fj
# ZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRUaW1lU3RhbXBpbmdS
# U0E0MDk2U0hBMjU2MjAyNUNBMS5jcnQwXwYDVR0fBFgwVjBUoFKgUIZOaHR0cDov
# L2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZEc0VGltZVN0YW1waW5n
# UlNBNDA5NlNIQTI1NjIwMjVDQTEuY3JsMCAGA1UdIAQZMBcwCAYGZ4EMAQQCMAsG
# CWCGSAGG/WwHATANBgkqhkiG9w0BAQsFAAOCAgEAZSqt8RwnBLmuYEHs0QhEnmNA
# ciH45PYiT9s1i6UKtW+FERp8FgXRGQ/YAavXzWjZhY+hIfP2JkQ38U+wtJPBVBaj
# YfrbIYG+Dui4I4PCvHpQuPqFgqp1PzC/ZRX4pvP/ciZmUnthfAEP1HShTrY+2DE5
# qjzvZs7JIIgt0GCFD9ktx0LxxtRQ7vllKluHWiKk6FxRPyUPxAAYH2Vy1lNM4kze
# kd8oEARzFAWgeW3az2xejEWLNN4eKGxDJ8WDl/FQUSntbjZ80FU3i54tpx5F/0Kr
# 15zW/mJAxZMVBrTE2oi0fcI8VMbtoRAmaaslNXdCG1+lqvP4FbrQ6IwSBXkZagHL
# hFU9HCrG/syTRLLhAezu/3Lr00GrJzPQFnCEH1Y58678IgmfORBPC1JKkYaEt2Od
# Dh4GmO0/5cHelAK2/gTlQJINqDr6JfwyYHXSd+V08X1JUPvB4ILfJdmL+66Gp3CS
# BXG6IwXMZUXBhtCyIaehr0XkBoDIGMUG1dUtwq1qmcwbdUfcSYCn+OwncVUXf53V
# JUNOaMWMts0VlRYxe5nK+At+DI96HAlXHAL5SlfYxJ7La54i71McVWRP66bW+yER
# NpbJCjyCYG2j+bdpxo/1Cy4uPcU3AWVPGrbn5PhDBf3Froguzzhk++ami+r3Qrx5
# bIbY3TVzgiFI7Gq3zWcxggYTMIIGDwIBATA3MCMxITAfBgNVBAMMGEplYW4tUGF1
# bCB2YW4gUmF2ZW5zYmVyZwIQELbg9grCcadOf9RJU4Fg9DANBglghkgBZQMEAgEF
# AKCBhDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgor
# BgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3
# DQEJBDEiBCBuA5ooyF1/fJXOfbIhQtvHk0BxQyXspEjxv2Np9v4b7zANBgkqhkiG
# 9w0BAQEFAASCAgCJLKrA8K2WaHLWJ5GKeKYACTbkWgviSLtJwVC66VsPYeC7PTVS
# eUV2uGI4bVkFWxDU0b6sDCOCQ3phg7IXEJaRM6BTWaMNf2DhXfTRK1Z5k/q4wpn/
# /dL9nldXZyTIYVCrcCMhv2gwJ6oVi6bL9Im0aCqxtUuQRj+t24nIRMG3is7taXVn
# xcLrrJ6FnBxO2lQt05nGUYV8HFGfOQmVtxzvr2py5nwCMKlFjO2PBOUjaPBoK6hE
# Oi84EvQ+d9BjolM0Iv9A55T75RjkgwR6GN7tguSjdJFXRdu6d/N3crOjtOfEOs3W
# W3MM1Ygul3iupEgtYWJHajeiZccA1Ys8aU0bgXl5+sblR/wN9Hy0cm14Ry4P5OEE
# 8kJr+q46gQKyFu7FykxaOIiKROvE8/LG/rrzH9G5eW8hfG+1XlylgFVSdtwNQ/nh
# OGEBq671c3kPFey5w1rsSg4l9BmM1l2tCxjN5ZVemd+L8kPQg1ubEUFbcAJZsHkA
# Wwv03Wp8Nt3xtSxgu3dn7ZFNcEH6354lGO+E8zd927e6Hu9ldNhwtmrcFJ55mqzE
# yJvzNzBOb2XrAWcaJQbKxHXqm2vGEokpD2IqBeY2MZVe9Pr6Jmf8pXFLgQdSLn5c
# l8ChI5OXLS27bb4GEpQ29OIHWvREWBLkNQo2eKEFU9JrW+KvCWEAXAPH6KGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA3MjkwODE4MDZaMC8GCSqGSIb3DQEJBDEi
# BCAnSbiOMCeQotN26vwPMRZGjOra4qu6tmDkQ2AvIwhOIzANBgkqhkiG9w0BAQEF
# AASCAgATL1Kp7jaatH1B7m1hR0+n9HE37vs4mp1w5w+o6TiCiYMObuBpazP1AkFz
# fZw2q/Mg+IiapPmderx7TB2BUdWDiwoYlPJvjGlpPH4ygQ9cS5++I60q5S7zXxnU
# FFX5UTP5oTfXxya041f7q4TbbX7LfYcrZgvFO4fELf96RxMH1syPJUBx/pMgmRxI
# Me5NLMS6GwRrtQJXeU7+3TRDvj8PTKoffHPBycENnLeAXDHSaz0vlCUHiRMK+P1M
# bJLXcO0F/i/qm8iQ4gb7kdscqhZAlXnw0HFCUHv/5fvOPYD21OHO7VRZQSghDuo/
# 4nRz9hS+L8RAgMWAS6TZjnmiptl7ZXXCMqaS63ecGVSMIcOivh+AzwBIJYyfUiKj
# lmcFWh885kY/ohdzjmtUNKjtuPiHZ+ScVnQh/PPh4GBHuIKpT/aiaTaoIP5qTF9J
# OKpkMWlWd9wrHpP+B6CF65P7K2Pvtse9N/SEjkjn97AkEbgJlW7xgAC+cFGmiygT
# zUr0/rf8usvI2OgJac8aqj/xxUP5NWK8WRANPYbMMqvjtDMOzbIhCHHi7eHP7Vls
# IEozckdD4sM8ypJtm2ORyNgnmhyWpNrhmRtjh9dd22+cJN75T+Mef5x6G+vDqxuf
# 5Brwo2thWW0WxKjXAj1BILxoNStrGRL8bdX/3Y6VTBSZ0bHg9g==
# SIG # End signature block
