# Maintenance notes

Working notes for future updates to the Seahawks dashboard. The spec is
`seahawks-dashboard-spec.md`; the README covers setup. This file is the "what you need to know
before touching it" list. Last updated 2026-09-30 (season 2026, through week 3).

## Where things are

| Thing | Location |
|---|---|
| Live site (primary) | https://seahawks-dash.ewpicton.workers.dev (Cloudflare Worker `seahawks-dash`, static assets from `site/`) |
| Live site (backup) | https://crimsoncat77.github.io/Main/site/ (GitHub Pages, root of `main`) |
| Repo | https://github.com/CrimsonCat77/Main (branch `main`) |
| Weekly refresh | GitHub Actions "Refresh data", Tuesdays 6am Pacific + manual: https://github.com/CrimsonCat77/Main/actions |
| Local checkout | `C:\Users\ewpic\OneDrive\Desktop\dir\nfl_seahawks` |
| R | `C:\Program Files\R\R-4.5.1\bin\Rscript.exe` (not on PATH) |

Deploy chain: any push to `main` (including the bot's data commits) redeploys Cloudflare and
GitHub Pages. Cloudflare's build queue can take 15+ minutes before it starts; the previous
deployment stays live meanwhile. No secrets are involved anywhere.

## Everyday commands (PowerShell)

```powershell
cd C:\Users\ewpic\OneDrive\Desktop\dir\nfl_seahawks
git pull                                                   # pick up the bot's weekly data commits first
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R\build.R   # rebuild site/data (about 20-40 s)
node scripts\serve.js                                      # preview at http://localhost:8765/
git add . ; git commit -m "..." ; git push                 # deploys
```

Run R from PowerShell. Running Rscript from Git Bash segfaulted silently on this machine.
Do not use Python for anything in this project (pipeline or tooling); the owner asked for R only.

Force a data refresh without a local build: Actions tab → Refresh data → Run workflow.

## How the pipeline is laid out

`R/build.R` sources the modules in order and writes JSON. Everything is computed for all 32
teams first, then the Seahawks (and each opponent) are looked up from those tables.

| File | Spec section | Notes |
|---|---|---|
| `R/helpers.R` | 6 | `PARAMS` (all thresholds/toggles), `filter_pbp()`, `schedule_long()`, `record_of()`, ranking + JSON helpers |
| `R/load.R` | 6, 10 | nflreadr loaders with an on-disk cache in `cache/` (git-ignored). Current-season files always re-download; older seasons are cached forever. Player stats are also memoised in memory per run |
| `R/team_averages.R` | 2 | `STAT_DEFS` table drives labels, direction, formats. Add a stat = add a row + a column in `compute_team_averages()` |
| `R/rushing.R` | 3 | team rushing line, weekly series, RB table with league rank |
| `R/situational.R` | 4, 5, 7e | goal line and 3rd/4th-and-short, both toggle variants, offense and defense, all teams |
| `R/games.R` | 7 | header, box score, scoring summary, drives, win-probability series, player stats, `games/index.json` |
| `R/opponents.R` | 8 | identity, records, standings, best win / worst loss, averages vs SEA + prior season, situational lookup |
| `R/qbs.R` | 9 | starter identification, bio, career from weekly stats, per-season table, current-season ranks, this-game line |

Output shapes: every stat object is `{key, label, fmt, value, n, rank, higher_is_better, league_avg}`;
`fmt` (`num1`, `num2`, `int`, `pct`, `epa`, `time`) tells the page how to format it. Ranks are
`null` when not ranked, and situational blocks carry `qualified`, `threshold`, `n_qualified`.

Frontend: `site/assets/common.js` (formatting, rank pills, stat cards, sparkline, WP chart),
`site/assets/app.js` (splash page), `site/assets/game.js` (game/opponent/QB page). Vanilla JS,
no build step, no libraries. Light/dark theme via CSS variables in `site/assets/style.css`.

## Data definitions that were decided during the build

These are the calls that are not obvious from the spec; see `site/methodology.html` for the
user-facing version.

- nflfastR flags scrambles as `rush == 0`, `qb_scramble == 1`, `rush_attempt == 1`. Team-level
  rushing uses `rush_attempt == 1` (matches box scores); RB table and situational stats use designed
  runs (`rush_attempt == 1 & qb_scramble == 0`). Kneel-downs are excluded by the play filter, so
  team rushing totals are a yard or two off the official numbers.
- Situational rank thresholds (10 goal line, 15 short) are prorated by weeks completed with a floor
  of 3 (`prorate_threshold()`), otherwise nothing ranks until midseason. `meta.json` records both.
- Situational league averages are pooled rates across all teams; Section 2 league averages are
  the mean of the 32 team values.
- QB career stats come from weekly player stats (regular season), not all-seasons play-by-play.
  Dropbacks = attempts + sacks. "Primary passer" for the career record = most dropbacks for his
  team that week.
- Division standings: win pct, then point differential. Not the real NFL tiebreakers.
- Prior-season baseline is regular season only.
- Turnovers/takeaways count offensive snaps only (no special-teams turnovers).

## Gotchas hit during development

- **dplyr sequential evaluation**: inside `mutate()`, `summarise()` and `tibble()`, a column you
  just created shadows any variable of the same name for the rest of the call. This caused three
  separate bugs (`key`, `att`, `t`). Use different names or compute weights before overwriting.
- **Column vs argument name clashes in `filter()`**: `schedule_long()` frames have a column `opp`,
  so `filter(team == opp)` compares against the column. Use `!!opp` or rename the argument.
- **`passer_rating()` must stay vectorised** (it is used inside `transmute`).
- **GitHub token scope**: pushing anything under `.github/workflows/` needs the `workflow` scope
  (`gh auth refresh -h github.com -s workflow`). Already granted on this machine.
- **Cloudflare**: the Worker name in `wrangler.jsonc` must match the Worker's name in the dashboard
  (`seahawks-dash`). The Cloudflare "Create" screen hides Pages; the Worker path with
  `wrangler.jsonc` is what is in use.
- **GitHub disables scheduled workflows after 60 days without commits**. Harmless in the offseason;
  one manual "Run workflow" re-enables it when the new season starts.

## Verification that exists

- `meta.json` → `cross_check` compares play-by-play passing/rushing totals with `load_team_stats()`.
- Headless page test: a jsdom script was used during the build (not checked in) to load each page
  against `node scripts\serve.js` and confirm no script errors. The site has not been visually
  reviewed in a real browser; do that after any CSS or layout change.
- Every data file was fetched from the live Cloudflare URL after deploy (54/54 OK).

## New season checklist

1. `R/build.R` defaults to `nflreadr::most_recent_season()`, so nothing to change; pass
   `--season YYYY` to build a specific year.
2. Run the workflow manually once nflverse has week 1 data (usually the Tuesday after).
3. Check `meta.json` `n_games` and the situational thresholds; with 1 week of data most situational
   ranks will be `n/a` (expected).
4. Delete nothing in `cache/` on CI; the actions cache key rolls forward automatically.

## Open items / ideas

- Shorten the URL: buy a domain via Cloudflare Registrar and attach under Worker → Settings →
  Domains & Routes; or create a Cloudflare Pages project (`<name>.pages.dev`, output dir `site`);
  or rename the Worker + account subdomain.
- Delete the accidental "Dashboard Template" Worker in the Cloudflare account.
- Spec open decisions not yet done: playoffs handling (`season_type`, currently REG only), a
  "last 4 weeks" column in Section 2, a matching profile for the Seahawks' own QB (cheap: the
  QB pipeline already exists, call `qb_profile()` for the SEA starter).
- Situational "by player" tables on the defense side list opposing rushers; consider hiding or
  relabelling.
- Visual QA in a real browser, especially the win-probability chart hover and dark mode.
- `games/index.json` includes bye weeks; playoff games would need `game_type != "REG"` handling in
  `games_index()` and `sea_games`.
