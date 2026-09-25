# TASMAC Bottle Return — Backend

FastAPI backend for the TASMAC Empty Bottle Return & Refund System.

## Stack

- Python 3.12+
- FastAPI
- Uvicorn
- SQLAlchemy 2.x
- Alembic
- Pydantic / pydantic-settings

## Structure

```
backend/
├── app/
│   ├── main.py       # FastAPI app entrypoint, /health endpoint
│   ├── core/          # settings/config
│   ├── db/             # SQLAlchemy engine, session, declarative base
│   ├── models/         # (empty for now — ORM models added in a later phase)
│   ├── schemas/        # (empty for now — Pydantic schemas added in a later phase)
│   ├── api/             # (empty for now — routers added in a later phase)
│   └── services/        # (empty for now — business logic added in a later phase)
├── alembic/             # migration environment
├── tests/
├── requirements.txt
├── alembic.ini
└── .env.example
```

## Setup

```bash
cd backend
python -m venv .venv

# Windows
.venv\Scripts\activate

pip install -r requirements.txt
copy .env.example .env
```

## Run

```bash
uvicorn app.main:app --reload
```

Then open http://127.0.0.1:8000/health

## Test

```bash
pytest
```
