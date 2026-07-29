#Requires -Version 5.1
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Test fixtures build SecureStrings from literal, non-sensitive placeholder values.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'InModuleScope -Parameters values are consumed inside nested Mock scriptblocks, which the analyzer cannot trace.')]
param()
<#
.SYNOPSIS
    Pester tests for the GitHub CLI transport helpers.

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

Describe "Resolve-GitHubRepoName" -Tag "Unit" {
    It "qualifies a bare name with the owner" {
        InModuleScope DotfilesHelpers {
            Resolve-GitHubRepoName -Repository 'docker' -Owner 'DevSecNinja' | Should -Be 'DevSecNinja/docker'
        }
    }

    It "passes an already-qualified name through" {
        InModuleScope DotfilesHelpers {
            Resolve-GitHubRepoName -Repository 'someone/docker' -Owner 'DevSecNinja' | Should -Be 'someone/docker'
        }
    }

    It "accepts a full GitHub URL" {
        InModuleScope DotfilesHelpers {
            Resolve-GitHubRepoName -Repository 'https://github.com/DevSecNinja/docker' | Should -Be 'DevSecNinja/docker'
        }
    }

    It "strips a trailing .git suffix" {
        InModuleScope DotfilesHelpers {
            Resolve-GitHubRepoName -Repository 'https://github.com/DevSecNinja/docker.git' | Should -Be 'DevSecNinja/docker'
        }
    }

    It "throws for a bare name with no owner" {
        InModuleScope DotfilesHelpers {
            { Resolve-GitHubRepoName -Repository 'docker' } | Should -Throw -ExpectedMessage "*has no owner*"
        }
    }

    It "throws for a malformed reference" {
        InModuleScope DotfilesHelpers {
            { Resolve-GitHubRepoName -Repository 'a/b/c' -Owner 'x' } |
                Should -Throw -ExpectedMessage "*not a valid repository reference*"
        }
    }
}

Describe "Invoke-GitHubApi response shaping" -Tag "Unit" {
    It "returns a JSON list as a usable array, not nested one level deeper" {
        InModuleScope DotfilesHelpers {
            Mock Invoke-GitHubCli { '[{"id":1},{"id":2},{"id":3}]' }

            $result = Invoke-GitHubApi -Endpoint 'repos/o/r/rulesets'

            @($result).Count | Should -Be 3
            $result[0].id | Should -Be 1
            $result[2].id | Should -Be 3
        }
    }

    It "preserves an empty JSON list as an empty array rather than collapsing to null" {
        InModuleScope DotfilesHelpers {
            Mock Invoke-GitHubCli { '[]' }

            $result = Invoke-GitHubApi -Endpoint 'repos/o/r/rulesets'

            # Deliberately not -BeNullOrEmpty: an empty array *is* empty by that
            # assertion, but it must stay distinguishable from $null, which is
            # what a failed call returns.
            $null -eq $result | Should -BeFalse -Because 'an empty list must not be confused with a failed call'
            @($result).Count | Should -Be 0
        }
    }

    It "returns a single-element JSON list as an array, not a bare object" {
        InModuleScope DotfilesHelpers {
            Mock Invoke-GitHubCli { '[{"id":42,"name":"Default"}]' }

            $result = Invoke-GitHubApi -Endpoint 'repos/o/r/rulesets'

            @($result).Count | Should -Be 1
            $result[0].name | Should -Be 'Default'
        }
    }

    It "returns a JSON object unwrapped" {
        InModuleScope DotfilesHelpers {
            Mock Invoke-GitHubCli { '{"name":"docker","archived":false}' }

            $result = Invoke-GitHubApi -Endpoint 'repos/o/r'

            $result.name | Should -Be 'docker'
            $result | Should -Not -BeOfType [System.Object[]]
        }
    }

    It "returns null when the call fails under -AllowFailure" {
        InModuleScope DotfilesHelpers {
            Mock Invoke-GitHubCli { $null }

            $result = Invoke-GitHubApi -Endpoint 'repos/o/r/rulesets' -AllowFailure

            $null -eq $result | Should -BeTrue
        }
    }

    It "sends a request body on stdin rather than as arguments" {
        InModuleScope DotfilesHelpers {
            Mock Invoke-GitHubCli { '{}' }

            $null = Invoke-GitHubApi -Endpoint 'repos/o/r' -Method PATCH -Body @{ has_wiki = $false }

            Should -Invoke Invoke-GitHubCli -Times 1 -Exactly -ParameterFilter {
                $StdIn -match '"has_wiki"' -and $Arguments -contains '--input'
            }
        }
    }

    It "preserves booleans as real JSON booleans in the body" {
        InModuleScope DotfilesHelpers {
            Mock Invoke-GitHubCli { '{}' }

            $null = Invoke-GitHubApi -Endpoint 'repos/o/r' -Method PATCH -Body @{ has_wiki = $false }

            Should -Invoke Invoke-GitHubCli -Times 1 -Exactly -ParameterFilter {
                ($StdIn | ConvertFrom-Json).has_wiki -eq $false -and $StdIn -notmatch '"False"'
            }
        }
    }

    It "throws on a malformed response" {
        InModuleScope DotfilesHelpers {
            Mock Invoke-GitHubCli { 'not json at all' }

            { Invoke-GitHubApi -Endpoint 'repos/o/r' } | Should -Throw -ExpectedMessage "*as JSON*"
        }
    }
}
