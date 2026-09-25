from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_admin_user
from app.db.session import get_db
from app.models.shop import Shop
from app.schemas.shop import ShopCreate, ShopOut, ShopUpdate

router = APIRouter(prefix="/shops", tags=["shops"], dependencies=[Depends(get_current_admin_user)])


@router.get("", response_model=list[ShopOut])
def list_shops(db: Session = Depends(get_db)):
    return db.query(Shop).order_by(Shop.id).all()


@router.post("", response_model=ShopOut, status_code=status.HTTP_201_CREATED)
def create_shop(payload: ShopCreate, db: Session = Depends(get_db)):
    existing = db.query(Shop).filter(Shop.shop_code == payload.shop_code).first()
    if existing:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Shop code already exists")

    shop = Shop(**payload.model_dump())
    db.add(shop)
    db.commit()
    db.refresh(shop)
    return shop


@router.get("/{shop_id}", response_model=ShopOut)
def get_shop(shop_id: int, db: Session = Depends(get_db)):
    shop = db.get(Shop, shop_id)
    if shop is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Shop not found")
    return shop


@router.patch("/{shop_id}", response_model=ShopOut)
def update_shop(shop_id: int, payload: ShopUpdate, db: Session = Depends(get_db)):
    shop = db.get(Shop, shop_id)
    if shop is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Shop not found")

    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(shop, field, value)

    db.commit()
    db.refresh(shop)
    return shop


@router.delete("/{shop_id}", response_model=ShopOut)
def deactivate_shop(shop_id: int, db: Session = Depends(get_db)):
    shop = db.get(Shop, shop_id)
    if shop is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Shop not found")

    shop.is_active = False
    db.commit()
    db.refresh(shop)
    return shop
