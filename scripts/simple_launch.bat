@echo off
REM Simple launcher for Bonsai Chatbot
REM Just double-click this file to start everything!

setlocal
set SCRIPT_DIR=%~dp0
set PS_SCRIPT=%SCRIPT_DIR%simple_launch.ps1

REM Default paths (update these if needed)
set MODEL_PATH=%~dp0..\models\bonsai-gguf.gguf
set SERVER_BIN=C:\Users\loudo\llama.cpp\build\bin\Release\llama-server.exe

if not exist "%PS_SCRIPT%" (
  echo [ERROR] simple_launch.ps1 not found next to this file.
  pause
  exit /b 1
)

echo.
echo Starting Bonsai Chatbot...
echo.

REM Launch PowerShell with the script
REM -NoExit keeps window open so you can stop services with Ctrl+C
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -NoExit -File "%PS_SCRIPT%" -ModelPath "%MODEL_PATH%" -ServerBinary "%SERVER_BIN%"

endlocal