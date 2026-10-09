/* Link Logic — game + solver UI. All rules are enforced server-side;
   this file renders state, orchestrates animations, and calls the API. */

const $ = (sel) => document.querySelector(sel);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const state = {
  username: "",
  puzzle: null,        // {puzzle_id, nyt_number, puzzle_date, words}
  sessionId: null,
  remaining: [],       // words still on the board
  selected: new Set(),
  mistakes: 0,
  solved: [],          // [{name, difficulty, words}]
  gameOver: false,
  latestDate: null,
  busy: false,         // guards double submits during animations
};

/* ------------------------------ helpers ------------------------------ */

async function api(path, options) {
  const res = await fetch(path, options);
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body.detail || `Request failed (${res.status})`);
  return body;
}

function esc(s) {
  const div = document.createElement("div");
  div.textContent = String(s);
  return div.innerHTML;
}

let toastTimer = null;
function toast(msg, type = "", ms = 1900) {
  const el = $("#toast");
  el.textContent = msg;
  el.className = type;                 // resets previous variant
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.add("hidden"), ms);
}

function htmlTable(headers, rowsHtml) {
  if (!rowsHtml.length) return `<p class="muted">No matches found in the archive.</p>`;
  return `<table><thead><tr>${headers.map((h) => `<th>${esc(h)}</th>`).join("")}</tr></thead>
          <tbody>${rowsHtml.join("")}</tbody></table>`;
}

const colorBadge = (difficulty, color) =>
  `<span class="badge diff-${difficulty}">${esc(color || "")}</span>`;

/* ------------------------------ tabs ------------------------------ */

document.querySelectorAll(".tab").forEach((btn) =>
  btn.addEventListener("click", () => {
    document.querySelectorAll(".tab").forEach((b) => b.classList.remove("active"));
    btn.classList.add("active");
    ["game", "solver", "stats"].forEach((name) =>
      $(`#screen-${name}`).classList.toggle("hidden", name !== btn.dataset.tab)
    );
    $("#screen-start").classList.add("hidden");
    if (btn.dataset.tab === "stats") loadStats();
  })
);

/* ------------------------------ start ------------------------------ */

async function init() {
  try {
    const meta = await api("/api/meta");
    state.latestDate = meta.last_date;
    $("#meta-line").textContent =
      `${meta.puzzle_count} puzzles in the database — ${meta.first_date} to ${meta.last_date}.`;
    $("#pick-date").min = meta.first_date;
    $("#pick-date").max = meta.last_date;
    $("#pick-date").value = meta.last_date;
  } catch (err) {
    $("#start-error").textContent = "API not reachable: " + err.message;
  }
}

async function startGame(fetchPuzzle) {
  const username = $("#username").value.trim();
  $("#start-error").textContent = "";
  if (!username) {
    $("#start-error").textContent = "Enter a player name first.";
    $("#username").focus();
    return;
  }
  try {
    const puzzle = await fetchPuzzle();
    const session = await api("/api/session", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username, puzzle_id: puzzle.puzzle_id }),
    });
    Object.assign(state, {
      username,
      puzzle,
      sessionId: session.session_id,
      remaining: [...puzzle.words],
      selected: new Set(),
      mistakes: 0,
      solved: [],
      gameOver: false,
      busy: false,
    });
    $("#screen-start").classList.add("hidden");
    $("#tabs").classList.remove("hidden");
    $("#screen-game").classList.remove("hidden");
    $("#overlay").classList.add("hidden");
    $("#puzzle-info").innerHTML =
      `<span>Puzzle #${esc(puzzle.nyt_number)}</span>` +
      `<span>${esc(puzzle.puzzle_date)}</span>` +
      `<span>&#127918; ${esc(username)}</span>`;
    renderAll({ deal: true });
  } catch (err) {
    $("#start-error").textContent = err.message;
  }
}

