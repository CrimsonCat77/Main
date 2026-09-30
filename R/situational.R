# Sections 4 and 5: goal line and 3rd/4th-and-short rushing, offense and defense, all teams.
#
# Rushes are designed runs (rush == 1 & qb_scramble == 0). Dropbacks are qb_dropback == 1.
# Offense keys on posteam; defense keys on defteam (what the defense allowed).

GL_DEFS <- tribble(
  ~key,          ~label,                    ~fmt,   ~ranked,
  "ypc",         "Yards per carry",         "num2", FALSE,
  "td_rate",     "TD rate",                 "pct",  TRUE,
  "success",     "Success rate",            "pct",  TRUE,
  "epa_rush",    "EPA per rush",            "epa",  TRUE,
  "rush_share",  "Rush share",              "pct",  FALSE,
  "pass_td_rate","TD rate when passing",    "pct",  FALSE
)
SHORT_DEFS <- tribble(
  ~key,          ~label,                          ~fmt,   ~ranked,
  "conv_rate",   "Conversion rate",               "pct",  TRUE,
  "ypc",         "Yards per carry",               "num2", FALSE,
  "success",     "Success rate",                  "pct",  TRUE,
  "epa_rush",    "EPA per rush",                  "epa",  TRUE,
  "rush_share",  "Rush share",                    "pct",  FALSE,
  "pass_conv",   "Conversion rate when passing",  "pct",  FALSE
)

situ_team <- function(d, team_col, teams) {
  d |> group_by(team = .data[[team_col]]) |>
    summarise(att = sum(designed_rush), yds = sum(rushing_yards[designed_rush], na.rm = TRUE),
              td = sum(rush_touchdown[designed_rush], na.rm = TRUE), conv = sum(converted[designed_rush]),
              succ = sum(success[designed_rush], na.rm = TRUE), epa = sum(epa[designed_rush]),
              db = sum(dropback), db_conv = sum(converted[dropback]), db_td = sum(nz(touchdown)[dropback])) |>
    right_join(tibble(team = teams), by = "team") |>
    mutate(across(-team, nz)) |>
    mutate(ypc = sdiv(yds, att), td_rate = sdiv(td, att), conv_rate = sdiv(conv, att), success = sdiv(succ, att),
           epa_rush = sdiv(epa, att), rush_share = sdiv(att, att + db), pass_conv = sdiv(db_conv, db),
           pass_td_rate = sdiv(db_td, db))
}

situ_players <- function(d, team_col, pos) {
  d |> filter(designed_rush, !is.na(rusher_player_id)) |>
    group_by(team = .data[[team_col]], gsis_id = rusher_player_id) |>
    summarise(att = n(), yds = sum(rushing_yards, na.rm = TRUE), td = sum(rush_touchdown, na.rm = TRUE),
              conv = sum(converted), epa = mean(epa)) |>
    ungroup() |>
    left_join(pos |> select(gsis_id, name, position), by = "gsis_id") |>
    mutate(td_rate = td / att, conv_rate = conv / att, ypc = yds / att) |>
    arrange(team, desc(att))
}

add_ranks <- function(s, defs, hib, threshold) {
  s <- s |> mutate(qualified = att >= threshold, threshold = threshold)
  for (k in defs$key[defs$ranked]) s[[paste0("rank_", k)]] <- rank_dir(ifelse(s$qualified, s[[k]], NA_real_), hib)
  # league values are pooled rates across all 32 teams
  tot <- s |> summarise(across(c(att, yds, td, conv, succ, epa, db, db_conv, db_td), sum))
  s |> mutate(
    n_qualified = sum(qualified),
    avg_ypc = sdiv(tot$yds, tot$att), avg_td_rate = sdiv(tot$td, tot$att), avg_conv_rate = sdiv(tot$conv, tot$att),
    avg_success = sdiv(tot$succ, tot$att), avg_epa_rush = sdiv(tot$epa, tot$att), avg_rush_share = sdiv(tot$att, tot$att + tot$db),
    avg_pass_conv = sdiv(tot$db_conv, tot$db), avg_pass_td_rate = sdiv(tot$db_td, tot$db))
}

