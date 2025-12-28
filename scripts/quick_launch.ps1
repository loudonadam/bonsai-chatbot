param(
  [string]$ConfigFile = "config.yaml",
  [string]$ModelPath = "models\\bonsai-gguf.gguf",
  [string]$ServerBinary = "C:\\Users\\loudo\Desktop\\src\\llama.cpp\\build\\bin\\Release\\llama-server.exe",
  [string]$ApiHost = "0.0.0.0",
  [int]$ApiPort = 8010,
  [int]$UiPort = 3000,
  [Nullable[int]]$VulkanDevice = $null,
  [string]$VkIcdFilenames = "",
  [string]$PreferredVulkanGpuPattern = "7900",
  [switch]$AutoSelectAmdVkIcd = $true,
  [switch]$DisableVulkanDiagLog,
  [switch]$ClearVulkanDevice,
  [switch]$SkipModel,
  [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path $scriptDir -Parent
Set-Location $repoRoot
$dllExitHint = "Exit code -1073741515 (0xC0000135) usually means a missing DLL or blocked binary. Ensure ggml*.dll, llama.dll, mtmd.dll sit next to llama-server.exe, and right-click > Properties > Unblock. If you built llama.cpp yourself, copy everything from build\\bin\\Release next to the exe."

Write-Host "[INFO] Bonsai Chatbot quick launch (single PowerShell window)" -ForegroundColor Cyan
Write-Host "[INFO] Repo root: $repoRoot"

$logsDir = Join-Path $repoRoot "logs"
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
$errorLog = Join-Path $logsDir "quick-launch-error.log"
$vulkanDiagLog = Join-Path $logsDir "quick-launch-vulkan.log"

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

function Get-VulkanDevicesFromOutput {
  param(
    [string]$Output
  )
  $devices = @()
  foreach ($line in ($Output -split "`r?`n")) {
    if ($line -match "ggml_vulkan:\s*(\d+):\s*(.+)$") {
      $devices += [pscustomobject]@{
        Index = [int]$matches[1]
        Name  = $matches[2].Trim()
      }
    }
  }
  return $devices
}

function Get-VulkanDeviceCountFromOutput {
  param(
    [string]$Output
  )
  $count = $null
  if ($Output -match "ggml_vulkan:\s*Found\s+(\d+)\s+Vulkan devices") {
    $count = [int]$matches[1]
  }
  return $count
}

function Write-VulkanDiagnostics {
  param(
    [string]$BinaryPath,
    [Array]$Devices,
    [Nullable[int]]$DeviceCount,
    [string]$Output,
    [psobject]$SelectedDevice,
    [Array]$RegisteredDrivers
  )
  if ($DisableVulkanDiagLog) { return }
  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $lines = @()
  $lines += "[$timestamp] Vulkan diagnostics"
  $lines += "  Binary: $BinaryPath"
  $lines += "  GGML_VULKAN_DEVICE: $($env:GGML_VULKAN_DEVICE)"
  $lines += "  VK_ICD_FILENAMES: $($env:VK_ICD_FILENAMES)"
  $lines += "  Preferred pattern: $PreferredVulkanGpuPattern"
  $lines += "  AutoSelectAmdVkIcd: $AutoSelectAmdVkIcd"
  if ($RegisteredDrivers -and $RegisteredDrivers.Count -gt 0) {
    $lines += "  Registered Vulkan drivers (registry):"
    foreach ($drv in $RegisteredDrivers) {
      $lines += "    - $($drv.Path)"
    }
  } else {
    $lines += "  Registered Vulkan drivers (registry): none found"
  }
  if ($SelectedDevice) {
    $lines += "  Selected device: index $($SelectedDevice.Index) name '$($SelectedDevice.Name)'"
  }
  if ($DeviceCount -ne $null) {
    $lines += "  Device count (from output): $DeviceCount"
  }
  if ($Devices -and $Devices.Count -gt 0) {
    $lines += "  Parsed devices:"
    foreach ($d in $Devices) {
      $lines += "    - [$($d.Index)] $($d.Name)"
    }
  } else {
    $lines += "  Parsed devices: none"
  }
  if (Test-Path $BinaryPath) {
    $binDir = Split-Path $BinaryPath -Parent
    $lines += "  Binary folder DLLs:"
    foreach ($dll in @("llama.dll","mtmd.dll")) {
      $isPresent = Test-Path (Join-Path $binDir $dll)
      if ($isPresent) {
        $lines += "    - ${dll}: present"
      } else {
        $lines += "    - ${dll}: missing"
      }
    }
    $ggml = Get-ChildItem -Path $binDir -Filter "ggml*.dll" -ErrorAction SilentlyContinue
    if ($ggml) {
      foreach ($g in $ggml) {
        $lines += "    - $($g.Name)"
      }
    } else {
      $lines += "    - ggml*.dll: none found"
    }
  } else {
    $lines += "  Binary not found; skipping DLL inventory."
  }
  $lines += "  Self-test output (truncated to 50 lines):"
  $lines += ($Output -split "`r?`n" | Select-Object -First 50)
  $lines += ""
  $lines | Out-File -FilePath $vulkanDiagLog -Encoding utf8 -Append
}

function Get-VulkanDrivers {
  $paths = @()
  foreach ($root in @("HKLM:\\SOFTWARE\\Khronos\\Vulkan\\Drivers", "HKCU:\\SOFTWARE\\Khronos\\Vulkan\\Drivers")) {
    if (Test-Path $root) {
      Get-ItemProperty -Path "$root\\*" -ErrorAction SilentlyContinue | ForEach-Object {
        $enabled = $true
        if ($_."(default)" -ne $null) {
          # Khronos driver entries may store DWORD 0 to disable.
          $enabled = ($_."(default)" -ne 0)
        }
        if ($enabled -and $_.PSChildName) {
          $paths += [pscustomobject]@{
            Path    = $_.PSChildName
            Enabled = $enabled
          }
        }
      }
    }
  }
  return $paths | Sort-Object Path -Unique
}

function Test-LlamaBinary {
  param(
    [string]$BinaryPath,
    [string]$PreferredGpuPattern,
    [switch]$AutoSelectVulkan,
    [Array]$RegisteredDrivers = @(),
    [switch]$RequireRegisteredDrivers
  )
  if (-not (Test-Path $BinaryPath)) {
    throw "llama-server.exe not found at $BinaryPath"
  }
  $binaryDir = Split-Path $BinaryPath -Parent
  if ($binaryDir -and (-not ($env:PATH.Split(';') -contains $binaryDir))) {
    $env:PATH = "$binaryDir;$($env:PATH)"
  }
  $selectedVulkanDevice = $null
  $attemptedAutoRetry = $false
  $parsedDevices = @()
  $parsedDeviceCount = $null

  function Invoke-VersionCheck {
    param()
    try {
      $out = & $BinaryPath --version 2>&1
      $code = $LASTEXITCODE
    } catch {
      $code = $LASTEXITCODE
      $out = $_.Exception.Message
    }
    return [pscustomobject]@{ Output = $out; ExitCode = $code }
  }

  $result = Invoke-VersionCheck

  if ($AutoSelectVulkan -and (-not $env:GGML_VULKAN_DEVICE)) {
    $parsedDevices = Get-VulkanDevicesFromOutput -Output $result.Output
    $parsedDeviceCount = Get-VulkanDeviceCountFromOutput -Output $result.Output
    $devices = $parsedDevices
    $deviceCount = $parsedDeviceCount
    if ($RequireRegisteredDrivers -and ($RegisteredDrivers.Count -eq 0)) {
      throw "No Vulkan ICDs detected in the registry. Install/repair your AMD GPU driver (Adrenalin) so an ICD JSON appears under HKLM/HKCU\SOFTWARE\Khronos\Vulkan\Drivers, or set -VkIcdFilenames to the AMD ICD path (e.g., C:\Windows\System32\amdvlk64.dll)."
    }
    $match = $null
    if ($PreferredGpuPattern -and $PreferredGpuPattern.Trim().Length -gt 0) {
      $match = $devices | Where-Object { $_.Name -match $PreferredGpuPattern } | Select-Object -First 1
    }
    if (-not $match -and $devices.Count -gt 1) {
      # Fallback: pick the highest index (usually the discrete GPU) if no pattern matched.
      $match = $devices | Sort-Object Index -Descending | Select-Object -First 1
      if ($match) {
        Write-Warning "Multiple Vulkan devices detected. No device matched pattern '$PreferredGpuPattern', so selecting index $($match.Index) ($($match.Name)) as a fallback (highest index). Use -VulkanDevice <index> to override."
      }
    } elseif (-not $match -and $deviceCount -and $deviceCount -gt 1) {
      # If llama.cpp printed only the count but no device names, still try the highest index.
      $fallbackIndex = $deviceCount - 1
      $match = [pscustomobject]@{ Index = $fallbackIndex; Name = "(count-only, index $fallbackIndex)" }
      Write-Warning "Multiple Vulkan devices detected (count=$deviceCount), but no names were printed. Selecting index $fallbackIndex as a fallback. Use -VulkanDevice <index> or -VkIcdFilenames <path-to-AMD-ICD.json> to override explicitly."
    }
    if ($match) {
      $env:GGML_VULKAN_DEVICE = "$($match.Index)"
      $selectedVulkanDevice = $match
      Write-Host "[INFO] Auto-selected Vulkan device index $($match.Index) ($($match.Name)) based on pattern '$PreferredGpuPattern'." -ForegroundColor Cyan
      $attemptedAutoRetry = $true
      $result = Invoke-VersionCheck
    } elseif ($result.Output -match "ggml_vulkan: Found .*Vulkan devices") {
      Write-Warning "Multiple Vulkan devices detected, but none matched '$PreferredGpuPattern'. Re-run with -VulkanDevice <index> or -VkIcdFilenames <path-to-AMD-ICD.json> to force the discrete GPU (e.g., RX 7900 XTX)."
    }
  }

  $output = $result.Output
  $exitCode = $result.ExitCode

  if ($exitCode -eq -1073741515 -or $exitCode -eq 3221225781) {
    throw "llama-server self-test (--version) returned $exitCode. $dllExitHint"
  }
  if ($exitCode -ne 0) {
    $multiDeviceHint = ""
    if ($output -match "ggml_vulkan: Found .*Vulkan devices") {
      $multiDeviceHint = "`nHint: multiple Vulkan devices detected."
      if ($selectedVulkanDevice) {
        $multiDeviceHint += " Auto-selected index $($selectedVulkanDevice.Index) ($($selectedVulkanDevice.Name)) but self-test still failed."
      }
      if (-not $selectedVulkanDevice -and $AutoSelectVulkan) {
        $multiDeviceHint += " Tried to match '$PreferredGpuPattern' but found none."
      }
      $multiDeviceHint += " Set -VulkanDevice <index> (0-based) or VK_ICD_FILENAMES to point at the discrete GPU ICD (e.g., AMD RX 7900 XTX)."
    }
    Write-VulkanDiagnostics -BinaryPath $BinaryPath -Devices $parsedDevices -DeviceCount $parsedDeviceCount -Output $output -SelectedDevice $selectedVulkanDevice -RegisteredDrivers $RegisteredDrivers
    $logNote = ""
    if (-not $DisableVulkanDiagLog) {
      $logNote = "`nDiagnostics written to $vulkanDiagLog"
    }
    throw "llama-server self-test (--version) failed. Exit code: $exitCode. Output:`n$output`n$dllExitHint$multiDeviceHint$logNote"
  }

  if (-not $output -or "$output".Trim().Length -eq 0) {
    Write-Host "[WARN] llama-server --version produced no output (exit code 0). If it still fails to launch, double-check DLLs are beside the exe and rerun with a PowerShell prompt to see loader errors." -ForegroundColor Yellow
  } else {
    Write-Host "[CHECK] llama-server --version output:`n$output" -ForegroundColor Green
  }

  return [pscustomobject]@{
    ExitCode          = $exitCode
    Output            = $output
    SelectedVulkanGpu = $selectedVulkanDevice
  }
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
      WorkingDirectory       = $repoRoot
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

        # Synchronous retry to surface Windows loader errors (e.g., missing DLLs/blocked binary)
        Write-Host "[RETRY] $Name exited too quickly with no log output. Running synchronously to capture console errors..." -ForegroundColor Yellow
        $retryExit = $null
        try {
          & $FilePath @ArgumentList *>&1 | Tee-Object -FilePath $stderrLog -Append
          $retryExit = $LASTEXITCODE
        } catch {
          $message += "`nRetry failed to execute: $($_.Exception.Message)"
        }
        # Append anything new we just captured
        if (Test-Path $stderrLog) {
          $lastError = (Get-Content -Path $stderrLog -Tail 40 -ErrorAction SilentlyContinue) -join "`n"
        }
        if ($retryExit -ne $null) {
          $message += "`nRetry exit code: $retryExit"
        }
        if ($lastError) {
          $message += "`nCaptured during retry:`n$lastError"
        }
        $message += "`nIf you still see no output, Windows may be blocking the binary (right-click > Properties > Unblock) or the VC++ runtime/GPU DLLs may be missing."
      }
      if ($exitCode -eq -1073741515 -or $exitCode -eq 3221225781) {
        $message += "`n$dllExitHint"
      }
      throw $message
    }

    Write-Host "[STARTED] $Name -> $stdoutLog / $stderrLog"
    return $proc
  }

  if (-not $SkipModel) {
    if ((Test-Path $ServerBinary) -and (Test-Path $ModelPath)) {
      $serverDir = Split-Path $ServerBinary -Parent
      $dlls = @("llama.dll", "mtmd.dll")
      $ggmlDlls = Get-ChildItem -Path $serverDir -Filter "ggml*.dll" -ErrorAction SilentlyContinue
      $missingDlls = @()
      foreach ($dll in $dlls) {
        if (-not (Test-Path (Join-Path $serverDir $dll))) {
          $missingDlls += $dll
        }
      }
      if (($missingDlls.Count -gt 0) -or (-not $ggmlDlls)) {
        $dllMsg = "Missing DLLs detected near llama-server.exe: "
        if ($missingDlls.Count -gt 0) {
          $dllMsg += ($missingDlls -join ", ")
        }
        if (-not $ggmlDlls) {
          if ($missingDlls.Count -gt 0) { $dllMsg += "; " }
          $dllMsg += "no ggml*.dll files found"
        }
        $dllMsg += ". Copy ALL files from your llama.cpp build\\bin\\Release folder next to $ServerBinary (including ggml*.dll, llama.dll, mtmd.dll, ggml-vulkan*.dll). Right-click each DLL > Properties > Unblock, then rerun."
        throw $dllMsg
      }

      # Ensure dependent DLLs in the llama.cpp folder are on PATH for the child process.
      if ($serverDir -and (-not ($env:PATH.Split(';') -contains $serverDir))) {
        $env:PATH = "$serverDir;$($env:PATH)"
      }

      $registeredDrivers = @()
      if (-not $VkIcdFilenames -and $AutoSelectAmdVkIcd) {
        $icds = Get-VulkanDrivers
        $registeredDrivers = $icds
        if (-not $icds -or $icds.Count -eq 0) {
          throw "No Vulkan ICDs detected in the registry. Install/repair your AMD GPU driver (Adrenalin) so an ICD JSON appears under HKLM/HKCU\SOFTWARE\Khronos\Vulkan\Drivers, or set -VkIcdFilenames to the AMD ICD path (e.g., C:\Windows\System32\amdvlk64.dll)."
        }
        if ($icds -and $icds.Count -gt 1) {
          $amdIcds = $icds | Where-Object { $_.Path -match "(amd|radeon|7900)" }
          $choice = $amdIcds | Select-Object -First 1
          if (-not $choice) {
            # If nothing matched AMD, prefer the last entry (often the dGPU) to avoid basic/integrated ICD first.
            $choice = $icds | Select-Object -Last 1
          }
          if ($choice) {
            $env:VK_ICD_FILENAMES = $choice.Path
            Write-Host "[INFO] Auto-selected VK_ICD_FILENAMES=$($choice.Path)" -ForegroundColor Cyan
          }
        }
      }

      if ($ClearVulkanDevice) {
        Remove-Item Env:\GGML_VULKAN_DEVICE -ErrorAction SilentlyContinue | Out-Null
        Write-Host "[INFO] Cleared GGML_VULKAN_DEVICE (using llama.cpp default device selection)" -ForegroundColor Yellow
      } elseif ($VulkanDevice -ne $null) {
        $env:GGML_VULKAN_DEVICE = "$VulkanDevice"
        Write-Host "[INFO] Using Vulkan device index $VulkanDevice (GGML_VULKAN_DEVICE)" -ForegroundColor Cyan
      }

      if ($VkIcdFilenames -and $VkIcdFilenames.Trim().Length -gt 0) {
        $env:VK_ICD_FILENAMES = $VkIcdFilenames
        Write-Host "[INFO] Using VK_ICD_FILENAMES=$VkIcdFilenames" -ForegroundColor Cyan
      }

      # Quick self-test to surface DLL issues before the logged launch.
      $autoSelectVulkan = (-not $ClearVulkanDevice) -and ($VulkanDevice -eq $null) -and (-not $env:GGML_VULKAN_DEVICE)
      Test-LlamaBinary -BinaryPath $ServerBinary -PreferredGpuPattern $PreferredVulkanGpuPattern -AutoSelectVulkan:$autoSelectVulkan -RegisteredDrivers $registeredDrivers -RequireRegisteredDrivers:$AutoSelectAmdVkIcd

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
