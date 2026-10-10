<a id="readme-top"></a>

<div align="center">

<a href="https://linklogic-ctji.onrender.com">
  <img src="docs/assets/banner.png" alt="LinkLogic: the NYT Connections puzzle rebuilt on PostgreSQL, with a hint engine written entirely in SQL" width="100%">
</a>

<br/>

<a href="https://linklogic-ctji.onrender.com"><img src="https://img.shields.io/badge/%E2%96%B6%20Play%20live-linklogic--ctji.onrender.com-8b5cf6?style=for-the-badge&logo=render&logoColor=white" alt="Play live"></a>

<img src="https://img.shields.io/badge/Python-3.14-3776AB?style=flat-square&logo=python&logoColor=white" alt="Python 3.14">
<img src="https://img.shields.io/badge/FastAPI-API-009688?style=flat-square&logo=fastapi&logoColor=white" alt="FastAPI">
<img src="https://img.shields.io/badge/PostgreSQL-18-4169E1?style=flat-square&logo=postgresql&logoColor=white" alt="PostgreSQL 18">
<img src="https://img.shields.io/badge/JavaScript-no%20build%20step-F7DF1E?style=flat-square&logo=javascript&logoColor=black" alt="Vanilla JavaScript">
<img src="https://img.shields.io/badge/Neon-serverless%20Postgres-00E599?style=flat-square&logo=neon&logoColor=black" alt="Neon">
<img src="https://img.shields.io/badge/Render-deployed-46E3B7?style=flat-square&logo=render&logoColor=black" alt="Render">
<img src="https://img.shields.io/github/last-commit/sehscape/LinkLogic---NYT-Connections?style=flat-square&color=8b5cf6" alt="Last commit">

<h3>Sixteen words. Four hidden groups. One database that remembers every puzzle ever played.</h3>

<a href="https://linklogic-ctji.onrender.com"><b>Play now</b></a> ·
<a href="#-how-it-works"><b>How it works</b></a> ·
<a href="#%EF%B8%8F-database-design"><b>Database design</b></a> ·
<a href="#-the-sql-solver"><b>SQL solver</b></a> ·
<a href="#-getting-started"><b>Run locally</b></a>

</div>

<br/>

## 🎬 See it in action

<div align="center">
  <img src="docs/assets/demo.gif" alt="Gameplay: a wrong guess triggers 'One away!', then all four groups are solved and a confetti win screen shows the share grid" width="100%">
  <sub>A real game on the live database: one "One away!" mistake, four groups found, share grid and confetti.</sub>
</div>

<br/>

**LinkLogic** is a full-stack remake of the New York Times *Connections* puzzle. It ships with a twist: a **solving assistant written entirely in SQL**.

Every daily puzzle since June 2023 lives in a normalized PostgreSQL database. Words come back across puzzles again and again. HEAT, BALL and RING have each served dozens of different themes. So the archive itself is a knowledge base. The solver mines it with joins, CTEs, window functions and trigram search, and never peeks at today's answers.

> Built as a *Database & Data Warehousing* course project on the theme *"Building a Database Backend for a Puzzle Solver"*.

<details>
<summary><b>📑 Table of contents</b></summary>

