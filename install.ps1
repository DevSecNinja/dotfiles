# Wrapper script for Coder support
# Coder looks for install.ps1 in the repository root
# This script delegates to the actual install script in the home directory

#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ChezmoiVersion = "latest"
)

$ErrorActionPreference = "Stop"

# Get the directory of this script
$scriptDir = $PSScriptRoot

# Run the actual install script from the home directory
& "$scriptDir\home\install.ps1" -ChezmoiVersion $ChezmoiVersion

# Exit with the same exit code
exit $LASTEXITCODE
