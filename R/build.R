#!/usr/bin/env Rscript
# Build every JSON file the dashboard reads.
#   Rscript R/build.R                 # current season
#   Rscript R/build.R --season 2026   # explicit season
# Output goes to site/data/ (Cloudflare Pages serves site/).

args <- commandArgs(trailingOnly = TRUE)
script_dir <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1]))
setwd(normalizePath(file.path(script_dir, "..")))
for (f in c("helpers", "load", "team_averages", "rushing", "situational", "games", "opponents", "qbs")) source(file.path("R", paste0(f, ".R")))

season <- if ("--season" %in% args) as.integer(args[which(args == "--season") + 1]) else nflreadr::most_recent_season()
out_dir <- if ("--out" %in% args) args[which(args == "--out") + 1] else file.path("site", "data")
message("Building season ", season, " -> ", out_dir)
t0 <- Sys.time()

# ---- Load ----------------------------------------------------------------------------------
data <- load_all(season)
sched_season <- data$sched_all |> filter(season == !!season)
sched_prior  <- data$sched_all |> filter(season == !!season - 1)
pbp_f <- filter_pbp(data$pbp)
teams <- sort(data$teams$team_abbr)
weeks_completed <- max(sched_season$week[!is.na(sched_season$home_score) & sched_season$game_type == "REG"], 0)
pos <- position_lookup(data$rosters, data$players)
long_played <- schedule_long(sched_season)
long_all <- schedule_long(sched_season, all = TRUE)
ps <- player_stats_season(season, season)

# ---- Compute (all 32 teams, once) ----------------------------------------------------------
message("Team averages")
ta <- compute_team_averages(pbp_f, data$pbp, sched_season)
ta_prior <- cached(paste0("team_averages_", season - 1),
                   function() compute_team_averages(filter_pbp(data$pbp_prior), data$pbp_prior, sched_prior))
message("Rushing")
rush <- compute_rushing(pbp_f, sched_season, pos, PARAMS)
message("Situational")
situ <- compute_situational(pbp_f, teams, pos, PARAMS, weeks_completed)
starters <- compute_starters(pbp_f, sched_season)

ctx <- list(season = season, teams = data$teams, players = data$players, sched_all = data$sched_all,
            long_played = long_played, long_all = long_all, ta = ta, ta_prior = ta_prior, situ = situ)

# ---- Part A: splash page -------------------------------------------------------------------
sea_rec <- record_of(long_played |> filter(team == TEAM))
cross <- data$team_stats |> filter(team == TEAM, season_type == "REG") |>
  summarise(pass_net = sum(passing_yards + sack_yards_lost), rush = sum(rushing_yards))
sea_wide <- ta$wide |> filter(team == TEAM)
meta <- list(
  season = season, team = TEAM, week = weeks_completed, record = sea_rec,
  games_played = sea_rec$games, refreshed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  pbp_updated = as.character(attr(data$pbp, "nflverse_timestamp") %||% NA),
  params = PARAMS, thresholds = situ$thresholds,
  cross_check = list(source = "load_team_stats()", pass_net_yards = list(pbp = sea_wide$pass_ypg * sea_wide$games, team_stats = cross$pass_net),
                     rush_yards = list(pbp = sea_wide$rush_ypg * sea_wide$games, team_stats = cross$rush)),
  n_games = list(min = min(ta$wide$games), max = max(ta$wide$games))
)
write_json(meta, file.path(out_dir, "meta.json"))
write_json(team_averages_list(ta, TEAM), file.path(out_dir, "team_averages.json"))
write_json(rushing_team_json(rush, TEAM), file.path(out_dir, "rushing_team.json"))
write_json(rushing_rbs_json(rush, TEAM), file.path(out_dir, "rushing_rbs.json"))
write_json(situational_json(situ, "off", TEAM, PARAMS), file.path(out_dir, "situational_off.json"))
write_json(situational_json(situ, "def", TEAM, PARAMS), file.path(out_dir, "situational_def.json"))

# ---- Part B: games, opponents, QBs ---------------------------------------------------------
message("Games")
sea_games <- sched_season |> filter(game_type == "REG", home_team == TEAM | away_team == TEAM) |> arrange(week)
write_json(games_index(sched_season, data$teams), file.path(out_dir, "games", "index.json"))
qb_ids <- character(0)
opp_weeks <- list()
for (i in seq_len(nrow(sea_games))) {
  g <- sea_games[i, ]
  gj <- build_game(g, data$pbp, pbp_f, ps, data$teams, situ, starters, PARAMS)
  if (gj$header$played) gj$qb$game_line <- qb_game_line(gj$qb$gsis_id, g$game_id, ps, pbp_f |> filter(game_id == g$game_id))
  gj$files <- list(opponent = sprintf("opponents/%s.json", gj$header$opponent),
                   qb = if (!is.na(gj$qb$gsis_id %||% NA)) sprintf("qbs/%s.json", gj$qb$gsis_id) else NA)
  write_json(gj, file.path(out_dir, "games", paste0(g$game_id, ".json")))
  qb_ids <- c(qb_ids, gj$qb$gsis_id, gj$qb$usual_id)
  opp <- gj$header$opponent
  opp_weeks[[opp]] <- c(opp_weeks[[opp]], g$week)
}

message("Opponents")
for (opp in names(opp_weeks)) {
  # record_entering uses the first meeting; the page shows record_current alongside
  write_json(opponent_json(opp, min(opp_weeks[[opp]]), ctx), file.path(out_dir, "opponents", paste0(opp, ".json")))
}

message("Quarterbacks")
for (id in unique(na.omit(qb_ids))) {
  prof <- qb_profile(id, ctx)
  if (!is.null(prof)) write_json(prof, file.path(out_dir, "qbs", paste0(id, ".json")))
}

message("Done in ", round(as.numeric(difftime(Sys.time(), t0, units = "secs"))), "s")
