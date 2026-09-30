/* Splash page (spec Part A). */
(async function () {
  const main = document.getElementById("main");
  let meta, index, averages, rushTeam, rbs, situOff, situDef;
  try {
    [meta, index, averages, rushTeam, rbs, situOff, situDef] = await Promise.all([
      loadJSON("meta.json"), loadJSON("games/index.json"), loadJSON("team_averages.json"), loadJSON("rushing_team.json"),
      loadJSON("rushing_rbs.json"), loadJSON("situational_off.json"), loadJSON("situational_def.json")]);
  } catch (e) { showError(main, e); return; }

  // 1. Header
  document.getElementById("hdr-sub").textContent = `${meta.season} regular season · through Week ${meta.week}`;
  document.getElementById("hdr-record").textContent = meta.record.text;
  document.getElementById("hdr-meta").innerHTML = `Data refreshed ${esc(new Date(meta.refreshed_at).toLocaleString())}<br>nflverse play-by-play updated ${esc(meta.pbp_updated || "")}`;
  document.getElementById("footer-refresh").textContent = ` · Refreshed ${new Date(meta.refreshed_at).toLocaleString()}`;
  document.title = `Seahawks ${meta.season} Dashboard`;

  // 1a. Schedule strip
  document.getElementById("strip").innerHTML = index.map(g => {
    if (g.bye) return `<div class="tile bye"><div class="wk">Week ${g.week}</div><div class="opp" style="margin-top:22px">BYE</div></div>`;
    const cls = g.played ? resultClass(g.result) : "";
    const score = g.played ? `<div class="score ${cls}">${g.result} ${g.sea_score}–${g.opp_score}</div>`
                           : `<div class="score muted">${esc(fmtDate(g.gameday))}<br>${esc(fmtTime(g.gametime))}</div>`;
    return `<a class="tile ${cls}" href="game.html?id=${encodeURIComponent(g.game_id)}" title="${esc(g.opponent_name)}">
      <div class="wk">Wk ${g.week} · ${g.home ? "vs" : "@"}</div><img src="${esc(g.opponent_logo)}" alt="" loading="lazy">
      <div class="opp">${esc(g.opponent)}</div>${score}</a>`;
  }).join("");

  // 2. Team averages
  document.getElementById("rank-legend").innerHTML = rankLegend();
  document.getElementById("cards-off").innerHTML = averages.filter(s => s.group === "offense").map(s => statCard(s, { nKind: nKind(s) })).join("");
  document.getElementById("cards-def").innerHTML = averages.filter(s => s.group === "defense").map(s => statCard(s, { nKind: nKind(s) })).join("");
  function nKind(s) { return s.fmt === "time" || /per game/.test(s.label) ? "games" : /3rd/.test(s.label) ? "3rd downs" : /Red zone/.test(s.label) ? "trips" : "plays"; }

  // 3a. Team rushing
  document.getElementById("cards-rush").innerHTML = rushTeam.stats.map(s => statCard(s, { nKind: /per game|TDs/.test(s.label) ? "games" : "rushes" })).join("");
  const t = rushTeam.totals;
  document.getElementById("rush-totals").innerHTML =
    `All rushes: <b>${t.all_rushes.att} att, ${t.all_rushes.yds} yds</b> · designed runs: <b>${t.designed.att} att, ${t.designed.yds} yds</b> · QB scrambles: ${t.scrambles.att} att, ${t.scrambles.yds} yds. Kneel-downs are excluded everywhere.`;
  sparkline(document.getElementById("spark"),
    rushTeam.weekly.map(w => ({ x: `Wk ${w.week}`, y: w.yds, meta: `${w.home ? "vs" : "@"} ${w.opp} (${w.result}) · ${w.att} att · EPA/rush ${fmt(w.epa, "epa")}` })),
    { fmtY: v => `${v} rushing yards`, label: "Seahawks rushing yards by week" });

  // 3b. Running backs
  const rbRows = rbs.players.map(p => `<tr>
      <td class="l">${esc(p.name)}<span class="pos">${esc(p.position)}${p.jersey ? " #" + p.jersey : ""}</span></td>
      <td>${p.games}</td><td>${fmt(p.att_pg, "num1")}</td><td>${fmt(p.ypg, "num1")}</td><td>${fmt(p.ypc, "num2")}</td><td>${p.td}</td>
      <td>${fmt(p.epa, "epa")}</td><td>${fmt(p.success, "pct")}</td><td>${fmt(p.explosive, "pct")}</td>
      <td>${p.qualified ? rankPill(p.league_rank, { of: rbs.threshold.n_qualified }) : `<span class="rank rank-na" title="Below ${rbs.threshold.min_carries_per_game} carries per game">n/a</span>`}</td>
    </tr>`).join("");
  const tt = rbs.totals;
  document.getElementById("rb-table").innerHTML = `<thead><tr><th class="l">Player</th><th>G</th><th>Att/G</th><th>Yds/G</th><th>YPC</th><th>TD</th><th>EPA/rush</th><th>Success</th><th>Explosive</th><th>Lg rank (Yds/G)</th></tr></thead>
    <tbody>${rbRows}<tr class="total"><td class="l">All RBs</td><td>${tt.games}</td><td>${fmt(tt.att_pg, "num1")}</td><td>${fmt(tt.ypg, "num1")}</td><td>${fmt(tt.ypc, "num2")}</td><td>${tt.td}</td><td>${fmt(tt.epa, "epa")}</td><td>${fmt(tt.success, "pct")}</td><td>${fmt(tt.explosive, "pct")}</td><td></td></tr></tbody>`;
  document.getElementById("rb-note").textContent = `Games = games with at least one carry. League rank among ${rbs.threshold.n_qualified} RBs/FBs averaging ≥ ${rbs.threshold.min_carries_per_game} carries per game. Explosive = runs of 10+ yards.`;

  // 4 / 5. Situational
  renderSituational(document.getElementById("situ-off"), situOff, "off");
  renderSituational(document.getElementById("situ-def"), situDef, "def");

  function renderSituational(root, d, side) {
    const state = { gl: String(d.defaults.goal_line), sh: String(d.defaults.short) };
    const who = side === "off" ? "Seahawks" : "Opponents vs. Seahawks";
    root.innerHTML = `
      <div class="panel">
        <div class="toolbar"><h3 style="margin:0">Goal line rushing</h3><span id="${side}-gl-toggle"></span><span class="hint" id="${side}-gl-hint"></span></div>
        <div class="cards" id="${side}-gl-cards"></div>
        <h3>By player</h3><div class="tbl-wrap"><table id="${side}-gl-players"></table></div>
      </div>
      <div class="panel" style="margin-top:14px">
        <div class="toolbar"><h3 style="margin:0">3rd &amp; short rushing</h3><span id="${side}-sh-toggle"></span><span class="hint" id="${side}-sh-hint"></span></div>
        <div class="cards" id="${side}-sh-cards"></div>
        <h3>4th &amp; short (secondary)</h3>
        <div class="cards" id="${side}-fo-cards"></div>
        <h3>By player (3rd &amp; short)</h3><div class="tbl-wrap"><table id="${side}-sh-players"></table></div>
      </div>`;
    toggle(`${side}-gl-toggle`, [{ value: "5", label: "Inside the 5" }, { value: "10", label: "Inside the 10" }], state.gl, v => { state.gl = v; drawGL(); });
    toggle(`${side}-sh-toggle`, [{ value: "2", label: "≤ 2 yards" }, { value: "3", label: "≤ 3 yards" }], state.sh, v => { state.sh = v; drawSH(); });
    drawGL(); drawSH();

    function hint(b) {
      return `${who}: ${b.att} rushes, ${b.dropbacks} dropbacks · ranks need ≥ ${b.threshold} rushes (${b.n_qualified} teams qualify)` + (b.qualified ? "" : " · below threshold, not ranked");
    }
    function drawGL() {
      const b = d.goal_line[state.gl];
      document.getElementById(`${side}-gl-hint`).textContent = hint(b);
      document.getElementById(`${side}-gl-cards`).innerHTML = b.stats.map(s => statCard(s, { nKind: s.key.startsWith("pass") ? "dropbacks" : "rushes" })).join("");
      document.getElementById(`${side}-gl-players`).innerHTML = playerTable(b.by_player, "td");
    }
    function drawSH() {
      const b = d.short[state.sh].third, f = d.short[state.sh].fourth;
      document.getElementById(`${side}-sh-hint`).textContent = hint(b);
      document.getElementById(`${side}-sh-cards`).innerHTML = b.stats.map(s => statCard(s, { nKind: s.key.startsWith("pass") ? "dropbacks" : "rushes" })).join("");
      document.getElementById(`${side}-fo-cards`).innerHTML = f.stats.map(s => statCard(s, { nKind: s.key.startsWith("pass") ? "dropbacks" : "rushes" })).join("");
      document.getElementById(`${side}-sh-players`).innerHTML = playerTable(b.by_player, "conv");
    }
    function playerTable(rows, kind) {
      if (!rows || !rows.length) return `<tbody><tr><td class="l muted">No designed runs in this situation yet.</td></tr></tbody>`;
      const head = kind === "td" ? "<th>TD</th><th>TD rate</th>" : "<th>Conv</th><th>Conv rate</th>";
      return `<thead><tr><th class="l">Player</th><th>Att</th><th>Yds</th><th>YPC</th>${head}<th>EPA/rush</th></tr></thead><tbody>` +
        rows.map(p => `<tr><td class="l">${esc(p.name || p.gsis_id)}<span class="pos">${esc(p.position || "")}</span></td><td>${p.att}</td><td>${p.yds}</td><td>${fmt(p.ypc, "num2")}</td>` +
          (kind === "td" ? `<td>${p.td}</td><td>${fmt(p.td_rate, "pct0")}</td>` : `<td>${p.conv}</td><td>${fmt(p.conv_rate, "pct0")}</td>`) +
          `<td>${fmt(p.epa, "epa")}</td></tr>`).join("") + "</tbody>";
    }
  }
})();
