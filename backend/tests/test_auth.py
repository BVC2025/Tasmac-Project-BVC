from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

TEST_PHONE = "9999999999"
TEST_PASSWORD = "Staff@123"


def test_login_success():
    response = client.post("/auth/login", json={"phone_number": TEST_PHONE, "password": TEST_PASSWORD})
    assert response.status_code == 200
    body = response.json()
    assert body["token_type"] == "bearer"
    assert body["access_token"]


def test_login_wrong_password():
    response = client.post("/auth/login", json={"phone_number": TEST_PHONE, "password": "wrong-password"})
    assert response.status_code == 401


def test_me_endpoint_with_valid_token():
    login_response = client.post("/auth/login", json={"phone_number": TEST_PHONE, "password": TEST_PASSWORD})
    token = login_response.json()["access_token"]

    response = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    assert response.json()["phone_number"] == TEST_PHONE


def test_me_endpoint_without_token():
    response = client.get("/auth/me")
    assert response.status_code in (401, 403)
