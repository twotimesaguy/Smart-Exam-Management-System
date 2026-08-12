"""Compatibility entrypoint for launching the FastAPI backend from repo root.

This lets `uvicorn main:app` work while keeping the real application code in
`backend/app/main.py`.
"""

import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent / "backend"
sys.path.insert(0, str(BACKEND_DIR))

from app.main import app
