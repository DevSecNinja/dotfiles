# Decide where a credential may safely live, and detect who needs it.
#
# Placement is a security decision, not a preference: an environment secret
# is only safer than a repository secret when the environment is pinned to
# the default branch, and the GitHub Free plan withholds that on private
# repositories. These helpers make that determination explicit so the
# callers can fail closed.
#
# Part of the GitHub repository configuration tooling; see
# GitHubRepoConfig.ps1 for the public commands and docs/github-repo-config.md
# for the user-facing guide.

function Get-GitHubCredentialScope {
    <#
    .SYNOPSIS
        Decide whether a repository's App credential lives in an environment.
    .DESCRIPTION
        Environments, environment secrets and deployment branch policies are
        public-repository-only on the GitHub Free plan. Rather than failing on a
        private repository, callers fall back to repository-level secrets.

        The fallback loses nothing in practice: an environment secret is only
        safer than a repository secret because of the deployment branch policy
        pinning it to the default branch, and that policy is exactly what the
        Free plan withholds on private repositories.
    .PARAMETER Repository
        Repository in 'owner/name' form.
    .PARAMETER Environment
        Desired environment name. Empty means repository-level by choice.
    .PARAMETER Visibility
        Repository visibility as reported by the API.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $false)][string]$Environment,
        [Parameter(Mandatory = $true)][string]$Visibility
    )

    if ([string]::IsNullOrWhiteSpace($Environment)) {
        return [PSCustomObject]@{ UseEnvironment = $false; Environment = ''; Reason = 'baseline requests repository-level credentials' }
    }

    if ($Visibility -ne 'public') {
        return [PSCustomObject]@{
            UseEnvironment = $false
            Environment    = $Environment
            Reason         = "environments are public-repository-only on the GitHub Free plan; $Repository is $Visibility"
        }
    }

    return [PSCustomObject]@{ UseEnvironment = $true; Environment = $Environment; Reason = '' }
}

function Get-GitHubEnvironmentState {
    <#
    .SYNOPSIS
        Report whether an environment exists and how its branch policy is set.
    .DESCRIPTION
        Distinguishes "environment absent" from "environment present but
        unrestricted", because only the second is a security gap worth naming:
        an environment without a deployment branch policy grants no more
        protection than a repository secret.
    .PARAMETER Repository
        Repository in 'owner/name' form.
    .PARAMETER Environment
        Environment name.
    .PARAMETER DefaultBranch
        Branch the environment should be pinned to.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$Environment,
        [Parameter(Mandatory = $false)][AllowEmptyString()][string]$DefaultBranch
    )

    $env = Invoke-GitHubApi -Endpoint "repos/$Repository/environments/$Environment" -AllowFailure
    if ($null -eq $env) {
        return [PSCustomObject]@{ Exists = $false; PinnedToDefaultBranch = $false; ExtraBranchPolicies = @() }
    }

    # Pinned means the default branch and *nothing else*. A policy list of
    # main + feature/* would still let a workflow on an attacker-controlled
    # branch read the secret, so merely containing the default branch is not
    # enough - the extra policies are reported so remediation can remove them.
    $pinned = $false
    $extraPolicies = @()
    if ($null -ne $env.deployment_branch_policy -and $env.deployment_branch_policy.custom_branch_policies) {
        $policies = Invoke-GitHubApi -Endpoint "repos/$Repository/environments/$Environment/deployment-branch-policies" -AllowFailure
        if ($null -ne $policies -and -not [string]::IsNullOrWhiteSpace($DefaultBranch)) {
            $branchPolicies = @($policies.branch_policies)
            $matching = @($branchPolicies | Where-Object { $_.name -eq $DefaultBranch })
            $extraPolicies = @($branchPolicies | Where-Object { $_.name -ne $DefaultBranch })
            $pinned = ($matching.Count -eq 1) -and ($extraPolicies.Count -eq 0)
        }
    }

    return [PSCustomObject]@{
        Exists                = $true
        PinnedToDefaultBranch = $pinned
        ExtraBranchPolicies   = $extraPolicies
    }
}

