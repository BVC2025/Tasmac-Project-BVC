from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

STAFF_PHONE = "9999999999"
STAFF_USER_ID = "Staff001"
STAFF_PASSWORD = "Staff@123"
ADMIN_PHONE = "8888888888"
ADMIN_USER_ID = "Admin"
ADMIN_PASSWORD = "Admin@123"


def _login(phone: str, password: str) -> str:
    response = client.post("/auth/login", json={"user_id": phone, "password": password})
    assert response.status_code == 200
    return response.json()["access_token"]


def test_staff_user_cannot_list_staff():
    token = _login(STAFF_USER_ID, STAFF_PASSWORD)
    response = client.get("/staff", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 403


def test_admin_can_list_staff():
    token = _login(ADMIN_USER_ID, ADMIN_PASSWORD)
    response = client.get("/staff", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    assert isinstance(response.json(), list)
    assert len(response.json()) >= 2


def test_admin_can_create_and_deactivate_staff():
    token = _login(ADMIN_USER_ID, ADMIN_PASSWORD)
    headers = {"Authorization": f"Bearer {token}"}

    create_response = client.post(
        "/staff",
        json={
            "full_name": "Temp Staff",
            "user_id": "7777777777",
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


def test_admin_can_reset_staff_password():
    admin_token = _login(ADMIN_USER_ID, ADMIN_PASSWORD)
    headers = {"Authorization": f"Bearer {admin_token}"}

    create_response = client.post(
        "/staff",
        json={
            "full_name": "Reset Target",
            "user_id": "7000000001",
            "phone_number": "7000000001",
            "password": "Original@123",
            "role": "staff",
        },
        headers=headers,
    )
    assert create_response.status_code == 201
    staff_id = create_response.json()["id"]

    reset_response = client.post(
        f"/staff/{staff_id}/reset-password",
        json={"new_password": "NewPass@123"},
        headers=headers,
    )
    assert reset_response.status_code == 200

    assert _login("7000000001", "NewPass@123")

    old_login = client.post(
        "/auth/login", json={"user_id": "7000000001", "password": "Original@123"}
    )
    assert old_login.status_code == 401


def test_staff_user_cannot_reset_password():
    staff_token = _login(STAFF_USER_ID, STAFF_PASSWORD)
    response = client.post(
        "/staff/1/reset-password",
        json={"new_password": "Whatever@123"},
        headers={"Authorization": f"Bearer {staff_token}"},
    )
    assert response.status_code == 403


def test_create_staff_with_duplicate_phone_fails():
    token = _login(ADMIN_USER_ID, ADMIN_PASSWORD)
    response = client.post(
        "/staff",
        json={
            "full_name": "Duplicate",
            "user_id": "dup-user-001",
            "phone_number": STAFF_PHONE,
            "password": "Whatever@123",
            "role": "staff",
        },
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 409


def test_create_staff_with_duplicate_user_id_fails():
    token = _login(ADMIN_USER_ID, ADMIN_PASSWORD)
    response = client.post(
        "/staff",
        json={
            "full_name": "Duplicate User ID",
            "user_id": STAFF_USER_ID,
            "phone_number": "7222222222",
            "password": "Whatever@123",
            "role": "staff",
        },
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 409


def test_staff_photo_upload_and_fetch():
    admin_token = _login(ADMIN_USER_ID, ADMIN_PASSWORD)
    admin_headers = {"Authorization": f"Bearer {admin_token}"}

    create_response = client.post(
        "/staff",
        json={
            "full_name": "Photo Target",
            "user_id": "7333333333",
            "phone_number": "7333333333",
            "password": "Photo@123",
            "role": "staff",
        },
        headers=admin_headers,
    )
    assert create_response.status_code == 201
    staff_id = create_response.json()["id"]
    assert create_response.json()["has_photo"] is False

    upload_response = client.post(
        f"/staff/{staff_id}/photo",
        files={"photo": ("face.jpg", b"fake-jpeg-bytes", "image/jpeg")},
        headers=admin_headers,
    )
    assert upload_response.status_code == 200
    assert upload_response.json()["has_photo"] is True

    staff_token = _login("7333333333", "Photo@123")
    self_fetch = client.get(f"/staff/{staff_id}/photo", headers={"Authorization": f"Bearer {staff_token}"})
    assert self_fetch.status_code == 200
    assert self_fetch.content == b"fake-jpeg-bytes"

    admin_fetch = client.get(f"/staff/{staff_id}/photo", headers=admin_headers)
    assert admin_fetch.status_code == 200

    other_staff_token = _login(STAFF_USER_ID, STAFF_PASSWORD)
    other_fetch = client.get(f"/staff/{staff_id}/photo", headers={"Authorization": f"Bearer {other_staff_token}"})
    assert other_fetch.status_code == 403
