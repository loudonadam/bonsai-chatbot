# Bonsai Chatbot (v1 lightweight)

A minimal, self-hosted RAG chatbot tailored for bonsai notes. Runs locally on Windows (or Linux) with a small set of scripts to ingest your documents and chat over them. This version favors simplicity over features and is intended for personal/hobby use.

## What this provides
- **Local API** (FastAPI) that exposes `/ask` to chat and `/ingest` to rebuild the knowledge base.
- **Simple ingestion pipeline** (text/Markdown) using a small embedding model (BGE small) and a local Chroma vector store.
- **Static web UI** you can open in your browser to chat.
- **Windows one-click helpers**: batch files to start the model server, rebuild the KB, and launch everything.

## Prerequisites
- **Windows 11** (target) or Linux/macOS for development.
- **Python 3.11+** installed and on PATH.
- **Git** installed (to clone the repo locally).
- **Model + server**: `llama.cpp` prebuilt for Windows (Vulkan build recommended for AMD GPUs) and a GGUF model (e.g., Llama 3 8B Instruct Q4_K_M).
  - Download `llama.cpp` Windows binaries: <https://github.com/ggerganov/llama.cpp/releases>
  - Download a model (example): <https://huggingface.co/QuantFactory/Meta-Llama-3-8B-Instruct-GGUF>

## Quick start (Windows, double-click friendly)
> Goal: be able to launch, test, troubleshoot, fix, and restart by double-clicking at most two files.

1) **Clone the repo**
   ```powershell
   git clone <your fork url> BonsaiChat
   cd BonsaiChat
   ```
2) **(One-time) Create and activate a virtual environment (so dependencies stay local)**
   ```powershell
   python -m venv .venv
   .\.venv\Scripts\activate
   pip install --upgrade pip
   pip install -r app/requirements.txt
   ```
   > If you skip the venv, ensure `python` on PATH has the required packages from `app/requirements.txt`. All launchers auto-use `.venv\Scripts\python.exe` when it exists, even when you double-click them.
3) **Place model + llama.cpp server**
   - Download a full GGUF model (example: <https://huggingface.co/QuantFactory/Meta-Llama-3-8B-Instruct-GGUF>). Do **not** use vocab-only files; you need a full checkpoint (e.g., `...Q4_K_M.gguf`).
   - Put the model at `models\bonsai-gguf.gguf` **or** update `MODEL_PATH` in `scripts\launch.bat` / `scripts\start_model.bat`, the `-ModelPath` flag for `scripts\quick_launch.ps1`, and `model.path` in `config.yaml` to the file you downloaded.
   - If you download prebuilt llama.cpp: place `llama-server.exe` (CPU or Vulkan build) in `scripts\` **or** point quick launch at it via `-ServerBinary "C:\path\to\llama-server.exe"`. Keep all companion DLLs next to it (at minimum `ggml*.dll`, `llama.dll`, `mtmd.dll`; if you built llama.cpp yourself, copy everything from `build\bin\Release` beside the exe). Missing DLLs often surface as exit code `-1073741515` or a silent crash.
4) **Configure the app**
   ```powershell
   copy config.example.yaml config.yaml
   ```
   Then edit `config.yaml`:
   - Set `model.path` to your GGUF file.
   - If you must stay offline, set `embedding.local_files_only: true` and set `embedding.model` to a local path or pre-downloaded folder. Optional: set `embedding.cache_dir` to a writable folder for cached models.
5) **Add documents to index**
   - Put your `.txt` or `.md` sources in `data\raw`. (The scripts create this folder if missing.)
6) **Launch everything (one window, double-click)**
   - Double-click `scripts\quick_launch.bat` (or right-click > Run with PowerShell). No extra windows are opened; all logs go to `logs\`.
   - The script will:
     - Auto-use `.venv\Scripts\python.exe` when present; otherwise uses `python` on PATH.
     - Check required files (`config.yaml`, `llama-server.exe` + model if present).
     - Preflight ports (LLM on 8080, API on 8010, UI on 3000 by default) and pick an alternate UI port if needed.
     - Start `llama-server.exe` (if available), the FastAPI backend, and the static UI server in the same window.
     - Write logs to `logs\llama-server-stdout.log` / `stderr.log`, `logs\api-stdout.log` / `stderr.log`, and `logs\ui-stdout.log` / `stderr.log`.
     - Open your browser to the UI (default `http://localhost:3000`).
   - When you press Enter in that window, all processes stop cleanly.
   - Switches (for advanced use): add `-SkipModel` to skip starting `llama-server.exe`, or `-NoBrowser` to avoid opening the UI tab. You can also pass `-ModelPath` and `-ServerBinary` if your GGUF or llama.cpp build lives elsewhere.
7) **Ingest documents (when you add/change files in `data\raw`)**
   - Double-click `scripts\rebuild_kb.bat` (recommended). The window stays open so you can read errors.
   - If you prefer a command (same behavior): `python -m app.ingest --config config.yaml`

