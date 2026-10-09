"""
Link Logic API: serves puzzles, validates guesses server-side, records
gameplay, and exposes the solver queries as hint endpoints.

Run from the project root:
    uvicorn backend.main:app --reload
"""

import random
from collections import Counter
from datetime import date
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from backend.db import COLOR_NAMES, pool

app = FastAPI(title="Link Logic", docs_url="/api/docs", openapi_url="/api/openapi.json")

FRONTEND_DIR = Path(__file__).resolve().parent.parent / "frontend"


# ---------------------------------------------------------------------------
# Request bodies
# ---------------------------------------------------------------------------

class SessionBody(BaseModel):
    username: str = Field(min_length=1, max_length=40)
    puzzle_id: int


class GuessBody(BaseModel):
    session_id: int
    words: list[str] = Field(min_length=4, max_length=4)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _grid_rows(conn, puzzle_id: int):
    return conn.execute(
        """
        SELECT w.word_id, w.word_text
        FROM categories c
        JOIN category_words cw ON cw.category_id = c.category_id
        JOIN words w           ON w.word_id      = cw.word_id
        WHERE c.puzzle_id = %s
        """,
        (puzzle_id,),
    ).fetchall()


def _puzzle_payload(conn, puzzle_row):
    words = [r["word_text"] for r in _grid_rows(conn, puzzle_row["puzzle_id"])]
    random.shuffle(words)
    return {
        "puzzle_id": puzzle_row["puzzle_id"],
        "nyt_number": puzzle_row["nyt_number"],
        "puzzle_date": puzzle_row["puzzle_date"],
        "words": words,
    }


def _solution(conn, puzzle_id: int):
    rows = conn.execute(
        """
        SELECT c.name, c.difficulty,
               ARRAY_AGG(w.word_text ORDER BY w.word_text) AS words
        FROM categories c
        JOIN category_words cw ON cw.category_id = c.category_id
        JOIN words w           ON w.word_id      = cw.word_id
        WHERE c.puzzle_id = %s
        GROUP BY c.category_id, c.name, c.difficulty
        ORDER BY c.difficulty
        """,
        (puzzle_id,),
    ).fetchall()
    for r in rows:
        r["color"] = COLOR_NAMES[r["difficulty"]]
    return rows


# ---------------------------------------------------------------------------
# Puzzle endpoints
# ---------------------------------------------------------------------------

@app.get("/api/meta")
def meta():
    with pool.connection() as conn:
        row = conn.execute(
            "SELECT COUNT(*) AS puzzle_count, MIN(puzzle_date) AS first_date,"
            "       MAX(puzzle_date) AS last_date FROM puzzles"
        ).fetchone()
        return row


@app.get("/api/puzzle/random")
def random_puzzle():
    with pool.connection() as conn:
        row = conn.execute(
            "SELECT puzzle_id, nyt_number, puzzle_date FROM puzzles"
            " ORDER BY random() LIMIT 1"
        ).fetchone()
        if not row:
            raise HTTPException(404, "No puzzles loaded - run etl/load_data.py")
        return _puzzle_payload(conn, row)


@app.get("/api/puzzle/by-date/{puzzle_date}")
def puzzle_by_date(puzzle_date: date):
    with pool.connection() as conn:
        row = conn.execute(
            "SELECT puzzle_id, nyt_number, puzzle_date FROM puzzles"
            " WHERE puzzle_date = %s",
            (puzzle_date,),
        ).fetchone()
        if not row:
            raise HTTPException(404, f"No puzzle for {puzzle_date}")
        return _puzzle_payload(conn, row)


# ---------------------------------------------------------------------------
# Gameplay endpoints
# ---------------------------------------------------------------------------

@app.post("/api/session")
def create_session(body: SessionBody):
    with pool.connection() as conn:
        player = conn.execute(
            """
            INSERT INTO players (username) VALUES (%s)
            ON CONFLICT (username) DO UPDATE SET username = EXCLUDED.username
            RETURNING player_id
            """,
            (body.username.strip(),),
        ).fetchone()
        session = conn.execute(
            "INSERT INTO game_sessions (player_id, puzzle_id) VALUES (%s, %s)"
            " RETURNING session_id",
            (player["player_id"], body.puzzle_id),
        ).fetchone()
        return {"session_id": session["session_id"], "player_id": player["player_id"]}


