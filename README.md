# TASMAC Empty Bottle Return & Refund System

## Project Purpose

A secure mobile application for authorized TASMAC staff to verify returned
empty liquor bottles and process a ₹10 refund to the customer. The system
aims to bring a transparent, auditable digital workflow to the empty bottle
return process at TASMAC outlets.

## Technology Stack

| Layer            | Technology                          |
|-------------------|--------------------------------------|
| Mobile App        | Flutter + Dart                       |
| Backend API       | Python + FastAPI                     |
| Database          | PostgreSQL                           |
| Admin Web Panel   | React.js (implemented in a later phase) |
| Version Control   | Git                                   |
| Containerization  | Docker (implemented in a later phase) |

## High-Level Future Modules

- Authentication & Role-Based Access Control (staff, admin)
- Shop / outlet management
- GPS-based geofencing (100m radius verification)
- Bottle QR code generation & verification
- Customer UPI / payment integration
- ₹10 refund transaction processing
- Audit logging
- Admin reporting dashboard (React)

## Development Phases

0. Project folder structure
1. Git + README + .gitignore
2. Flutter mobile app setup
3. FastAPI backend setup
4. PostgreSQL + SQLAlchemy + Alembic setup
5. Database schema design
6. Authentication
7. Authorized staff + RBAC
8. Shop management
9. GPS + 100m geofence verification
10. Bottle QR generation/design
11. Bottle QR verification
12. Customer UPI/payment integration
13. ₹10 refund transaction
14. Audit logs
15. Admin React panel
16. Testing + security
17. Docker
18. Production server deployment

## Repository Structure

```
tasmac-bottle-return/
│
├── mobile/     # Flutter mobile application
├── backend/    # FastAPI backend service
├── admin/      # React admin web panel (later phase)
├── docs/       # Project documentation
└── README.md
```

## Status

Phase 0/1 — project scaffolding only. No business logic, APIs, or screens
have been implemented yet.
