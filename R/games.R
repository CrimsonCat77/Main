# Section 7: one JSON per Seahawks game (header, box score, scoring, drives, win probability,
# player stats, single-game situational rushing) plus games/index.json for the schedule strip.

team_identity <- function(teams, abbr) {
  t <- teams |> filter(team_abbr == abbr)
  if (!nrow(t)) return(list(abbr = abbr))
  list(abbr = abbr, name = t$team_name, nick = t$team_nick, conf = t$team_conf, division = t$team_division,
       color = t$team_color, color2 = t$team_color2, logo = t$team_logo_espn, wordmark = t$team_wordmark)
}

game_header <- function(g, teams) {
  sea_home <- g$home_team == TEAM
  opp <- if (sea_home) g$away_team else g$home_team
  played <- !is.na(g$home_score)
  sea_pts <- if (sea_home) g$home_score else g$away_score
  opp_pts <- if (sea_home) g$away_score else g$home_score
  sea_spread <- if (sea_home) g$spread_line else -g$spread_line   # positive = SEA favored by
  margin <- sea_pts - opp_pts
  covered <- if (!played || is.na(sea_spread)) NA else if (margin + sea_spread > 0) "covered" else if (margin + sea_spread < 0) "lost" else "push"
  total <- sea_pts + opp_pts
  total_result <- if (!played || is.na(g$total_line)) NA else if (total > g$total_line) "over" else if (total < g$total_line) "under" else "push"
  list(
    game_id = g$game_id, season = g$season, week = g$week, gameday = g$gameday, weekday = g$weekday, gametime = g$gametime,
    home = sea_home, opponent = opp, opponent_identity = team_identity(teams, opp),
    stadium = g$stadium, roof = g$roof, surface = g$surface, temp = g$temp, wind = g$wind, div_game = g$div_game == 1,
    played = played, sea_score = sea_pts, opp_score = opp_pts, margin = margin,
    result = if (!played) NA else if (margin > 0) "W" else if (margin < 0) "L" else "T",
    spread_line = sea_spread, covered = covered, total_line = g$total_line, total = if (played) total else NA,
    total_result = total_result,
    sea_coach = if (sea_home) g$home_coach else g$away_coach, opp_coach = if (sea_home) g$away_coach else g$home_coach,
    sea_qb = if (sea_home) g$home_qb_name else g$away_qb_name, opp_qb = if (sea_home) g$away_qb_name else g$home_qb_name,
    referee = g$referee, overtime = g$overtime == 1
  )
}

box_team <- function(pbp_g, pbp_g_raw, team, pts) {
  o <- pbp_g |> filter(posteam == team); d <- pbp_g |> filter(defteam == team)
  p <- o |> filter(pass == 1)
  rz <- o |> group_by(fixed_drive) |> summarise(trip = any(yardline_100 <= 20), td = first(fixed_drive_result) == "Touchdown") |> filter(trip)
  pen <- pbp_g_raw |> filter(nz(penalty) == 1, penalty_team == team)
  top <- pbp_g_raw |> filter(posteam == team, !is.na(drive_time_of_possession)) |> distinct(fixed_drive, drive_time_of_possession)
  pass_yds <- sum(p$passing_yards, na.rm = TRUE) + sum(p$yards_gained[p$sack == 1], na.rm = TRUE)
  rush_yds <- sum(o$rushing_yards[o$any_rush], na.rm = TRUE)
  list(
    points = pts, total_yards = pass_yds + rush_yds, plays = nrow(o),
    pass_yards = pass_yds, comp = sum(p$complete_pass, na.rm = TRUE), att = sum(p$pass_attempt == 1 & p$sack == 0, na.rm = TRUE),
    pass_td = sum(p$pass_touchdown, na.rm = TRUE), int = sum(p$interception, na.rm = TRUE), sacks_taken = sum(p$sack, na.rm = TRUE),
    rush_yards = rush_yds, rush_att = sum(o$any_rush), rush_ypc = sdiv(rush_yds, sum(o$any_rush)), rush_td = sum(o$rush_touchdown, na.rm = TRUE),
    first_downs = sum(o$first_down == 1, na.rm = TRUE),
    third_att = sum(o$down == 3, na.rm = TRUE), third_conv = sum(o$down == 3 & o$third_down_converted == 1, na.rm = TRUE),
    fourth_att = sum(o$down == 4, na.rm = TRUE), fourth_conv = sum(o$down == 4 & o$fourth_down_converted == 1, na.rm = TRUE),
    rz_trips = nrow(rz), rz_td = sum(rz$td, na.rm = TRUE),
    turnovers = sum(nz(o$interception) == 1 | nz(o$fumble_lost) == 1),
    sacks = sum(d$sack, na.rm = TRUE),
    penalties = nrow(pen), penalty_yards = sum(pen$penalty_yards, na.rm = TRUE),
    top = sum(mmss_to_sec(top$drive_time_of_possession), na.rm = TRUE),
    epa_play = mean(o$epa), success = mean(o$success, na.rm = TRUE), explosive = mean(o$explosive, na.rm = TRUE)
  )
}

