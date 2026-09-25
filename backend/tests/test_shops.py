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


def test_staff_user_cannot_list_shops():
    token = _login(STAFF_PHONE, STAFF_PASSWORD)
    response = client.get("/shops", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 403


def test_admin_can_create_list_and_deactivate_shop():
    token = _login(ADMIN_PHONE, ADMIN_PASSWORD)
    headers = {"Authorization": f"Bearer {token}"}

    create_response = client.post(
        "/shops",
        json={
            "name": "TASMAC Outlet - Test",
            "shop_code": "TST-001",
            "address": "Test Address",
            "latitude": 13.0827,
            "longitude": 80.2707,
        },
        headers=headers,
    )
    assert create_response.status_code == 201
    shop_id = create_response.json()["id"]
    assert create_response.json()["is_active"] is True

    list_response = client.get("/shops", headers=headers)
    assert list_response.status_code == 200
    assert any(s["id"] == shop_id for s in list_response.json())

    deactivate_response = client.delete(f"/shops/{shop_id}", headers=headers)
    assert deactivate_response.status_code == 200
    assert deactivate_response.json()["is_active"] is False


def test_create_shop_with_duplicate_code_fails():
    token = _login(ADMIN_PHONE, ADMIN_PASSWORD)
    headers = {"Authorization": f"Bearer {token}"}

    client.post(
        "/shops",
        json={"name": "Dup Shop 1", "shop_code": "DUP-001"},
        headers=headers,
    )
    response = client.post(
        "/shops",
        json={"name": "Dup Shop 2", "shop_code": "DUP-001"},
        headers=headers,
    )
    assert response.status_code == 409
