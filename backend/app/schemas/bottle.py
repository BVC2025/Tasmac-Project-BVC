from pydantic import BaseModel, ConfigDict

from app.models.bottle import BottleStatus


class BottleOut(BaseModel):
    id: int
    refund_qr_code: str
    manufacturing_qr_code: str
    brand_name: str | None
    status: BottleStatus

    model_config = ConfigDict(from_attributes=True)
