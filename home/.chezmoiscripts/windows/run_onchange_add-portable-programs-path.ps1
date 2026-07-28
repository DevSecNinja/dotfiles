#!/usr/bin/env pwsh
# Add OneDrive Portable Programs to the user PATH.
# Runs when this script changes; the operation itself is idempotent.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    "PSAvoidUsingWriteHost",
    "",
    Justification = "Matches existing chezmoi setup script progress output."
)]
param(
    [switch]$SkipApply
)

$ErrorActionPreference = "Stop"

function ConvertTo-PathLookupKey {
    param(
        [AllowNull()]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }

    return $Path.Trim().Trim('"').TrimEnd('\').ToUpperInvariant()
}

function Test-PathListContainsEntry {
    param(
        [AllowNull()]
        [string]$PathList,

        [Parameter(Mandatory = $true)]
        [string]$Entry
    )

    $pathListValue = if ($null -eq $PathList) { "" } else { $PathList }
    $entryKey = ConvertTo-PathLookupKey -Path $Entry
    foreach ($pathEntry in ($pathListValue -split ';')) {
        if ((ConvertTo-PathLookupKey -Path $pathEntry) -eq $entryKey) {
            return $true
        }
    }

    return $false
}

function Add-PathListEntry {
    param(
        [AllowNull()]
        [string]$PathList,

        [Parameter(Mandatory = $true)]
        [string]$Entry
    )

    if (Test-PathListContainsEntry -PathList $PathList -Entry $Entry) {
        return $PathList
    }

    if ([string]::IsNullOrWhiteSpace($PathList)) {
        return $Entry
    }

    $separator = if ($PathList.EndsWith(';')) { "" } else { ";" }
    return "$PathList$separator$Entry"
}

function Resolve-UserPathRegistryWriteInfo {
    param(
        [AllowNull()]
        [string]$ValueName,

        [AllowNull()]
        [object]$Kind,

        [AllowNull()]
        [string]$Value
    )

    $resolvedValueName = if ([string]::IsNullOrWhiteSpace($ValueName)) { "Path" } else { $ValueName }
    $resolvedKind = if ($Kind -is [Microsoft.Win32.RegistryValueKind] -and
        $Kind -ne [Microsoft.Win32.RegistryValueKind]::Unknown) {
        $Kind
    }
    elseif ($Value -like "*%*") {
        [Microsoft.Win32.RegistryValueKind]::ExpandString
    }
    else {
        [Microsoft.Win32.RegistryValueKind]::String
    }

    return [pscustomobject]@{
        ValueName = $resolvedValueName
        Kind      = $resolvedKind
    }
}

function Get-UserPathRegistryValue {
    $environmentKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $false)
    try {
        if (-not $environmentKey) {
            return [pscustomobject]@{
                Value     = ""
                ValueName = "Path"
                Kind      = $null
            }
        }

        $valueName = $environmentKey.GetValueNames() |
            Where-Object { $_ -in @("Path", "PATH") } |
            Select-Object -First 1
        if (-not $valueName) {
            return [pscustomobject]@{
                Value     = ""
                ValueName = "Path"
                Kind      = $null
            }
        }

        return [pscustomobject]@{
            Value     = [string]$environmentKey.GetValue(
                $valueName,
                "",
                [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
            )
            ValueName = $valueName
            Kind      = $environmentKey.GetValueKind($valueName)
        }
    }
    finally {
        if ($environmentKey) {
            $environmentKey.Dispose()
        }
    }
}

function Send-EnvironmentChangeBroadcast {
    try {
        if (-not ([System.Management.Automation.PSTypeName]"NativeMethods.EnvironmentBroadcast").Type) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace NativeMethods {
    public static class EnvironmentBroadcast {
        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern IntPtr SendMessageTimeout(
            IntPtr hWnd,
            uint Msg,
            UIntPtr wParam,
            string lParam,
            uint fuFlags,
            uint uTimeout,
            out UIntPtr lpdwResult);
    }
}
'@
        }

        $sendResult = [UIntPtr]::Zero
        $response = [NativeMethods.EnvironmentBroadcast]::SendMessageTimeout(
            [IntPtr]0xffff,
            0x001A,
            [UIntPtr]::Zero,
            "Environment",
            0x0002,
            5000,
            [ref]$sendResult
        )

        if ($response -eq [IntPtr]::Zero) {
            Write-Host "[WARN] Could not broadcast environment change notification." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "[WARN] Could not broadcast environment change notification: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Set-UserPathRegistryValue {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [AllowNull()]
        [string]$ValueName,

        [AllowNull()]
        [object]$Kind
    )

    $writeInfo = Resolve-UserPathRegistryWriteInfo -ValueName $ValueName -Kind $Kind -Value $Path
    if ($PSCmdlet.ShouldProcess("HKCU:\Environment\$($writeInfo.ValueName)", "Set user PATH registry value")) {
        $environmentKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $true)
        try {
            if (-not $environmentKey) {
                $environmentKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey("Environment")
            }

            $environmentKey.SetValue($writeInfo.ValueName, $Path, $writeInfo.Kind)
        }
        finally {
            if ($environmentKey) {
                $environmentKey.Dispose()
            }
        }

        Send-EnvironmentChangeBroadcast
    }
}

