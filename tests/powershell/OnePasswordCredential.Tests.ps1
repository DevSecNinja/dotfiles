#Requires -Version 5.1
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Test fixtures build SecureStrings from literal, non-sensitive placeholder values.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'InModuleScope -Parameters values are consumed inside nested Mock scriptblocks, which the analyzer cannot trace.')]
param()
<#
.SYNOPSIS
    Pester tests for reading deployment credentials from 1Password.

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

Describe "Get-CloudflareCredential" -Tag "Unit" {
    BeforeAll {
        $script:CfItemJson = @{
            fields = @(
                @{ id = 'account-id'; label = 'account-id' }
                @{ id = 'api-token'; label = 'api-token' }
            )
        } | ConvertTo-Json -Depth 5
        $script:ValidAccount = '0123456789abcdef0123456789abcdef'
    }

    It "returns both values as SecureStrings" {
        InModuleScope DotfilesHelpers -Parameters @{ Json = $script:CfItemJson; Account = $script:ValidAccount } {
            param($Json, $Account)
            Mock Get-Command { [PSCustomObject]@{ Name = 'op' } } -ParameterFilter { $Name -eq 'op' }
            Mock Invoke-OnePasswordCli { 'me@example.com' } -ParameterFilter { $Arguments -contains 'whoami' }
            Mock Invoke-OnePasswordCli { $Json } -ParameterFilter { $Arguments -contains 'item' }
            Mock Invoke-OnePasswordCli {
                if ($Arguments -contains 'op://Private/Cloudflare Pages Deploy/account-id') { return $Account }
                return 'cf-token-value'
            } -ParameterFilter { $Arguments -contains 'read' }

            $cred = Get-CloudflareCredential

            $cred.AccountId | Should -BeOfType [System.Security.SecureString]
            $cred.ApiToken | Should -BeOfType [System.Security.SecureString]
            ConvertFrom-DotfilesSecureString -SecureString $cred.AccountId | Should -Be $Account
            ConvertFrom-DotfilesSecureString -SecureString $cred.ApiToken | Should -Be 'cf-token-value'
        }
    }

    It "rejects an account ID that is not 32 hex characters" {
        InModuleScope DotfilesHelpers -Parameters @{ Json = $script:CfItemJson } {
            param($Json)
            Mock Get-Command { [PSCustomObject]@{ Name = 'op' } } -ParameterFilter { $Name -eq 'op' }
            Mock Invoke-OnePasswordCli { 'me@example.com' } -ParameterFilter { $Arguments -contains 'whoami' }
            Mock Invoke-OnePasswordCli { $Json } -ParameterFilter { $Arguments -contains 'item' }
            Mock Invoke-OnePasswordCli {
                if ($Arguments -contains 'op://Private/Cloudflare Pages Deploy/account-id') { return 'my-project-name' }
                return 'cf-token-value'
            } -ParameterFilter { $Arguments -contains 'read' }

            { Get-CloudflareCredential } | Should -Throw -ExpectedMessage "*not a Cloudflare account ID*"
        }
    }

    It "rejects an empty API token" {
        InModuleScope DotfilesHelpers -Parameters @{ Json = $script:CfItemJson; Account = $script:ValidAccount } {
            param($Json, $Account)
            Mock Get-Command { [PSCustomObject]@{ Name = 'op' } } -ParameterFilter { $Name -eq 'op' }
            Mock Invoke-OnePasswordCli { 'me@example.com' } -ParameterFilter { $Arguments -contains 'whoami' }
            Mock Invoke-OnePasswordCli { $Json } -ParameterFilter { $Arguments -contains 'item' }
            Mock Invoke-OnePasswordCli {
                if ($Arguments -contains 'op://Private/Cloudflare Pages Deploy/account-id') { return $Account }
                return ''
            } -ParameterFilter { $Arguments -contains 'read' }

            { Get-CloudflareCredential } | Should -Throw -ExpectedMessage "*Cloudflare Pages:Edit*"
        }
    }

    It "verifies the 1Password item before reading anything" {
        InModuleScope DotfilesHelpers {
            Mock Get-Command { [PSCustomObject]@{ Name = 'op' } } -ParameterFilter { $Name -eq 'op' }
            Mock Invoke-OnePasswordCli { 'me@example.com' } -ParameterFilter { $Arguments -contains 'whoami' }
            Mock Invoke-OnePasswordCli { $null } -ParameterFilter { $Arguments -contains 'item' }

            { Get-CloudflareCredential } |
                Should -Throw -ExpectedMessage "*'Cloudflare Pages Deploy' was not found in vault 'Private'*"
        }
    }
}

