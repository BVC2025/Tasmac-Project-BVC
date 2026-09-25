from pydantic import BaseModel, ConfigDict, Field

from app.models.bottle import BottleStatus


class BottleCreate(BaseModel):
    brand_name: str | None = None


class BulkBottleCreate(BaseModel):
    count: int = Field(gt=0, le=500)
    brand_name: str | None = None


class BottleOut(BaseModel):
    id: int
    refund_qr_code: str
    manufacturing_qr_code: str
    brand_name: str | None
    status: BottleStatus

    model_config = ConfigDict(from_attributes=True)
