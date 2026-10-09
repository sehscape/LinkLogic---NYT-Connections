"""
Link Logic ETL: load the community NYT Connections archive into PostgreSQL.

Usage:
    python etl/load_data.py

Reads DATABASE_URL from .env. Downloads the archive JSON once and caches it
under data/connections.json; re-running is idempotent (ON CONFLICT DO NOTHING
everywhere), so the script can be used both for the first load and to top up
new puzzles later.
"""

import json
import os
import sys
from pathlib import Path

import psycopg
import requests
from dotenv import load_dotenv

ARCHIVE_URL = (
    "https://raw.githubusercontent.com/Eyefyre/NYT-Connections-Answers"
    "/main/connections.json"
)
PROJECT_ROOT = Path(__file__).resolve().parent.parent
CACHE_FILE = PROJECT_ROOT / "data" / "connections.json"


def fetch_archive() -> list[dict]:
    """Return the archive as a list of puzzle dicts, downloading if needed."""
    if CACHE_FILE.exists():
        print(f"Using cached archive: {CACHE_FILE}")
        return json.loads(CACHE_FILE.read_text(encoding="utf-8"))

    print(f"Downloading archive from {ARCHIVE_URL} ...")
    resp = requests.get(ARCHIVE_URL, timeout=60)
    resp.raise_for_status()
    CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
    CACHE_FILE.write_text(resp.text, encoding="utf-8")
    return resp.json()


def clean(archive: list[dict]) -> list[dict]:
    """Apply data-quality rules to the raw archive.

    1. Difficulty: older entries carry the official level 0-3; from puzzle
       #832 the archive stopped recording it (level = -1 everywhere). The
       answers array is still ordered Yellow -> Purple, so when the four
       levels are not exactly {0,1,2,3} we assign difficulty by position.
    2. Drop malformed puzzles: every puzzle must have 16 distinct non-empty
       words (the 2025-04-01 April Fools puzzle #660 lost its symbol-only
       words entirely and is unrecoverable).
    """
    cleaned = []
    for p in archive:
        answers = [dict(a) for a in p["answers"]]
        if sorted(a["level"] for a in answers) != [0, 1, 2, 3]:
            for position, ans in enumerate(answers):
                ans["level"] = position

        members = [m.strip() for a in answers for m in a["members"]]
        if len(set(members)) != 16 or "" in members:
            print(f"  skipping malformed puzzle #{p['id']} ({p['date']})")
            continue

        cleaned.append({**p, "answers": answers})
    return cleaned


def load(conn: psycopg.Connection, archive: list[dict]) -> None:
    """Insert puzzles, categories, words and the category_words bridge."""
    cur = conn.cursor()

    # 1) Puzzles -------------------------------------------------------------
    cur.executemany(
        """
        INSERT INTO puzzles (nyt_number, puzzle_date)
        VALUES (%s, %s)
        ON CONFLICT (nyt_number) DO NOTHING
        """,
        [(p["id"], p["date"]) for p in archive],
    )
    cur.execute("SELECT nyt_number, puzzle_id FROM puzzles")
    puzzle_ids = dict(cur.fetchall())

    # 2) Canonical vocabulary ------------------------------------------------
    vocab = sorted(
        {
            member.strip()
            for p in archive
            for ans in p["answers"]
            for member in ans["members"]
        }
    )
    cur.executemany(
        "INSERT INTO words (word_text) VALUES (%s) ON CONFLICT DO NOTHING",
        [(w,) for w in vocab],
    )
    cur.execute("SELECT word_text, word_id FROM words")
    word_ids = dict(cur.fetchall())

    # 3) Categories ----------------------------------------------------------
    cur.executemany(
        """
        INSERT INTO categories (puzzle_id, name, difficulty)
        VALUES (%s, %s, %s)
        ON CONFLICT (puzzle_id, difficulty) DO NOTHING
        """,
        [
            (puzzle_ids[p["id"]], ans["group"].strip(), ans["level"])
            for p in archive
            for ans in p["answers"]
        ],
    )
    cur.execute("SELECT puzzle_id, difficulty, category_id FROM categories")
    category_ids = {(pid, diff): cid for pid, diff, cid in cur.fetchall()}

    # 4) Bridge table ----------------------------------------------------------
    cur.executemany(
        """
        INSERT INTO category_words (category_id, word_id)
        VALUES (%s, %s)
        ON CONFLICT DO NOTHING
        """,
        [
            (category_ids[(puzzle_ids[p["id"]], ans["level"])], word_ids[m.strip()])
            for p in archive
            for ans in p["answers"]
            for m in ans["members"]
        ],
    )

    conn.commit()


def report(conn: psycopg.Connection) -> None:
    cur = conn.cursor()
    for table in ("puzzles", "categories", "words", "category_words"):
        cur.execute(f"SELECT COUNT(*) FROM {table}")
        print(f"  {table:<16} {cur.fetchone()[0]:>7} rows")


def main() -> None:
    load_dotenv(PROJECT_ROOT / ".env")
    dsn = os.getenv("DATABASE_URL")
    if not dsn:
        sys.exit("DATABASE_URL is not set - copy .env.example to .env first.")

    archive = fetch_archive()
    print(f"Archive contains {len(archive)} puzzles.")
    archive = clean(archive)
    print(f"{len(archive)} puzzles remain after cleaning.")

    with psycopg.connect(dsn) as conn:
        load(conn, archive)
        print("Load complete:")
        report(conn)


if __name__ == "__main__":
    main()
