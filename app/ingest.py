import argparse
import pathlib

from app.config import AppConfig
from app.rag import RAGConfig, RAGPipeline


def run_ingest(config_path: pathlib.Path) -> int:
    config = AppConfig.load(config_path)
    config.ensure_data_dirs()

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
    return pipeline.rebuild(pathlib.Path(config.data.raw_dir))


def main() -> None:
    parser = argparse.ArgumentParser(description="Ingest bonsai documents into the vector store.")
    parser.add_argument(
        "--config",
        type=pathlib.Path,
        default=pathlib.Path("config.yaml"),
        help="Path to config YAML (default: config.yaml)",
    )
    args = parser.parse_args()

    try:
        count = run_ingest(args.config)
    except ValueError as exc:
        parser.error(str(exc))
        return

    print(f"Ingested {count} chunks into the index.")


if __name__ == "__main__":
    main()
