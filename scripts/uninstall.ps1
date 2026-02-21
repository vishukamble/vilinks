$ErrorActionPreference = "Stop"

function Info($m){ Write-Host "→ $m" -ForegroundColor Cyan }
function Ok($m){ Write-Host "✓ $m" -ForegroundColor Green }
function Warn($m){ Write-Host "⚠ $m" -ForegroundColor Yellow }

$InstallDir = $env:VILINKS_INSTALL_DIR
if (-not $InstallDir) { $InstallDir = Join-Path $env:LOCALAPPDATA "vilinks" }

$DataDir = $env:VILINKS_DATA_DIR
if (-not $DataDir) { $DataDir = Join-Path $env:USERPROFILE ".vilinks" }

$Pid1 = Join-Path $InstallDir "vilinks.pid"
$Pid2 = Join-Path $DataDir "vilinks.pid"

Info "Stopping Docker container (if any)..."
if (Get-Command docker -ErrorAction SilentlyContinue) {
  docker rm -f vilinks 2>$null | Out-Null
}

function Stop-PidFile($pidFile) {
  if (Test-Path $pidFile) {
    $pid = Get-Content $pidFile -ErrorAction SilentlyContinue
    if ($pid) {
      Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
    }
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
  }
}

Info "Stopping Python process (if any)..."
Stop-PidFile $Pid1
Stop-PidFile $Pid2
Ok "Stopped"

# Admin-only cleanup: portproxy + hosts
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($IsAdmin) {
  Info "Removing portproxy 80->8765 (if present)..."
  netsh interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=80 2>$null | Out-Null

  Info "Removing hosts entry for 'vi' (if present)..."
  $hosts = "$env:WINDIR\System32\drivers\etc\hosts"
  if (Test-Path $hosts) {
    (Get-Content $hosts) |
      Where-Object { $_ -notmatch '^\s*127\.0\.0\.1\s+vi(\s|$)' } |
      Set-Content $hosts
  }
  Ok "Network hooks removed"
} else {
  Warn "Not running as Administrator: leaving hosts/portproxy intact."
  Warn "If you want full cleanup, re-run uninstall.ps1 as Admin."
}

Info "Removing install dir: $InstallDir"
Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue

Info "Removing data dir: $DataDir"
Remove-Item -Recurse -Force $DataDir -ErrorAction SilentlyContinue

Ok "vilinks uninstalled"