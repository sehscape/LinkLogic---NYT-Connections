# Link Logic — NYT Connections with a SQL Solving Assistant

A database-backed clone of NYT Connections plus a **solver assistant powered
entirely by PostgreSQL queries** over an archive of 1,100+ past puzzles.

Built for the *Database & Data Warehousing* course project
(theme: “Building a Database Backend for a Puzzle Solver”).

## The idea

Connections gives you 16 words hiding 4 groups of 4. The trick: words are
chosen so several plausible groupings exist. But the archive of past puzzles
is a knowledge base — words repeat across years, and their grouping history is
a solving signal. This project stores the archive in a normalized (3NF)
PostgreSQL schema and mines it with SQL:

- **Word history** — every category a word has ever appeared in *(3-table join)*
- **Pair signals** — grid words that shared a category before *(self-join + aggregation)*
- **Candidate groups** — past categories overlapping today's grid with 2+ words *(CTE + HAVING)*
- **Trap words** — historically ambiguous grid words *(window RANK)*
- **Theme hypothesis** — fuzzy-match your theory against 4,400+ past category names *(pg_trgm GIN index)*

The solver never looks at the current puzzle's answers — only at other
puzzles' history.

On top of that sits a playable web game (FastAPI + vanilla JS): guesses are
validated server-side by SQL, every session/guess is recorded, and views power
a leaderboard and difficulty analytics.

## Repository layout

```
db/
  01_schema.sql          3NF schema (puzzle archive + gameplay tables)
  02_indexes.sql         indexing decisions, with rationale for each
  03_views.sql           leaderboard / difficulty / ambiguity views
  04_solver_queries.sql  the solver as runnable, parameterized SQL (S1–S7)
  05_benchmark.sql       EXPLAIN ANALYZE proof of the indexing choices
etl/load_data.py         archive JSON -> PostgreSQL (idempotent)
backend/                 FastAPI API: game rules, stats, solver endpoints
frontend/                the game UI (vanilla JS, no build step)
docs/design.md           ER diagram, 3NF justification, benchmark results
```

## Setup

Requirements: PostgreSQL 14+ (tested on 18), Python 3.11+.

```bash
# 1. Create the database
psql -U postgres -c "CREATE DATABASE linklogic"

# 2. Schema, indexes, views
psql -U postgres -d linklogic -f db/01_schema.sql
psql -U postgres -d linklogic -f db/02_indexes.sql
psql -U postgres -d linklogic -f db/03_views.sql

# 3. Python environment
pip install -r requirements.txt
copy .env.example .env        # then put your postgres password in .env

# 4. Load the puzzle archive (downloads + caches the JSON)
python etl/load_data.py

# 5. Run the app
uvicorn backend.main:app --reload
```

Open http://127.0.0.1:8000 — pick a name, play a random puzzle or any date,
and open the **Solver** tab for SQL-powered hints.

## Running the solver from psql

```bash
psql -U postgres -d linklogic -f db/04_solver_queries.sql
```

Edit the `\set` variables at the top of the file to solve a different date or
test a different word/theme. Benchmarks:

```bash
psql -U postgres -d linklogic -f db/05_benchmark.sql
```

## Design highlights

- **Canonical vocabulary**: every word stored once (`words`), referenced via a
  `category_words` bridge — cross-puzzle questions become index-backed joins.
- **Reverse junction index** `category_words(word_id)`: the PK covers
  category→words, this covers word→categories, which is the direction every
  solver query walks.
- **Trigram GIN indexes** for fuzzy theme search.
- Full justification, ER diagram and measured benchmarks: [docs/design.md](docs/design.md).
