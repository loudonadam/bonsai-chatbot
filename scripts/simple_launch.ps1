param(
  [string]$ConfigFile = "config.yaml",
  [string]$ModelPath = "",
  [string]$ServerBinary = "",
  [int]$ModelPort = 8080,
  [int]$ApiPort = 8010,
  [int]$UiPort = 3000,
  [switch]$SkipModel,
  [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path $scriptDir -Parent
Set-Location $repoRoot

# Default paths
if (-not $ModelPath) { $ModelPath = Join-Path $repoRoot "models\bonsai-gguf.gguf" }
if (-not $ServerBinary) { $ServerBinary = "C:\Users\loudo\llama.cpp\build\bin\Release\llama-server.exe" }

$logsDir = Join-Path $repoRoot "logs"
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null

# Track processes for cleanup
$script:processes = @()

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

function Write-Step {
  param([string]$Message)
  Write-Host ""
  Write-Host "===============================================================" -ForegroundColor Cyan
  Write-Host " $Message" -ForegroundColor Cyan
  Write-Host "===============================================================" -ForegroundColor Cyan
}

function Write-Success {
  param([string]$Message)
  Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Info {
  param([string]$Message)
  Write-Host "[INFO] $Message" -ForegroundColor Yellow
}

function Write-Error-Fatal {
  param([string]$Message)
  Write-Host ""
  Write-Host "[ERROR] $Message" -ForegroundColor Red
  Write-Host ""
  Cleanup-All
  Read-Host "Press Enter to exit"
  exit 1
}

function Test-PortAvailable {
  param([int]$Port)
  $listener = $null
  try {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
    $listener.Start()
    return $true
  } catch {
    return $false
  } finally {
    if ($listener) { $listener.Stop() }
  }
}

function Find-AvailablePort {
  param([int]$StartPort, [int]$MaxAttempts = 20)
  for ($i = 0; $i -lt $MaxAttempts; $i++) {
    $port = $StartPort + $i
    if (Test-PortAvailable -Port $port) {
      return $port
    }
  }
  throw "Could not find available port starting at $StartPort"
}

function Wait-ForUrl {
  param(
    [string]$Url,
    [string]$Name,
    [int]$TimeoutSeconds = 60,
    [scriptblock]$SuccessCheck = { param($response) $response.StatusCode -eq 200 }
  )
  
  Write-Info "Waiting for $Name to be ready..."
  $startTime = Get-Date
  $lastError = ""
  
  while ($true) {
    $elapsed = (Get-Date) - $startTime
    if ($elapsed.TotalSeconds -gt $TimeoutSeconds) {
      Write-Error-Fatal "$Name did not start within $TimeoutSeconds seconds. Last error: $lastError`nCheck logs in: $logsDir"
    }
    
    try {
      $response = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
      if (& $SuccessCheck $response) {
        Write-Success "$Name is ready!"
        return $true
      }
    } catch {
      $lastError = $_.Exception.Message
      Write-Host "." -NoNewline -ForegroundColor DarkGray
      Start-Sleep -Seconds 2
    }
  }
}

function Cleanup-All {
  Write-Host ""
  Write-Info "Cleaning up processes..."
  
  foreach ($proc in $script:processes) {
    if ($proc -and -not $proc.HasExited) {
      try {
        Write-Host "  Stopping $($proc.ProcessName) (PID: $($proc.Id))" -ForegroundColor DarkGray
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
      } catch {
        # Ignore errors during cleanup
      }
    }
  }
  
  Write-Success "Cleanup complete"
}

function Ensure-Python {
  Write-Step "CHECKING PYTHON"
  
  $venvPython = Join-Path $repoRoot ".venv\Scripts\python.exe"
  
  if (Test-Path $venvPython) {
    Write-Success "Found virtual environment: $venvPython"
    return $venvPython
  }
  
  # Find system Python
  $pythonCmd = $null
  if ($cmd = Get-Command "python" -ErrorAction SilentlyContinue) {
    $pythonCmd = $cmd.Path
  } elseif ($cmd = Get-Command "py" -ErrorAction SilentlyContinue) {
    $pythonCmd = (& py -3 -c "import sys; print(sys.executable)") -replace "`r|`n",""
  } else {
    Write-Error-Fatal "Python not found. Install Python 3.11+ and ensure it's on PATH"
  }
  
  Write-Info "Creating virtual environment using: $pythonCmd"
  & $pythonCmd -m venv (Join-Path $repoRoot ".venv") | Out-Null
  
  if (-not (Test-Path $venvPython)) {
    Write-Error-Fatal "Failed to create virtual environment"
  }
  
  Write-Info "Installing dependencies..."
  & $venvPython -m pip install --quiet --upgrade pip
  & $venvPython -m pip install --quiet -r (Join-Path $repoRoot "app\requirements.txt")
  
  if ($LASTEXITCODE -ne 0) {
    Write-Error-Fatal "Failed to install Python dependencies"
  }
  
  Write-Success "Python environment ready"
  return $venvPython
}

# ============================================================================
# MAIN LAUNCH SEQUENCE
# ============================================================================

try {
  Write-Host ""
  Write-Host "===============================================================" -ForegroundColor Cyan
  Write-Host "                 BONSAI CHATBOT LAUNCHER                       " -ForegroundColor Cyan
  Write-Host "===============================================================" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "Repository: $repoRoot" -ForegroundColor DarkGray
  Write-Host "Logs: $logsDir" -ForegroundColor DarkGray
  Write-Host ""
  
  # Register cleanup handler
  Register-EngineEvent PowerShell.Exiting -Action { Cleanup-All } | Out-Null
  
  # -------------------------------------------------------------------------
  # STEP 1: VALIDATE CONFIGURATION
  # -------------------------------------------------------------------------
  Write-Step "VALIDATING CONFIGURATION"
  
  if (-not (Test-Path $ConfigFile)) {
    Write-Error-Fatal "$ConfigFile not found. Copy config.example.yaml to $ConfigFile"
  }
  Write-Success "Config file found: $ConfigFile"
  
  # -------------------------------------------------------------------------
  # STEP 2: SETUP PYTHON ENVIRONMENT
  # -------------------------------------------------------------------------
  $pythonCmd = Ensure-Python
  
  # -------------------------------------------------------------------------
  # STEP 3: START MODEL SERVER (if not skipped)
  # -------------------------------------------------------------------------
  $modelApiBase = "http://127.0.0.1:$ModelPort/v1"
  
  if (-not $SkipModel) {
    Write-Step "STARTING MODEL SERVER"
    
    if (-not (Test-Path $ServerBinary)) {
      Write-Error-Fatal "llama-server.exe not found at: $ServerBinary"
    }
    
    if (-not (Test-Path $ModelPath)) {
      Write-Error-Fatal "Model file not found at: $ModelPath"
    }
    
    # Find available port
    $actualModelPort = Find-AvailablePort -StartPort $ModelPort
    if ($actualModelPort -ne $ModelPort) {
      Write-Info "Port $ModelPort in use, using $actualModelPort instead"
      $ModelPort = $actualModelPort
      $modelApiBase = "http://127.0.0.1:$ModelPort/v1"
    }
    
    Write-Info "Model: $ModelPath"
    Write-Info "Binding to: 127.0.0.1:$ModelPort"
    
    # Start llama-server
    $modelArgs = @(
      "--model", $ModelPath,
      "--alias", "local-llm",
      "--host", "127.0.0.1",
      "--port", "$ModelPort",
      "--ctx-size", "4096",
      "--n-gpu-layers", "-1",
      "--embedding"
    )
    
    $modelProc = Start-Process -FilePath $ServerBinary `
      -ArgumentList $modelArgs `
      -WorkingDirectory $repoRoot `
      -PassThru `
      -WindowStyle Minimized
    
    $script:processes += $modelProc
    Write-Success "Model server process started (PID: $($modelProc.Id))"
    
    # Wait for model to load
    Wait-ForUrl -Url "$modelApiBase/models" -Name "Model server" -TimeoutSeconds 90 -SuccessCheck {
      param($response)
      if ($response.StatusCode -eq 200) {
        $data = $response.Content | ConvertFrom-Json
        return ($data.data -and $data.data.Count -gt 0)
      }
      return $false
    }
  } else {
    Write-Step "SKIPPING MODEL SERVER"
    Write-Info "Assuming model server is already running at: $modelApiBase"
  }
  
  # -------------------------------------------------------------------------
  # STEP 4: START API SERVER
  # -------------------------------------------------------------------------
  Write-Step "STARTING API SERVER"
  
  # Set environment variable for API to find model
  $env:BONSAI_MODEL_API_BASE = $modelApiBase
  Write-Info "API will connect to: $modelApiBase"
  
  # Find available port
  $actualApiPort = Find-AvailablePort -StartPort $ApiPort
  if ($actualApiPort -ne $ApiPort) {
    Write-Info "Port $ApiPort in use, using $actualApiPort instead"
    $ApiPort = $actualApiPort
  }
  
  Write-Info "Binding to: 0.0.0.0:$ApiPort"
  
  $apiProc = Start-Process -FilePath $pythonCmd `
    -ArgumentList @("-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "$ApiPort") `
    -WorkingDirectory $repoRoot `
    -PassThru `
    -WindowStyle Minimized
  
  $script:processes += $apiProc
  Write-Success "API server process started (PID: $($apiProc.Id))"
  
  Wait-ForUrl -Url "http://localhost:$ApiPort/health" -Name "API server" -TimeoutSeconds 30
  
  # -------------------------------------------------------------------------
  # STEP 5: START UI SERVER
  # -------------------------------------------------------------------------
  Write-Step "STARTING UI SERVER"
  
  # Find available port
  $actualUiPort = Find-AvailablePort -StartPort $UiPort
  if ($actualUiPort -ne $UiPort) {
    Write-Info "Port $UiPort in use, using $actualUiPort instead"
    $UiPort = $actualUiPort
  }
  
  # Write UI config
  $uiApiBase = "http://localhost:$ApiPort"
  $uiConfigPath = Join-Path $repoRoot "ui\config.js"
  $configContent = @"
// Auto-generated by simple_launch.ps1
window.BONSAI_API_BASE = "$uiApiBase";
"@
  Set-Content -Path $uiConfigPath -Value $configContent -Encoding UTF8
  Write-Info "Updated ui\config.js to point to: $uiApiBase"
  
  Write-Info "Binding to: localhost:$UiPort"
  
  $uiProc = Start-Process -FilePath $pythonCmd `
    -ArgumentList @("-m", "http.server", "$UiPort", "-d", "ui") `
    -WorkingDirectory $repoRoot `
    -PassThru `
    -WindowStyle Minimized
  
  $script:processes += $uiProc
  Write-Success "UI server process started (PID: $($uiProc.Id))"
  
  Wait-ForUrl -Url "http://localhost:$UiPort" -Name "UI server" -TimeoutSeconds 15
  
  # -------------------------------------------------------------------------
  # LAUNCH COMPLETE
  # -------------------------------------------------------------------------
  Write-Host ""
  Write-Host "===============================================================" -ForegroundColor Green
  Write-Host "                  LAUNCH SUCCESSFUL                            " -ForegroundColor Green
  Write-Host "===============================================================" -ForegroundColor Green
  Write-Host ""
  
  if (-not $SkipModel) {
    Write-Host "  Model Server:  http://127.0.0.1:$ModelPort" -ForegroundColor Cyan
  }
  Write-Host "  API Server:    http://localhost:$ApiPort" -ForegroundColor Cyan
  Write-Host "  UI Server:     http://localhost:$UiPort" -ForegroundColor Cyan
  Write-Host "  Logs:          $logsDir" -ForegroundColor DarkGray
  Write-Host ""
  
  if (-not $NoBrowser) {
    Write-Info "Opening browser..."
    Start-Process "http://localhost:$UiPort"
  }
  
  Write-Host ""
  Write-Host "Press Ctrl+C or close this window to stop all services" -ForegroundColor Yellow
  Write-Host ""
  
  # Keep running until user stops
  while ($true) {
    Start-Sleep -Seconds 5
    
    # Check if any process has died
    foreach ($proc in $script:processes) {
      if ($proc.HasExited) {
        Write-Host ""
        Write-Host "[WARNING] Process $($proc.ProcessName) (PID: $($proc.Id)) has exited unexpectedly" -ForegroundColor Red
        Write-Host "  Check logs in: $logsDir" -ForegroundColor Yellow
        Cleanup-All
        Read-Host "Press Enter to exit"
        exit 1
      }
    }
  }
  
} catch {
  Write-Host ""
  Write-Host "[FATAL ERROR]" -ForegroundColor Red
  Write-Host $_.Exception.Message -ForegroundColor Red
  Write-Host ""
  Write-Host "Stack trace:" -ForegroundColor DarkGray
  Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
  Cleanup-All
  Read-Host "Press Enter to exit"
  exit 1
} finally {
  Cleanup-All
}