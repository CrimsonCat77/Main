# Seahawks Dashboard — Spec

Static HTML dashboard of Seattle Seahawks data built from nflverse, hosted on Cloudflare Pages.
This document specifies the splash (landing) page (Part A, sections 1–6) and the per-game
detail pages with opponent profiles (Part B, sections 7–10): what each shows, how each number
is defined, and what the data layer needs to produce.

---

# Part A — Splash page

Season in scope: 2026 regular season (parameterized; default to the current season).
Team code: `SEA`. Rankings are always 1–32 across all teams for the same season and filters.

---

## 1. Page layout

Top to bottom:

1. **Header** — team name, season, record (W-L-T), last data refresh timestamp, "through Week N".
1a. **Schedule strip** — one tile per game (week, opponent logo, home/away, score or kickoff
   time, W/L color). Played games link to their game detail page (Part B); upcoming games link
   to a preview version of the same page with the opponent profile only.
2. **Team averages** — a card grid of core per-game statistics, each with the Seahawks value,
   league average, and league rank.
3. **Rushing offense** — team rushing yards per game with rank, then a table of running backs.
4. **Situational rushing (offense)** — goal line and 3rd-and-short performance.
5. **Situational rushing (defense)** — the same two situations from the defensive side.
6. **Footer** — data source note (nflverse), methodology link, repo link.

Each stat card follows the same pattern: **value · rank/32 · league avg**. Ranks are colored
on a simple scale (top 8 / middle 16 / bottom 8) so the page reads at a glance.

---

## 2. Team averages (Section 2)

All values are per game, regular season only, rank shown out of 32.

### Offense (rank: higher is better)

| Stat | Definition |
|---|---|
| Points per game | Team points scored / games played |
| Total yards per game | Passing + rushing yards (net of sacks) / games |
| Passing yards per game | Net passing yards / games |
| Rushing yards per game | Rushing yards / games |
| Yards per play | Total yards / offensive plays (excluding penalties, kneels, spikes) |
| EPA per play | Mean `epa` on offensive plays where `posteam == "SEA"` |
| Success rate | Share of offensive plays with `success == 1` |
| 3rd down conversion % | 3rd down conversions / 3rd down attempts |
| Red zone TD % | Touchdowns / red zone trips |
| Turnovers per game | Interceptions thrown + fumbles lost / games |
| Time of possession | Average possession time per game |

### Defense (rank: lower allowed is better, so rank 1 = fewest allowed)

| Stat | Definition |
|---|---|
| Points allowed per game | Opponent points / games |
| Total yards allowed per game | Opponent passing + rushing yards / games |
| Passing yards allowed per game | Opponent net passing yards / games |
| Rushing yards allowed per game | Opponent rushing yards / games |
| Yards per play allowed | Opponent yards / opponent plays |
| EPA per play allowed | Mean `epa` on plays where `defteam == "SEA"` (lower is better) |
| Success rate allowed | Share of opponent plays with `success == 1` |
| 3rd down conversion % allowed | Opponent conversions / attempts |
| Takeaways per game | Interceptions + fumble recoveries / games (higher is better) |
| Sacks per game | Sacks / games (higher is better) |

**Rank direction** must be stored per stat, not inferred. Each stat carries a `higher_is_better`
flag so defensive stats rank correctly.

---

## 3. Rushing offense (Section 3)

### 3a. Team-level rushing yards per game

- Value: SEA rushing yards / games played.
- Rank: 1–32, descending.
- Also show: rushing attempts per game, yards per carry, rushing TDs, rushing EPA per play,
  rushing success rate, and rush share (rushes / (rushes + dropbacks)).
- Small sparkline of rushing yards by week.

### 3b. Rushing yards per game by running back

Table, one row per running back with at least one carry:

