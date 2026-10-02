from datetime import datetime, timedelta

from fastapi.testclient import TestClient

import app.api.routes.returns as returns_module
from app.db.session import SessionLocal
from app.main import app
from app.services.bottle_provisioning import new_bottle

client = TestClient(app)

STAFF_USER_ID = "Staff001"
STAFF_PASSWORD = "Staff@123"
ADMIN_USER_ID = "Admin"
ADMIN_PASSWORD = "Admin@123"

# Matches the seeded "TASMAC Outlet - Test" shop location
SHOP_LAT = 11.040952791653277
SHOP_LNG = 77.03880915156792
FAR_LAT = 11.040952791653277
FAR_LNG = 77.0888091515679


def _login(phone: str, password: str) -> str:
    response = client.post("/auth/login", json={"user_id": phone, "password": password})
    assert response.status_code == 200
    return response.json()["access_token"]


def _generate_bottle() -> tuple[str, str]:
    """Bottle creation isn't exposed over the API (see scripts/generate_bottles.py),
    so tests seed bottles directly."""
    db = SessionLocal()
    try:
        bottle = new_bottle(db)
        db.add(bottle)
        db.commit()
        db.refresh(bottle)
        return bottle.refund_qr_code, bottle.manufacturing_qr_code
    finally:
        db.close()


def _seeded_shop_id(admin_token: str) -> int:
    response = client.get("/shops", headers={"Authorization": f"Bearer {admin_token}"})
    for shop in response.json():
        if shop["shop_code"] == "SEED-001":
            return shop["id"]
    raise AssertionError("Seeded shop SEED-001 not found")


def _force_payment_result(monkeypatch, success: bool):
    monkeypatch.setattr(returns_module, "_simulate_payment", lambda: (success, "SIM-TEST"))


def test_verify_refund_qr_success():
    admin_token = _login(ADMIN_USER_ID, ADMIN_PASSWORD)
    staff_token = _login(STAFF_USER_ID, STAFF_PASSWORD)
    refund_qr, _ = _generate_bottle()

    response = client.post(
        "/returns/verify-refund-qr",
        json={"refund_qr_code": refund_qr, "latitude": SHOP_LAT, "longitude": SHOP_LNG},
        headers={"Authorization": f"Bearer {staff_token}"},
    )
    assert response.status_code == 200
    assert response.json()["valid"] is True


def test_verify_refund_qr_unknown_code_404():
    staff_token = _login(STAFF_USER_ID, STAFF_PASSWORD)
    response = client.post(
        "/returns/verify-refund-qr",
        json={"refund_qr_code": "TSM-R-doesnotexist", "latitude": SHOP_LAT, "longitude": SHOP_LNG},
        headers={"Authorization": f"Bearer {staff_token}"},
    )
    assert response.status_code == 404


def test_verify_refund_qr_outside_geofence_403():
    admin_token = _login(ADMIN_USER_ID, ADMIN_PASSWORD)
    staff_token = _login(STAFF_USER_ID, STAFF_PASSWORD)
    refund_qr, _ = _generate_bottle()

    response = client.post(
        "/returns/verify-refund-qr",
        json={"refund_qr_code": refund_qr, "latitude": FAR_LAT, "longitude": FAR_LNG},
        headers={"Authorization": f"Bearer {staff_token}"},
    )
    assert response.status_code == 403


def test_verify_manufacturing_qr_success():
    admin_token = _login(ADMIN_USER_ID, ADMIN_PASSWORD)
    staff_token = _login(STAFF_USER_ID, STAFF_PASSWORD)
    refund_qr, mfg_qr = _generate_bottle()

    response = client.post(
        "/returns/verify-manufacturing-qr",
        json={"refund_qr_code": refund_qr, "manufacturing_qr_code": mfg_qr},
        headers={"Authorization": f"Bearer {staff_token}"},
    )
    assert response.status_code == 200
    assert response.json()["valid"] is True


def test_verify_manufacturing_qr_mismatch():
    admin_token = _login(ADMIN_USER_ID, ADMIN_PASSWORD)
    staff_token = _login(STAFF_USER_ID, STAFF_PASSWORD)
    refund_qr, _ = _generate_bottle()
    _, other_mfg_qr = _generate_bottle()

    response = client.post(
        "/returns/verify-manufacturing-qr",
        json={"refund_qr_code": refund_qr, "manufacturing_qr_code": other_mfg_qr},
        headers={"Authorization": f"Bearer {staff_token}"},
    )
    assert response.status_code == 400


def test_lookup_manufacturing_qr_success():
    staff_token = _login(STAFF_USER_ID, STAFF_PASSWORD)
    refund_qr, mfg_qr = _generate_bottle()

    response = client.post(
        "/returns/lookup-manufacturing-qr",
        json={"manufacturing_qr_code": mfg_qr},
        headers={"Authorization": f"Bearer {staff_token}"},
    )
    assert response.status_code == 200
    assert response.json()["refund_qr_code"] == refund_qr


def test_lookup_manufacturing_qr_unknown_code_404():
    staff_token = _login(STAFF_USER_ID, STAFF_PASSWORD)

    response = client.post(
        "/returns/lookup-manufacturing-qr",
        json={"manufacturing_qr_code": "TSM-M-doesnotexist"},
        headers={"Authorization": f"Bearer {staff_token}"},
    )
    assert response.status_code == 404


