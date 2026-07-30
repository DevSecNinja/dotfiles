#Requires -Version 7.0
<#
.SYNOPSIS
    Pester tests for the Windows fastfetch status script.

.DESCRIPTION
    Covers home/dot_config/fastfetch/status.ps1, which caches the winget update
    count so the fastfetch banner can render it without ever querying winget on
    the login path, plus the chezmoi wiring that ships it (config template,
    .chezmoiignore and the profile's background refresh).

.NOTES
    winget itself is never invoked: the collector functions are dot-sourced and
    mocked so the tests stay fast and offline.
#>

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:FastfetchDir = Join-Path $script:RepoRoot "home\dot_config\fastfetch"
    $script:StatusScript = Join-Path $script:FastfetchDir "status.ps1"
    $script:ConfigTemplate = Join-Path $script:FastfetchDir "config.jsonc.tmpl"
    $script:ProfilePath = Join-Path $script:RepoRoot "home\dot_config\powershell\profile.ps1"

    # Isolated cache so tests never touch the real %LOCALAPPDATA% cache.
    $script:OriginalCacheDir = $env:FASTFETCH_STATUS_CACHE_DIR
    $script:OriginalTtl = $env:FASTFETCH_STATUS_TTL
    $script:OriginalDisable = $env:FASTFETCH_STATUS_DISABLE
    $script:TestCacheDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ff-status-" + [guid]::NewGuid().ToString('N'))
    $env:FASTFETCH_STATUS_CACHE_DIR = $script:TestCacheDir

    # Dot-sourcing loads the functions without dispatching a command.
    . $script:StatusScript
}

AfterAll {
    $env:FASTFETCH_STATUS_CACHE_DIR = $script:OriginalCacheDir
    $env:FASTFETCH_STATUS_TTL = $script:OriginalTtl
    $env:FASTFETCH_STATUS_DISABLE = $script:OriginalDisable
    if (Test-Path -LiteralPath $script:TestCacheDir) {
        Remove-Item -LiteralPath $script:TestCacheDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "fastfetch status.ps1 file" {
    It "should exist" {
        $script:StatusScript | Should -Exist
    }

    It "should have valid PowerShell syntax" {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:StatusScript, [ref]$null, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It "should stay ASCII-only so unsigned loads under Windows PowerShell 5.1 do not corrupt strings" {
        $bytes = [System.IO.File]::ReadAllBytes($script:StatusScript)
        @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
}

Describe "fastfetch status.ps1 commands" {
    BeforeEach {
        if (Test-Path -LiteralPath $script:TestCacheDir) {
            Remove-Item -LiteralPath $script:TestCacheDir -Recurse -Force
        }
    }

    It "help should print usage" {
        $output = & $script:StatusScript help | Out-String
        $output | Should -Match "Usage: status.ps1"
        $output | Should -Match "updates"
        $output | Should -Match "refresh"
    }

    It "should print usage when no command is given" {
        $output = & $script:StatusScript | Out-String
        $output | Should -Match "Usage: status.ps1"
    }

    It "should reject an unknown command" {
        { & $script:StatusScript bogus } | Should -Throw
    }

    It "updates should print nothing when the cache is missing" {
        $output = & $script:StatusScript updates
        $output | Should -BeNullOrEmpty
    }

    It "updates should print the cached line" {
        New-Item -ItemType Directory -Path $script:TestCacheDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:TestCacheDir 'updates') -Value '3 update(s) available (winget)'

        $output = & $script:StatusScript updates | Out-String
        $output | Should -Match "3 update\(s\) available \(winget\)"
    }

    It "updates should print nothing when disabled" {
        New-Item -ItemType Directory -Path $script:TestCacheDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:TestCacheDir 'updates') -Value '3 update(s) available (winget)'

        $env:FASTFETCH_STATUS_DISABLE = '1'
        try {
            $output = & $script:StatusScript updates
            $output | Should -BeNullOrEmpty
        }
        finally {
            $env:FASTFETCH_STATUS_DISABLE = $script:OriginalDisable
        }
    }

    It "clear should remove the cache directory" {
        New-Item -ItemType Directory -Path $script:TestCacheDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:TestCacheDir 'updates') -Value 'x'

        & $script:StatusScript clear
        $script:TestCacheDir | Should -Not -Exist
    }
}

Describe "fastfetch status.ps1 cache staleness" {
    BeforeEach {
        if (Test-Path -LiteralPath $script:TestCacheDir) {
            Remove-Item -LiteralPath $script:TestCacheDir -Recurse -Force
        }
    }

    It "should be stale when the cache is missing" {
        Test-StatusCacheStale | Should -BeTrue
    }

    It "should be fresh right after a refresh stamp is written" {
        New-Item -ItemType Directory -Path $script:TestCacheDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:TestCacheDir '.refreshed-at') -Value ''

        Test-StatusCacheStale | Should -BeFalse
    }

    It "should be stale once the stamp is older than the TTL" {
        New-Item -ItemType Directory -Path $script:TestCacheDir -Force | Out-Null
        $stamp = Join-Path $script:TestCacheDir '.refreshed-at'
        Set-Content -LiteralPath $stamp -Value ''
        (Get-Item -LiteralPath $stamp).LastWriteTime = (Get-Date).AddSeconds(-120)

        $env:FASTFETCH_STATUS_TTL = '60'
        try {
            Test-StatusCacheStale | Should -BeTrue
        }
        finally {
            $env:FASTFETCH_STATUS_TTL = $script:OriginalTtl
        }
    }
}