| Column | Definition |
|---|---|
| Player | From `load_rosters()`, `position == "RB"` (include FB as separate flag if any carries) |
| Games | Games with ≥ 1 carry |
| Att/G | Carries / games |
| Yds/G | Rushing yards / games |
| YPC | Rushing yards / carries |
| TD | Rushing touchdowns |
| EPA/rush | Mean `epa` on that player's rushes |
| Success % | Share of rushes with `success == 1` |
| Explosive % | Share of rushes ≥ 10 yards |
| League rank (Yds/G) | Rank among all NFL RBs with ≥ 5 carries per game (threshold parameterized) |

Sort by Yds/G descending. Show the team's combined RB line as a totals row.

**Scope note:** QB scrambles and WR/TE carries are excluded from this table but included in
the team-level number in 3a. Both totals should be shown so the difference is visible.

---

## 4. Situational rushing — offense (Section 4)

Two situations, each as a card pair (Seahawks vs. league) with rank.

### 4a. Goal line rushing

**Definition:** rushing plays where `posteam == "SEA"` and `yardline_100 <= 5`.
(Inside the 5 is the default; `yardline_100 <= 10` is available as a toggle. Store both.)

| Stat | Definition |
|---|---|
| Attempts | Count of goal line rushes |
| Yards per carry | Yards / attempts |
| TD rate | Rushing TDs / attempts |
| Success rate | Share with `success == 1` |
| EPA per rush | Mean `epa` |
| Rush share at goal line | Goal line rushes / (goal line rushes + goal line dropbacks) |
| By player | Same stats broken out per RB (attempts, TD, TD rate) |

Ranks: TD rate, EPA per rush, and success rate ranked 1–32 (higher is better).

### 4b. 3rd and short rushing

**Definition:** rushing plays where `posteam == "SEA"`, `down == 3`, and `ydstogo <= 2`.
(≤ 2 yards is the default; `ydstogo <= 3` available as a toggle. Store both.)

Also include 4th and short (`down == 4`, `ydstogo <= 2`) as a secondary row since teams
treat it similarly.

| Stat | Definition |
|---|---|
| Attempts | Count of 3rd-and-short rushes |
| Conversion rate | Share with `first_down == 1` or `touchdown == 1` |
| Yards per carry | Yards / attempts |
| Success rate | Share with `success == 1` |
| EPA per rush | Mean `epa` |
| Rush share on 3rd and short | Rushes / (rushes + dropbacks) in the situation |
| Conversion rate when passing | Same filter, dropbacks, for comparison |
| By player | Attempts and conversion rate per RB |

Ranks: conversion rate, EPA per rush, success rate ranked 1–32 (higher is better).

---

## 5. Situational rushing — defense (Section 5)

Mirror of Section 4 with `defteam == "SEA"` and the opponent as `posteam`.
Same situation definitions, same toggles, same stat set. Rank direction flips:
lower opponent TD rate / conversion rate / EPA allowed = better rank.

### 5a. Goal line rushing defense

- Opponent rushing attempts inside the 5, yards per carry allowed, TD rate allowed,
  success rate allowed, EPA per rush allowed.
- Rank 1 = lowest TD rate allowed.

### 5b. 3rd and short rushing defense

- Opponent rushing attempts on 3rd and ≤ 2, conversion rate allowed, YPC allowed,
  success rate allowed, EPA per rush allowed.
- Include 4th and short allowed as a secondary row.
- Include opponent conversion rate when passing in the same situation, for contrast.
- Rank 1 = lowest conversion rate allowed.

---

## 6. Data layer

### Sources (nflreadr)

| Function | Used for |
|---|---|
| `load_pbp(season)` | All situational and EPA-based stats; rushing by player |
| `load_schedules(season)` | Record, games played, weeks completed |
| `load_rosters(season)` | Position lookup for RB filtering, player names, headshots |
| `load_team_stats(season)` or `load_player_stats(season)` | Cross-check for box-score totals (passing/rushing yards, turnovers) |

