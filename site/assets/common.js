/* Shared helpers: data loading, number formatting, rank pills, stat cards, small SVG charts. */
const SEA = "SEA";
const DATA = "data/";

async function loadJSON(path) {
  const r = await fetch(DATA + path, { cache: "no-cache" });
  if (!r.ok) throw new Error(`${path}: ${r.status}`);
  return r.json();
}

const FMT = {
  num1: v => v.toLocaleString(undefined, { minimumFractionDigits: 1, maximumFractionDigits: 1 }),
  num2: v => v.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 }),
  int:  v => Math.round(v).toLocaleString(),
  pct:  v => (v * 100).toFixed(1) + "%",
  pct0: v => (v * 100).toFixed(0) + "%",
  epa:  v => (v > 0 ? "+" : "") + v.toFixed(3),
  epa2: v => (v > 0 ? "+" : "") + v.toFixed(2),
  time: v => `${Math.floor(v / 60)}:${String(Math.round(v % 60)).padStart(2, "0")}`,
  signed1: v => (v > 0 ? "+" : "") + v.toFixed(1),
};
function fmt(v, f = "num1") {
  if (v === null || v === undefined || Number.isNaN(v)) return "—";
  return (FMT[f] || FMT.num1)(v);
}
function esc(s) { return String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])); }

/* Rank color scale: top quarter / middle half / bottom quarter of the pool (8 / 16 / 8 for 32 teams). */
function rankClass(r, of = 32) {
  if (r === null || r === undefined) return "rank-na";
  const q = Math.max(1, Math.round(of / 4));
  return r <= q ? "rank-top" : r > of - q ? "rank-bot" : "rank-mid";
}
function rankPill(r, opts = {}) {
  const of = opts.of || 32;
  if (r === null || r === undefined) return `<span class="rank rank-na" title="${esc(opts.naTitle || "Not ranked")}">n/a</span>`;
  return `<span class="rank ${rankClass(r, of)}" title="Rank ${r} of ${of}">#${r}<span class="muted">/${of}</span></span>`;
}
function nLabel(n, kind) {
  if (n === null || n === undefined) return "";
  return `n=${fmt(n, "int")}${kind ? " " + kind : ""}`;
}

/* A stat card: value · rank/32 · league average, sample size on hover. */
function statCard(s, opts = {}) {
  const nKind = opts.nKind || "";
  const naTitle = s.ranked === false ? "Not a ranked stat" : (s.qualified === false ? `Below minimum attempts (${s.threshold})` : "Not ranked");
  return `<div class="card" title="${esc(nLabel(s.n, nKind))}">
    <div class="label">${esc(s.label)}</div>
    <div class="value">${fmt(s.value, s.fmt)}</div>
    <div class="row">${rankPill(s.rank, { naTitle })}<span>lg ${fmt(s.league_avg, s.fmt)}</span><span class="n">${esc(nLabel(s.n, nKind))}</span></div>
  </div>`;
}

function rankLegend() {
  return `<div class="legend-ranks"><span>Rank color:</span>
    <span class="rank rank-top">1–8</span><span class="rank rank-mid">9–24</span><span class="rank rank-bot">25–32</span>
    <span>· lg = league average · hover a card for sample size</span></div>`;
}

function toggle(id, options, current, onChange) {
  const el = document.getElementById(id);
  el.className = "toggle";
  el.innerHTML = options.map(o => `<button data-v="${esc(o.value)}" class="${String(o.value) === String(current) ? "on" : ""}">${esc(o.label)}</button>`).join("");
  el.querySelectorAll("button").forEach(b => b.addEventListener("click", () => {
    el.querySelectorAll("button").forEach(x => x.classList.toggle("on", x === b));
    onChange(b.dataset.v);
  }));
}