$("#btn-random").addEventListener("click", () =>
  startGame(() => api("/api/puzzle/random"))
);
$("#btn-bydate").addEventListener("click", () =>
  startGame(() => api(`/api/puzzle/by-date/${$("#pick-date").value}`))
);
$("#btn-latest").addEventListener("click", () =>
  startGame(() => api(`/api/puzzle/by-date/${state.latestDate}`))
);

/* ------------------------------ board ------------------------------ */

function renderAll(opts = {}) {
  renderSolved();
  renderGrid(opts);
  renderDots();
}

function renderSolved() {
  $("#solved-groups").innerHTML = state.solved
    .map(
      (g) => `<div class="group-bar diff-${g.difficulty}">
                <div class="g-name">${esc(g.name)}</div>
                <div class="g-words">${g.words.map(esc).join(", ")}</div>
              </div>`
    )
    .join("");
}

function renderGrid({ deal = false } = {}) {
  const grid = $("#grid");
  grid.innerHTML = "";
  state.remaining.forEach((word, i) => {
    const tile = document.createElement("button");
    tile.className = "tile" + (word.length > 7 ? " len-long" : "");
    tile.textContent = word;
    if (deal) {
      tile.classList.add("deal");
      tile.style.animationDelay = `${i * 45}ms`;
    }
    if (state.selected.has(word)) tile.classList.add("selected");
    tile.addEventListener("click", () => {
      if (state.gameOver || state.busy) return;
      if (state.selected.has(word)) state.selected.delete(word);
      else if (state.selected.size < 4) state.selected.add(word);
      else return;
      tile.classList.toggle("selected");
      updateSubmit();
    });
    grid.appendChild(tile);
  });
  updateSubmit();
}

function updateSubmit() {
  const btn = $("#btn-submit");
  btn.disabled = state.selected.size !== 4 || state.gameOver || state.busy;
  btn.classList.toggle("ready", !btn.disabled);
}

function renderDots() {
  $("#dots").innerHTML = [0, 1, 2, 3]
    .map((i) => `<i class="${i < state.mistakes ? "lost" : ""}"></i>`)
    .join("");
}

function popDot(index) {
  const dot = document.querySelectorAll("#dots i")[index];
  if (!dot) return;
  dot.classList.add("popping");
  setTimeout(() => { dot.classList.remove("popping"); dot.classList.add("lost"); }, 420);
}

function shakeSelected() {
  document.querySelectorAll(".tile.selected").forEach((t) => t.classList.add("shake"));
  setTimeout(
    () => document.querySelectorAll(".tile.shake").forEach((t) => t.classList.remove("shake")),
    450
  );
}

$("#btn-shuffle").addEventListener("click", () => {
  if (state.busy) return;
  for (let i = state.remaining.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [state.remaining[i], state.remaining[j]] = [state.remaining[j], state.remaining[i]];
  }
  renderGrid({ deal: true });
});

$("#btn-deselect").addEventListener("click", () => {
  state.selected.clear();
  renderGrid();
});

/* ------------------------------ guessing ------------------------------ */

$("#btn-submit").addEventListener("click", async () => {
  if (state.selected.size !== 4 || state.gameOver || state.busy) return;
  state.busy = true;
  updateSubmit();
  try {
    const result = await api("/api/guess", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ session_id: state.sessionId, words: [...state.selected] }),
    });
    await handleGuessResult(result);
  } catch (err) {
    toast(err.message);
  } finally {
    state.busy = false;
    updateSubmit();
  }
});

