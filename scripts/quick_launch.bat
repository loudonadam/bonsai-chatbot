@echo off
REM Wrapper to keep the window open when running the PowerShell quick launch script.
setlocal
set SCRIPT_DIR=%~dp0
set PS_SCRIPT=%SCRIPT_DIR%quick_launch.ps1

if not exist "%PS_SCRIPT%" (
  echo [ERROR] quick_launch.ps1 not found next to this file.
  pause
  exit /b 1
)

REM -NoExit ensures the window stays open so any error messages are visible.
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -NoExit -File "%PS_SCRIPT%"
endlocal
