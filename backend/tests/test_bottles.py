from fastapi.testclient import TestClient

from app.db.session import SessionLocal
from app.main import app
from app.services.bottle_provisioning import new_bottle

client = TestClient(app)

STAFF_USER_ID = "Staff001"
STAFF_PASSWORD = "Staff@123"
ADMIN_USER_ID = "Admin"
ADMIN_PASSWORD = "Admin@123"


def _login(phone: str, password: str) -> str:
    response = client.post("/auth/login", json={"user_id": phone, "password": password})
    assert response.status_code == 200
    return response.json()["access_token"]


def _seed_bottles(count: int = 1, brand_name: str | None = None) -> list[int]:
    """Bottle creation isn't exposed over the API (see scripts/generate_bottles.py),
    so tests that need existing bottles seed them directly."""
    db = SessionLocal()
    try:
        bottles = [new_bottle(db, brand_name) for _ in range(count)]
        db.add_all(bottles)
        db.commit()
        ids = [b.id for b in bottles]
        return ids
    finally:
        db.close()


def test_staff_cannot_list_bottles():
    _seed_bottles(1)
    token = _login(STAFF_USER_ID, STAFF_PASSWORD)
    response = client.get("/bottles", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 403


def test_admin_can_list_bottles():
    _seed_bottles(1)
    token = _login(ADMIN_USER_ID, ADMIN_PASSWORD)
    headers = {"Authorization": f"Bearer {token}"}

    response = client.get("/bottles", headers=headers)
    assert response.status_code == 200
    assert len(response.json()) >= 1


def test_bottle_qr_image_endpoints_return_png():
    bottle_id = _seed_bottles(1)[0]
    token = _login(ADMIN_USER_ID, ADMIN_PASSWORD)
    headers = {"Authorization": f"Bearer {token}"}

    for suffix in ["refund", "manufacturing"]:
        qr_response = client.get(f"/bottles/{bottle_id}/qr/{suffix}", headers=headers)
        assert qr_response.status_code == 200
        assert qr_response.headers["content-type"] == "image/png"
        assert len(qr_response.content) > 0


def test_labels_pdf_for_specific_ids():
    ids = _seed_bottles(3)
    token = _login(ADMIN_USER_ID, ADMIN_PASSWORD)
    headers = {"Authorization": f"Bearer {token}"}

    pdf_response = client.get(
        f"/bottles/labels-pdf?ids={','.join(str(i) for i in ids)}", headers=headers
    )
    assert pdf_response.status_code == 200
    assert pdf_response.headers["content-type"] == "application/pdf"
    assert len(pdf_response.content) > 0


def test_labels_pdf_unknown_ids_returns_404():
    token = _login(ADMIN_USER_ID, ADMIN_PASSWORD)
    headers = {"Authorization": f"Bearer {token}"}

    response = client.get("/bottles/labels-pdf?ids=99999999", headers=headers)
    assert response.status_code == 404
