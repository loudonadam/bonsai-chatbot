[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")
Set-Location $repoRoot

# Match the values used by start_model.bat
$MODEL_PATH = "C:\Users\loudo\Desktop\bonsai-chatbot\bonsai-chatbot\models\bonsai-gguf.gguf"
$SERVER_BIN = "C:\Users\loudo\llama.cpp\build\bin\Release\llama-server.exe"
$BASE_PORT = 8080
$MAX_PORT_SEARCH = 20
$LOGS_DIR = Join-Path $repoRoot "logs"
$STDOUT_LOG = Join-Path $LOGS_DIR "llama-server-stdout.log"
$STDERR_LOG = Join-Path $LOGS_DIR "llama-server-stderr.log"
# Optional Vulkan overrides (leave blank to let llama.cpp choose)
$VULKAN_DEVICE = ""
$VULKAN_ICD_FILENAMES = ""

function PauseAndExit {
  param(
    [int]$Code = 0,
    [string]$Message = ""
  )
  if ($Message) {
    if ($Code -eq 0) {
      Write-Host $Message
    } else {
      Write-Host $Message -ForegroundColor Red
    }
  }
  Read-Host "Press Enter to exit" | Out-Null
  exit $Code
}

try {
  if ($VULKAN_DEVICE) {
    $env:GGML_VULKAN_DEVICE = $VULKAN_DEVICE
    Write-Host "Using GGML_VULKAN_DEVICE=$($env:GGML_VULKAN_DEVICE)"
  }
  if ($VULKAN_ICD_FILENAMES) {
    $env:VK_ICD_FILENAMES = $VULKAN_ICD_FILENAMES
    Write-Host "Using VK_ICD_FILENAMES=$($env:VK_ICD_FILENAMES)"
  }

  if (-not (Test-Path $LOGS_DIR)) {
    New-Item -ItemType Directory -Force -Path $LOGS_DIR | Out-Null
  }

  if (-not (Test-Path $SERVER_BIN)) {
    PauseAndExit -Code 1 -Message "llama-server.exe not found at $SERVER_BIN`nDownload the Windows release of llama.cpp and place llama-server.exe here."
  }

  $serverName = Split-Path $SERVER_BIN -Leaf
  if ($serverName -ieq "llama-cli.exe") {
    PauseAndExit -Code 1 -Message "SERVER_BIN currently points to llama-cli.exe, which does not support --host/--port.`nPlease point SERVER_BIN to llama-server.exe instead."
  }

  if (-not (Test-Path $MODEL_PATH)) {
    PauseAndExit -Code 1 -Message "Model file not found at $MODEL_PATH"
  }

  function Get-AvailablePort {
    param(
      [int]$BasePort,
      [int]$MaxSearch
    )

    for ($port = $BasePort; $port -le ($BasePort + $MaxSearch); $port++) {
      $listener = $null
      try {
        $listener = [System.Net.Sockets.TcpListener]::Create($port)
        $listener.Start()
        return $port
      } catch {
        continue
      } finally {
        if ($listener) { $listener.Stop() }
      }
    }

    throw "No free port found between $BasePort and $($BasePort + $MaxSearch)."
  }

  $PORT = Get-AvailablePort -BasePort $BASE_PORT -MaxSearch $MAX_PORT_SEARCH
  Write-Host "Using port $PORT."

  Write-Host "Writing llama.cpp logs to:" -ForegroundColor Cyan
  Write-Host "  $STDOUT_LOG"
  Write-Host "  $STDERR_LOG"
  Write-Host ""

  $arguments = @(
    "--model", $MODEL_PATH,
    "--host", "127.0.0.1",
    "--port", "$PORT",
    "--ctx-size", "4096",
    "--n-gpu-layers", "-1",
    "--embedding"
  )

  & $SERVER_BIN @arguments 1>> $STDOUT_LOG 2>> $STDERR_LOG
  $exitCode = $LASTEXITCODE

  if ($exitCode -ne 0) {
    PauseAndExit -Code $exitCode -Message "llama-server exited with error level $exitCode. Review the log files above for details."
  }

  PauseAndExit -Code 0 -Message "llama-server exited normally."
} catch {
  PauseAndExit -Code 1 -Message $_
}
