"""Provisions bottle QR codes directly in the database.

Bottle generation is deliberately NOT exposed over the API — neither staff
nor admin can mint a "valid" bottle from inside the app. New bottles are
provisioned out-of-band, by whoever controls the manufacturing/labelling
process, running this script with direct database access.

Run with: python -m scripts.generate_bottles --count 50 --brand "TASMAC"
"""

import argparse

from app.db.session import SessionLocal
from app.services.bottle_provisioning import new_bottle


def run(count: int, brand_name: str | None) -> None:
    db = SessionLocal()
    try:
        bottles = []
        for _ in range(count):
            bottle = new_bottle(db, brand_name)
            db.add(bottle)
            db.flush()  # makes this bottle's codes visible to the next uniqueness check
            bottles.append(bottle)
        db.commit()

        for bottle in bottles:
            db.refresh(bottle)
            print(f"id={bottle.id} refund={bottle.refund_qr_code} manufacturing={bottle.manufacturing_qr_code}")
        print(f"\nGenerated {len(bottles)} bottle(s).")
    finally:
        db.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--count", type=int, default=1, help="Number of bottles to generate")
    parser.add_argument("--brand", type=str, default=None, help="Optional brand name to tag the bottles with")
    args = parser.parse_args()

    run(args.count, args.brand)