## llama.cpp setup (Windows 11 + AMD GPU, quickest path to use with quick_launch)
These steps assume you built llama.cpp yourself (useful when you want the Vulkan build for AMD). If you already have a working `llama-server.exe`, skip to step 4.

1) **Build llama.cpp (Release)**
   ```powershell
   git clone https://github.com/ggerganov/llama.cpp.git
   cd llama.cpp
   cmake -B build -G "Visual Studio 17 2022" -A x64 -DLLAMA_CURL=OFF -DLLAMA_VULKAN=ON
   cmake --build build --config Release -j
   ```
   > `-DLLAMA_CURL=OFF` avoids the curl dependency. Drop `-DLLAMA_VULKAN=ON` if you only want CPU.
2) **Smoke-test the binary (optional but recommended)**
   ```powershell
   .\build\bin\Release\llama-cli.exe -m C:\path\to\model.gguf -p "Hello! Summarize llama.cpp in one sentence." --gpu-layers 20
   ```
   Lower `--gpu-layers` if you hit OOM; remove it for CPU-only.
3) **Copy the server binary where quick_launch can see it**
   - Option A: copy `build\bin\Release\llama-server.exe` **plus all DLLs from the same folder (`ggml*.dll`, `llama.dll`, `mtmd.dll`, etc.)** into this repo’s `scripts\` folder. Missing DLLs → exit code `-1073741515`.
   - Option B: leave it where it is and tell quick launch where to find it (the script also prepends that folder to `PATH` so co-located DLLs are found):
     ```powershell
     .\scripts\quick_launch.ps1 -ServerBinary "C:\path\to\llama-server.exe" -ModelPath "C:\path\to\your-model.gguf"
     ```
4) **Point the Bonsai chatbot at your model**
   - Update `config.yaml` `model.path`, or pass `-ModelPath` to `scripts\quick_launch.ps1`.
   - If you keep the model in `models\`, the default paths already work.
5) **Run the bot (single window)**
   ```powershell
   .\scripts\quick_launch.ps1
   ```
   - Add `-ModelPath` / `-ServerBinary` if you didn’t copy files into `models\` and `scripts\`.
   - Logs live in `logs\` (LLM, API, UI). Press Enter in the window to stop everything.

### Fast daily loop (minimal clicks)
- Start everything: double-click `scripts\quick_launch.bat`.
- Test in the browser (opens automatically). Watch `logs\*` if something fails.
- Stop/restart: press Enter in the quick-launch window, then double-click it again.
- Re-ingest after edits: double-click `scripts\rebuild_kb.bat`.

## Manual launch (only if you prefer separate windows)
- **LLM server**: `scripts\start_model.bat` (writes logs to `logs\llama-server-*.log`; refuses to start if port 8080 is busy).
- **API**: `python -m uvicorn app.main:app --host 0.0.0.0 --port 8010`
- **UI**: `python -m http.server 3000 -d ui`
- Then open <http://localhost:3000>.

### Common troubleshooting tips (PowerShell)
- Ensure `config.yaml` exists in the repo root.
- If you use a venv, make sure the shell says `(.venv)` in the prompt before running scripts. If not, run `.\.venv\Scripts\activate`.
- Ensure `PYTHONPATH` is set for the session (`set PYTHONPATH=$PWD`) if you see `ModuleNotFoundError: No module named 'app'`.
- Leave each window open to read any traceback or missing-file warnings.
- The embedding model (`BAAI/bge-small-en-v1.5`) downloads automatically on first ingest; it is not needed for `llama-server.exe` startup. If you must stay offline, set `embedding.local_files_only: true` and point `embedding.model` to a local copy.
- If `llama-server.exe` exits instantly with no logs, try: unblock the file (Right-click > Properties > Unblock), confirm you downloaded the correct Windows build (CPU/Vulkan/CUDA as needed), and install the Visual C++ runtime that the build requires.

## Commands (manual, if you prefer)
- Rebuild index:
  ```powershell
  python app/ingest.py --config config.yaml
  ```
- Start API:
  ```powershell
  uvicorn app.main:app --host 0.0.0.0 --port 8010 --reload
  ```
- Open UI: open `ui/index.html` or serve it via `python -m http.server 3000 -d ui`.

## Configuration
`config.example.yaml` shows all options. Copy to `config.yaml` and edit:
- `model.path`: path to your GGUF model file.
- `model.server_binary`: path to `llama-server.exe` (or leave empty to manage manually).
- `server.host`/`server.port`: FastAPI host/port.
- `ui.port`: where to serve the static UI if you use `launch.bat`.
- `data.raw_dir`: folder containing your documents.
- `data.index_dir`: where the Chroma index lives.
- `embedding.model`: HuggingFace model name for embeddings (defaults to `BAAI/bge-small-en-v1.5`).
- `embedding.cache_dir`: optional folder for caching/downloading the embedding model. Useful if you want to pre-download once.
- `embedding.local_files_only`: set to `true` to require the embedding model to be available locally (no internet download attempts). Make sure `embedding.model` points to a local path or that the model already exists in `cache_dir`.
- The app will create `data/raw` and `data/index` if they do not exist yet, but you still need to place your source documents under `data/raw`.

## Troubleshooting the scripts
- **Nothing happens when I double-click a `.bat` file**: each helper window now stays open and prints an error before exiting. Look for messages like "Python not found", "config.yaml not found", or "Model file not found".
- **config.yaml not found**: the scripts now change to the repo root automatically, so keep `config.yaml` at the top level (next to `README.md`).
- **Model download blocked (offline/proxy)**: set `embedding.local_files_only: true` in `config.yaml` and point `embedding.model` to a local folder. You can also set `embedding.cache_dir` to a path where you manually place the model files.
- **llama-server.exe missing**: the launch script will warn and continue; start `scripts\start_model.bat` after you download `llama-server.exe` and place it in `scripts\`.

## Current limitations
- Ingestion supports `.txt` and `.md` only. PDF/HTML require adding a parser.
- Embeddings run on CPU by default (uses `sentence-transformers` + PyTorch CPU); for AMD GPU, install `torch-directml` if desired.
- No persistent conversation history beyond what the UI keeps in page state.

## File layout
```
app/
  main.py           # FastAPI app (/ask, /ingest)
  ingest.py         # CLI + callable ingestion
  rag.py            # Retrieval + prompt assembly
  utils.py          # File loading and chunking
  requirements.txt  # Python deps
config.example.yaml # Copy to config.yaml
scripts/
  launch.bat        # Start model server (optional), API, and UI server
  rebuild_kb.bat    # Rebuild embeddings/index
  start_model.bat   # Start llama.cpp server (optional helper)
ui/
  index.html        # Minimal chat UI
```

## Using the chat UI
- After running `scripts\quick_launch.ps1` (recommended) or `launch.bat` / manual commands, open `http://localhost:3000`.
- Ask a question; the app retrieves top chunks from your indexed docs, adds them to the prompt, and streams the model response.
- Sources for retrieved chunks are shown under the chat output.

## Extending later
- Add PDF/HTML loaders in `app/utils.py`.
- Swap embeddings to an ONNX DirectML model if you want GPU acceleration without PyTorch.
- Add caching/change detection (hash files) to avoid re-embedding unchanged docs.
- Wire a better UI framework (React/Tauri/Electron) once this flow feels good.
```
