#Requires -Version 5.1
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Test fixtures build SecureStrings from literal, non-sensitive placeholder values.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'InModuleScope -Parameters values are consumed inside nested Mock scriptblocks, which the analyzer cannot trace.')]
param()
<#
.SYNOPSIS
    Pester tests for credential placement and Pages-workflow detection.

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

Describe "Get-GitHubCredentialScope" -Tag "Unit" {
    It "uses the environment on a public repository" {
        InModuleScope DotfilesHelpers {
            $scope = Get-GitHubCredentialScope -Repository 'o/r' -Environment 'production' -Visibility 'public'
            $scope.UseEnvironment | Should -BeTrue
            $scope.Environment | Should -Be 'production'
        }
    }

    It "falls back to repository level on a <_> repository" -ForEach @('private', 'internal') {
        $visibility = $_
        InModuleScope DotfilesHelpers -Parameters @{ Visibility = $visibility } {
            param($Visibility)
            $scope = Get-GitHubCredentialScope -Repository 'o/r' -Environment 'production' -Visibility $Visibility
            $scope.UseEnvironment | Should -BeFalse
            $scope.Reason | Should -Match 'Free plan'
        }
    }

    It "stays at repository level when the baseline asks for no environment" {
        InModuleScope DotfilesHelpers {
            $scope = Get-GitHubCredentialScope -Repository 'o/r' -Environment '' -Visibility 'public'
            $scope.UseEnvironment | Should -BeFalse
            $scope.Reason | Should -Match 'baseline'
        }
    }
}

Describe "Get-GitHubEnvironmentState" -Tag "Unit" {
    It "reports an absent environment" {
        InModuleScope DotfilesHelpers {
            Mock Invoke-GitHubApi { $null }
            $state = Get-GitHubEnvironmentState -Repository 'o/r' -Environment 'production' -DefaultBranch 'main'
            $state.Exists | Should -BeFalse
            $state.PinnedToDefaultBranch | Should -BeFalse
        }
    }

    It "reports an environment with no branch policy as unpinned" {
        InModuleScope DotfilesHelpers {
            Mock Invoke-GitHubApi { [PSCustomObject]@{ name = 'production'; deployment_branch_policy = $null } }
            $state = Get-GitHubEnvironmentState -Repository 'o/r' -Environment 'production' -DefaultBranch 'main'
            $state.Exists | Should -BeTrue
            $state.PinnedToDefaultBranch | Should -BeFalse
        }
    }

    It "reports an environment pinned to the default branch" {
        InModuleScope DotfilesHelpers {
            Mock Invoke-GitHubApi {
                if ($Endpoint -like '*deployment-branch-policies*') {
                    return [PSCustomObject]@{ branch_policies = @([PSCustomObject]@{ name = 'main' }) }
                }
                return [PSCustomObject]@{ name = 'production'; deployment_branch_policy = [PSCustomObject]@{ custom_branch_policies = $true } }
            }
            $state = Get-GitHubEnvironmentState -Repository 'o/r' -Environment 'production' -DefaultBranch 'main'
            $state.PinnedToDefaultBranch | Should -BeTrue
        }
    }

    It "does not treat a policy for another branch as pinned" {
        InModuleScope DotfilesHelpers {
            Mock Invoke-GitHubApi {
                if ($Endpoint -like '*deployment-branch-policies*') {
                    return [PSCustomObject]@{ branch_policies = @([PSCustomObject]@{ name = 'develop' }) }
                }
                return [PSCustomObject]@{ name = 'production'; deployment_branch_policy = [PSCustomObject]@{ custom_branch_policies = $true } }
            }
            $state = Get-GitHubEnvironmentState -Repository 'o/r' -Environment 'production' -DefaultBranch 'main'
            $state.PinnedToDefaultBranch | Should -BeFalse
        }
    }

    It "treats protected_branches-only policy as not pinned to the default branch" {
        InModuleScope DotfilesHelpers {
            Mock Invoke-GitHubApi {
                [PSCustomObject]@{ name = 'production'; deployment_branch_policy = [PSCustomObject]@{ custom_branch_policies = $false; protected_branches = $true } }
            }
            $state = Get-GitHubEnvironmentState -Repository 'o/r' -Environment 'production' -DefaultBranch 'main'
            $state.PinnedToDefaultBranch | Should -BeFalse
        }
    }
}

