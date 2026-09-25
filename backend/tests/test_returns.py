from datetime import datetime, timedelta

from fastapi.testclient import TestClient

import app.api.routes.returns as returns_module
from app.main import app

client = TestClient(app)

STAFF_PHONE = "9999999999"
STAFF_PASSWORD = "Staff@123"
ADMIN_PHONE = "8888888888"
ADMIN_PASSWORD = "Admin@123"

# Matches the seeded "TASMAC Outlet - Test" shop location
SHOP_LAT = 11.040952791653277
SHOP_LNG = 77.03880915156792
FAR_LAT = 11.040952791653277
FAR_LNG = 77.0888091515679


def _login(phone: str, password: str) -> str:
    response = client.post("/auth/login", json={"phone_number": phone, "password": password})
    assert response.status_code == 200
    return response.json()["access_token"]


def _generate_bottle(admin_token: str) -> tuple[str, str]:
    response = client.post("/bottles", json={}, headers={"Authorization": f"Bearer {admin_token}"})
    assert response.status_code == 201
    body = response.json()
    return body["refund_qr_code"], body["manufacturing_qr_code"]


def _seeded_shop_id(admin_token: str) -> int:
    response = client.get("/shops", headers={"Authorization": f"Bearer {admin_token}"})
    for shop in response.json():
        if shop["shop_code"] == "SEED-001":
            return shop["id"]
    raise AssertionError("Seeded shop SEED-001 not found")


def _force_payment_result(monkeypatch, success: bool):
    monkeypatch.setattr(returns_module, "_simulate_payment", lambda: (success, "SIM-TEST"))


def test_verify_refund_qr_success():
    admin_token = _login(ADMIN_PHONE, ADMIN_PASSWORD)
    staff_token = _login(STAFF_PHONE, STAFF_PASSWORD)
    refund_qr, _ = _generate_bottle(admin_token)

    response = client.post(
        "/returns/verify-refund-qr",
        json={"refund_qr_code": refund_qr, "latitude": SHOP_LAT, "longitude": SHOP_LNG},
        headers={"Authorization": f"Bearer {staff_token}"},
    )
    assert response.status_code == 200
    assert response.json()["valid"] is True


def test_verify_refund_qr_unknown_code_404():
    staff_token = _login(STAFF_PHONE, STAFF_PASSWORD)
    response = client.post(
        "/returns/verify-refund-qr",
        json={"refund_qr_code": "TSM-R-doesnotexist", "latitude": SHOP_LAT, "longitude": SHOP_LNG},
        headers={"Authorization": f"Bearer {staff_token}"},
    )
    assert response.status_code == 404


def test_verify_refund_qr_outside_geofence_403():
    admin_token = _login(ADMIN_PHONE, ADMIN_PASSWORD)
    staff_token = _login(STAFF_PHONE, STAFF_PASSWORD)
    refund_qr, _ = _generate_bottle(admin_token)

    response = client.post(
        "/returns/verify-refund-qr",
        json={"refund_qr_code": refund_qr, "latitude": FAR_LAT, "longitude": FAR_LNG},
        headers={"Authorization": f"Bearer {staff_token}"},
    )
    assert response.status_code == 403


def test_verify_manufacturing_qr_success():
    admin_token = _login(ADMIN_PHONE, ADMIN_PASSWORD)
    staff_token = _login(STAFF_PHONE, STAFF_PASSWORD)
    refund_qr, mfg_qr = _generate_bottle(admin_token)

    response = client.post(
        "/returns/verify-manufacturing-qr",
        json={"refund_qr_code": refund_qr, "manufacturing_qr_code": mfg_qr},
        headers={"Authorization": f"Bearer {staff_token}"},
    )
    assert response.status_code == 200
    assert response.json()["valid"] is True