function resultClass(r) { return r === "W" ? "win" : r === "L" ? "loss" : r === "T" ? "tie" : ""; }
function fmtDate(iso) {
  if (!iso) return "";
  const d = new Date(iso + "T12:00:00");
  return d.toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" });
}
function fmtTime(hhmm) {
  if (!hhmm) return "";
  const [h, m] = hhmm.split(":").map(Number);
  const ampm = h >= 12 ? "PM" : "AM";
  return `${((h + 11) % 12) + 1}:${String(m).padStart(2, "0")} ${ampm} ET`;
}
function ageAt(birth, on) {
  if (!birth) return null;
  const b = new Date(birth), d = on ? new Date(on) : new Date();
  let a = d.getFullYear() - b.getFullYear();
  if (d.getMonth() < b.getMonth() || (d.getMonth() === b.getMonth() && d.getDate() < b.getDate())) a--;
  return a;
}

/* Single-series sparkline with hover tooltip. points: [{x:label, y:value, meta}] */
function sparkline(container, points, { fmtY = v => fmt(v, "int"), label = "" } = {}) {
  const W = 420, H = 90, P = { l: 6, r: 6, t: 8, b: 18 };
  const ys = points.map(p => p.y);
  const yMin = Math.min(0, ...ys), yMax = Math.max(...ys) * 1.1 || 1;
  const x = i => P.l + (points.length === 1 ? (W - P.l - P.r) / 2 : i * (W - P.l - P.r) / (points.length - 1));
  const y = v => P.t + (H - P.t - P.b) * (1 - (v - yMin) / (yMax - yMin));
  const path = points.map((p, i) => `${i ? "L" : "M"}${x(i).toFixed(1)},${y(p.y).toFixed(1)}`).join(" ");
  const area = `${path} L${x(points.length - 1).toFixed(1)},${y(yMin)} L${x(0).toFixed(1)},${y(yMin)} Z`;
  container.classList.add("chart");
  container.innerHTML = `<svg class="spark" viewBox="0 0 ${W} ${H}" role="img" aria-label="${esc(label)}">
    <g class="grid"><line x1="${P.l}" x2="${W - P.r}" y1="${y(yMin)}" y2="${y(yMin)}"/></g>
    <path class="area" d="${area}"/><path class="line" d="${path}"/>
    ${points.map((p, i) => `<circle class="mark" data-i="${i}" cx="${x(i)}" cy="${y(p.y)}" r="4"/>`).join("")}
    <g class="axis">${points.map((p, i) => `<text x="${x(i)}" y="${H - 4}" text-anchor="middle">${esc(p.x)}</text>`).join("")}</g>
    ${points.map((p, i) => `<rect data-i="${i}" x="${x(i) - (W / points.length) / 2}" y="0" width="${W / points.length}" height="${H}" fill="transparent"/>`).join("")}
  </svg><div class="tip"></div>`;
  const tip = container.querySelector(".tip");
  container.querySelectorAll("rect[data-i]").forEach(r => {
    r.addEventListener("mousemove", e => {
      const p = points[+r.dataset.i];
      tip.style.display = "block";
      tip.innerHTML = `<b>${esc(p.x)}</b> ${esc(p.meta || "")}<br>${fmtY(p.y)}`;
      const rect = container.getBoundingClientRect();
      tip.style.left = Math.min(e.clientX - rect.left + 10, rect.width - 150) + "px";
      tip.style.top = (e.clientY - rect.top - 40) + "px";
    });
    r.addEventListener("mouseleave", () => tip.style.display = "none");
  });
}

