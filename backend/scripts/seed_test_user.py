"""Creates test users and a test shop for exercising auth, RBAC and geofencing.

Proper staff/shop onboarding is done via the /staff and /shops APIs (Phase 7/8),
by an admin. This script only bootstraps enough data locally to exercise those
APIs and the Phase 9 location-verification flow end to end.
Run with: python -m scripts.seed_test_user
"""

from app.core.security import hash_password
from app.db.session import SessionLocal
from app.models.shop import Shop
from app.models.user import User, UserRole

TEST_SHOP = {
    "name": "TASMAC Outlet - Test",
    "shop_code": "SEED-001",
    "address": "Erode, Tamil Nadu",
    "latitude": 11.040952791653277,
    "longitude": 77.03880915156792,
}

TEST_USERS = [
    {"full_name": "Test Staff", "phone_number": "9999999999", "password": "Staff@123", "role": UserRole.STAFF},
    {"full_name": "Test Admin", "phone_number": "8888888888", "password": "Admin@123", "role": UserRole.ADMIN},
]


def run():
    db = SessionLocal()
    try:
        shop = db.query(Shop).filter(Shop.shop_code == TEST_SHOP["shop_code"]).first()
        if shop is None:
            shop = Shop(**TEST_SHOP)
            db.add(shop)
            db.commit()
            db.refresh(shop)
            print(f"Created shop: {shop.name} (id={shop.id}) at ({shop.latitude}, {shop.longitude})")
        else:
            print(f"Shop {TEST_SHOP['shop_code']} already exists (id={shop.id})")

        for data in TEST_USERS:
            existing = db.query(User).filter(User.phone_number == data["phone_number"]).first()
            if existing:
                print(f"User with phone {data['phone_number']} already exists (id={existing.id})")
                continue

            user = User(
                full_name=data["full_name"],
                phone_number=data["phone_number"],
                hashed_password=hash_password(data["password"]),
                role=data["role"],
                shop_id=shop.id if data["role"] == UserRole.STAFF else None,
                is_active=True,
            )
            db.add(user)
            db.commit()
            print(f"Created {data['role'].value} user: phone={data['phone_number']} password={data['password']}")
    finally:
        db.close()


if __name__ == "__main__":
    run()
