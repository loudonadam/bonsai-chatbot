@echo off
setlocal

REM Start llama-server if available (optional helper)
if exist "scripts\llama-server.exe" (
  echo Starting llama.cpp server...
  start "llama" "scripts\llama-server.exe" --model "models\bonsai-gguf.gguf" --host 127.0.0.1 --port 8080 --ctx-size 4096 --n-gpu-layers 35 --embedding
) else (
  echo Skipping llama-server auto-start (place llama-server.exe in scripts\ or run scripts\start_model.bat manually).
)

REM Start FastAPI (Uvicorn)
start "bonsai-api" cmd /k "python -m uvicorn app.main:app --host 0.0.0.0 --port 8000"

REM Serve UI (simple Python HTTP server)
pushd ui
start "bonsai-ui" cmd /k "python -m http.server 3000"
popd

REM Open browser
start http://localhost:3000

endlocal
