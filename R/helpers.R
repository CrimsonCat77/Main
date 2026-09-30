# Shared helpers: parameters, play-by-play filters, stat objects, ranking, JSON.
suppressWarnings(suppressPackageStartupMessages({
  library(nflreadr)
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(jsonlite)
}))
options(nflreadr.verbose = FALSE, dplyr.summarise.inform = FALSE, warn = 1)

TEAM <- "SEA"

# ---- Parameters (spec section 11 "open decisions" are all set here) --------------------------
PARAMS <- list(
  goal_line_default   = 5,     # yardline_100 <= 5 (toggle: 10)
  goal_line_variants  = c(5, 10),
  short_default       = 2,     # ydstogo <= 2 (toggle: 3)
  short_variants      = c(2, 3),
  min_att_goal_line   = 10,    # full-season minimum attempts for situational ranks
  min_att_short       = 15,
  rb_min_carries_pg   = 5,     # league RB rank threshold (carries per game)
  qb_min_dropbacks_pg = 14,    # qualified QB threshold (dropbacks per team game)
  vet_years           = 4,     # experience tier: Veteran starts at this many years
  include_playoffs    = FALSE  # ranks and averages use regular season only
)

# Situational thresholds are prorated by weeks completed (min 3) so ranks exist early in
# the season; the full-season values above apply from week 17 on. Both are written to meta.
prorate_threshold <- function(full, weeks_completed) {
  max(3L, as.integer(round(full * min(weeks_completed, 17) / 17)))
}

# ---- Small utilities ------------------------------------------------------------------------
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a
sdiv <- function(a, b) ifelse(is.na(b) | b == 0, NA_real_, a / b)
nz <- function(x) ifelse(is.na(x), 0, x)

rank_dir <- function(x, higher_is_better = TRUE) {
  r <- if (higher_is_better) rank(-x, ties.method = "min", na.last = "keep")
       else rank(x, ties.method = "min", na.last = "keep")
  as.integer(r)
}

mmss_to_sec <- function(s) {
  p <- strsplit(as.character(s), ":", fixed = TRUE)
  vapply(p, function(v) if (length(v) == 2) as.numeric(v[1]) * 60 + as.numeric(v[2]) else NA_real_, 1)
}
sec_to_mmss <- function(x) ifelse(is.na(x), NA_character_, sprintf("%d:%02d", as.integer(x) %/% 60, as.integer(x) %% 60))

passer_rating <- function(comp, att, yds, td, int) {
  # vectorised NFL passer rating; NA where there are no attempts
  cl <- function(v) pmax(0, pmin(2.375, v))
  a <- cl((comp / att - 0.3) * 5); b <- cl((yds / att - 3) * 0.25)
  c <- cl(td / att * 20);          d <- cl(2.375 - int / att * 25)
  r <- round((a + b + c + d) / 6 * 100, 1)
  ifelse(is.na(att) | att == 0, NA_real_, r)
}

# A stat object: the page renders value / rank / league average and shows n on hover.
st <- function(value, n = NULL, rank = NULL, higher_is_better = TRUE, league_avg = NULL, ...) {
  c(list(value = value %||% NA, n = n %||% NA, rank = rank %||% NA,
         higher_is_better = higher_is_better, league_avg = league_avg %||% NA), list(...))
}

write_json <- function(x, path) {
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  writeLines(toJSON(x, auto_unbox = TRUE, na = "null", null = "null", digits = 4, pretty = FALSE), path, useBytes = TRUE)
}

# ---- Play-by-play filter (spec section 6) --------------------------------------------------
filter_pbp <- function(pbp) {
  pbp |>
    filter(season_type == "REG", !is.na(epa), play_type %in% c("run", "pass"),
           penalty == 0 | !is.na(yards_gained)) |>
    mutate(
      # nflfastR: rush_attempt == 1 covers designed runs AND scrambles (matches box-score rushing);
      # rush == 1 is designed runs only (scrambles are pass == 1 plays with qb_scramble == 1).
      any_rush      = nz(rush_attempt) == 1,
      designed_rush = nz(rush_attempt) == 1 & nz(qb_scramble) == 0,
      dropback      = qb_dropback == 1,
      converted     = nz(first_down) == 1 | nz(touchdown) == 1,
      explosive     = (pass == 1 & yards_gained >= 20) | (rush == 1 & yards_gained >= 10)
    )
}

# Schedule in long form: one row per team-game (played games only unless all = TRUE).
schedule_long <- function(sched, all = FALSE) {
  s <- sched |> filter(game_type == "REG")
  if (!all) s <- s |> filter(!is.na(home_score))
  bind_rows(
    s |> transmute(game_id, season, week, gameday, team = home_team, opp = away_team, home = TRUE,
                   pts = home_score, pts_allowed = away_score, coach = home_coach, qb_name = home_qb_name, qb_id = home_qb_id),
    s |> transmute(game_id, season, week, gameday, team = away_team, opp = home_team, home = FALSE,
                   pts = away_score, pts_allowed = home_score, coach = away_coach, qb_name = away_qb_name, qb_id = away_qb_id)
  ) |>
    mutate(result = case_when(is.na(pts) ~ NA_character_, pts > pts_allowed ~ "W", pts < pts_allowed ~ "L", TRUE ~ "T")) |>
    arrange(team, week)
}

record_of <- function(long_team) {
  w <- sum(long_team$result == "W", na.rm = TRUE); l <- sum(long_team$result == "L", na.rm = TRUE)
  t <- sum(long_team$result == "T", na.rm = TRUE); g <- w + l + t
  list(w = w, l = l, t = t, games = g, pct = if (g > 0) (w + 0.5 * t) / g else NA,
       text = if (t > 0) sprintf("%d-%d-%d", w, l, t) else sprintf("%d-%d", w, l))
}
