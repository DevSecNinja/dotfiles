# System utilities

function which($name) {
    Get-Command $name -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
}

function touch($file) {
    if (Test-Path $file) {
        (Get-Item $file).LastWriteTime = Get-Date
    }
    else {
        New-Item -ItemType File -Path $file | Out-Null
    }
}

function mkcd($path) {
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    Set-Location $path
}
