import logging
from dataclasses import dataclass
from typing import Any, Dict, Optional

import httpx
from fastapi import HTTPException

logger = logging.getLogger(__name__)


@dataclass
class LlamaCPPClient:
    api_base: str
    model_name: str
    max_tokens: int
    temperature: float
    timeout_seconds: int = 120

    async def generate(self, prompt: str, client: httpx.AsyncClient) -> str:
        chat_body = {
            "model": self.model_name,
            "messages": [
                {"role": "system", "content": "You are a helpful bonsai assistant."},
                {"role": "user", "content": prompt},
            ],
            "max_tokens": self.max_tokens,
            "temperature": self.temperature,
            "stream": False,
        }

        completion_body = {
            "model": self.model_name,
            "prompt": prompt,
            "max_tokens": self.max_tokens,
            "temperature": self.temperature,
            "stream": False,
        }

        def _extract_chat(payload: Dict[str, Any]) -> Optional[str]:
            return payload.get("choices", [{}])[0].get("message", {}).get("content")

        def _extract_completion(payload: Dict[str, Any]) -> Optional[str]:
            return payload.get("choices", [{}])[0].get("text")

        try:
            resp = await client.post(f"{self.api_base}/chat/completions", json=chat_body)
            resp.raise_for_status()
            data = resp.json()
            content = _extract_chat(data)
            if content:
                return content
            logger.warning("Chat completion payload missing content; retrying with /completions")
        except httpx.HTTPStatusError as exc:
            if exc.response.status_code in (400, 404) and "model not found" in exc.response.text.lower():
                detail = (
                    "Model not found on llama.cpp. Start llama-server.exe with "
                    f"--model <path> --alias {self.model_name} --no-router "
                    "(or update config.model.name to the alias you use), and stop any router-mode server already running."
                )
                raise HTTPException(status_code=400, detail=detail) from exc
            if exc.response.status_code not in (400, 404):
                raise HTTPException(
                    status_code=exc.response.status_code,
                    detail=f"Model call failed: {exc}. Response: {exc.response.text}",
                ) from exc
            logger.warning(
                "Chat completion failed with status %s. Retrying with /completions. Body: %s",
                exc.response.status_code,
                exc.response.text,
            )
        except Exception as exc:  # pragma: no cover - runtime guardrail
            raise HTTPException(status_code=500, detail=f"Model call failed: {exc}") from exc

        # Fallback to legacy /completions
        try:
            resp = await client.post(f"{self.api_base}/completions", json=completion_body)
            resp.raise_for_status()
            data = resp.json()
            content = _extract_completion(data)
            if not content:
                raise HTTPException(
                    status_code=500,
                    detail="Model returned an empty payload from /completions",
                )
            return content
        except httpx.HTTPStatusError as exc:
            if exc.response.status_code in (400, 404) and "model not found" in exc.response.text.lower():
                detail = (
                    "Model not found on llama.cpp (fallback). Start llama-server.exe with "
                    f"--model <path> --alias {self.model_name} --no-router "
                    "and keep config.model.name in sync; also stop any router-mode server already running."
                )
                raise HTTPException(status_code=400, detail=detail) from exc
            raise HTTPException(
                status_code=exc.response.status_code,
                detail=f"Model call failed after fallback: {exc}. Response: {exc.response.text}",
            ) from exc
        except Exception as exc:  # pragma: no cover - runtime guardrail
            raise HTTPException(status_code=500, detail=f"Model call failed after fallback: {exc}")