### Common filters applied to play-by-play before anything else

```r
pbp <- load_pbp(season) |>
  filter(season_type == "REG",
         !is.na(epa),
         play_type %in% c("run", "pass"),   # drops kicks, kneels, spikes, no-plays
         penalty == 0 | !is.na(yards_gained))
```

### Rushing play definition

Use `rush == 1` for team-level rushing. For the RB table and situational stats use
`rush == 1 & qb_scramble == 0` (designed runs). Document this on the page's methodology note.

### Key fields

`posteam`, `defteam`, `rusher_player_id`, `rusher_player_name`, `rushing_yards`,
`yards_gained`, `down`, `ydstogo`, `yardline_100`, `epa`, `success`, `first_down`,
`touchdown`, `rush_touchdown`, `qb_scramble`, `qb_dropback`, `week`, `game_id`.

### Ranking rule

Compute every stat for all 32 teams from the same filtered play-by-play, then rank.
Never rank SEA against a separately sourced league table — small filter differences will
produce inconsistent ranks. Minimum-attempt thresholds (parameterized) apply to situational
ranks so a team with 3 goal line carries doesn't rank #1 on TD rate.

### Output

One JSON file per section written to `data/`:

```
data/
  meta.json            # season, week, record, refresh timestamp, thresholds used
  team_averages.json   # section 2 — array of {stat, sea, league_avg, rank, higher_is_better}
  rushing_team.json    # section 3a — team rushing line + weekly series
  rushing_rbs.json     # section 3b — array of player rows
  situational_off.json # section 4 — goal line + 3rd/4th and short, both toggle variants
  situational_def.json # section 5 — same shape as situational_off
```

Every stat object includes `n` (attempts / plays / games) so the page can show sample size
on hover.

### Refresh

GitHub Actions on a weekly cron (Tuesday morning Pacific), plus manual dispatch.
Runs the R script, commits `data/*.json`, and Cloudflare Pages redeploys from the push.

---

# Part B — Game detail pages

One page per Seahawks game. Reached from the schedule strip on the splash page. Built as a
single `game.html` template that reads a `?id=<game_id>` query parameter and loads that game's
JSON, so adding a game means adding a JSON file, not a page. `game_id` is the nflverse ID
(e.g. `2026_04_SEA_ARI`).

Each page has two halves: **the game** (section 7) and **the opponent** (sections 8–9).
Upcoming games render only the opponent half plus a preview header.

---

## 7. Game detail (Section 7)

### 7a. Header

From `load_schedules()`: week, date, kickoff, home/away, stadium, roof, surface, temperature
and wind if outdoors, final score, result (W/L margin), spread line and total line with
whether SEA covered / over or under hit. Opponent logo and colors from `load_teams()`.

### 7b. Box score

Two-column team comparison (SEA vs. opponent), all computed from that game's play-by-play:

| Stat | Definition |
|---|---|
| Points | Final score, plus by-quarter line |
| Total yards | Passing (net of sacks) + rushing |
| Passing yards / Comp-Att / TD / INT | Standard passing line |
| Rushing yards / Att / YPC / TD | Standard rushing line |
| First downs | Count of `first_down == 1` |
| 3rd down | Conversions / attempts |
| 4th down | Conversions / attempts |
| Red zone | TDs / trips |
| Turnovers | Interceptions + fumbles lost |
| Sacks | Sacks made (defense) |
| Penalties | Count and yards |
| Time of possession | From drive data |
| EPA per play | Mean `epa` for each team's offense |
| Success rate | Share of plays with `success == 1` |
| Explosive play rate | Share of plays with ≥ 20 yards passing or ≥ 10 rushing |

### 7c. Scoring summary and drive chart

- Scoring plays in order: quarter, time, team, description, score after.
- Drive table: drive number, team, start yardline, plays, yards, time, result, EPA.
- Win probability line chart across the game (`vegas_wp` for SEA, x = game seconds remaining)
  with scoring plays annotated.

