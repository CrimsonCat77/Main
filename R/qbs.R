# Section 9: opponent quarterback profile.
#
# Starter rule (9a): the passer with the most qb_dropback == 1 plays in the game.
# Career stats (9c): summed from weekly player stats (regular season). "Dropbacks" there are
# attempts + sacks taken, and the per-game primary passer (for the career record as starter) is
# the player with the most attempts + sacks for his team that week - the weekly-stats equivalent
# of the play-by-play rule, which avoids pulling all-seasons play-by-play in the weekly job.

compute_starters <- function(pbp_f, sched_season) {
  st <- pbp_f |> filter(dropback, !is.na(passer_player_id)) |>
    count(game_id, week, posteam, passer_player_id, passer_player_name) |>
    group_by(game_id, posteam) |> slice_max(n, n = 1, with_ties = FALSE) |> ungroup()
  usual <- st |> group_by(posteam, passer_player_id, passer_player_name) |>
    summarise(starts = n(), last_week = max(week)) |> ungroup() |>
    arrange(posteam, desc(starts), desc(last_week)) |> group_by(posteam) |> slice(1) |> ungroup()
  recent <- st |> group_by(posteam) |> slice_max(week, n = 1, with_ties = FALSE) |> ungroup()
  long_all <- schedule_long(sched_season, all = TRUE)

  game_qb <- function(game_id, opp) {
    g <- st |> filter(game_id == !!game_id, posteam == opp)
    u <- usual |> filter(posteam == opp)
    basis <- "game"
    if (!nrow(g)) { g <- recent |> filter(posteam == opp); basis <- "most_recent" }
    if (!nrow(g)) {  # opponent has not played yet: fall back to the schedule's listed QB
      s <- long_all |> filter(game_id == !!game_id, team == opp)
      return(list(gsis_id = s$qb_id %||% NA, name = s$qb_name %||% NA, dropbacks = NA, basis = "schedule",
                  usual_id = NA, usual_name = NA, differs = FALSE))
    }
    list(gsis_id = g$passer_player_id, name = g$passer_player_name, dropbacks = g$n, basis = basis,
         usual_id = u$passer_player_id %||% NA, usual_name = u$passer_player_name %||% NA,
         differs = !is.na(u$passer_player_id %||% NA) && u$passer_player_id != g$passer_player_id)
  }
  list(starts = st, usual = usual, game_qb = game_qb)
}

# Per-season "primary passer" table for every team-game (cached per season in memory).
.primary_cache <- new.env()
primary_passers <- function(s, current_season) {
  key <- as.character(s)
  if (!is.null(.primary_cache[[key]])) return(.primary_cache[[key]])
  ps <- player_stats_season(s, current_season) |> filter(season_type == "REG", attempts + sacks_suffered > 0)
  out <- ps |> mutate(dropbacks = attempts + sacks_suffered) |>
    group_by(season, week, team) |> slice_max(dropbacks, n = 1, with_ties = FALSE) |> ungroup() |>
    select(season, week, team, opponent_team, player_id, dropbacks)
  .primary_cache[[key]] <- out
  out
}

qb_line <- function(d) {
  att <- sum(d$attempts); comp <- sum(d$completions); yds <- sum(d$passing_yards)
  td <- sum(d$passing_tds); int <- sum(d$passing_interceptions); sacks <- sum(d$sacks_suffered)
  db <- att + sacks
  list(games = sum(d$attempts + d$sacks_suffered > 0), comp = comp, att = att, comp_pct = sdiv(comp, att), yds = yds,
       td = td, int = int, ypa = sdiv(yds, att), rating = passer_rating(comp, att, yds, td, int), sacks = sacks,
       dropbacks = db, epa_db = sdiv(sum(d$passing_epa, na.rm = TRUE), db),
       cpoe = if (any(!is.na(d$passing_cpoe))) weighted.mean(d$passing_cpoe, d$attempts, na.rm = TRUE) else NA,
       rush_att = sum(d$carries), rush_yds = sum(d$rushing_yards), rush_td = sum(d$rushing_tds))
}

