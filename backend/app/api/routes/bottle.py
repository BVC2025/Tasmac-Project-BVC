import io
import secrets

import qrcode
from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import Response
from PIL import Image, ImageDraw, ImageFont
from sqlalchemy.orm import Session

from app.api.deps import get_current_admin_user
from app.db.session import get_db
from app.models.bottle import Bottle
from app.schemas.bottle import BottleCreate, BottleOut, BulkBottleCreate

router = APIRouter(prefix="/bottles", tags=["bottles"], dependencies=[Depends(get_current_admin_user)])

REFUND_PREFIX = "TSM-R"
MANUFACTURING_PREFIX = "TSM-M"
MAX_GENERATION_ATTEMPTS = 5


def _code_in_use(db: Session, candidate: str) -> bool:
    return (
        db.query(Bottle).filter(Bottle.refund_qr_code == candidate).first() is not None
        or db.query(Bottle).filter(Bottle.manufacturing_qr_code == candidate).first() is not None
    )


def _generate_unique_code(db: Session, prefix: str) -> str:
    for _ in range(MAX_GENERATION_ATTEMPTS):
        candidate = f"{prefix}-{secrets.token_hex(4)}"
        if not _code_in_use(db, candidate):
            return candidate
    raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Could not generate a unique QR code")


def _new_bottle(db: Session, brand_name: str | None) -> Bottle:
    return Bottle(
        refund_qr_code=_generate_unique_code(db, REFUND_PREFIX),
        manufacturing_qr_code=_generate_unique_code(db, MANUFACTURING_PREFIX),
        brand_name=brand_name,
    )


@router.get("", response_model=list[BottleOut])
def list_bottles(db: Session = Depends(get_db)):
    return db.query(Bottle).order_by(Bottle.id.desc()).all()


@router.post("", response_model=BottleOut, status_code=status.HTTP_201_CREATED)
def create_bottle(payload: BottleCreate, db: Session = Depends(get_db)):
    bottle = _new_bottle(db, payload.brand_name)
    db.add(bottle)
    db.commit()
    db.refresh(bottle)
    return bottle


@router.post("/bulk", response_model=list[BottleOut], status_code=status.HTTP_201_CREATED)
def create_bottles_bulk(payload: BulkBottleCreate, db: Session = Depends(get_db)):
    bottles = []
    for _ in range(payload.count):
        bottle = _new_bottle(db, payload.brand_name)
        db.add(bottle)
        db.flush()  # makes this bottle's codes visible to the next uniqueness check
        bottles.append(bottle)

    db.commit()
    for bottle in bottles:
        db.refresh(bottle)
    return bottles


PAGE_SIZE = (2480, 3508)  # A4 at 300 DPI
PAGE_MARGIN = 80
LABEL_COLS = 3
LABEL_ROWS = 3


def _load_font(size: int):
    try:
        return ImageFont.truetype("arial.ttf", size)
    except OSError:
        return ImageFont.load_default()


def _draw_centered_text(draw: ImageDraw.ImageDraw, text: str, center_x: int, y: int, font) -> None:
    bbox = draw.textbbox((0, 0), text, font=font)
    width = bbox[2] - bbox[0]
    draw.text((center_x - width // 2, y), text, fill="black", font=font)


def _build_labels_pdf(bottles: list[Bottle]) -> bytes:
    if not bottles:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No bottles to print")

    cell_width = (PAGE_SIZE[0] - 2 * PAGE_MARGIN) // LABEL_COLS
    cell_height = (PAGE_SIZE[1] - 2 * PAGE_MARGIN) // LABEL_ROWS
    per_page = LABEL_COLS * LABEL_ROWS

    qr_size = min(cell_width - 60, (cell_height - 160) // 2)
    label_font = _load_font(28)
    code_font = _load_font(24)

    pages = []
    for page_start in range(0, len(bottles), per_page):
        page_bottles = bottles[page_start : page_start + per_page]
        page = Image.new("RGB", PAGE_SIZE, "white")
        draw = ImageDraw.Draw(page)

        for index, bottle in enumerate(page_bottles):
            col = index % LABEL_COLS
            row = index // LABEL_COLS
            cell_x = PAGE_MARGIN + col * cell_width
            cell_y = PAGE_MARGIN + row * cell_height
            center_x = cell_x + cell_width // 2

            border = [cell_x + 10, cell_y + 10, cell_x + cell_width - 10, cell_y + cell_height - 10]
            draw.rectangle(border, outline="lightgray", width=2)

            y = cell_y + 20
            _draw_centered_text(draw, f"Bottle #{bottle.id}", center_x, y, label_font)
            y += 40

            _draw_centered_text(draw, "REFUND QR", center_x, y, label_font)
            y += 36
            refund_img = qrcode.make(bottle.refund_qr_code).resize((qr_size, qr_size))
            page.paste(refund_img, (center_x - qr_size // 2, y))
            y += qr_size + 8
            _draw_centered_text(draw, bottle.refund_qr_code, center_x, y, code_font)
            y += 40

            _draw_centered_text(draw, "MANUFACTURING QR", center_x, y, label_font)
            y += 36
            mfg_img = qrcode.make(bottle.manufacturing_qr_code).resize((qr_size, qr_size))
            page.paste(mfg_img, (center_x - qr_size // 2, y))
            y += qr_size + 8
            _draw_centered_text(draw, bottle.manufacturing_qr_code, center_x, y, code_font)

        pages.append(page)

    buffer = io.BytesIO()
    pages[0].save(buffer, format="PDF", save_all=True, append_images=pages[1:])
    return buffer.getvalue()


@router.get("/labels-pdf")
def get_labels_pdf(ids: str | None = Query(default=None), db: Session = Depends(get_db)):
    query = db.query(Bottle).order_by(Bottle.id)

    if ids:
        try:
            bottle_ids = [int(x) for x in ids.split(",") if x.strip()]
        except ValueError:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="ids must be a comma-separated list of integers")
        query = query.filter(Bottle.id.in_(bottle_ids))

    bottles = query.all()
    pdf_bytes = _build_labels_pdf(bottles)

    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={"Content-Disposition": "attachment; filename=bottle_labels.pdf"},
    )


@router.get("/{bottle_id}", response_model=BottleOut)
def get_bottle(bottle_id: int, db: Session = Depends(get_db)):
    bottle = db.get(Bottle, bottle_id)
    if bottle is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Bottle not found")
    return bottle


def _qr_png_response(value: str) -> Response:
    img = qrcode.make(value)
    buffer = io.BytesIO()
    img.save(buffer, format="PNG")
    return Response(content=buffer.getvalue(), media_type="image/png")


@router.get("/{bottle_id}/qr/refund")
def get_refund_qr_image(bottle_id: int, db: Session = Depends(get_db)):
    bottle = db.get(Bottle, bottle_id)
    if bottle is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Bottle not found")
    return _qr_png_response(bottle.refund_qr_code)


@router.get("/{bottle_id}/qr/manufacturing")
def get_manufacturing_qr_image(bottle_id: int, db: Session = Depends(get_db)):
    bottle = db.get(Bottle, bottle_id)
    if bottle is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Bottle not found")
    return _qr_png_response(bottle.manufacturing_qr_code)