### 7d. Seahawks player stats for this game

From `load_player_stats()` filtered to the game's week, `team == "SEA"`:

- Passing: comp/att, yards, TD, INT, sacks, EPA, passer rating.
- Rushing: att, yards, YPC, TD, EPA, success rate.
- Receiving: targets, receptions, yards, TD, EPA.
- Defense: tackles, TFL, sacks, QB hits, INT, PD, forced fumbles.

### 7e. Situational rushing in this game

Same goal line and 3rd/4th-and-short definitions as sections 4–5, computed for this game only,
offense and defense, with the season rate alongside for context. Sample sizes will be tiny;
always show `n` and never rank single-game situational stats.

---

## 8. Opponent profile (Section 8)

Shown on every game page, for the team SEA played (or will play).

### 8a. Identity and standing

- Team name, logo, colors, division, head coach (`load_schedules()` carries coach names per game).
- Record entering the game (from `load_schedules()`, games before this week) and current record
  at refresh time. Division standing.
- Season result list: each game as a tile (opponent, W/L, score), with the SEA game highlighted.

### 8b. Best win and worst loss (by opponent win percentage)

Both computed from `load_schedules()` for the current season at refresh time.

| Item | Definition |
|---|---|
| Best win | Among the opponent's wins, the beaten team with the **highest** win percentage. Show that team, its record, the score, and the week. |
| Worst loss | Among the opponent's losses, the winning team with the **lowest** win percentage. Show that team, its record, the score, and the week. |

Rules:
- Win percentage = (W + 0.5·T) / games played, for the beaten/winning team's **full current
  record**, not their record at the time of the game. Also store the at-time-of-game record
  so the page can show it as a secondary line ("was 3-1 then, now 6-4").
- Ties on win percentage break toward the team with more games played, then alphabetical.
- SEA can be the answer (if the opponent beat SEA, SEA is a candidate for best win).
- If the opponent has no wins yet, best win shows "none"; likewise for losses.

### 8c. Opponent season averages

The full section 2 stat set (offense and defense, per game, with 1–32 ranks) for the opponent.
No new computation: `team_averages` is already computed for all 32 teams for the splash page,
so this is a lookup. Show as a compact table with SEA's value in a third column for head-to-head
comparison.

