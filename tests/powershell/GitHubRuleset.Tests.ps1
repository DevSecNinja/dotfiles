#Requires -Version 5.1
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Test fixtures build SecureStrings from literal, non-sensitive placeholder values.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'InModuleScope -Parameters values are consumed inside nested Mock scriptblocks, which the analyzer cannot trace.')]
param()
<#
.SYNOPSIS
    Pester tests for default-branch ruleset payload construction.

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

Describe "New-GitHubRulesetPayload" -Tag "Unit" {
    It "includes the repository admin role as a bypass actor" {
        InModuleScope DotfilesHelpers {
            $payload = New-GitHubRulesetPayload -Ruleset (Get-GitHubRepoBaseline).Ruleset
            $payload.bypass_actors.Count | Should -Be 1
            $payload.bypass_actors[0].actor_type | Should -Be 'RepositoryRole'
            $payload.bypass_actors[0].actor_id | Should -Be 5
            $payload.bypass_actors[0].bypass_mode | Should -Be 'always'
        }
    }

    It "omits bypass actors when AdminCanBypass is false" {
        InModuleScope DotfilesHelpers {
            $ruleset = (Get-GitHubRepoBaseline -Override @{ Ruleset = @{ AdminCanBypass = $false } }).Ruleset
            $payload = New-GitHubRulesetPayload -Ruleset $ruleset
            @($payload.bypass_actors).Count | Should -Be 0
        }
    }

    It "targets the default branch" {
        InModuleScope DotfilesHelpers {
            $payload = New-GitHubRulesetPayload -Ruleset (Get-GitHubRepoBaseline).Ruleset
            $payload.target | Should -Be 'branch'
            $payload.conditions.ref_name.include | Should -Contain '~DEFAULT_BRANCH'
        }
    }

    It "emits the deletion, non_fast_forward and pull_request rules" {
        InModuleScope DotfilesHelpers {
            $payload = New-GitHubRulesetPayload -Ruleset (Get-GitHubRepoBaseline).Ruleset
            $types = @($payload.rules | ForEach-Object { $_.type })
            $types | Should -Contain 'deletion'
            $types | Should -Contain 'non_fast_forward'
            $types | Should -Contain 'pull_request'
        }
    }

    It "drops rules that the baseline disables" {
        InModuleScope DotfilesHelpers {
            $ruleset = (Get-GitHubRepoBaseline -Override @{
                    Ruleset = @{ BlockDeletion = $false; RequirePullRequest = $false }
                }).Ruleset
            $payload = New-GitHubRulesetPayload -Ruleset $ruleset
            $types = @($payload.rules | ForEach-Object { $_.type })
            $types | Should -Not -Contain 'deletion'
            $types | Should -Not -Contain 'pull_request'
            $types | Should -Contain 'non_fast_forward'
        }
    }

    It "carries the required approving review count into the pull_request rule" {
        InModuleScope DotfilesHelpers {
            $ruleset = (Get-GitHubRepoBaseline -Override @{ Ruleset = @{ RequiredApprovingReviews = 2 } }).Ruleset
            $payload = New-GitHubRulesetPayload -Ruleset $ruleset
            $prRule = @($payload.rules | Where-Object { $_.type -eq 'pull_request' })[0]
            $prRule.parameters.required_approving_review_count | Should -Be 2
        }
    }

    It "serialises to JSON that GitHub's rulesets API accepts" {
        InModuleScope DotfilesHelpers {
            $payload = New-GitHubRulesetPayload -Ruleset (Get-GitHubRepoBaseline).Ruleset
            $json = $payload | ConvertTo-Json -Depth 10
            { $json | ConvertFrom-Json } | Should -Not -Throw
            ($json | ConvertFrom-Json).enforcement | Should -Be 'active'
        }
    }

    Context "updating an existing ruleset" {
        It "preserves rules the baseline does not manage" {
            InModuleScope DotfilesHelpers {
                $existing = [PSCustomObject]@{
                    rules = @(
                        [PSCustomObject]@{ type = 'deletion' }
                        [PSCustomObject]@{
                            type       = 'required_status_checks'
                            parameters = [PSCustomObject]@{
                                required_status_checks = @(
                                    [PSCustomObject]@{ context = 'lint / yamllint'; integration_id = 15368 }
                                )
                            }
                        }
                        [PSCustomObject]@{ type = 'copilot_code_review' }
                    )
                }

                $payload = New-GitHubRulesetPayload -Ruleset (Get-GitHubRepoBaseline).Ruleset -ExistingRuleset $existing
                $types = @($payload.rules | ForEach-Object { $_.type })

                $types | Should -Contain 'required_status_checks'
                $types | Should -Contain 'copilot_code_review'
            }
        }

        It "keeps the configured status check contexts intact" {
            InModuleScope DotfilesHelpers {
                $existing = [PSCustomObject]@{
                    rules = @(
                        [PSCustomObject]@{
                            type       = 'required_status_checks'
                            parameters = [PSCustomObject]@{
                                required_status_checks = @(
                                    [PSCustomObject]@{ context = 'lint / yamllint'; integration_id = 15368 }
                                    [PSCustomObject]@{ context = 'lint / zizmor'; integration_id = 15368 }
                                )
                            }
                        }
                    )
                }

                $payload = New-GitHubRulesetPayload -Ruleset (Get-GitHubRepoBaseline).Ruleset -ExistingRuleset $existing
                $checks = @($payload.rules | Where-Object { $_.type -eq 'required_status_checks' })[0]
                @($checks.parameters.required_status_checks).Count | Should -Be 2
            }
        }

        It "does not duplicate a managed rule that already exists" {
            InModuleScope DotfilesHelpers {
                $existing = [PSCustomObject]@{
                    rules = @(
                        [PSCustomObject]@{ type = 'deletion' }
                        [PSCustomObject]@{ type = 'non_fast_forward' }
                    )
                }

                $payload = New-GitHubRulesetPayload -Ruleset (Get-GitHubRepoBaseline).Ruleset -ExistingRuleset $existing
                @($payload.rules | Where-Object { $_.type -eq 'deletion' }).Count | Should -Be 1
                @($payload.rules | Where-Object { $_.type -eq 'non_fast_forward' }).Count | Should -Be 1
            }
        }

        It "adds the admin bypass without dropping other bypass actors" {
            InModuleScope DotfilesHelpers {
                $existing = [PSCustomObject]@{
                    rules         = @()
                    bypass_actors = @(
                        [PSCustomObject]@{ actor_id = 99; actor_type = 'Integration'; bypass_mode = 'always' }
                    )
                }

                $payload = New-GitHubRulesetPayload -Ruleset (Get-GitHubRepoBaseline).Ruleset -ExistingRuleset $existing
                @($payload.bypass_actors).Count | Should -Be 2
                @($payload.bypass_actors | Where-Object { $_.actor_type -eq 'Integration' }).Count | Should -Be 1
                @($payload.bypass_actors | Where-Object { $_.actor_id -eq 5 }).Count | Should -Be 1
            }
        }

        It "does not add a second admin bypass when one is already present" {
            InModuleScope DotfilesHelpers {
                $existing = [PSCustomObject]@{
                    rules         = @()
                    bypass_actors = @(
                        [PSCustomObject]@{ actor_id = 5; actor_type = 'RepositoryRole'; bypass_mode = 'always' }
                    )
                }

                $payload = New-GitHubRulesetPayload -Ruleset (Get-GitHubRepoBaseline).Ruleset -ExistingRuleset $existing
                @($payload.bypass_actors | Where-Object { $_.actor_id -eq 5 }).Count | Should -Be 1
            }
        }

        It "removes the admin bypass when the baseline disables it" {
            InModuleScope DotfilesHelpers {
                $existing = [PSCustomObject]@{
                    rules         = @()
                    bypass_actors = @(
                        [PSCustomObject]@{ actor_id = 5; actor_type = 'RepositoryRole'; bypass_mode = 'always' }
                        [PSCustomObject]@{ actor_id = 99; actor_type = 'Integration'; bypass_mode = 'always' }
                    )
                }
                $ruleset = (Get-GitHubRepoBaseline -Override @{ Ruleset = @{ AdminCanBypass = $false } }).Ruleset

                $payload = New-GitHubRulesetPayload -Ruleset $ruleset -ExistingRuleset $existing
                @($payload.bypass_actors | Where-Object { $_.actor_id -eq 5 }).Count | Should -Be 0
                @($payload.bypass_actors | Where-Object { $_.actor_type -eq 'Integration' }).Count | Should -Be 1
            }
        }

        It "keeps a custom ref condition rather than retargeting the ruleset" {
            InModuleScope DotfilesHelpers {
                $existing = [PSCustomObject]@{
                    rules      = @()
                    conditions = [PSCustomObject]@{
                        ref_name = [PSCustomObject]@{
                            include = @('refs/heads/release/*')
                            exclude = @('refs/heads/release/legacy')
                        }
                    }
                }

                $payload = New-GitHubRulesetPayload -Ruleset (Get-GitHubRepoBaseline).Ruleset -ExistingRuleset $existing
                $payload.conditions.ref_name.include | Should -Contain 'refs/heads/release/*'
                $payload.conditions.ref_name.exclude | Should -Contain 'refs/heads/release/legacy'
            }
        }

        It "targets the default branch when creating a brand new ruleset" {
            InModuleScope DotfilesHelpers {
                $payload = New-GitHubRulesetPayload -Ruleset (Get-GitHubRepoBaseline).Ruleset
                $payload.conditions.ref_name.include | Should -Contain '~DEFAULT_BRANCH'
            }
        }
    }
}