async function handleGuessResult(result) {
  if (result.duplicate) {
    toast("Already guessed!", "warn");
    return;
  }

  if (result.correct) {
    // let the four tiles celebrate before they leave the board
    document.querySelectorAll(".tile.selected").forEach((t, i) => {
      t.style.animationDelay = `${i * 70}ms`;
      t.classList.add("solving");
    });
    await sleep(560);
    state.solved.push(result.category);
    state.remaining = state.remaining.filter((w) => !result.category.words.includes(w));
    state.selected.clear();
    renderAll();
    if (result.game_over && result.won) endGame(true);
    return;
  }

  // wrong guess
  shakeSelected();
  const lostIndex = result.mistakes - 1;
  state.mistakes = result.mistakes;
  popDot(lostIndex);
  if (result.one_away) toast("One away!", "warn");

  if (result.game_over && !result.won) {
    await sleep(650);
    const found = new Set(state.solved.map((g) => g.name));
    (result.solution || []).forEach((g) => {
      if (!found.has(g.name)) state.solved.push(g);
    });
    state.remaining = [];
    state.selected.clear();
    renderAll();
    endGame(false);
  }
}

/* ------------------------------ end of game ------------------------------ */

const EMOJI = { 0: "\u{1F7E8}", 1: "\u{1F7E9}", 2: "\u{1F7E6}", 3: "\u{1F7EA}" };

async function endGame(won) {
  state.gameOver = true;
  let summary = null;
  try {
    summary = await api(`/api/session/${state.sessionId}/summary`);
  } catch { /* overlay still works without the share grid */ }

  const headline = won
    ? state.mistakes === 0 ? "Perfect!" : state.mistakes === 1 ? "Brilliant!" : "You got it!"
    : "So close!";
  const emoji = won ? (state.mistakes === 0 ? "&#127942;" : "&#127881;") : "&#128148;";
  const sub = won
    ? `Solved with ${state.mistakes} mistake${state.mistakes === 1 ? "" : "s"}.`
    : "The full solution is on the board.";

  const gridHtml = summary
    ? `<div class="share-grid">` + summary.guesses
        .map((row, r) =>
          `<div class="share-row">` +
          row.map((d, i) => `<i class="d${d}" style="animation-delay:${(r * 4 + i) * 45}ms"></i>`).join("") +
          `</div>`
        ).join("") + `</div>`
    : "";

  $("#overlay-card").innerHTML = `
    <div class="big">${emoji}</div>
    <h3>${headline}</h3>
    <p class="sub">${esc(sub)}</p>
    ${gridHtml}
    <div class="overlay-actions">
      ${summary ? `<button id="btn-copy" class="btn btn-ghost">&#128203; Copy result</button>` : ""}
      <button id="btn-again" class="btn btn-primary">Play again</button>
    </div>`;
  $("#overlay").classList.remove("hidden");

  if (summary) {
    $("#btn-copy").addEventListener("click", () => {
      const lines = summary.guesses.map((row) => row.map((d) => EMOJI[d]).join(""));
      const text = `Link Logic #${summary.nyt_number} — ${summary.puzzle_date}\n` +
                   `${won ? "Solved" : "X"} · ${state.mistakes}/4 mistakes\n` + lines.join("\n");
      navigator.clipboard.writeText(text)
        .then(() => toast("Result copied!"))
        .catch(() => toast("Could not copy"));
    });
  }
  $("#btn-again").addEventListener("click", backToStart);

  if (won) confetti();
}

function backToStart() {
  $("#overlay").classList.add("hidden");
  $("#screen-game").classList.add("hidden");
  $("#screen-solver").classList.add("hidden");
  $("#screen-stats").classList.add("hidden");
  $("#tabs").classList.add("hidden");
  $("#screen-start").classList.remove("hidden");
  document.querySelectorAll(".tab").forEach((b) => b.classList.remove("active"));
  document.querySelector('.tab[data-tab="game"]').classList.add("active");
}

