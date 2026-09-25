# Data Architecture — Phase 4

High-level entity flow for the TASMAC Empty Bottle Return & Refund System.
This is a design reference only — no tables have been created yet. Tables
will be implemented incrementally starting in Phase 5 (Database design).

## Entity flow

```
Users
  |
  v
Shops
  |
  v
Bottles
  |
  v
Return Transactions
  |
  v
Payments
  |
  v
Audit Logs
```

## Entity notes

- **Users** — authorized TASMAC staff (and later, admins). Source of truth
  for authentication and role-based access control (Phase 6/7).
- **Shops** — TASMAC outlets. Each user is tied to one or more shops for
  geofence verification (Phase 9).
- **Bottles** — empty bottles identified via QR code (Phase 10/11).
- **Return Transactions** — a record of a bottle being verified and
  returned by a staff member at a shop.
- **Payments** — the ₹10 refund issued against a return transaction
  (Phase 12/13).
- **Audit Logs** — immutable trail of who did what and when, across all
  the above entities (Phase 14).

## Database connection

- Database name: `tasmac_bottle_return`
- Managed via SQLAlchemy 2.x (`backend/app/db/`) and Alembic
  (`backend/alembic/`)
- Connection string is read from `backend/.env` (`DATABASE_URL`), never
  committed to git — see `backend/.env.example` for the expected format
