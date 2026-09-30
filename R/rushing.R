# Section 3: team rushing line (3a) and running back table (3b).

RUSH_DEFS <- tribble(
  ~key,          ~label,                      ~fmt,
  "rush_ypg",    "Rushing yards per game",    "num1",
  "att_pg",      "Attempts per game",         "num1",
  "ypc",         "Yards per carry",           "num2",
  "td",          "Rushing TDs",               "int",
  "epa",         "Rushing EPA per play",      "epa",
  "success",     "Rushing success rate",      "pct",
  "rush_share",  "Rush share",                "pct"
)

# Latest roster entry per player, with players.rds as a fallback for anyone missing.
position_lookup <- function(rosters, players) {
  ros <- rosters |> arrange(desc(week)) |> distinct(gsis_id, .keep_all = TRUE) |>
    transmute(gsis_id, position, name = full_name, headshot = headshot_url, jersey = as.integer(jersey_number))
  pl <- players |> transmute(gsis_id, position_p = position, name_p = display_name, headshot_p = headshot,
                             jersey_p = suppressWarnings(as.integer(jersey_number)))
  full_join(ros, pl, by = "gsis_id") |>
    transmute(gsis_id, position = coalesce(position, position_p), name = coalesce(name, name_p),
              headshot = coalesce(headshot, headshot_p), jersey = coalesce(jersey, jersey_p))
}

compute_rushing <- function(pbp_f, sched, pos, params) {
  long  <- schedule_long(sched)
  games <- long |> count(team, name = "games")

  rushes <- pbp_f |> filter(any_rush)
  team <- rushes |>
    group_by(team = posteam) |>
    summarise(att = n(), yds = sum(rushing_yards, na.rm = TRUE), td = sum(rush_touchdown, na.rm = TRUE),
              epa = mean(epa), success = mean(success, na.rm = TRUE),
              designed_att = sum(designed_rush), designed_yds = sum(rushing_yards[designed_rush], na.rm = TRUE)) |>
    left_join(pbp_f |> group_by(team = posteam) |> summarise(dropbacks = sum(dropback)), by = "team") |>
    left_join(games, by = "team") |>
    mutate(rush_ypg = yds / games, att_pg = att / games, ypc = yds / att,
           rush_share = designed_att / (designed_att + dropbacks),
           scramble_att = att - designed_att, scramble_yds = yds - designed_yds)
  for (k in RUSH_DEFS$key) {
    team[[paste0("rank_", k)]] <- rank_dir(team[[k]], TRUE)
    team[[paste0("avg_", k)]]  <- mean(team[[k]], na.rm = TRUE)
  }

  # 3b: designed runs by player (QB scrambles excluded), per player-team and per player.
  by_pt <- pbp_f |> filter(designed_rush, !is.na(rusher_player_id)) |>
    group_by(team = posteam, gsis_id = rusher_player_id) |>
    summarise(games = n_distinct(game_id), att = n(), yds = sum(rushing_yards, na.rm = TRUE),
              td = sum(rush_touchdown, na.rm = TRUE), epa = mean(epa), success = mean(success, na.rm = TRUE),
              explosive = mean(rushing_yards >= 10, na.rm = TRUE)) |>
    ungroup()
  league <- pbp_f |> filter(designed_rush, !is.na(rusher_player_id)) |>
    group_by(gsis_id = rusher_player_id) |>
    summarise(games = n_distinct(game_id), att = n(), yds = sum(rushing_yards, na.rm = TRUE)) |>
    left_join(pos, by = "gsis_id") |>
    filter(position %in% c("RB", "FB")) |>
    mutate(att_pg = att / games, ypg = yds / games, qualified = att_pg >= params$rb_min_carries_pg) |>
    mutate(league_rank = rank_dir(ifelse(qualified, ypg, NA_real_), TRUE), n_qualified = sum(qualified))

  rbs <- by_pt |> left_join(pos, by = "gsis_id") |> filter(position %in% c("RB", "FB")) |>
    left_join(league |> select(gsis_id, league_rank, qualified, n_qualified), by = "gsis_id") |>
    mutate(att_pg = att / games, ypg = yds / games, ypc = yds / att, is_fb = position == "FB")

  list(team = team, rbs = rbs, weekly = rushes |> filter(posteam == TEAM) |>
         group_by(week, game_id) |> summarise(yds = sum(rushing_yards, na.rm = TRUE), att = n(), epa = mean(epa)) |>
         left_join(long |> filter(team == TEAM) |> select(game_id, opp, home, result), by = "game_id") |> arrange(week))
}

rushing_team_json <- function(r, team) {
  row <- r$team |> filter(team == !!team)
  stats <- pmap(RUSH_DEFS, function(key, label, fmt)
    list(key = key, label = label, fmt = fmt, value = row[[key]], n = if (key %in% c("rush_ypg", "att_pg", "td")) row$games else row$att,
         rank = row[[paste0("rank_", key)]], higher_is_better = TRUE, league_avg = row[[paste0("avg_", key)]]))
  list(
    team = team, games = row$games, stats = stats,
    totals = list(all_rushes = list(att = row$att, yds = row$yds),
                  designed = list(att = row$designed_att, yds = row$designed_yds),
                  scrambles = list(att = row$scramble_att, yds = row$scramble_yds)),
    weekly = r$weekly
  )
}

rushing_rbs_json <- function(r, team) {
  rows <- r$rbs |> filter(team == !!team) |> arrange(desc(ypg))
  tot <- rows |> summarise(games = max(games), epa = weighted.mean(epa, att), success = weighted.mean(success, att),
                           explosive = weighted.mean(explosive, att), att = sum(att), yds = sum(yds), td = sum(td)) |>
    mutate(att_pg = att / games, ypg = yds / games, ypc = yds / att)
  list(
    players = rows |> transmute(gsis_id, name, position, is_fb, jersey, headshot, games, att, att_pg, yds, ypg, ypc, td,
                                epa, success, explosive, league_rank, qualified, n_qualified),
    totals = as.list(tot),
    threshold = list(min_carries_per_game = PARAMS$rb_min_carries_pg,
                     n_qualified = if (nrow(rows)) rows$n_qualified[1] else NA)
  )
}
