-- ============================================================================
-- Link Logic : NYT Connections solver database
-- 04_solver_queries.sql - THE SOLVER
--
-- Run as:
--   psql -U postgres -d linklogic -f db/04_solver_queries.sql
-- or open psql, \set the variables below to anything you like, and run the
-- queries one by one.
--
-- How the solver works
-- --------------------
-- Connections gives you 16 words that must be split into 4 hidden groups.
-- The archive of past puzzles is a knowledge base: words repeat across the
-- years, and words that were grouped together before tend to be related.
-- Each query below extracts one "solving signal" from that history:
--
--   S1  What has this word meant before?           (3-table join)
--   S2  Which grid words were grouped together
--       in past puzzles?                           (self-join + aggregation)
--   S3  Which past categories overlap today's
--       grid with 2+ words?  <- candidate groups   (CTE + HAVING)
--   S4  Which grid words are "traps"?              (aggregation + window RANK)
--   S5  Does my theme hypothesis match any past
--       category name?                             (pg_trgm fuzzy search)
--   S6  Archive analytics over date ranges         (range queries, GROUP BY)
--   S7  Set-based curiosities                      (subqueries / EXISTS)
-- ============================================================================

-- Parameters used by the queries below.
\set target_word  'HEAT'
\set target_date  '2024-06-01'
\set hypothesis   'basketball teams'

-- ---------------------------------------------------------------------------
\echo
\echo '=== S1. Word history: every past appearance of' :target_word '==='
-- The fundamental lookup: word -> categories -> puzzles.
-- Uses UNIQUE index on words.word_text, then idx_category_words_word.
-- ---------------------------------------------------------------------------
SELECT
    w.word_text,
    c.name                                   AS category,
    CASE c.difficulty
        WHEN 0 THEN 'Yellow' WHEN 1 THEN 'Green'
        WHEN 2 THEN 'Blue'   ELSE 'Purple'
    END                                      AS color,
    p.puzzle_date,
    p.nyt_number
FROM words w
JOIN category_words cw ON cw.word_id     = w.word_id
JOIN categories     c  ON c.category_id  = cw.category_id
JOIN puzzles        p  ON p.puzzle_id    = c.puzzle_id
WHERE upper(w.word_text) = upper(:'target_word')
ORDER BY p.puzzle_date;

-- ---------------------------------------------------------------------------
\echo
\echo '=== S2. Co-occurrence: grid word pairs that shared a category before ==='
-- Take the 16 words of the target puzzle, then self-join category_words to
-- find pairs of those words that appeared together in some OTHER puzzle's
-- category. Pairs with history together are strong group candidates.
-- ---------------------------------------------------------------------------
WITH grid AS (                       -- the 16 words of the puzzle being solved
    SELECT w.word_id, w.word_text
    FROM puzzles p
    JOIN categories     c  ON c.puzzle_id   = p.puzzle_id
    JOIN category_words cw ON cw.category_id = c.category_id
    JOIN words          w  ON w.word_id      = cw.word_id
    WHERE p.puzzle_date = :'target_date'
)
SELECT
    g1.word_text            AS word_a,
    g2.word_text            AS word_b,
    COUNT(*)                AS times_grouped,
    ARRAY_AGG(c.name ORDER BY p.puzzle_date) AS under_categories
FROM grid g1
JOIN category_words cw1 ON cw1.word_id     = g1.word_id
JOIN category_words cw2 ON cw2.category_id = cw1.category_id
JOIN grid g2            ON g2.word_id      = cw2.word_id
JOIN categories c       ON c.category_id   = cw1.category_id
JOIN puzzles    p       ON p.puzzle_id     = c.puzzle_id
WHERE g1.word_id < g2.word_id            -- each unordered pair once
  AND p.puzzle_date <> :'target_date'    -- never peek at the puzzle itself
GROUP BY g1.word_text, g2.word_text
ORDER BY times_grouped DESC, word_a;

-- ---------------------------------------------------------------------------
\echo
\echo '=== S3. Candidate groups: past categories overlapping the grid 2+ times ==='
-- The strongest signal the archive can give: if a past category contains
-- several of today's words, that category's theme is a candidate group.
-- ---------------------------------------------------------------------------
WITH grid AS (
    SELECT w.word_id, w.word_text
    FROM puzzles p
    JOIN categories     c  ON c.puzzle_id    = p.puzzle_id
    JOIN category_words cw ON cw.category_id = c.category_id
    JOIN words          w  ON w.word_id      = cw.word_id
    WHERE p.puzzle_date = :'target_date'
),
candidate_groups AS (        -- ("overlaps" would clash with the SQL keyword)
    SELECT
        c.name                                        AS past_category,
        p.puzzle_date                                 AS seen_on,
        COUNT(*)                                      AS grid_words_matched,
        ARRAY_AGG(g.word_text ORDER BY g.word_text)   AS matched_words
    FROM grid g
    JOIN category_words cw ON cw.word_id    = g.word_id
    JOIN categories     c  ON c.category_id = cw.category_id
    JOIN puzzles        p  ON p.puzzle_id   = c.puzzle_id
    WHERE p.puzzle_date <> :'target_date'
    GROUP BY c.category_id, c.name, p.puzzle_date
    HAVING COUNT(*) >= 2                  -- at least 2 of today's 16 words
)
SELECT *
FROM candidate_groups
ORDER BY grid_words_matched DESC, seen_on DESC
LIMIT 20;

