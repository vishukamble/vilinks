$ErrorActionPreference = "Stop"

$Owner = $env:VILINKS_OWNER; if (!$Owner) { $Owner = "vishukamble" }
$Repo  = $env:VILINKS_REPO;  if (!$Repo)  { $Repo  = "vilinks" }
$Ref   = $env:VILINKS_REF;   if (!$Ref)   { $Ref   = "main" }

$InstallDir = $env:VILINKS_INSTALL_DIR
if (!$InstallDir) { $InstallDir = Join-Path $env:LOCALAPPDATA "vilinks" }

$DataDir = $env:VILINKS_DATA_DIR
if (!$DataDir) { $DataDir = Join-Path $env:USERPROFILE ".vilinks" }

$CfgFile = Join-Path $InstallDir "config.env"

function Info($m){ Write-Host "→ $m" -ForegroundColor Cyan }
function Ok($m){ Write-Host "✓ $m" -ForegroundColor Green }
function Warn($m){ Write-Host "⚠ $m" -ForegroundColor Yellow }
function Die($m){ Write-Host "✗ $m" -ForegroundColor Red; exit 1 }

function DownloadAndExtract {
  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  $tmp = New-Item -ItemType Directory -Force -Path (Join-Path $env:TEMP ("vilinks_" + [guid]::NewGuid().ToString()))

  $zipUrl = "https://github.com/$Owner/$Repo/archive/refs/heads/$Ref.zip"
  $zipPath = Join-Path $tmp.FullName "vilinks.zip"

  Info "Downloading $Owner/$Repo ($Ref)..."
  Invoke-WebRequest -UseBasicParsing -Uri $zipUrl -OutFile $zipPath

  Info "Extracting..."
  $srcDir = Join-Path $InstallDir "src"
  if (Test-Path $srcDir) { Remove-Item -Recurse -Force $srcDir }
  Expand-Archive -Force -Path $zipPath -DestinationPath $tmp.FullName

  $extracted = Get-ChildItem $tmp.FullName -Directory | Where-Object { $_.Name -like "$Repo-*" } | Select-Object -First 1
  if (!$extracted) { Die "Could not find extracted folder." }

  New-Item -ItemType Directory -Force -Path $srcDir | Out-Null
  Copy-Item -Recurse -Force -Path (Join-Path $extracted.FullName "*") -Destination $srcDir

  Remove-Item -Recurse -Force $tmp.FullName
  Ok "Installed source → $srcDir"
}

function WriteConfig($prefix, $port) {
  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

@"
VILINKS_PREFIX=$prefix
VILINKS_PORT=$port
VILINKS_DB=$DataDir\vilinks.db
"@ | Set-Content -Encoding ASCII -Path $CfgFile

  Ok "Config → $CfgFile"
}

function DockerUp {
  if (!(Get-Command docker -ErrorAction SilentlyContinue)) { Die "docker not found." }
  Info "Starting vilinks (Docker)..."
  Push-Location (Join-Path $InstallDir "src")
  docker compose up -d --build | Out-Null
  Pop-Location
  Ok "vilinks is running (Docker)"
}

function PythonUp {
  $py = Get-Command python -ErrorAction SilentlyContinue
  if (!$py) { Die "python not found. Install Python 3.10+." }

  $venv = Join-Path $InstallDir "venv"
  Info "Setting up venv..."
  Push-Location (Join-Path $InstallDir "src")
  python -m venv $venv
  & (Join-Path $venv "Scripts\python.exe") -m pip install -U pip | Out-Null
  & (Join-Path $venv "Scripts\python.exe") -m pip install -r requirements.txt | Out-Null

  Info "Starting vilinks (Python)..."
  $envs = Get-Content $CfgFile | Where-Object { $_ -and ($_ -notmatch '^#') }
  foreach ($line in $envs) {
    $kv = $line.Split("=",2)
    [System.Environment]::SetEnvironmentVariable($kv[0], $kv[1], "Process")
  }

  # Start background
  $p = Start-Process -FilePath (Join-Path $venv "Scripts\python.exe") -ArgumentList "app.py" -PassThru -WindowStyle Hidden
  $pidPath = Join-Path $InstallDir "vilinks.pid"
  $p.Id | Set-Content -Path $pidPath
  Pop-Location
  Ok "vilinks started (Python) pid=$($p.Id)"
}

function MaybePrettyUrl($prefix, $port) {
  $ans = Read-Host "Set up pretty URL http://$prefix/ (hosts + port 80 forward; requires Admin)? [y/N]"
  if ($ans -notmatch '^[Yy]') { return }

  # Hosts file
  $hosts = "$env:WINDIR\System32\drivers\etc\hosts"
  $entry = "127.0.0.1 $prefix"
  $content = Get-Content $hosts -ErrorAction Stop
  if ($content -contains $entry) {
    Ok "Hosts entry already present"
  } else {
    Info "Adding hosts entry..."
    Add-Content -Path $hosts -Value $entry
    Ok "Added hosts entry"
  }

  # Port 80 → $port using netsh portproxy
  Info "Configuring portproxy 80 → $port..."
  & netsh interface portproxy add v4tov4 listenaddress=127.0.0.1 listenport=80 connectaddress=127.0.0.1 connectport=$port | Out-Null
  Ok "Pretty URL enabled: http://$prefix/"
}

Write-Host ""
Write-Host "vilinks installer" -ForegroundColor White
Write-Host ""

DownloadAndExtract

$prefix = Read-Host "Prefix hostname (default: vi)"
if (!$prefix) { $prefix = "vi" }
$port = Read-Host "App port (default: 8765)"
if (!$port) { $port = "8765" }

WriteConfig $prefix $port

Write-Host ""
Write-Host "Install method:"
Write-Host "  1) Docker (recommended)"
Write-Host "  2) Python (venv, no Docker)"
$choice = Read-Host "Choose [1/2] (default 1)"
if (!$choice) { $choice = "1" }

if ($choice -eq "1") { DockerUp } elseif ($choice -eq "2") { PythonUp } else { Die "Invalid choice." }

MaybePrettyUrl $prefix $port

Write-Host ""
Ok "Done."
Write-Host ("Open (no admin): http://{0}.localhost:{1}/" -f $prefix, $port)
Write-Host ("Config:          {0}" -f $CfgFile)
Write-Host ("Data:            {0}\vilinks.db" -f $DataDir)
Write-Host ""