function Test-GitHubPagesWorkflow {
    <#
    .SYNOPSIS
        Does this repository call the central reusable Pages workflow?
    .DESCRIPTION
        Cloudflare credentials are only meaningful in repositories that deploy
        through DevSecNinja/.github's reusable pages workflow, so the audit is
        gated on the caller actually being present rather than on the secret
        merely being absent.

        Scans .github/workflows for a file referencing the reusable workflow.
        Files whose name mentions "pages" are checked first and the scan stops
        at the first hit, so the conventional layout costs two API calls.
    .PARAMETER Repository
        Repository in 'owner/name' form.
    .PARAMETER Marker
        Substring identifying the reusable workflow reference.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)][string]$Repository,

        [Parameter(Mandatory = $false)]
        [string]$Marker = 'DevSecNinja/.github/.github/workflows/pages.yml@'
    )

    $listing = Invoke-GitHubApi -Endpoint "repos/$Repository/contents/.github/workflows" -AllowFailure
    if ($null -eq $listing) { return $false }

    $candidates = @($listing | Where-Object { $_.type -eq 'file' -and $_.name -match '\.ya?ml$' })
    if ($candidates.Count -eq 0) { return $false }

    # Conventional names first so the common case exits after one fetch.
    $ordered = @($candidates | Sort-Object @{ Expression = { $_.name -notmatch 'page' } }, Name)

    foreach ($file in $ordered) {
        $content = Invoke-GitHubApi -Endpoint "repos/$Repository/contents/$($file.path)" -AllowFailure
        if ($null -eq $content -or [string]::IsNullOrWhiteSpace($content.content)) { continue }

        try {
            $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(($content.content -replace '\s', '')))
        }
        catch {
            continue
        }

        if ($decoded -like "*$Marker*") {
            Write-Verbose "$Repository calls the central Pages workflow via $($file.path)"
            return $true
        }
    }

    return $false
}

