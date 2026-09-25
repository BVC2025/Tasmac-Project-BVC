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


def test_staff_user_cannot_list_staff():
    token = _login(STAFF_PHONE, STAFF_PASSWORD)
    response = client.get("/staff", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 403


def test_admin_can_list_staff():
    token = _login(ADMIN_PHONE, ADMIN_PASSWORD)
    response = client.get("/staff", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    assert isinstance(response.json(), list)
    assert len(response.json()) >= 2


def test_admin_can_create_and_deactivate_staff():
    token = _login(ADMIN_PHONE, ADMIN_PASSWORD)
    headers = {"Authorization": f"Bearer {token}"}

    create_response = client.post(
        "/staff",
        json={
            "full_name": "Temp Staff",
            "phone_number": "7777777777",
            "password": "Temp@123",
            "role": "staff",
        },
        headers=headers,
    )
    assert create_response.status_code == 201
    new_id = create_response.json()["id"]
    assert create_response.json()["is_active"] is True

    deactivate_response = client.delete(f"/staff/{new_id}", headers=headers)
    assert deactivate_response.status_code == 200
    assert deactivate_response.json()["is_active"] is False


def test_create_staff_with_duplicate_phone_fails():
    token = _login(ADMIN_PHONE, ADMIN_PASSWORD)
    response = client.post(
        "/staff",
        json={
            "full_name": "Duplicate",
            "phone_number": STAFF_PHONE,
            "password": "Whatever@123",
            "role": "staff",
        },
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 409
