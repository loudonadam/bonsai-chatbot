param(
  [string]$ConfigFile = "config.yaml",
  [string]$ModelPath = "models\\bonsai-gguf.gguf",
  [string]$ServerBinary = "scripts\\llama-server.exe",
  [string]$ApiHost = "0.0.0.0",
  [int]$ApiPort = 8000,
  [int]$UiPort = 3000,
  [switch]$SkipModel,
  [switch]$NoBrowser
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path $scriptDir -Parent
Set-Location $repoRoot

Write-Host "[INFO] Bonsai Chatbot quick launch (single PowerShell window)" -ForegroundColor Cyan
Write-Host "[INFO] Repo root: $repoRoot"

$pythonCmd = "python"
$venvPython = Join-Path $repoRoot ".venv\\Scripts\\python.exe"
if (Test-Path $venvPython) {
  $pythonCmd = $venvPython
  Write-Host "[INFO] Using venv Python at $venvPython" -ForegroundColor Cyan
} else {
  Write-Host "[INFO] No .venv detected; using system Python from PATH." -ForegroundColor Yellow
}

if ((-not (Test-Path $venvPython)) -and (-not (Get-Command python -ErrorAction SilentlyContinue))) {
  Write-Error "Python not found on PATH. Install Python 3.11+ and reopen this window."
  exit 1
}

if (-not (Test-Path $ConfigFile)) {
  Write-Error "$ConfigFile not found in $repoRoot. Copy config.example.yaml to config.yaml and edit paths."
  exit 1
}

if (-not (Test-Path "app/requirements.txt")) {
  Write-Warning "app/requirements.txt not found. Ensure dependencies are installed."
}

if (-not $env:PYTHONPATH) {
  $env:PYTHONPATH = $repoRoot
  Write-Host "[INFO] Set PYTHONPATH=$repoRoot" -ForegroundColor Yellow
}

foreach ($folder in @("data/raw", "data/index")) {
  if (-not (Test-Path $folder)) {
    Write-Host "[INFO] Creating $folder..."
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
  }
}

$logsDir = Join-Path $repoRoot "logs"
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null

$function:Assert-PortAvailable = {
  param(
    [int]$Port,
    [string]$Name
  )
  $listener = $null
  try {
    $listener = [System.Net.Sockets.TcpListener]::Create($Port)
    $listener.Start()
  } catch {
    Write-Error "$Name port $Port is already in use. Close the existing process or rerun with a different port (ApiPort/UiPort)." -ErrorAction Stop
  } finally {
    if ($listener) {
      $listener.Stop()
    }
  }
}

$processes = @()
function Start-LoggedProcess {
  param(
    [string]$Name,
    [string]$FilePath,
    [string[]]$ArgumentList = @()
  )
  $stdoutLog = Join-Path $logsDir "$Name-stdout.log"
  $stderrLog = Join-Path $logsDir "$Name-stderr.log"
  $startParams = @{
    PassThru               = $true
    WindowStyle            = "Hidden"
    FilePath               = $FilePath
    RedirectStandardOutput = $stdoutLog
    RedirectStandardError  = $stderrLog
  }
  if ($ArgumentList -and ($ArgumentList.Count -gt 0)) {
    $startParams.ArgumentList = $ArgumentList
  }
  $proc = Start-Process @startParams
  Write-Host "[STARTED] $Name -> $stdoutLog / $stderrLog"
  return $proc
}

if (-not $SkipModel) {
  if ((Test-Path $ServerBinary) -and (Test-Path $ModelPath)) {
    Assert-PortAvailable -Port 8080 -Name "Model (llama.cpp)"
    $llamaArgs = @("--model", $ModelPath, "--host", "127.0.0.1", "--port", "8080", "--ctx-size", "4096", "--n-gpu-layers", "35", "--embedding")
    $processes += Start-LoggedProcess -Name "llama-server" -FilePath $ServerBinary -Args $llamaArgs
  } elseif (-not (Test-Path $ServerBinary)) {
    Write-Warning "llama-server.exe not found at $ServerBinary; skipping model server."
  } else {
    Write-Warning "Model file not found at $ModelPath; skipping model server."
  }
} else {
  Write-Host "[INFO] SkipModel set; not launching llama-server."
}

Assert-PortAvailable -Port $ApiPort -Name "API"
$apiArgs = @("-m", "uvicorn", "app.main:app", "--host", $ApiHost, "--port", $ApiPort)
$processes += Start-LoggedProcess -Name "api" -FilePath $pythonCmd -ArgumentList $apiArgs

Assert-PortAvailable -Port $UiPort -Name "UI"
$uiArgs = @("-m", "http.server", "$UiPort", "-d", "ui")
$processes += Start-LoggedProcess -Name "ui" -FilePath $pythonCmd -ArgumentList $uiArgs

if (-not $NoBrowser) {
  Write-Host "[INFO] Opening browser to http://localhost:$UiPort"
  Start-Process "http://localhost:$UiPort" | Out-Null
}

Write-Host "" 
Write-Host "[INFO] Services are running. Logs: $logsDir" -ForegroundColor Green
Write-Host "[INFO] Press Enter to stop all processes." -ForegroundColor Yellow
Read-Host | Out-Null

foreach ($proc in $processes) {
  if ($proc -and -not $proc.HasExited) {
    try {
      $proc.CloseMainWindow() | Out-Null
      Start-Sleep -Milliseconds 300
    } catch {}
    if (-not $proc.HasExited) {
      Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
  }
}

Write-Host "[INFO] All processes stopped." -ForegroundColor Cyan
