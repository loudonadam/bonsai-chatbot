@echo off
setlocal enabledelayedexpansion

REM Ensure we run from repo root even when double-clicked from scripts\
pushd "%~dp0.."

REM --- user settings ------------------------------------------------------
set CONFIG_FILE=config.yaml
set MODEL_PATH=models\bonsai-gguf.gguf
set SERVER_BIN=C:\Users\loudo\llama.cpp\build\bin\Release\llama-server.exe
set API_HOST=0.0.0.0
set API_PORT=8010
set UI_PORT=3000
REM ------------------------------------------------------------------------

echo [INFO] Checking prerequisites...
where python >nul 2>nul || (
  echo [ERROR] Python not found on PATH. Install Python 3.11+ and reopen this window.
  pause
  popd
  exit /b 1
)
if not exist "%CONFIG_FILE%" (
  echo [ERROR] %CONFIG_FILE% not found in %CD%.
  echo Copy config.example.yaml to config.yaml and edit paths.
  pause
  popd
  exit /b 1
)

if not exist "app\requirements.txt" (
  echo [WARN] app\requirements.txt not found. Make sure dependencies are installed.
)

if not exist "data\raw" (
  echo [INFO] Creating data\raw (drop your .txt/.md sources here)...
  mkdir "data\raw"
)
if not exist "data\index" (
  echo [INFO] Creating data\index to hold the Chroma database...
  mkdir "data\index"
)

echo [INFO] Starting llama.cpp server helper (optional)...
if exist "%SERVER_BIN%" (
  if not exist "%MODEL_PATH%" (
    echo [ERROR] Model file not found at %MODEL_PATH%.
    echo Update MODEL_PATH in launch.bat or config.yaml.
  ) else (
    echo [INFO] Launching %SERVER_BIN% with model %MODEL_PATH%...
    start "llama" cmd /k "\"%SERVER_BIN%\" --model \"%MODEL_PATH%\" --host 127.0.0.1 --port 8080 --ctx-size 4096 --n-gpu-layers 35 --embedding || (echo llama-server exited with error & pause)"
  )
) else (
  echo [INFO] Skipping llama-server auto-start (place llama-server.exe in scripts\ or run scripts\start_model.bat manually).
)

echo [INFO] Starting FastAPI (Uvicorn) on %API_HOST%:%API_PORT% ...
start "bonsai-api" cmd /k "python -m uvicorn app.main:app --host %API_HOST% --port %API_PORT% || (echo API exited with error & pause)"

echo [INFO] Serving UI from ui\ on port %UI_PORT% ...
pushd ui
start "bonsai-ui" cmd /k "python -m http.server %UI_PORT% || (echo UI server exited with error & pause)"
popd

echo [INFO] Opening browser to http://localhost:%UI_PORT%
start http://localhost:%UI_PORT%

echo [INFO] All processes launched. Check the opened windows for logs/errors.

popd
endlocal
