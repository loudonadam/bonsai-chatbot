# Bonsai Chatbot — One-Click llama.cpp RAG

This repo is rebuilt from scratch to pair your locally built **llama.cpp** (Ryzen 7700X CPU + RX 7900 XTX GPU) with a lean Retrieval Augmented Generation (RAG) stack. Add trusted bonsai notes, double-click once, and chat over them in a browser.

## Is this feasible with your hardware?
Yes. llama.cpp already runs on Windows 11 with AMD GPUs via the Vulkan build, and this project only needs:

- Your existing **llama.cpp** build (place `llama-server.exe` next to its DLLs).
- A **GGUF model** (any instruct model you prefer; Llama 3 8B works well and fits in 24 GB VRAM with Q4 quantization).
- **Python 3.11+** for the RAG API, ingestion, and static UI server.

Everything else is scripted for one-click launch on Windows.

## How it works (methodology)
1. **Document ingestion**: `app/ingest.py` scans `data/raw` for `.txt` and `.md`, normalizes/chunks text, embeds with **BAAI/bge-small-en-v1.5**, and writes vectors into a local **Chroma** index at `data/index`.
2. **Model serving**: `llama-server.exe` (from llama.cpp) exposes an OpenAI-compatible endpoint on port 8080. It can offload to the RX 7900 XTX via Vulkan; tune `--n-gpu-layers` or Vulkan device selection as needed.
3. **RAG API**: `app/main.py` (FastAPI) retrieves top chunks from Chroma, builds a grounded prompt, and forwards it to the llama.cpp server via an OpenAI-compatible call with chat-first / completion fallback.
4. **One-click orchestrator**: `scripts/quick_launch.bat` (with `quick_launch.ps1`) validates prerequisites, starts `llama-server.exe` (unless skipped), the API on port 8010, serves the static UI on port 3000, writes logs to `logs/`, and opens your browser. Press Enter in that window to stop everything.

## Quick start (Windows 11, double-click friendly)

> You already have llama.cpp built; these steps wire it into the chatbot and deliver a single double-click launch.

1) **Clone and enter the repo**
   ```powershell
   git clone <your fork url> BonsaiChat
   cd BonsaiChat
   ```

2) **(One-time) Create a virtual environment and install deps**
   ```powershell
   python -m venv .venv
   .\.venv\Scripts\activate
   pip install --upgrade pip
   pip install -r app/requirements.txt
   ```
   The launch scripts auto-use `.venv\Scripts\python.exe` when present.

3) **Copy and edit config**
   ```powershell
   copy config.example.yaml config.yaml
   ```
   Then set:
   - `model.path`: path to your GGUF (e.g., `C:\models\llama3-8b-q4.gguf` or keep `models\bonsai-gguf.gguf`).
   - `model.server_binary`: path to your `llama-server.exe` (keep it beside its DLLs). Default is `C:\Users\loudo\Desktop\src\llama.cpp\build\bin\Release\llama-server.exe`.
   - `model.name`: model identifier llama.cpp should expose (default `local-llm`).
   - `model.timeout_seconds`: request timeout; extend if your GPU warm-up is slow.
   - If you must stay offline, set `embedding.local_files_only: true` and point `embedding.model` to a local folder; otherwise the embedding model downloads on first ingest.

4) **Place model + llama.cpp server**
   - Drop your **GGUF** under `models\` (or anywhere, then update `config.yaml` or pass `-ModelPath` to quick launch).
   - Keep your **llama-server.exe** (plus its DLLs like `ggml*.dll`, `llama.dll`, `mtmd.dll`, Vulkan DLLs) at `C:\Users\loudo\Desktop\src\llama.cpp\build\bin\Release\llama-server.exe` (default). If you move it, update `model.server_binary` and the scripts.
   - Optional sanity check: from PowerShell, run `& 'C:\Users\loudo\Desktop\src\llama.cpp\build\bin\Release\llama-server.exe' --version` to confirm DLLs load.

5) **Add your bonsai sources**
   - Place trusted `.txt` or `.md` files in `data\raw`. The folder is created automatically if missing.

6) **Ingest (build the knowledge base)**
   - Double-click `scripts\rebuild_kb.bat`.
   - This runs `python -m app.ingest --config config.yaml`, creates `data\index`, and prints any missing-file errors in the window.

7) **Launch everything with one double-click**
   - Double-click `scripts\quick_launch.bat` (or right-click > Run with PowerShell).
   - What happens:
     - Checks for `config.yaml`, the model, and `llama-server.exe` (if configured to start it).
     - Starts `llama-server.exe` on port **8080** (skips if unavailable), the FastAPI backend on **8010**, and a static UI server on **3000** (auto-picks another UI port if 3000 is busy).
     - Opens your browser to the chat UI.
     - Writes logs to `logs\llama-server-*.log`, `logs\api-*.log`, and `logs\ui-*.log`.
   - Press **Enter** in that window to stop everything cleanly.

8) **Chat**
   - Ask questions in the browser; retrieved sources are shown under responses so you can verify where answers came from.

## Tips for the RX 7900 XTX + llama.cpp
- Use the **Vulkan build** of llama.cpp and keep Vulkan runtime updated (AMD drivers include it).
- If llama.cpp lists multiple devices (e.g., iGPU + dGPU), `quick_launch.ps1` auto-picks a GPU whose name matches `"7900"`; override with `-VulkanDevice <index>` in PowerShell if needed.
- Lower `--gpu-layers` if you see OOM; raise it to move more work to the GPU for faster responses.

## Manual commands (optional)
- Rebuild index: `python -m app.ingest --config config.yaml`
- Start API only: `uvicorn app.main:app --host 0.0.0.0 --port 8010`
- Serve UI only: `python -m http.server 3000 -d ui`

## What to expect
- **Single-click launch** after setup: double-click `scripts\quick_launch.bat`.
- **Local-only flow**: all data stays on your machine; embeddings and model are local.
- **Extensible**: add PDF/HTML loaders in `app/utils.py` later, or swap embeddings for a GPU-accelerated DirectML/ONNX option if desired.
