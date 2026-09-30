# Seahawks Dashboard

Static dashboard of Seattle Seahawks data built from [nflverse](https://github.com/nflverse/nflverse-data)
with R, hosted on Cloudflare Pages. Spec: [`seahawks-dashboard-spec.md`](seahawks-dashboard-spec.md).

```
R/                 data pipeline (nflreadr + dplyr), entry point R/build.R
site/              the static site Cloudflare Pages serves
  index.html       splash page (Part A)
  game.html        game detail + opponent + QB profile (Part B), reads ?id=<game_id>
  methodology.html definitions
  data/            generated JSON (committed; refreshed weekly by GitHub Actions)
cache/             raw downloads and historical caches (git-ignored)
.github/workflows/refresh.yml   weekly Tuesday-morning rebuild + commit
```

## Run locally

Requires R 4.x with `nflreadr`, `dplyr`, `tidyr`, `purrr`, `jsonlite`.

```powershell
# build site/data for the current season (first run downloads ~30 nflverse files)
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R\build.R
# or an explicit season
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" R\build.R --season 2026

# preview the site (any static server works; this one needs Node)
node scripts\serve.js
# then open http://localhost:8765/
```

All tunable thresholds (goal line 5/10, short 2/3, minimum attempts, RB and QB qualification,
"vet" years) live in `PARAMS` at the top of `R/helpers.R`.

## Deploy

The site is plain static files, so any static host works. Two Cloudflare paths, both free:

- **Cloudflare Pages**: Workers & Pages → Create → Pages → Connect to Git → this repo.
  Build command: *none*. Build output directory: `site`. URL: `https://<project>.pages.dev`.
- **Cloudflare Workers (Import a repository)**: uses `wrangler.jsonc` in this repo, which serves `site/`
  as static assets. Build command: *none*. Deploy command: `npx wrangler deploy`.
  URL: `https://seahawks-dash.<account>.workers.dev`.

GitHub Pages also serves it from the root of `main` at `/site/`.

The `Refresh data` workflow runs every Tuesday at 6am Pacific (and on demand from the Actions tab),
commits `site/data/*.json`, and the host redeploys from the push.

The workflow needs no secrets: it uses the repository's built-in `GITHUB_TOKEN` to push.

## Data notes

- Team rushing uses `rush_attempt == 1` (includes scrambles); the RB table and all situational
  stats use designed runs (`qb_scramble == 0`). Kneel-downs are excluded everywhere.
- Every stat is computed for all 32 teams from the same filtered play-by-play, then ranked.
- Situational rank thresholds are prorated by weeks completed (floor 3) so ranks exist early in the season.
- QB career stats are summed from nflverse weekly player stats (1999–present); historical seasons are cached.
- See `site/methodology.html` for the full list of definitions.
