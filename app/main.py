import asyncio
import logging
import pathlib
from contextlib import asynccontextmanager
from typing import Dict, List

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from app.config import AppConfig
from app.llm import LlamaCPPClient
from app.rag import RAGConfig, RAGPipeline

logger = logging.getLogger(__name__)


def load_config(config_path: pathlib.Path) -> AppConfig:
    if not config_path.exists():
        raise RuntimeError(
            f"Config file not found at {config_path}. Copy config.example.yaml to config.yaml and update paths."
        )
    return AppConfig.load(config_path)


def build_pipeline(config: AppConfig) -> RAGPipeline:
    rag_config = RAGConfig(
        index_dir=pathlib.Path(config.data.index_dir),
        embedding_model=config.embedding.model,
        device=config.embedding.device,
        chunk_size=config.retrieval.chunk_size,
        chunk_overlap=config.retrieval.chunk_overlap,
        top_k=config.retrieval.k,
        cache_dir=pathlib.Path(config.embedding.cache_dir) if config.embedding.cache_dir else None,
        local_files_only=config.embedding.local_files_only,
    )
    pipeline = RAGPipeline(rag_config)
    pipeline.prime()
    return pipeline


def build_llm_client(config: AppConfig) -> LlamaCPPClient:
    return LlamaCPPClient(
        api_base=config.model.api_base,
        model_name=config.model.name,
        max_tokens=config.model.max_tokens,
        temperature=config.model.temperature,
        timeout_seconds=config.model.timeout_seconds if hasattr(config.model, "timeout_seconds") else 120,
    )


async def verify_llama_server(client: httpx.AsyncClient, llm: LlamaCPPClient) -> None:
    """
    Detect the common router-mode / no-model issue up front.
    If /v1/models exists and shows zero or missing models, raise a clear error.
    """
    try:
        resp = await client.get(f"{llm.api_base}/models")
    except httpx.HTTPError:
        # Connection errors are handled later when we actually call the model.
        return

    # Older llama.cpp builds may not implement /models; tolerate 404.
    if resp.status_code == 404:
        return

    try:
        resp.raise_for_status()
    except httpx.HTTPStatusError:
        return

    try:
        payload = resp.json()
    except Exception:
        return

    models = {m.get("id") for m in payload.get("data", []) if isinstance(m, dict)}
    if not models:
        raise RuntimeError(
            "llama.cpp is running without a loaded model (router mode). "
            f"Start llama-server.exe with --model <path> --alias {llm.model_name} --no-router, "
            "and stop any existing router-mode llama-server on the same port."
        )
    if llm.model_name not in models:
        raise RuntimeError(
            f"llama.cpp is serving models {sorted(models)}, but config.model.name is '{llm.model_name}'. "
            "Restart llama-server.exe with matching --alias, or update config.model.name."
        )


def get_app(config_path: pathlib.Path = pathlib.Path("config.yaml")) -> FastAPI:
    config = load_config(config_path)
    config.ensure_data_dirs()
    rag_pipeline = build_pipeline(config)
    llama_client = build_llm_client(config)

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        async with httpx.AsyncClient(timeout=config.model.timeout_seconds) as client:
            app.state.http_client = client
            await verify_llama_server(client, llama_client)
            yield
        app.state.http_client = None

    app = FastAPI(title="Bonsai Chatbot API", version="2.0", lifespan=lifespan)

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    class AskRequest(BaseModel):
        question: str

    class AskResponse(BaseModel):
        answer: str
        sources: List[Dict[str, str]]

    class IngestResponse(BaseModel):
        chunks: int

    @app.get("/health")
    async def health() -> Dict[str, str]:
        return {"status": "ok"}

    @app.post("/ask", response_model=AskResponse)
    async def ask(payload: AskRequest):
        hits = rag_pipeline.retrieve(payload.question)
        prompt = rag_pipeline.build_prompt(payload.question, hits)

        client: httpx.AsyncClient = getattr(app.state, "http_client", None)
        if client is None:
            raise HTTPException(status_code=500, detail="HTTP client not initialized.")

        try:
            content = await llama_client.generate(prompt, client)
        except httpx.ConnectError as exc:  # pragma: no cover - runtime guardrail
            raise HTTPException(
                status_code=502,
                detail=(
                    f"Failed to reach llama.cpp at {llama_client.api_base}. "
                    "Ensure llama-server.exe is running and config.model.api_base matches."
                ),
            ) from exc

        return AskResponse(answer=content.strip(), sources=list(hits))

    @app.post("/ingest", response_model=IngestResponse)
    async def ingest():
        loop = asyncio.get_event_loop()
        try:
            count = await loop.run_in_executor(None, rag_pipeline.rebuild, pathlib.Path(config.data.raw_dir))
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc))
        except Exception as exc:  # pragma: no cover - runtime guardrail
            raise HTTPException(status_code=500, detail=f"Ingestion failed: {exc}")

        return IngestResponse(chunks=count)

    return app


app = get_app()
