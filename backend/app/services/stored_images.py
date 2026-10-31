"""Images (staff photos, rejection evidence) stored as bytes in the database.

Render's free tier has no persistent disk: anything written under media/ is
gone after the next deploy or restart, which left staff photos and evidence
images pointing at missing files. The bytes now live in the row itself; the
old *_path column holds STORED_IN_DB as the marker that an image exists.
"""

from pathlib import Path

from fastapi import HTTPException, UploadFile, status
from fastapi.responses import FileResponse, Response

STORED_IN_DB = "db"
MAX_IMAGE_BYTES = 5 * 1024 * 1024


async def read_upload(file: UploadFile) -> bytes:
    data = await file.read()
    if not data:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="The image is empty")
    if len(data) > MAX_IMAGE_BYTES:
        raise HTTPException(status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, detail="The image is larger than 5 MB")
    return data


def is_available(path: str | None) -> bool:
    """True when the image can actually be served — stored in the database,
    or (for images saved before this change) its file still exists."""
    if path is None:
        return False
    return path == STORED_IN_DB or Path(path).exists()


def image_response(path: str | None, data: bytes | None, missing_detail: str):
    if path == STORED_IN_DB and data:
        media_type = "image/png" if data.startswith(b"\x89PNG") else "image/jpeg"
        return Response(content=data, media_type=media_type)
    if path is not None and path != STORED_IN_DB and Path(path).exists():
        return FileResponse(Path(path))
    raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=missing_detail)
