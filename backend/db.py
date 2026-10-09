"""Database connection pool shared by all API routes."""

import os
from pathlib import Path

from dotenv import load_dotenv
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

load_dotenv(Path(__file__).resolve().parent.parent / ".env")

DATABASE_URL = os.getenv("DATABASE_URL")
if not DATABASE_URL:
    raise RuntimeError("DATABASE_URL is not set - copy .env.example to .env first.")

# Rows come back as dicts so routes can return them as JSON directly.
pool = ConnectionPool(
    DATABASE_URL,
    min_size=1,
    max_size=10,
    kwargs={"row_factory": dict_row},
    open=True,
)

COLOR_NAMES = {0: "Yellow", 1: "Green", 2: "Blue", 3: "Purple"}