Describe "fastfetch status.ps1 winget table parsing" {
    It "should count package rows and ignore the summary sentence" {
        $output = @(
            'Name                 Id                  Version   Available Source'
            '--------------------------------------------------------------------'
            'Copilot CLI          GitHub.Copilot      v1.0.71   v1.0.76   winget'
            'mise-en-place        jdx.mise            2026.7.7  2026.7.15 winget'
            '2 upgrades available.'
        ) -join "`r`n"

        Measure-WingetTableRow -Output $output | Should -Be 2
    }

    It "should return 0 when winget reports nothing to upgrade" {
        Measure-WingetTableRow -Output 'No installed package found matching input criteria.' |
            Should -Be 0
    }

    It "should return 0 for empty output" {
        Measure-WingetTableRow -Output '' | Should -Be 0
    }

    It "should ignore trailing notes that are not table rows" {
        $output = @(
            'Name        Id            Version Available Source'
            '---------------------------------------------------'
            '7-Zip       7zip.7zip     24.09   25.01     winget'
            '1 upgrades available.'
            '1 package(s) have version numbers that cannot be determined.'
        ) -join "`r`n"

        Measure-WingetTableRow -Output $output | Should -Be 1
    }
}

Describe "fastfetch status.ps1 update line" {
    BeforeEach {
        if (Test-Path -LiteralPath $script:TestCacheDir) {
            Remove-Item -LiteralPath $script:TestCacheDir -Recurse -Force
        }
    }

    It "should be empty when winget is unavailable" {
        Mock Get-WingetUpdateCount { $null }
        Get-UpdatesLine | Should -BeNullOrEmpty
    }

    It "should be empty when everything is up to date" {
        Mock Get-WingetUpdateCount { 0 }
        Get-UpdatesLine | Should -BeNullOrEmpty
    }

    It "should report the count and the manager" {
        Mock Get-WingetUpdateCount { 6 }
        Get-UpdatesLine | Should -Match '^\S+ 6 update\(s\) available \(winget\) \S+ checked @ago:\d+@$'
    }

    It "should date the line with a token rather than a frozen duration" {
        # A pre-rendered "checked 0s ago" would stay 0s until the next refresh
        # an hour later, so the epoch has to survive into the cache.
        Mock Get-WingetUpdateCount { 6 }
        $line = Get-UpdatesLine
        $line | Should -Not -Match '\d+[smhd] ago'
        $line | Should -Match '@ago:\d+@'
    }

    It "refresh should write a source file and a stamp" {
        Mock Get-WingetUpdateCount { 4 }
        Invoke-StatusRefresh

        Join-Path $script:TestCacheDir '.refreshed-at' | Should -Exist
        $line = Get-Content -LiteralPath (Join-Path $script:TestCacheDir 'updates.src') -Raw
        $line | Should -Match '4 update\(s\) available \(winget\)'
    }

    It "refresh should render the source into the file fastfetch reads" {
        Mock Get-WingetUpdateCount { 4 }
        Invoke-StatusRefresh

        $line = Get-Content -LiteralPath (Join-Path $script:TestCacheDir 'updates') -Raw
        $line | Should -Match '4 update\(s\) available \(winget\)'
        $line | Should -Match 'checked \d+[smhd] ago'
        $line | Should -Not -Match '@ago:'
    }

    It "refresh should write the cache as UTF-8 without a BOM so cmd /c type stays clean" {
        Mock Get-WingetUpdateCount { 4 }
        Invoke-StatusRefresh

        $bytes = [System.IO.File]::ReadAllBytes((Join-Path $script:TestCacheDir 'updates'))
        $bytes[0] | Should -Not -Be 0xEF
    }

    It "refresh should remove both cache files when nothing is outdated" {
        Mock Get-WingetUpdateCount { 3 }
        Invoke-StatusRefresh
        Join-Path $script:TestCacheDir 'updates' | Should -Exist

        Mock Get-WingetUpdateCount { 0 }
        Invoke-StatusRefresh
        Join-Path $script:TestCacheDir 'updates' | Should -Not -Exist
        Join-Path $script:TestCacheDir 'updates.src' | Should -Not -Exist
    }

    It "refresh should release the lock on completion" {
        Mock Get-WingetUpdateCount { 1 }
        Invoke-StatusRefresh
        Join-Path $script:TestCacheDir '.refresh.lock' | Should -Not -Exist
    }

    It "refresh should skip while another run holds a fresh lock" {
        Mock Get-WingetUpdateCount { 5 }
        New-Item -ItemType Directory -Path $script:TestCacheDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:TestCacheDir '.refresh.lock') -Value ''

        Invoke-StatusRefresh
        Join-Path $script:TestCacheDir 'updates' | Should -Not -Exist
        Should -Invoke Get-WingetUpdateCount -Times 0
    }

    It "refresh -Force should take over a held lock" {
        Mock Get-WingetUpdateCount { 5 }
        New-Item -ItemType Directory -Path $script:TestCacheDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:TestCacheDir '.refresh.lock') -Value ''

        Invoke-StatusRefresh -Force
        Join-Path $script:TestCacheDir 'updates' | Should -Exist
    }

    It "refresh should reclaim a lock left behind by an interrupted run" {
        Mock Get-WingetUpdateCount { 5 }
        New-Item -ItemType Directory -Path $script:TestCacheDir -Force | Out-Null
        $lock = Join-Path $script:TestCacheDir '.refresh.lock'
        Set-Content -LiteralPath $lock -Value ''
        (Get-Item -LiteralPath $lock).LastWriteTime = (Get-Date).AddMinutes(-30)

        Invoke-StatusRefresh
        Join-Path $script:TestCacheDir 'updates' | Should -Exist
    }
}

