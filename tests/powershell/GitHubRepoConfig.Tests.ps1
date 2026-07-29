#Requires -Version 5.1
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Test fixtures build SecureStrings from literal, non-sensitive placeholder values.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'InModuleScope -Parameters values are consumed inside nested Mock scriptblocks, which the analyzer cannot trace.')]
param()
<#
.SYNOPSIS
    Pester tests for the GitHub repository configuration audit and remediation.

.DESCRIPTION
    Covers Get-GitHubRepoBaseline, Get-GitHubAppCredential,
    Get-GitHubRepoConfig and Set-GitHubRepoConfig.

    Every external dependency is mocked at the module's own CLI wrappers
    (Invoke-GitHubCli, Invoke-OnePasswordCli, Test-GitHubCliReady), so the
    suite runs identically on any platform without the `gh` or `op` binaries
    being installed and never touches a real repository.
#>

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $modulePath = Join-Path $script:RepoRoot "home/dot_config/powershell/modules/DotfilesHelpers"
    Get-Module DotfilesHelpers -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $modulePath -Force -DisableNameChecking

    # A repository whose settings already match the baseline exactly.
    function script:New-CompliantRepoResponse {
        return [PSCustomObject]@{
            name                        = 'compliant'
            visibility                  = 'public'
            archived                    = $false
            default_branch              = 'main'
            allow_squash_merge          = $true
            allow_merge_commit          = $false
            allow_rebase_merge          = $false
            allow_auto_merge            = $true
            delete_branch_on_merge      = $true
            allow_update_branch         = $true
            squash_merge_commit_title   = 'PR_TITLE'
            squash_merge_commit_message = 'BLANK'
            has_issues                  = $true
            has_wiki                    = $false
            has_projects                = $false
            has_discussions             = $false
            web_commit_signoff_required = $false
        }
    }

    # A repository at GitHub's defaults, i.e. fully drifted.
    function script:New-DriftedRepoResponse {
        $repo = script:New-CompliantRepoResponse
        $repo.name = 'drifted'
        $repo.allow_merge_commit = $true
        $repo.allow_rebase_merge = $true
        $repo.allow_auto_merge = $false
        $repo.delete_branch_on_merge = $false
        $repo.squash_merge_commit_title = 'COMMIT_OR_PR_TITLE'
        return $repo
    }

    function script:New-CompliantActionsResponse {
        return [PSCustomObject]@{
            default_workflow_permissions     = 'read'
            can_approve_pull_request_reviews = $false
        }
    }

    function script:New-CompliantRulesetDetail {
        return [PSCustomObject]@{
            id            = 42
            name          = 'Default'
            target        = 'branch'
            source_type   = 'Repository'
            enforcement   = 'active'
            conditions    = [PSCustomObject]@{
                ref_name = [PSCustomObject]@{ include = @('~DEFAULT_BRANCH'); exclude = @() }
            }
            bypass_actors = @(
                [PSCustomObject]@{ actor_id = 5; actor_type = 'RepositoryRole'; bypass_mode = 'always' }
            )
            rules         = @(
                [PSCustomObject]@{ type = 'deletion' }
                [PSCustomObject]@{ type = 'non_fast_forward' }
                [PSCustomObject]@{
                    type       = 'pull_request'
                    parameters = [PSCustomObject]@{
                        allowed_merge_methods           = @('squash')
                        required_approving_review_count = 0
                    }
                }
            )
        }
    }

    # Canned ruleset-list responses for the Get-GitHubRulesetList seam.
    function script:New-RulesetListPresent {
        return [PSCustomObject]@{
            Available = $true
            Rulesets  = @([PSCustomObject]@{ id = 42; name = 'Default'; target = 'branch'; source_type = 'Repository' })
        }
    }

    function script:New-RulesetListEmpty {
        return [PSCustomObject]@{ Available = $true; Rulesets = @() }
    }

    function script:New-RulesetListUnavailable {
        return [PSCustomObject]@{ Available = $false; Rulesets = @() }
    }

    # Routes a mocked Invoke-GitHubApi call to the right canned response.
    function script:Get-MockApiResponse {
        param(
            [string]$Endpoint,
            [object]$Repo,
            [object]$Actions,
            [object]$RulesetDetail,
            [object]$Variables,
            [object]$Secrets,
            [object]$EnvironmentDetail,
            [object]$BranchPolicies,
            [object]$WorkflowListing,
            [object]$WorkflowFile
        )

        switch -Regex ($Endpoint) {
            '/contents/\.github/workflows$' { return $WorkflowListing }
            '/contents/\.github/workflows/' { return $WorkflowFile }
            '/actions/permissions/workflow$' { return $Actions }
            '/environments/[^/]+/variables$' { return $Variables }
            '/environments/[^/]+/secrets$' { return $Secrets }
            '/environments/[^/]+/deployment-branch-policies$' { return $BranchPolicies }
            '/environments/[^/]+$' { return $EnvironmentDetail }
            '/actions/variables$' { return $Variables }
            '/actions/secrets$' { return $Secrets }
            '/rulesets/\d+$' { return $RulesetDetail }
            default { return $Repo }
        }
    }
}

