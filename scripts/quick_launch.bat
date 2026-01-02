@echo off
REM Wrapper to keep the window open when running the PowerShell quick launch script.
setlocal
set SCRIPT_DIR=%~dp0
set PS_SCRIPT=%SCRIPT_DIR%quick_launch.ps1
REM Keep these in sync with scripts\start_model.bat
set MODEL_PATH=%~dp0..\models\bonsai-gguf.gguf
set SERVER_BIN=C:\Users\loudo\llama.cpp\build\bin\Release\llama-server.exe
set BASE_MODEL_PORT=8080
set MAX_PORT_SEARCH=20

if not exist "%PS_SCRIPT%" (
  echo [ERROR] quick_launch.ps1 not found next to this file.
  pause
  exit /b 1
)

REM -NoExit ensures the window stays open so any error messages are visible.
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -NoExit -File "%PS_SCRIPT%" -ModelPath "%MODEL_PATH%" -ServerBinary "%SERVER_BIN%" -BaseModelPort %BASE_MODEL_PORT% -MaxPortSearch %MAX_PORT_SEARCH%
endlocal