@app.post("/api/guess")
def submit_guess(body: GuessBody):
    if len(set(body.words)) != 4:
        raise HTTPException(400, "Pick 4 different words")

    with pool.connection() as conn:
        session = conn.execute(
            "SELECT session_id, puzzle_id, mistakes, finished_at"
            " FROM game_sessions WHERE session_id = %s",
            (body.session_id,),
        ).fetchone()
        if not session:
            raise HTTPException(404, "Unknown session")
        if session["finished_at"]:
            raise HTTPException(400, "This game is already finished")

        # Which categories of this puzzle do the 4 words belong to?
        rows = conn.execute(
            """
            SELECT w.word_id, w.word_text, cw.category_id
            FROM words w
            JOIN category_words cw ON cw.word_id     = w.word_id
            JOIN categories c      ON c.category_id  = cw.category_id
            WHERE c.puzzle_id = %s AND w.word_text = ANY(%s)
            """,
            (session["puzzle_id"], body.words),
        ).fetchall()
        if len(rows) != 4:
            raise HTTPException(400, "Words do not belong to this puzzle")

        # Reject a combination that was already submitted (no penalty).
        current_ids = sorted(r["word_id"] for r in rows)
        previous = conn.execute(
            """
            SELECT ARRAY_AGG(gw.word_id ORDER BY gw.word_id) AS ids
            FROM guesses g
            JOIN guess_words gw ON gw.guess_id = g.guess_id
            WHERE g.session_id = %s
            GROUP BY g.guess_id
            """,
            (body.session_id,),
        ).fetchall()
        if any(p["ids"] == current_ids for p in previous):
            return {"duplicate": True, "mistakes": session["mistakes"]}

        counts = Counter(r["category_id"] for r in rows)
        matched_category_id, best = counts.most_common(1)[0]
        correct = best == 4
        one_away = best == 3

        guess_number = len(previous) + 1
        guess = conn.execute(
            """
            INSERT INTO guesses
                (session_id, guess_number, is_correct, is_one_away, matched_category_id)
            VALUES (%s, %s, %s, %s, %s)
            RETURNING guess_id
            """,
            (
                body.session_id,
                guess_number,
                correct,
                one_away,
                matched_category_id if correct else None,
            ),
        ).fetchone()
        conn.cursor().executemany(
            "INSERT INTO guess_words (guess_id, word_id) VALUES (%s, %s)",
            [(guess["guess_id"], wid) for wid in current_ids],
        )

        result = {
            "duplicate": False,
            "correct": correct,
            "one_away": one_away,
            "game_over": False,
            "won": None,
            "mistakes": session["mistakes"],
        }

        if correct:
            cat = conn.execute(
                """
                SELECT c.name, c.difficulty,
                       ARRAY_AGG(w.word_text ORDER BY w.word_text) AS words
                FROM categories c
                JOIN category_words cw ON cw.category_id = c.category_id
                JOIN words w           ON w.word_id      = cw.word_id
                WHERE c.category_id = %s
                GROUP BY c.category_id, c.name, c.difficulty
                """,
                (matched_category_id,),
            ).fetchone()
            cat["color"] = COLOR_NAMES[cat["difficulty"]]
            result["category"] = cat

            solved_count = conn.execute(
                "SELECT COUNT(*) AS n FROM guesses"
                " WHERE session_id = %s AND is_correct",
                (body.session_id,),
            ).fetchone()["n"]
            if solved_count == 4:
                conn.execute(
                    "UPDATE game_sessions SET solved = TRUE, finished_at = now()"
                    " WHERE session_id = %s",
                    (body.session_id,),
                )
                result["game_over"] = True
                result["won"] = True
        else:
            mistakes = session["mistakes"] + 1
            conn.execute(
                "UPDATE game_sessions SET mistakes = %s WHERE session_id = %s",
                (mistakes, body.session_id),
            )
            result["mistakes"] = mistakes
            if mistakes >= 4:
                conn.execute(
                    "UPDATE game_sessions SET solved = FALSE, finished_at = now()"
                    " WHERE session_id = %s",
                    (body.session_id,),
                )
                result["game_over"] = True
                result["won"] = False
                result["solution"] = _solution(conn, session["puzzle_id"])

        return result