/* Win probability line: x = game seconds elapsed, y = SEA win probability. */
function wpChart(container, series, { home, opp } = {}) {
  const W = 900, H = 260, P = { l: 40, r: 12, t: 12, b: 26 };
  const maxS = 3600, ot = series.some(p => p.qtr > 4);
  const totalS = ot ? 3600 + 600 : 3600;
  const elapsed = p => (p.qtr > 4 ? 3600 + (600 - p.s) : 3600 - p.s);
  const x = t => P.l + (W - P.l - P.r) * t / totalS;
  const y = v => P.t + (H - P.t - P.b) * (1 - v);
  const pts = series.map(p => ({ ...p, t: elapsed(p) }));
  const path = pts.map((p, i) => `${i ? "L" : "M"}${x(p.t).toFixed(1)},${y(p.wp).toFixed(1)}`).join(" ");
  const qs = [900, 1800, 2700, 3600].concat(ot ? [4200] : []);
  const scoring = pts.filter(p => p.score);
  container.classList.add("chart");
  container.innerHTML = `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Seahawks win probability">
    <g class="grid">${[0, .25, .5, .75, 1].map(v => `<line x1="${P.l}" x2="${W - P.r}" y1="${y(v)}" y2="${y(v)}"${v === .5 ? ' stroke-dasharray="4 4"' : ""}/>`).join("")}
      ${qs.map(s => `<line x1="${x(s)}" x2="${x(s)}" y1="${P.t}" y2="${H - P.b}"/>`).join("")}</g>
    <g class="axis">${[0, .25, .5, .75, 1].map(v => `<text x="${P.l - 6}" y="${y(v) + 4}" text-anchor="end">${v * 100}%</text>`).join("")}
      ${["Q1", "Q2", "Q3", "Q4"].concat(ot ? ["OT"] : []).map((q, i) => `<text x="${x(i * 900 + 450)}" y="${H - 8}" text-anchor="middle">${q}</text>`).join("")}</g>
    <path class="line" d="${path}"/>
    ${scoring.map((p, i) => `<circle class="mark ${p.team === SEA ? "" : "opp"}" data-i="${i}" cx="${x(p.t)}" cy="${y(p.wp)}" r="5"/>`).join("")}
    <line class="cross" id="wp-cross" x1="0" x2="0" y1="${P.t}" y2="${H - P.b}" style="display:none"/>
    <rect id="wp-hit" x="${P.l}" y="${P.t}" width="${W - P.l - P.r}" height="${H - P.t - P.b}" fill="transparent"/>
  </svg><div class="tip"></div>
  <div class="note">Line: Seahawks win probability (nflverse <code>vegas_wp</code>). Dots: scoring plays (green = Seahawks, grey = ${esc(opp || "opponent")}). Hover for details.</div>`;
  const tip = container.querySelector(".tip"), cross = container.querySelector("#wp-cross"), hit = container.querySelector("#wp-hit");
  const show = (e, html) => {
    const rect = container.getBoundingClientRect();
    tip.style.display = "block"; tip.innerHTML = html;
    tip.style.left = Math.min(e.clientX - rect.left + 12, rect.width - 240) + "px";
    tip.style.top = Math.max(0, e.clientY - rect.top - 50) + "px";
  };
  hit.addEventListener("mousemove", e => {
    const svg = container.querySelector("svg"), r = svg.getBoundingClientRect();
    const t = (e.clientX - r.left) / r.width * W;
    const tt = (t - P.l) / (W - P.l - P.r) * totalS;
    let best = pts[0];
    for (const p of pts) if (Math.abs(p.t - tt) < Math.abs(best.t - tt)) best = p;
    cross.style.display = "block"; cross.setAttribute("x1", x(best.t)); cross.setAttribute("x2", x(best.t));
    const q = best.qtr > 4 ? "OT" : "Q" + best.qtr, rem = best.qtr > 4 ? best.s : best.s - (4 - best.qtr) * 900;
    show(e, `<b>${q} ${Math.floor(rem / 60)}:${String(rem % 60).padStart(2, "0")}</b> · SEA win prob <b>${(best.wp * 100).toFixed(0)}%</b>${best.score ? `<br>${esc(best.team)}: ${esc(best.desc)}` : ""}`);
  });
  hit.addEventListener("mouseleave", () => { tip.style.display = "none"; cross.style.display = "none"; });
  container.querySelectorAll("circle[data-i]").forEach(c => {
    c.addEventListener("mousemove", e => { const p = scoring[+c.dataset.i]; show(e, `<b>${esc(p.team)}</b> · SEA win prob ${(p.wp * 100).toFixed(0)}%<br>${esc(p.desc)}`); });
    c.addEventListener("mouseleave", () => tip.style.display = "none");
  });
}

function showError(el, err) {
  el.innerHTML = `<div class="err">Could not load data (${esc(err.message)}). If you opened this file directly, serve the <code>site/</code> folder over HTTP.</div>`;
}
