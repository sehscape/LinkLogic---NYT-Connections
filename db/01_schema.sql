-- ============================================================================
-- Link Logic : NYT Connections solver database
-- 01_schema.sql - relational schema (3NF)
--
-- Run as:  psql -U postgres -d linklogic -f db/01_schema.sql
--
-- Design notes
-- ------------
-- The schema is split into two halves:
--   1) PUZZLE CONTENT  (puzzles, categories, words, category_words)
--      - the historical archive the solver reasons over.
--   2) GAMEPLAY        (players, game_sessions, guesses, guess_words)
--      - rows produced by people playing the game, used for analytics.
--
-- Normalization: every table is in 3NF. `words` is a canonical vocabulary
-- table: the same word (e.g. HEAT) appears in many puzzles over the years,
-- so word text is stored exactly once and referenced by id. This is what
-- makes cross-puzzle solver queries (co-occurrence, ambiguity) cheap joins
-- instead of string scans.
-- ============================================================================

DROP TABLE IF EXISTS guess_words     CASCADE;
DROP TABLE IF EXISTS guesses         CASCADE;
DROP TABLE IF EXISTS game_sessions   CASCADE;
DROP TABLE IF EXISTS players         CASCADE;
DROP TABLE IF EXISTS category_words  CASCADE;
DROP TABLE IF EXISTS words           CASCADE;
DROP TABLE IF EXISTS categories      CASCADE;
DROP TABLE IF EXISTS puzzles         CASCADE;

-- ---------------------------------------------------------------------------
-- 1) Puzzle content
-- ---------------------------------------------------------------------------

-- One row per daily puzzle.
CREATE TABLE puzzles (
    puzzle_id   SERIAL PRIMARY KEY,
    nyt_number  INTEGER NOT NULL UNIQUE,   -- official puzzle number
    puzzle_date DATE    NOT NULL UNIQUE    -- one puzzle per day
);

-- Each puzzle has exactly 4 categories, one per difficulty color:
--   0 = Yellow (easiest), 1 = Green, 2 = Blue, 3 = Purple (hardest)
-- UNIQUE(puzzle_id, difficulty) enforces "one category per color per puzzle".
CREATE TABLE categories (
    category_id SERIAL PRIMARY KEY,
    puzzle_id   INTEGER  NOT NULL REFERENCES puzzles(puzzle_id) ON DELETE CASCADE,
    name        TEXT     NOT NULL,
    difficulty  SMALLINT NOT NULL CHECK (difficulty BETWEEN 0 AND 3),
    UNIQUE (puzzle_id, difficulty)
);

-- Canonical vocabulary: each distinct word stored once, ever.
CREATE TABLE words (
    word_id   SERIAL PRIMARY KEY,
    word_text TEXT NOT NULL UNIQUE
);

-- M:N bridge between categories and words (4 words per category).
-- Composite PK doubles as the (category_id, word_id) index.
CREATE TABLE category_words (
    category_id INTEGER NOT NULL REFERENCES categories(category_id) ON DELETE CASCADE,
    word_id     INTEGER NOT NULL REFERENCES words(word_id)          ON DELETE CASCADE,
    PRIMARY KEY (category_id, word_id)
);

-- ---------------------------------------------------------------------------
-- 2) Gameplay
-- ---------------------------------------------------------------------------

CREATE TABLE players (
    player_id  SERIAL PRIMARY KEY,
    username   TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- One row per attempt of a puzzle by a player.
-- solved: NULL = still playing, TRUE = won, FALSE = lost (4 mistakes).
CREATE TABLE game_sessions (
    session_id  SERIAL PRIMARY KEY,
    player_id   INTEGER NOT NULL REFERENCES players(player_id) ON DELETE CASCADE,
    puzzle_id   INTEGER NOT NULL REFERENCES puzzles(puzzle_id) ON DELETE CASCADE,
    started_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at TIMESTAMPTZ,
    mistakes    SMALLINT NOT NULL DEFAULT 0 CHECK (mistakes BETWEEN 0 AND 4),
    solved      BOOLEAN
);

-- Every submitted group of 4 words, in order.
-- matched_category_id is set only when the guess was correct.
CREATE TABLE guesses (
    guess_id            SERIAL PRIMARY KEY,
    session_id          INTEGER  NOT NULL REFERENCES game_sessions(session_id) ON DELETE CASCADE,
    guess_number        SMALLINT NOT NULL,
    is_correct          BOOLEAN  NOT NULL,
    is_one_away         BOOLEAN  NOT NULL DEFAULT FALSE,  -- 3 of 4 in one category
    matched_category_id INTEGER  REFERENCES categories(category_id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (session_id, guess_number)
);

-- The 4 words that made up each guess (kept normalized instead of an array
-- column so guesses can be joined back to words/categories for analytics).
CREATE TABLE guess_words (
    guess_id INTEGER NOT NULL REFERENCES guesses(guess_id) ON DELETE CASCADE,
    word_id  INTEGER NOT NULL REFERENCES words(word_id),
    PRIMARY KEY (guess_id, word_id)
);
