import argparse
import pathlib
from dataclasses import dataclass
from typing import Any, Dict

import yaml

from app import rag


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
        return AppConfig(**data)


def run_ingest(config_path: pathlib.Path) -> int:
    app_config = AppConfig.load(config_path)
    raw_dir = pathlib.Path(app_config.data["raw_dir"])
    index_dir = pathlib.Path(app_config.data["index_dir"])
    index_dir.mkdir(parents=True, exist_ok=True)

    rag_config = rag.RAGConfig(
        index_dir=index_dir,
        embedding_model=app_config.embedding["model"],
        device=app_config.embedding.get("device", "cpu"),
        chunk_size=int(app_config.retrieval.get("chunk_size", 800)),
        chunk_overlap=int(app_config.retrieval.get("chunk_overlap", 120)),
        top_k=int(app_config.retrieval.get("k", 4)),
    )

    if not raw_dir.exists():
        raise FileNotFoundError(f"Raw data directory not found: {raw_dir}")

    count = rag.ingest_directory(rag_config, raw_dir)
    return count


def main() -> None:
    parser = argparse.ArgumentParser(description="Ingest bonsai documents")
    parser.add_argument("--config", type=pathlib.Path, default=pathlib.Path("config.yaml"))
    args = parser.parse_args()

    count = run_ingest(args.config)
    print(f"Ingested {count} chunks into the index.")


if __name__ == "__main__":
    main()
