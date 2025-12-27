param(
  [string]$ConfigFile = "config.yaml",
  [string]$ModelPath = "models\\bonsai-gguf.gguf",
  [string]$ServerBinary = "scripts\\llama-server.exe",
  [string]$ApiHost = "0.0.0.0",
  [int]$ApiPort = 8010,
  [int]$UiPort = 3000,
  [switch]$SkipModel,
  [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path $scriptDir -Parent
Set-Location $repoRoot

Write-Host "[INFO] Bonsai Chatbot quick launch (single PowerShell window)" -ForegroundColor Cyan
Write-Host "[INFO] Repo root: $repoRoot"

$logsDir = Join-Path $repoRoot "logs"
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
$errorLog = Join-Path $logsDir "quick-launch-error.log"

function FailAndPause {
  param(
    [string]$Message
  )
  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Write-Host "[ERROR] $Message" -ForegroundColor Red
  if ($Message) {
    "$timestamp`t$Message" | Out-File -FilePath $errorLog -Encoding utf8 -Append
  }
  if (Test-Path $logsDir) {
    Write-Host "[INFO] Check logs in $logsDir (if any were written)" -ForegroundColor Yellow
  }
  Read-Host "Press Enter to exit" | Out-Null
  exit 1
}

try {
  trap {
    FailAndPause -Message $_.Exception.Message
  }

  $pythonCmd = "python"
  $venvPython = Join-Path $repoRoot ".venv\\Scripts\\python.exe"
  if (Test-Path $venvPython) {
    $pythonCmd = $venvPython
    Write-Host "[INFO] Using venv Python at $venvPython" -ForegroundColor Cyan
  } else {
    Write-Host "[INFO] No .venv detected; using system Python from PATH." -ForegroundColor Yellow
  }

  if ((-not (Test-Path $venvPython)) -and (-not (Get-Command python -ErrorAction SilentlyContinue))) {
    throw "Python not found on PATH. Install Python 3.11+ and reopen this window."
  }

  if (-not (Test-Path $ConfigFile)) {
    throw "$ConfigFile not found in $repoRoot. Copy config.example.yaml to config.yaml and edit paths."
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

  function Assert-PortAvailable {
    param(
      [int]$Port,
      [string]$Name
    )
    $listener = $null
    try {
      $listener = [System.Net.Sockets.TcpListener]::Create($Port)
      $listener.Start()
    } catch {
      throw "$Name port $Port is already in use. Close the existing process or rerun with a different port (ApiPort/UiPort)."
    } finally {
      if ($listener) {
        $listener.Stop()
      }
    }
  }

  function Get-AvailablePort {
    param(
      [int]$StartingPort,
      [string]$Name,
      [int]$MaxAttempts = 20
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
        if ($listener) {
          $listener.Stop()
        }
      }
    }
    throw "No open port found for $Name starting at $StartingPort (tried $MaxAttempts ports)."
  }

  $processes = @()
  function Start-LoggedProcess {
    param(
      [string]$Name,
      [string]$FilePath,
      [Alias("Args")][string[]]$ArgumentList = @()
    )
    if (-not (Test-Path $FilePath)) {
      throw "$Name cannot start because file not found: $FilePath"
    }
    $stdoutLog = Join-Path $logsDir "$Name-stdout.log"
    $stderrLog = Join-Path $logsDir "$Name-stderr.log"
    $startParams = @{
      PassThru               = $true
      WindowStyle            = "Hidden"
      FilePath               = $FilePath
      RedirectStandardOutput = $stdoutLog
      RedirectStandardError  = $stderrLog
      ErrorAction            = "Stop"
    }
    if ($ArgumentList -and ($ArgumentList.Count -gt 0)) {
      $startParams.ArgumentList = $ArgumentList
    }
    try {
      $proc = Start-Process @startParams
    } catch {
      throw "$Name failed to start. Command: `"$FilePath`" $($ArgumentList -join ' ')`nError: $($_.Exception.Message)"
    }
    if (-not $proc -or -not $proc.Id) {
      throw "$Name failed to start (process handle missing). Command: `"$FilePath`" $($ArgumentList -join ' ')"
    }
    $proc | Add-Member -NotePropertyName StdoutLog -NotePropertyValue $stdoutLog -Force
    $proc | Add-Member -NotePropertyName StderrLog -NotePropertyValue $stderrLog -Force

    Start-Sleep -Milliseconds 500
    # ensure exit code is populated if the process already died
    Wait-Process -Id $proc.Id -Timeout 1 -ErrorAction SilentlyContinue | Out-Null

    if ($proc.HasExited) {
      $lastError = ""
      if (Test-Path $stderrLog) {
        $lastError = (Get-Content -Path $stderrLog -Tail 20 -ErrorAction SilentlyContinue) -join "`n"
      }
      $lastOut = ""
      if (Test-Path $stdoutLog) {
        $lastOut = (Get-Content -Path $stdoutLog -Tail 10 -ErrorAction SilentlyContinue) -join "`n"
      }
      $exitCode = $proc.ExitCode
      if ($null -eq $exitCode -or "$exitCode" -eq "") {
        $exitCode = "unknown"
      }
      $cmdLine = "`"$FilePath`" $($ArgumentList -join ' ')"
      $message = "$Name exited immediately with code $exitCode. Check $stderrLog."
      if ($lastError) {
        $message += "`nLast stderr lines:`n$lastError"
      }
      if (-not $lastError -and $lastOut) {
        $message += "`nLast stdout lines:`n$lastOut"
      }
      if (-not (Test-Path $stderrLog) -or ((Get-Item $stderrLog).Length -eq 0 -and -not $lastError)) {
        $message += "`nNo stderr output was captured. Confirm the binary exists, the model path is correct, and try running the command manually from the repo root:"
        $message += "`n`n  $cmdLine"
      }
      throw $message
    }

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

  $uiPortToUse = Get-AvailablePort -StartingPort $UiPort -Name "UI"
  if ($uiPortToUse -ne $UiPort) {
    Write-Host "[INFO] UI port $UiPort is busy. Using $uiPortToUse instead." -ForegroundColor Yellow
  }
  $uiArgs = @("-m", "http.server", "$uiPortToUse", "-d", "ui")
  $processes += Start-LoggedProcess -Name "ui" -FilePath $pythonCmd -ArgumentList $uiArgs

  if (-not $NoBrowser) {
    Write-Host "[INFO] Opening browser to http://localhost:$uiPortToUse"
    Start-Process "http://localhost:$uiPortToUse" | Out-Null
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
} catch {
  FailAndPause -Message $_.Exception.Message
}
