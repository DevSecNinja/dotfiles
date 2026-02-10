# DotfilesHelpers Module Loader
# Dot-sources all public function files from the Public directory

$Public = @(Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue)

foreach ($file in $Public) {
    try {
        . $file.FullName
    }
    catch {
        Write-Error "Failed to import function file $($file.FullName): $_"
    }
}