def test_verify_manufacturing_qr_mismatch():
    admin_token = _login(ADMIN_PHONE, ADMIN_PASSWORD)
    staff_token = _login(STAFF_PHONE, STAFF_PASSWORD)
    refund_qr, _ = _generate_bottle(admin_token)
    _, other_mfg_qr = _generate_bottle(admin_token)

    response = client.post(
        "/returns/verify-manufacturing-qr",
        json={"refund_qr_code": refund_qr, "manufacturing_qr_code": other_mfg_qr},
        headers={"Authorization": f"Bearer {staff_token}"},
    )
    assert response.status_code == 400


def test_complete_return_success(monkeypatch):
    _force_payment_result(monkeypatch, True)
    admin_token = _login(ADMIN_PHONE, ADMIN_PASSWORD)
    staff_token = _login(STAFF_PHONE, STAFF_PASSWORD)
    refund_qr, mfg_qr = _generate_bottle(admin_token)

    response = client.post(
        "/returns/complete",
        json={
            "refund_qr_code": refund_qr,
            "manufacturing_qr_code": mfg_qr,
            "latitude": SHOP_LAT,
            "longitude": SHOP_LNG,
            "payment_method": "upi",
            "customer_identifier": "customer@upi",
        },
        headers={"Authorization": f"Bearer {staff_token}"},
    )
    assert response.status_code == 201
    body = response.json()
    assert body["status"] == "verified"
    assert body["payment_status"] == "success"
    assert body["amount"] == 10.0

    bottle_response = client.get(
        f"/bottles/{body['bottle_id']}", headers={"Authorization": f"Bearer {admin_token}"}
    )
    assert bottle_response.json()["status"] == "returned"


def test_complete_return_payment_failure_does_not_mark_bottle_returned(monkeypatch):
    _force_payment_result(monkeypatch, False)
    admin_token = _login(ADMIN_PHONE, ADMIN_PASSWORD)
    staff_token = _login(STAFF_PHONE, STAFF_PASSWORD)
    refund_qr, mfg_qr = _generate_bottle(admin_token)

    response = client.post(
        "/returns/complete",
        json={
            "refund_qr_code": refund_qr,
            "manufacturing_qr_code": mfg_qr,
            "latitude": SHOP_LAT,
            "longitude": SHOP_LNG,
            "payment_method": "phone",
            "customer_identifier": "9876543210",
        },
        headers={"Authorization": f"Bearer {staff_token}"},
    )
    assert response.status_code == 402

    bottle_response = client.get("/bottles", headers={"Authorization": f"Bearer {admin_token}"})
    bottle = next(b for b in bottle_response.json() if b["refund_qr_code"] == refund_qr)
    assert bottle["status"] == "issued"


def test_complete_return_twice_fails_with_conflict(monkeypatch):
    _force_payment_result(monkeypatch, True)
    admin_token = _login(ADMIN_PHONE, ADMIN_PASSWORD)
    staff_token = _login(STAFF_PHONE, STAFF_PASSWORD)
    refund_qr, mfg_qr = _generate_bottle(admin_token)
    headers = {"Authorization": f"Bearer {staff_token}"}
    payload = {
        "refund_qr_code": refund_qr,
        "manufacturing_qr_code": mfg_qr,
        "latitude": SHOP_LAT,
        "longitude": SHOP_LNG,
        "payment_method": "upi",
        "customer_identifier": "customer@upi",
    }

    first = client.post("/returns/complete", json=payload, headers=headers)
    assert first.status_code == 201

    second = client.post("/returns/complete", json=payload, headers=headers)
    assert second.status_code == 409


def test_reject_return_with_reason_and_remarks():
    admin_token = _login(ADMIN_PHONE, ADMIN_PASSWORD)
    staff_token = _login(STAFF_PHONE, STAFF_PASSWORD)
    refund_qr, _ = _generate_bottle(admin_token)

    response = client.post(
        "/returns/reject",
        data={
            "reason": "bottle_broken_cracked",
            "refund_qr_code": refund_qr,
            "remarks": "Neck of the bottle was cracked",
            "latitude": str(SHOP_LAT),
            "longitude": str(SHOP_LNG),
        },
        headers={"Authorization": f"Bearer {staff_token}"},
    )
    assert response.status_code == 201
    body = response.json()
    assert body["status"] == "rejected"
    assert body["reason"] == "bottle_broken_cracked"


