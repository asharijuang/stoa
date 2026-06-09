# Stoa server installer (native Windows) — bootstrap the hub on a fresh machine.
#
#   irm https://raw.githubusercontent.com/a-athaullah/stoa/master/install.ps1 | iex
#   # or, from a clone:
#   powershell -ExecutionPolicy Bypass -File .\install.ps1
#
# Checks prerequisites, fetches the code, installs deps, then runs `node cli.js install`
# which links the `stoa` command and registers the background gateway (Scheduled Task).

$ErrorActionPreference = "Stop"

# Repo to clone (only used when not already inside a checkout). Auto-detects from
# this script's git origin so it follows whatever fork you cloned; falls back to
# upstream. Override with STOA_REPO_URL.
function Get-RepoUrl {
  if ($env:STOA_REPO_URL) { return $env:STOA_REPO_URL }
  $o = $null
  if ($PSScriptRoot) { $o = (git -C $PSScriptRoot remote get-url origin 2>$null) }
  if (-not $o) { $o = (git remote get-url origin 2>$null) }
  if ($o) { return $o } else { return "https://github.com/a-athaullah/stoa" }
}
$RepoUrl    = Get-RepoUrl
# Managed app location (Hermes-style): code in ~/.stoa/app, data in ~/.stoa/server.
$InstallDir = if ($env:STOA_DIR) { $env:STOA_DIR } else { "$env:USERPROFILE\.stoa\app" }
$RepoSlug   = ($RepoUrl -replace '.*github\.com[:/]+', '') -replace '\.git$', ''

Write-Host "=== Stoa installer (Windows) ==="

foreach ($cmd in @("git", "node", "npm")) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    Write-Error "$cmd not found. Install Node.js 20+ (https://nodejs.org/) and git (https://git-scm.com/) first."
    exit 1
  }
}
$nodeMajor = [int](node -p "process.versions.node.split('.')[0]")
if ($nodeMajor -lt 20) { Write-Error "Node 20+ required (found $(node -v))."; exit 1 }
Write-Host "ok: node $(node -v), npm $(npm -v), git present"

# Priority: current checkout (dev) → prebuilt GitHub release tarball (no build!) → git clone.
if ((Test-Path ".\cli.js") -and (Test-Path ".\server.js")) {
  $InstallDir = (Get-Location).Path
  Write-Host "[1/3] Using current checkout: $InstallDir"
} elseif (Test-Path "$InstallDir\.git") {
  Write-Host "[1/3] Updating existing clone: $InstallDir"
  git -C "$InstallDir" pull --ff-only
} else {
  $asset = $null
  try {
    $rel = Invoke-RestMethod "https://api.github.com/repos/$RepoSlug/releases/latest" -Headers @{ 'User-Agent' = 'stoa-cli' }
    $asset = ($rel.assets | Where-Object { $_.name -like '*.tar.gz' } | Select-Object -First 1).browser_download_url
  } catch {}
  if ($asset) {
    Write-Host "[1/3] Installing from latest release - prebuilt, no build"
    New-Item -ItemType Directory -Force $InstallDir | Out-Null
    $tmp = Join-Path $env:TEMP 'stoa-release.tar.gz'
    Invoke-WebRequest $asset -OutFile $tmp -UseBasicParsing
    tar -xzf $tmp -C $InstallDir --strip-components=1
    Remove-Item $tmp -Force
  } else {
    Write-Host "[1/3] No release found - cloning $RepoUrl"
    git clone $RepoUrl $InstallDir
  }
  if ($RepoSlug) { Set-Content -Path "$InstallDir\.stoa-source" -Value $RepoSlug -NoNewline }
}
Set-Location $InstallDir

Write-Host "[2/3] Installing dependencies..."
npm install --omit=dev --no-audit --no-fund

Write-Host "[3/3] Bootstrapping (link command + enable gateway)..."
node cli.js install

Write-Host ""
Write-Host "=== Done ==="
Write-Host "Open the dashboard:  stoa dashboard"
Write-Host "Check status:        stoa gateway status"
Write-Host "Stop the server:     stoa gateway stop"