/* Tiny confetti burst in the four puzzle colors — no libraries. */
function confetti() {
  const canvas = $("#confetti");
  const ctx = canvas.getContext("2d");
  canvas.width = window.innerWidth;
  canvas.height = window.innerHeight;
  const colors = ["#ffd95e", "#9be15d", "#7fb3ff", "#d29bff", "#ffffff"];
  const pieces = Array.from({ length: 160 }, () => ({
    x: Math.random() * canvas.width,
    y: -20 - Math.random() * canvas.height * 0.4,
    w: 6 + Math.random() * 7,
    h: 8 + Math.random() * 8,
    vx: -1.6 + Math.random() * 3.2,
    vy: 2.2 + Math.random() * 3.4,
    rot: Math.random() * Math.PI,
    vr: -0.12 + Math.random() * 0.24,
    color: colors[(Math.random() * colors.length) | 0],
  }));
  const t0 = performance.now();
  (function frame(t) {
    const elapsed = t - t0;
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    if (elapsed > 3400 || $("#overlay").classList.contains("hidden")) return;
    ctx.globalAlpha = Math.min(1, (3400 - elapsed) / 700);
    for (const p of pieces) {
      p.x += p.vx; p.y += p.vy; p.rot += p.vr;
      ctx.save();
      ctx.translate(p.x, p.y);
      ctx.rotate(p.rot);
      ctx.fillStyle = p.color;
      ctx.fillRect(-p.w / 2, -p.h / 2, p.w, p.h);
      ctx.restore();
    }
    requestAnimationFrame(frame);
  })(t0);
}

/* ------------------------------ solver ------------------------------ */

function requirePuzzle() {
  if (!state.puzzle) {
    toast("Start a game first — the grid signals need a current puzzle.", "warn");
    return false;
  }
  return true;
}

function showSkeleton() {
  $("#solver-results").innerHTML =
    `<div class="skeleton">${"<i></i>".repeat(4)}</div>`;
}

function showSolverResult(title, html) {
  $("#solver-results").innerHTML = `<h4>${esc(title)}</h4>${html}`;
}

async function runSolver(btn, fetcher, render) {
  btn.disabled = true;
  showSkeleton();
  try {
    render(await fetcher());
  } catch (err) {
    $("#solver-results").innerHTML = "";
    toast(err.message);
  } finally {
    btn.disabled = false;
  }
}

$("#btn-word-history").addEventListener("click", (e) => {
  const word = $("#solver-word").value.trim();
  if (!word) return $("#solver-word").focus();
  runSolver(e.target,
    () => api(`/api/solver/word-history?word=${encodeURIComponent(word)}`),
    (rows) => showSolverResult(
      `History of "${word.toUpperCase()}" — ${rows.length} appearance${rows.length === 1 ? "" : "s"}`,
      htmlTable(
        ["Date", "Puzzle #", "Category", "Color"],
        rows.map(
          (r) => `<tr><td>${esc(r.puzzle_date)}</td><td>${esc(r.nyt_number)}</td>
                  <td>${esc(r.category)}</td><td>${colorBadge(r.difficulty, r.color)}</td></tr>`
        )
      )
    ));
});

$("#btn-candidates").addEventListener("click", (e) => {
  if (!requirePuzzle()) return;
  runSolver(e.target,
    () => api(`/api/solver/candidates?puzzle_id=${state.puzzle.puzzle_id}`),
    (rows) => showSolverResult(
      "Past categories overlapping this grid (2+ words)",
      htmlTable(
        ["Past category", "Seen on", "Matches", "Matched words"],
        rows.map(
          (r) => `<tr><td>${esc(r.past_category)}</td><td>${esc(r.seen_on)}</td>
                  <td>${esc(r.grid_words_matched)}</td><td>${r.matched_words.map(esc).join(", ")}</td></tr>`
        )
      )
    ));
});

$("#btn-pairs").addEventListener("click", (e) => {
  if (!requirePuzzle()) return;
  runSolver(e.target,
    () => api(`/api/solver/co-occurrence?puzzle_id=${state.puzzle.puzzle_id}`),
    (rows) => showSolverResult(
      "Grid word pairs that shared a category before",
      htmlTable(
        ["Word A", "Word B", "Times grouped together"],
        rows.map(
          (r) => `<tr><td>${esc(r.word_a)}</td><td>${esc(r.word_b)}</td>
                  <td>${esc(r.times_grouped)}</td></tr>`
        )
      )
    ));
});

