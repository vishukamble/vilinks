$ErrorActionPreference = "Stop"

function Info($m){ Write-Host "-> $m" -ForegroundColor Cyan }
function Ok($m){ Write-Host "[OK] $m" -ForegroundColor Green }
function Warn($m){ Write-Host "[!!] $m" -ForegroundColor Yellow }

$InstallDir = $env:VILINKS_INSTALL_DIR
if (-not $InstallDir) { $InstallDir = Join-Path $env:LOCALAPPDATA "vilinks" }

$DataDir = $env:VILINKS_DATA_DIR
if (-not $DataDir) { $DataDir = Join-Path $env:USERPROFILE ".vilinks" }

$CfgCandidates = @(
  (Join-Path $DataDir "config.env"),
  (Join-Path $InstallDir "config.env")
)

# Defaults
$Port = 8765
$Prefix = "vi"

function Load-EnvFile($path) {
  if (!(Test-Path $path)) { return }

  Info ("Loading config: {0}" -f $path)
  Get-Content $path | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith("#")) { return }
    $kv = $line.Split("=",2)
    if ($kv.Count -ne 2) { return }
    [System.Environment]::SetEnvironmentVariable($kv[0], $kv[1], "Process")
  }
}

# Load config if present (DataDir preferred)
foreach ($cfg in $CfgCandidates) { Load-EnvFile $cfg }

if ($env:VILINKS_PORT)   { $Port = [int]$env:VILINKS_PORT }
if ($env:VILINKS_PREFIX) { $Prefix = $env:VILINKS_PREFIX }

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
  $pids = @()

  foreach ($line in (netstat -ano)) {
    # Examples:
    # TCP    127.0.0.1:8765     0.0.0.0:0      LISTENING       1234
    # TCP    0.0.0.0:8765       0.0.0.0:0      LISTENING       1234
    # TCP    [::]:8765          [::]:0         LISTENING       1234
    if ($line -match ("TCP\s+127\.0\.0\.1:{0}\s+.*LISTENING\s+(\d+)$" -f $port)) { $pids += [int]$Matches[1] }
    if ($line -match ("TCP\s+0\.0\.0\.0:{0}\s+.*LISTENING\s+(\d+)$" -f $port))     { $pids += [int]$Matches[1] }
    if ($line -match ("TCP\s+\[::\]:{0}\s+.*LISTENING\s+(\d+)$" -f $port))         { $pids += [int]$Matches[1] }
  }

  $pids = $pids | Sort-Object -Unique
  foreach ($pid in $pids) {
    Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
  }

  if ($pids.Count -gt 0) {
    Ok ("Stopped processes on port {0}: {1}" -f $port, ($pids -join ", "))
  }
}

Info "Stopping Docker container (if any)..."
if (Get-Command docker -ErrorAction SilentlyContinue) {
  try {
    docker rm -f vilinks 2>$null | Out-Null
    Ok "Docker container removed (or did not exist)"
  } catch {
    Warn "Docker not running or container missing; continuing..."
  }
} else {
  Warn "Docker not found; skipping Docker cleanup"
}

Info "Stopping Python process (pid files if present)..."
Stop-PidFile $Pid1
Stop-PidFile $Pid2

Info ("Stopping anything listening on port {0} (fallback)..." -f $Port)
Stop-ByPort $Port

# Admin-only cleanup: portproxy + hosts
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($IsAdmin) {
  Info ("Removing portproxy 80->{0} (if present)..." -f $Port)
  netsh interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=80 2>$null | Out-Null

  Info ("Removing hosts entry for '{0}' (if present)..." -f $Prefix)
  $hosts = "$env:WINDIR\System32\drivers\etc\hosts"
  if (Test-Path $hosts) {
    (Get-Content $hosts) |
      Where-Object { $_ -notmatch ("^\s*127\.0\.0\.1\s+{0}(\s|$)" -f [regex]::Escape($Prefix)) } |
      Set-Content $hosts
  }
  ipconfig /flushdns | Out-Null
  Ok "Network hooks removed"
} else {
  Warn "Not running as Administrator: leaving hosts/portproxy intact."
  Warn "Re-run uninstall.ps1 as Admin for full cleanup."
}

Info ("Removing install dir: {0}" -f $InstallDir)
Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue

Info ("Removing data dir: {0}" -f $DataDir)
Remove-Item -Recurse -Force $DataDir -ErrorAction SilentlyContinue

Ok "vilinks uninstalled"