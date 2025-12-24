@echo off
setlocal enabledelayedexpansion

set CONFIG=config.yaml

echo [INFO] Rebuilding knowledge base using %CONFIG%...

where python >nul 2>nul || (
  echo [ERROR] Python not found on PATH. Install Python 3.11+ and reopen this window.
  pause
  exit /b 1
)

if not exist "%CONFIG%" (
  echo [ERROR] %CONFIG% not found. Copy config.example.yaml to config.yaml and edit paths.
  pause
  exit /b 1
)

if not exist "data\raw" (
  echo [INFO] data\raw not found; creating it now. Place your .txt/.md files here before rerunning.
  mkdir "data\raw"
  pause
  exit /b 1
)

python app/ingest.py --config %CONFIG%
if errorlevel 1 (
  echo [ERROR] Ingestion failed. Check the log above (network blocks can prevent model downloads).
  pause
  exit /b 1
)

echo [INFO] Ingestion complete.
pause

endlocal