Describe "Hardcoded 1Password references" -Tag "Unit" {
    It "pins <Name> to <Expected>" -ForEach @(
        @{ Name = 'GitHubAppId'; Expected = 'op://Private/GitHub Automation App/app-id' }
        @{ Name = 'GitHubPrivateKey'; Expected = 'op://Private/GitHub Automation App/private-key' }
        @{ Name = 'CloudflareAccountId'; Expected = 'op://Private/Cloudflare Pages Deploy/account-id' }
        @{ Name = 'CloudflareApiToken'; Expected = 'op://Private/Cloudflare Pages Deploy/api-token' }
    ) {
        $key = $Name
        $want = $Expected
        InModuleScope DotfilesHelpers -Parameters @{ Key = $key; Want = $want } {
            param($Key, $Want)
            $script:OnePasswordReferences[$Key] | Should -Be $Want
        }
    }

    It "keeps every reference in valid op://Vault/Item/field form" {
        InModuleScope DotfilesHelpers {
            foreach ($ref in $script:OnePasswordReferences.Values) {
                { ConvertFrom-OnePasswordReference -Reference $ref } | Should -Not -Throw
            }
        }
    }

    It "uses the hardcoded App reference when nothing is configured" {
        InModuleScope DotfilesHelpers {
            $pem = "-----BEGIN RSA PRIVATE KEY-----`nX`n-----END RSA PRIVATE KEY-----"
            $json = @{ fields = @(@{ id = 'app-id'; label = 'app-id' }, @{ id = 'private-key'; label = 'private-key' }) } | ConvertTo-Json -Depth 5

            Mock Get-Command { [PSCustomObject]@{ Name = 'op' } } -ParameterFilter { $Name -eq 'op' }
            Mock Invoke-OnePasswordCli { 'me@example.com' } -ParameterFilter { $Arguments -contains 'whoami' }
            Mock Invoke-OnePasswordCli { $json } -ParameterFilter { $Arguments -contains 'item' }
            Mock Invoke-OnePasswordCli {
                if ($Arguments -contains 'op://Private/GitHub Automation App/app-id') { return '123456' }
                return $pem
            } -ParameterFilter { $Arguments -contains 'read' }

            $null = Get-GitHubAppCredential

            Should -Invoke Invoke-OnePasswordCli -Times 1 -Exactly -ParameterFilter {
                $Arguments -contains 'read' -and $Arguments -contains 'op://Private/GitHub Automation App/private-key'
            }
        }
    }

    It "uses the hardcoded Cloudflare reference when nothing is configured" {
        InModuleScope DotfilesHelpers {
            $json = @{ fields = @(@{ id = 'account-id'; label = 'account-id' }, @{ id = 'api-token'; label = 'api-token' }) } | ConvertTo-Json -Depth 5

            Mock Get-Command { [PSCustomObject]@{ Name = 'op' } } -ParameterFilter { $Name -eq 'op' }
            Mock Invoke-OnePasswordCli { 'me@example.com' } -ParameterFilter { $Arguments -contains 'whoami' }
            Mock Invoke-OnePasswordCli { $json } -ParameterFilter { $Arguments -contains 'item' }
            Mock Invoke-OnePasswordCli {
                if ($Arguments -contains 'op://Private/Cloudflare Pages Deploy/account-id') { return '0123456789abcdef0123456789abcdef' }
                return 'cf-token'
            } -ParameterFilter { $Arguments -contains 'read' }

            $null = Get-CloudflareCredential

            Should -Invoke Invoke-OnePasswordCli -Times 1 -Exactly -ParameterFilter {
                $Arguments -contains 'read' -and $Arguments -contains 'op://Private/Cloudflare Pages Deploy/api-token'
            }
        }
    }
}
