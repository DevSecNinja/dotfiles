# Wrapper script for Coder support
# Coder looks for install.ps1 in the repository root
# This script delegates to the actual install script in the home directory

#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

# Get the directory of this script
$scriptDir = $PSScriptRoot

# Run the actual install script from the home directory, forwarding all parameters
& "$scriptDir\home\install.ps1" @args

# Exit with the same exit code
exit $LASTEXITCODE