- [✨ Features](#-features)
- [🖼️ Screenshots](#️-screenshots)
- [🕹️ How to play](#️-how-to-play)
- [🧭 How it works](#-how-it-works)
  - [Architecture](#architecture)
  - [Life of a guess](#life-of-a-guess)
  - [Game state machine](#game-state-machine)
- [🗄️ Database design](#️-database-design)
- [🧠 The SQL solver](#-the-sql-solver)
- [📊 Data & insights](#-data--insights)
- [⚡ Indexing & performance](#-indexing--performance)
- [🔄 Data pipeline (ETL)](#-data-pipeline-etl)
- [🔌 API reference](#-api-reference)
- [📁 Project structure](#-project-structure)
- [🚀 Getting started](#-getting-started)
- [☁️ Deployment](#️-deployment)
- [🧰 Tech stack](#-tech-stack)
- [🙏 Acknowledgements](#-acknowledgements)

</details>

---

## ✨ Features

<table>
<tr>
<td width="50%" valign="top">

### 🎮 Faithful gameplay
16 words, 4 hidden groups and 4 mistakes, with **"One away!"** hints, free retries on duplicate guesses, and shuffle and deselect. **Every rule is enforced server-side**, so the browser never knows the answers.

</td>
<td width="50%" valign="top">

### 🧠 SQL solver assistant
Five hint signals mined from **1,210 past puzzles**: word history, pair signals, candidate groups, trap words and fuzzy theme search. Each one is a single SQL query.

</td>
</tr>
<tr>
<td valign="top">

### 🏆 Leaderboard & analytics
SQL **views** with `RANK()` window functions power the leaderboard, real-play difficulty per puzzle, and the "which color gets solved when" chart.

</td>
<td valign="top">

### 🟨 Shareable result grid
The classic 🟨🟩🟦🟪 emoji grid, rebuilt after the game from a **4-table join** and copied to the clipboard in one tap.

</td>
</tr>
<tr>
<td valign="top">

### 📅 Any puzzle, any day
Play a random puzzle, the latest one, or pick **any date** from Jun 2023 to today. The archive tops itself up with an idempotent ETL.

</td>
<td valign="top">

### ⚡ Indexed & benchmarked
Reverse-junction B-tree and **GIN trigram** indexes, each justified with `EXPLAIN ANALYZE`, for **up to 11.7× faster** queries.

</td>
</tr>
<tr>
<td valign="top">

### 📱 Responsive & animated
A dark glass UI with a deal-in animation, a shake on misses and confetti on wins. It works on phones too. No framework and no build step.

</td>
<td valign="top">

### ☁️ Deployed on free tiers
FastAPI on **Render** and PostgreSQL on **Neon**. Every push to `main` redeploys automatically.

</td>
</tr>
</table>

<p align="right"><a href="#readme-top">⬆ back to top</a></p>

## 🖼️ Screenshots

<table>
<tr>
<td width="50%"><img src="docs/assets/screen-home.png" alt="Start screen"><p align="center"><b>Start</b>: pick a name, then a random puzzle, the latest one, or any date</p></td>
<td width="50%"><img src="docs/assets/screen-game.png" alt="Game in progress"><p align="center"><b>Play</b>: two groups found, four tiles selected, one mistake used</p></td>
</tr>
<tr>
<td width="50%"><img src="docs/assets/screen-solver.png" alt="Solver assistant"><p align="center"><b>Solver</b>: past categories that overlap today's grid</p></td>
<td width="50%"><img src="docs/assets/screen-win.png" alt="Win screen"><p align="center"><b>Win</b>: share grid rebuilt from the guess history</p></td>
</tr>
<tr>
<td colspan="2" align="center"><img src="docs/assets/screen-mobile.png" alt="Mobile layout" width="260"><p align="center"><b>Mobile</b>: the same game on a phone-sized screen</p></td>
</tr>
</table>

## 🕹️ How to play

| Color | Difficulty | Example from the archive |
|:---:|---|---|
| 🟨 **Yellow** | straightforward | "DON'T DELAY!": HURRY, NOW, PRONTO, STAT |
| 🟩 **Green** | getting warmer | OCEAN PHENOMENA: CURRENT, DRIFT, TIDE, WAVE |
| 🟦 **Blue** | think harder | DUMBBELL EXERCISES: CURL, FLY, PRESS, ROW |
| 🟪 **Purple** | the twist | PHILOSOPHER HOMOPHONES: LOCK, MARKS, PANE, RUSTLE |

1. Select **four words** you think share a hidden connection, then press **Submit**.
2. A correct group locks in and is revealed in its color.
3. A wrong group costs one of your **four mistakes**. If three of the four were right, you'll see **"One away!"**
4. Repeating an earlier guess is free: it's detected and rejected without a penalty.
5. Find all four groups to win. Stuck? Open the **Solver** tab for hints mined from history.

<p align="right"><a href="#readme-top">⬆ back to top</a></p>

---

## 🧭 How it works

### Architecture

One FastAPI service serves **both** the static frontend and the JSON API. All state lives in PostgreSQL.

```mermaid
flowchart TB
    UI["🖥️ Browser<br/>vanilla JS: index.html · game.js · style.css"]

    subgraph App["☁️ Render · FastAPI"]
        STATIC["StaticFiles mount<br/>serves /frontend"]
        API["REST API<br/>backend/main.py"]
        POOL["psycopg connection pool<br/>health-checked connections"]
    end

    subgraph DB["🐘 Neon · PostgreSQL 18"]
        ARCHIVE[("Puzzle archive<br/>puzzles · categories<br/>words · category_words")]
        PLAY[("Gameplay<br/>players · game_sessions<br/>guesses · guess_words")]
        VIEWS[["Analytics views<br/>v_leaderboard · v_puzzle_difficulty<br/>v_color_stats · v_word_ambiguity"]]
    end

    SRC["📦 Community archive JSON"] --> ETL["🔄 etl/load_data.py"]

    UI -- "GET /" --> STATIC
    UI -- "fetch /api/*" --> API
    API --> POOL
    POOL --> ARCHIVE & PLAY & VIEWS
    ETL -- "idempotent upsert" --> ARCHIVE
```

| Layer | What it does | Key file |
|---|---|---|
| **Frontend** | Renders the board, runs animations and calls the API. It holds **no answers**. | [`frontend/game.js`](frontend/game.js) |
| **API** | Validates every guess with SQL, records gameplay and exposes the solver | [`backend/main.py`](backend/main.py) |
| **Connection pool** | Reuses connections, and tests each one before use so the app survives Neon's idle suspend | [`backend/db.py`](backend/db.py) |
| **Database** | 8 tables in 3NF, 7 indexes and 4 views | [`db/`](db) |
| **ETL** | Downloads, cleans and loads the archive. Safe to re-run. | [`etl/load_data.py`](etl/load_data.py) |

### Life of a guess

The browser only ever sends four words. The server decides everything else.

```mermaid
sequenceDiagram
    autonumber
    actor P as Player
    participant UI as game.js
    participant API as FastAPI · POST /api/guess
    participant DB as PostgreSQL

    P->>UI: select 4 tiles, press Submit
    UI->>API: { session_id, words[4] }
    API->>DB: load session (mistakes, finished?)
    API->>DB: map the 4 words to their categories in this puzzle
    API->>DB: fetch earlier guesses of this session
    alt same 4 words as an earlier guess
        API-->>UI: { duplicate: true }, no penalty
    else a new guess
        API->>DB: INSERT guesses + 4 guess_words rows
        alt all 4 words share one category
            API->>DB: count solved groups, mark the game won at 4
            API-->>UI: { correct: true, category, game_over }
        else 3 of 4 share a category, or worse
            API->>DB: mistakes + 1, mark the game lost at 4
            API-->>UI: { correct: false, one_away, mistakes }
        end
    end
    UI-->>P: lock the group in, shake, "One away!" or confetti
```

### Game state machine

Each game session moves through three states, and the `game_sessions` row records exactly where it is.

```mermaid
stateDiagram-v2
    direction LR
    [*] --> Playing: POST /api/session
    Playing --> Playing: correct, wrong or duplicate guess
    Playing --> Won: 4th group found
    Playing --> Lost: 4th mistake
    Won --> Summary: share grid
    Lost --> Summary: share grid + full solution
    Summary --> [*]: Play again
```

| State | `solved` | `finished_at` | `mistakes` |
|---|:---:|:---:|:---:|
| Playing | `NULL` | `NULL` | 0–3 |
| Won | `TRUE` | set | 0–3 |
| Lost | `FALSE` | set | 4 |

<p align="right"><a href="#readme-top">⬆ back to top</a></p>

---

## 🗄️ Database design

The schema has two halves. The **puzzle content** is the historical archive the solver reasons over. The **gameplay** half holds the rows created by people playing.

```mermaid
erDiagram
    puzzles ||--|{ categories : "has 4"
    categories ||--|{ category_words : contains
    words ||--o{ category_words : "appears in"
    players ||--o{ game_sessions : plays
    puzzles ||--o{ game_sessions : "is played in"
    game_sessions ||--o{ guesses : records
    guesses ||--|{ guess_words : "made of 4"
    words ||--o{ guess_words : "used in"
    categories |o--o{ guesses : "matched by"

    puzzles {
        int puzzle_id PK
        int nyt_number UK
        date puzzle_date UK
    }
    categories {
        int category_id PK
        int puzzle_id FK
        text name
        smallint difficulty "0-3, unique per puzzle"
    }
    words {
        int word_id PK
        text word_text UK
    }
    category_words {
        int category_id PK, FK
        int word_id PK, FK
    }
    players {
        int player_id PK
        text username UK
        timestamptz created_at
    }
    game_sessions {
        int session_id PK
        int player_id FK
        int puzzle_id FK
        smallint mistakes
        boolean solved
        timestamptz started_at
        timestamptz finished_at
    }
    guesses {
        int guess_id PK
        int session_id FK
        smallint guess_number
        boolean is_correct
        boolean is_one_away
        int matched_category_id FK
    }
    guess_words {
        int guess_id PK, FK
        int word_id PK, FK
    }
```

### Why relational, and why 3NF

The solver's value comes from **relationships across puzzles**: the same word linked to many categories over the years. In a document store each puzzle would be a self-contained blob, and every cross-puzzle question would mean a full scan. In this schema, those questions are **index-backed joins**.

| Normal form | How the schema satisfies it |
|---|---|
| **1NF** | No repeating groups. A category's 4 words are rows in `category_words`, and a guess's 4 words are rows in `guess_words`, never array columns. |
| **2NF** | The only composite-key tables (`category_words`, `guess_words`) have no non-key attributes, so partial dependencies are impossible. |
| **3NF** | No transitive dependencies. Color depends only on `categories.difficulty`, dates live only in `puzzles`, and word text lives only in `words`. |

> 💡 **The key decision is the canonical vocabulary table.** Each word is stored **exactly once, ever**, and every appearance is a `(category_id, word_id)` pair. That turns *"has HEAT ever been grouped with JAZZ?"* into a 3-way index join instead of a string search over every puzzle.

**Integrity is enforced by the database itself:**
- `UNIQUE (puzzle_id, difficulty)` gives one category per color per puzzle.
- `CHECK (difficulty BETWEEN 0 AND 3)` and `CHECK (mistakes BETWEEN 0 AND 4)`.
- `UNIQUE (session_id, guess_number)` keeps guesses strictly ordered.
- Foreign keys with `ON DELETE CASCADE`, so removing a player cleans up their whole history.

<p align="right"><a href="#readme-top">⬆ back to top</a></p>

---

## 🧠 The SQL solver

Every hint is a live query over the **other** puzzles in the archive. The puzzle being solved is always excluded (`c.puzzle_id <> :pid`), so the solver can only reason from history.

```mermaid
flowchart LR
    W["🔤 A word you type"] --> S1
    G["🎯 Today's 16 grid words"] --> S2 & S3 & S4
    T["💭 A theme you suspect"] --> S5

    subgraph Solver["Each signal is one SQL query, with the current puzzle excluded"]
        S1["S1 · Word history<br/>3-table join"]
        S2["S2 · Pair signals<br/>self-join + COUNT"]
        S3["S3 · Candidate groups<br/>CTE + HAVING ≥ 2"]
        S4["S4 · Trap words<br/>RANK() window"]
        S5["S5 · Theme hypothesis<br/>pg_trgm similarity"]
    end

    S1 & S2 & S3 & S4 & S5 --> H["💡 Hints in the Solver tab"]
```

| # | Signal | SQL techniques | What it tells you | Endpoint |
|:---:|---|---|---|---|
| S1 | **Word history** | 3-table inner join | What a word has meant before | `/api/solver/word-history` |
| S2 | **Pair signals** | self-join + aggregation | Grid word pairs that were grouped together before | `/api/solver/co-occurrence` |
| S3 | **Candidate groups** | CTE + `HAVING COUNT(*) >= 2` + `ARRAY_AGG` | Past categories overlapping today's grid: the strongest signal | `/api/solver/candidates` |
| S4 | **Trap words** | aggregation + `RANK()` window | Which grid words are historically ambiguous | `/api/solver/trap-words` |
| S5 | **Theme hypothesis** | `pg_trgm` `similarity()` + GIN index | Whether your theory has precedent | `/api/solver/theme` |
| S6 | Archive analytics | date range + `GROUP BY` | Meta-statistics over the archive | psql only |
| S7 | Difficulty extremes | correlated `EXISTS` | Words that were both a Yellow and a Purple answer | psql only |

### 🔍 A real example: puzzle #762 (2025-07-12)

Asking for **candidate groups** on this grid returns past categories such as:

| Past category | Seen on | Matched grid words |
|---|---|---|
| ENDORSE | 2026-06-20 | BACK, CHAMPION, SUPPORT |
| SUPPORT | 2026-04-02 | BACK, CHAMPION, SECOND |
| PERIOD | 2024-02-29 | AGE, DAY, TIME |

Put the first two rows together and you get **BACK · CHAMPION · SECOND · SUPPORT**, which is exactly today's 🟨 group *(ENDORSE)*. The third row gives 3 of the 4 words in the 🟦 group *(ERA)*. History alone gets you most of the way to two groups, without the solver ever reading today's answers.

<details>
<summary><b>Show the SQL behind "Candidate groups" (S3)</b></summary>

```sql
WITH grid AS (                       -- the 16 words on today's board
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
JOIN category_words cw ON cw.word_id    = g.word_id      -- walks word → categories
JOIN categories c      ON c.category_id = cw.category_id --   (reverse junction index)
JOIN puzzles p         ON p.puzzle_id   = c.puzzle_id
WHERE c.puzzle_id <> %(pid)s                             -- never look at today's answers
GROUP BY c.category_id, c.name, p.puzzle_date
HAVING COUNT(*) >= 2
ORDER BY grid_words_matched DESC, seen_on DESC
LIMIT 15;
```

All seven solver queries, parameterized and runnable in `psql`, are in [`db/04_solver_queries.sql`](db/04_solver_queries.sql).

</details>

<p align="right"><a href="#readme-top">⬆ back to top</a></p>

---

## 📊 Data & insights

These numbers are queried straight from the production database.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/chart-kpis-dark.png">
  <img src="docs/assets/chart-kpis-light.png" alt="Archive by the numbers: 1,210 puzzles, 4,840 categories, 8,761 distinct words, 19,360 word appearances, 40.7% of words reappear, 85% of grids have a solver lead" width="100%">
</picture>

<br/><br/>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/chart-reuse-dark.png">
  <img src="docs/assets/chart-reuse-light.png" alt="Column chart: 5,198 words seen once; 1,437 seen twice; 739 three times; 681 four to five times; 516 six to nine times; 190 ten or more times" width="100%">
</picture>

<details>
<summary>View as a table</summary>

| Times a word has appeared | Distinct words |
|---|---:|
| Once | 5,198 |
| 2× | 1,437 |
| 3× | 739 |
| 4–5× | 681 |
| 6–9× | 516 |
| 10+× | 190 |
| **Total** | **8,761** |

**40.7%** of words appear more than once, and the average word appears **2.2×**. For **85.4%** of puzzles, at least one past category shares 2+ words with the grid (**50.7%** share 3+).

</details>

<br/>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/chart-traps-dark.png">
  <img src="docs/assets/chart-traps-light.png" alt="Bar chart of the most frequent words: BALL 30 categories, RING 25, BAR 22, FLY 22, CHECK 21, LEAD 20, BLUE 19, JACK 19, WING 19, CAN 18, HEART 18, HOOK 18" width="100%">
</picture>

<details>
<summary>View as a table</summary>

| Word | Categories appeared in | Distinct themes |
|---|---:|---:|
| BALL | 30 | 25 |
| RING | 25 | 23 |
| BAR | 22 | 22 |
| FLY | 22 | 18 |
| CHECK | 21 | 18 |
| LEAD | 20 | 18 |
| BLUE | 19 | 19 |
| JACK | 19 | 16 |
| WING | 19 | 17 |
| CAN | 18 | 16 |
| HEART | 18 | 18 |
| HOOK | 18 | 15 |

Most repeated category names: **ANAGRAMS** and **HOMOPHONES** (10 each), **FISH** (8), and **MAGAZINES**, **PALINDROMES** and **THINGS THAT ARE RED** (6 each).

</details>

<p align="right"><a href="#readme-top">⬆ back to top</a></p>

---

## ⚡ Indexing & performance

Each index was **proven** with `EXPLAIN ANALYZE`. The index is dropped **inside a transaction that is rolled back**, so both plans run on identical data and the database is left untouched ([`db/05_benchmark.sql`](db/05_benchmark.sql)).

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/chart-bench-dark.png">
  <img src="docs/assets/chart-bench-light.png" alt="Dumbbell chart: word to categories join 2.62 ms to 0.47 ms (5.6x faster); grid co-occurrence self-join 2.50 ms to 0.65 ms (3.8x); fuzzy theme search 16.79 ms to 1.43 ms (11.7x)" width="100%">
</picture>

| Index | Type | Why it exists |
|---|---|---|
| `idx_category_words_word` on `category_words(word_id)` | B-tree | The PK only serves category → words, but **every solver query walks word → categories**. This is the most important index in the system. |
| `idx_categories_puzzle` on `categories(puzzle_id)` | B-tree | Grid assembly: fetch a puzzle's 4 categories. |
| `idx_categories_name_trgm` on `categories(name)` | GIN (`pg_trgm`) | Fuzzy theme search over 4,840 category names. |
| `idx_words_text_trgm` on `words(word_text)` | GIN (`pg_trgm`) | Fuzzy word lookup. |
| `idx_sessions_player`, `idx_sessions_puzzle`, `idx_guesses_session` | B-tree | Leaderboard and analytics joins. |

<details>
<summary><b>Indexes deliberately <i>not</i> created, and an optimizer plot twist</b></summary>

**Not created:**
- `puzzles(puzzle_date)`, `words(word_text)`, `players(username)`: their `UNIQUE` constraints already create B-tree indexes.
- `categories(difficulty)`: only 4 distinct values, far too unselective to help.
- `guess_words(word_id)`: rarely queried, and it sits on the hottest insert path.

**The plot twist (B3):** with the GIN index present, the planner **still chose a sequential scan**. Its I/O-centric cost model underestimates how CPU-expensive `similarity()` is per row. Forcing the index with `SET enable_seqscan = off` proved the GIN plan is **11.7× faster**. The lesson: on small but CPU-heavy predicates, the ground truth is a measured `EXPLAIN ANALYZE`, not the optimizer's estimate.

</details>

<p align="right"><a href="#readme-top">⬆ back to top</a></p>

---

## 🔄 Data pipeline (ETL)

```mermaid
flowchart TB
    A["🌐 Download the community archive JSON"] --> B["💾 Cache it to data/connections.json"]
    B --> C{"🧹 Clean each puzzle"}
    C -- "difficulty levels missing<br/>(puzzle #832 onwards)" --> D["Assign difficulty<br/>by answer position"]
    C -- "fewer than 16 distinct words" --> E["⛔ Skip the puzzle<br/>(#660 April Fools)"]
    C -- "valid" --> F["⬆️ Upsert in dependency order<br/>puzzles → words →<br/>categories → category_words"]
    D --> F
    F --> G["📈 Row-count report"]
```

- **Idempotent:** every insert is `ON CONFLICT DO NOTHING`, so the same script does the first load *and* later top-ups.
- **Missing difficulty levels:** from puzzle #832 the archive stopped recording levels (all `-1`). The answers are still ordered Yellow to Purple, so the ETL assigns difficulty by position.
- **Unrecoverable puzzle:** the 2025-04-01 April Fools puzzle (#660) used symbol-only "words" that the archive stored as empty strings, so it is skipped.
- The schema's `CHECK` constraints caught both of these problems during the first load.

<p align="right"><a href="#readme-top">⬆ back to top</a></p>

---

## 🔌 API reference

Interactive Swagger docs are live at **[/api/docs](https://linklogic-ctji.onrender.com/api/docs)**.

| Method | Endpoint | Purpose |
|:---:|---|---|
| `GET` | `/api/meta` | Puzzle count and date range of the archive |
| `GET` | `/api/puzzle/random` | A random puzzle with its 16 shuffled words |
| `GET` | `/api/puzzle/by-date/{date}` | The puzzle for a given `YYYY-MM-DD` |
| `POST` | `/api/session` | Start a game: `{ "username", "puzzle_id" }` |
| `POST` | `/api/guess` | Submit a guess: `{ "session_id", "words": [4] }` |
| `GET` | `/api/session/{id}/summary` | Share grid of a **finished** game, so answers never leak mid-game |
| `GET` | `/api/stats/leaderboard` | Top 10 players (`v_leaderboard`) |
| `GET` | `/api/stats/colors` | Average solve position per color (`v_color_stats`) |
| `GET` | `/api/stats/hardest` | Hardest puzzles by real play (`v_puzzle_difficulty`) |
| `GET` | `/api/solver/word-history?word=` | S1: every past appearance of a word |
| `GET` | `/api/solver/co-occurrence?puzzle_id=` | S2: grid word pairs grouped together before |
| `GET` | `/api/solver/candidates?puzzle_id=` | S3: past categories overlapping the grid |
| `GET` | `/api/solver/trap-words?puzzle_id=` | S4: the grid's most ambiguous words |
| `GET` | `/api/solver/theme?q=&exclude_puzzle_id=` | S5: fuzzy-match a theme against past categories |

<details>
<summary>Example: submitting a guess</summary>

```bash
curl -X POST https://linklogic-ctji.onrender.com/api/guess \
     -H "Content-Type: application/json" \
     -d '{"session_id": 42, "words": ["HURRY", "NOW", "PRONTO", "STAT"]}'
```

```json
{
  "duplicate": false,
  "correct": true,
  "one_away": false,
  "game_over": false,
  "won": null,
  "mistakes": 0,
  "category": {
    "name": "“DON’T DELAY!”",
    "difficulty": 0,
    "color": "Yellow",
    "words": ["HURRY", "NOW", "PRONTO", "STAT"]
  }
}
```

</details>

<p align="right"><a href="#readme-top">⬆ back to top</a></p>

---

## 📁 Project structure

```text
LinkLogic---NYT-Connections/
├── backend/
│   ├── main.py                 # FastAPI app: game rules, stats, solver, static mount
│   └── db.py                   # health-checked psycopg connection pool
├── frontend/
│   ├── index.html              # start, game, solver and stats screens
│   ├── game.js                 # UI state, animations, API calls (no framework)
│   └── style.css               # dark glass theme in the four Connections colors
├── db/
│   ├── 01_schema.sql           # 3NF schema: archive + gameplay tables
│   ├── 02_indexes.sql          # B-tree + GIN trigram indexes, with rationale
│   ├── 03_views.sql            # leaderboard, difficulty, ambiguity, color views
│   ├── 04_solver_queries.sql   # the solver as runnable SQL (S1–S7)
│   └── 05_benchmark.sql        # EXPLAIN ANALYZE proof for each index
├── etl/
│   └── load_data.py            # download → clean → idempotent load
├── docs/
│   ├── design.md               # full design document: ER, 3NF, benchmarks
│   └── assets/                 # README images, charts and demo GIF
├── render.yaml                 # Render blueprint (free web service)
├── requirements.txt            # Python dependencies
├── .python-version             # Python 3.14
└── .env.example                # DATABASE_URL template
```

<p align="right"><a href="#readme-top">⬆ back to top</a></p>

---

## 🚀 Getting started

### Prerequisites

- **Python 3.11+** (3.14 recommended)
- **PostgreSQL 14+** running locally (tested on 18), **or** a free [Neon](https://neon.tech) database

### 1. Clone and install

```bash
git clone https://github.com/sehscape/LinkLogic---NYT-Connections.git
cd LinkLogic---NYT-Connections
python -m venv .venv
```

Activate the environment, using **one** of these:

```bash
.venv\Scripts\activate          # Windows
source .venv/bin/activate       # macOS / Linux
```

```bash
pip install -r requirements.txt
```

### 2. Create the database

```bash
psql -U postgres -c "CREATE DATABASE linklogic"
psql -U postgres -d linklogic -f db/01_schema.sql -f db/02_indexes.sql -f db/03_views.sql
```

### 3. Configure

Copy `.env.example` to `.env`, then set your connection string:

```ini
DATABASE_URL=postgresql://postgres:YOUR_PASSWORD@localhost:5432/linklogic
```

### 4. Load the puzzle archive

```bash
python etl/load_data.py
```

```text
Archive contains 1211 puzzles.
  skipping malformed puzzle #660 (2025-04-01)
1210 puzzles remain after cleaning.
Load complete:
  puzzles             1210 rows
  categories          4840 rows
  words               8761 rows
  category_words     19360 rows
```

### 5. Play

```bash
uvicorn backend.main:app --reload
```

Open **http://127.0.0.1:8000** to play, or **http://127.0.0.1:8000/api/docs** to explore the API.

> 🔁 **New puzzles come out daily.** Delete `data/connections.json` and re-run `python etl/load_data.py`. Only the new puzzles are added.

<p align="right"><a href="#readme-top">⬆ back to top</a></p>

---

## ☁️ Deployment

The live site runs entirely on free tiers.

```mermaid
flowchart LR
    DEV["💻 git push"] --> GH["🐙 GitHub<br/>main branch"]
    GH -- "auto-deploy" --> R["☁️ Render web service<br/>pip install → uvicorn"]
    U["👥 Players"] -- "HTTPS" --> R
    R -- "DATABASE_URL over TLS" --> N[("🐘 Neon PostgreSQL<br/>Singapore")]
    L["🛠️ Local machine"] -- "schema + ETL<br/>(one-time)" --> N
```

1. **Neon:** create a project in the Singapore region and copy the **direct** (non-pooled) connection string.
2. **Load the data** from your machine, with that connection string in `.env`:
   ```bash
   psql "<neon-url>" -f db/01_schema.sql -f db/02_indexes.sql -f db/03_views.sql
   python etl/load_data.py
   ```
3. **Render:** choose **New → Blueprint** and pick this repo. [`render.yaml`](render.yaml) sets the build and start commands. Paste the Neon string when asked for `DATABASE_URL`.

| Detail | Behaviour |
|---|---|
| **Auto-deploy** | Every push to `main` triggers a new build. |
| **Cold start** | The free Render instance sleeps after ~15 min idle, so the first visit takes up to a minute to wake it. |
| **Idle database** | Neon suspends after ~5 min idle. The pool checks each connection before use, so no request fails. |
| **Health check** | `/` serves the static page, so Render's checks never wake the database. |

> ⚠️ `db/01_schema.sql` **drops and recreates** every table. Run it once on a new database, never on a live one.

<p align="right"><a href="#readme-top">⬆ back to top</a></p>

---

## 🧰 Tech stack

| Area | Technology |
|---|---|
| **Database** | PostgreSQL 18 · `pg_trgm` · views · window functions · CTEs |
| **Backend** | Python 3.14 · FastAPI · Uvicorn · psycopg 3 · psycopg-pool |
| **Frontend** | HTML · CSS (glass UI, keyframe animations) · vanilla JavaScript |
| **Data** | `requests` ETL · JSON archive · idempotent upserts |
| **Hosting** | Render (web service) · Neon (serverless Postgres) |

---

## 🙏 Acknowledgements

- Puzzle data comes from the community-maintained **[NYT-Connections-Answers](https://github.com/Eyefyre/NYT-Connections-Answers)** archive.
- *Connections* is a game by **The New York Times**. This is an independent educational project and is **not affiliated with or endorsed by The New York Times**.
- Fonts: [Outfit](https://fonts.google.com/specimen/Outfit) and [Space Grotesk](https://fonts.google.com/specimen/Space+Grotesk).

<div align="center">

<br/>

**If you enjoyed it, give the repo a ⭐ and [play today's puzzle](https://linklogic-ctji.onrender.com)!**

<sub>Made with 🐘 PostgreSQL and ☕ by <a href="https://github.com/sehscape">Sehal Chodankar</a></sub>

<p><a href="#readme-top">⬆ back to top</a></p>

</div>
