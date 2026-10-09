-- ============================================================================
-- Link Logic : NYT Connections solver database
-- 02_indexes.sql - indexing decisions
--
-- Run as:  psql -U postgres -d linklogic -f db/02_indexes.sql
--
-- Rationale for each index is next to it. Indexes we deliberately did NOT
-- create are documented at the bottom - knowing what not to index is part
-- of the design. Benchmarks proving these choices: db/05_benchmark.sql.
-- ============================================================================

-- Trigram extension: powers fuzzy text search (similarity(), % operator)
-- used by the solver's "theme hypothesis" queries.
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ---------------------------------------------------------------------------
-- Join-support B-tree indexes
-- ---------------------------------------------------------------------------

-- The single most important index for the solver.
-- category_words has PK (category_id, word_id): fine for category -> words,
-- useless for word -> categories (word_id is the 2nd column). Every solver
-- query starts from a word and walks to its categories, so we index the
-- reverse direction explicitly.
CREATE INDEX IF NOT EXISTS idx_category_words_word
    ON category_words (word_id);

-- categories are always fetched by their puzzle when building a grid.
CREATE INDEX IF NOT EXISTS idx_categories_puzzle
    ON categories (puzzle_id);

-- Gameplay foreign keys used by the leaderboard / analytics joins.
CREATE INDEX IF NOT EXISTS idx_sessions_player  ON game_sessions (player_id);
CREATE INDEX IF NOT EXISTS idx_sessions_puzzle  ON game_sessions (puzzle_id);
CREATE INDEX IF NOT EXISTS idx_guesses_session  ON guesses (session_id);

-- ---------------------------------------------------------------------------
-- Trigram GIN indexes for fuzzy text search
-- ---------------------------------------------------------------------------

-- Solver: "which historical category names look like my theme hypothesis?"
-- A GIN index over trigrams turns that from a full scan of every category
-- name into an index lookup.
CREATE INDEX IF NOT EXISTS idx_categories_name_trgm
    ON categories USING GIN (name gin_trgm_ops);

-- Solver: fuzzy word lookup (typos, partial words in the UI search box).
CREATE INDEX IF NOT EXISTS idx_words_text_trgm
    ON words USING GIN (word_text gin_trgm_ops);

-- ---------------------------------------------------------------------------
-- Indexes we did NOT create (and why)
-- ---------------------------------------------------------------------------
-- puzzles(puzzle_date), puzzles(nyt_number), words(word_text),
-- players(username):
--     already indexed implicitly - UNIQUE constraints create B-tree indexes,
--     so date range queries and exact word lookups are covered for free.
-- categories(difficulty):
--     only 4 distinct values across the table; the planner would (rightly)
--     ignore an index with such low selectivity.
-- guess_words(word_id):
--     analytics on guessed words are rare and the table stays small;
--     not worth the write cost on the hottest insert path.
