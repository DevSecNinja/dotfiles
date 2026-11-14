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

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBN9cFaVRcXjSZJ
# iM0tmTtIWmzGbR9MWOm2GOI0Pd13FaCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCDvOR0Km4fH574gm2vyR64B7iUtKfKAU5y3CiROvwTkWzANBgkqhkiG
# 9w0BAQEFAASCAgB5TnbEh0JVNyf6KVbV5bBHA1KiT9dBqdLT9hHKbo89/cm3BAC9
# uR96/ua88hx6kr9b1hEdP2VWYf6okI7n2P+rtSFyqjfXzucernCGsm6UHJbD+C28
# Pk4CeUrtKMtoZksyud6NmOMfB4VNlFwIEyc2/evDJIrT3W8p73iah+aLQfOA0F1J
# NWu+COBW0+6g9xVXVXMQFVqgkRYX+0lRrngyjsLCCqpEJwKn9LwTF9cGdDp+jjCn
# ZznCWaPoQQyXIBnXELr3i4VAr7L1sNegMiALPUypi1qycfG710OhkRsUixPrxnQB
# KfvRIvpoNuF8ftMIeUxbR39Atlns3t9mVHML9t/uwPS3sVwydxFNTVhQzJk3j+SZ
# tAsB6LVrQbhw1JX9mCXpYcNwZGewvCyWFacVOX9egqyPBB0x2suqmd7wNJIRM10C
# bENvt8B8u7Mhclh5tdQlAlrvg5t29qlQ0rKWoOOnpWKqRxxXxgCA/RlcsJq6Djnd
# 15C5+GiG3tDM8mHPwfQJGfhThVpvJSp/VrqE7gqhHvOKxj2mdrC/F42v4YYB3gXg
# krtVYqYxf/H4UYRsVbFGDT562pbGkZVoHkA4LZ8qRPULKrLPYuJnz4aBpacCOwSk
# R+FSuhpERLPOWkswrvR68HG1v3u8UfiAs+JPSyY261kz2ciQOow3JXBDPKGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAhP3DNPfkVO
# 28MPj/mSGDUwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjExMTQxMTU0MjRaMC8GCSqGSIb3DQEJBDEi
# BCC3QduOkqpAOlzvZ3829mxOtzuNa9Q0gBUVX8DEEjqwJTANBgkqhkiG9w0BAQEF
# AASCAgBv53dCAOTwTJzHnsOrWzR5KmBDBsuPHCdZ3wuZsJuoCM5OElvAMK/Ib0KL
# 8pd+tevrbYuohd5gXEYR5zESNIjWX1v8vzZeZWPoZTsKz/+pvu9jGIVVuxih0h7g
# sUFeTbFBOVboJUwBrlZW6iTPY1LSiBo9CNSSn2FEH3VgixCI3PXb0BUKbvCOqJD0
# gHFJgdq8+SMyDGhHqMeLqnQt40CeE2PkcNjGmCIyb4QE4c5OeKeVQTP728x5HhW2
# izfZFX0KI3+U6NpxiwBid/q02MBUsu7n+pWGmOSBJ/k5fGqXIE15fAAws8qs3BJL
# jJZ3wuo7efYXoc9hgDEIoxlXfte63UK42bvyJNlhhW3uGFuHohA91RK0sJzyH3/1
# SM4ycLcS8QYIkcRSM8YdybfUFqCiAgMV20cyDeuKxWPAsIMz4N7HN7SR8S7HBQGz
# uauX3pCfAw/I6sIaHDKIAW7MhxeB/qgQCkgx4wB81KMl6QXnfhWQUmqwrzPCFXtj
# W0E3EKvgIR1vn6cWGEIghQPcWNGvgYJjMNL3oYWw7N5bVNBcCswFaT/DECH66ElF
# zeKcLI6W93A3U4KT2Wn1wDsAEPRa2KC4AHzC5iZpQQMdhWJNRsIZnmmLh6EqmyG5
# mumqo3yDE5SqD04oxOotR9PibFzf266/W9u3XDt2qvTaswR5rQ==
# SIG # End signature block
