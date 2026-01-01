import asyncio
import logging
import pathlib
from contextlib import asynccontextmanager
from dataclasses import dataclass
from typing import Any, Dict, List, Optional
import os

import httpx
import yaml
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from app import rag

logger = logging.getLogger(__name__)


@dataclass
class AppConfig:
    model: Dict[str, Any]
    server: Dict[str, Any]
    ui: Dict[str, Any]
    embedding: Dict[str, Any]
    retrieval: Dict[str, Any]
    data: Dict[str, Any]

    @staticmethod
    def load(path: pathlib.Path) -> "AppConfig":
        with path.open("r", encoding="utf-8") as f:
            data = yaml.safe_load(f)

        # Allow quick launch scripts to override the model API base without touching the YAML
        env_api_base = os.getenv("BONSAI_MODEL_API_BASE")
        if env_api_base:
            data.setdefault("model", {})
            data["model"]["api_base"] = env_api_base

        return AppConfig(**data)


def get_app(config_path: pathlib.Path = pathlib.Path("config.yaml")) -> FastAPI:
    app_config = AppConfig.load(config_path)

    index_dir = pathlib.Path(app_config.data["index_dir"])
    raw_dir = pathlib.Path(app_config.data["raw_dir"])
    index_dir.mkdir(parents=True, exist_ok=True)
    raw_dir.mkdir(parents=True, exist_ok=True)

    cache_dir = app_config.embedding.get("cache_dir")

    rag_config = rag.RAGConfig(
        index_dir=index_dir,
        embedding_model=app_config.embedding["model"],
        device=app_config.embedding.get("device", "cpu"),
        chunk_size=int(app_config.retrieval.get("chunk_size", 800)),
        chunk_overlap=int(app_config.retrieval.get("chunk_overlap", 120)),
        top_k=int(app_config.retrieval.get("k", 4)),
        cache_dir=pathlib.Path(cache_dir) if cache_dir else None,
        local_files_only=bool(app_config.embedding.get("local_files_only", False)),
    )
    rag_service = rag.RAGService(rag_config)

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        rag_service.prime()
        client_timeout = app_config.model.get("timeout_seconds", 120)
        async with httpx.AsyncClient(timeout=client_timeout) as client:
            app.state.http_client = client
            yield
        app.state.http_client = None

    app = FastAPI(title="Bonsai Chatbot API", version="1.0", lifespan=lifespan)

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

    @app.get("/health")
    async def health() -> Dict[str, str]:
        return {"status": "ok"}

    @app.post("/ask", response_model=AskResponse)
    async def ask(payload: AskRequest):
        try:
            hits = rag_service.retrieve(payload.question)
            if not hits:
                logger.warning("No retrieval results for query: %s", payload.question)
        except RuntimeError as exc:
            raise HTTPException(status_code=500, detail=str(exc))
        prompt = rag.build_prompt(payload.question, hits)

        api_base = app_config.model.get("api_base", "http://127.0.0.1:8080/v1")
        body = {
            "model": "local-llm",
            "messages": [
                {"role": "system", "content": "You are a helpful bonsai assistant."},
                {"role": "user", "content": prompt},
            ],
            "max_tokens": app_config.model.get("max_tokens", 512),
            "temperature": app_config.model.get("temperature", 0.7),
            "stream": False,
        }

        try:
            client: Optional[httpx.AsyncClient] = getattr(app.state, "http_client", None)
            if client is None:
                raise RuntimeError("HTTP client not initialized; FastAPI lifespan may not have started.")
            resp = await client.post(f"{api_base}/chat/completions", json=body)
            resp.raise_for_status()
            data = resp.json()
            content: Optional[str] = data.get("choices", [{}])[0].get("message", {}).get("content")
        except httpx.ConnectError as exc:  # pragma: no cover - runtime errors reported to user
            hint = (
                f"Failed to reach LLM server at {api_base}. "
                "Make sure llama.cpp is running (e.g., scripts/start_model.bat) "
                "and that config.model.api_base matches the server URL."
            )
            raise HTTPException(status_code=502, detail=hint) from exc
        except httpx.HTTPStatusError as exc:  # pragma: no cover - runtime errors reported to user
            raise HTTPException(status_code=exc.response.status_code, detail=f"Model call failed: {exc}") from exc
        except Exception as exc:  # pragma: no cover - runtime errors reported to user
            raise HTTPException(status_code=500, detail=f"Model call failed: {exc}") from exc

        if not content:
            raise HTTPException(status_code=500, detail="Empty response from model")

        return AskResponse(answer=content.strip(), sources=list(hits))

    class IngestResponse(BaseModel):
        chunks: int

    @app.post("/ingest", response_model=IngestResponse)
    async def ingest():
        loop = asyncio.get_event_loop()
        try:
            count = await loop.run_in_executor(None, rag_service.ingest_directory, raw_dir)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc))
        except Exception as exc:  # pragma: no cover - runtime guardrail
            raise HTTPException(status_code=500, detail=f"Ingestion failed: {exc}")
        return IngestResponse(chunks=count)

    return app


app = get_app()