by_quarter <- function(pbp_g_raw, sea_home) {
  q <- pbp_g_raw |> filter(!is.na(qtr), !is.na(total_home_score)) |> group_by(qtr) |>
    summarise(h = max(total_home_score), a = max(total_away_score)) |> arrange(qtr) |>
    mutate(hq = h - lag(h, default = 0), aq = a - lag(a, default = 0))
  list(quarters = q$qtr, sea = if (sea_home) q$hq else q$aq, opp = if (sea_home) q$aq else q$hq)
}

scoring_summary <- function(pbp_g_raw) {
  sc <- pbp_g_raw |> arrange(play_id) |>
    filter(nz(sp) == 1, nz(touchdown) == 1 | field_goal_result %in% "made" | nz(safety) == 1 |
             two_point_conv_result %in% "success" | extra_point_result %in% "good") |>
    transmute(play_id, qtr, time, posteam, defteam,
              kind = case_when(nz(touchdown) == 1 ~ "TD", field_goal_result %in% "made" ~ "FG", nz(safety) == 1 ~ "SAF",
                               two_point_conv_result %in% "success" ~ "2PT", TRUE ~ "XP"),
              team = case_when(nz(touchdown) == 1 ~ td_team, nz(safety) == 1 ~ defteam, TRUE ~ posteam),
              desc = trimws(gsub("^\\([0-9:]+\\)\\s*", "", desc)), home = total_home_score, away = total_away_score)
  out <- list()
  for (i in seq_len(nrow(sc))) {
    r <- sc[i, ]
    if (r$kind %in% c("XP", "2PT") && length(out) && out[[length(out)]]$kind == "TD") {
      out[[length(out)]]$pat <- if (r$kind == "XP") "XP good" else "2-pt good"
      out[[length(out)]]$home <- r$home; out[[length(out)]]$away <- r$away
    } else if (r$kind != "XP") {
      out[[length(out) + 1]] <- list(qtr = r$qtr, time = r$time, team = r$team, kind = r$kind, desc = r$desc,
                                     pat = NA, home = r$home, away = r$away)
    }
  }
  out
}

drive_table <- function(pbp_g_raw) {
  pbp_g_raw |> filter(!is.na(fixed_drive), !is.na(posteam)) |> group_by(fixed_drive) |>
    summarise(team = first(posteam), qtr = first(drive_quarter_start), start = first(drive_start_yard_line),
              plays = first(drive_play_count), time = first(drive_time_of_possession), result = first(fixed_drive_result),
              yards = sum(yards_gained[play_type %in% c("run", "pass")], na.rm = TRUE),
              epa = sum(epa[play_type %in% c("run", "pass")], na.rm = TRUE)) |>
    rename(drive = fixed_drive)
}

wp_series <- function(pbp_g_raw, sea_home) {
  pbp_g_raw |> filter(!is.na(vegas_home_wp), !is.na(game_seconds_remaining)) |> arrange(play_id) |>
    transmute(s = game_seconds_remaining, wp = round(if (sea_home) vegas_home_wp else 1 - vegas_home_wp, 3), qtr,
              score = nz(sp) == 1 & (nz(touchdown) == 1 | field_goal_result %in% "made" | nz(safety) == 1),
              team = ifelse(score, ifelse(nz(touchdown) == 1, td_team, ifelse(nz(safety) == 1, defteam, posteam)), NA),
              desc = ifelse(score, trimws(gsub("^\\([0-9:]+\\)\\s*", "", desc)), NA))
}

