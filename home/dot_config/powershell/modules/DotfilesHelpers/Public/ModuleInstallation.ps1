# Module installation utilities

function Install-PowerShellModule {
    <#
    .SYNOPSIS
    Installs a PowerShell module using pwsh -Command for reliable installation.

    .PARAMETER ModuleName
    The name of the module to install from PowerShell Gallery.

    .EXAMPLE
    Install-PowerShellModule -ModuleName "oh-my-posh"
    #>
    param (
        [Parameter(Mandatory)]
        [string]$ModuleName
    )

    Write-Host "Installing module '$ModuleName'..." -NoNewline
    $result = pwsh -NoProfile -NonInteractive -Command "`$module = Install-Module -Name $ModuleName -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck -ErrorAction SilentlyContinue -PassThru 2>&1; if (`$module) { `$module | Select-Object Name, Version | Format-Table -HideTableHeaders | Out-String } else { Write-Error 'Module installation failed' }" 2>&1

    if ($LASTEXITCODE -eq 0) {
        if ($result) {
            # Parse the output to extract module name and version
            $parsed = $result.Trim().Split(" ") | Where-Object { $_ -ne "" }
            if ($parsed.Count -ge 2) {
                $moduleInfo = [PSCustomObject]@{
                    Name    = $parsed[0]
                    Version = $parsed[1]
                }
                Write-Host " [OK] Installed $($moduleInfo.Name) $($moduleInfo.Version)" -ForegroundColor Green
                return $moduleInfo
            }
        }
    }
    else {
        Write-Host " [FAILED]" -ForegroundColor Red
        Write-Error "Module installation failed: $result"
        return $null
    }
}

function Install-GitPowerShellModule {
    <#
    .SYNOPSIS
    Installs a PowerShell module from a Git repository.

    .DESCRIPTION
    Clones a Git repository into the PowerShell modules directory and adds it to PSModulePath.
    For security reasons, only GitHub HTTPS URLs are supported.

    .PARAMETER Name
    The display name of the module for logging purposes.

    .PARAMETER Url
    The Git repository URL to clone from. Must be a GitHub HTTPS URL (e.g., https://github.com/user/repo.git).
    For security reasons, only GitHub URLs are supported.

    .PARAMETER Destination
    The destination folder name within the PowerShell modules directory.
    Must be a simple folder name without path separators or traversal characters.

    .EXAMPLE
    Install-GitPowerShellModule -Name "PowerShell-Modules" -Url "https://github.com/DevSecNinja/PowerShell-Modules.git" -Destination "DevSecNinja.PowerShell"

    .NOTES
    - Only GitHub HTTPS URLs are supported for security
    - Destination must be a simple folder name (no paths or special characters)
    - Module will be cloned to ~/Documents/PowerShell/Modules/<Destination>
    - Module path will be automatically added to PSModulePath
    #>
    param (
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Url,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    # Validate Destination to prevent path traversal attacks and UNC paths
    if ($Destination -match '(\.\.|[/\\]|^[a-zA-Z]:|^\\\\)') {
        Write-Host " [FAILED]" -ForegroundColor Red
        Write-Error "Invalid destination name. Destination must be a simple folder name without path traversal characters (e.g., 'MyModule', not '../MyModule' or 'C:\MyModule')"
        return $null
    }

    # Additional validation: ensure destination doesn't contain invalid characters
    if ($Destination -match '[<>:"|?*\x00-\x1F]') {
        Write-Host " [FAILED]" -ForegroundColor Red
        Write-Error "Invalid destination name. Contains invalid path characters."
        return $null
    }

    # Determine PowerShell modules directory
    $modulesDir = Join-Path $env:USERPROFILE "Documents\PowerShell\Modules"
    if (-not (Test-Path $modulesDir)) {
        New-Item -ItemType Directory -Path $modulesDir -Force | Out-Null
    }

    $targetPath = Join-Path $modulesDir $Destination

    # Additional safety check: ensure target path is within modules directory
    $normalizedTarget = [System.IO.Path]::GetFullPath($targetPath)
    $normalizedModulesDir = [System.IO.Path]::GetFullPath($modulesDir)
    if (-not $normalizedTarget.StartsWith($normalizedModulesDir)) {
        Write-Host " [FAILED]" -ForegroundColor Red
        Write-Error "Security violation: Target path escapes modules directory"
        return $null
    }

    Write-Host "Installing Git module '$Name'..." -NoNewline

    # Check if module already exists
    if (Test-Path $targetPath) {
        Write-Host " [OK] Already exists at $targetPath" -ForegroundColor Yellow

        # Try to update if it's a git repository
        if (Test-Path (Join-Path $targetPath ".git")) {
            Write-Host "  Updating..." -NoNewline
            Push-Location $targetPath
            try {
                # Use git fetch and reset for a clean update (avoids merge conflicts)
                git fetch --quiet origin 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    # Get the default branch name
                    $defaultBranch = git symbolic-ref refs/remotes/origin/HEAD 2>&1 | ForEach-Object { $_ -replace 'refs/remotes/origin/', '' }
                    if (-not $defaultBranch) {
                        $defaultBranch = "main"  # Fallback to main if detection fails
                    }

                    # Reset to remote branch
                    git reset --hard "origin/$defaultBranch" --quiet 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host " [OK] Updated" -ForegroundColor Green
                    }
                    else {
                        Write-Host " [WARN] Reset failed, trying pull" -ForegroundColor Yellow
                        # Fallback to pull if reset fails
                        git pull --quiet 2>&1 | Out-Null
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host " [OK] Updated" -ForegroundColor Green
                        }
                        else {
                            Write-Host " [WARN] Update failed" -ForegroundColor Yellow
                        }
                    }
                }
                else {
                    Write-Host " [WARN] Fetch failed" -ForegroundColor Yellow
                }
            }
            catch {
                Write-Host " [WARN] Update failed: $_" -ForegroundColor Yellow
            }
            finally {
                Pop-Location
            }
        }

        # Ensure the module path is in PSModulePath
        Add-ToPSModulePath -Path $modulesDir
        return [PSCustomObject]@{
            Name   = $Name
            Path   = $targetPath
            Status = "Exists"
        }
    }

    # Check if git is available
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host " [FAILED]" -ForegroundColor Red
        Write-Error "Git is not installed or not in PATH. Please install Git first."
        return $null
    }

    # Validate URL format to prevent command injection
    if ($Url -notmatch '^https://github\.com/.+/.+\.git$') {
        Write-Host " [FAILED]" -ForegroundColor Red
        Write-Error "Invalid Git URL format. Only GitHub HTTPS URLs are supported (e.g., https://github.com/user/repo.git)"
        return $null
    }

    # Clone the repository using git command directly with proper escaping
    try {
        # Use git directly with proper parameter passing (not string interpolation)
        # Use -- separator to prevent argument injection
        Push-Location $modulesDir
        try {
            git clone --quiet $Url -- $Destination 2>&1 | Out-Null
            $cloneSuccess = $LASTEXITCODE -eq 0
        }
        finally {
            Pop-Location
        }

        if ($cloneSuccess -and (Test-Path $targetPath)) {
            Write-Host " [OK] Cloned to $targetPath" -ForegroundColor Green

            # Ensure the module path is in PSModulePath
            Add-ToPSModulePath -Path $modulesDir

            return [PSCustomObject]@{
                Name   = $Name
                Path   = $targetPath
                Status = "Installed"
            }
        }
        else {
            Write-Host " [FAILED]" -ForegroundColor Red
            Write-Error "Failed to clone repository from $Url"
            return $null
        }
    }
    catch {
        Write-Host " [FAILED]" -ForegroundColor Red
        Write-Error "Failed to clone repository: $_"
        return $null
    }
}

