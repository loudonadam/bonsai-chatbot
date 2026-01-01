param(
  [string]$ConfigFile = "config.yaml",
  [string]$ModelPath,
  [string]$ServerBinary,
  [string]$ApiHost = "0.0.0.0",
  [int]$ApiPort = 8010,
  [int]$UiPort = 3000,
  [int]$BaseModelPort = 8080,
  [int]$MaxPortSearch = 20,
  [switch]$SkipModel,
  [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path $scriptDir -Parent
Set-Location $repoRoot

$defaultModelPath = "C:\Users\loudo\Desktop\bonsai-chatbot\bonsai-chatbot\models\bonsai-gguf.gguf"
$defaultServerBinary = "C:\Users\loudo\llama.cpp\build\bin\Release\llama-server.exe"
$logsDir = Join-Path $repoRoot "logs"
$modelStdout = Join-Path $logsDir "llama-server-stdout.log"
$modelStderr = Join-Path $logsDir "llama-server-stderr.log"
$apiStdout = Join-Path $logsDir "api-stdout.log"
$apiStderr = Join-Path $logsDir "api-stderr.log"
$uiStdout = Join-Path $logsDir "ui-stdout.log"
$uiStderr = Join-Path $logsDir "ui-stderr.log"

if (-not $ModelPath) { $ModelPath = $defaultModelPath }
if (-not $ServerBinary) { $ServerBinary = $defaultServerBinary }

Write-Host "[INFO] Repo root: $repoRoot" -ForegroundColor Cyan
Write-Host "[INFO] Model path: $ModelPath"
Write-Host "[INFO] llama-server path: $ServerBinary"
Write-Host "[INFO] Base model port: $BaseModelPort (searching up to $MaxPortSearch ports)"

New-Item -ItemType Directory -Force -Path $logsDir | Out-Null

function Fail-AndPause {
  param([string]$Message)
  Write-Host "[ERROR] $Message" -ForegroundColor Red
  Write-Host "[INFO] Logs live in $logsDir" -ForegroundColor Yellow
  Read-Host "Press Enter to exit" | Out-Null
  exit 1
}

function Get-AvailablePort {
  param(
    [int]$StartingPort,
    [int]$MaxAttempts = 20,
    [string]$Name = "port"
  )
  $port = $StartingPort
  for ($i = 0; $i -lt $MaxAttempts; $i++) {
    $listener = $null
    try {
      $listener = [System.Net.Sockets.TcpListener]::Create($port)
      $listener.Start()
      return $port
    } catch {
      $port++
    } finally {
      if ($listener) { $listener.Stop() }
    }
  }
  throw "No open $Name found between $StartingPort and $($StartingPort + $MaxAttempts - 1)."
}

function Start-LoggedProcess {
  param(
    [string]$Name,
    [string]$FilePath,
    [string[]]$Args = @(),
    [string]$StdoutPath,
    [string]$StderrPath,
    [string]$WorkingDir
  )

  if (-not (Test-Path $FilePath)) {
    throw "$Name failed to start because file was not found: $FilePath"
  }

  $startParams = @{
    FilePath               = $FilePath
    ArgumentList           = $Args
    WorkingDirectory       = $WorkingDir
    RedirectStandardOutput = $StdoutPath
    RedirectStandardError  = $StderrPath
    WindowStyle            = "Hidden"
    PassThru               = $true
  }

  $proc = Start-Process @startParams
  Start-Sleep -Milliseconds 400
  Wait-Process -Id $proc.Id -Timeout 1 -ErrorAction SilentlyContinue | Out-Null

  if ($proc.HasExited) {
    $code = $proc.ExitCode
    $errTail = ""
    if (Test-Path $StderrPath) {
      $errTail = (Get-Content -Path $StderrPath -Tail 20 -ErrorAction SilentlyContinue) -join "`n"
    }
    $outTail = ""
    if (Test-Path $StdoutPath) {
      $outTail = (Get-Content -Path $StdoutPath -Tail 10 -ErrorAction SilentlyContinue) -join "`n"
    }
    $msg = "$Name exited immediately with code $code. Command: `"$FilePath`" $($Args -join ' ')."
    if ($errTail) { $msg += "`nLast stderr lines:`n$errTail" }
    if (-not $errTail -and $outTail) { $msg += "`nLast stdout lines:`n$outTail" }
    throw $msg
  }

  Write-Host "[STARTED] $Name (stdout: $StdoutPath, stderr: $StderrPath)"
  return $proc
}

try {
  $pythonCmd = "python"
  if (-not (Get-Command $pythonCmd -ErrorAction SilentlyContinue)) {
    throw "Python not found on PATH. Install Python 3.11+ and retry."
  }

  if (-not (Test-Path $ConfigFile)) {
    throw "$ConfigFile not found. Copy config.example.yaml to $ConfigFile and update paths."
  }

  $modelPort = $null
  $processes = @()

  if (-not $SkipModel) {
    if (-not (Test-Path $ServerBinary)) {
      throw "llama-server.exe not found at $ServerBinary. Update scripts\start_model.bat and this script to point to your llama.cpp build."
    }
    $serverName = Split-Path $ServerBinary -Leaf
    if ($serverName -ieq "llama-cli.exe") {
      throw "ServerBinary points to llama-cli.exe, which does not support --host/--port. Use llama-server.exe."
    }
    if (-not (Test-Path $ModelPath)) {
      throw "Model file not found at $ModelPath. Update ModelPath to your GGUF file."
    }

    $modelPort = Get-AvailablePort -StartingPort $BaseModelPort -MaxAttempts $MaxPortSearch -Name "model port"
    if ($modelPort -ne $BaseModelPort) {
      Write-Host "[INFO] Model base port $BaseModelPort in use; switching to $modelPort." -ForegroundColor Yellow
    }

    $modelArgs = @(
      "--model", $ModelPath,
      "--host", "127.0.0.1",
      "--port", "$modelPort",
      "--ctx-size", "4096",
      "--n-gpu-layers", "-1",
      "--embedding"
    )
    $processes += Start-LoggedProcess -Name "llama-server" -FilePath $ServerBinary -Args $modelArgs -StdoutPath $modelStdout -StderrPath $modelStderr -WorkingDir $repoRoot
  } else {
    Write-Host "[INFO] SkipModel set; not launching llama-server."
  }

  $apiPort = Get-AvailablePort -StartingPort $ApiPort -MaxAttempts $MaxPortSearch -Name "API port"
  if ($apiPort -ne $ApiPort) {
    Write-Host "[INFO] API base port $ApiPort in use; switching to $apiPort." -ForegroundColor Yellow
  }
  $apiArgs = @("-m", "uvicorn", "app.main:app", "--host", $ApiHost, "--port", $apiPort)
  $processes += Start-LoggedProcess -Name "api" -FilePath $pythonCmd -Args $apiArgs -StdoutPath $apiStdout -StderrPath $apiStderr -WorkingDir $repoRoot

  $uiPort = Get-AvailablePort -StartingPort $UiPort -MaxAttempts $MaxPortSearch -Name "UI port"
  if ($uiPort -ne $UiPort) {
    Write-Host "[INFO] UI base port $UiPort in use; switching to $uiPort." -ForegroundColor Yellow
  }
  $uiArgs = @("-m", "http.server", "$uiPort", "-d", "ui")
  $processes += Start-LoggedProcess -Name "ui" -FilePath $pythonCmd -Args $uiArgs -StdoutPath $uiStdout -StderrPath $uiStderr -WorkingDir $repoRoot

  if (-not $NoBrowser) {
    Write-Host "[INFO] Opening browser to http://localhost:$uiPort"
    Start-Process "http://localhost:$uiPort" | Out-Null
  }

  Write-Host ""
  if (-not $SkipModel -and $modelPort) {
    Write-Host "[INFO] Model server: http://127.0.0.1:$modelPort" -ForegroundColor Cyan
  }
  Write-Host ("[INFO] API:   http://{0}:{1}" -f $ApiHost, $apiPort) -ForegroundColor Cyan
  Write-Host "[INFO] UI:    http://localhost:$uiPort" -ForegroundColor Cyan
  Write-Host "[INFO] Logs:  $logsDir" -ForegroundColor Cyan
  Write-Host "[INFO] Press Enter to stop all processes." -ForegroundColor Yellow
  Read-Host | Out-Null

  foreach ($proc in $processes) {
    if ($proc -and -not $proc.HasExited) {
      try { $proc.CloseMainWindow() | Out-Null } catch {}
      Start-Sleep -Milliseconds 300
      if (-not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
      }
    }
  }

  Write-Host "[INFO] All processes stopped." -ForegroundColor Green
} catch {
  Fail-AndPause -Message $_.Exception.Message
}
