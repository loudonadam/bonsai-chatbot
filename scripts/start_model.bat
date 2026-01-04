@echo off
setlocal EnableExtensions EnableDelayedExpansion

<<<<<<< Updated upstream
REM Update the model path to your GGUF file
=======
REM Update the model path to your GGUF file (relative to repo root by default)
>>>>>>> Stashed changes
set MODEL_PATH=C:\Users\loudo\Desktop\bonsai-chatbot\bonsai-chatbot\models\bonsai-gguf.gguf
REM IMPORTANT: use llama-server.exe (llama-cli.exe does not support --host/--port)
set SERVER_BIN=C:\Users\loudo\llama.cpp\build\bin\Release\llama-server.exe
set BASE_PORT=8080
set MAX_PORT_SEARCH=20
set LOGS_DIR=%~dp0..\logs
set STDOUT_LOG=%LOGS_DIR%\llama-server-stdout.log
set STDERR_LOG=%LOGS_DIR%\llama-server-stderr.log
rem If you have both an iGPU and dGPU and want to force one, set VULKAN_DEVICE to a 0-based index (leave blank to let llama.cpp decide).
set VULKAN_DEVICE=0
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
  echo llama-server.exe not found at %SERVER_BIN%
  echo Download the Windows release of llama.cpp and place llama-server.exe here.
  pause
  exit /b 1
)

for %%B in ("%SERVER_BIN%") do set "SERVER_NAME=%%~nxB"
if /I "%SERVER_NAME%"=="llama-cli.exe" (
  echo SERVER_BIN currently points to llama-cli.exe, which does not support --host/--port.
  echo Please point SERVER_BIN to llama-server.exe instead.
  pause
  exit /b 1
)

if not exist "%MODEL_PATH%" (
  echo Model file not found at %MODEL_PATH%
  pause
  exit /b 1
)

REM Find the first available port starting at BASE_PORT.
set PORT=%BASE_PORT%
set /a MAX_PORT=%BASE_PORT% + %MAX_PORT_SEARCH%
:CHECK_PORT
set "PORT_IN_USE="
set "PORT_IN_USE_LINE="
for /f "skip=4 tokens=1,2,5" %%a in ('netstat -ano -p tcp ^| findstr /R /C:":%PORT% .*LISTENING"') do (
  set "PORT_IN_USE=%%c"
  set "PORT_IN_USE_LINE=%%a %%b %%c"
)
if defined PORT_IN_USE (
  echo Port %PORT% is already in use by PID %PORT_IN_USE%. Details: !PORT_IN_USE_LINE!. Trying next port...
  set /a PORT+=1
  if %PORT% gtr %MAX_PORT% (
    echo No free port found between %BASE_PORT% and %MAX_PORT%.
    pause
    exit /b 1
  )
  goto CHECK_PORT
)
echo Using port %PORT%.

echo Writing llama.cpp logs to:
echo   %STDOUT_LOG%
echo   %STDERR_LOG%
echo.

<<<<<<< Updated upstream
"%SERVER_BIN%" --model "%MODEL_PATH%" --host 127.0.0.1 --port %PORT% --ctx-size 4096 --n-gpu-layers -1 --embedding 1>>"%STDOUT_LOG%" 2>>"%STDERR_LOG%"
=======
"%SERVER_BIN%" --model "%MODEL_PATH%" --alias "%MODEL_ALIAS%" --host 127.0.0.1 --port %PORT% --ctx-size 4096 --n-gpu-layers -1 --embedding 1>>"%STDOUT_LOG%" 2>>"%STDERR_LOG%"

>>>>>>> Stashed changes

if %errorlevel% neq 0 (
  echo llama-server exited with error level %errorlevel%. Review the log files above for details.
  pause
  exit /b %errorlevel%
)

pause

endlocal
