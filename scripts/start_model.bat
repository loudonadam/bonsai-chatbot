@echo off
setlocal

REM Update the model path to your GGUF file
set MODEL_PATH=models\bonsai-gguf.gguf
set SERVER_BIN=scripts\llama-server.exe

if not exist "%SERVER_BIN%" (
  echo llama-server.exe not found at %SERVER_BIN%
  echo Download the Windows release of llama.cpp and place llama-server.exe here.
  exit /b 1
)

if not exist "%MODEL_PATH%" (
  echo Model file not found at %MODEL_PATH%
  exit /b 1
)

"%SERVER_BIN%" --model "%MODEL_PATH%" --host 127.0.0.1 --port 8080 --ctx-size 4096 --n-gpu-layers 35 --embedding

endlocal
