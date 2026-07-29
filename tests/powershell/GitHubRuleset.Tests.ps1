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

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBb25Gwz1cScU4Z
# ywalwEmE9I4p3Vxc5eRPEKtSNGWQWKCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCBeAPQADJRJNHGBw1vpXpnTIHK1LtmPtE8bAWTELDBBIjANBgkqhkiG
# 9w0BAQEFAASCAgCPXWEBQnGozpHRV19tO4PvGyWNnjcr6dTue1NovwQn7MrEiTsn
# DDjqauNuf1UeEGAIDNB39hWjX4lQYiqo4pSwbENCwU7NDAY7+9sc0cm3U7D3P91+
# ZwqmE5aY3IWKQqrKSbZKk7c572O6CAyNSmxnO6CIBzNhtBqMedMOEkLhjE4CDSOf
# ttyGFLJE1liO+JNvvQSkQCShi9zooU3M5omLQArSTVM0Bv2K3wksYrkAJkAhC+p4
# /3T3UKOv8CBskiekqFdd576rwDDs31l/NNzAtdByARLjjfOjxBJf/iNwwfW6ewM+
# br/A1M8YQSLI/DT19Dq+YlpzwhwNrFn2hRvcb9Lt5bp+HAcZfASCKjHdZmKVyCoQ
# glEBx5bA5P0rkqZ7t+SqbEGh41+2Dit7m2vR080IhW9cz38tk8vJg4qoJUXmVRLO
# 88IsRK1bBhxssOpnsF2/neqpWOKTB25Ei9ReTBNoL32En6t3uSVwDX0FzoIX95pX
# F3AUDKgV5wp+rNbywx3YVEnnf484UcaF2cEcqDPa7Rm8lCERTwLuraqKb0MVHq/v
# 0dPxNXOcvdT5UUdF0zecxt+SDCA9riWUawqLWAdYVk7hnlJ6y6kAIQJjFcxzgJ/D
# hXe7Z4oJZ76zmPEgPz0vMhf9rgW3DqOaK2wp+fLE34v1e6w7R+kuYnR7c6GCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA3MjkwODE4MDdaMC8GCSqGSIb3DQEJBDEi
# BCAuZFlL8mZ7DvIpEbo15gxleRE34giTthFbU3uPckDl0TANBgkqhkiG9w0BAQEF
# AASCAgCvyHcA9zE8B8mxthecxlD5DPa+40dNUUkGgq4fG8tRDyFU74hk7/9kE1Jd
# pDunbDZU6GsmHKIOfo1vbxkTMhtqZbzzODu6h6RmGS8MqypIq4vZ/zo4kJKdPB2l
# VyZysLFyqBntYpd0S4loY7OoGLxU4P9PeZA1Aa2z7eLbYDSBK9H1LJkaxw5Wue33
# EnHbQmzwwi32kY2oxoGOKTzL73dHOYMXHjxSUVqz6Ct8eW/vsOg69rT7LGFT88nm
# lFBkGpJr5NuZtPl5DkTg/24zjtV7gyj8/E1uHoVJUhXJbYrAIAI5IQoYCmMuak+E
# 6mUuwL82ILpggm+2mUWQQ/x2Yc3UtbUKr9s/wu866+Jyp51ZR4SZlxa8Vbfhe7Zc
# py6vFXgvfowAAzZUWQePXKWauZ9Cmt5/0N4NDfkS0ZvGm08rVt+xdBgs3U9XViPY
# pOLqTy6GQ9u4Jx+ZmZPMKHzlOTzUPvx8iD+unwFF4ugHDAZmZdwYlcnAFIUUWO2A
# IGDXjpjYnIVYHpfmz2e6gAc/kp4DVS9E8c44To1dzwsSPu4P67gqxc0AwJqocx5X
# 0YtLExlG5ZLN+7GoRuwB8tJAd8cVf8KxYbzWJkPcmCPAyLdTPYpxfAZ5J8D0bGgI
# A9RCBtck2Mi/PlK8CFK9GhcA81x4GQsiYIUIl/Ee5lmf/IsT2Q==
# SIG # End signature block
