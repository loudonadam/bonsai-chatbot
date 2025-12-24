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

## Quick start (Windows, step-by-step)
> These steps assume fresh Windows 11. Use PowerShell for the setup commands. Each helper script now leaves its window open and prints clear error messages if something fails.

1) **Clone the repo**
   ```powershell
   git clone <your fork url> BonsaiChat
   cd BonsaiChat
   ```
2) **Create and activate a virtual environment**
   ```powershell
   python -m venv .venv
   .\.venv\Scripts\activate
   pip install --upgrade pip
   pip install -r app/requirements.txt
   ```
3) **Place model + llama.cpp server**
   - Download a GGUF model (example: <https://huggingface.co/QuantFactory/Meta-Llama-3-8B-Instruct-GGUF>).
   - Put the model at `models\bonsai-gguf.gguf` **or** update `MODEL_PATH` in `scripts\launch.bat` / `scripts\start_model.bat` and `model.path` in `config.yaml` to the file you downloaded.
   - Download `llama-server.exe` from the llama.cpp Windows release and place it in `scripts\`.
4) **Configure the app**
   ```powershell
   copy config.example.yaml config.yaml
   ```
   Then edit `config.yaml`:
   - Set `model.path` to your GGUF file.
   - If you must stay offline, set `embedding.local_files_only: true` and set `embedding.model` to a local path or pre-downloaded folder. Optional: set `embedding.cache_dir` to a writable folder for cached models.
5) **Add documents to index**
   - Put your `.txt` or `.md` sources in `data\raw`. (The scripts create this folder if missing.)
6) **Build the index (ingestion)**
   - Recommended (explicit PowerShell steps so you can see errors):
     1. Open **PowerShell**.
     2. `Set-Location C:\path\to\bonsai-chatbot` (repo root).
     3. (If you created a venv) `.\.venv\Scripts\Activate.ps1`
     4. Set the module path for this shell: `set PYTHONPATH=$PWD`
     5. Run ingestion:  
        ```powershell
        python -m app.ingest --config config.yaml
        ```
   - If you prefer the helper script, you can still run it from the repo root to keep output visible:
     ```powershell
     scripts\rebuild_kb.bat
     ```
   - If anything fails, the PowerShell window will show the exact error (e.g., missing config/model, blocked download).
7) **Launch servers and UI (manual PowerShell steps; recommended if double-click doesn’t work)**
   - Open **PowerShell** at the repo root and activate your venv (if using one).
   - Start the API (keep this window open to see logs/errors):  
     ```powershell
     python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
     ```
   - In a **second** PowerShell window at the repo root (venv active), serve the UI:  
     ```powershell
     python -m http.server 3000 -d ui
     ```
   - (Optional) If you downloaded `llama-server.exe`, start it in a **third** PowerShell window:  
     ```powershell
     scripts\start_model.bat
     ```
   - Then open <http://localhost:3000> in your browser.
   - If you still want the helper script, run it from an open shell so logs stay visible:  
     ```powershell
     cmd.exe /c scripts\launch.bat
     ```
   - **Prefer one-window launch?** Use the PowerShell helper below to start everything in the current shell (logs go to `logs\`).

### One-window launch helper (PowerShell)
- Ensure dependencies are installed (virtual env activated if you use one).
- From the repo root (or just double-click in `scripts\`), run:
  ```powershell
  PowerShell -ExecutionPolicy Bypass -File scripts\quick_launch.ps1
  ```
- The script will:
  - Check for `config.yaml` and `python` on PATH.
  - Create `data/raw` and `data/index` if missing.
  - Launch the API, UI server, and (if available) `llama-server.exe` **without opening extra PowerShell windows**.
  - Drop logs to `logs/api.log`, `logs/ui.log`, and `logs/llama-server.log`.
  - Open your browser to `http://localhost:3000` by default.
- Virtual envs: if a `.venv\Scripts\python.exe` exists in the repo root, the script will auto-use it (so right-click “Run with PowerShell” works). Otherwise it falls back to the system `python`.
- Press Enter in the same window to cleanly stop all launched processes.
- Switches:
  - `-SkipModel` to avoid starting `llama-server.exe`.
  - `-NoBrowser` to skip auto-opening the UI tab.

### Common troubleshooting tips (PowerShell)
- Ensure `config.yaml` exists in the repo root.
- Ensure `PYTHONPATH` is set for the session (`set PYTHONPATH=$PWD`) if you see `ModuleNotFoundError: No module named 'app'`.
- Leave each window open to read any traceback or missing-file warnings.

## Commands (manual, if you prefer)
- Rebuild index:
  ```powershell
  python app/ingest.py --config config.yaml
  ```
- Start API:
  ```powershell
  uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
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
- After running `launch.bat` (or starting services manually), open `http://localhost:3000`.
- Ask a question; the app retrieves top chunks from your indexed docs, adds them to the prompt, and streams the model response.
- Sources for retrieved chunks are shown under the chat output.

## Extending later
- Add PDF/HTML loaders in `app/utils.py`.
- Swap embeddings to an ONNX DirectML model if you want GPU acceleration without PyTorch.
- Add caching/change detection (hash files) to avoid re-embedding unchanged docs.
- Wire a better UI framework (React/Tauri/Electron) once this flow feels good.
```