game_players <- function(ps, pbp_g, game_id) {
  p <- ps |> filter(game_id == !!game_id, team == TEAM)
  rush_succ <- pbp_g |> filter(posteam == TEAM, any_rush, !is.na(rusher_player_id)) |>
    group_by(player_id = rusher_player_id) |> summarise(success = mean(success, na.rm = TRUE))
  list(
    passing = p |> filter(attempts > 0) |> arrange(desc(attempts)) |>
      transmute(player_id, name = player_display_name, headshot = headshot_url, comp = completions, att = attempts,
                yds = passing_yards, td = passing_tds, int = passing_interceptions, sacks = sacks_suffered, epa = passing_epa,
                cpoe = passing_cpoe, rating = passer_rating(completions, attempts, passing_yards, passing_tds, passing_interceptions)),
    rushing = p |> filter(carries > 0) |> arrange(desc(rushing_yards)) |> left_join(rush_succ, by = "player_id") |>
      transmute(player_id, name = player_display_name, position, att = carries, yds = rushing_yards, ypc = rushing_yards / carries,
                td = rushing_tds, epa = rushing_epa, success),
    receiving = p |> filter(targets > 0) |> arrange(desc(receiving_yards)) |>
      transmute(player_id, name = player_display_name, position, targets, rec = receptions, yds = receiving_yards, td = receiving_tds, epa = receiving_epa),
    defense = p |> mutate(tk = def_tackles_solo + def_tackles_with_assist + def_tackle_assists,
                          any = tk + def_tackles_for_loss + def_sacks + def_qb_hits + def_interceptions + def_pass_defended + def_fumbles_forced) |>
      filter(any > 0) |> arrange(desc(tk), desc(def_sacks)) |>
      transmute(player_id, name = player_display_name, position, tackles = tk, solo = def_tackles_solo, tfl = def_tackles_for_loss,
                sacks = def_sacks, qb_hits = def_qb_hits, int = def_interceptions, pd = def_pass_defended, ff = def_fumbles_forced)
  )
}

build_game <- function(g, pbp_raw, pbp_f, ps, teams, situ, starters, params) {
  h <- game_header(g, teams)
  out <- list(header = h)
  qb <- starters$game_qb(g$game_id, h$opponent)
  out$qb <- qb
  if (h$played) {
    raw <- pbp_raw |> filter(game_id == g$game_id)
    gf  <- pbp_f |> filter(game_id == g$game_id)
    out$box <- list(sea = box_team(gf, raw, TEAM, h$sea_score), opp = box_team(gf, raw, h$opponent, h$opp_score),
                    by_quarter = by_quarter(raw, h$home))
    out$scoring <- scoring_summary(raw)
    out$drives <- drive_table(raw)
    out$wp <- wp_series(raw, h$home)
    out$players <- game_players(ps, gf, g$game_id)
    out$situational <- situ_game_json(gf, situ, TEAM, params)
  }
  out
}

games_index <- function(sched_season, teams) {
  s <- sched_season |> filter(game_type == "REG", home_team == TEAM | away_team == TEAM) |> arrange(week)
  rows <- map(seq_len(nrow(s)), function(i) {
    h <- game_header(s[i, ], teams)
    list(game_id = h$game_id, week = h$week, opponent = h$opponent, opponent_name = h$opponent_identity$name,
         opponent_logo = h$opponent_identity$logo, home = h$home, gameday = h$gameday, gametime = h$gametime,
         played = h$played, result = h$result, sea_score = h$sea_score, opp_score = h$opp_score, bye = FALSE)
  })
  weeks <- s$week
  byes <- setdiff(seq_len(max(sched_season$week[sched_season$game_type == "REG"])), weeks)
  for (b in byes) rows[[length(rows) + 1]] <- list(week = b, bye = TRUE, played = FALSE)
  rows[order(map_dbl(rows, "week"))]
}