Also store a **prior-season baseline** (previous season's per-game averages) so the page can
flag where the opponent is meaningfully up or down from last year.

### 8d. Opponent situational rushing

Sections 4 and 5 for the opponent (their goal line and 3rd-and-short rushing, offense and
defense). Again a lookup — these are computed for all 32 teams. Frame it as "what SEA's run
game faces" / "what SEA's run defense faces."

---

## 9. Opponent quarterback profile (Section 9)

### 9a. Identifying the starter

For a played game: the opponent player with the most `qb_dropback == 1` plays as
`passer_player_id` in that game. For an upcoming game: the opponent's most recent starter by
the same rule. Flag if the game's QB differs from the opponent's usual starter (injury /
benching) and, if so, show both.

### 9b. Bio and experience

From `load_players()` (joined on `gsis_id`):

| Field | Source / definition |
|---|---|
| Name, headshot, jersey number | `load_players()` / `load_rosters()` |
| Age | From `birth_date` at game date |
| Years of experience | `years_of_experience` |
| Draft | `draft_year`, `draft_round`, `draft_pick`, `draft_club`, or "undrafted" |
| College | `college_name` |
| Experience tier | Rookie (0 yrs) · Young (1–3) · Veteran (4–8) · Long-tenured (9+). "Vet" on the page means tier ≥ Veteran; threshold parameterized. |

### 9c. Career stats

Aggregate `load_player_stats(seasons = TRUE)` for the QB's `gsis_id` (available 1999–present):

| Stat | Definition |
|---|---|
| Seasons / games | Count of seasons and weeks with ≥ 1 dropback |
| Career record as starter | From play-by-play: games where he was the primary passer (rule in 9a), W-L-T from `load_schedules()` |
| Comp / Att / Comp % | Sums |
| Passing yards, TD, INT | Sums |
| Yards per attempt | Yards / attempts |
| Passer rating | Standard NFL formula from career sums |
| Sacks taken | Sum |
| Rushing att / yards / TD | Sums |
| Career EPA per dropback | Mean over all seasons (weighted by dropbacks) |
| Per-season table | One row per season: team, games, comp %, yards, TD, INT, rating, EPA/dropback |
| Career vs. SEA | Same line restricted to games against SEA, with W-L |

### 9d. Current season and this game

- Current-season line (same stats as 9c) with league rank among qualified QBs
  (≥ 14 dropbacks per team game; threshold parameterized).
- This game's line (played games only): comp/att, yards, TD, INT, sacks, EPA per dropback,
  success rate, CPOE, and a note on how it compares to his season average.

---

## 10. Data layer additions

### Additional sources

| Function | Used for |
|---|---|
| `load_schedules(season)` | Game headers, coaches, lines, weather; opponent records; best win / worst loss |
| `load_teams()` | Logos, colors, divisions |
| `load_players()` | QB bio, draft, experience |
| `load_player_stats(seasons = TRUE)` | QB career stats (cache locally; refresh only the current season each week) |
| `load_pbp(seasons = TRUE)` | Only for career record as starter and career EPA; compute once per QB, cache, append current season |

### Career-stat caching

Historical seasons never change. Cache `load_player_stats(seasons = TRUE)` and the per-QB
career aggregates on first build (`cache/`), and on each weekly refresh recompute only the
current season and re-sum. Do not pull all-seasons play-by-play in the weekly job.

### Output additions

```
data/
  games/
    index.json               # schedule strip — array of {game_id, week, opponent, home, date,
                             #   result, score, played}
    {game_id}.json           # section 7 — header, box score, scoring, drives, wp series,
                             #   SEA player stats, situational
  opponents/
    {team}.json              # section 8 — identity, record, results, best win / worst loss,
                             #   season averages (with SEA + prior-season columns), situational
  qbs/
    {gsis_id}.json           # section 9 — bio, career totals, per-season table, vs SEA,
                             #   current season with ranks
```

A game page loads three files: `games/{game_id}.json`, `opponents/{team}.json`, and
`qbs/{gsis_id}.json` (the QB id is stored in the game file). Opponent and QB files are shared
across games (a divisional opponent appears twice), so they are written once per refresh.

---

## 11. Open decisions

- Goal line default: inside the 5 vs. inside the 10 (spec defaults to 5, toggle for 10).
- 3rd and short default: ≤ 2 vs. ≤ 3 yards (spec defaults to 2, toggle for 3).
- Whether to include playoffs when they arrive (`season_type`), and whether ranks then
  reset to regular season only.
- Minimum attempts for situational ranks (suggest 10 for goal line, 15 for 3rd and short).
- Chart library: Observable Plot vs. Plotly. Only the weekly sparkline and a rank strip need a
  chart on the splash page; the rest is cards and tables.
- Whether Section 2 should show a "last 4 weeks" column alongside the season average.
- "Vet" threshold for the QB experience tier (spec uses 4+ years; could be 3+).
- Best win / worst loss: whether the headline number uses the beaten/winning team's current
  record or their record at the time of the game (spec headlines current, shows at-time-of-game
  as secondary).
- Whether to include the opponent's playoff games from prior seasons in the prior-season baseline.
- Career record as starter for QBs who split games with another passer: rule is "most dropbacks
  in the game," but a QB who was injured on the opening drive gets credited with neither a start
  nor a decision — acceptable for v1.
- Whether the QB profile should also cover the SEA starting QB for symmetry (cheap once the QB
  pipeline exists).