function Get-GitHubReleaseEvidence {
    <#
    .SYNOPSIS
        Explain why a repository counts as one that publishes releases.
    .DESCRIPTION
        The Automation App credential is needed by repositories that cut
        releases through the shared release-please workflow. A repository
        qualifies when it has a root release-please-config.json, or at least
        one published release whose tag looks like a version (v1.2, 1.2.3).

        Data or state snapshots stored as GitHub releases - tags such as
        db-2026-01-01 or news-state - do not look like versions, so they do
        not qualify a repository on their own.

        The config file is checked first because it is one cheap call and is
        conclusive. Releases are then read a page of 100 at a time, newest
        first, stopping at the first versioned one, so a repository whose
        version release sits behind many data releases still qualifies.
    .PARAMETER Repository
        Repository in 'owner/name' form.
    .PARAMETER VersionPattern
        Regex a release tag must match to count as a version release.
    .OUTPUTS
        String describing the evidence, or $null when there is none. Throws
        when the release list cannot be read, so an API, network or rate-limit
        failure is never mistaken for "no releases".
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][string]$Repository,

        [Parameter(Mandatory = $false)]
        [string]$VersionPattern = '^v?\d+\.\d+'
    )

    $config = Invoke-GitHubApi -Endpoint "repos/$Repository/contents/release-please-config.json" -AllowFailure
    if ($null -ne $config) {
        return 'release-please-config.json'
    }

    $pageSize = 100
    for ($page = 1; ; $page++) {
        $releases = Invoke-GitHubApi -Endpoint "repos/$Repository/releases?per_page=$pageSize&page=$page" -AllowFailure
        if ($null -eq $releases) {
            throw "Could not list releases for $Repository (page $page). Check the gh token, network access and API rate limit."
        }
        $releases = @($releases)

        $versioned = @($releases | Where-Object {
                $null -ne $_ -and -not $_.draft -and [string]$_.tag_name -match $VersionPattern
            })
        if ($versioned.Count -gt 0) {
            return "release $($versioned[0].tag_name)"
        }
        if ($releases.Count -lt $pageSize) {
            return $null
        }
    }
}

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDHNNJ7VqdowaOo
# BRSYcdeyWho5qPUWD7PqG1+H+EZDPqCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCC+CGjxPEAMDfFRMf17Cr3Y6PqT6l21srSYadSEHJxpBTANBgkqhkiG
# 9w0BAQEFAASCAgBIHvwzeE0hzXCo5IcjCwaU39KYDUBNGlXMuy82KKg89M1u3S2z
# xYRgWizh7J904swVZePu4wO00xqOMMGgrQIpWmwI861fByBRKiwlVKFWpjpO3igb
# T1bUbFc6gGGesRXIDWE4l7woft0JbVX9d8RMxmT9VhmuUewvMlwJvjaVJEbXhMM6
# wkHoClOobMW+S48/qHxUZ5a+YEVAALfdTCNW8IRjdrF3llx2Oqfv/ScDg7hpkoYt
# rGaa28dqdhgeHFVqx78fxtrJHtkz8TLYBnUgSK6f49XGHh5cVgdUqwn33eHgL34G
# JDfcb0TUCrKwwXLm5gv4wSmN4c20A7n9Jj0Q2xlDWY91nNFGokzhnfafLn6s9Uiv
# bpwy66yrlhKA+KGTHpIs/TPBRk4xrDyupudcvXfmDpcXS/qQ8T3GoBUV8SOt8gxo
# Xlron2NHtFTBSM4NVKJQvBFNbYKpl076oIUVHjkXoKrNJyOdy+vqM8B7FF1dTZtG
# faEAOANDFYH3+dRGCntvojxJWZMu2chKbDtPauAmNI6WbQxmEB9qf53o1adZVBrW
# LFwFLaxp2IIUylUu7wqAhgg/E1y4WX/PkMOiaCKzeoDx9dk1brY7szDR1mNRJs1H
# 9MF/PWBP39PiW3A7N01nw6GMYRjVXOBs7he42ECMDTLlBDNrcq3/GyPILaGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAhP3DNPfkVO
# 28MPj/mSGDUwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjExMTQxMTU0MjJaMC8GCSqGSIb3DQEJBDEi
# BCD5as4QueR6Fxhhwm6502ccDbw5aY6tx+6aVmgMxwgMXjANBgkqhkiG9w0BAQEF
# AASCAgA/oAeF2FaVCxeDTBdUvPr/LDZIEF3G2An7qlWzUaS+Q9cRESqi6xHkxt/N
# xE4haSW7v+SC40qpEZICx2I1KYTHxi4aVMEwnTZSrS6Ry8CJZefDH4p5vuKlCxmt
# CP1dnwd1/yAZRx/zbBHxD1Cj9AeKDv3z9pFIuJM4kxTS3G0EWjRFFObV1YE3/dU1
# pmryUc1NbENaYD/j7HAY0+Z4sAqGQYQm6sAwOeKFqoZwXQn0gNWMKD7SjeIZvNIK
# qqqr1wmXK4sb1byUOwyMfFMflutJIAN+v6a+BFSIL+7QnBS0IV2NhxxeGSG474rm
# zWx/7s1dR0MqB1i45NceTk1ojo0W+Hz1HC0mk+bgbcM5sSHnXxqLyFjebxkCJEMQ
# 5TtLFnn6F1n8A0tkyJTLyxhbOtHXBIsdxlfeVTCqH6RoAzyhIwjwGcgIcD0mfOp+
# r31xrIzjqURCgErWu2kwod6QqxiTenSipTaPIYQtdypHKR26pbqfJX1uvRUxr0zm
# Ia43Dnn0PiRYWmhZP5u3i/5oonkfYdv/0RdVve6PGZwfx0Pa/eoz5mARqvhE5We+
# yG1FMzx9quSAl/R6pPyV7r1xANh6FYh0FdFEWRe9cteHNuEP5vAR3gM59ptdaFHt
# G7Uul8INKGFA8AQH5Xn1P1oT/uBB2zvcRpE+dBMVXOIiT/dPyQ==
# SIG # End signature block
