import os

import httpx


async def forward_report(payload: dict) -> tuple[str, str | None]:
    webhook_url = os.getenv("MALPRACTICE_WEBHOOK_URL", "").strip()
    if not webhook_url:
        return "queued", "MALPRACTICE_WEBHOOK_URL is not configured."

    try:
        async with httpx.AsyncClient(timeout=15) as client:
            response = await client.post(webhook_url, json=payload)
            response.raise_for_status()
        return "forwarded", None
    except Exception as error:
        return "failed", str(error)