function Add-ToPSModulePath {
    <#
    .SYNOPSIS
    Adds a directory to the PSModulePath if it's not already present.

    .PARAMETER Path
    The path to add to PSModulePath.

    .EXAMPLE
    Add-ToPSModulePath -Path "C:\Users\username\Documents\PowerShell\Modules"
    #>
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        # Normalize the path with error handling
        $normalizedPath = [System.IO.Path]::GetFullPath($Path)

        # Get current PSModulePath from environment
        $currentPath = [Environment]::GetEnvironmentVariable("PSModulePath", "User")
        if (-not $currentPath) {
            $currentPath = ""
        }

        # Split into array and check if path already exists
        $pathArray = $currentPath -split [IO.Path]::PathSeparator | Where-Object { $_ }
        $pathExists = $false

        foreach ($existingPath in $pathArray) {
            try {
                $normalizedExisting = [System.IO.Path]::GetFullPath($existingPath)
                if ($normalizedExisting -eq $normalizedPath) {
                    $pathExists = $true
                    break
                }
            }
            catch {
                # Skip invalid paths in existing PSModulePath
                Write-Verbose "Skipping invalid path in PSModulePath: $existingPath"
                continue
            }
        }

        if (-not $pathExists) {
            # Add to user's PSModulePath permanently
            if ($currentPath) {
                $newPath = $currentPath + [IO.Path]::PathSeparator + $normalizedPath
            }
            else {
                $newPath = $normalizedPath
            }
            [Environment]::SetEnvironmentVariable("PSModulePath", $newPath, "User")

            # Also update current session
            $env:PSModulePath = $env:PSModulePath + [IO.Path]::PathSeparator + $normalizedPath

            Write-Host "  Added $normalizedPath to PSModulePath" -ForegroundColor Cyan
        }
    }
    catch {
        Write-Warning "Failed to add path to PSModulePath: $_"
    }
}
