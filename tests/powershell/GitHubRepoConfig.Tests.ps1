#Requires -Version 5.1
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Test fixtures build SecureStrings from literal, non-sensitive placeholder values.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'InModuleScope -Parameters values are consumed inside nested Mock scriptblocks, which the analyzer cannot trace.')]
param()
<#
.SYNOPSIS
    Pester tests for the GitHub repository configuration helpers in the
    DotfilesHelpers module.

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
            enforcement   = 'active'
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
            Rulesets  = @([PSCustomObject]@{ id = 42; name = 'Default' })
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
            [object]$Secrets
        )

        switch -Regex ($Endpoint) {
            '/actions/permissions/workflow$' { return $Actions }
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

Describe "ConvertFrom-DotfilesSecureString" -Tag "Unit" {
    It "round-trips a secure string" {
        InModuleScope DotfilesHelpers {
            $secure = ConvertTo-SecureString -String 'hunter2' -AsPlainText -Force
            ConvertFrom-DotfilesSecureString -SecureString $secure | Should -Be 'hunter2'
        }
    }

    It "preserves multi-line PEM content" {
        InModuleScope DotfilesHelpers {
            $pem = "-----BEGIN RSA PRIVATE KEY-----`nMIIabc`n-----END RSA PRIVATE KEY-----"
            $secure = ConvertTo-SecureString -String $pem -AsPlainText -Force
            ConvertFrom-DotfilesSecureString -SecureString $secure | Should -Be $pem
        }
    }
}

Describe "Get-GitHubAppCredential" -Tag "Unit" {
    BeforeAll {
        $script:FakePem = "-----BEGIN RSA PRIVATE KEY-----`nMIIFAKE`n-----END RSA PRIVATE KEY-----"

        # Shape of `op item get --format json` for a well-formed entry.
        $script:ItemJson = @{
            id     = 'abc123'
            title  = 'GitHub Automation App'
            fields = @(
                @{ id = 'app-id'; label = 'app-id'; type = 'STRING' }
                @{ id = 'private-key'; label = 'private-key'; type = 'CONCEALED' }
            )
        } | ConvertTo-Json -Depth 5
    }

    Context "reference parsing" {
        It "splits a well-formed reference into vault, item and field" {
            InModuleScope DotfilesHelpers {
                $parsed = ConvertFrom-OnePasswordReference -Reference 'op://Private/GitHub Automation App/app-id'
                $parsed.Vault | Should -Be 'Private'
                $parsed.Item | Should -Be 'GitHub Automation App'
                $parsed.Field | Should -Be 'app-id'
            }
        }

        It "throws on <_>" -ForEach @(
            'Private/Item/field'
            'op://Private/Item'
            'op://'
            'nonsense'
        ) {
            $reference = $_
            InModuleScope DotfilesHelpers -Parameters @{ Reference = $reference } {
                param($Reference)
                { ConvertFrom-OnePasswordReference -Reference $Reference } |
                    Should -Throw -ExpectedMessage "*not a valid 1Password secret reference*"
            }
        }
    }

    Context "pre-flight checks" {
        It "throws when the op CLI is missing" {
            InModuleScope DotfilesHelpers {
                Mock Get-Command { $null } -ParameterFilter { $Name -eq 'op' }
                { Get-GitHubAppCredential } | Should -Throw -ExpectedMessage "*1Password CLI (op) was not found*"
            }
        }

        It "throws when 1Password is locked or signed out" {
            InModuleScope DotfilesHelpers {
                Mock Get-Command { [PSCustomObject]@{ Name = 'op' } } -ParameterFilter { $Name -eq 'op' }
                Mock Invoke-OnePasswordCli { $null } -ParameterFilter { $Arguments -contains 'whoami' }

                { Get-GitHubAppCredential } | Should -Throw -ExpectedMessage "*not signed in*"
            }
        }

        It "names the missing item and how to create it" {
            InModuleScope DotfilesHelpers {
                Mock Get-Command { [PSCustomObject]@{ Name = 'op' } } -ParameterFilter { $Name -eq 'op' }
                Mock Invoke-OnePasswordCli { 'me@example.com' } -ParameterFilter { $Arguments -contains 'whoami' }
                Mock Invoke-OnePasswordCli { $null } -ParameterFilter { $Arguments -contains 'item' }

                { Get-GitHubAppCredential } |
                    Should -Throw -ExpectedMessage "*'GitHub Automation App' was not found in vault 'Private'*"
            }
        }

        It "suggests an op item create command when the item is missing" {
            InModuleScope DotfilesHelpers {
                Mock Get-Command { [PSCustomObject]@{ Name = 'op' } } -ParameterFilter { $Name -eq 'op' }
                Mock Invoke-OnePasswordCli { 'me@example.com' } -ParameterFilter { $Arguments -contains 'whoami' }
                Mock Invoke-OnePasswordCli { $null } -ParameterFilter { $Arguments -contains 'item' }

                { Get-GitHubAppCredential } | Should -Throw -ExpectedMessage "*op item create*"
            }
        }

        It "names the missing field and lists the ones that do exist" {
            InModuleScope DotfilesHelpers {
                $json = @{
                    fields = @(@{ id = 'username'; label = 'username' })
                } | ConvertTo-Json -Depth 5

                Mock Get-Command { [PSCustomObject]@{ Name = 'op' } } -ParameterFilter { $Name -eq 'op' }
                Mock Invoke-OnePasswordCli { 'me@example.com' } -ParameterFilter { $Arguments -contains 'whoami' }
                Mock Invoke-OnePasswordCli { $json } -ParameterFilter { $Arguments -contains 'item' }

                { Get-GitHubAppCredential } |
                    Should -Throw -ExpectedMessage "*has no field named 'app-id'*username*"
            }
        }

        It "verifies both references before reading any value" {
            InModuleScope DotfilesHelpers -Parameters @{ Json = $script:ItemJson; Pem = $script:FakePem } {
                param($Json, $Pem)
                Mock Get-Command { [PSCustomObject]@{ Name = 'op' } } -ParameterFilter { $Name -eq 'op' }
                Mock Invoke-OnePasswordCli { 'me@example.com' } -ParameterFilter { $Arguments -contains 'whoami' }
                Mock Invoke-OnePasswordCli { $Json } -ParameterFilter { $Arguments -contains 'item' }
                Mock Invoke-OnePasswordCli {
                    if ($Arguments -contains 'op://Private/GitHub Automation App/app-id') { return '123456' }
                    return $Pem
                } -ParameterFilter { $Arguments -contains 'read' }

                $null = Get-GitHubAppCredential

                Should -Invoke Invoke-OnePasswordCli -Times 2 -Exactly -ParameterFilter { $Arguments -contains 'item' }
            }
        }
    }

    Context "reading the credential" {
        It "returns the App ID and the key as a SecureString" {
            InModuleScope DotfilesHelpers -Parameters @{ Json = $script:ItemJson; Pem = $script:FakePem } {
                param($Json, $Pem)
                Mock Get-Command { [PSCustomObject]@{ Name = 'op' } } -ParameterFilter { $Name -eq 'op' }
                Mock Invoke-OnePasswordCli { 'me@example.com' } -ParameterFilter { $Arguments -contains 'whoami' }
                Mock Invoke-OnePasswordCli { $Json } -ParameterFilter { $Arguments -contains 'item' }
                Mock Invoke-OnePasswordCli {
                    if ($Arguments -contains 'op://Private/GitHub Automation App/app-id') { return '123456' }
                    return $Pem
                } -ParameterFilter { $Arguments -contains 'read' }

                $cred = Get-GitHubAppCredential

                $cred.AppId | Should -Be '123456'
                $cred.PrivateKey | Should -BeOfType [System.Security.SecureString]
                ConvertFrom-DotfilesSecureString -SecureString $cred.PrivateKey | Should -Be $Pem
            }
        }

        It "defaults to the Private vault entry when nothing is configured" {
            InModuleScope DotfilesHelpers -Parameters @{ Json = $script:ItemJson; Pem = $script:FakePem } {
                param($Json, $Pem)
                Mock Get-Command { [PSCustomObject]@{ Name = 'op' } } -ParameterFilter { $Name -eq 'op' }
                Mock Invoke-OnePasswordCli { 'me@example.com' } -ParameterFilter { $Arguments -contains 'whoami' }
                Mock Invoke-OnePasswordCli { $Json } -ParameterFilter { $Arguments -contains 'item' }
                Mock Invoke-OnePasswordCli {
                    if ($Arguments -contains 'op://Private/GitHub Automation App/app-id') { return '123456' }
                    return $Pem
                } -ParameterFilter { $Arguments -contains 'read' }

                $null = Get-GitHubAppCredential

                Should -Invoke Invoke-OnePasswordCli -Times 1 -Exactly -ParameterFilter {
                    $Arguments -contains 'read' -and $Arguments -contains 'op://Private/GitHub Automation App/private-key'
                }
            }
        }

        It "honours an explicit reference override" {
            InModuleScope DotfilesHelpers -Parameters @{ Json = $script:ItemJson; Pem = $script:FakePem } {
                param($Json, $Pem)
                Mock Get-Command { [PSCustomObject]@{ Name = 'op' } } -ParameterFilter { $Name -eq 'op' }
                Mock Invoke-OnePasswordCli { 'me@example.com' } -ParameterFilter { $Arguments -contains 'whoami' }
                Mock Invoke-OnePasswordCli { $Json } -ParameterFilter { $Arguments -contains 'item' }
                Mock Invoke-OnePasswordCli {
                    if ($Arguments -contains 'op://Work/Bot/app-id') { return '999' }
                    return $Pem
                } -ParameterFilter { $Arguments -contains 'read' }

                $cred = Get-GitHubAppCredential -AppIdReference 'op://Work/Bot/app-id' -PrivateKeyReference 'op://Work/Bot/private-key'
                $cred.AppId | Should -Be '999'

                # Both overridden references live in the Work vault, so the
                # item check runs once per reference.
                Should -Invoke Invoke-OnePasswordCli -Times 2 -Exactly -ParameterFilter {
                    $Arguments -contains 'item' -and $Arguments -contains 'Work'
                }
            }
        }

        It "rejects an App ID that is not numeric" {
            InModuleScope DotfilesHelpers -Parameters @{ Json = $script:ItemJson; Pem = $script:FakePem } {
                param($Json, $Pem)
                Mock Get-Command { [PSCustomObject]@{ Name = 'op' } } -ParameterFilter { $Name -eq 'op' }
                Mock Invoke-OnePasswordCli { 'me@example.com' } -ParameterFilter { $Arguments -contains 'whoami' }
                Mock Invoke-OnePasswordCli { $Json } -ParameterFilter { $Arguments -contains 'item' }
                Mock Invoke-OnePasswordCli {
                    if ($Arguments -contains 'op://Private/GitHub Automation App/app-id') { return 'Iv1.abc123' }
                    return $Pem
                } -ParameterFilter { $Arguments -contains 'read' }

                { Get-GitHubAppCredential } | Should -Throw -ExpectedMessage "*not a numeric GitHub App ID*"
            }
        }

        It "rejects an empty App ID" {
            InModuleScope DotfilesHelpers -Parameters @{ Json = $script:ItemJson } {
                param($Json)
                Mock Get-Command { [PSCustomObject]@{ Name = 'op' } } -ParameterFilter { $Name -eq 'op' }
                Mock Invoke-OnePasswordCli { 'me@example.com' } -ParameterFilter { $Arguments -contains 'whoami' }
                Mock Invoke-OnePasswordCli { $Json } -ParameterFilter { $Arguments -contains 'item' }
                Mock Invoke-OnePasswordCli { '' } -ParameterFilter { $Arguments -contains 'read' }

                { Get-GitHubAppCredential } | Should -Throw -ExpectedMessage "*is empty*"
            }
        }

        It "rejects a value that is not a PEM private key" {
            InModuleScope DotfilesHelpers -Parameters @{ Json = $script:ItemJson } {
                param($Json)
                Mock Get-Command { [PSCustomObject]@{ Name = 'op' } } -ParameterFilter { $Name -eq 'op' }
                Mock Invoke-OnePasswordCli { 'me@example.com' } -ParameterFilter { $Arguments -contains 'whoami' }
                Mock Invoke-OnePasswordCli { $Json } -ParameterFilter { $Arguments -contains 'item' }
                Mock Invoke-OnePasswordCli {
                    if ($Arguments -contains 'op://Private/GitHub Automation App/app-id') { return '123456' }
                    return 'this is not a key'
                } -ParameterFilter { $Arguments -contains 'read' }

                { Get-GitHubAppCredential } |
                    Should -Throw -ExpectedMessage "*does not look like a PEM-encoded private key*"
            }
        }
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
            $result.IsCompliant | Should -BeTrue
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

        It "does not report drift when the App credential is already present" {
            Mock -ModuleName DotfilesHelpers Get-GitHubRulesetList { script:New-RulesetListEmpty }
            Mock -ModuleName DotfilesHelpers Invoke-GitHubApi {
                script:Get-MockApiResponse -Endpoint $Endpoint `
                    -Repo (script:New-DriftedRepoResponse) `
                    -Actions (script:New-CompliantActionsResponse) `
                    -RulesetDetail $null `
                    -Variables ([PSCustomObject]@{ variables = @([PSCustomObject]@{ name = 'AUTOMATION_APP_ID' }) }) `
                    -Secrets ([PSCustomObject]@{ secrets = @([PSCustomObject]@{ name = 'AUTOMATION_APP_PRIVATE_KEY' }) })
            }

            $result = Get-GitHubRepoConfig -Repository 'drifted' -Check AppCredential
            @($result.Drift | Where-Object { $_.Category -eq 'AppCredential' }).Count | Should -Be 0
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

Describe "GitHubRepoConfig static analysis" -Tag "Unit" {
    BeforeAll {
        $script:SourcePath = Join-Path $script:RepoRoot "home/dot_config/powershell/modules/DotfilesHelpers/Public/GitHubRepoConfig.ps1"
    }

    It "parses without syntax errors" {
        $errors = $null
        $tokens = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:SourcePath, [ref]$tokens, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It "does not hardcode a GitHub token or PAT" {
        $content = Get-Content $script:SourcePath -Raw
        $content | Should -Not -Match 'gh[pousr]_[A-Za-z0-9]{16,}'
    }

    It "routes every gh invocation through the Invoke-GitHubCli wrapper" {
        $content = Get-Content $script:SourcePath -Raw
        # Only the pre-flight check and the wrapper itself may call gh directly.
        ([regex]::Matches($content, '&\s+gh\s')).Count | Should -BeLessOrEqual 3
    }
}