Describe "fastfetch chezmoi wiring" {
    BeforeAll {
        $script:TemplateContent = Get-Content $script:ConfigTemplate -Raw
        $script:IgnoreContent = Get-Content (Join-Path $script:RepoRoot "home\.chezmoiignore") -Raw
        $script:ProfileContent = Get-Content $script:ProfilePath -Raw
    }

    It "config template should exist" {
        $script:ConfigTemplate | Should -Exist
    }

    It "config template should branch on the OS" {
        $script:TemplateContent | Should -Match 'if eq \.chezmoi\.os "windows"'
    }

    It "Windows branch should read the cache with cmd instead of PowerShell" {
        $script:TemplateContent | Should -Match 'type updates'
        # Double quotes cannot survive fastfetch's cmd invocation, so the path
        # has to be entered with `cd` rather than quoted inline.
        $script:TemplateContent | Should -Match 'cd /d %LOCALAPPDATA%'
    }

    It "Unix branch should keep the status.sh modules" {
        $script:TemplateContent | Should -Match 'status\.sh\\" updates'
        $script:TemplateContent | Should -Match 'status\.sh\\" reboot'
        $script:TemplateContent | Should -Match 'status\.sh\\" ansible'
    }

    It "chezmoiignore should keep status.sh off Windows" {
        $script:IgnoreContent | Should -Match '\.config/fastfetch/status\.sh'
    }

    It "chezmoiignore should keep status.ps1 off Unix" {
        $script:IgnoreContent | Should -Match '\.config/fastfetch/status\.ps1'
    }

    It "chezmoiignore should no longer exclude the whole fastfetch directory on Windows" {
        $script:IgnoreContent | Should -Not -Match '\.config/fastfetch/\*\*'
    }

    It "profile should delegate the status cache to the module" {
        # The render must run on every shell start (so "checked 5m ago" keeps
        # counting), but dot-sourcing status.ps1 from the profile costs ~60ms,
        # hence the module function the profile already has loaded.
        $script:ProfileContent | Should -Match 'Update-FastfetchStatusCache'
    }

    It "profile should not inline the refresh spawn any more" {
        $script:ProfileContent | Should -Not -Match 'CreateNoWindow'
        $script:ProfileContent | Should -Not -Match 'FASTFETCH_STATUS_TTL'
    }

    It "profile should skip the welcome lines when fastfetch rendered" {
        $script:ProfileContent | Should -Match '\$script:_fastfetchShown = \$true'
        $script:ProfileContent | Should -Match '-not \$script:_fastfetchShown'
    }

    It "profile should still show the welcome lines without fastfetch" {
        # The welcome block must not be nested inside the fastfetch guard, or a
        # light install would start completely silently.
        $script:ProfileContent | Should -Match 'PowerShell Profile Loaded'
    }
}

