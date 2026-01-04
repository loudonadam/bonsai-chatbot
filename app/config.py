import os
import pathlib
from dataclasses import dataclass
from typing import Any, Dict, Optional

import yaml


@dataclass
class ModelSettings:
    path: str
    server_binary: str
    api_base: str
    max_tokens: int = 512
    temperature: float = 0.7
    timeout_seconds: int = 120
    name: str = "local-llm"


@dataclass
class ServerSettings:
    host: str
    port: int


@dataclass
class UiSettings:
    host: str
    port: int


@dataclass
class EmbeddingSettings:
    model: str
    device: str
    cache_dir: Optional[str] = None
    local_files_only: bool = False


@dataclass
class RetrievalSettings:
    k: int
    chunk_size: int
    chunk_overlap: int


@dataclass
class DataSettings:
    raw_dir: str
    index_dir: str


@dataclass
class AppConfig:
    model: ModelSettings
    server: ServerSettings
    ui: UiSettings
    embedding: EmbeddingSettings
    retrieval: RetrievalSettings
    data: DataSettings

    @classmethod
    def _coerce(cls, data: Dict[str, Any]) -> "AppConfig":
        return cls(
            model=ModelSettings(**data["model"]),
            server=ServerSettings(**data["server"]),
            ui=UiSettings(**data["ui"]),
            embedding=EmbeddingSettings(**data["embedding"]),
            retrieval=RetrievalSettings(**data["retrieval"]),
            data=DataSettings(**data["data"]),
        )

    @classmethod
    def load(cls, path: pathlib.Path) -> "AppConfig":
        with path.open("r", encoding="utf-8") as handle:
            payload = yaml.safe_load(handle)

        env_api_base = os.getenv("BONSAI_MODEL_API_BASE")
        if env_api_base:
            payload.setdefault("model", {})
            payload["model"]["api_base"] = env_api_base

        env_model_path = os.getenv("BONSAI_MODEL_PATH")
        if env_model_path:
            payload.setdefault("model", {})
            payload["model"]["path"] = env_model_path

        return cls._coerce(payload)

    def ensure_data_dirs(self) -> None:
        pathlib.Path(self.data.raw_dir).mkdir(parents=True, exist_ok=True)
        pathlib.Path(self.data.index_dir).mkdir(parents=True, exist_ok=True)
