$ErrorActionPreference = "Stop"

function Info($m){ Write-Host "-> $m" -ForegroundColor Cyan }
function Ok($m){ Write-Host "[OK] $m" -ForegroundColor Green }
function Warn($m){ Write-Host "[!!] $m" -ForegroundColor Yellow }

$InstallDir = $env:VILINKS_INSTALL_DIR
if (-not $InstallDir) { $InstallDir = Join-Path $env:LOCALAPPDATA "vilinks" }

$DataDir = $env:VILINKS_DATA_DIR
if (-not $DataDir) { $DataDir = Join-Path $env:USERPROFILE ".vilinks" }

$Port = $env:VILINKS_PORT
if (-not $Port) { $Port = 8765 }

$Pid1 = Join-Path $InstallDir "vilinks.pid"
$Pid2 = Join-Path $DataDir "vilinks.pid"

function Stop-PidFile($pidFile) {
  if (Test-Path $pidFile) {
    $pid = Get-Content $pidFile -ErrorAction SilentlyContinue
    if ($pid) {
      Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
    }
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
  }
}

function Stop-ByPort($port) {
  # Find processes listening on TCP port (Windows)
  $conns = netstat -ano | Select-String -Pattern "LISTENING\s+(\d+)$"
  $pids = @()

  foreach ($line in (netstat -ano)) {
    # Example line: TCP    127.0.0.1:8765     0.0.0.0:0      LISTENING       1234
    if ($line -match "TCP\s+127\.0\.0\.1:$port\s+.*LISTENING\s+(\d+)$") {
      $pids += [int]$Matches[1]
    }
    if ($line -match "TCP\s+0\.0\.0\.0:$port\s+.*LISTENING\s+(\d+)$") {
      $pids += [int]$Matches[1]
    }
    if ($line -match "TCP\s+\[::\]:$port\s+.*LISTENING\s+(\d+)$") {
      $pids += [int]$Matches[1]
    }
  }

  $pids = $pids | Sort-Object -Unique
  foreach ($pid in $pids) {
    Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
  }

  if ($pids.Count -gt 0) { Ok "Stopped processes on port $port: $($pids -join ', ')" }
}

Info "Stopping Docker container (if any)..."
if (Get-Command docker -ErrorAction SilentlyContinue) {
  try {
    docker rm -f vilinks 2>$null | Out-Null
    Ok "Docker container removed (or did not exist)"
  } catch {
    # Never abort uninstall because docker container doesn't exist
    Warn "Docker not running or container missing; continuing..."
  }
} else {
  Warn "Docker not found; skipping Docker cleanup"
}

Info "Stopping Python process (pid files if present)..."
Stop-PidFile $Pid1
Stop-PidFile $Pid2

Info "Stopping anything listening on port $Port (fallback)..."
Stop-ByPort $Port

# Admin-only cleanup: portproxy + hosts
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($IsAdmin) {
  Info "Removing portproxy 80->${Port} (if present)..."
  netsh interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=80 2>$null | Out-Null

  Info "Removing hosts entry for 'vi' (if present)..."
  $hosts = "$env:WINDIR\System32\drivers\etc\hosts"
  if (Test-Path $hosts) {
    (Get-Content $hosts) |
      Where-Object { $_ -notmatch '^\s*127\.0\.0\.1\s+vi(\s|$)' } |
      Set-Content $hosts
  }
  ipconfig /flushdns | Out-Null
  Ok "Network hooks removed"
} else {
  Warn "Not running as Administrator: leaving hosts/portproxy intact."
  Warn "Re-run uninstall.ps1 as Admin for full cleanup."
}

Info "Removing install dir: $InstallDir"
Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue

Info "Removing data dir: $DataDir"
Remove-Item -Recurse -Force $DataDir -ErrorAction SilentlyContinue

Ok "vilinks uninstalled"