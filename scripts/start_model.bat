@echo off
setlocal

REM Update the model path to your GGUF file
set MODEL_PATH=models\bonsai-gguf.gguf
set SERVER_BIN=C:\Users\loudo\llama.cpp\build\bin\Release\llama-cli.exe
set BASE_PORT=8080
set LOGS_DIR=%~dp0..\logs
set STDOUT_LOG=%LOGS_DIR%\llama-server-stdout.log
set STDERR_LOG=%LOGS_DIR%\llama-server-stderr.log
rem If you have both an iGPU and dGPU and want to force one, set VULKAN_DEVICE to a 0-based index (leave blank to let llama.cpp decide).
set VULKAN_DEVICE=
rem Optional: restrict visible Vulkan ICDs (semicolon-separated paths to .json ICD files, often under C:\Windows\System32\DriverStore\FileRepository\*\*.json).
set VULKAN_ICD_FILENAMES=

if defined VULKAN_DEVICE (
  set GGML_VULKAN_DEVICE=%VULKAN_DEVICE%
  echo Using GGML_VULKAN_DEVICE=%GGML_VULKAN_DEVICE%
)
if defined VULKAN_ICD_FILENAMES (
  set VK_ICD_FILENAMES=%VULKAN_ICD_FILENAMES%
  echo Using VK_ICD_FILENAMES=%VK_ICD_FILENAMES%
)

if not exist "%LOGS_DIR%" (
  mkdir "%LOGS_DIR%" >nul 2>nul
)

if not exist "%SERVER_BIN%" (
  echo llama-cli.exe not found at %SERVER_BIN%
  echo Download the Windows release of llama.cpp and place llama-cli.exe here.
  pause
  exit /b 1
)

if not exist "%MODEL_PATH%" (
  echo Model file not found at %MODEL_PATH%
  pause
  exit /b 1
)

rem Find the first available port starting at BASE_PORT (tries 20 ports).
set PORT=%BASE_PORT%
set MAX_TRIES=20
set /a END_PORT=%BASE_PORT%+%MAX_TRIES%
:CHECK_PORT
set PORT_BUSY=
for /f "tokens=5" %%p in ('netstat -ano ^| findstr /r ":%PORT%[ ]" ^| findstr LISTENING') do (
  set PORT_BUSY=1
)
if defined PORT_BUSY (
  set /a PORT+=1
  if %PORT% GEQ %END_PORT% (
    echo No free port found between %BASE_PORT% and %END_PORT%.
    pause
    exit /b 1
  )
  goto CHECK_PORT
)
echo Using port %PORT% for llama.cpp server.

echo Writing llama.cpp logs to:
echo   %STDOUT_LOG%
echo   %STDERR_LOG%
echo.

"%SERVER_BIN%" --server --model "%MODEL_PATH%" --host 127.0.0.1 --port %PORT% --ctx-size 4096 --n-gpu-layers -1 --embedding 1>>"%STDOUT_LOG%" 2>>"%STDERR_LOG%"

if %errorlevel% neq 0 (
  echo llama-server exited with error level %errorlevel%. Review the log files above for details.
  pause
  exit /b %errorlevel%
)

pause

endlocal
