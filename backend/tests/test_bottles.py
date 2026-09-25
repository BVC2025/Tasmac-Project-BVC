from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

STAFF_PHONE = "9999999999"
STAFF_PASSWORD = "Staff@123"
ADMIN_PHONE = "8888888888"
ADMIN_PASSWORD = "Admin@123"


def _login(phone: str, password: str) -> str:
    response = client.post("/auth/login", json={"phone_number": phone, "password": password})
    assert response.status_code == 200
    return response.json()["access_token"]


def test_staff_user_cannot_create_bottle():
    token = _login(STAFF_PHONE, STAFF_PASSWORD)
    response = client.post("/bottles", json={}, headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 403


def test_admin_can_generate_bottle_with_two_unique_qr_codes():
    token = _login(ADMIN_PHONE, ADMIN_PASSWORD)
    headers = {"Authorization": f"Bearer {token}"}

    response = client.post("/bottles", json={"brand_name": "Test Brand"}, headers=headers)
    assert response.status_code == 201
    body = response.json()
    assert body["refund_qr_code"].startswith("TSM-R-")
    assert body["manufacturing_qr_code"].startswith("TSM-M-")
    assert body["refund_qr_code"] != body["manufacturing_qr_code"]
    assert body["status"] == "issued"
    assert body["brand_name"] == "Test Brand"


def test_admin_can_list_bottles():
    token = _login(ADMIN_PHONE, ADMIN_PASSWORD)
    headers = {"Authorization": f"Bearer {token}"}

    client.post("/bottles", json={}, headers=headers)
    response = client.get("/bottles", headers=headers)
    assert response.status_code == 200
    assert len(response.json()) >= 1


def test_bottle_qr_image_endpoints_return_png():
    token = _login(ADMIN_PHONE, ADMIN_PASSWORD)
    headers = {"Authorization": f"Bearer {token}"}

    create_response = client.post("/bottles", json={}, headers=headers)
    bottle_id = create_response.json()["id"]

    for suffix in ["refund", "manufacturing"]:
        qr_response = client.get(f"/bottles/{bottle_id}/qr/{suffix}", headers=headers)
        assert qr_response.status_code == 200
        assert qr_response.headers["content-type"] == "image/png"
        assert len(qr_response.content) > 0


def test_admin_can_bulk_generate_bottles():
    token = _login(ADMIN_PHONE, ADMIN_PASSWORD)
    headers = {"Authorization": f"Bearer {token}"}

    response = client.post("/bottles/bulk", json={"count": 5, "brand_name": "Bulk Brand"}, headers=headers)
    assert response.status_code == 201
    bottles = response.json()
    assert len(bottles) == 5

    refund_codes = [b["refund_qr_code"] for b in bottles]
    mfg_codes = [b["manufacturing_qr_code"] for b in bottles]
    assert len(set(refund_codes)) == 5
    assert len(set(mfg_codes)) == 5
    assert set(refund_codes).isdisjoint(set(mfg_codes))


def test_bulk_generate_rejects_zero_or_too_large_count():
    token = _login(ADMIN_PHONE, ADMIN_PASSWORD)
    headers = {"Authorization": f"Bearer {token}"}

    assert client.post("/bottles/bulk", json={"count": 0}, headers=headers).status_code == 422
    assert client.post("/bottles/bulk", json={"count": 501}, headers=headers).status_code == 422


def test_staff_cannot_bulk_generate_bottles():
    token = _login(STAFF_PHONE, STAFF_PASSWORD)
    response = client.post("/bottles/bulk", json={"count": 2}, headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 403


def test_labels_pdf_for_specific_ids():
    token = _login(ADMIN_PHONE, ADMIN_PASSWORD)
    headers = {"Authorization": f"Bearer {token}"}

    create_response = client.post("/bottles/bulk", json={"count": 3}, headers=headers)
    ids = [str(b["id"]) for b in create_response.json()]

    pdf_response = client.get(f"/bottles/labels-pdf?ids={','.join(ids)}", headers=headers)
    assert pdf_response.status_code == 200
    assert pdf_response.headers["content-type"] == "application/pdf"
    assert len(pdf_response.content) > 0


def test_labels_pdf_unknown_ids_returns_404():
    token = _login(ADMIN_PHONE, ADMIN_PASSWORD)
    headers = {"Authorization": f"Bearer {token}"}

    response = client.get("/bottles/labels-pdf?ids=99999999", headers=headers)
    assert response.status_code == 404
