# Section 2: per-game team averages for all 32 teams, with ranks and league averages.

STAT_DEFS <- tribble(
  ~key,                 ~label,                          ~group,    ~hib,  ~fmt,   ~n_kind,
  "ppg",                "Points per game",               "offense", TRUE,  "num1", "games",
  "ypg",                "Total yards per game",          "offense", TRUE,  "num1", "games",
  "pass_ypg",           "Passing yards per game",        "offense", TRUE,  "num1", "games",
  "rush_ypg",           "Rushing yards per game",        "offense", TRUE,  "num1", "games",
  "ypp",                "Yards per play",                "offense", TRUE,  "num2", "plays",
  "epa_play",           "EPA per play",                  "offense", TRUE,  "epa",  "plays",
  "success",            "Success rate",                  "offense", TRUE,  "pct",  "plays",
  "third_pct",          "3rd down conversion %",         "offense", TRUE,  "pct",  "third_att",
  "rz_td_pct",          "Red zone TD %",                 "offense", TRUE,  "pct",  "rz_trips",
  "to_pg",              "Turnovers per game",            "offense", FALSE, "num1", "games",
  "top",                "Time of possession",            "offense", TRUE,  "time", "games",
  "ppg_allowed",        "Points allowed per game",       "defense", FALSE, "num1", "games",
  "ypg_allowed",        "Total yards allowed per game",  "defense", FALSE, "num1", "games",
  "pass_ypg_allowed",   "Passing yards allowed per game","defense", FALSE, "num1", "games",
  "rush_ypg_allowed",   "Rushing yards allowed per game","defense", FALSE, "num1", "games",
  "ypp_allowed",        "Yards per play allowed",        "defense", FALSE, "num2", "plays",
  "epa_play_allowed",   "EPA per play allowed",          "defense", FALSE, "epa",  "plays",
  "success_allowed",    "Success rate allowed",          "defense", FALSE, "pct",  "plays",
  "third_pct_allowed",  "3rd down conversion % allowed", "defense", FALSE, "pct",  "third_att",
  "takeaways_pg",       "Takeaways per game",            "defense", TRUE,  "num1", "games",
  "sacks_pg",           "Sacks per game",                "defense", TRUE,  "num1", "games"
)

# Offensive summary keyed by whichever team column is passed (posteam = offense, defteam = the
# opponent's offense, i.e. what this defense allowed).
side_summary <- function(pbp_f, pbp_raw, team_col) {
  base <- pbp_f |>
    group_by(team = .data[[team_col]]) |>
    summarise(
      plays     = n(),
      pass_yds  = sum(passing_yards, na.rm = TRUE) + sum(yards_gained[sack == 1], na.rm = TRUE),
      rush_yds  = sum(rushing_yards, na.rm = TRUE),
      epa_sum   = sum(epa),
      succ      = sum(success, na.rm = TRUE),
      third_att = sum(down == 3, na.rm = TRUE),
      third_conv= sum(down == 3 & third_down_converted == 1, na.rm = TRUE),
      turnovers = sum(nz(interception) == 1 | nz(fumble_lost) == 1),
      sacks     = sum(sack == 1, na.rm = TRUE)
    ) |>
    mutate(yards = pass_yds + rush_yds)
  rz <- pbp_f |>
    group_by(team = .data[[team_col]], game_id, fixed_drive) |>
    summarise(trip = any(yardline_100 <= 20, na.rm = TRUE), td = first(fixed_drive_result) == "Touchdown") |>
    filter(trip) |>
    group_by(team) |>
    summarise(rz_trips = n(), rz_td = sum(td, na.rm = TRUE))
  top <- pbp_raw |>
    filter(season_type == "REG", !is.na(.data[[team_col]]), !is.na(drive_time_of_possession)) |>
    distinct(team = .data[[team_col]], game_id, fixed_drive, drive_time_of_possession) |>
    mutate(sec = mmss_to_sec(drive_time_of_possession)) |>
    group_by(team) |>
    summarise(top_sec = sum(sec, na.rm = TRUE))
  base |> left_join(rz, by = "team") |> left_join(top, by = "team")
}

compute_team_averages <- function(pbp_f, pbp_raw, sched) {
  long  <- schedule_long(sched)
  games <- long |> group_by(team) |> summarise(games = n(), pts = sum(pts), pts_allowed = sum(pts_allowed))
  off <- side_summary(pbp_f, pbp_raw, "posteam")
  def <- side_summary(pbp_f, pbp_raw, "defteam") |> rename_with(~ paste0(.x, "_d"), -team)

  wide <- games |> inner_join(off, by = "team") |> inner_join(def, by = "team") |>
    transmute(
      team, games,
      ppg = pts / games, ypg = yards / games, pass_ypg = pass_yds / games, rush_ypg = rush_yds / games,
      ypp = yards / plays, epa_play = epa_sum / plays, success = succ / plays,
      third_pct = sdiv(third_conv, third_att), rz_td_pct = sdiv(rz_td, rz_trips),
      to_pg = turnovers / games, top = top_sec / games,
      ppg_allowed = pts_allowed / games, ypg_allowed = yards_d / games, pass_ypg_allowed = pass_yds_d / games,
      rush_ypg_allowed = rush_yds_d / games, ypp_allowed = yards_d / plays_d, epa_play_allowed = epa_sum_d / plays_d,
      success_allowed = succ_d / plays_d, third_pct_allowed = sdiv(third_conv_d, third_att_d),
      takeaways_pg = turnovers_d / games, sacks_pg = sacks_d / games,
      # sample sizes
      n_games = games, n_plays = plays, n_third_att = third_att, n_rz_trips = rz_trips,
      n_plays_d = plays_d, n_third_att_d = third_att_d
    )

  long_stats <- STAT_DEFS |>
    pmap_dfr(function(key, label, group, hib, fmt, n_kind) {
      k <- key
      ncol <- switch(n_kind, games = "n_games", plays = if (group == "offense") "n_plays" else "n_plays_d",
                     third_att = if (group == "offense") "n_third_att" else "n_third_att_d", rz_trips = "n_rz_trips")
      v <- wide[[k]]; nn <- wide[[ncol]]
      tibble(team = wide$team, key = k, label = label, group = group, fmt = fmt,
             value = v, n = nn, higher_is_better = hib) |>
        mutate(rank = rank_dir(value, hib), league_avg = mean(value, na.rm = TRUE))
    })
  list(wide = wide, long = long_stats)
}

team_averages_list <- function(ta, team) {
  ta$long |> filter(team == !!team) |>
    pmap(function(team, key, label, group, fmt, value, n, higher_is_better, rank, league_avg)
      list(key = key, label = label, group = group, fmt = fmt, value = value, n = n,
           rank = rank, higher_is_better = higher_is_better, league_avg = league_avg))
}
