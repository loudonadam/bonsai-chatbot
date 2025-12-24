import pathlib
from dataclasses import dataclass
from typing import List, Optional, Sequence

import chromadb
from chromadb.api.types import Documents, EmbeddingFunction, Embeddings, Metadatas
from sentence_transformers import SentenceTransformer

from app import utils


@dataclass
class RAGConfig:
    index_dir: pathlib.Path
    embedding_model: str
    chunk_size: int
    chunk_overlap: int
    top_k: int
    device: str = "cpu"
    cache_dir: Optional[pathlib.Path] = None
    local_files_only: bool = False


class SentenceTransformerEmbedding(EmbeddingFunction):
    def __init__(
        self,
        model_name: str,
        device: str = "cpu",
        cache_dir: Optional[pathlib.Path] = None,
        local_files_only: bool = False,
    ) -> None:
        try:
            self.model = SentenceTransformer(
                model_name,
                device=device,
                cache_folder=str(cache_dir) if cache_dir else None,
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

    def __call__(self, input: Documents) -> Embeddings:  # type: ignore[override]
        return self.model.encode(list(input), normalize_embeddings=True).tolist()


def build_client(index_dir: pathlib.Path) -> chromadb.Client:
    return chromadb.PersistentClient(path=str(index_dir))


def ensure_collection(client: chromadb.Client, name: str, embedding_fn: EmbeddingFunction):
    if name in {col.name for col in client.list_collections()}:
        return client.get_collection(name=name, embedding_function=embedding_fn)
    return client.create_collection(name=name, embedding_function=embedding_fn)


def ingest_directory(config: RAGConfig, source_dir: pathlib.Path, collection_name: str = "bonsai") -> int:
    embedding_fn = SentenceTransformerEmbedding(
        config.embedding_model,
        device=config.device,
        cache_dir=config.cache_dir,
        local_files_only=config.local_files_only,
    )
    client = build_client(config.index_dir)
    collection = ensure_collection(client, collection_name, embedding_fn)

    documents: Documents = []
    metadatas: Metadatas = []
    ids: List[str] = []

    for path in utils.iter_text_files(source_dir):
        raw_text = utils.read_text_file(path)
        chunks = utils.chunk_text(raw_text, chunk_size=config.chunk_size, chunk_overlap=config.chunk_overlap)
        for idx, chunk in enumerate(chunks):
            doc_id = f"{path.relative_to(source_dir)}::{idx}"
            documents.append(chunk)
            metadatas.append({"source": str(path.relative_to(source_dir))})
            ids.append(doc_id)

    if not documents:
        return 0

    collection.delete(where={"source": {"$exists": True}})
    collection.add(documents=documents, metadatas=metadatas, ids=ids)
    return len(documents)


def retrieve(
    query: str,
    config: RAGConfig,
    collection_name: str = "bonsai",
) -> Sequence[dict]:
    embedding_fn = SentenceTransformerEmbedding(
        config.embedding_model,
        device=config.device,
        cache_dir=config.cache_dir,
        local_files_only=config.local_files_only,
    )
    client = build_client(config.index_dir)
    collection = ensure_collection(client, collection_name, embedding_fn)
    results = collection.query(query_texts=[query], n_results=config.top_k)
    hits = []
    for doc, meta in zip(results.get("documents", [[]])[0], results.get("metadatas", [[]])[0]):
        hits.append({"text": doc, "source": meta.get("source", "unknown")})
    return hits


def build_prompt(query: str, hits: Sequence[dict]) -> str:
    context_blocks = []
    for hit in hits:
        context_blocks.append(f"Source: {hit['source']}\n{hit['text']}")
    context = "\n\n".join(context_blocks)
    return (
        "You are a helpful bonsai assistant. Use only the provided context. "
        "If the answer is not in the context, say you don't know.\n\n"
        f"Context:\n{context}\n\nQuestion: {query}\nAnswer:"
    )
