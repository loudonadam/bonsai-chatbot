import pathlib
from typing import Iterable, List


def iter_text_files(root: pathlib.Path) -> Iterable[pathlib.Path]:
    for path in root.rglob("*"):
        if path.is_file() and path.suffix.lower() in {".txt", ".md"}:
            yield path


def read_text_file(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8", errors="ignore")


def chunk_text(text: str, chunk_size: int, chunk_overlap: int) -> List[str]:
    words = text.split()
    chunks: List[str] = []
    start = 0
    while start < len(words):
        end = min(len(words), start + chunk_size)
        chunks.append(" ".join(words[start:end]))
        if end == len(words):
            break
        start = end - chunk_overlap
        if start < 0:
            start = 0
    return chunks