Describe "GitHub repo config command availability" -Tag "Unit" {
    It "exports <_>" -ForEach @(
        'Get-GitHubRepoBaseline'
        'Get-GitHubRepoConfig'
        'Set-GitHubRepoConfig'
        'Get-GitHubAppCredential'
    ) {
        Get-Command -Name $_ -Module DotfilesHelpers -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It "lists <_> in the module manifest" -ForEach @(
        'Get-GitHubRepoBaseline'
        'Get-GitHubRepoConfig'
        'Set-GitHubRepoConfig'
        'Get-GitHubAppCredential'
    ) {
        $manifestPath = Join-Path $script:RepoRoot "home/dot_config/powershell/modules/DotfilesHelpers/DotfilesHelpers.psd1"
        $manifest = Import-PowerShellDataFile -Path $manifestPath
        $manifest.FunctionsToExport | Should -Contain $_
    }

    It "provides comment-based help for <_>" -ForEach @(
        'Get-GitHubRepoBaseline'
        'Get-GitHubRepoConfig'
        'Set-GitHubRepoConfig'
        'Get-GitHubAppCredential'
    ) {
        $help = Get-Help $_ -ErrorAction SilentlyContinue
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Description | Should -Not -BeNullOrEmpty
        @($help.Examples.Example).Count | Should -BeGreaterThan 0
    }
}

Describe "Get-GitHubRepoBaseline" -Tag "Unit" {
    It "returns the Settings, Actions, Ruleset and AppCredential sections" {
        $baseline = Get-GitHubRepoBaseline
        $baseline.Keys | Should -Contain 'Settings'
        $baseline.Keys | Should -Contain 'Actions'
        $baseline.Keys | Should -Contain 'Ruleset'
        $baseline.Keys | Should -Contain 'AppCredential'
    }

    It "standardises on squash-only merges" {
        $settings = (Get-GitHubRepoBaseline).Settings
        $settings.allow_squash_merge | Should -BeTrue
        $settings.allow_merge_commit | Should -BeFalse
        $settings.allow_rebase_merge | Should -BeFalse
    }

    It "keeps release-please friendly squash commit formatting" {
        $settings = (Get-GitHubRepoBaseline).Settings
        $settings.squash_merge_commit_title | Should -Be 'PR_TITLE'
        $settings.squash_merge_commit_message | Should -Be 'BLANK'
    }

    It "does not let Actions approve pull requests" {
        (Get-GitHubRepoBaseline).Actions.can_approve_pull_request_reviews | Should -BeFalse
    }

    It "defaults the workflow token to read-only" {
        (Get-GitHubRepoBaseline).Actions.default_workflow_permissions | Should -Be 'read'
    }

    It "keeps the admin bypass on the default-branch ruleset" {
        (Get-GitHubRepoBaseline).Ruleset.AdminCanBypass | Should -BeTrue
    }

    It "requires a pull request on the default branch" {
        (Get-GitHubRepoBaseline).Ruleset.RequirePullRequest | Should -BeTrue
    }

    It "merges an override into a single section without discarding the rest" {
        $baseline = Get-GitHubRepoBaseline -Override @{ Settings = @{ has_wiki = $true } }
        $baseline.Settings.has_wiki | Should -BeTrue
        $baseline.Settings.allow_squash_merge | Should -BeTrue
        $baseline.Actions.default_workflow_permissions | Should -Be 'read'
    }

    It "merges an override into the Ruleset section" {
        $baseline = Get-GitHubRepoBaseline -Override @{ Ruleset = @{ RequiredApprovingReviews = 1 } }
        $baseline.Ruleset.RequiredApprovingReviews | Should -Be 1
        $baseline.Ruleset.AdminCanBypass | Should -BeTrue
    }

    It "throws on an unknown baseline section" {
        { Get-GitHubRepoBaseline -Override @{ Nonsense = @{ a = 1 } } } |
            Should -Throw -ExpectedMessage "*Unknown baseline section*"
    }

    It "returns an independent copy on each call" {
        $first = Get-GitHubRepoBaseline
        $first.Settings.has_wiki = $true
        (Get-GitHubRepoBaseline).Settings.has_wiki | Should -BeFalse
    }
}

Describe "Get-GitHubRepoConfig" -Tag "Unit" {
    BeforeEach {
        Mock -ModuleName DotfilesHelpers Test-GitHubCliReady { }
        Mock -ModuleName DotfilesHelpers Get-GitHubCurrentOwner { 'DevSecNinja' }
    }

    Context "when a repository already matches the baseline" {
        BeforeEach {
            Mock -ModuleName DotfilesHelpers Get-GitHubRulesetList { script:New-RulesetListPresent }
            Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
                script:Get-MockApiResponse -Endpoint $Endpoint `
                    -Repo (script:New-CompliantRepoResponse) `
                    -Actions (script:New-CompliantActionsResponse) `
                    -RulesetDetail (script:New-CompliantRulesetDetail)
            }
        }

        It "reports it as compliant with no drift" {
            $result = Get-GitHubRepoConfig -Repository 'compliant'
            $result.IsCompliant | Should -BeTrue
            $result.DriftCount | Should -Be 0
        }

        It "qualifies the repository name with the default owner" {
            (Get-GitHubRepoConfig -Repository 'compliant').Repository | Should -Be 'DevSecNinja/compliant'
        }

        It "emits an object of the expected type" {
            $result = Get-GitHubRepoConfig -Repository 'compliant'
            $result.PSObject.TypeNames | Should -Contain 'Dotfiles.GitHubRepoConfig'
        }

        It "surfaces IsFork so results can be filtered after the fact" {
            (Get-GitHubRepoConfig -Repository 'compliant').PSObject.Properties.Name |
                Should -Contain 'IsFork'
        }

        It "reports a fork as IsFork" {
            Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
                $repo = script:New-CompliantRepoResponse
                $repo | Add-Member -NotePropertyName fork -NotePropertyValue $true -Force
                script:Get-MockApiResponse -Endpoint $Endpoint `
                    -Repo $repo `
                    -Actions (script:New-CompliantActionsResponse) `
                    -RulesetDetail (script:New-CompliantRulesetDetail)
            }

            (Get-GitHubRepoConfig -Repository 'compliant').IsFork | Should -BeTrue
        }

        It "reports a non-fork as not IsFork" {
            (Get-GitHubRepoConfig -Repository 'compliant').IsFork | Should -BeFalse
        }

        It "records the ruleset id so Set can update in place" {
            (Get-GitHubRepoConfig -Repository 'compliant').RulesetId | Should -Be 42
        }

        It "never issues a write request" {
            $null = Get-GitHubRepoConfig -Repository 'compliant'
            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubApi -Times 0 -Exactly -ParameterFilter {
                $Method -in @('POST', 'PATCH', 'PUT', 'DELETE')
            }
        }
    }

    Context "when a repository has drifted" {
        BeforeEach {
            Mock -ModuleName DotfilesHelpers Get-GitHubRulesetList { script:New-RulesetListEmpty }
            Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
                script:Get-MockApiResponse -Endpoint $Endpoint `
                    -Repo (script:New-DriftedRepoResponse) `
                    -Actions (script:New-CompliantActionsResponse) `
                    -RulesetDetail $null
            }
        }

        It "reports it as non-compliant" {
            (Get-GitHubRepoConfig -Repository 'drifted').IsCompliant | Should -BeFalse
        }

        It "identifies each drifted setting with its current and desired value" {
            $drift = @((Get-GitHubRepoConfig -Repository 'drifted').Drift)
            $rebase = @($drift | Where-Object { $_.Setting -eq 'allow_rebase_merge' })[0]
            $rebase.Current | Should -BeTrue
            $rebase.Desired | Should -BeFalse
            $rebase.Category | Should -Be 'Settings'
        }

        It "flags a missing ruleset" {
            $drift = @((Get-GitHubRepoConfig -Repository 'drifted').Drift)
            @($drift | Where-Object { $_.Setting -eq 'ruleset_present' }).Count | Should -Be 1
        }

        It "does not flag settings that already match" {
            $drift = @((Get-GitHubRepoConfig -Repository 'drifted').Drift)
            @($drift | Where-Object { $_.Setting -eq 'allow_squash_merge' }).Count | Should -Be 0
        }

        It "honours a baseline override" {
            $result = Get-GitHubRepoConfig -Repository 'drifted' -Baseline @{ Settings = @{ allow_rebase_merge = $true } }
            @($result.Drift | Where-Object { $_.Setting -eq 'allow_rebase_merge' }).Count | Should -Be 0
        }
    }

    Context "when the ruleset has lost the admin bypass" {
        BeforeEach {
            Mock -ModuleName DotfilesHelpers Get-GitHubRulesetList { script:New-RulesetListPresent }
            Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
                $detail = script:New-CompliantRulesetDetail
                $detail.bypass_actors = @()
                script:Get-MockApiResponse -Endpoint $Endpoint `
                    -Repo (script:New-CompliantRepoResponse) `
                    -Actions (script:New-CompliantActionsResponse) `
                    -RulesetDetail $detail
            }
        }

        It "flags the missing bypass so the owner does not get locked out" {
            $drift = @((Get-GitHubRepoConfig -Repository 'compliant').Drift)
            $bypass = @($drift | Where-Object { $_.Setting -eq 'ruleset_admin_bypass' })[0]
            $bypass | Should -Not -BeNullOrEmpty
            $bypass.Current | Should -BeFalse
            $bypass.Desired | Should -BeTrue
        }
    }

    Context "when the ruleset allows merge methods outside the baseline" {
        BeforeEach {
            Mock -ModuleName DotfilesHelpers Get-GitHubRulesetList { script:New-RulesetListPresent }
            Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
                $detail = script:New-CompliantRulesetDetail
                $detail.rules[2].parameters.allowed_merge_methods = @('merge', 'squash', 'rebase')
                script:Get-MockApiResponse -Endpoint $Endpoint `
                    -Repo (script:New-CompliantRepoResponse) `
                    -Actions (script:New-CompliantActionsResponse) `
                    -RulesetDetail $detail
            }
        }

        It "flags the merge methods as drifted" {
            $drift = @((Get-GitHubRepoConfig -Repository 'compliant').Drift)
            @($drift | Where-Object { $_.Setting -eq 'ruleset_allowed_merge_methods' }).Count | Should -Be 1
        }
    }

    Context "when Actions permissions cannot be read" {
        BeforeEach {
            Mock -ModuleName DotfilesHelpers Get-GitHubRulesetList { script:New-RulesetListPresent }
            Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
                script:Get-MockApiResponse -Endpoint $Endpoint `
                    -Repo (script:New-CompliantRepoResponse) `
                    -Actions $null `
                    -RulesetDetail (script:New-CompliantRulesetDetail)
            }
        }

        It "warns and skips the category instead of reporting false drift" {
            $warnings = @()
            $result = Get-GitHubRepoConfig -Repository 'compliant' -WarningVariable warnings -WarningAction SilentlyContinue
            $warnings.Count | Should -BeGreaterThan 0
            @($result.Drift | Where-Object { $_.Category -eq 'Actions' }).Count | Should -Be 0
        }
    }

    Context "when rulesets are unavailable on the plan" {
        BeforeEach {
            Mock -ModuleName DotfilesHelpers Get-GitHubRulesetList { script:New-RulesetListUnavailable }
            Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
                script:Get-MockApiResponse -Endpoint $Endpoint `
                    -Repo (script:New-CompliantRepoResponse) `
                    -Actions (script:New-CompliantActionsResponse) `
                    -RulesetDetail $null
            }
        }

        It "warns about the plan limitation rather than failing" {
            $warnings = @()
            $result = Get-GitHubRepoConfig -Repository 'private-repo' -WarningVariable warnings -WarningAction SilentlyContinue
            ($warnings -join ' ') | Should -Match 'GitHub Pro'
            $result.IsCompliant | Should -BeNullOrEmpty -Because 'the ruleset category could not be evaluated, so compliance is unknown'
        }
    }

    Context "category selection" {
        BeforeEach {
            Mock -ModuleName DotfilesHelpers Get-GitHubRulesetList { script:New-RulesetListEmpty }
            Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
                script:Get-MockApiResponse -Endpoint $Endpoint `
                    -Repo (script:New-DriftedRepoResponse) `
                    -Actions (script:New-CompliantActionsResponse) `
                    -RulesetDetail $null `
                    -Variables ([PSCustomObject]@{ variables = @() }) `
                    -Secrets ([PSCustomObject]@{ secrets = @() })
            }
        }

        It "checks only the requested categories" {
            $result = Get-GitHubRepoConfig -Repository 'drifted' -Check Settings
            @($result.Drift | Where-Object { $_.Category -ne 'Settings' }).Count | Should -Be 0
        }

        It "skips the rulesets endpoint when Ruleset is not requested" {
            $null = Get-GitHubRepoConfig -Repository 'drifted' -Check Settings
            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubApi -Times 0 -Exactly -ParameterFilter {
                $Endpoint -like '*/rulesets*'
            }
        }

        It "reports a missing App credential when AppCredential is requested" {
            $result = Get-GitHubRepoConfig -Repository 'drifted' -Check AppCredential
            $settings = @($result.Drift | ForEach-Object { $_.Setting })
            $settings | Should -Contain 'AUTOMATION_APP_ID'
            $settings | Should -Contain 'AUTOMATION_APP_PRIVATE_KEY'
        }

        It "does not report drift when a repository-level App credential is already present" {
            Mock -ModuleName DotfilesHelpers Get-GitHubRulesetList { script:New-RulesetListEmpty }
            Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
                script:Get-MockApiResponse -Endpoint $Endpoint `
                    -Repo (script:New-DriftedRepoResponse) `
                    -Actions (script:New-CompliantActionsResponse) `
                    -RulesetDetail $null `
                    -Variables ([PSCustomObject]@{ variables = @([PSCustomObject]@{ name = 'AUTOMATION_APP_ID' }) }) `
                    -Secrets ([PSCustomObject]@{ secrets = @([PSCustomObject]@{ name = 'AUTOMATION_APP_PRIVATE_KEY' }) })
            }

            $result = Get-GitHubRepoConfig -Repository 'drifted' -Check AppCredential -Baseline @{ AppCredential = @{ Environment = '' } }
            @($result.Drift | Where-Object { $_.Category -eq 'AppCredential' }).Count | Should -Be 0
        }

        It "reads repository-level endpoints when the baseline asks for no environment" {
            $null = Get-GitHubRepoConfig -Repository 'drifted' -Check AppCredential -Baseline @{ AppCredential = @{ Environment = '' } }

            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubApi -Times 1 -Exactly -ParameterFilter {
                $Endpoint -eq 'repos/DevSecNinja/drifted/actions/secrets'
            }
        }
    }

    Context "Cloudflare credentials" {
        BeforeEach {
            Mock -ModuleName DotfilesHelpers Get-GitHubRulesetList { script:New-RulesetListEmpty }
            Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
                script:Get-MockApiResponse -Endpoint $Endpoint `
                    -Repo (script:New-DriftedRepoResponse) `
                    -Actions (script:New-CompliantActionsResponse) `
                    -RulesetDetail $null `
                    -Variables ([PSCustomObject]@{ variables = @() }) `
                    -Secrets ([PSCustomObject]@{ secrets = @() })
            }
        }

        It "reports both secrets as drift when the repo uses the Pages workflow" {
            Mock -ModuleName DotfilesHelpers Test-GitHubPagesWorkflow { $true }

            $result = Get-GitHubRepoConfig -Repository 'drifted' -Check CloudflareCredential
            $settings = @($result.Drift | ForEach-Object { $_.Setting })
            $settings | Should -Contain 'CLOUDFLARE_ACCOUNT_ID'
            $settings | Should -Contain 'CLOUDFLARE_API_TOKEN'
        }

        It "reports no drift when the repo does not use the Pages workflow" {
            Mock -ModuleName DotfilesHelpers Test-GitHubPagesWorkflow { $false }

            $result = Get-GitHubRepoConfig -Repository 'drifted' -Check CloudflareCredential
            @($result.Drift | Where-Object { $_.Category -eq 'CloudflareCredential' }).Count | Should -Be 0
            $result.UsesPagesWorkflow | Should -BeFalse
        }

        It "does not even list secrets when the repo has no Pages workflow" {
            Mock -ModuleName DotfilesHelpers Test-GitHubPagesWorkflow { $false }

            $null = Get-GitHubRepoConfig -Repository 'drifted' -Check CloudflareCredential

            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubApi -Times 0 -Exactly -ParameterFilter {
                $Endpoint -like '*/actions/secrets'
            }
        }

        It "reports no drift when both secrets already exist" {
            Mock -ModuleName DotfilesHelpers Test-GitHubPagesWorkflow { $true }
            Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
                script:Get-MockApiResponse -Endpoint $Endpoint `
                    -Repo (script:New-DriftedRepoResponse) `
                    -Actions (script:New-CompliantActionsResponse) `
                    -RulesetDetail $null `
                    -Secrets ([PSCustomObject]@{ secrets = @(
                            [PSCustomObject]@{ name = 'CLOUDFLARE_ACCOUNT_ID' }
                            [PSCustomObject]@{ name = 'CLOUDFLARE_API_TOKEN' }
                        )
                    })
            }

            $result = Get-GitHubRepoConfig -Repository 'drifted' -Check CloudflareCredential
            @($result.Drift | Where-Object { $_.Category -eq 'CloudflareCredential' }).Count | Should -Be 0
        }

        It "writes both secrets at repository scope, never with --env" {
            Mock -ModuleName DotfilesHelpers Test-GitHubPagesWorkflow { $true }
            Mock -ModuleName DotfilesHelpers Invoke-GitHubCli { 'ok' }

            $cf = [PSCustomObject]@{
                PSTypeName = 'Dotfiles.CloudflareCredential'
                AccountId  = (ConvertTo-SecureString '0123456789abcdef0123456789abcdef' -AsPlainText -Force)
                ApiToken   = (ConvertTo-SecureString 'cf-token' -AsPlainText -Force)
            }

            Get-GitHubRepoConfig -Repository 'drifted' -Check CloudflareCredential |
                Set-GitHubRepoConfig -CloudflareCredential $cf -Confirm:$false

            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubCli -Times 2 -Exactly -ParameterFilter {
                $Arguments -contains 'secret' -and $Arguments -notcontains '--env'
            }
        }

        It "pipes secret values on stdin rather than as arguments" {
            Mock -ModuleName DotfilesHelpers Test-GitHubPagesWorkflow { $true }
            Mock -ModuleName DotfilesHelpers Invoke-GitHubCli { 'ok' }

            $cf = [PSCustomObject]@{
                PSTypeName = 'Dotfiles.CloudflareCredential'
                AccountId  = (ConvertTo-SecureString '0123456789abcdef0123456789abcdef' -AsPlainText -Force)
                ApiToken   = (ConvertTo-SecureString 'cf-token' -AsPlainText -Force)
            }

            Get-GitHubRepoConfig -Repository 'drifted' -Check CloudflareCredential |
                Set-GitHubRepoConfig -CloudflareCredential $cf -Confirm:$false

            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubCli -Times 1 -Exactly -ParameterFilter {
                $Arguments -contains 'CLOUDFLARE_API_TOKEN' -and $StdIn -eq 'cf-token' -and
                ($Arguments -join ' ') -notmatch 'cf-token'
            }
        }

        It "warns and skips when no credential is supplied" {
            Mock -ModuleName DotfilesHelpers Test-GitHubPagesWorkflow { $true }
            Mock -ModuleName DotfilesHelpers Invoke-GitHubCli { 'ok' }

            $warnings = @()
            Get-GitHubRepoConfig -Repository 'drifted' -Check CloudflareCredential |
                Set-GitHubRepoConfig -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue

            ($warnings -join ' ') | Should -Match 'Get-CloudflareCredential'
            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubCli -Times 0 -Exactly -ParameterFilter {
                $Arguments -contains 'secret'
            }
        }

        It "writes nothing under -WhatIf" {
            Mock -ModuleName DotfilesHelpers Test-GitHubPagesWorkflow { $true }
            Mock -ModuleName DotfilesHelpers Invoke-GitHubCli { 'ok' }

            $cf = [PSCustomObject]@{
                PSTypeName = 'Dotfiles.CloudflareCredential'
                AccountId  = (ConvertTo-SecureString '0123456789abcdef0123456789abcdef' -AsPlainText -Force)
                ApiToken   = (ConvertTo-SecureString 'cf-token' -AsPlainText -Force)
            }

            Get-GitHubRepoConfig -Repository 'drifted' -Check CloudflareCredential |
                Set-GitHubRepoConfig -CloudflareCredential $cf -WhatIf

            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubCli -Times 0 -Exactly -ParameterFilter {
                $Arguments -contains 'secret'
            }
        }
    }

    Context "bulk enumeration" {
        BeforeEach {
            Mock -ModuleName DotfilesHelpers Invoke-GitHubCli {
                @(
                    @{ nameWithOwner = 'DevSecNinja/one'; isArchived = $false; isFork = $false }
                    @{ nameWithOwner = 'DevSecNinja/two'; isArchived = $false; isFork = $false }
                    @{ nameWithOwner = 'DevSecNinja/forked'; isArchived = $false; isFork = $true }
                    @{ nameWithOwner = 'DevSecNinja/old'; isArchived = $true; isFork = $false }
                    @{ nameWithOwner = 'DevSecNinja/oldfork'; isArchived = $true; isFork = $true }
                ) | ConvertTo-Json -Compress
            } -ParameterFilter { $Arguments -contains 'list' }

            Mock -ModuleName DotfilesHelpers Get-GitHubRulesetList { script:New-RulesetListPresent }
            Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
                script:Get-MockApiResponse -Endpoint $Endpoint `
                    -Repo (script:New-CompliantRepoResponse) `
                    -Actions (script:New-CompliantActionsResponse) `
                    -RulesetDetail (script:New-CompliantRulesetDetail)
            }
        }

        It "excludes archived repositories by default" {
            $result = @(Get-GitHubRepoConfig -All)
            @($result | ForEach-Object { $_.Repository }) | Should -Not -Contain 'DevSecNinja/old'
        }

        It "includes archived repositories with -IncludeArchived" {
            @(Get-GitHubRepoConfig -All -IncludeArchived).Count | Should -Be 5
        }

        It "includes forks by default, since a fork you maintain still wants the baseline" {
            $result = @(Get-GitHubRepoConfig -All)
            $result.Count | Should -Be 3
            @($result | ForEach-Object { $_.Repository }) | Should -Contain 'DevSecNinja/forked'
        }

        It "excludes forks with -ExcludeForks" {
            $result = @(Get-GitHubRepoConfig -All -ExcludeForks)
            $result.Count | Should -Be 2
            @($result | ForEach-Object { $_.Repository }) | Should -Not -Contain 'DevSecNinja/forked'
        }

        It "applies -ExcludeForks and the archived filter together" {
            $result = @(Get-GitHubRepoConfig -All -ExcludeForks -IncludeArchived)
            $names = @($result | ForEach-Object { $_.Repository })
            $names | Should -Contain 'DevSecNinja/old'
            $names | Should -Not -Contain 'DevSecNinja/forked'
            $names | Should -Not -Contain 'DevSecNinja/oldfork'
        }

        It "asks gh for the isFork field" {
            $null = Get-GitHubRepoConfig -All

            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubCli -Times 1 -Exactly -ParameterFilter {
                $Arguments -contains 'list' -and ($Arguments -join ' ') -match 'isFork'
            }
        }

        It "rejects -ExcludeForks outside the -All parameter set" {
            { Get-GitHubRepoConfig -Repository 'one' -ExcludeForks -ErrorAction Stop } | Should -Throw
        }

        It "accepts several repositories from the pipeline" {
            $result = @('one', 'two' | Get-GitHubRepoConfig)
            $result.Count | Should -Be 2
        }
    }
}

Describe "Set-GitHubRepoConfig" -Tag "Unit" {
    BeforeEach {
        Mock -ModuleName DotfilesHelpers Test-GitHubCliReady { }
        Mock -ModuleName DotfilesHelpers Get-GitHubCurrentOwner { 'DevSecNinja' }
        Mock -ModuleName DotfilesHelpers Get-GitHubRulesetList { script:New-RulesetListEmpty }
        Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
            script:Get-MockApiResponse -Endpoint $Endpoint `
                -Repo (script:New-DriftedRepoResponse) `
                -Actions (script:New-CompliantActionsResponse) `
                -RulesetDetail $null `
                -Variables ([PSCustomObject]@{ variables = @() }) `
                -Secrets ([PSCustomObject]@{ secrets = @() })
        }
        Mock -ModuleName DotfilesHelpers Invoke-GitHubCli { 'ok' }
    }

    Context "dry runs" {
        It "sends no write request under -WhatIf" {
            Get-GitHubRepoConfig -Repository 'drifted' -Check Settings |
                Set-GitHubRepoConfig -WhatIf

            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubApi -Times 0 -Exactly -ParameterFilter {
                $Method -in @('POST', 'PATCH', 'PUT', 'DELETE')
            }
        }

        It "creates no ruleset under -WhatIf" {
            Get-GitHubRepoConfig -Repository 'drifted' -Check Ruleset |
                Set-GitHubRepoConfig -WhatIf

            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubApi -Times 0 -Exactly -ParameterFilter {
                $Endpoint -like '*/rulesets'
            }
        }

        It "writes no secret under -WhatIf" {
            $cred = [PSCustomObject]@{
                PSTypeName = 'Dotfiles.GitHubAppCredential'
                AppId      = '123'
                PrivateKey = (ConvertTo-SecureString 'pem' -AsPlainText -Force)
            }

            Get-GitHubRepoConfig -Repository 'drifted' -Check AppCredential |
                Set-GitHubRepoConfig -AppCredential $cred -WhatIf

            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubCli -Times 0 -Exactly -ParameterFilter {
                $Arguments -contains 'secret'
            }
        }
    }

    Context "applying settings" {
        It "PATCHes the repository once with every drifted field" {
            Get-GitHubRepoConfig -Repository 'drifted' -Check Settings |
                Set-GitHubRepoConfig -Confirm:$false

            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubApi -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'repos/DevSecNinja/drifted'
            }
        }

        It "sends the desired values in the request body" {
            Get-GitHubRepoConfig -Repository 'drifted' -Check Settings |
                Set-GitHubRepoConfig -Confirm:$false

            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubApi -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and
                $Body['allow_rebase_merge'] -eq $false -and
                $Body['allow_merge_commit'] -eq $false -and
                $Body['delete_branch_on_merge'] -eq $true
            }
        }

        It "does not send fields that already match" {
            Get-GitHubRepoConfig -Repository 'drifted' -Check Settings |
                Set-GitHubRepoConfig -Confirm:$false

            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubApi -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and -not $Body.ContainsKey('allow_squash_merge')
            }
        }

        It "writes nothing for an already-compliant repository" {
            Mock -ModuleName DotfilesHelpers Get-GitHubRulesetList { script:New-RulesetListPresent }
            Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
                script:Get-MockApiResponse -Endpoint $Endpoint `
                    -Repo (script:New-CompliantRepoResponse) `
                    -Actions (script:New-CompliantActionsResponse) `
                    -RulesetDetail (script:New-CompliantRulesetDetail)
            }

            Get-GitHubRepoConfig -Repository 'compliant' | Set-GitHubRepoConfig -Confirm:$false

            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubApi -Times 0 -Exactly -ParameterFilter {
                $Method -in @('POST', 'PATCH', 'PUT', 'DELETE')
            }
        }
    }

    Context "applying rulesets" {
        It "POSTs a new ruleset when none exists" {
            Get-GitHubRepoConfig -Repository 'drifted' -Check Ruleset |
                Set-GitHubRepoConfig -Confirm:$false

            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubApi -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Endpoint -eq 'repos/DevSecNinja/drifted/rulesets'
            }
        }

        It "includes the admin bypass actor in the created ruleset" {
            Get-GitHubRepoConfig -Repository 'drifted' -Check Ruleset |
                Set-GitHubRepoConfig -Confirm:$false

            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubApi -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and
                @($Body['bypass_actors'] | Where-Object { $_.actor_type -eq 'RepositoryRole' -and $_.actor_id -eq 5 }).Count -eq 1
            }
        }

        It "PUTs an existing ruleset in place rather than creating a duplicate" {
            Mock -ModuleName DotfilesHelpers Get-GitHubRulesetList { script:New-RulesetListPresent }
            Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
                $detail = script:New-CompliantRulesetDetail
                $detail.enforcement = 'disabled'
                script:Get-MockApiResponse -Endpoint $Endpoint `
                    -Repo (script:New-CompliantRepoResponse) `
                    -Actions (script:New-CompliantActionsResponse) `
                    -RulesetDetail $detail
            }

            Get-GitHubRepoConfig -Repository 'compliant' -Check Ruleset |
                Set-GitHubRepoConfig -Confirm:$false

            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubApi -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PUT' -and $Endpoint -eq 'repos/DevSecNinja/compliant/rulesets/42'
            }
            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubApi -Times 0 -Exactly -ParameterFilter {
                $Method -eq 'POST'
            }
        }
    }

    Context "applying the App credential" {
        BeforeEach {
            $script:Credential = [PSCustomObject]@{
                PSTypeName = 'Dotfiles.GitHubAppCredential'
                AppId      = '123456'
                PrivateKey = (ConvertTo-SecureString "-----BEGIN RSA PRIVATE KEY-----`nX`n-----END RSA PRIVATE KEY-----" -AsPlainText -Force)
            }

            # Public repo with no environment yet: the environment and its
            # branch policy are created, then the credential is stored in it.
            Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
                script:Get-MockApiResponse -Endpoint $Endpoint `
                    -Repo (script:New-DriftedRepoResponse) `
                    -Actions (script:New-CompliantActionsResponse) `
                    -RulesetDetail $null `
                    -Variables ([PSCustomObject]@{ variables = @() }) `
                    -Secrets ([PSCustomObject]@{ secrets = @() }) `
                    -EnvironmentDetail $null `
                    -BranchPolicies ([PSCustomObject]@{ branch_policies = @([PSCustomObject]@{ name = 'main' }) })
            }
        }

        It "creates the environment before storing anything in it" {
            Get-GitHubRepoConfig -Repository 'drifted' -Check AppCredential |
                Set-GitHubRepoConfig -AppCredential $script:Credential -Confirm:$false

            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubApi -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PUT' -and $Endpoint -eq 'repos/DevSecNinja/drifted/environments/production' -and
                $Body['deployment_branch_policy'].custom_branch_policies -eq $true
            }
        }

        It "pins the environment to the default branch" {
            Get-GitHubRepoConfig -Repository 'drifted' -Check AppCredential |
                Set-GitHubRepoConfig -AppCredential $script:Credential -Confirm:$false

            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubApi -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and
                $Endpoint -eq 'repos/DevSecNinja/drifted/environments/production/deployment-branch-policies' -and
                $Body['name'] -eq 'main' -and $Body['type'] -eq 'branch'
            }
        }

        It "scopes the secret to the environment with --env" {
            Get-GitHubRepoConfig -Repository 'drifted' -Check AppCredential |
                Set-GitHubRepoConfig -AppCredential $script:Credential -Confirm:$false

            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubCli -Times 1 -Exactly -ParameterFilter {
                $Arguments -contains 'secret' -and $Arguments -contains '--env' -and $Arguments -contains 'production'
            }
        }

        It "scopes the variable to the environment with --env" {
            Get-GitHubRepoConfig -Repository 'drifted' -Check AppCredential |
                Set-GitHubRepoConfig -AppCredential $script:Credential -Confirm:$false

            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubCli -Times 1 -Exactly -ParameterFilter {
                $Arguments -contains 'variable' -and $Arguments -contains '--env' -and $Arguments -contains 'production'
            }
        }

        It "falls back to repository scope on a private repository" {
            Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
                $repo = script:New-DriftedRepoResponse
                $repo.visibility = 'private'
                script:Get-MockApiResponse -Endpoint $Endpoint `
                    -Repo $repo `
                    -Actions (script:New-CompliantActionsResponse) `
                    -RulesetDetail $null `
                    -Variables ([PSCustomObject]@{ variables = @() }) `
                    -Secrets ([PSCustomObject]@{ secrets = @() })
            }

            Get-GitHubRepoConfig -Repository 'drifted' -Check AppCredential -WarningAction SilentlyContinue |
                Set-GitHubRepoConfig -AppCredential $script:Credential -Confirm:$false

            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubCli -Times 0 -Exactly -ParameterFilter {
                $Arguments -contains '--env'
            }
            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubApi -Times 0 -Exactly -ParameterFilter {
                $Endpoint -like '*/environments/*' -and $Method -ne 'GET'
            }
        }

        It "warns that a private repository cannot use an environment" {
            Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
                $repo = script:New-DriftedRepoResponse
                $repo.visibility = 'private'
                script:Get-MockApiResponse -Endpoint $Endpoint `
                    -Repo $repo `
                    -Actions (script:New-CompliantActionsResponse) `
                    -RulesetDetail $null `
                    -Variables ([PSCustomObject]@{ variables = @() }) `
                    -Secrets ([PSCustomObject]@{ secrets = @() })
            }

            $warnings = @()
            $null = Get-GitHubRepoConfig -Repository 'drifted' -Check AppCredential -WarningVariable warnings -WarningAction SilentlyContinue
            ($warnings -join ' ') | Should -Match 'Free plan'
        }

        It "sets the App ID as an Actions variable" {
            Get-GitHubRepoConfig -Repository 'drifted' -Check AppCredential |
                Set-GitHubRepoConfig -AppCredential $script:Credential -Confirm:$false

            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubCli -Times 1 -Exactly -ParameterFilter {
                $Arguments -contains 'variable' -and $Arguments -contains 'AUTOMATION_APP_ID'
            }
        }

        It "pipes the private key on stdin instead of as an argument" {
            Get-GitHubRepoConfig -Repository 'drifted' -Check AppCredential |
                Set-GitHubRepoConfig -AppCredential $script:Credential -Confirm:$false

            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubCli -Times 1 -Exactly -ParameterFilter {
                $Arguments -contains 'secret' -and
                $StdIn -match 'BEGIN RSA PRIVATE KEY' -and
                ($Arguments -join ' ') -notmatch 'PRIVATE KEY'
            }
        }

        It "warns and skips when no credential is supplied" {
            $warnings = @()
            Get-GitHubRepoConfig -Repository 'drifted' -Check AppCredential |
                Set-GitHubRepoConfig -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue

            ($warnings -join ' ') | Should -Match 'Get-GitHubAppCredential'
            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubCli -Times 0 -Exactly -ParameterFilter {
                $Arguments -contains 'secret'
            }
        }
    }

    Context "category filtering" {
        It "applies only the requested category" {
            Get-GitHubRepoConfig -Repository 'drifted' -Check Settings, Ruleset |
                Set-GitHubRepoConfig -Category Settings -Confirm:$false

            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubApi -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH'
            }
            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubApi -Times 0 -Exactly -ParameterFilter {
                $Method -eq 'POST'
            }
        }
    }

    Context "safety and reporting" {
        It "skips archived repositories" {
            Mock -ModuleName DotfilesHelpers Get-GitHubRulesetList { script:New-RulesetListEmpty }
            Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
                $repo = script:New-DriftedRepoResponse
                $repo.archived = $true
                script:Get-MockApiResponse -Endpoint $Endpoint `
                    -Repo $repo `
                    -Actions (script:New-CompliantActionsResponse) `
                    -RulesetDetail $null
            }

            $warnings = @()
            Get-GitHubRepoConfig -Repository 'old' -Check Settings |
                Set-GitHubRepoConfig -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue

            ($warnings -join ' ') | Should -Match 'archived'
            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubApi -Times 0 -Exactly -ParameterFilter {
                $Method -eq 'PATCH'
            }
        }

        It "reports what it applied with -PassThru" {
            $result = Get-GitHubRepoConfig -Repository 'drifted' -Check Settings |
                Set-GitHubRepoConfig -Confirm:$false -PassThru

            $result.Repository | Should -Be 'DevSecNinja/drifted'
            $result.Applied | Should -Contain 'Settings/allow_rebase_merge'
        }

        It "emits nothing without -PassThru" {
            $result = Get-GitHubRepoConfig -Repository 'drifted' -Check Settings |
                Set-GitHubRepoConfig -Confirm:$false
            $result | Should -BeNullOrEmpty
        }

        It "processes every repository piped to it" {
            $result = @(Get-GitHubRepoConfig -Repository 'one', 'two' -Check Settings |
                    Set-GitHubRepoConfig -Confirm:$false -PassThru)
            $result.Count | Should -Be 2
        }

        It "declares SupportsShouldProcess so -WhatIf is available" {
            (Get-Command Set-GitHubRepoConfig).Parameters.Keys | Should -Contain 'WhatIf'
        }

        It "rejects pipeline input that is not a repo config object" {
            { [PSCustomObject]@{ Repository = 'x' } | Set-GitHubRepoConfig -Confirm:$false -ErrorAction Stop } |
                Should -Throw
        }
    }
}

