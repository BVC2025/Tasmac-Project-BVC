import pytest

from app.db.session import SessionLocal
from app.models.shop import Shop
from app.models.user import User

# Tests run against the real dev database (no separate test DB yet), so
# clean up the throwaway records each test creates before every run.
TEST_STAFF_PHONES = ["7777777777", "7000000001"]
TEST_SHOP_CODES = ["TST-001", "DUP-001"]


@pytest.fixture(autouse=True)
def cleanup_test_records():
    db = SessionLocal()
    try:
        db.query(User).filter(User.phone_number.in_(TEST_STAFF_PHONES)).delete(synchronize_session=False)
        db.query(Shop).filter(Shop.shop_code.in_(TEST_SHOP_CODES)).delete(synchronize_session=False)
        db.commit()
    finally:
        db.close()

    yield
