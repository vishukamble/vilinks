param(
  [Parameter(Mandatory=$true)][ValidateSet('start','stop','restart','status')]$Action,
  [int]$Port = 8765,
  [string]$HostName = 'vi'
)

$DataDir = $env:VILINKS_DATA_DIR
if (-not $DataDir) { $DataDir = Join-Path $HOME '.vilinks' }

$CfgFile = $env:VILINKS_CONFIG
if (-not $CfgFile) { $CfgFile = Join-Path $DataDir 'config.env' }

$PidFile = Join-Path $DataDir 'vilinks.pid'
$LogFile = Join-Path $DataDir 'vilinks.log'
$VenvDir = Join-Path $DataDir 'venv'
$Python = Join-Path $VenvDir 'Scripts\python.exe'
$RepoDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$AppPy = Join-Path $RepoDir 'app.py'

New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

# Load config.env if present
if (Test-Path $CfgFile) {
  Get-Content $CfgFile | ForEach-Object {
    if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
    $kv = $_.Split('=',2)
    if ($kv.Count -eq 2) {
      [System.Environment]::SetEnvironmentVariable($kv[0], $kv[1], "Process")
    }
  }
}

function Is-Running {
  if (Test-Path $PidFile) {
    $pid = Get-Content $PidFile -ErrorAction SilentlyContinue
    if ($pid) { return (Get-Process -Id $pid -ErrorAction SilentlyContinue) -ne $null }
  }
  return $false
}

function Start-App {
  if (Is-Running) {
    Write-Host "vilinks already running" -ForegroundColor Green
    return
  }
  if (-not (Test-Path $Python)) {
    throw "venv not found at $VenvDir. Use install.ps1 (Python mode) to create it."
  }

  $env:VILINKS_BIND = '127.0.0.1'
  $env:VILINKS_PORT = "$Port"
  $env:VILINKS_PREFIX = $HostName
  $env:VILINKS_DB = (Join-Path $DataDir 'vilinks.db')
  if (-not $env:VILINKS_BASE_URL) {
    $env:VILINKS_BASE_URL = "http://$($HostName).localhost:$($Port)/"
  }

  $p = Start-Process -FilePath $Python -ArgumentList @($AppPy) -RedirectStandardOutput $LogFile -RedirectStandardError $LogFile -PassThru -WindowStyle Hidden
  Set-Content -Path $PidFile -Value $p.Id
  Write-Host "vilinks started (pid $($p.Id))" -ForegroundColor Green
  Write-Host "Open: $($env:VILINKS_BASE_URL)" -ForegroundColor Cyan
}

function Stop-App {
  if (-not (Test-Path $PidFile)) {
    Write-Host "vilinks not running" -ForegroundColor Yellow
    return
  }
  $pid = Get-Content $PidFile -ErrorAction SilentlyContinue
  if ($pid) {
    $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
    if ($proc) { Stop-Process -Id $pid -Force }
  }
  Remove-Item $PidFile -ErrorAction SilentlyContinue
  Write-Host "vilinks stopped" -ForegroundColor Green
}

switch ($Action) {
  'start'   { Start-App }
  'stop'    { Stop-App }
  'restart' { Stop-App; Start-App }
  'status'  { if (Is-Running) { Write-Host 'running' -ForegroundColor Green } else { Write-Host 'stopped' -ForegroundColor Yellow } }
}