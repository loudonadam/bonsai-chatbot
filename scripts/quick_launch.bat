@echo off
REM Wrapper to run the PowerShell quick launch script that mirrors start_model.bat.
setlocal
set SCRIPT_DIR=%~dp0
set PS_SCRIPT=%SCRIPT_DIR%quick_launch.ps1

if not exist "%PS_SCRIPT%" (
  echo [ERROR] quick_launch.ps1 not found next to this file.
  pause
  exit /b 1
)

powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -NoExit -File "%PS_SCRIPT%"
endlocal
