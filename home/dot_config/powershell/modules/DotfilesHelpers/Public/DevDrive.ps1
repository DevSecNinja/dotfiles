# Dev Drive detection and projects folder resolution
#
# A Dev Drive is a Windows 11 ReFS volume tuned for developer workloads. It is
# a much better home for source code than the user profile (which is usually on
# the NTFS system drive and covered by real-time antivirus scanning).
#
# Note: "fsutil devdrv query" is the authoritative check, but it requires an
# elevated shell, so it can't be used from a profile. Fixed ReFS volumes are
# used as the heuristic instead - on a normal workstation those are Dev Drives.
# Set $env:DEV_DRIVE to pin a specific volume, or $env:PROJECTS_PATH to pin the
# projects folder outright.

function Test-DevDriveSupported {
    <#
    .SYNOPSIS
        Returns $true when running on Windows, where Dev Drives exist.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        return $true
    }

    return [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)
}

function Get-DevDrivePath {
    <#
    .SYNOPSIS
        Returns the root paths of the Dev Drives on this machine.

    .DESCRIPTION
        Honours $env:DEV_DRIVE when set (and the path exists). Otherwise returns
        every fixed, ready ReFS volume, sorted by drive letter. Returns an empty
        array when no Dev Drive is present or the platform isn't Windows.

    .EXAMPLE
        Get-DevDrivePath
        D:\
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    if (-not [string]::IsNullOrWhiteSpace($env:DEV_DRIVE)) {
        $override = $env:DEV_DRIVE.Trim().Trim('"')
        if (Test-Path -LiteralPath $override) {
            return @($override)
        }

        Write-Verbose "DEV_DRIVE is set to '$override' but that path does not exist; ignoring it."
    }

    if (-not (Test-DevDriveSupported)) {
        return @()
    }

    $roots = @()

    try {
        foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
            if (-not $drive.IsReady) { continue }
            if ($drive.DriveType -ne [System.IO.DriveType]::Fixed) { continue }
            if ($drive.DriveFormat -ne 'ReFS') { continue }

            $roots += $drive.RootDirectory.FullName
        }
    }
    catch {
        Write-Verbose "Failed to enumerate drives: $_"
        return @()
    }

    return @($roots | Sort-Object)
}

function Get-ProjectsPath {
    <#
    .SYNOPSIS
        Resolves the folder that holds local source code checkouts.

    .DESCRIPTION
        Resolution order:
          1. $env:PROJECTS_PATH, when set.
          2. <Dev Drive>\projects, when a Dev Drive has one.
          3. $env:USERPROFILE\projects (or $HOME/projects off Windows).

        Without -CreateIfMissing the function never touches the file system, so
        it is safe to call from the PowerShell profile on every startup.

    .PARAMETER CreateIfMissing
        Create the resolved folder when it does not exist yet. A Dev Drive is
        preferred over the user profile when creating.

    .EXAMPLE
        Get-ProjectsPath
        D:\projects
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [switch]$CreateIfMissing
    )

    $userHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    $fallback = Join-Path $userHome 'projects'

    if (-not [string]::IsNullOrWhiteSpace($env:PROJECTS_PATH)) {
        $explicit = $env:PROJECTS_PATH.Trim().Trim('"')

        if ($CreateIfMissing -and -not (Test-Path -LiteralPath $explicit)) {
            if ($PSCmdlet.ShouldProcess($explicit, 'Create projects directory')) {
                New-Item -ItemType Directory -Path $explicit -Force | Out-Null
            }
        }

        return $explicit
    }

    $devDrives = @(Get-DevDrivePath)

    foreach ($root in $devDrives) {
        $candidate = Join-Path $root 'projects'
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    if ($CreateIfMissing) {
        $target = if ($devDrives.Count -gt 0) { Join-Path $devDrives[0] 'projects' } else { $fallback }

        if (-not (Test-Path -LiteralPath $target)) {
            if ($PSCmdlet.ShouldProcess($target, 'Create projects directory')) {
                New-Item -ItemType Directory -Path $target -Force | Out-Null
            }
        }

        return $target
    }

    return $fallback
}
