# ============================================================================
# mcsquared.ai — Developer Workstation Setup + Stockyard Coding Swarm
# Windows PowerShell version
#
# Run: irm https://raw.githubusercontent.com/mcsquared-ai/mc2-IgAN-LaunchToolkit/main/scripts/stockyard-dev-setup.ps1 | iex
# Or:  .\scripts\stockyard-dev-setup.ps1
# ============================================================================

$ErrorActionPreference = "Stop"

$STOCKYARD_HOST = "34.121.124.99"
$STOCKYARD_PORT = "65433"
$STOCKYARD_URL = "grpc://${STOCKYARD_HOST}:${STOCKYARD_PORT}"
$GCP_PROJECT = "sales-demos-485118"
$STOCKYARD_REPO = "https://github.com/prime-radiant-inc/stockyard.git"

function Log($msg) { Write-Host "[+] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Err($msg) { Write-Host "[x] $msg" -ForegroundColor Red }
function Info($msg) { Write-Host "[-] $msg" -ForegroundColor Cyan }

# ── Check WSL2 ───────────────────────────────────────────────────────

Info "Checking for WSL2..."
$wslInstalled = $false
try {
    $wslOutput = wsl --status 2>&1
    if ($wslOutput -match "Default Distribution") { $wslInstalled = $true }
} catch {}

if (-not $wslInstalled) {
    Warn "WSL2 not found. Stockyard CLI runs best under WSL2."
    Info "Installing WSL2..."
    wsl --install --no-distribution
    Write-Host ""
    Warn "WSL2 installed. Please RESTART your computer, then:"
    Write-Host "  1. Open PowerShell and run: wsl --install -d Ubuntu-24.04"
    Write-Host "  2. Open Ubuntu from Start Menu"
    Write-Host "  3. Run this inside Ubuntu:"
    Write-Host "     curl -fsSL https://raw.githubusercontent.com/mcsquared-ai/mc2-IgAN-LaunchToolkit/main/scripts/stockyard-dev-setup.sh | bash"
    exit 0
}

# ── Install via winget ───────────────────────────────────────────────

Info "Installing prerequisites via winget..."

$tools = @(
    @{Name="Git"; Id="Git.Git"},
    @{Name="Go"; Id="GoLang.Go"},
    @{Name="Google Cloud SDK"; Id="Google.CloudSDK"},
    @{Name="GitHub CLI"; Id="GitHub.cli"},
    @{Name="Python"; Id="Python.Python.3.12"},
    @{Name="Node.js"; Id="OpenJS.NodeJS.LTS"}
)

foreach ($tool in $tools) {
    $installed = winget list --id $tool.Id 2>&1 | Select-String $tool.Id
    if ($installed) {
        Log "$($tool.Name): installed"
    } else {
        Info "Installing $($tool.Name)..."
        winget install --id $tool.Id --accept-package-agreements --accept-source-agreements
        Log "$($tool.Name): installed"
    }
}

# ── Build Stockyard CLI ──────────────────────────────────────────────

Info "Building Stockyard CLI..."

$tmpDir = Join-Path $env:TEMP "stockyard-build"
if (Test-Path $tmpDir) { Remove-Item -Recurse -Force $tmpDir }
New-Item -ItemType Directory -Path $tmpDir | Out-Null

Push-Location $tmpDir
git clone --depth 1 $STOCKYARD_REPO stockyard 2>$null
Push-Location stockyard

$env:GOOS = "windows"
$env:GOARCH = "amd64"
go build -o stockyard.exe ./cmd/stockyard

$binDir = Join-Path $env:USERPROFILE ".local\bin"
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
Copy-Item stockyard.exe $binDir

Pop-Location
Pop-Location
Remove-Item -Recurse -Force $tmpDir

Log "Stockyard CLI: $binDir\stockyard.exe"

# ── Configure environment ────────────────────────────────────────────

Info "Configuring environment..."

[Environment]::SetEnvironmentVariable("STOCKYARD_URL", $STOCKYARD_URL, "User")
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($currentPath -notlike "*\.local\bin*") {
    [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$binDir", "User")
}

$env:STOCKYARD_URL = $STOCKYARD_URL
$env:PATH = "$env:PATH;$binDir"

Log "STOCKYARD_URL=$STOCKYARD_URL"

# ── Verify ───────────────────────────────────────────────────────────

Info "Testing connection..."
try {
    $result = & "$binDir\stockyard.exe" list 2>&1
    if ($result -match "No tasks found" -or $result -match "ID") {
        Log "Stockyard daemon: connected"
    } else {
        Warn "Cannot reach daemon. Host VM may be stopped."
        Write-Host "  Run: gcloud compute instances start stockyard-host --zone=us-central1-a"
    }
} catch {
    Warn "Connection failed: $_"
}

# ── Summary ──────────────────────────────────────────────────────────

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  mcsquared.ai Developer Setup Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Stockyard CLI:  $binDir\stockyard.exe"
Write-Host "  Host VM:        $STOCKYARD_HOST"
Write-Host "  Config:         STOCKYARD_URL env var"
Write-Host ""
Write-Host "  Quick Start:" -ForegroundColor Green
Write-Host "    stockyard list              # List running micro-VMs"
Write-Host "    stockyard run --name test   # Spawn a micro-VM"
Write-Host ""
Write-Host "  Note: Open a NEW terminal for PATH changes" -ForegroundColor Yellow
Write-Host ""
