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
        Get-UpdatesLine | Should -Match '^\S+ 6 update\(s\) available \(winget\)$'
    }

    It "refresh should write a cache file and a stamp" {
        Mock Get-WingetUpdateCount { 4 }
        Invoke-StatusRefresh

        Join-Path $script:TestCacheDir '.refreshed-at' | Should -Exist
        $line = Get-Content -LiteralPath (Join-Path $script:TestCacheDir 'updates') -Raw
        $line | Should -Match '4 update\(s\) available \(winget\)'
    }

    It "refresh should write the cache as UTF-8 without a BOM so cmd /c type stays clean" {
        Mock Get-WingetUpdateCount { 4 }
        Invoke-StatusRefresh

        $bytes = [System.IO.File]::ReadAllBytes((Join-Path $script:TestCacheDir 'updates'))
        $bytes[0] | Should -Not -Be 0xEF
    }

    It "refresh should remove the cache file when nothing is outdated" {
        Mock Get-WingetUpdateCount { 3 }
        Invoke-StatusRefresh
        Join-Path $script:TestCacheDir 'updates' | Should -Exist

        Mock Get-WingetUpdateCount { 0 }
        Invoke-StatusRefresh
        Join-Path $script:TestCacheDir 'updates' | Should -Not -Exist
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

    It "profile should spawn a background refresh of the status cache" {
        $script:ProfileContent | Should -Match 'fastfetch\\status\.ps1'
        $script:ProfileContent | Should -Match "'refresh'|refresh"
    }

    It "profile background refresh should not create a visible window" {
        $script:ProfileContent | Should -Match 'CreateNoWindow'
    }

    It "profile should honour FASTFETCH_STATUS_DISABLE" {
        $script:ProfileContent | Should -Match 'FASTFETCH_STATUS_DISABLE'
    }
}