def test_reject_return_without_known_bottle():
    staff_token = _login(STAFF_PHONE, STAFF_PASSWORD)
    response = client.post(
        "/returns/reject",
        data={"reason": "refund_qr_invalid"},
        headers={"Authorization": f"Bearer {staff_token}"},
    )
    assert response.status_code == 201
    assert response.json()["reason"] == "refund_qr_invalid"


def test_reject_return_with_evidence_image():
    staff_token = _login(STAFF_PHONE, STAFF_PASSWORD)
    fake_image = (b"\x89PNG\r\n\x1a\n" + b"0" * 100)

    response = client.post(
        "/returns/reject",
        data={"reason": "bottle_tampered"},
        files={"evidence_image": ("evidence.png", fake_image, "image/png")},
        headers={"Authorization": f"Bearer {staff_token}"},
    )
    assert response.status_code == 201


def test_staff_can_list_own_returns(monkeypatch):
    _force_payment_result(monkeypatch, True)
    admin_token = _login(ADMIN_PHONE, ADMIN_PASSWORD)
    staff_token = _login(STAFF_PHONE, STAFF_PASSWORD)
    refund_qr, mfg_qr = _generate_bottle(admin_token)

    client.post(
        "/returns/complete",
        json={
            "refund_qr_code": refund_qr,
            "manufacturing_qr_code": mfg_qr,
            "latitude": SHOP_LAT,
            "longitude": SHOP_LNG,
            "payment_method": "upi",
            "customer_identifier": "customer@upi",
        },
        headers={"Authorization": f"Bearer {staff_token}"},
    )

    response = client.get("/returns/mine", headers={"Authorization": f"Bearer {staff_token}"})
    assert response.status_code == 200
    assert any(t["qr_code"] == refund_qr for t in response.json())


def test_staff_cannot_list_all_returns():
    staff_token = _login(STAFF_PHONE, STAFF_PASSWORD)
    response = client.get("/returns", headers={"Authorization": f"Bearer {staff_token}"})
    assert response.status_code == 403


def test_admin_can_list_all_returns():
    admin_token = _login(ADMIN_PHONE, ADMIN_PASSWORD)
    response = client.get("/returns", headers={"Authorization": f"Bearer {admin_token}"})
    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_service_time_window_blocks_outside_current_hour():
    admin_token = _login(ADMIN_PHONE, ADMIN_PASSWORD)
    staff_token = _login(STAFF_PHONE, STAFF_PASSWORD)
    admin_headers = {"Authorization": f"Bearer {admin_token}"}
    shop_id = _seeded_shop_id(admin_token)

    future_start = (datetime.now() + timedelta(hours=2)).strftime("%H:%M:%S")
    future_end = (datetime.now() + timedelta(hours=3)).strftime("%H:%M:%S")

    try:
        client.patch(
            f"/shops/{shop_id}",
            json={"service_start_time": future_start, "service_end_time": future_end},
            headers=admin_headers,
        )

        refund_qr, _ = _generate_bottle(admin_token)
        response = client.post(
            "/returns/verify-refund-qr",
            json={"refund_qr_code": refund_qr, "latitude": SHOP_LAT, "longitude": SHOP_LNG},
            headers={"Authorization": f"Bearer {staff_token}"},
        )
        assert response.status_code == 403
        assert "Service available only between" in response.json()["detail"]
    finally:
        client.patch(
            f"/shops/{shop_id}",
            json={"service_start_time": None, "service_end_time": None},
            headers=admin_headers,
        )
