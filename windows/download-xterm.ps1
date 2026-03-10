# download-xterm.ps1 — Download xterm.js dependencies for PPG Desktop
# Run this script from the windows/ directory before building.

$ErrorActionPreference = "Stop"

$TerminalDir = Join-Path $PSScriptRoot "PPGDesktop" "Terminal"
$TempDir = Join-Path $PSScriptRoot ".xterm-temp"

Write-Host "Downloading xterm.js dependencies..." -ForegroundColor Cyan

# Create temp directory
if (Test-Path $TempDir) { Remove-Item $TempDir -Recurse -Force }
New-Item -ItemType Directory -Path $TempDir | Out-Null

try {
    Push-Location $TempDir

    # Pack xterm
    Write-Host "  Packing @xterm/xterm..." -ForegroundColor Gray
    npm pack "@xterm/xterm@latest" 2>$null | Out-Null
    $xtermTgz = Get-ChildItem -Filter "xterm-xterm-*.tgz" | Select-Object -First 1
    if (-not $xtermTgz) {
        throw "Failed to download @xterm/xterm"
    }

    # Pack fit addon
    Write-Host "  Packing @xterm/addon-fit..." -ForegroundColor Gray
    npm pack "@xterm/addon-fit@latest" 2>$null | Out-Null
    $fitTgz = Get-ChildItem -Filter "xterm-addon-fit-*.tgz" | Select-Object -First 1
    if (-not $fitTgz) {
        throw "Failed to download @xterm/addon-fit"
    }

    # Extract xterm
    Write-Host "  Extracting xterm.js files..." -ForegroundColor Gray
    tar -xzf $xtermTgz.FullName
    $xtermPkg = Join-Path $TempDir "package"

    $xtermJs = Join-Path $xtermPkg "lib" "xterm.min.js"
    if (-not (Test-Path $xtermJs)) {
        $xtermJs = Join-Path $xtermPkg "lib" "xterm.js"
    }
    $xtermCss = Join-Path $xtermPkg "css" "xterm.css"

    if (Test-Path $xtermJs) {
        Copy-Item $xtermJs (Join-Path $TerminalDir "xterm.min.js") -Force
        Write-Host "    Copied xterm.min.js" -ForegroundColor Green
    } else {
        Write-Host "    WARNING: Could not find xterm.min.js in package" -ForegroundColor Yellow
    }

    if (Test-Path $xtermCss) {
        Copy-Item $xtermCss (Join-Path $TerminalDir "xterm.css") -Force
        Write-Host "    Copied xterm.css" -ForegroundColor Green
    } else {
        Write-Host "    WARNING: Could not find xterm.css in package" -ForegroundColor Yellow
    }

    # Clean up xterm extraction before fit addon
    Remove-Item $xtermPkg -Recurse -Force

    # Extract fit addon
    tar -xzf $fitTgz.FullName
    $fitPkg = Join-Path $TempDir "package"

    $fitJs = Join-Path $fitPkg "lib" "addon-fit.min.js"
    if (-not (Test-Path $fitJs)) {
        $fitJs = Join-Path $fitPkg "lib" "addon-fit.js"
    }

    if (Test-Path $fitJs) {
        Copy-Item $fitJs (Join-Path $TerminalDir "xterm-addon-fit.min.js") -Force
        Write-Host "    Copied xterm-addon-fit.min.js" -ForegroundColor Green
    } else {
        Write-Host "    WARNING: Could not find addon-fit.min.js in package" -ForegroundColor Yellow
    }

    Pop-Location
    Write-Host "`nDone! xterm.js files installed to $TerminalDir" -ForegroundColor Green
}
catch {
    Pop-Location
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}
finally {
    # Cleanup temp
    if (Test-Path $TempDir) {
        Remove-Item $TempDir -Recurse -Force
    }
}
