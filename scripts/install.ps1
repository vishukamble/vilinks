$ErrorActionPreference = 'Stop'

function Is-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p = New-Object Security.Principal.WindowsPrincipal($id)
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

Write-Host "`nvilinks — local GoLinks-style shortener`n" -ForegroundColor Cyan

$defaultHost = 'vi'
$hostName = Read-Host "Short hostname (so you type 'vi/') [$defaultHost]"
if ([string]::IsNullOrWhiteSpace($hostName)) { $hostName = $defaultHost }
if ($hostName -notmatch '^[a-z][a-z0-9-]{1,30}$') { throw "Invalid hostname '$hostName'" }

$defaultPort = 8765
$portIn = Read-Host "App port [$defaultPort]"
$port = if ([string]::IsNullOrWhiteSpace($portIn)) { $defaultPort } else { [int]$portIn }
if ($port -lt 1024 -or $port -gt 65535) { throw "Invalid port '$port'" }

$repoDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$dataDir = Join-Path $HOME '.vilinks'
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

# Install mode
Write-Host "Choose install mode" -ForegroundColor Cyan
Write-Host "  1) Docker (recommended)"
Write-Host "  2) Native Python (venv in %USERPROFILE%\.vilinks)"
$mode = Read-Host "Select [1/2]"
if ([string]::IsNullOrWhiteSpace($mode)) { $mode = '1' }

# Write .env for docker compose
$envPath = Join-Path $repoDir '.env'
@(
  "VILINKS_PORT=$port",
  "VILINKS_BASE_HOST=$hostName",
  "VILINKS_DATA_DIR=$dataDir"
) | Set-Content -Path $envPath -Encoding ascii
Write-Host "Wrote $envPath" -ForegroundColor Green

$admin = Is-Admin

# Hosts entry
$addHosts = Read-Host "Add hosts entry '127.0.0.1 $hostName' (needed for http://$hostName/ )? [Y/n]"
if ([string]::IsNullOrWhiteSpace($addHosts)) { $addHosts = 'Y' }
if ($addHosts -match '^[Yy]$') {
  if (-not $admin) {
    Write-Host "Not running as admin → can't edit hosts. You'll be able to use http://$hostName.localhost:$port/" -ForegroundColor Yellow
  } else {
    $hostsFile = "$env:WINDIR\System32\drivers\etc\hosts"
    $line = "127.0.0.1 $hostName"
    $content = Get-Content $hostsFile -ErrorAction Stop
    if ($content -notcontains $line) {
      Add-Content -Path $hostsFile -Value $line
      Write-Host "Added hosts entry" -ForegroundColor Green
    } else {
      Write-Host "Hosts entry already present" -ForegroundColor Green
    }
  }
}

# Port 80 forward
$forward80 = Read-Host "Enable port-80 forward so http://$hostName/ works (requires admin)? [y/N]"
if ([string]::IsNullOrWhiteSpace($forward80)) { $forward80 = 'N' }
if ($forward80 -match '^[Yy]$') {
  if (-not $admin) {
    Write-Host "Not running as admin → can't add portproxy. Use http://$hostName.localhost:$port/" -ForegroundColor Yellow
  } else {
    # Listen on 127.0.0.1 only
    netsh interface portproxy add v4tov4 listenaddress=127.0.0.1 listenport=80 connectaddress=127.0.0.1 connectport=$port | Out-Null
    Write-Host "Configured portproxy 127.0.0.1:80 -> 127.0.0.1:$port" -ForegroundColor Green
  }
}

if ($mode -eq '1') {
  Write-Host "Checking Docker..." -ForegroundColor Cyan
  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw "Docker not found. Install Docker Desktop." }
  docker info | Out-Null
  docker compose version | Out-Null

  Write-Host "Building + starting container..." -ForegroundColor Cyan
  Push-Location $repoDir
  docker compose up -d --build
  Pop-Location
  Write-Host "vilinks container is running" -ForegroundColor Green
}
elseif ($mode -eq '2') {
  Write-Host "Setting up native Python venv..." -ForegroundColor Cyan
  if (-not (Get-Command python -ErrorAction SilentlyContinue)) { throw "Python not found. Install Python 3.11+" }

  $venv = Join-Path $dataDir 'venv'
  python -m venv $venv
  & (Join-Path $venv 'Scripts\pip.exe') install -r (Join-Path $repoDir 'requirements.txt') | Out-Null
  Write-Host "Dependencies installed" -ForegroundColor Green

  Write-Host "Starting vilinks..." -ForegroundColor Cyan
  $env:VILINKS_DATA_DIR = $dataDir
  & (Join-Path $repoDir 'scripts\run.ps1') -Action start -Port $port -HostName $hostName
}
else {
  throw "Unknown mode '$mode'"
}

Write-Host "" 
Write-Host "vilinks installed!" -ForegroundColor Green
if ($admin -and ($forward80 -match '^[Yy]$')) {
  Write-Host "→ http://$hostName/" -ForegroundColor Green
} elseif ($admin -and ($addHosts -match '^[Yy]$')) {
  Write-Host "→ http://$hostName:$port/" -ForegroundColor Green
} else {
  Write-Host "→ http://$hostName.localhost:$port/" -ForegroundColor Green
}
Write-Host "" 
