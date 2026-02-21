$ErrorActionPreference = 'SilentlyContinue'

function Is-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p = New-Object Security.Principal.WindowsPrincipal($id)
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

Write-Host "`nvilinks uninstaller`n" -ForegroundColor Cyan

$repoDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$envFile = Join-Path $repoDir '.env'
$hostName = 'vi'
$port = 8765
$dataDir = Join-Path $HOME '.vilinks'

if (Test-Path $envFile) {
  Get-Content $envFile | ForEach-Object {
    if ($_ -match '^VILINKS_BASE_HOST=(.+)$') { $hostName = $Matches[1] }
    if ($_ -match '^VILINKS_PORT=(.+)$') { $port = [int]$Matches[1] }
    if ($_ -match '^VILINKS_DATA_DIR=(.+)$') { $dataDir = $Matches[1] }
  }
}

# Stop docker
if (Get-Command docker -ErrorAction SilentlyContinue) {
  docker rm -f vilinks | Out-Null
  Push-Location $repoDir
  docker compose down | Out-Null
  Pop-Location
}

# Stop native
$runPs1 = Join-Path $repoDir 'scripts\run.ps1'
if (Test-Path $runPs1) {
  & $runPs1 -Action stop -Port $port -HostName $hostName | Out-Null
}

$admin = Is-Admin
if ($admin) {
  # Remove portproxy
  netsh interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=80 | Out-Null

  # Remove hosts entry
  $hostsFile = "$env:WINDIR\System32\drivers\etc\hosts"
  $line = "127.0.0.1 $hostName"
  $content = Get-Content $hostsFile
  $content | Where-Object { $_ -ne $line } | Set-Content -Path $hostsFile
}

Write-Host "Removed vilinks (data preserved at $dataDir)" -ForegroundColor Green
Write-Host "To fully wipe: Remove-Item -Recurse -Force $dataDir" -ForegroundColor Yellow
