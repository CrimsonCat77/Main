/* Game detail page (spec Part B): the game (section 7), the opponent (8), the opponent QB (9). */
(async function () {
  const main = document.getElementById("main");
  const id = new URLSearchParams(location.search).get("id");
  if (!id) { main.innerHTML = `<div class="err">No game selected. <a href="index.html">Back to the dashboard.</a></div>`; return; }
  let g, opp, qb = null, meta;
  try {
    [g, meta] = await Promise.all([loadJSON(`games/${id}.json`), loadJSON("meta.json")]);
    const wants = [loadJSON(g.files.opponent)];
    if (g.files.qb) wants.push(loadJSON(g.files.qb).catch(() => null));
    [opp, qb] = await Promise.all(wants);
  } catch (e) { showError(main, e); return; }

  const h = g.header, oi = h.opponent_identity;
  document.title = `Week ${h.week}: SEA ${h.home ? "vs" : "@"} ${h.opponent}`;
  document.getElementById("hdr-title").textContent = `Week ${h.week} · Seahawks ${h.home ? "vs" : "at"} ${oi.name}`;
  document.getElementById("hdr-sub").textContent = `${fmtDate(h.gameday)} · ${fmtTime(h.gametime)} · ${h.stadium || ""}`;
  document.getElementById("hdr-meta").innerHTML = `${h.played ? "Final" : "Preview"} · data through Week ${meta.week}<br>Refreshed ${esc(new Date(meta.refreshed_at).toLocaleString())}`;

  const parts = [];
  parts.push(renderHeader());
  if (h.played) {
    parts.push(renderBox(), renderScoringDrives(), renderPlayers(), renderSituational());
  } else {
    parts.push(`<section><p class="lede">This game has not been played yet. Below: the opponent profile and their expected starting quarterback.</p></section>`);
  }
  parts.push(renderOpponent(), renderQB());
  parts.push(`<footer>Data: <a href="https://github.com/nflverse/nflverse-data" target="_blank" rel="noopener">nflverse</a> · <a href="methodology.html">Methodology</a> · <a href="index.html">Dashboard</a></footer>`);
  main.innerHTML = parts.join("");
  if (h.played && g.wp && g.wp.length) wpChart(document.getElementById("wp"), g.wp, { home: h.home, opp: h.opponent });

  /* ---------- 7a. Header ---------- */
  function renderHeader() {
    const seaRec = meta.record.text;
    const oppRec = opp.record_current.text;
    const score = h.played ? `<div class="score">${h.home ? `${h.opp_score}<span class="sep">–</span>${h.sea_score}` : `${h.sea_score}<span class="sep">–</span>${h.opp_score}`}</div>
        <div class="res">${h.result === "W" ? "Seahawks win" : h.result === "L" ? "Seahawks lose" : "Tie"} by ${Math.abs(h.margin)}${h.overtime ? " (OT)" : ""}</div>`
      : `<div class="score muted">${esc(fmtTime(h.gametime))}</div><div class="res">${esc(fmtDate(h.gameday))}</div>`;
    const away = h.home ? teamBlock(oi.abbr, oi.name, oi.logo, oppRec) : teamBlock("SEA", "Seattle Seahawks", "https://a.espncdn.com/i/teamlogos/nfl/500/sea.png", seaRec);
    const home = h.home ? teamBlock("SEA", "Seattle Seahawks", "https://a.espncdn.com/i/teamlogos/nfl/500/sea.png", seaRec) : teamBlock(oi.abbr, oi.name, oi.logo, oppRec);
    const spread = h.spread_line == null ? "" : `<span>Line: <b>SEA ${h.spread_line > 0 ? "−" : "+"}${Math.abs(h.spread_line)}</b>${h.covered ? ` (${h.covered})` : ""}</span>`;
    const total = h.total_line == null ? "" : `<span>Total: <b>${h.total_line}</b>${h.total_result ? ` (${h.total_result}, ${h.total})` : ""}</span>`;
    const weather = h.roof === "outdoors" || h.roof === "open" ? `<span>Weather: <b>${h.temp != null ? h.temp + "°F" : "—"}</b>${h.wind != null ? `, wind ${h.wind} mph` : ""}</span>` : "";
    return `<section>
      <div class="game-hero">${away}<div>${score}</div>${home}</div>
      <div class="facts">
        <span>${esc(h.stadium || "")} · ${esc(h.roof || "")} · ${esc(h.surface || "")}</span>${weather}${spread}${total}
        <span>Coaches: <b>${esc(h.sea_coach)}</b> (SEA) · <b>${esc(h.opp_coach)}</b> (${esc(h.opponent)})</span>
        ${h.referee ? `<span>Referee: ${esc(h.referee)}</span>` : ""}${h.div_game ? `<span class="pill">Division game</span>` : ""}
      </div>
    </section>`;
    function teamBlock(abbr, name, logo, rec) {
      return `<div class="team"><img src="${esc(logo)}" alt=""><div class="nm">${esc(name)}</div><div class="rec">${esc(rec)}</div></div>`;
    }
  }

  /* ---------- 7b. Box score ---------- */
  function renderBox() {
    const s = g.box.sea, o = g.box.opp, q = g.box.by_quarter;
    const row = (label, a, b, f, hib = true) => {
      const av = typeof a === "number" ? a : null, bv = typeof b === "number" ? b : null;
      const aBetter = av != null && bv != null && av !== bv && ((av > bv) === hib);
      const bBetter = av != null && bv != null && av !== bv && ((bv > av) === hib);
      return `<tr><td class="num ${aBetter ? "better" : ""}">${f ? f(a) : a}</td><td class="mid">${label}</td><td class="num ${bBetter ? "better" : ""}">${f ? f(b) : b}</td></tr>`;
    };
    const pct = (c, a) => a ? `${c}/${a} (${Math.round(c / a * 100)}%)` : "0/0";
    const rows = [
      row("Total yards", s.total_yards, o.total_yards),
      row("Plays · yds/play", `${s.plays} · ${fmt(s.total_yards / s.plays, "num1")}`, `${o.plays} · ${fmt(o.total_yards / o.plays, "num1")}`),
      row("Passing yards (net)", s.pass_yards, o.pass_yards),
      row("Comp–Att · TD · INT", `${s.comp}–${s.att} · ${s.pass_td} · ${s.int}`, `${o.comp}–${o.att} · ${o.pass_td} · ${o.int}`),
      row("Rushing yards", s.rush_yards, o.rush_yards),
      row("Att · YPC · TD", `${s.rush_att} · ${fmt(s.rush_ypc, "num2")} · ${s.rush_td}`, `${o.rush_att} · ${fmt(o.rush_ypc, "num2")} · ${o.rush_td}`),
      row("First downs", s.first_downs, o.first_downs),
      row("3rd down", pct(s.third_conv, s.third_att), pct(o.third_conv, o.third_att)),
      row("4th down", pct(s.fourth_conv, s.fourth_att), pct(o.fourth_conv, o.fourth_att)),
      row("Red zone (TD / trips)", pct(s.rz_td, s.rz_trips), pct(o.rz_td, o.rz_trips)),
      row("Turnovers", s.turnovers, o.turnovers, null, false),
      row("Sacks (by defense)", s.sacks, o.sacks),
      row("Penalties · yards", `${s.penalties} · ${s.penalty_yards}`, `${o.penalties} · ${o.penalty_yards}`),
      row("Time of possession", s.top, o.top, v => fmt(v, "time")),
      row("EPA per play", s.epa_play, o.epa_play, v => fmt(v, "epa")),
      row("Success rate", s.success, o.success, v => fmt(v, "pct")),
      row("Explosive play rate", s.explosive, o.explosive, v => fmt(v, "pct")),
    ].join("");
    const qHead = q.quarters.map(x => `<th>${x > 4 ? "OT" : "Q" + x}</th>`).join("");
    const qRow = (name, arr, tot) => `<tr><td class="l">${name}</td>${arr.map(v => `<td>${v}</td>`).join("")}<td><b>${tot}</b></td></tr>`;
    return `<section><h2>Box score</h2>
      <div class="two-col">
        <div class="tbl-wrap"><table class="box"><thead><tr><th class="num" style="text-align:center">SEA</th><th class="mid"></th><th class="num" style="text-align:center">${esc(h.opponent)}</th></tr></thead><tbody>${rows}</tbody></table>
          <p class="note">Computed from this game's play-by-play (run and pass plays; kneels, spikes and nullified plays excluded). Green = the better side.</p></div>
        <div><div class="tbl-wrap"><table><thead><tr><th class="l">Scoring</th>${qHead}<th>F</th></tr></thead><tbody>${qRow("SEA", q.sea, h.sea_score)}${qRow(h.opponent, q.opp, h.opp_score)}</tbody></table></div>
          <h3>Win probability</h3><div id="wp"></div></div>
      </div></section>`;
  }

  /* ---------- 7c. Scoring summary + drives ---------- */
  function renderScoringDrives() {
    const scoreAfter = r => h.home ? `${r.away}–${r.home}` : `${r.home}–${r.away}`;  // shown as SEA-opp? keep away–home order like the hero
    const sc = g.scoring.map(r => `<tr class="${r.team === SEA ? "hl" : ""}"><td class="l">Q${r.qtr} ${r.time}</td><td class="l">${esc(r.team)}</td><td class="l">${r.kind}${r.pat ? ` (${r.pat})` : ""}</td><td class="l" style="white-space:normal">${esc(r.desc)}</td><td>${r.away}–${r.home}</td></tr>`).join("");
    const dr = g.drives.map(d => `<tr class="${d.team === SEA ? "hl" : ""}"><td>${d.drive}</td><td class="l">${esc(d.team)}</td><td>${d.qtr ?? ""}</td><td class="l">${esc(d.start || "")}</td><td>${d.plays ?? ""}</td><td>${d.yards}</td><td>${esc(d.time || "")}</td><td class="l">${esc(d.result || "")}</td><td>${fmt(d.epa, "epa2")}</td></tr>`).join("");
    return `<section><h2>Scoring summary</h2>
      <div class="tbl-wrap"><table><thead><tr><th class="l">Time</th><th class="l">Team</th><th class="l">Play</th><th class="l">Description</th><th>Score (${h.home ? esc(h.opponent) : "SEA"}–${h.home ? "SEA" : esc(h.opponent)})</th></tr></thead><tbody>${sc}</tbody></table></div>
      <h2 style="margin-top:22px">Drives</h2>
      <div class="tbl-wrap"><table><thead><tr><th>#</th><th class="l">Team</th><th>Qtr</th><th class="l">Start</th><th>Plays</th><th>Yards</th><th>Time</th><th class="l">Result</th><th>EPA</th></tr></thead><tbody>${dr}</tbody></table></div>
    </section>`;
  }

  /* ---------- 7d. Seahawks player stats ---------- */
  function renderPlayers() {
    const p = g.players;
    const tbl = (title, head, rows) => `<h3>${title}</h3><div class="tbl-wrap"><table><thead><tr>${head}</tr></thead><tbody>${rows || `<tr><td class="l muted">None</td></tr>`}</tbody></table></div>`;
    const nm = r => `<td class="l">${esc(r.name)}${r.position ? `<span class="pos">${esc(r.position)}</span>` : ""}</td>`;
    return `<section><h2>Seahawks player stats</h2>
      ${tbl("Passing", `<th class="l">Player</th><th>Comp–Att</th><th>Yds</th><th>TD</th><th>INT</th><th>Sacks</th><th>EPA</th><th>CPOE</th><th>Rating</th>`,
        p.passing.map(r => `<tr>${nm(r)}<td>${r.comp}–${r.att}</td><td>${r.yds}</td><td>${r.td}</td><td>${r.int}</td><td>${r.sacks}</td><td>${fmt(r.epa, "epa2")}</td><td>${fmt(r.cpoe, "signed1")}</td><td>${fmt(r.rating, "num1")}</td></tr>`).join(""))}
      ${tbl("Rushing", `<th class="l">Player</th><th>Att</th><th>Yds</th><th>YPC</th><th>TD</th><th>EPA</th><th>Success</th>`,
        p.rushing.map(r => `<tr>${nm(r)}<td>${r.att}</td><td>${r.yds}</td><td>${fmt(r.ypc, "num2")}</td><td>${r.td}</td><td>${fmt(r.epa, "epa2")}</td><td>${fmt(r.success, "pct0")}</td></tr>`).join(""))}
      ${tbl("Receiving", `<th class="l">Player</th><th>Tgt</th><th>Rec</th><th>Yds</th><th>TD</th><th>EPA</th>`,
        p.receiving.map(r => `<tr>${nm(r)}<td>${r.targets}</td><td>${r.rec}</td><td>${r.yds}</td><td>${r.td}</td><td>${fmt(r.epa, "epa2")}</td></tr>`).join(""))}
      ${tbl("Defense", `<th class="l">Player</th><th>Tkl</th><th>Solo</th><th>TFL</th><th>Sacks</th><th>QB hits</th><th>INT</th><th>PD</th><th>FF</th>`,
        p.defense.map(r => `<tr>${nm(r)}<td>${r.tackles}</td><td>${r.solo}</td><td>${r.tfl}</td><td>${r.sacks}</td><td>${r.qb_hits}</td><td>${r.int}</td><td>${r.pd}</td><td>${r.ff}</td></tr>`).join(""))}
    </section>`;
  }

  /* ---------- 7e. Situational rushing in this game ---------- */
  function renderSituational() {
    const s = g.situational;
    const block = (title, b) => `<div class="panel"><h3>${title} <span class="muted" style="text-transform:none;font-weight:400">· ${b.att} rushes, ${b.dropbacks} dropbacks</span></h3>
      <div class="tbl-wrap"><table><thead><tr><th class="l">Stat</th><th>This game</th><th>n</th><th>Season</th><th>n</th></tr></thead><tbody>
      ${b.stats.map(x => `<tr><td class="l">${esc(x.label)}</td><td>${fmt(x.value, x.fmt)}</td><td class="muted">${x.n}</td><td>${fmt(x.season_value, x.fmt)}</td><td class="muted">${x.season_n}</td></tr>`).join("")}
      </tbody></table></div></div>`;
    const side = (label, d) => `<h3>${label}</h3><div class="two-col">${block(`Goal line (inside the ${s.defaults.goal_line})`, d.goal_line)}${block(`3rd &amp; ≤ ${s.defaults.short}`, d.third)}</div>
      <div style="margin-top:10px">${block(`4th &amp; ≤ ${s.defaults.short}`, d.fourth)}</div>`;
    return `<section><h2>Situational rushing in this game</h2>
      <p class="lede">Designed runs, this game only, with the season rate alongside. Single-game samples are tiny and are never ranked.</p>
      ${side("Seahawks offense", s.off)}${side("Seahawks defense (opponent rushing)", s.def)}</section>`;
  }

  /* ---------- 8. Opponent profile ---------- */
  function renderOpponent() {
    const o = opp, st = o.standing, bw = o.best_worst;
    const results = o.results.map(r => `<a class="r ${r.played ? resultClass(r.result) : ""} ${r.is_sea ? "sea" : ""}" href="${r.is_sea ? `game.html?id=${encodeURIComponent(r.game_id)}` : "#"}" ${r.is_sea ? "" : 'onclick="return false"'}>
        <div class="w">Wk ${r.week} ${r.home ? "vs" : "@"}</div><div>${esc(r.opponent)}</div><div>${r.played ? `${r.result} ${r.pts}–${r.pts_allowed}` : esc(fmtDate(r.gameday))}</div></a>`).join("");
    const bwCard = (title, x, none) => `<div class="panel"><h3>${title}</h3>${x ? `<div><b>${x.home ? "vs" : "@"} ${esc(x.team)}</b> (${esc(x.record)} now${x.record_then !== x.record ? `, was ${esc(x.record_then)} then` : ""}) · Week ${x.week} · ${esc(x.score)}</div><div class="note">Opponent win % now: ${fmt(x.pct, "pct")}</div>` : `<div class="muted">${none}</div>`}</div>`;
    const avgRows = grp => o.averages.filter(a => a.group === grp).map(a => {
      const d = a.prior.value != null && a.opp.value != null ? a.opp.value - a.prior.value : null;
      const rel = d == null ? "" : (Math.abs(d) / (Math.abs(a.prior.value) || 1) >= 0.1 ? ((d > 0) === a.higher_is_better ? "delta-up" : "delta-down") : "");
      return `<tr><td class="l">${esc(a.label)}</td><td>${fmt(a.opp.value, a.fmt)}</td><td>${rankPill(a.opp.rank)}</td><td>${fmt(a.sea.value, a.fmt)}</td><td>${rankPill(a.sea.rank)}</td>
        <td class="${rel}">${fmt(a.prior.value, a.fmt)}${a.prior.rank ? ` <span class="muted">#${a.prior.rank}</span>` : ""}</td></tr>`;
    }).join("");
    const avgTable = grp => `<div class="tbl-wrap"><table><thead><tr><th class="l">${grp === "offense" ? "Offense" : "Defense"}</th><th>${esc(o.team)}</th><th>Rank</th><th>SEA</th><th>Rank</th><th>${o.prior_season} ${esc(o.team)}</th></tr></thead><tbody>${avgRows(grp)}</tbody></table></div>`;
    return `<section>
      <h2><img src="${esc(o.identity.logo)}" alt="" style="height:28px;vertical-align:middle;margin-right:6px">${esc(o.identity.name)}</h2>
      <p class="lede">${esc(o.identity.division)} · Head coach ${esc(o.coach || "—")} · Record entering this game <b>${esc(o.record_entering.text)}</b> · now <b>${esc(o.record_current.text)}</b> · ${ordinal(st.place)} in the ${esc(st.division)}</p>
      <div class="results">${results}</div>
      <div class="bw" style="margin-top:14px">${bwCard("Best win", bw.best_win, "No wins yet")}${bwCard("Worst loss", bw.worst_loss, "No losses yet")}</div>
      <p class="note">Best win / worst loss use the other team's <b>current</b> win percentage (ties → more games played, then alphabetical); the record at the time of the game is shown as secondary.</p>
      <h3>Division standings</h3>
      <div class="tbl-wrap"><table><thead><tr><th class="l">Team</th><th>Record</th><th>Pct</th><th>Pt diff</th></tr></thead><tbody>
        ${st.table.map(t => `<tr class="${t.team === o.team ? "hl" : ""}"><td class="l">${t.place}. ${esc(t.team)}</td><td>${esc(t.record)}</td><td>${fmt(t.pct, "num2").replace(/^0/, "")}</td><td>${t.diff > 0 ? "+" : ""}${t.diff}</td></tr>`).join("")}
      </tbody></table></div>
      <p class="note">Standings are ordered by win percentage then point differential (a simplification of the NFL tiebreakers).</p>
      <h3>Season averages vs. Seahawks</h3>
      <div class="two-col">${avgTable("offense")}${avgTable("defense")}</div>
      <p class="note">Last column: ${o.prior_season} regular-season average and rank. Colored when this season is at least 10% different from last year (green = improved).</p>
      <h3>What Seattle's run game faces: ${esc(o.team)} run defense</h3>
      ${situBlock(o.situational.def)}
      <h3>What Seattle's run defense faces: ${esc(o.team)} rushing offense</h3>
      ${situBlock(o.situational.off)}
    </section>`;
  }
  function situBlock(d) {
    const gl = d.goal_line[String(d.defaults.goal_line)], sh = d.short[String(d.defaults.short)].third;
    const cards = b => `<div class="cards">${b.stats.map(s => statCard(s, { nKind: s.key.startsWith("pass") ? "dropbacks" : "rushes" })).join("")}</div>`;
    return `<div class="two-col"><div><h3 style="margin-top:0">Goal line (inside the ${d.defaults.goal_line}) · ${gl.att} rushes</h3>${cards(gl)}</div>
      <div><h3 style="margin-top:0">3rd &amp; ≤ ${d.defaults.short} · ${sh.att} rushes</h3>${cards(sh)}</div></div>`;
  }
  function ordinal(n) { return n + (["th", "st", "nd", "rd"][((n % 100) - 20) % 10] || ["th", "st", "nd", "rd"][n % 100] || "th"); }

  /* ---------- 9. Opponent quarterback ---------- */
  function renderQB() {
    const q = g.qb;
    if (!qb) return `<section><h2>Opponent quarterback</h2><p class="muted">${q && q.name ? `${esc(q.name)} — no profile available yet.` : "No quarterback identified yet."}</p></section>`;
    const c = qb.career, cur = qb.current, gl = q.game_line;
    const basis = q.basis === "game" ? "Started this game (most dropbacks)" : q.basis === "most_recent" ? `${h.opponent}'s most recent starter` : "Listed starter on the schedule";
    const differs = q.differs ? `<span class="pill warn">Not the usual starter — ${esc(q.usual_name)} has the most starts this season</span>` : "";
    const line = (l, title) => l ? `<tr><td class="l">${title}</td><td>${l.games ?? ""}</td><td>${l.comp}–${l.att}</td><td>${fmt(l.comp_pct, "pct")}</td><td>${l.yds}</td><td>${l.td}</td><td>${l.int}</td><td>${fmt(l.ypa, "num1")}</td><td>${fmt(l.rating, "num1")}</td><td>${l.sacks}</td><td>${fmt(l.epa_db, "epa")}</td><td>${fmt(l.cpoe, "signed1")}</td><td>${l.rush_att}–${l.rush_yds}–${l.rush_td}</td></tr>` : "";
    const head = `<thead><tr><th class="l"></th><th>G</th><th>Comp–Att</th><th>Comp%</th><th>Yds</th><th>TD</th><th>INT</th><th>Y/A</th><th>Rtg</th><th>Sk</th><th>EPA/db</th><th>CPOE</th><th>Rush A–Y–TD</th></tr></thead>`;
    const rk = k => cur.ranks && cur.ranks[k] != null ? rankPill(cur.ranks[k], { of: cur.n_qualified }) : `<span class="rank rank-na">n/a</span>`;
    const gameLine = gl ? `<h3>This game</h3><div class="tbl-wrap"><table>${head}<tbody>${line({ ...gl, games: 1 }, `Week ${h.week} vs SEA`)}${line(gl.season, `${meta.season} season avg`)}</tbody></table></div>
      <p class="note">${gameCompare(gl)}</p>` : "";
    return `<section><h2>Opponent quarterback</h2>
      <div class="qb-card">
        <img src="${esc(qb.headshot || "")}" alt="">
        <div>
          <h2>${esc(qb.name)} <span class="muted">#${qb.jersey ?? ""} · ${esc(qb.team)}</span></h2>
          <div style="margin:4px 0 8px"><span class="pill">${esc(basis)}</span> ${differs}</div>
          <dl class="kv">
            <dt>Age</dt><dd>${ageAt(qb.birth_date, h.gameday) ?? "—"} (born ${esc(qb.birth_date || "")})</dd>
            <dt>Experience</dt><dd>${qb.years_of_experience} yrs · <b>${esc(qb.tier)}</b>${qb.is_vet ? " · Vet" : ""} <span class="muted">(Vet = ${qb.vet_threshold}+ yrs)</span></dd>
            <dt>Draft</dt><dd>${esc(qb.draft)}</dd>
            <dt>College</dt><dd>${esc(qb.college || "—")}</dd>
            <dt>Career record</dt><dd>${esc(c.record)} as starter over ${c.seasons} seasons, ${c.games} games</dd>
            <dt>vs. Seahawks</dt><dd>${qb.vs_sea.games ? `${esc(qb.vs_sea.record)} as starter · ${qb.vs_sea.comp}–${qb.vs_sea.att}, ${qb.vs_sea.yds} yds, ${qb.vs_sea.td} TD, ${qb.vs_sea.int} INT, rating ${fmt(qb.vs_sea.rating, "num1")}` : "No games"}</dd>
          </dl>
        </div>
      </div>
      ${gameLine}
      <h3>${meta.season} season ${cur.qualified ? `· ranks among ${cur.n_qualified} qualified QBs` : `· not yet qualified (needs ${cur.min_dropbacks} dropbacks)`}</h3>
      <div class="tbl-wrap"><table>${head}<tbody>${line(cur, `${meta.season}`)}
        <tr><td class="l muted">Rank</td><td></td><td></td><td>${rk("comp_pct")}</td><td>${rk("yds")}</td><td>${rk("td")}</td><td>${rk("int")}</td><td>${rk("ypa")}</td><td>${rk("rating")}</td><td></td><td>${rk("epa_db")}</td><td>${rk("cpoe")}</td><td></td></tr></tbody></table></div>
      <h3>Career (regular season)</h3>
      <div class="tbl-wrap"><table>${head}<tbody>${line(c, "Career")}${line(qb.vs_sea, "vs. SEA")}</tbody></table></div>
      <h3>By season</h3>
      <div class="tbl-wrap"><table><thead><tr><th class="l">Season</th><th class="l">Team</th><th>G</th><th>Record</th><th>Comp%</th><th>Yds</th><th>TD</th><th>INT</th><th>Rtg</th><th>EPA/db</th></tr></thead><tbody>
        ${qb.per_season.map(s => `<tr><td class="l">${s.season}</td><td class="l">${esc(s.team)}</td><td>${s.games}</td><td>${esc(s.record)}</td><td>${fmt(s.comp_pct, "pct")}</td><td>${s.yds}</td><td>${s.td}</td><td>${s.int}</td><td>${fmt(s.rating, "num1")}</td><td>${fmt(s.epa_db, "epa")}</td></tr>`).join("")}
      </tbody></table></div>
      <p class="note">Career from nflverse weekly player stats (1999–present). Dropbacks = attempts + sacks. Record as starter credits the passer with the most dropbacks for his team in each game.</p>
    </section>`;
  }
  function gameCompare(gl) {
    const s = gl.season, d = gl.epa_db - s.epa_db, dc = gl.comp_pct - s.comp_pct;
    const tone = d > 0.1 ? "well above" : d > 0.03 ? "above" : d < -0.1 ? "well below" : d < -0.03 ? "below" : "about";
    return `Against Seattle his EPA per dropback was ${tone} his season average (${fmt(gl.epa_db, "epa")} vs ${fmt(s.epa_db, "epa")}); completion rate ${dc >= 0 ? "+" : ""}${(dc * 100).toFixed(1)} pts; success rate ${fmt(gl.success, "pct")}.`;
  }
})();
