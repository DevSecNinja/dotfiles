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

    # Set-GitHubRepoConfig logs to the information stream by default; keep the
    # test output quiet. Tests that assert on the log use -InformationVariable.
    $global:PSDefaultParameterValues['Set-GitHubRepoConfig:InformationAction'] = 'SilentlyContinue'

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
            name          = 'steward-default-branch'
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
                [PSCustomObject]@{ type = 'required_linear_history' }
                [PSCustomObject]@{ type = 'required_signatures' }
            )
        }
    }

    # Canned ruleset-list responses for the Get-GitHubRulesetList seam.
    function script:New-RulesetListPresent {
        return [PSCustomObject]@{
            Available = $true
            Rulesets  = @([PSCustomObject]@{ id = 42; name = 'steward-default-branch'; target = 'branch'; source_type = 'Repository' })
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

AfterAll {
    $global:PSDefaultParameterValues.Remove('Set-GitHubRepoConfig:InformationAction')
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

    It "manages repo-steward's steward-default-branch ruleset rather than a competing one" {
        (Get-GitHubRepoBaseline).Ruleset.Name | Should -Be 'steward-default-branch'
    }

    It "merges an override into a single section without discarding the rest" {
        $baseline = Get-GitHubRepoBaseline -Override @{ Settings = @{ has_wiki = $true } }
        $baseline.Settings.has_wiki | Should -BeTrue
        $baseline.Settings.allow_squash_merge | Should -BeTrue
        $baseline.Actions.default_workflow_permissions | Should -Be 'read'
    }

    It "merges an override into the Ruleset section" {
        $baseline = Get-GitHubRepoBaseline -Override @{ Ruleset = @{ Rules = @('deletion') } }
        $baseline.Ruleset.Rules | Should -Be @('deletion')
        $baseline.Ruleset.ForkRules | Should -Be @('deletion', 'non_fast_forward')
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

    Context "when the ruleset is missing a steward rule" {
        BeforeEach {
            Mock -ModuleName DotfilesHelpers Get-GitHubRulesetList { script:New-RulesetListPresent }
            Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
                $detail = script:New-CompliantRulesetDetail
                $detail.rules = @($detail.rules | Where-Object { $_.type -ne 'required_signatures' }) + @(
                    [PSCustomObject]@{ type = 'pull_request'; parameters = [PSCustomObject]@{ allowed_merge_methods = @('merge') } }
                )
                script:Get-MockApiResponse -Endpoint $Endpoint `
                    -Repo (script:New-CompliantRepoResponse) `
                    -Actions (script:New-CompliantActionsResponse) `
                    -RulesetDetail $detail
            }
        }

        It "flags the missing rule" {
            $drift = @((Get-GitHubRepoConfig -Repository 'compliant').Drift)
            $missing = @($drift | Where-Object { $_.Setting -eq 'ruleset_required_signatures' })
            $missing.Count | Should -Be 1
            $missing[0].Desired | Should -BeTrue
        }

        It "does not judge a pull_request rule that repo-steward owns elsewhere" {
            $drift = @((Get-GitHubRepoConfig -Repository 'compliant').Drift)
            @($drift | Where-Object { $_.Setting -match 'pull_request|merge_methods|review' }).Count | Should -Be 0
        }
    }

    Context "when a fork carries the full steward rule set" {
        BeforeEach {
            Mock -ModuleName DotfilesHelpers Get-GitHubRulesetList { script:New-RulesetListPresent }
            Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
                $repo = script:New-CompliantRepoResponse
                $repo | Add-Member -NotePropertyName fork -NotePropertyValue $true
                script:Get-MockApiResponse -Endpoint $Endpoint `
                    -Repo $repo `
                    -Actions (script:New-CompliantActionsResponse) `
                    -RulesetDetail (script:New-CompliantRulesetDetail)
            }
        }

        It "flags linear history and signatures as unwanted, since they block Sync fork" {
            $drift = @((Get-GitHubRepoConfig -Repository 'compliant').Drift)
            @($drift | ForEach-Object Setting) | Sort-Object |
                Should -Be @('ruleset_required_linear_history', 'ruleset_required_signatures')
            @($drift | Where-Object { $_.Desired -ne $false }).Count | Should -Be 0
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
    Context "fork remediation" {
        It "writes only the fork rules when remediating a fork" {
            Mock -ModuleName DotfilesHelpers Test-GitHubCliReady { }
            Mock -ModuleName DotfilesHelpers Get-GitHubCurrentOwner { 'DevSecNinja' }
            Mock -ModuleName DotfilesHelpers Get-GitHubRulesetList { script:New-RulesetListEmpty }
            Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
                $repo = script:New-CompliantRepoResponse
                $repo | Add-Member -NotePropertyName fork -NotePropertyValue $true
                script:Get-MockApiResponse -Endpoint $Endpoint -Repo $repo
            }

            Get-GitHubRepoConfig -Repository 'forked' -Check Ruleset |
                Set-GitHubRepoConfig -Confirm:$false

            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubApi -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Endpoint -like '*/rulesets' -and
                (@($Body['rules'] | ForEach-Object { $_.type }) | Sort-Object) -join ',' -eq 'deletion,non_fast_forward'
            }
        }
    }
    Context "ruleset identity" {
        It "ignores a tag ruleset that shares the baseline name" {
            InModuleScope DotfilesHelpers {
                $list = [PSCustomObject]@{
                    Available = $true
                    Rulesets  = @([PSCustomObject]@{ id = 9; name = 'steward-default-branch'; target = 'tag'; source_type = 'Repository' })
                }
                @($list.Rulesets | Where-Object {
                        $_.name -eq 'steward-default-branch' -and $_.target -eq 'branch' -and
                        ($null -eq $_.source_type -or $_.source_type -eq 'Repository')
                    }).Count | Should -Be 0
            }
        }

        It "ignores an organisation-inherited ruleset that shares the name" {
            InModuleScope DotfilesHelpers {
                $rulesets = @([PSCustomObject]@{ id = 9; name = 'steward-default-branch'; target = 'branch'; source_type = 'Organization' })
                @($rulesets | Where-Object {
                        $_.name -eq 'steward-default-branch' -and $_.target -eq 'branch' -and
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

Describe "Get-GitHubAppCredential -PrivateKeyPath" -Tag "Unit" {
    BeforeAll {
        # Genuine throwaway keys generated per run, never written outside
        # TestDrive. KeyMarker is a slice of the key material used to detect
        # any leak into an output stream.
        $rsa = [System.Security.Cryptography.RSA]::Create(2048)
        $script:RsaPem = $rsa.ExportRSAPrivateKeyPem()
        $script:Pkcs8Pem = $rsa.ExportPkcs8PrivateKeyPem()
        $script:EcPem = [System.Security.Cryptography.ECDsa]::Create().ExportPkcs8PrivateKeyPem()
        $script:KeyMarker = ($script:RsaPem -split "`n")[2].Substring(0, 40)
        $rsa.Dispose()

        function script:New-KeyFile {
            param([string]$Content, [string]$Name = 'automation-app.2026-11-14.private-key.pem')
            $path = Join-Path $TestDrive $Name
            [System.IO.File]::WriteAllText($path, $Content)
            return $path
        }

        function script:ConvertFrom-TestSecureString {
            param([System.Security.SecureString]$SecureString)
            InModuleScope DotfilesHelpers -Parameters @{ S = $SecureString } {
                param($S)
                ConvertFrom-DotfilesSecureString -SecureString $S
            }
        }
    }

    Context "valid keys" {
        It "reads a <Kind> key into a SecureString" -ForEach @(
            @{ Kind = 'PKCS#1 RSA' }
            @{ Kind = 'PKCS#8' }
            @{ Kind = 'CRLF' }
        ) {
            $pem = switch ($Kind) {
                'PKCS#1 RSA' { $script:RsaPem }
                'PKCS#8' { $script:Pkcs8Pem }
                'CRLF' { $script:RsaPem -replace "`n", "`r`n" }
            }
            $path = script:New-KeyFile -Content "$pem`n"

            $cred = Get-GitHubAppCredential -AppId 3563533 -PrivateKeyPath $path

            $cred.AppId | Should -Be '3563533'
            $cred.PrivateKey | Should -BeOfType [System.Security.SecureString]
            script:ConvertFrom-TestSecureString -SecureString $cred.PrivateKey | Should -Be $pem
        }

        It "accepts the '.private-key' extension" {
            $path = script:New-KeyFile -Content $script:RsaPem -Name 'automation-app.private-key'
            (Get-GitHubAppCredential -AppId 1 -PrivateKeyPath $path).AppId | Should -Be '1'
        }

        It "keeps only the key block, dropping text around it" {
            $path = script:New-KeyFile -Content "Bag Attributes`n    localKeyID: 01`n$($script:RsaPem)`n`n"
            $cred = Get-GitHubAppCredential -AppId 1 -PrivateKeyPath $path
            script:ConvertFrom-TestSecureString -SecureString $cred.PrivateKey | Should -Be $script:RsaPem
        }

        It "does not touch 1Password" {
            Mock -ModuleName DotfilesHelpers Invoke-OnePasswordCli { throw 'op must not be called' }
            $path = script:New-KeyFile -Content $script:Pkcs8Pem

            $null = Get-GitHubAppCredential -AppId 1 -PrivateKeyPath $path

            Should -Invoke -ModuleName DotfilesHelpers Invoke-OnePasswordCli -Times 0 -Exactly
        }
    }

    Context "rejected files" {
        It "rejects <Case>" -ForEach @(
            @{ Case = 'a certificate'; Content = "-----BEGIN CERTIFICATE-----`nMIIDcertificateSentinelBody==`n-----END CERTIFICATE-----"; Message = '*contains a certificate, not a private key*' }
            @{ Case = 'a certificate bundled with a key'; Content = "-----BEGIN CERTIFICATE-----`nMIIDcert==`n-----END CERTIFICATE-----`n-----BEGIN RSA PRIVATE KEY-----`nMIIE==`n-----END RSA PRIVATE KEY-----"; Message = '*contains a certificate*' }
            @{ Case = 'an empty file'; Content = ''; Message = '*is empty*' }
            @{ Case = 'a whitespace-only file'; Content = "  `n`t`n"; Message = '*is empty*' }
            @{ Case = 'arbitrary text'; Content = 'not a key at all'; Message = '*does not contain a PEM private key*' }
            @{ Case = 'a public key'; Content = "-----BEGIN PUBLIC KEY-----`nMIIBIjAN==`n-----END PUBLIC KEY-----"; Message = '*does not contain a PEM private key*' }
            @{ Case = 'mismatched BEGIN/END lines'; Content = "-----BEGIN RSA PRIVATE KEY-----`nMIIE==`n-----END PRIVATE KEY-----"; Message = '*does not contain a PEM private key*' }
            @{ Case = 'an encrypted PKCS#8 key'; Content = "-----BEGIN ENCRYPTED PRIVATE KEY-----`nMIIE==`n-----END ENCRYPTED PRIVATE KEY-----"; Message = '*passphrase-protected*' }
            @{ Case = 'an encrypted PKCS#1 key'; Content = "-----BEGIN RSA PRIVATE KEY-----`nProc-Type: 4,ENCRYPTED`nDEK-Info: AES-128-CBC,00`n`nMIIE==`n-----END RSA PRIVATE KEY-----"; Message = '*passphrase-protected*' }
            @{ Case = 'two keys'; Content = "-----BEGIN RSA PRIVATE KEY-----`nMIIE==`n-----END RSA PRIVATE KEY-----`n-----BEGIN PRIVATE KEY-----`nMIIE==`n-----END PRIVATE KEY-----"; Message = '*contains 2 private keys*' }
            @{ Case = 'a whitespace-only key body'; Content = "-----BEGIN RSA PRIVATE KEY-----`n   `n-----END RSA PRIVATE KEY-----"; Message = '*does not hold a valid RSA private key*' }
            @{ Case = 'base64-encoded text'; Content = "-----BEGIN RSA PRIVATE KEY-----`naGVsbG8gd29ybGQsIHRoaXMgaXMgbm90IGEga2V5`n-----END RSA PRIVATE KEY-----"; Message = '*does not hold a valid RSA private key*' }
            @{ Case = 'a truncated key'; Content = "-----BEGIN PRIVATE KEY-----`nMIIEvQIBADANBgkqhkiG9w0BAQEFAASC`n-----END PRIVATE KEY-----"; Message = '*does not hold a valid RSA private key*' }
            @{ Case = 'a minimal AAAA body'; Content = "-----BEGIN RSA PRIVATE KEY-----`nAAAA`n-----END RSA PRIVATE KEY-----"; Message = '*does not hold a valid RSA private key*' }
        ) {
            $path = script:New-KeyFile -Content $Content
            { Get-GitHubAppCredential -AppId 1 -PrivateKeyPath $path } | Should -Throw -ExpectedMessage $Message
        }

        It "rejects a non-RSA (EC) PKCS#8 key" {
            $path = script:New-KeyFile -Content $script:EcPem
            { Get-GitHubAppCredential -AppId 1 -PrivateKeyPath $path } |
                Should -Throw -ExpectedMessage '*does not hold a valid RSA private key*'
        }

        It "rejects a missing file" {
            { Get-GitHubAppCredential -AppId 1 -PrivateKeyPath (Join-Path $TestDrive 'missing.pem') } |
                Should -Throw -ExpectedMessage '*was not found*'
        }

        It "rejects a directory" {
            { Get-GitHubAppCredential -AppId 1 -PrivateKeyPath $TestDrive } |
                Should -Throw -ExpectedMessage '*was not found*'
        }

        It "rejects an App ID that is not numeric" {
            $path = script:New-KeyFile -Content $script:RsaPem
            { Get-GitHubAppCredential -AppId 'Iv1.abc123' -PrivateKeyPath $path } |
                Should -Throw -ExpectedMessage '*not a numeric GitHub App ID*'
        }

        It "cannot mix a file with 1Password references" {
            $path = script:New-KeyFile -Content $script:RsaPem
            { Get-GitHubAppCredential -AppId 1 -PrivateKeyPath $path -PrivateKeyReference 'op://a/b/c' } | Should -Throw
        }
    }

    Context "secrecy" {
        It "writes no key material to any output stream" {
            $path = script:New-KeyFile -Content $script:RsaPem
            $info = @()

            $streams = Get-GitHubAppCredential -AppId 1 -PrivateKeyPath $path -Verbose -InformationVariable info *>&1

            ($streams | Out-String).Contains($script:KeyMarker) | Should -BeFalse
            ($info | Out-String).Contains($script:KeyMarker) | Should -BeFalse
        }

        It "does not echo file contents in validation errors for <Case>" -ForEach @(
            @{ Case = 'a certificate'; Content = "-----BEGIN CERTIFICATE-----`nMIIDcertificateSentinelBody==`n-----END CERTIFICATE-----" }
            @{ Case = 'an invalid key body'; Content = "-----BEGIN RSA PRIVATE KEY-----`nMIIEkeySentinelBodyNotAKey==`n-----END RSA PRIVATE KEY-----" }
        ) {
            $path = script:New-KeyFile -Content $Content
            $message = try { Get-GitHubAppCredential -AppId 1 -PrivateKeyPath $path; '' } catch { $_.Exception.Message }
            $message | Should -Not -BeNullOrEmpty
            $message | Should -Not -Match 'Sentinel'
        }
    }

    Context "Windows PowerShell 5.1 structural fallback" {
        BeforeAll {
            function script:Test-DerFromBase64 {
                param([string]$Base64, [string]$Label)
                InModuleScope DotfilesHelpers -Parameters @{ Base64 = $Base64; Label = $Label } {
                    param($Base64, $Label)
                    Test-GitHubAppPrivateKeyDer -Der ([System.Convert]::FromBase64String($Base64)) -Label $Label
                }
            }
            function script:Get-PemBase64 {
                param([string]$Pem)
                ($Pem -replace '-----[A-Z ]+-----', '') -replace '\s', ''
            }
        }

        It "accepts a genuine <Label> key" -ForEach @(
            @{ Label = 'RSA PRIVATE KEY' }
            @{ Label = 'PRIVATE KEY' }
        ) {
            $pem = if ($Label -eq 'RSA PRIVATE KEY') { $script:RsaPem } else { $script:Pkcs8Pem }
            script:Test-DerFromBase64 -Base64 (script:Get-PemBase64 $pem) -Label $Label | Should -BeTrue
        }

        It "rejects <Case>" -ForEach @(
            @{ Case = 'an empty payload'; Base64 = ''; Label = 'RSA PRIVATE KEY' }
            @{ Case = 'encoded text'; Base64 = 'aGVsbG8gd29ybGQsIHRoaXMgaXMgbm90IGEga2V5'; Label = 'RSA PRIVATE KEY' }
            @{ Case = 'a truncated key'; Base64 = 'MIIEvQIBADANBgkqhkiG9w0BAQEFAASC'; Label = 'PRIVATE KEY' }
            @{ Case = 'an EC key'; Base64 = 'EC'; Label = 'PRIVATE KEY' }
        ) {
            $value = if ($Base64 -eq 'EC') { script:Get-PemBase64 $script:EcPem } else { $Base64 }
            script:Test-DerFromBase64 -Base64 $value -Label $Label | Should -BeFalse
        }
    }
    Context "rolling it out" {
        BeforeEach {
            Mock -ModuleName DotfilesHelpers Test-GitHubCliReady { }
            Mock -ModuleName DotfilesHelpers Get-GitHubCurrentOwner { 'DevSecNinja' }
            Mock -ModuleName DotfilesHelpers Get-GitHubRulesetList { script:New-RulesetListEmpty }
            Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
                script:Get-MockApiResponse -Endpoint $Endpoint `
                    -Repo (script:New-DriftedRepoResponse) `
                    -Variables ([PSCustomObject]@{ variables = @() }) `
                    -Secrets ([PSCustomObject]@{ secrets = @() }) `
                    -EnvironmentDetail $null `
                    -BranchPolicies ([PSCustomObject]@{ branch_policies = @([PSCustomObject]@{ name = 'main' }) })
            }
            Mock -ModuleName DotfilesHelpers Invoke-GitHubCli { 'ok' }

            $script:FileCredential = Get-GitHubAppCredential -AppId 3563533 -PrivateKeyPath (script:New-KeyFile -Content $script:RsaPem)
        }

        It "makes no writes under -WhatIf" {
            Get-GitHubRepoConfig -Repository 'drifted' -Check AppCredential |
                Set-GitHubRepoConfig -AppCredential $script:FileCredential -WhatIf

            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubCli -Times 0 -Exactly -ParameterFilter {
                $Arguments -contains 'secret' -or $Arguments -contains 'variable'
            }
            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubApi -Times 0 -Exactly -ParameterFilter {
                $Method -in @('POST', 'PATCH', 'PUT', 'DELETE')
            }
        }

        It "previews the credential writes under -WhatIf instead of refusing them" {
            $warnings = @()
            Get-GitHubRepoConfig -Repository 'drifted' -Check AppCredential |
                Set-GitHubRepoConfig -AppCredential $script:FileCredential -WhatIf -WarningVariable warnings -WarningAction SilentlyContinue

            ($warnings -join ' ') | Should -Not -Match 'Not writing the App credential'
        }

        It "hands the key to gh on stdin only, and logs none of it" {
            $info = @()
            $streams = Get-GitHubRepoConfig -Repository 'drifted' -Check AppCredential |
                Set-GitHubRepoConfig -AppCredential $script:FileCredential -Confirm:$false -Verbose -InformationVariable info *>&1

            Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubCli -Times 1 -Exactly -ParameterFilter {
                $Arguments -contains 'secret' -and $StdIn.Contains($script:KeyMarker) -and -not ($Arguments -join ' ').Contains($script:KeyMarker)
            }
            ($streams | Out-String).Contains($script:KeyMarker) | Should -BeFalse
            ($info | Out-String).Contains($script:KeyMarker) | Should -BeFalse
        }
    }
}

Describe "Release repository filter" -Tag "Unit" {
    BeforeEach {
        Mock -ModuleName DotfilesHelpers Test-GitHubCliReady { }
        Mock -ModuleName DotfilesHelpers Get-GitHubCurrentOwner { 'DevSecNinja' }
        Mock -ModuleName DotfilesHelpers Get-GitHubRulesetList { script:New-RulesetListPresent }
        Mock -ModuleName DotfilesHelpers Invoke-GitHubCli {
            @(
                @{ nameWithOwner = 'DevSecNinja/app'; isArchived = $false; isFork = $false }
                @{ nameWithOwner = 'DevSecNinja/cfg'; isArchived = $false; isFork = $false }
                @{ nameWithOwner = 'DevSecNinja/paged'; isArchived = $false; isFork = $false }
                @{ nameWithOwner = 'DevSecNinja/data'; isArchived = $false; isFork = $false }
                @{ nameWithOwner = 'DevSecNinja/none'; isArchived = $false; isFork = $false }
                @{ nameWithOwner = 'DevSecNinja/draft'; isArchived = $false; isFork = $false }
                @{ nameWithOwner = 'DevSecNinja/forked'; isArchived = $false; isFork = $true }
                @{ nameWithOwner = 'DevSecNinja/old'; isArchived = $true; isFork = $false }
            ) | ConvertTo-Json -Compress
        } -ParameterFilter { $Arguments -contains 'list' }

        Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
            $release = { param($tag, $draft = $false) [PSCustomObject]@{ tag_name = $tag; draft = $draft } }
            switch -Regex ($Endpoint) {
                '/cfg/contents/release-please-config\.json$' { return [PSCustomObject]@{ name = 'release-please-config.json' } }
                '/contents/release-please-config\.json$' { return $null }
                '/app/releases' { return , @((& $release 'db-2026-11-01'), (& $release 'v1.2.0')) }
                '/paged/releases\?.*page=1$' { return , @(1..100 | ForEach-Object { & $release "db-$_" }) }
                '/paged/releases\?.*page=2$' { return , @((& $release 'v2.0.0')) }
                '/data/releases' { return , @((& $release 'db-2026-11-01'), (& $release 'news-state')) }
                '/draft/releases' { return , @((& $release 'v1.0.0' $true)) }
                '/(forked|old)/releases' { return , @((& $release 'v9.0.0')) }
                '/releases' { return , @() }
                default {
                    script:Get-MockApiResponse -Endpoint $Endpoint `
                        -Repo (script:New-CompliantRepoResponse) `
                        -Actions (script:New-CompliantActionsResponse) `
                        -RulesetDetail (script:New-CompliantRulesetDetail)
                }
            }
        }
    }

    It "keeps repositories with a versioned release or a release-please config" {
        $names = @(Get-GitHubRepoConfig -All -HasRelease -Check Settings -InformationAction SilentlyContinue).Repository
        $names | Should -Be @('DevSecNinja/app', 'DevSecNinja/cfg', 'DevSecNinja/paged')
    }

    It "ignores data and state releases, drafts and repositories without releases" {
        $names = @(Get-GitHubRepoConfig -All -HasRelease -Check Settings -InformationAction SilentlyContinue).Repository
        $names | Should -Not -Contain 'DevSecNinja/data'
        $names | Should -Not -Contain 'DevSecNinja/draft'
        $names | Should -Not -Contain 'DevSecNinja/none'
    }

    It "excludes forks and archived repositories without querying their releases" {
        $null = Get-GitHubRepoConfig -All -HasRelease -Check Settings -InformationAction SilentlyContinue

        Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubApi -Times 0 -Exactly -ParameterFilter {
            $Endpoint -match '/(forked|old)/'
        }
    }

    It "records why each repository qualified" {
        $results = @(Get-GitHubRepoConfig -All -HasRelease -Check Settings -InformationAction SilentlyContinue)
        ($results | Where-Object Name -EQ 'app').ReleaseEvidence | Should -Be 'release v1.2.0'
        ($results | Where-Object Name -EQ 'cfg').ReleaseEvidence | Should -Be 'release-please-config.json'
    }

    It "follows release pages until it finds a versioned release" {
        $results = @(Get-GitHubRepoConfig -All -HasRelease -Check Settings -InformationAction SilentlyContinue)

        ($results | Where-Object Name -EQ 'paged').ReleaseEvidence | Should -Be 'release v2.0.0'
        Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubApi -Times 1 -Exactly -ParameterFilter {
            $Endpoint -match '/paged/releases\?.*page=2$'
        }
        Should -Invoke -ModuleName DotfilesHelpers Invoke-GitHubApi -Times 0 -Exactly -ParameterFilter {
            $Endpoint -match '/data/releases\?.*page=2$'
        }
    }

    It "reports how many repositories the filter kept" {
        $info = @()
        $null = Get-GitHubRepoConfig -All -HasRelease -Check Settings -InformationVariable info -InformationAction SilentlyContinue
        ($info.MessageData -join ' ') | Should -Match '3 of 6 active, non-fork repositories'
    }

    It "leaves results unfiltered without -HasRelease" {
        @(Get-GitHubRepoConfig -All -Check Settings).Count | Should -Be 7
    }

    It "refuses to combine -HasRelease with -IncludeArchived" {
        { Get-GitHubRepoConfig -All -HasRelease -IncludeArchived } | Should -Throw -ExpectedMessage '*-IncludeArchived*'
    }

    It "warns about and counts a repository whose releases cannot be read" {
        Mock -ModuleName DotfilesHelpers Get-GitHubReleaseEvidence {
            if ($Repository -eq 'DevSecNinja/data') { throw 'Could not list releases for DevSecNinja/data (page 1).' }
            if ($Repository -eq 'DevSecNinja/app') { return 'release v1.2.0' }
            return $null
        }
        $warnings = @()
        $info = @()

        $names = @(Get-GitHubRepoConfig -All -HasRelease -Check Settings -WarningVariable warnings -WarningAction SilentlyContinue -InformationVariable info -InformationAction SilentlyContinue).Repository

        $names | Should -Be @('DevSecNinja/app')
        ($warnings -join ' ') | Should -Match 'could not check DevSecNinja/data'
        ($info.MessageData -join ' ') | Should -Match '1 could not be checked and were left out'
    }

    It "throws from the evidence lookup when the release list cannot be read" {
        InModuleScope DotfilesHelpers {
            Mock Invoke-GitHubApi { $null }
            { Get-GitHubReleaseEvidence -Repository 'DevSecNinja/x' } | Should -Throw -ExpectedMessage '*Could not list releases*'
        }
    }

    It "treats '<Tag>' as a version release: <Expected>" -ForEach @(
        @{ Tag = 'v1.2.0'; Expected = $true }
        @{ Tag = '1.2'; Expected = $true }
        @{ Tag = 'v10.0.0-rc.1'; Expected = $true }
        @{ Tag = 'v1'; Expected = $false }
        @{ Tag = 'db-2026-01-01'; Expected = $false }
        @{ Tag = 'news-state'; Expected = $false }
        @{ Tag = 'latest'; Expected = $false }
    ) {
        InModuleScope DotfilesHelpers -Parameters @{ Tag = $Tag; Expected = $Expected } {
            param($Tag, $Expected)
            Mock Invoke-GitHubApi {
                if ($Endpoint -like '*/releases*') { return , @([PSCustomObject]@{ tag_name = $Tag; draft = $false }) }
                return $null
            }
            $null -ne (Get-GitHubReleaseEvidence -Repository 'DevSecNinja/x') | Should -Be $Expected
        }
    }
}

Describe "Set-GitHubRepoConfig logging" -Tag "Unit" {
    BeforeEach {
        Mock -ModuleName DotfilesHelpers Test-GitHubCliReady { }
        Mock -ModuleName DotfilesHelpers Get-GitHubCurrentOwner { 'DevSecNinja' }
        Mock -ModuleName DotfilesHelpers Get-GitHubRulesetList { script:New-RulesetListEmpty }
        Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
            script:Get-MockApiResponse -Endpoint $Endpoint `
                -Repo (script:New-DriftedRepoResponse) `
                -Actions (script:New-CompliantActionsResponse) `
                -Variables ([PSCustomObject]@{ variables = @() }) `
                -Secrets ([PSCustomObject]@{ secrets = @() })
        }
        Mock -ModuleName DotfilesHelpers Invoke-GitHubCli { 'ok' }
    }

    It "logs what was applied to each repository and a summary" {
        $info = @()
        Get-GitHubRepoConfig -Repository 'drifted' -Check Settings |
            Set-GitHubRepoConfig -Confirm:$false -InformationVariable info -InformationAction SilentlyContinue

        $log = $info.MessageData -join "`n"
        $log | Should -Match 'DevSecNinja/drifted: applied 5 of 5 change\(s\) \[Settings/allow_merge_commit'
        $log | Should -Match 'Summary: 1 repositories, 0 already compliant, 0 not fully evaluated, 0 archived, 1 changed \(5 change\(s\) applied\), 0 item\(s\) skipped'
    }

    It "logs skipped items by name" {
        $info = @()
        Get-GitHubRepoConfig -Repository 'drifted' -Check AppCredential -WarningAction SilentlyContinue |
            Set-GitHubRepoConfig -Confirm:$false -InformationVariable info -InformationAction SilentlyContinue -WarningAction SilentlyContinue

        ($info.MessageData -join "`n") | Should -Match 'skipped \[.*AppCredential/AUTOMATION_APP_PRIVATE_KEY'
    }

    It "reports previewed changes under -WhatIf" {
        $info = @()
        Get-GitHubRepoConfig -Repository 'drifted' -Check Settings |
            Set-GitHubRepoConfig -WhatIf -InformationVariable info -InformationAction SilentlyContinue

        $log = $info.MessageData -join "`n"
        $log | Should -Match 'drifted: 5 change\(s\) previewed, none applied'
        $log | Should -Match 'WhatIf: nothing was written'
    }

    It "logs an already-compliant repository" {
        Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
            script:Get-MockApiResponse -Endpoint $Endpoint -Repo (script:New-CompliantRepoResponse)
        }
        $info = @()
        Get-GitHubRepoConfig -Repository 'compliant' -Check Settings |
            Set-GitHubRepoConfig -Confirm:$false -InformationVariable info -InformationAction SilentlyContinue

        $log = $info.MessageData -join "`n"
        $log | Should -Match 'compliant: already compliant'
        $log | Should -Match '1 already compliant'
    }

    It "does not call a repository with unreadable categories compliant" {
        Mock -ModuleName DotfilesHelpers Get-GitHubRulesetList { script:New-RulesetListUnavailable }
        Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
            script:Get-MockApiResponse -Endpoint $Endpoint -Repo (script:New-CompliantRepoResponse)
        }
        $info = @()
        Get-GitHubRepoConfig -Repository 'compliant' -Check Settings, Ruleset -WarningAction SilentlyContinue |
            Set-GitHubRepoConfig -Confirm:$false -InformationVariable info -InformationAction SilentlyContinue

        $log = $info.MessageData -join "`n"
        $log | Should -Match 'compliant: no drift found; not evaluated \[Ruleset\]'
        $log | Should -Match '0 already compliant, 1 not fully evaluated'
    }

    It "ignores unreadable categories outside -Category" {
        Mock -ModuleName DotfilesHelpers Get-GitHubRulesetList { script:New-RulesetListUnavailable }
        Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
            script:Get-MockApiResponse -Endpoint $Endpoint -Repo (script:New-CompliantRepoResponse)
        }
        $info = @()
        Get-GitHubRepoConfig -Repository 'compliant' -Check Settings, Ruleset -WarningAction SilentlyContinue |
            Set-GitHubRepoConfig -Category Settings -Confirm:$false -InformationVariable info -InformationAction SilentlyContinue

        ($info.MessageData -join "`n") | Should -Match 'compliant: already compliant'
    }

    It "does not count skipped items as previewed under -WhatIf" {
        $info = @()
        Get-GitHubRepoConfig -Repository 'drifted' -Check AppCredential -WarningAction SilentlyContinue |
            Set-GitHubRepoConfig -WhatIf -InformationVariable info -InformationAction SilentlyContinue -WarningAction SilentlyContinue

        $log = $info.MessageData -join "`n"
        $log | Should -Match 'drifted: 0 change\(s\) previewed, none applied; skipped \[.*AppCredential/AUTOMATION_APP_PRIVATE_KEY'
        $log | Should -Match '0 change\(s\) previewed, 4 item\(s\) skipped\. WhatIf'
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

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCAS771y7oEK6Xf
# 7nvi3PwZd+DLQtO88ix5sSKfzbdkqKCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# oW2jNrbM1pD2T7m3XDCCBu0wggTVoAMCAQICEAhP3DNPfkVO28MPj/mSGDUwDQYJ
# KoZIhvcNAQELBQAwaTELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJ
# bmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVkIEc0IFRpbWVTdGFtcGluZyBS
# U0E0MDk2IFNIQTI1NiAyMDI1IENBMTAeFw0yNjA4MDUwMDAwMDBaFw0zNzExMDQy
# MzU5NTlaMGMxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7
# MDkGA1UEAxMyRGlnaUNlcnQgU0hBMjU2IFJTQTQwOTYgVGltZXN0YW1wIFJlc3Bv
# bmRlciAyMDI2IDEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC2e6by
# yf7NSvjUm0xls/04xjD4fAkOkbnGQi7+Wpx81iYxfzViaxSIctuH3KSl5YEYpMuF
# gGsA31N2D9ATMbfZdw5uaAhuWevQKhDdZIB4NnqcfpfpWQXJiQnDdAElETC+bhSE
# vNLGbA8DtwUpFMQ4yyYQSPqomT92osQAv6hBi47ATZS6JfVWe6XxhF4jJZ3iSAuf
# 2Cros1czRSmWRHqMv9AfGZvp8ygYElhudpQjtcPpwoOl6QrZJUyV3iINvN4cO05p
# rGV0fkjG426xDr2d3z9lcSIHkdvGPdGUrXdxfVbgOUVcp2/8ISEzwKPW++Wa+E2u
# jI91EZtukGWDJ/xZ27k3oHKEXBRGfRTqjOU+jE3ba/5++JSE/7oNHnjs5mekExYN
# 96LV/mxUbCKJb8pBNY4r3uD7hEmk/M81XhVgwDA7aMzYC3LZBg9WY5BMmbSay5ec
# mtJuXaB/0nKWmQmVZeqTVDgsmzHP5MQuhAJkiWNuC9MmCg9TZHXbJ2/yLVSov9p1
# 6UDTLtT0+aa1vN71fHeu1qMLlLNB3WOB/ADCxr3S/1hxI92Z6jKgEED/btwIvbfu
# XkNNhg8MtDg43c4tMZae9FvqMOt/9PvmAxF9TNIsIFB8G6yb36ZJZGUL8N/pL971
# DyLXcK6HM5PYnH5X+eVtczhCgHCVQCF6XDAlPQIDAQABo4IBlTCCAZEwDAYDVR0T
# AQH/BAIwADAdBgNVHQ4EFgQUFMljijAu1Er7bpTz5uNAfvXszeIwHwYDVR0jBBgw
# FoAU729TSunkBnx6yuKQVvYv1Ensy04wDgYDVR0PAQH/BAQDAgeAMBYGA1UdJQEB
# /wQMMAoGCCsGAQUFBwMIMIGVBggrBgEFBQcBAQSBiDCBhTAkBggrBgEFBQcwAYYY
# aHR0cDovL29jc3AuZGlnaWNlcnQuY29tMF0GCCsGAQUFBzAChlFodHRwOi8vY2Fj
# ZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRUaW1lU3RhbXBpbmdS
# U0E0MDk2U0hBMjU2MjAyNUNBMS5jcnQwXwYDVR0fBFgwVjBUoFKgUIZOaHR0cDov
# L2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZEc0VGltZVN0YW1waW5n
# UlNBNDA5NlNIQTI1NjIwMjVDQTEuY3JsMCAGA1UdIAQZMBcwCAYGZ4EMAQQCMAsG
# CWCGSAGG/WwHATANBgkqhkiG9w0BAQsFAAOCAgEAjcU6YR6dUgrfmawJgH59KECx
# a9Ji8sEi2g10CBDaMiqsaxWyW5cwlT/6ZF5sFznazqVsoC85U9dqLOYqQwst+UQQ
# oNlDHgKRLa3xoc+OReFreFhnTXSG0Vrd2E2CZqUfm+5a+He1MJ/h+tNLuA+0Zzhn
# /Fo+FDYAHWZHx4R79ZsfRFYe9UiXpXBDf6DkUo183Y38NYmR/XfDYf7YZ+oR9t3f
# lbDwK+hgGMs0gNNp1w9Z2CyOyI5or/sSwomAuNQ0hWC9xoU4stD8aWsD7RkcmgVR
# s6vlIk3zPKQ+ylcheWkMlj+CoVRlFE55pv0ZWCaFt04lwP/rdGHE9qEVQZtyRE42
# ox7oNgC/r+Y4bSlZ3dw9K2x1xLtu6PkPKeLBFjzKigwfqm3Hm+k/+lnME8F5kPZT
# giy2HLEHklpryqs6QHnPXrRNeIzkAMyylnRN8P0wmirS0WkU+ywpEWFZ4QNg+9xS
# 43tTuW9x0eXh7NDc1P/sV+zWxHXKH8tFt1ncHdVzqrZaYPyYMLSn2TOXajveJW1L
# 3joiQSPsWRGxkbDDW15jERFE4LvjnGu2O9zD1nLJSMdlYZEikl4w2w+q4IN/R+TI
# e0H4ngCI1moJCTbevGH4punIxM1Uoi0nmX3ZK+XbRT01uowE5ViXWHng0RgsmrX/
# EdYUo80r3TfMlkD0/YMxggYTMIIGDwIBATA3MCMxITAfBgNVBAMMGEplYW4tUGF1
# bCB2YW4gUmF2ZW5zYmVyZwIQELbg9grCcadOf9RJU4Fg9DANBglghkgBZQMEAgEF
# AKCBhDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgor
# BgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3
# DQEJBDEiBCCgEGS0UhgkuIsP+SLXcRxoo0yRVQxrs1Lcz3hQqlD3MjANBgkqhkiG
# 9w0BAQEFAASCAgAGC2f+tXjiXn7K1ro7a+WqUC24hMpWfLupsm/cULztN6+gXJxh
# iSjOj95VMcb6F0mXkjyhR+u/ecvS+OpgCb57Ddgaw9uahobQZBJXbUCitdzUjo8n
# 0DiPsXjecUytMjSl3XPV8mD7Pg+lj0/uYMnoRXROq15wiX3Hnx5DwQzF05ga1U7g
# 3VhHQOaDURIcWKoTGWhijmwCH4619mX8MnF+if7dFeBSXdA1TwR5m3lA7rMkZnXB
# Wg65/om3c/VFHx+OX7sbqqx+BKpN8ZpPGDUd83IztznALrJbTF9PHGUftJYIv2pX
# uFdkLChPD+gauCADajNrtCotbAkixxnEHBguQyzWqMZKQYcexCOF9Or/6soScSRI
# 5y9cIuxlGk+/hPPRyeUk+E8zGfHGumHGb02n6cAZRBCMz3/r/FZuYs2RLvpwErAF
# 2Ug/G5CZwfyGok1sjNm1ey4/eqXO1zfQ4uVLyFVyi3e2zbY5b2gWi74HrFrX0+rn
# GxhBqS8hOu/F9F0JarwKarOxvh5p8oRflLAUPvw5VJEgnTTcy+t/5KOQJqefVp87
# 9tYfflPsxyz6u4Zb7IMi+uI+rCRpNouLTR1edMG1g6yf8HdbzgiPc7WueUVR8WYA
# DQTZCmaDkJ4UEds6NxSw93zb2lcnkAGW99Yj5hvFkRah6hLLaRmNPcuaqKGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAhP3DNPfkVO
# 28MPj/mSGDUwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjExMTQxMTU0MjRaMC8GCSqGSIb3DQEJBDEi
# BCC/2tTfcyX1J1JquUj3I7VVyh8BDIp7TRveoDm66zx3vjANBgkqhkiG9w0BAQEF
# AASCAgCIJ49kBmPkEWJmtle32TAmHRPUyEjPlU1ol2J9R4RAcxhOBYCwjTI7355X
# 0vZYwnlfr94G39JAwcaKWYqZj3uhA3CDbyF/EENgupPugidYppOfaN/JW9+X+5Jb
# 37HgVF2sc+Gm5fHjpHk7GXSPe+0Fp2LdbvdDFtpjSC0/p1R1g0O6eSQM1m2Dlw6G
# KrPhZqY3F7oHEF7gM/uc+G6eLwsRAopDRNg4dtzi+c0szSDHvVy8nzS5TQISpBMH
# 4Qo7ukoC48vh0k82nMJln7vM+fHRlfGifWu3NhpTiuppzb1+gYDyfRQV3BsCqY72
# nkDMV8LVBGHH2nuBpPspasKTU1AoFhGtakrKrITmhpfVhiWJADLMnBdaPN3u720Q
# nOpF/b6kwd/syhmUj7rtmlIq9KIM0XpnhhBBnWIgBxezEvErWz/kfmSp5uOvViLy
# kSkUPpQbcNT/7ORssLFRrMnr9Tgu+F9V+MzMzDp26X7GNf9YtrIsFD2LCb5Vjz06
# nbWBMtvbXYMyg6dQhgpUzE2Bxx8GlWrGmgCctN0LmEbAtPtbPeKzY34biDxoNyde
# O5MCq6GbSU6uGUEZ8N4CPdLrkqC8bOLOL0gev3z/Z7JBFj1Ga5JXbS1p3lRwhd9j
# kLIe1EchDC3J8F0x6arFSlu+1CauqDQmuW8aZ0yQyGCXEs7XZw==
# SIG # End signature block
