import logging
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from app.api.routes.auth import router as auth_router
from app.api.routes.bottle import router as bottle_router
from app.api.routes.location import router as location_router
from app.api.routes.returns import router as returns_router
from app.api.routes.shop import router as shop_router
from app.api.routes.staff import router as staff_router
from app.core.config import settings

app = FastAPI(title=settings.app_name)

logger = logging.getLogger(__name__)


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """Without this an unexpected error returns a plain-text "Internal Server
    Error" body, which the app can't read a message from, so staff only ever
    saw a generic "Could not verify ..." with no hint of the cause."""
    logger.exception("Unhandled error on %s %s", request.method, request.url.path)
    return JSONResponse(
        status_code=500,
        content={"detail": f"Server error ({type(exc).__name__}) — please try again. If it keeps happening, report it to the admin."},
    )

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if settings.app_env == "development" else [],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router)
app.include_router(staff_router)
app.include_router(shop_router)
app.include_router(location_router)
app.include_router(bottle_router)
app.include_router(returns_router)

Path("media/evidence").mkdir(parents=True, exist_ok=True)
app.mount("/media", StaticFiles(directory="media"), name="media")


@app.get("/health")
def health_check():
    return {"status": "ok", "app": settings.app_name, "env": settings.app_env}