Describe "fastfetch status module helpers" {
    BeforeAll {
        Import-Module (Join-Path $script:RepoRoot "home\dot_config\powershell\modules\DotfilesHelpers") `
            -Force -DisableNameChecking
    }

    Context "Format-FastfetchStatusDuration" {
        It "should format <seconds>s as '<expected>'" -ForEach @(
            @{ Seconds = 0; Expected = '0s' }
            @{ Seconds = 45; Expected = '45s' }
            @{ Seconds = 59; Expected = '59s' }
            @{ Seconds = 60; Expected = '1m' }
            @{ Seconds = 3540; Expected = '59m' }
            @{ Seconds = 3600; Expected = '1h' }
            @{ Seconds = 86399; Expected = '23h' }
            @{ Seconds = 86400; Expected = '1d' }
        ) {
            Format-FastfetchStatusDuration -Seconds $seconds | Should -Be $expected
        }

        It "should clamp a negative age to zero (clock skew)" {
            Format-FastfetchStatusDuration -Seconds -30 | Should -Be '0s'
        }
    }

    Context "Expand-FastfetchStatusToken" {
        BeforeAll { $script:Now = 1700000000 }

        It "should expand an elapsed token to a bare duration phrase" {
            Expand-FastfetchStatusToken -Line "checked @ago:$($script:Now - 300)@" -Now $script:Now |
                Should -Be 'checked 5m ago'
        }

        It "should let the caller own the wording around a token" {
            Expand-FastfetchStatusToken -Line "ran @ago:$($script:Now - 300)@" -Now $script:Now |
                Should -Be 'ran 5m ago'
        }

        It "should expand a future token" {
            Expand-FastfetchStatusToken -Line "next @in:$($script:Now + 1200)@" -Now $script:Now |
                Should -Be 'next in 20m'
        }

        It "should report a passed future token as due" {
            Expand-FastfetchStatusToken -Line "next @in:$($script:Now - 60)@" -Now $script:Now |
                Should -Be 'next due'
        }

        It "should expand several tokens in one line" {
            $line = "OK - ran @ago:$($script:Now - 60)@, next @in:$($script:Now + 60)@"
            Expand-FastfetchStatusToken -Line $line -Now $script:Now |
                Should -Be 'OK - ran 1m ago, next in 1m'
        }

        It "should leave unknown tokens untouched rather than throwing" {
            Expand-FastfetchStatusToken -Line 'user@host @nope:1@ 100% done' -Now $script:Now |
                Should -Be 'user@host @nope:1@ 100% done'
        }

        It "should handle an empty line" {
            Expand-FastfetchStatusToken -Line '' -Now $script:Now | Should -Be ''
        }
    }

    Context "Update-FastfetchStatusCache" {
        BeforeEach {
            if (Test-Path -LiteralPath $script:TestCacheDir) {
                Remove-Item -LiteralPath $script:TestCacheDir -Recurse -Force
            }
            New-Item -ItemType Directory -Path $script:TestCacheDir -Force | Out-Null
            # Fresh stamp so no background refresh is triggered by these tests.
            Set-Content -LiteralPath (Join-Path $script:TestCacheDir '.refreshed-at') -Value ''
        }

        It "should render a source file into its sibling" {
            $epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 600
            Set-Content -LiteralPath (Join-Path $script:TestCacheDir 'updates.src') `
                -Value "6 update(s) available (winget) - checked @ago:$epoch@"

            Update-FastfetchStatusCache -SkipRefresh

            $rendered = Get-Content -LiteralPath (Join-Path $script:TestCacheDir 'updates') -Raw
            $rendered | Should -Match 'checked 10m ago'
        }

        It "should re-render with the current clock, not the cached duration" {
            $src = Join-Path $script:TestCacheDir 'updates.src'
            $epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 60
            Set-Content -LiteralPath $src -Value "checked @ago:$epoch@"
            Update-FastfetchStatusCache -SkipRefresh
            (Get-Content -LiteralPath (Join-Path $script:TestCacheDir 'updates') -Raw) |
                Should -Match 'checked 1m ago'

            # Same source, older timestamp -> a different rendered duration,
            # without any refresh having run.
            $epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 7200
            Set-Content -LiteralPath $src -Value "checked @ago:$epoch@"
            Update-FastfetchStatusCache -SkipRefresh
            (Get-Content -LiteralPath (Join-Path $script:TestCacheDir 'updates') -Raw) |
                Should -Match 'checked 2h ago'
        }

        It "should write UTF-8 without a BOM" {
            Set-Content -LiteralPath (Join-Path $script:TestCacheDir 'updates.src') -Value 'plain line'
            Update-FastfetchStatusCache -SkipRefresh

            $bytes = [System.IO.File]::ReadAllBytes((Join-Path $script:TestCacheDir 'updates'))
            $bytes[0] | Should -Not -Be 0xEF
        }

        It "should drop a rendered file whose source has gone" {
            Set-Content -LiteralPath (Join-Path $script:TestCacheDir 'updates.src') -Value 'line'
            Update-FastfetchStatusCache -SkipRefresh
            Join-Path $script:TestCacheDir 'updates' | Should -Exist

            Remove-Item -LiteralPath (Join-Path $script:TestCacheDir 'updates.src')
            Update-FastfetchStatusCache -SkipRefresh
            Join-Path $script:TestCacheDir 'updates' | Should -Not -Exist
        }

        It "should leave the stamp alone" {
            Set-Content -LiteralPath (Join-Path $script:TestCacheDir 'updates.src') -Value 'line'
            Update-FastfetchStatusCache -SkipRefresh
            Join-Path $script:TestCacheDir '.refreshed-at' | Should -Exist
        }

        It "should do nothing when disabled" {
            Set-Content -LiteralPath (Join-Path $script:TestCacheDir 'updates.src') -Value 'line'
            $env:FASTFETCH_STATUS_DISABLE = '1'
            try {
                Update-FastfetchStatusCache -SkipRefresh
                Join-Path $script:TestCacheDir 'updates' | Should -Not -Exist
            }
            finally {
                $env:FASTFETCH_STATUS_DISABLE = $script:OriginalDisable
            }
        }

        It "should not throw when the cache directory does not exist" {
            Remove-Item -LiteralPath $script:TestCacheDir -Recurse -Force
            { Update-FastfetchStatusCache -SkipRefresh } | Should -Not -Throw
        }
    }

    Context "Start-FastfetchStatusRefresh" {
        It "should do nothing when the status script is missing" {
            $missing = Join-Path $script:TestCacheDir 'no-such-status.ps1'
            { Start-FastfetchStatusRefresh -StatusScript $missing } | Should -Not -Throw
        }
    }
}

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCC20jcCXcBg0vp/
# sStbX6/UXeC2TRBT5PQYLxq7q1Dv56CCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCAzoPFJ/ZqjsgbloHXf6oUSIwV4cwSS7BXzr/Sh8DyslzANBgkqhkiG
# 9w0BAQEFAASCAgCF+G5XE1Y7UsRIzqt0Wxbts/3crtIVgcoOMu5U/GGfgiw0K1gG
# xMUHYizZ6lpMkzLjlzslV4l2DQ/NfozzXb9GP+lxVbN3ZL0iy5plC5VY8ZbnKGgU
# QyKk/qSbdhYgOKZ1oyu/76t19nS+8pJNxvpxDctfCRP7Gd++J33F68WTh/Eaucsq
# PedbAuBjPLymwCG1J1P57vO9nuxE8IHNiWtAO67ruSDoPMyiPmH+CpnuwEsxveYb
# dfaiI4ekdXd0v/S/lkd0NVwwMS5NpX0KMQ3oAD2VDJ1IJw7RWo32GAjVrpPotYuf
# 3jiNKq4ndgWPlhDoGV37om0LMrSRACoh4i591MIFxrPUpF393nM5a2nhnbIHwPnw
# 8quJWZjZEkNOZH6B0tb49iGZV2AXsWIGZ0eW1tklQ4LhypRZjwklpihgtB7/XzA0
# G6ax0Q2kudI+8uLB3l5qjVtBSoaOinmYRepdUaX8O766I1nhjSIfX+N449Vd31l1
# eXG9O5LTDzI2SdXOHdu7n0MF5UqcVeky7Og0t5m6h4pgnd5eeXxSvQwQEuU1+a3N
# /inoHrBPJf5tUHxXarndH2YDa08ZQuTxTkNzoXlfj0aUpX0tqoafAaIlhfq9O3On
# Syyc95aowicMD3ROgHoHrEAvNqn5HIfp0Z8oiowCL+6kiSVQJK5JPDiBIqGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA3MzAxMDIwNDFaMC8GCSqGSIb3DQEJBDEi
# BCBq1peU51P06Jbf6T+otpvQGVx8lz+B6C6sLwYc1CrheTANBgkqhkiG9w0BAQEF
# AASCAgCJyw2EIZL0GbkdY8auhXQy8QcfR/mptUTzpMn7Gaqmd6FOIMkRE62Q5QEv
# sM8DAcPCnrR543J5KDSl/j1KaHqohPTLnNrz2qoD/VZWbDa4+XC3ihMhkvFXSU03
# eMFp125N7NpsYugbGpLHhh4PcpEGJv4ClSHrXJ+bab+WHqRYke6QgQJ2CylF6quh
# Z4ZbDgBaiklf0AkYn+GjqA/F4uhUTd6D7kz0bh6ETDPYL063BKSvyjSxAVO9iB6e
# XQSEsjNf7xhItYVbC6XC4EqHYDAEQ4VwpgWaR+wQrgzLzFmG7UYD8VSHtxOplsq5
# Xg5oFWqEDQMHfXNlZq0WygTktAPmA2gmWe+P9JOEOouRvCI0JnDCTbbczE0w7iN/
# qhs+l8gS8of22IUQCkx4XyqN8xCAL326rHcSo5jYnIf+GtIlS/OPD4Ns8iv1bpqV
# xDmkSg34QZrfUybBURJfQyHkH3CNSGfo2E9/P/nJG0sN5zlTIRSVZI8WOPopy+SM
# e9SE16RIp6jF5G+ZaLbJjKqunJ97XleNP34kkbPkLq/y0IM+HTavqwSTJ7Iyq3dC
# UFd8x+6ys/hwxQAgiD6a0DBIgZg3oLXPEWbxPsMxm64vm5TvrsWbIDZ8sx4Fozd4
# CEl+9nncur0tw7/n8/LVfYwOL/uvT/1hAbbxQcj5I8uET9HkYA==
# SIG # End signature block