@app.get("/api/session/{session_id}/summary")
def session_summary(session_id: int):
    """Post-game share grid: the true color of every word in every guess.

    Only available once the game is finished, so it never leaks answers
    mid-game. Rebuilding the grid is a 4-table join: guesses -> guess_words
    -> category_words -> categories, scoped to the session's puzzle.
    """
    with pool.connection() as conn:
        session = conn.execute(
            "SELECT gs.puzzle_id, gs.mistakes, gs.solved, gs.finished_at,"
            "       p.nyt_number, p.puzzle_date"
            " FROM game_sessions gs JOIN puzzles p ON p.puzzle_id = gs.puzzle_id"
            " WHERE gs.session_id = %s",
            (session_id,),
        ).fetchone()
        if not session:
            raise HTTPException(404, "Unknown session")
        if not session["finished_at"]:
            raise HTTPException(400, "Game still in progress")

        rows = conn.execute(
            """
            SELECT g.guess_number, c.difficulty
            FROM guesses g
            JOIN guess_words gw    ON gw.guess_id    = g.guess_id
            JOIN category_words cw ON cw.word_id     = gw.word_id
            JOIN categories c      ON c.category_id  = cw.category_id
            WHERE g.session_id = %s AND c.puzzle_id = %s
            ORDER BY g.guess_number, c.difficulty
            """,
            (session_id, session["puzzle_id"]),
        ).fetchall()
        grid: dict[int, list[int]] = {}
        for r in rows:
            grid.setdefault(r["guess_number"], []).append(r["difficulty"])
        return {
            "nyt_number": session["nyt_number"],
            "puzzle_date": session["puzzle_date"],
            "mistakes": session["mistakes"],
            "solved": session["solved"],
            "guesses": [grid[n] for n in sorted(grid)],
        }


# ---------------------------------------------------------------------------
# Stats endpoints (thin wrappers over the views in db/03_views.sql)
# ---------------------------------------------------------------------------

@app.get("/api/stats/leaderboard")
def leaderboard():
    with pool.connection() as conn:
        return conn.execute(
            "SELECT username, games_finished, wins, avg_mistakes, player_rank"
            " FROM v_leaderboard WHERE games_finished > 0"
            " ORDER BY player_rank, username LIMIT 10"
        ).fetchall()


@app.get("/api/stats/colors")
def color_stats():
    with pool.connection() as conn:
        return conn.execute("SELECT * FROM v_color_stats").fetchall()


@app.get("/api/stats/hardest")
def hardest_puzzles():
    with pool.connection() as conn:
        return conn.execute(
            "SELECT nyt_number, puzzle_date, attempts, avg_mistakes, win_rate_pct"
            " FROM v_puzzle_difficulty WHERE attempts > 0"
            " ORDER BY avg_mistakes DESC NULLS LAST LIMIT 10"
        ).fetchall()


# ---------------------------------------------------------------------------
# Solver endpoints (API versions of db/04_solver_queries.sql, S1-S5).
# All of them exclude the puzzle being solved - the solver only ever
# reasons from OTHER puzzles' history.
# ---------------------------------------------------------------------------

@app.get("/api/solver/word-history")
def solver_word_history(word: str):
    with pool.connection() as conn:
        rows = conn.execute(
            """
            SELECT w.word_text, c.name AS category, c.difficulty,
                   p.puzzle_date, p.nyt_number
            FROM words w
            JOIN category_words cw ON cw.word_id    = w.word_id
            JOIN categories c      ON c.category_id = cw.category_id
            JOIN puzzles p         ON p.puzzle_id   = c.puzzle_id
            WHERE upper(w.word_text) = upper(%s)
            ORDER BY p.puzzle_date
            """,
            (word.strip(),),
        ).fetchall()
        for r in rows:
            r["color"] = COLOR_NAMES[r["difficulty"]]
        return rows