function Add-PortableProgramsToUserPath {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [AllowNull()]
        [string]$OneDrivePath = $env:OneDrive,

        [scriptblock]$PathExists = {
            param([string]$Path)
            Test-Path -LiteralPath $Path -PathType Container
        },

        [scriptblock]$GetUserPath = {
            Get-UserPathRegistryValue
        },

        [scriptblock]$SetUserPath = {
            param(
                [string]$Path,
                [string]$ValueName,
                [object]$Kind
            )
            Set-UserPathRegistryValue -Path $Path -ValueName $ValueName -Kind $Kind
        }
    )

    if ([string]::IsNullOrWhiteSpace($OneDrivePath)) {
        return [pscustomobject]@{
            Status  = "OneDriveMissing"
            Changed = $false
            Path    = $null
        }
    }

    $oneDriveRoot = $OneDrivePath.TrimEnd('\').TrimEnd('/')
    $portableProgramsPath = "$oneDriveRoot\Portable Programs"

    # Persist only existing folders so a stale or not-yet-synced OneDrive path
    # is not written permanently; the profile still handles the current session.
    if (-not (& $PathExists $portableProgramsPath)) {
        Write-Host "[SKIP] Portable Programs folder not found: $portableProgramsPath" -ForegroundColor Yellow
        return [pscustomobject]@{
            Status  = "PortableProgramsMissing"
            Changed = $false
            Path    = $portableProgramsPath
        }
    }

    $userPathInfo = & $GetUserPath
    if ($null -eq $userPathInfo) {
        $userPath = ""
        $valueName = "Path"
        $valueKind = $null
    }
    elseif ($userPathInfo.PSObject.Properties["Value"]) {
        $userPath = [string]$userPathInfo.Value
        $valueName = $userPathInfo.ValueName
        $valueKind = $userPathInfo.Kind
    }
    else {
        $userPath = [string]$userPathInfo
        $valueName = "Path"
        $valueKind = $null
    }

    if (Test-PathListContainsEntry -PathList $userPath -Entry $portableProgramsPath) {
        Write-Host "[OK] Portable Programs is already in the user PATH" -ForegroundColor Green
        return [pscustomobject]@{
            Status  = "AlreadySet"
            Changed = $false
            Path    = $portableProgramsPath
        }
    }

    $updatedUserPath = Add-PathListEntry -PathList $userPath -Entry $portableProgramsPath
    if ($PSCmdlet.ShouldProcess("User PATH", "Append $portableProgramsPath")) {
        & $SetUserPath $updatedUserPath $valueName $valueKind
        Write-Host "[OK] Added Portable Programs to the user PATH: $portableProgramsPath" -ForegroundColor Green
    }

    return [pscustomobject]@{
        Status  = "Updated"
        Changed = $true
        Path    = $portableProgramsPath
    }
}

if (-not $SkipApply) {
    Add-PortableProgramsToUserPath | Out-Null
}
