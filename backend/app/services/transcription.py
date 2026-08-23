import base64
import os

import httpx


class TranscriptionConfigurationError(RuntimeError):
    """Raised when the deployed service has no speech provider configured."""


class TranscriptionError(RuntimeError):
    """Raised when the speech provider cannot produce a usable transcript."""


# Gemini accepts inline media requests up to 20 MB. Base64 expands the audio by
# roughly one third, so keep the source audio well below that request limit.
MAX_INLINE_AUDIO_BYTES = 10 * 1024 * 1024


async def transcribe_audio(
    *, audio_bytes: bytes, content_type: str | None, filename: str | None
) -> str:
    """Return a plain-text transcript for a short recorded voice note."""
    api_key = os.getenv("GEMINI_API_KEY", "").strip()
    if not api_key:
        raise TranscriptionConfigurationError(
            "Speech transcription has not been configured on the server."
        )

    if not audio_bytes:
        raise TranscriptionError("The voice recording is empty.")
    if len(audio_bytes) > MAX_INLINE_AUDIO_BYTES:
        raise TranscriptionError(
            "The voice recording is too large to transcribe. Keep it under 10 MB."
        )

    model = os.getenv("GEMINI_MODEL", "gemini-2.5-flash-lite").strip()
    if not model:
        raise TranscriptionConfigurationError("No Gemini model is configured.")

    mime_type = _audio_mime_type(content_type, filename)
    payload = {
        "contents": [
            {
                "role": "user",
                "parts": [
                    {
                        "text": (
                            "Transcribe the spoken words in this audio exactly. "
                            "Return only the transcript; do not add a title, summary, "
                            "speaker labels, or commentary."
                        )
                    },
                    {
                        "inlineData": {
                            "mimeType": mime_type,
                            "data": base64.b64encode(audio_bytes).decode("ascii"),
                        }
                    },
                ],
            }
        ]
    }

    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(90.0)) as client:
            response = await client.post(
                f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
                headers={"x-goog-api-key": api_key},
                json=payload,
            )
        response.raise_for_status()
    except httpx.HTTPError as error:
        raise TranscriptionError(
            "The transcription service could not process this voice note."
        ) from error

    transcript = _transcript_from_response(response.json())
    if not transcript:
        raise TranscriptionError("No speech was recognised in this voice note.")
    return transcript


def _audio_mime_type(content_type: str | None, filename: str | None) -> str:
    suffix = (filename or "").lower().rsplit(".", maxsplit=1)[-1]
    if suffix == "wav":
        return "audio/wav"
    if suffix in {"m4a", "aac"}:
        return "audio/aac"
    if suffix == "webm":
        return "audio/webm"
    if content_type and content_type.startswith("audio/"):
        return content_type
    return "audio/aac"


def _transcript_from_response(payload: dict) -> str:
    candidates = payload.get("candidates", [])
    if not candidates:
        return ""
    parts = candidates[0].get("content", {}).get("parts", [])
    return "".join(
        part.get("text", "") for part in parts if isinstance(part, dict)
    ).strip()