@app.get("/api/solver/co-occurrence")
def solver_co_occurrence(puzzle_id: int):
    with pool.connection() as conn:
        return conn.execute(
            """
            WITH grid AS (
                SELECT w.word_id, w.word_text
                FROM categories c
                JOIN category_words cw ON cw.category_id = c.category_id
                JOIN words w           ON w.word_id      = cw.word_id
                WHERE c.puzzle_id = %(pid)s
            )
            SELECT g1.word_text AS word_a, g2.word_text AS word_b,
                   COUNT(*)     AS times_grouped
            FROM grid g1
            JOIN category_words cw1 ON cw1.word_id     = g1.word_id
            JOIN category_words cw2 ON cw2.category_id = cw1.category_id
            JOIN grid g2            ON g2.word_id      = cw2.word_id
            JOIN categories c       ON c.category_id   = cw1.category_id
            WHERE g1.word_id < g2.word_id
              AND c.puzzle_id <> %(pid)s
            GROUP BY g1.word_text, g2.word_text
            ORDER BY times_grouped DESC, word_a
            LIMIT 30
            """,
            {"pid": puzzle_id},
        ).fetchall()


@app.get("/api/solver/candidates")
def solver_candidates(puzzle_id: int):
    with pool.connection() as conn:
        return conn.execute(
            """
            WITH grid AS (
                SELECT w.word_id, w.word_text
                FROM categories c
                JOIN category_words cw ON cw.category_id = c.category_id
                JOIN words w           ON w.word_id      = cw.word_id
                WHERE c.puzzle_id = %(pid)s
            )
            SELECT c.name                                      AS past_category,
                   p.puzzle_date                               AS seen_on,
                   COUNT(*)                                    AS grid_words_matched,
                   ARRAY_AGG(g.word_text ORDER BY g.word_text) AS matched_words
            FROM grid g
            JOIN category_words cw ON cw.word_id    = g.word_id
            JOIN categories c      ON c.category_id = cw.category_id
            JOIN puzzles p         ON p.puzzle_id   = c.puzzle_id
            WHERE c.puzzle_id <> %(pid)s
            GROUP BY c.category_id, c.name, p.puzzle_date
            HAVING COUNT(*) >= 2
            ORDER BY grid_words_matched DESC, seen_on DESC
            LIMIT 15
            """,
            {"pid": puzzle_id},
        ).fetchall()


@app.get("/api/solver/trap-words")
def solver_trap_words(puzzle_id: int):
    with pool.connection() as conn:
        return conn.execute(
            """
            WITH grid AS (
                SELECT w.word_id, w.word_text
                FROM categories c
                JOIN category_words cw ON cw.category_id = c.category_id
                JOIN words w           ON w.word_id      = cw.word_id
                WHERE c.puzzle_id = %(pid)s
            )
            SELECT g.word_text,
                   COUNT(DISTINCT cw.category_id) AS past_appearances,
                   COUNT(DISTINCT c.name)         AS distinct_themes,
                   RANK() OVER (ORDER BY COUNT(DISTINCT c.name) DESC) AS trap_rank
            FROM grid g
            JOIN category_words cw ON cw.word_id    = g.word_id
            JOIN categories c      ON c.category_id = cw.category_id
            WHERE c.puzzle_id <> %(pid)s
            GROUP BY g.word_text
            ORDER BY trap_rank, g.word_text
            """,
            {"pid": puzzle_id},
        ).fetchall()


@app.get("/api/solver/theme")
def solver_theme(q: str, exclude_puzzle_id: int | None = None):
    with pool.connection() as conn:
        return conn.execute(
            """
            SELECT c.name                                      AS past_category,
                   ROUND(similarity(c.name, %(q)s)::numeric, 3) AS sim,
                   p.puzzle_date,
                   ARRAY_AGG(w.word_text ORDER BY w.word_text) AS its_words
            FROM categories c
            JOIN puzzles p         ON p.puzzle_id    = c.puzzle_id
            JOIN category_words cw ON cw.category_id = c.category_id
            JOIN words w           ON w.word_id      = cw.word_id
            WHERE similarity(c.name, %(q)s) > 0.15
              AND c.puzzle_id IS DISTINCT FROM %(pid)s
            GROUP BY c.category_id, c.name, p.puzzle_date
            ORDER BY sim DESC
            LIMIT 15
            """,
            {"q": q.strip(), "pid": exclude_puzzle_id},
        ).fetchall()


# Static frontend - mounted last so /api/* wins.
app.mount("/", StaticFiles(directory=FRONTEND_DIR, html=True), name="frontend")
