import logging
import os
import pathlib
from dataclasses import dataclass
from functools import lru_cache
from threading import Lock
from typing import List, Optional, Sequence

# Silence Chroma telemetry warnings/errors in constrained environments.
os.environ.setdefault("CHROMA_TELEMETRY_ENABLED", "false")

import chromadb
from chromadb.api.types import Documents, EmbeddingFunction, Embeddings, Metadatas
from sentence_transformers import SentenceTransformer

from app import utils

logger = logging.getLogger(__name__)


@dataclass
class RAGConfig:
    index_dir: pathlib.Path
    embedding_model: str
    device: str
    chunk_size: int
    chunk_overlap: int
    top_k: int
    cache_dir: Optional[pathlib.Path] = None
    local_files_only: bool = False
    collection_name: str = "bonsai"


@lru_cache(maxsize=2)
def _load_embedding_model(
    model_name: str, device: str, cache_dir: Optional[str], local_files_only: bool
) -> SentenceTransformer:
    try:
        logger.info("Loading embedding model '%s' on device '%s' (cache_dir=%s)", model_name, device, cache_dir)
        return SentenceTransformer(
            model_name,
            device=device,
            cache_folder=cache_dir,
            local_files_only=local_files_only,
        )
    except Exception as exc:  # pragma: no cover - runtime guardrail
        hint = (
            f"Failed to load embedding model '{model_name}'. "
            "If you are offline, download the model manually and point embedding.model "
            "to the local folder (or set embedding.local_files_only: true). "
            f"cache_dir={cache_dir or 'default cache'}"
        )
        raise RuntimeError(hint) from exc


class SentenceTransformerEmbedding(EmbeddingFunction):
    def __init__(
        self,
        model_name: str,
        device: str,
        cache_dir: Optional[pathlib.Path],
        local_files_only: bool,
    ) -> None:
        cache_dir_str = str(cache_dir) if cache_dir else None
        self.model = _load_embedding_model(model_name, device, cache_dir_str, local_files_only)

    def __call__(self, input: Documents) -> Embeddings:  # type: ignore[override]
        return self.model.encode(list(input), normalize_embeddings=True).tolist()


def build_client(index_dir: pathlib.Path) -> chromadb.Client:
    index_dir.mkdir(parents=True, exist_ok=True)
    return chromadb.PersistentClient(path=str(index_dir))


def ensure_collection(client: chromadb.Client, name: str, embedding_fn: EmbeddingFunction):
    if name in {col.name for col in client.list_collections()}:
        return client.get_collection(name=name, embedding_function=embedding_fn)
    return client.create_collection(name=name, embedding_function=embedding_fn)


class RAGPipeline:
    def __init__(self, config: RAGConfig) -> None:
        self.config = config
        self._embedding_fn = SentenceTransformerEmbedding(
            model_name=config.embedding_model,
            device=config.device,
            cache_dir=config.cache_dir,
            local_files_only=config.local_files_only,
        )
        self._client = build_client(config.index_dir)
        self._collection = ensure_collection(self._client, config.collection_name, self._embedding_fn)
        self._lock = Lock()

    def prime(self) -> None:
        _ = self._embedding_fn
        logger.info("RAG pipeline ready. Index at %s", self.config.index_dir)

    def rebuild(self, source_dir: pathlib.Path) -> int:
        with self._lock:
            if self.config.collection_name in {col.name for col in self._client.list_collections()}:
                logger.info("Resetting collection '%s'", self.config.collection_name)
                self._client.delete_collection(name=self.config.collection_name)
            self._collection = self._client.create_collection(
                name=self.config.collection_name, embedding_function=self._embedding_fn
            )
            collection = self._collection

        documents: Documents = []
        metadatas: Metadatas = []
        ids: List[str] = []

        for path in utils.iter_text_files(source_dir):
            raw_text = utils.read_text_file(path)
            chunks = utils.chunk_text(
                raw_text,
                chunk_size=self.config.chunk_size,
                chunk_overlap=self.config.chunk_overlap,
            )
            for idx, chunk in enumerate(chunks):
                rel = path.relative_to(source_dir)
                documents.append(chunk)
                metadatas.append({"source": str(rel)})
                ids.append(f"{rel}::{idx}")

        if not documents:
            logger.warning("No documents found under %s; skipping ingestion", source_dir)
            return 0

        logger.info("Adding %d chunks to collection '%s'", len(documents), self.config.collection_name)
        collection.add(documents=documents, metadatas=metadatas, ids=ids)
        return len(documents)

    def retrieve(self, query: str) -> Sequence[dict]:
        with self._lock:
            if self._collection is None:
                self._collection = ensure_collection(self._client, self.config.collection_name, self._embedding_fn)
            collection = self._collection

        results = collection.query(query_texts=[query], n_results=self.config.top_k)
        hits = []
        for doc, meta in zip(results.get("documents", [[]])[0], results.get("metadatas", [[]])[0]):
            hits.append({"text": doc, "source": meta.get("source", "unknown")})
        return hits

    @staticmethod
    def build_prompt(question: str, hits: Sequence[dict]) -> str:
        context_blocks = []
        for hit in hits:
            context_blocks.append(f"Source: {hit['source']}\n{hit['text']}")
        context = "\n\n".join(context_blocks)
        return (
            "You are a helpful bonsai assistant. Use only the provided context. "
            "If the answer is not in the context, say you don't know.\n\n"
            f"Context:\n{context}\n\nQuestion: {question}\nAnswer:"
        )
