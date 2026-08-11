#!/usr/bin/env pwsh
# Disable the hardware power button on Microsoft Surface Laptop models.
# Runs on Windows and is idempotent.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    "PSAvoidUsingWriteHost",
    "",
    Justification = "Matches existing chezmoi setup script progress output."
)]
param(
    [switch]$SkipApply
)

$ErrorActionPreference = "Stop"

function Test-SurfaceLaptop {
    param(
        [AllowNull()]
        [object]$ComputerSystem
    )

    if ($null -eq $ComputerSystem) {
        return $false
    }

    $manufacturer = [string]$ComputerSystem.Manufacturer
    $model = [string]$ComputerSystem.Model

    return $manufacturer.Trim() -eq "Microsoft Corporation" -and
        $model.Trim() -match "^(?:Microsoft )?Surface Laptop(?:[\s,]|$)"
}

function Invoke-PowerCfg {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList
    )

    $powerCfgPath = Join-Path $env:SystemRoot "System32\powercfg.exe"
    if (-not (Test-Path -LiteralPath $powerCfgPath -PathType Leaf)) {
        throw "powercfg.exe was not found at '$powerCfgPath'."
    }

    $output = & $powerCfgPath @ArgumentList 2>&1
    if ($LASTEXITCODE -ne 0) {
        $details = ($output | Out-String).Trim()
        throw "powercfg.exe failed with exit code $LASTEXITCODE for '$($ArgumentList -join ' ')': $details"
    }
}

function Disable-SurfaceLaptopPowerButton {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [scriptblock]$GetComputerSystem = {
            Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        },

        [scriptblock]$InvokePowerCfg = {
            param([string[]]$ArgumentList)
            Invoke-PowerCfg -ArgumentList $ArgumentList
        }
    )

    $computerSystem = & $GetComputerSystem
    if (-not (Test-SurfaceLaptop -ComputerSystem $computerSystem)) {
        Write-Host "[SKIP] Power button unchanged: this device is not a Microsoft Surface Laptop." -ForegroundColor Yellow
        return [pscustomobject]@{
            Status  = "NotSurfaceLaptop"
            Changed = $false
            Model   = [string]$computerSystem.Model
        }
    }

    $powerButtonSetting = "7648efa3-dd9c-4e3e-b566-50f929386280"
    $buttonSubgroup = "4f971e89-eebd-4455-a8de-9e59040e7347"
    $commands = @(
        [pscustomobject]@{
            ArgumentList = @("/SETACVALUEINDEX", "SCHEME_CURRENT", $buttonSubgroup, $powerButtonSetting, "0")
        }
        [pscustomobject]@{
            ArgumentList = @("/SETDCVALUEINDEX", "SCHEME_CURRENT", $buttonSubgroup, $powerButtonSetting, "0")
        }
        [pscustomobject]@{
            ArgumentList = @("/SETACTIVE", "SCHEME_CURRENT")
        }
    )

    $model = [string]$computerSystem.Model
    if (-not $PSCmdlet.ShouldProcess($model, "Set the AC and battery power button action to Do nothing")) {
        return [pscustomobject]@{
            Status  = "WhatIf"
            Changed = $false
            Model   = $model
        }
    }

    foreach ($command in $commands) {
        & $InvokePowerCfg -ArgumentList $command.ArgumentList
    }

    Write-Host "[OK] Disabled the power button on $model for AC and battery power." -ForegroundColor Green
    return [pscustomobject]@{
        Status  = "Disabled"
        Changed = $true
        Model   = $model
    }
}

if (-not $SkipApply) {
    Disable-SurfaceLaptopPowerButton | Out-Null
}
