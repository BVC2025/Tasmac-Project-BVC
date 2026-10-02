from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

STAFF_USER_ID = "Staff001"
STAFF_PASSWORD = "Staff@123"
ADMIN_USER_ID = "Admin"
ADMIN_PASSWORD = "Admin@123"

# Matches the seeded "TASMAC Outlet - Test" shop location
SHOP_LAT = 11.040952791653277
SHOP_LNG = 77.03880915156792

# Roughly 5.5km away from the shop — well outside the 100m geofence
FAR_LAT = 11.040952791653277
FAR_LNG = 77.0888091515679


def _login(phone: str, password: str) -> str:
    response = client.post("/auth/login", json={"user_id": phone, "password": password})
    assert response.status_code == 200
    return response.json()["access_token"]


def test_staff_within_geofence():
    token = _login(STAFF_USER_ID, STAFF_PASSWORD)
    response = client.post(
        "/location/verify",
        json={"latitude": SHOP_LAT, "longitude": SHOP_LNG},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["within_range"] is True
    assert body["distance_meters"] < 100


def test_staff_outside_geofence():
    token = _login(STAFF_USER_ID, STAFF_PASSWORD)
    response = client.post(
        "/location/verify",
        json={"latitude": FAR_LAT, "longitude": FAR_LNG},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["within_range"] is False
    assert body["distance_meters"] > 100


def test_admin_without_shop_gets_400():
    token = _login(ADMIN_USER_ID, ADMIN_PASSWORD)
    response = client.post(
        "/location/verify",
        json={"latitude": SHOP_LAT, "longitude": SHOP_LNG},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 400


def test_verify_location_requires_auth():
    response = client.post("/location/verify", json={"latitude": SHOP_LAT, "longitude": SHOP_LNG})
    assert response.status_code in (401, 403)
