from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.database import init_db
from app.routers import (
    allocation,
    assignments,
    attendance,
    auth,
    malpractice,
    students,
)

app = FastAPI(title="Intelligent Exam System API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def on_startup() -> None:
    init_db()


@app.get("/health")
def health_check() -> dict[str, str]:
    return {"status": "ok"}


app.include_router(auth.router)
app.include_router(students.router)
app.include_router(allocation.router)
app.include_router(attendance.router)
app.include_router(malpractice.router)
app.include_router(assignments.router)
