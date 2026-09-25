from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.api.routes.auth import router as auth_router
from app.api.routes.bottle import router as bottle_router
from app.api.routes.location import router as location_router
from app.api.routes.returns import router as returns_router
from app.api.routes.shop import router as shop_router
from app.api.routes.staff import router as staff_router
from app.core.config import settings

app = FastAPI(title=settings.app_name)

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
