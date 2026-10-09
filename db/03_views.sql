-- ============================================================================
-- Link Logic : NYT Connections solver database
-- 03_views.sql - analytics views over gameplay + archive
--
-- Run as:  psql -U postgres -d linklogic -f db/03_views.sql
--
-- Views package the reporting queries the app shows on screen, so the
-- backend stays a thin "SELECT * FROM view" layer and the SQL lives here.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Leaderboard: rank players by wins, tie-break on fewer average mistakes.
-- Demonstrates: LEFT JOIN + FILTERed aggregates + window function over the
-- grouped result.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_leaderboard AS
SELECT
    p.player_id,
    p.username,
    COUNT(gs.session_id) FILTER (WHERE gs.finished_at IS NOT NULL)       AS games_finished,
    COUNT(gs.session_id) FILTER (WHERE gs.solved)                        AS wins,
    ROUND(AVG(gs.mistakes) FILTER (WHERE gs.finished_at IS NOT NULL), 2) AS avg_mistakes,
    RANK() OVER (
        ORDER BY COUNT(gs.session_id) FILTER (WHERE gs.solved) DESC,
                 AVG(gs.mistakes) FILTER (WHERE gs.finished_at IS NOT NULL) ASC NULLS LAST
    ) AS player_rank
FROM players p
LEFT JOIN game_sessions gs ON gs.player_id = p.player_id
GROUP BY p.player_id, p.username;

-- ---------------------------------------------------------------------------
-- Puzzle difficulty as measured by real play: attempts, average mistakes,
-- and win rate per puzzle.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_puzzle_difficulty AS
SELECT
    pz.puzzle_id,
    pz.nyt_number,
    pz.puzzle_date,
    COUNT(gs.session_id) FILTER (WHERE gs.finished_at IS NOT NULL) AS attempts,
    ROUND(AVG(gs.mistakes) FILTER (WHERE gs.finished_at IS NOT NULL), 2) AS avg_mistakes,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE gs.solved)
              / NULLIF(COUNT(*) FILTER (WHERE gs.finished_at IS NOT NULL), 0),
        1
    ) AS win_rate_pct
FROM puzzles pz
LEFT JOIN game_sessions gs ON gs.puzzle_id = pz.puzzle_id
GROUP BY pz.puzzle_id, pz.nyt_number, pz.puzzle_date;

-- ---------------------------------------------------------------------------
-- Word ambiguity across the whole archive: in how many categories, puzzles
-- and distinct themes has each word appeared? High counts = classic "trap"
-- words that fit several groups.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_word_ambiguity AS
SELECT
    w.word_id,
    w.word_text,
    COUNT(DISTINCT cw.category_id) AS category_count,
    COUNT(DISTINCT c.puzzle_id)    AS puzzle_count,
    COUNT(DISTINCT c.name)         AS distinct_themes
FROM words w
JOIN category_words cw ON cw.word_id = w.word_id
JOIN categories c      ON c.category_id = cw.category_id
GROUP BY w.word_id, w.word_text;

-- ---------------------------------------------------------------------------
-- Which color gets solved when? For each difficulty color: how often it was
-- found and the average guess position it was found at (Purple should trend
-- later than Yellow if the difficulty labels are honest).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_color_stats AS
SELECT
    c.difficulty,
    CASE c.difficulty
        WHEN 0 THEN 'Yellow'
        WHEN 1 THEN 'Green'
        WHEN 2 THEN 'Blue'
        ELSE        'Purple'
    END AS color,
    COUNT(g.guess_id)               AS times_solved,
    ROUND(AVG(g.guess_number), 2)   AS avg_guess_position
FROM guesses g
JOIN categories c ON c.category_id = g.matched_category_id
WHERE g.is_correct
GROUP BY c.difficulty
ORDER BY c.difficulty;