# Build every situation × variant × side once. Returns a nested list of summary/players frames.
compute_situational <- function(pbp_f, teams, pos, params, weeks_completed) {
  thr_gl <- prorate_threshold(params$min_att_goal_line, weeks_completed)
  thr_sh <- prorate_threshold(params$min_att_short, weeks_completed)
  out <- list(thresholds = list(goal_line = list(season = params$min_att_goal_line, effective = thr_gl),
                                short = list(season = params$min_att_short, effective = thr_sh)))
  for (side in c("off", "def")) {
    col <- if (side == "off") "posteam" else "defteam"
    hib <- side == "off"
    gl <- list()
    for (v in params$goal_line_variants) {
      d <- pbp_f |> filter(yardline_100 <= v)
      gl[[as.character(v)]] <- list(summary = situ_team(d, col, teams) |> add_ranks(GL_DEFS, hib, thr_gl),
                                    players = situ_players(d, col, pos))
    }
    sh <- list()
    for (v in params$short_variants) {
      blk <- list()
      for (dn in c(3, 4)) {
        d <- pbp_f |> filter(down == dn, ydstogo <= v)
        blk[[if (dn == 3) "third" else "fourth"]] <- list(
          summary = situ_team(d, col, teams) |> add_ranks(SHORT_DEFS, hib, if (dn == 3) thr_sh else 3L),
          players = situ_players(d, col, pos))
      }
      sh[[as.character(v)]] <- blk
    }
    out[[side]] <- list(goal_line = gl, short = sh)
  }
  out
}

situ_block_json <- function(blk, team, defs, hib) {
  s <- blk$summary |> filter(team == !!team)
  stats <- pmap(defs, function(key, label, fmt, ranked) {
    n <- if (key %in% c("pass_conv", "pass_td_rate")) s$db else s$att
    list(key = key, label = label, fmt = fmt, value = s[[key]], n = n,
         rank = if (ranked) s[[paste0("rank_", key)]] else NA, ranked = ranked,
         higher_is_better = hib, league_avg = s[[paste0("avg_", key)]])
  })
  list(att = s$att, yds = s$yds, td = s$td, conv = s$conv, dropbacks = s$db,
       qualified = s$qualified, threshold = s$threshold, n_qualified = s$n_qualified, stats = stats,
       by_player = blk$players |> filter(team == !!team) |> select(gsis_id, name, position, att, yds, ypc, td, td_rate, conv, conv_rate, epa))
}

situational_json <- function(situ, side, team, params) {
  hib <- side == "off"
  s <- situ[[side]]
  list(
    team = team, side = side,
    defaults = list(goal_line = params$goal_line_default, short = params$short_default),
    thresholds = situ$thresholds,
    goal_line = map(s$goal_line, situ_block_json, team = team, defs = GL_DEFS, hib = hib),
    short = map(s$short, function(v) list(third = situ_block_json(v$third, team, SHORT_DEFS, hib),
                                          fourth = situ_block_json(v$fourth, team, SHORT_DEFS, hib)))
  )
}

# Single-game version (section 7e): no ranks, season rate alongside for context.
situ_game_json <- function(pbp_g, situ, team, params) {
  teams <- c(team)
  one <- function(d, col, defs, season_blk) {
    s <- situ_team(d, col, teams)
    season <- season_blk$summary |> filter(team == !!team)
    list(att = s$att, yds = s$yds, td = s$td, conv = s$conv, dropbacks = s$db,
         stats = pmap(defs, function(key, label, fmt, ranked)
           list(key = key, label = label, fmt = fmt, value = s[[key]], n = if (key %in% c("pass_conv", "pass_td_rate")) s$db else s$att,
                season_value = season[[key]], season_n = if (key %in% c("pass_conv", "pass_td_rate")) season$db else season$att)))
  }
  gv <- as.character(params$goal_line_default); sv <- as.character(params$short_default)
  out <- list()
  for (side in c("off", "def")) {
    col <- if (side == "off") "posteam" else "defteam"
    out[[side]] <- list(
      goal_line = one(pbp_g |> filter(yardline_100 <= params$goal_line_default), col, GL_DEFS, situ[[side]]$goal_line[[gv]]),
      third = one(pbp_g |> filter(down == 3, ydstogo <= params$short_default), col, SHORT_DEFS, situ[[side]]$short[[sv]]$third),
      fourth = one(pbp_g |> filter(down == 4, ydstogo <= params$short_default), col, SHORT_DEFS, situ[[side]]$short[[sv]]$fourth))
  }
  out$defaults <- list(goal_line = params$goal_line_default, short = params$short_default)
  out
}