$("#btn-traps").addEventListener("click", (e) => {
  if (!requirePuzzle()) return;
  runSolver(e.target,
    () => api(`/api/solver/trap-words?puzzle_id=${state.puzzle.puzzle_id}`),
    (rows) => showSolverResult(
      "Most ambiguous words on this grid (likely traps)",
      htmlTable(
        ["Rank", "Word", "Past appearances", "Distinct themes"],
        rows.map(
          (r) => `<tr><td>${esc(r.trap_rank)}</td><td>${esc(r.word_text)}</td>
                  <td>${esc(r.past_appearances)}</td><td>${esc(r.distinct_themes)}</td></tr>`
        )
      )
    ));
});

$("#btn-theme").addEventListener("click", (e) => {
  const q = $("#solver-theme").value.trim();
  if (!q) return $("#solver-theme").focus();
  const exclude = state.puzzle ? `&exclude_puzzle_id=${state.puzzle.puzzle_id}` : "";
  runSolver(e.target,
    () => api(`/api/solver/theme?q=${encodeURIComponent(q)}${exclude}`),
    (rows) => showSolverResult(
      `Category names similar to "${q}"`,
      htmlTable(
        ["Past category", "Similarity", "Date", "Its words"],
        rows.map(
          (r) => `<tr><td>${esc(r.past_category)}</td><td>${esc(r.sim)}</td>
                  <td>${esc(r.puzzle_date)}</td><td>${r.its_words.map(esc).join(", ")}</td></tr>`
        )
      )
    ));
});

/* ------------------------------ stats ------------------------------ */

const MEDALS = ["\u{1F947}", "\u{1F948}", "\u{1F949}"];
const COLOR_LABELS = { 0: "Yellow", 1: "Green", 2: "Blue", 3: "Purple" };

async function loadStats() {
  const [board, colors, hardest] = await Promise.all([
    api("/api/stats/leaderboard"),
    api("/api/stats/colors"),
    api("/api/stats/hardest"),
  ]);

  $("#stats-leaderboard").innerHTML = htmlTable(
    ["", "Player", "Wins", "Finished", "Avg mistakes"],
    board.map(
      (r, i) => `<tr><td class="medal">${MEDALS[i] || "#" + r.player_rank}</td>
              <td><b>${esc(r.username)}</b></td>
              <td>${esc(r.wins)}</td><td>${esc(r.games_finished)}</td>
              <td>${esc(r.avg_mistakes ?? "—")}</td></tr>`
    )
  );

  // horizontal bars: average guess position per color (longer = found later)
  $("#stats-colors").innerHTML = colors.length
    ? colors.map((r) => {
        const pct = Math.min(100, (r.avg_guess_position / 7) * 100);
        return `<div class="colorbar">
                  <span class="label">${esc(COLOR_LABELS[r.difficulty])}</span>
                  <span class="track"><span class="fill d${r.difficulty}" style="width:${pct}%"></span></span>
                  <span class="val">found on guess ${esc(r.avg_guess_position)} · ${esc(r.times_solved)}×</span>
                </div>`;
      }).join("") +
      `<p class="muted small" style="margin:0.6rem 0 0">Longer bar = found later — Purple should trend last.</p>`
    : `<p class="muted">Play some games first!</p>`;

  $("#stats-hardest").innerHTML = htmlTable(
    ["Puzzle #", "Date", "Attempts", "Avg mistakes", "Win rate"],
    hardest.map(
      (r) => `<tr><td>${esc(r.nyt_number)}</td><td>${esc(r.puzzle_date)}</td>
              <td>${esc(r.attempts)}</td><td>${esc(r.avg_mistakes ?? "—")}</td>
              <td>${r.win_rate_pct == null ? "—" : esc(r.win_rate_pct) + "%"}</td></tr>`
    )
  );
}

init();
