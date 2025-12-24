@echo off
setlocal enabledelayedexpansion

REM Ensure we are in the repo root even when double-clicked from scripts\
pushd "%~dp0.."

set CONFIG=config.yaml

echo [INFO] Rebuilding knowledge base using %CONFIG%...

where python >nul 2>nul || (
  echo [ERROR] Python not found on PATH. Install Python 3.11+ and reopen this window.
  pause
  popd
  exit /b 1
)

if not exist "%CONFIG%" (
  echo [ERROR] %CONFIG% not found in %CD%.
  echo Copy config.example.yaml to config.yaml and edit paths.
  pause
  popd
  exit /b 1
)

if not exist "data\raw" (
  echo [INFO] data\raw not found; creating it now. Place your .txt/.md files here before rerunning.
  mkdir "data\raw"
  pause
  popd
  exit /b 1
)

python app/ingest.py --config %CONFIG%
if errorlevel 1 (
  echo [ERROR] Ingestion failed. Check the log above (network blocks can prevent model downloads).
  pause
  popd
  exit /b 1
)

echo [INFO] Ingestion complete.
pause

popd
endlocal
