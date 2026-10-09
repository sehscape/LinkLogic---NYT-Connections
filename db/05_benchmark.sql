-- ============================================================================
-- Link Logic : NYT Connections solver database
-- 05_benchmark.sql - proving the indexing decisions with EXPLAIN ANALYZE
--
-- Run as:  psql -U postgres -d linklogic -f db/05_benchmark.sql
--
-- Method: for each benchmark, the relevant index is dropped INSIDE a
-- transaction that is rolled back, so the "without index" plan is measured
-- on the exact same data and the database is left untouched.
-- Results are recorded in docs/design.md.
-- ============================================================================

\timing on

-- ---------------------------------------------------------------------------
\echo
\echo '############ B1. word -> categories lookup (idx_category_words_word) ####'
-- The solver's core access path: find every category a word appeared in.
-- Without the reverse junction index, Postgres must scan all of
-- category_words for each probe.
-- ---------------------------------------------------------------------------
\echo
\echo '--- B1 WITHOUT index ---'
BEGIN;
DROP INDEX idx_category_words_word;
EXPLAIN ANALYZE
SELECT c.name, p.puzzle_date
FROM words w
JOIN category_words cw ON cw.word_id    = w.word_id
JOIN categories     c  ON c.category_id = cw.category_id
JOIN puzzles        p  ON p.puzzle_id   = c.puzzle_id
WHERE w.word_text = 'HEAT';
ROLLBACK;

\echo
\echo '--- B1 WITH index ---'
EXPLAIN ANALYZE
SELECT c.name, p.puzzle_date
FROM words w
JOIN category_words cw ON cw.word_id    = w.word_id
JOIN categories     c  ON c.category_id = cw.category_id
JOIN puzzles        p  ON p.puzzle_id   = c.puzzle_id
WHERE w.word_text = 'HEAT';

-- ---------------------------------------------------------------------------
\echo
\echo '############ B2. co-occurrence self-join (heaviest solver query) ########'
-- S2 from the solver: joins category_words against itself across the 16
-- grid words. Hits the reverse junction index on both sides.
-- ---------------------------------------------------------------------------
\echo
\echo '--- B2 WITHOUT index ---'
BEGIN;
DROP INDEX idx_category_words_word;
EXPLAIN ANALYZE
WITH grid AS (
    SELECT w.word_id, w.word_text
    FROM puzzles p
    JOIN categories     c  ON c.puzzle_id    = p.puzzle_id
    JOIN category_words cw ON cw.category_id = c.category_id
    JOIN words          w  ON w.word_id      = cw.word_id
    WHERE p.puzzle_date = DATE '2024-06-01'
)
SELECT g1.word_text, g2.word_text, COUNT(*)
FROM grid g1
JOIN category_words cw1 ON cw1.word_id     = g1.word_id
JOIN category_words cw2 ON cw2.category_id = cw1.category_id
JOIN grid g2            ON g2.word_id      = cw2.word_id
WHERE g1.word_id < g2.word_id
GROUP BY g1.word_text, g2.word_text;
ROLLBACK;

\echo
\echo '--- B2 WITH index ---'
EXPLAIN ANALYZE
WITH grid AS (
    SELECT w.word_id, w.word_text
    FROM puzzles p
    JOIN categories     c  ON c.puzzle_id    = p.puzzle_id
    JOIN category_words cw ON cw.category_id = c.category_id
    JOIN words          w  ON w.word_id      = cw.word_id
    WHERE p.puzzle_date = DATE '2024-06-01'
)
SELECT g1.word_text, g2.word_text, COUNT(*)
FROM grid g1
JOIN category_words cw1 ON cw1.word_id     = g1.word_id
JOIN category_words cw2 ON cw2.category_id = cw1.category_id
JOIN grid g2            ON g2.word_id      = cw2.word_id
WHERE g1.word_id < g2.word_id
GROUP BY g1.word_text, g2.word_text;

-- ---------------------------------------------------------------------------
\echo
\echo '############ B3. fuzzy theme search (GIN trigram index) #################'
-- This one is the most interesting benchmark: at 4.4K rows the planner
-- STILL picks a sequential scan even when the GIN index exists, because its
-- cost model is I/O-centric and underestimates how CPU-expensive computing
-- similarity() on every row is (~16 ms of pure CPU). Forcing the index
-- (enable_seqscan = off) proves the GIN plan is an order of magnitude
-- faster. Lesson: EXPLAIN ANALYZE, not the optimizer's estimate, is the
-- ground truth.
-- ---------------------------------------------------------------------------
SELECT set_limit(0.15);

\echo
\echo '--- B3 WITHOUT the index (Seq Scan is the only option) ---'
BEGIN;
DROP INDEX idx_categories_name_trgm;
EXPLAIN ANALYZE
SELECT name, similarity(name, 'basketball teams') AS sim
FROM categories
WHERE name % 'basketball teams'
ORDER BY sim DESC;
ROLLBACK;

\echo
\echo '--- B3 WITH index, planner default (still chooses Seq Scan!) ---'
EXPLAIN ANALYZE
SELECT name, similarity(name, 'basketball teams') AS sim
FROM categories
WHERE name % 'basketball teams'
ORDER BY sim DESC;

\echo
\echo '--- B3 WITH index, forced (enable_seqscan = off) ---'
SET enable_seqscan = off;
EXPLAIN ANALYZE
SELECT name, similarity(name, 'basketball teams') AS sim
FROM categories
WHERE name % 'basketball teams'
ORDER BY sim DESC;
RESET enable_seqscan;

-- ---------------------------------------------------------------------------
\echo
\echo '############ B4. range queries ride the UNIQUE constraint for free #####'
-- No explicit index was created on puzzles.puzzle_date: the UNIQUE
-- constraint already provides a B-tree, and the planner uses it both for a
-- narrow window and for a scan of nearly the whole table.
-- ---------------------------------------------------------------------------
\echo
\echo '--- B4 narrow range (one quarter) ---'
EXPLAIN ANALYZE
SELECT * FROM puzzles
WHERE puzzle_date BETWEEN DATE '2024-01-01' AND DATE '2024-03-31';

\echo
\echo '--- B4 wide range (the whole archive) ---'
EXPLAIN ANALYZE
SELECT * FROM puzzles
WHERE puzzle_date BETWEEN DATE '2023-06-12' AND DATE '2026-06-27';