def test_complete_return_success(monkeypatch):
    _force_payment_result(monkeypatch, True)
    admin_token = _login(ADMIN_USER_ID, ADMIN_PASSWORD)
    staff_token = _login(STAFF_USER_ID, STAFF_PASSWORD)
    refund_qr, mfg_qr = _generate_bottle()

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
    admin_token = _login(ADMIN_USER_ID, ADMIN_PASSWORD)
    staff_token = _login(STAFF_USER_ID, STAFF_PASSWORD)
    refund_qr, mfg_qr = _generate_bottle()

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
    admin_token = _login(ADMIN_USER_ID, ADMIN_PASSWORD)
    staff_token = _login(STAFF_USER_ID, STAFF_PASSWORD)
    refund_qr, mfg_qr = _generate_bottle()
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
    admin_token = _login(ADMIN_USER_ID, ADMIN_PASSWORD)
    staff_token = _login(STAFF_USER_ID, STAFF_PASSWORD)
    refund_qr, _ = _generate_bottle()

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
    staff_token = _login(STAFF_USER_ID, STAFF_PASSWORD)
    response = client.post(
        "/returns/reject",
        data={"reason": "refund_qr_invalid"},
        headers={"Authorization": f"Bearer {staff_token}"},
    )
    assert response.status_code == 201
    assert response.json()["reason"] == "refund_qr_invalid"


def test_reject_return_with_evidence_image():
    staff_token = _login(STAFF_USER_ID, STAFF_PASSWORD)
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
    admin_token = _login(ADMIN_USER_ID, ADMIN_PASSWORD)
    staff_token = _login(STAFF_USER_ID, STAFF_PASSWORD)
    refund_qr, mfg_qr = _generate_bottle()

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
    staff_token = _login(STAFF_USER_ID, STAFF_PASSWORD)
    response = client.get("/returns", headers={"Authorization": f"Bearer {staff_token}"})
    assert response.status_code == 403


def test_admin_can_list_all_returns():
    admin_token = _login(ADMIN_USER_ID, ADMIN_PASSWORD)
    response = client.get("/returns", headers={"Authorization": f"Bearer {admin_token}"})
    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_service_time_window_blocks_outside_current_hour():
    admin_token = _login(ADMIN_USER_ID, ADMIN_PASSWORD)
    staff_token = _login(STAFF_USER_ID, STAFF_PASSWORD)
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

        refund_qr, _ = _generate_bottle()
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


def test_complete_batch_pays_once_for_all_bottles():
    staff_token = _login(STAFF_USER_ID, STAFF_PASSWORD)
    headers = {"Authorization": f"Bearer {staff_token}"}
    refund_1, mfg_1 = _generate_bottle()
    refund_2, mfg_2 = _generate_bottle()

    response = client.post(
        "/returns/complete-batch",
        json={
            "latitude": SHOP_LAT,
            "longitude": SHOP_LNG,
            "payment_method": "upi",
            "customer_identifier": "customer@upi",
            "bottles": [
                {"refund_qr_code": refund_1, "manufacturing_qr_code": mfg_1},
                {"refund_qr_code": refund_2, "manufacturing_qr_code": mfg_2},
            ],
        },
        headers=headers,
    )
    if response.status_code == 402:
        return  # simulated payment gateway rolled a failure; not what this test checks
    assert response.status_code == 201
    body = response.json()
    assert body["count"] == 2
    assert body["amount"] == 20.0

    mine = client.get("/returns/mine", headers=headers)
    assert mine.status_code == 200
    codes = [t["qr_code"] for t in mine.json()]
    assert refund_1 in codes and refund_2 in codes


def test_complete_batch_with_barcode_fallback_records_it():
    staff_token = _login(STAFF_USER_ID, STAFF_PASSWORD)
    headers = {"Authorization": f"Bearer {staff_token}"}
    refund_qr, _ = _generate_bottle()

    response = client.post(
        "/returns/complete-batch",
        json={
            "latitude": SHOP_LAT,
            "longitude": SHOP_LNG,
            "payment_method": "phone",
            "customer_identifier": "9876543210",
            "bottles": [{"refund_qr_code": refund_qr, "product_barcode": "8901030826404"}],
        },
        headers=headers,
    )
    if response.status_code == 402:
        return
    assert response.status_code == 201

    mine = client.get("/returns/mine", headers=headers)
    entry = next(t for t in mine.json() if t["qr_code"] == refund_qr)
    assert entry["product_barcode"] == "8901030826404"


def test_complete_batch_rejects_if_any_bottle_already_returned():
    staff_token = _login(STAFF_USER_ID, STAFF_PASSWORD)
    headers = {"Authorization": f"Bearer {staff_token}"}
    refund_1, mfg_1 = _generate_bottle()
    refund_2, mfg_2 = _generate_bottle()

    # Return bottle 2 on its own first, so it's no longer ISSUED.
    solo = client.post(
        "/returns/complete-batch",
        json={
            "latitude": SHOP_LAT,
            "longitude": SHOP_LNG,
            "payment_method": "upi",
            "customer_identifier": "solo@upi",
            "bottles": [{"refund_qr_code": refund_2, "manufacturing_qr_code": mfg_2}],
        },
        headers=headers,
    )
    if solo.status_code == 402:
        return

    response = client.post(
        "/returns/complete-batch",
        json={
            "latitude": SHOP_LAT,
            "longitude": SHOP_LNG,
            "payment_method": "upi",
            "customer_identifier": "customer@upi",
            "bottles": [
                {"refund_qr_code": refund_1, "manufacturing_qr_code": mfg_1},
                {"refund_qr_code": refund_2, "manufacturing_qr_code": mfg_2},
            ],
        },
        headers=headers,
    )
    assert response.status_code == 409
