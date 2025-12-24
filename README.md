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

## Quick start (Windows)
1. **Clone**
   ```powershell
   git clone <your fork url> BonsaiChat
   cd BonsaiChat
   ```
2. **Python environment**
   ```powershell
   python -m venv .venv
   .venv\Scripts\activate
   pip install --upgrade pip
   pip install -r app/requirements.txt
   ```
3. **Place your model**
   - Put your GGUF model at `models\bonsai-gguf.gguf` (or update the path in `config.example.yaml`).
   - Put `llama-server.exe` (from `llama.cpp` release) in `scripts\` or anywhere on PATH.
4. **Configure**
   - Copy `config.example.yaml` to `config.yaml` and adjust paths (model path, data folders, ports).
5. **Add documents**
   - Drop your trusted sources into `data/raw` (supports `.txt` and `.md` for now).
6. **Rebuild the knowledge base**
   - Double-click `scripts\rebuild_kb.bat` (or run `python app/ingest.py --config config.yaml`).
7. **Launch everything**
   - Double-click `scripts\launch.bat`. This will:
     - Start `llama-server.exe` (if configured) for inference.
     - Start the FastAPI app (Uvicorn) on port 8000.
     - Open the UI at `http://localhost:3000` (static HTML hitting the API).

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