-- ---------------------------------------------------------------------------
\echo
\echo '=== S4. Trap words: most ambiguous words on the grid ==='
-- A word that has lived in many different themes is exactly the word the
-- puzzle uses to mislead you. Rank today's 16 words by historical ambiguity.
-- ---------------------------------------------------------------------------
WITH grid AS (
    SELECT w.word_id, w.word_text
    FROM puzzles p
    JOIN categories     c  ON c.puzzle_id    = p.puzzle_id
    JOIN category_words cw ON cw.category_id = c.category_id
    JOIN words          w  ON w.word_id      = cw.word_id
    WHERE p.puzzle_date = :'target_date'
)
SELECT
    g.word_text,
    COUNT(DISTINCT cw.category_id) AS past_appearances,
    COUNT(DISTINCT c.name)         AS distinct_themes,
    RANK() OVER (ORDER BY COUNT(DISTINCT c.name) DESC) AS trap_rank
FROM grid g
JOIN category_words cw ON cw.word_id    = g.word_id
JOIN categories     c  ON c.category_id = cw.category_id
GROUP BY g.word_text
ORDER BY trap_rank, g.word_text;

-- ---------------------------------------------------------------------------
\echo
\echo '=== S5. Theme hypothesis check:' :hypothesis '==='
-- Fuzzy-match a guessed theme against every historical category name using
-- trigram similarity (GIN index: idx_categories_name_trgm), and show what
-- words fell under the similar categories.
-- ---------------------------------------------------------------------------
SELECT set_limit(0.15);   -- similarity threshold for the % operator

SELECT
    c.name                                       AS past_category,
    ROUND(similarity(c.name, :'hypothesis')::numeric, 3) AS sim,
    p.puzzle_date,
    ARRAY_AGG(w.word_text ORDER BY w.word_text)  AS its_words
FROM categories c
JOIN puzzles        p  ON p.puzzle_id    = c.puzzle_id
JOIN category_words cw ON cw.category_id = c.category_id
JOIN words          w  ON w.word_id      = cw.word_id
WHERE c.name % :'hypothesis'
  AND p.puzzle_date <> :'target_date'    -- the solver never peeks at its own puzzle
GROUP BY c.category_id, c.name, p.puzzle_date
ORDER BY sim DESC
LIMIT 15;

-- ---------------------------------------------------------------------------
\echo
\echo '=== S6a. Range query: puzzles per month, first half of 2024 ==='
-- Uses the implicit B-tree index from UNIQUE(puzzle_date).
-- ---------------------------------------------------------------------------
SELECT
    date_trunc('month', puzzle_date)::date AS month,
    COUNT(*)                               AS puzzles
FROM puzzles
WHERE puzzle_date BETWEEN DATE '2024-01-01' AND DATE '2024-06-30'
GROUP BY month
ORDER BY month;

\echo
\echo '=== S6b. Most reused words in the whole archive ==='
SELECT
    w.word_text,
    COUNT(*) AS appearances
FROM words w
JOIN category_words cw ON cw.word_id = w.word_id
GROUP BY w.word_text
HAVING COUNT(*) >= 4
ORDER BY appearances DESC, w.word_text
LIMIT 20;

-- ---------------------------------------------------------------------------
\echo
\echo '=== S7. Words that have been both a Yellow and a Purple answer ==='
-- Subquery/EXISTS demonstration: the same word appearing at both extremes
-- of the difficulty scale.
-- ---------------------------------------------------------------------------
SELECT w.word_text
FROM words w
WHERE EXISTS (
        SELECT 1
        FROM category_words cw
        JOIN categories c ON c.category_id = cw.category_id
        WHERE cw.word_id = w.word_id AND c.difficulty = 0
      )
  AND EXISTS (
        SELECT 1
        FROM category_words cw
        JOIN categories c ON c.category_id = cw.category_id
        WHERE cw.word_id = w.word_id AND c.difficulty = 3
      )
ORDER BY w.word_text
LIMIT 25;