Describe "Skipped check reporting" -Tag "Unit" {
    BeforeEach {
        Mock -ModuleName DotfilesHelpers Test-GitHubCliReady { }
        Mock -ModuleName DotfilesHelpers Get-GitHubCurrentOwner { 'DevSecNinja' }
    }

    It "records Actions when workflow permissions cannot be read" {
        Mock -ModuleName DotfilesHelpers Get-GitHubRulesetList { script:New-RulesetListPresent }
        Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
            script:Get-MockApiResponse -Endpoint $Endpoint `
                -Repo (script:New-CompliantRepoResponse) `
                -Actions $null `
                -RulesetDetail (script:New-CompliantRulesetDetail)
        }

        $result = Get-GitHubRepoConfig -Repository 'compliant' -WarningAction SilentlyContinue
        $result.SkippedChecks | Should -Contain 'Actions'
    }

    It "records Ruleset when rulesets are unavailable on the plan" {
        Mock -ModuleName DotfilesHelpers Get-GitHubRulesetList { script:New-RulesetListUnavailable }
        Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
            script:Get-MockApiResponse -Endpoint $Endpoint `
                -Repo (script:New-CompliantRepoResponse) `
                -Actions (script:New-CompliantActionsResponse) `
                -RulesetDetail $null
        }

        $result = Get-GitHubRepoConfig -Repository 'private-repo' -WarningAction SilentlyContinue
        $result.SkippedChecks | Should -Contain 'Ruleset'
    }

    It "records CloudflareCredential when secrets cannot be listed" {
        Mock -ModuleName DotfilesHelpers Test-GitHubPagesWorkflow { $true }
        Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
            script:Get-MockApiResponse -Endpoint $Endpoint `
                -Repo (script:New-CompliantRepoResponse) `
                -Actions (script:New-CompliantActionsResponse) `
                -RulesetDetail $null `
                -Secrets $null
        }

        $result = Get-GitHubRepoConfig -Repository 'compliant' -Check CloudflareCredential -WarningAction SilentlyContinue
        $result.SkippedChecks | Should -Contain 'CloudflareCredential'
        $result.DriftCount | Should -Be 0
    }

    It "reports no skipped checks when everything is readable" {
        Mock -ModuleName DotfilesHelpers Get-GitHubRulesetList { script:New-RulesetListPresent }
        Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
            script:Get-MockApiResponse -Endpoint $Endpoint `
                -Repo (script:New-CompliantRepoResponse) `
                -Actions (script:New-CompliantActionsResponse) `
                -RulesetDetail (script:New-CompliantRulesetDetail)
        }

        $result = Get-GitHubRepoConfig -Repository 'compliant'
        @($result.SkippedChecks).Count | Should -Be 0
        $result.IsCompliant | Should -BeTrue
    }

    It "does not let a skipped category masquerade as compliance" {
        Mock -ModuleName DotfilesHelpers Test-GitHubPagesWorkflow { $true }
        Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
            script:Get-MockApiResponse -Endpoint $Endpoint `
                -Repo (script:New-CompliantRepoResponse) `
                -Actions (script:New-CompliantActionsResponse) `
                -RulesetDetail $null `
                -Secrets $null
        }

        $result = Get-GitHubRepoConfig -Repository 'compliant' -Check CloudflareCredential -WarningAction SilentlyContinue

        # Nothing could be checked, so compliance is unknown ($null) rather
        # than a clean bill.
        $null -eq $result.IsCompliant | Should -BeTrue
        -not $result.IsCompliant | Should -BeTrue -Because 'a skipped check must not read as compliant'
        @($result.SkippedChecks).Count | Should -BeGreaterThan 0
    }
}

Describe "Rubber-duck regressions" -Tag "Unit" {
    Context "pull_request parameters the baseline does not own" {
        It "preserves require_code_owner_review when remediating merge methods" {
            InModuleScope DotfilesHelpers {
                $existing = [PSCustomObject]@{
                    rules = @(
                        [PSCustomObject]@{
                            type       = 'pull_request'
                            parameters = [PSCustomObject]@{
                                allowed_merge_methods             = @('merge', 'squash', 'rebase')
                                required_approving_review_count   = 0
                                require_code_owner_review         = $true
                                dismiss_stale_reviews_on_push     = $true
                                require_last_push_approval        = $true
                                required_review_thread_resolution = $true
                            }
                        }
                    )
                }

                $payload = New-GitHubRulesetPayload -Ruleset (Get-GitHubRepoBaseline).Ruleset -ExistingRuleset $existing
                $pr = @($payload.rules | Where-Object { $_.type -eq 'pull_request' })[0]

                $pr.parameters['require_code_owner_review'] | Should -BeTrue
                $pr.parameters['dismiss_stale_reviews_on_push'] | Should -BeTrue
                $pr.parameters['require_last_push_approval'] | Should -BeTrue
                $pr.parameters['required_review_thread_resolution'] | Should -BeTrue
                # ...while the two the baseline owns are still applied.
                $pr.parameters['allowed_merge_methods'] | Should -Be @('squash')
            }
        }

        It "carries over a parameter the baseline has never heard of" {
            InModuleScope DotfilesHelpers {
                $existing = [PSCustomObject]@{
                    rules = @(
                        [PSCustomObject]@{
                            type       = 'pull_request'
                            parameters = [PSCustomObject]@{
                                allowed_merge_methods       = @('merge')
                                some_future_github_setting  = 'keep-me'
                            }
                        }
                    )
                }

                $payload = New-GitHubRulesetPayload -Ruleset (Get-GitHubRepoBaseline).Ruleset -ExistingRuleset $existing
                $pr = @($payload.rules | Where-Object { $_.type -eq 'pull_request' })[0]
                $pr.parameters['some_future_github_setting'] | Should -Be 'keep-me'
            }
        }

        It "falls back to GitHub defaults when there is no existing rule" {
            InModuleScope DotfilesHelpers {
                $payload = New-GitHubRulesetPayload -Ruleset (Get-GitHubRepoBaseline).Ruleset
                $pr = @($payload.rules | Where-Object { $_.type -eq 'pull_request' })[0]
                $pr.parameters['require_code_owner_review'] | Should -BeFalse
                $pr.parameters['required_approving_review_count'] | Should -Be 0
            }
        }
    }

    Context "ruleset identity" {
        It "ignores a tag ruleset that shares the baseline name" {
            InModuleScope DotfilesHelpers {
                $list = [PSCustomObject]@{
                    Available = $true
                    Rulesets  = @([PSCustomObject]@{ id = 9; name = 'Default'; target = 'tag'; source_type = 'Repository' })
                }
                @($list.Rulesets | Where-Object {
                        $_.name -eq 'Default' -and $_.target -eq 'branch' -and
                        ($null -eq $_.source_type -or $_.source_type -eq 'Repository')
                    }).Count | Should -Be 0
            }
        }

        It "ignores an organisation-inherited ruleset that shares the name" {
            InModuleScope DotfilesHelpers {
                $rulesets = @([PSCustomObject]@{ id = 9; name = 'Default'; target = 'branch'; source_type = 'Organization' })
                @($rulesets | Where-Object {
                        $_.name -eq 'Default' -and $_.target -eq 'branch' -and
                        ($null -eq $_.source_type -or $_.source_type -eq 'Repository')
                    }).Count | Should -Be 0
            }
        }

        It "adds the default branch to a condition that does not cover it" {
            InModuleScope DotfilesHelpers {
                $existing = [PSCustomObject]@{
                    rules      = @()
                    conditions = [PSCustomObject]@{
                        ref_name = [PSCustomObject]@{ include = @('refs/heads/release/*'); exclude = @() }
                    }
                }

                $payload = New-GitHubRulesetPayload -Ruleset (Get-GitHubRepoBaseline).Ruleset -ExistingRuleset $existing
                $payload.conditions.ref_name.include | Should -Contain '~DEFAULT_BRANCH'
                $payload.conditions.ref_name.include | Should -Contain 'refs/heads/release/*'
            }
        }

        It "leaves a condition that already covers the default branch alone" {
            InModuleScope DotfilesHelpers {
                $existing = [PSCustomObject]@{
                    rules      = @()
                    conditions = [PSCustomObject]@{
                        ref_name = [PSCustomObject]@{ include = @('~ALL'); exclude = @() }
                    }
                }

                $payload = New-GitHubRulesetPayload -Ruleset (Get-GitHubRepoBaseline).Ruleset -ExistingRuleset $existing
                @($payload.conditions.ref_name.include).Count | Should -Be 1
                $payload.conditions.ref_name.include | Should -Contain '~ALL'
            }
        }
    }

    Context "environment pinning" {
        It "does not call an environment pinned when a broader policy also exists" {
            InModuleScope DotfilesHelpers {
                Mock Invoke-GitHubApi {
                    if ($Endpoint -like '*deployment-branch-policies*') {
                        return [PSCustomObject]@{ branch_policies = @(
                                [PSCustomObject]@{ id = 1; name = 'main' }
                                [PSCustomObject]@{ id = 2; name = 'feature/*' }
                            )
                        }
                    }
                    return [PSCustomObject]@{ name = 'production'; deployment_branch_policy = [PSCustomObject]@{ custom_branch_policies = $true } }
                }

                $state = Get-GitHubEnvironmentState -Repository 'o/r' -Environment 'production' -DefaultBranch 'main'
                $state.PinnedToDefaultBranch | Should -BeFalse
                @($state.ExtraBranchPolicies).Count | Should -Be 1
                $state.ExtraBranchPolicies[0].name | Should -Be 'feature/*'
            }
        }

        It "calls it pinned when only the default branch is allowed" {
            InModuleScope DotfilesHelpers {
                Mock Invoke-GitHubApi {
                    if ($Endpoint -like '*deployment-branch-policies*') {
                        return [PSCustomObject]@{ branch_policies = @([PSCustomObject]@{ id = 1; name = 'main' }) }
                    }
                    return [PSCustomObject]@{ name = 'production'; deployment_branch_policy = [PSCustomObject]@{ custom_branch_policies = $true } }
                }

                $state = Get-GitHubEnvironmentState -Repository 'o/r' -Environment 'production' -DefaultBranch 'main'
                $state.PinnedToDefaultBranch | Should -BeTrue
                @($state.ExtraBranchPolicies).Count | Should -Be 0
            }
        }
    }
}

Describe "External command containment" -Tag "Unit" {
    BeforeAll {
        # Covers the whole GitHub tooling surface, not one file, so moving a
        # function between files cannot quietly drop it from this check.
        $script:ToolingFiles = @(
            'GitHubApi.ps1'
            'GitHubCredentialPlacement.ps1'
            'GitHubRepoConfig.ps1'
            'GitHubRuleset.ps1'
            'OnePasswordCredential.ps1'
        ) | ForEach-Object {
            Join-Path $script:RepoRoot "home/dot_config/powershell/modules/DotfilesHelpers/Public/$_"
        }

        # Returns "FunctionName" for every invocation of $Command in $Path, so a
        # violation names the offender instead of moving a magic number.
        function script:Get-CommandCallSite {
            param([string]$Path, [string]$Command)

            $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
            $calls = $ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq $Command
                }, $true)

            $calls | ForEach-Object {
                $parent = $_.Parent
                while ($null -ne $parent -and -not ($parent -is [System.Management.Automation.Language.FunctionDefinitionAst])) {
                    $parent = $parent.Parent
                }
                if ($null -eq $parent) { '<file scope>' } else { $parent.Name }
            }
        }
    }

    It "invokes gh only from the wrapper and the pre-flight check" {
        # Everything else must go through Invoke-GitHubCli, so mocking that one
        # function is enough to keep the suite off the network.
        $allowed = @('Invoke-GitHubCli', 'Test-GitHubCliReady')
        $offenders = @()
        foreach ($file in $script:ToolingFiles) {
            foreach ($fn in (script:Get-CommandCallSite -Path $file -Command 'gh')) {
                if ($fn -notin $allowed) { $offenders += "$(Split-Path $file -Leaf):$fn" }
            }
        }
        $offenders | Should -BeNullOrEmpty -Because "gh must only be invoked from $($allowed -join ' or ')"
    }

    It "invokes op only from the wrapper" {
        $offenders = @()
        foreach ($file in $script:ToolingFiles) {
            foreach ($fn in (script:Get-CommandCallSite -Path $file -Command 'op')) {
                if ($fn -ne 'Invoke-OnePasswordCli') { $offenders += "$(Split-Path $file -Leaf):$fn" }
            }
        }
        $offenders | Should -BeNullOrEmpty -Because 'op must only be invoked from Invoke-OnePasswordCli'
    }

    It "actually finds the known call sites" {
        # Guards the guard: if the AST walk silently matched nothing, the two
        # tests above would pass no matter what the source did.
        $ghFile = Join-Path $script:RepoRoot 'home/dot_config/powershell/modules/DotfilesHelpers/Public/GitHubApi.ps1'
        @(script:Get-CommandCallSite -Path $ghFile -Command 'gh').Count | Should -BeGreaterThan 0
    }

    It "hardcodes no GitHub token in <_>" -ForEach @(
        'GitHubApi.ps1'
        'GitHubCredentialPlacement.ps1'
        'GitHubRepoConfig.ps1'
        'GitHubRuleset.ps1'
        'OnePasswordCredential.ps1'
    ) {
        $path = Join-Path $script:RepoRoot "home/dot_config/powershell/modules/DotfilesHelpers/Public/$_"
        Get-Content $path -Raw | Should -Not -Match 'gh[pousr]_[A-Za-z0-9]{16,}'
    }
}