Describe "Test-GitHubPagesWorkflow" -Tag "Unit" {
    BeforeAll {
        $script:PagesCaller = @'
jobs:
  pages:
    uses: DevSecNinja/.github/.github/workflows/pages.yml@abc123 # v1.9.0
'@
        $script:OtherWorkflow = @'
jobs:
  lint:
    uses: DevSecNinja/.github/.github/workflows/lint.yml@abc123
'@
    }

    It "detects a repository that calls the central Pages workflow" {
        InModuleScope DotfilesHelpers -Parameters @{ Yaml = $script:PagesCaller } {
            param($Yaml)
            Mock Invoke-GitHubApi {
                if ($Endpoint -like '*/workflows') {
                    return @([PSCustomObject]@{ type = 'file'; name = 'pages.yml'; path = '.github/workflows/pages.yml' })
                }
                return [PSCustomObject]@{ content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Yaml)) }
            }

            Test-GitHubPagesWorkflow -Repository 'o/r' | Should -BeTrue
        }
    }

    It "returns false when no workflow references it" {
        InModuleScope DotfilesHelpers -Parameters @{ Yaml = $script:OtherWorkflow } {
            param($Yaml)
            Mock Invoke-GitHubApi {
                if ($Endpoint -like '*/workflows') {
                    return @([PSCustomObject]@{ type = 'file'; name = 'lint.yml'; path = '.github/workflows/lint.yml' })
                }
                return [PSCustomObject]@{ content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Yaml)) }
            }

            Test-GitHubPagesWorkflow -Repository 'o/r' | Should -BeFalse
        }
    }

    It "returns false when the repository has no workflows directory" {
        InModuleScope DotfilesHelpers {
            Mock Invoke-GitHubApi { $null }
            Test-GitHubPagesWorkflow -Repository 'o/r' | Should -BeFalse
        }
    }

    It "finds the caller under a non-conventional file name" {
        InModuleScope DotfilesHelpers -Parameters @{ Yaml = $script:PagesCaller; Other = $script:OtherWorkflow } {
            param($Yaml, $Other)
            Mock Invoke-GitHubApi {
                if ($Endpoint -like '*/workflows') {
                    return @(
                        [PSCustomObject]@{ type = 'file'; name = 'lint.yml'; path = '.github/workflows/lint.yml' }
                        [PSCustomObject]@{ type = 'file'; name = 'site.yml'; path = '.github/workflows/site.yml' }
                    )
                }
                if ($Endpoint -like '*site.yml') {
                    return [PSCustomObject]@{ content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Yaml)) }
                }
                return [PSCustomObject]@{ content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Other)) }
            }

            Test-GitHubPagesWorkflow -Repository 'o/r' | Should -BeTrue
        }
    }

    It "checks pages-named files first so the common case costs one fetch" {
        InModuleScope DotfilesHelpers -Parameters @{ Yaml = $script:PagesCaller } {
            param($Yaml)
            Mock Invoke-GitHubApi {
                if ($Endpoint -like '*/workflows') {
                    return @(
                        [PSCustomObject]@{ type = 'file'; name = 'aaa.yml'; path = '.github/workflows/aaa.yml' }
                        [PSCustomObject]@{ type = 'file'; name = 'bbb.yml'; path = '.github/workflows/bbb.yml' }
                        [PSCustomObject]@{ type = 'file'; name = 'pages.yml'; path = '.github/workflows/pages.yml' }
                    )
                }
                return [PSCustomObject]@{ content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Yaml)) }
            }

            $null = Test-GitHubPagesWorkflow -Repository 'o/r'

            # Listing plus exactly one file fetch: pages.yml was tried first.
            Should -Invoke Invoke-GitHubApi -Times 2 -Exactly
        }
    }

    It "ignores directories in the workflows listing" {
        InModuleScope DotfilesHelpers {
            Mock Invoke-GitHubApi {
                if ($Endpoint -like '*/workflows') {
                    return @([PSCustomObject]@{ type = 'dir'; name = 'pages'; path = '.github/workflows/pages' })
                }
                throw 'should not fetch a directory'
            }

            Test-GitHubPagesWorkflow -Repository 'o/r' | Should -BeFalse
        }
    }
}