qb_profile <- function(gsis_id, ctx) {
  season <- ctx$season
  p <- ctx$players |> filter(gsis_id == !!gsis_id) |> slice(1)
  if (!nrow(p)) return(NULL)
  yrs <- p$years_of_experience %||% NA
  tier <- if (is.na(yrs)) NA else if (yrs == 0) "Rookie" else if (yrs <= 3) "Young" else if (yrs <= 8) "Veteran" else "Long-tenured"
  first_season <- min(c(p$rookie_season, p$draft_year, season), na.rm = TRUE)
  seasons <- seq(max(1999, first_season), season)

  rows <- map_dfr(seasons, function(s) player_stats_season(s, season) |> filter(player_id == !!gsis_id, season_type == "REG"))
  rows <- rows |> filter(attempts + sacks_suffered > 0)
  prim <- map_dfr(seasons, primary_passers, current_season = season) |> filter(player_id == !!gsis_id)
  long_hist <- schedule_long(ctx$sched_all |> filter(season %in% seasons)) |> select(season, week, team, result, opp)
  starts <- prim |> inner_join(long_hist, by = c("season", "week", "team"))

  rec <- record_of(starts)
  per_season <- rows |> group_by(season) |> group_map(function(d, k) {
    c(list(season = k$season, team = paste(unique(d$team), collapse = "/")), qb_line(d),
      list(record = record_of(starts |> filter(season == k$season))$text))
  })
  vs_sea <- rows |> filter(opponent_team == TEAM)
  cur <- rows |> filter(season == !!season)

  # Current-season ranks among qualified QBs (>= 14 dropbacks per team game played).
  ps_cur <- player_stats_season(season, season) |> filter(season_type == "REG", position == "QB", attempts + sacks_suffered > 0)
  team_games <- ctx$long_played |> count(team, name = "team_games")
  qual <- ps_cur |> group_by(player_id) |>
    summarise(team = names(which.max(table(team))), comp = sum(completions), att = sum(attempts), yds = sum(passing_yards),
              td = sum(passing_tds), int = sum(passing_interceptions), sacks = sum(sacks_suffered),
              epa = sum(passing_epa, na.rm = TRUE), cpoe = weighted.mean(passing_cpoe, attempts, na.rm = TRUE)) |>
    left_join(team_games, by = "team") |>
    mutate(dropbacks = att + sacks, qualified = dropbacks >= PARAMS$qb_min_dropbacks_pg * team_games,
           comp_pct = comp / att, ypa = yds / att, epa_db = epa / dropbacks,
           rating = pmap_dbl(list(comp, att, yds, td, int), passer_rating)) |>
    filter(qualified)
  rk <- function(col, hib = TRUE) { r <- rank_dir(qual[[col]], hib); r[match(gsis_id, qual$player_id)] }
  ranks <- if (gsis_id %in% qual$player_id) list(yds = rk("yds"), td = rk("td"), int = rk("int", FALSE), comp_pct = rk("comp_pct"),
                                                   ypa = rk("ypa"), rating = rk("rating"), epa_db = rk("epa_db"), cpoe = rk("cpoe")) else NULL

  list(
    gsis_id = gsis_id, name = p$display_name, headshot = p$headshot, jersey = p$jersey_number, birth_date = p$birth_date,
    height = p$height, weight = p$weight, team = p$latest_team, years_of_experience = yrs, tier = tier,
    is_vet = !is.na(yrs) && yrs >= PARAMS$vet_years, vet_threshold = PARAMS$vet_years,
    draft = if (is.na(p$draft_year)) "Undrafted" else sprintf("%d, Round %d, Pick %d (%s)", p$draft_year, p$draft_round, p$draft_pick, p$draft_team),
    college = p$college_name,
    career = c(list(seasons = n_distinct(rows$season), record = rec$text, wins = rec$w, losses = rec$l, ties = rec$t), qb_line(rows)),
    per_season = per_season,
    vs_sea = c(qb_line(vs_sea), list(record = record_of(starts |> filter(opp == TEAM))$text, games_started = sum(starts$opp == TEAM))),
    current = c(list(season = season, qualified = gsis_id %in% qual$player_id, n_qualified = nrow(qual),
                     min_dropbacks = PARAMS$qb_min_dropbacks_pg * (team_games$team_games[team_games$team == p$latest_team] %||% NA)),
                qb_line(cur), list(ranks = ranks))
  )
}

# This game's line for the opponent QB (9d), with the season line for comparison.
qb_game_line <- function(gsis_id, game_id, ps, pbp_g) {
  if (is.na(gsis_id)) return(NULL)
  d <- ps |> filter(game_id == !!game_id, player_id == gsis_id)
  if (!nrow(d)) return(NULL)
  s <- ps |> filter(player_id == gsis_id, season_type == "REG")
  succ <- pbp_g |> filter(dropback, passer_player_id == gsis_id)
  c(qb_line(d), list(success = mean(succ$success, na.rm = TRUE), season = qb_line(s)))
}
