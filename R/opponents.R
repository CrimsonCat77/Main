# Section 8: opponent profile, one JSON per opponent team (shared by both games vs. a division rival).

# Best win / worst loss by the other team's *current* win percentage (spec 8b).
best_worst <- function(team, long_played) {
  mine <- long_played |> filter(team == !!team)
  rec_now <- function(t) record_of(long_played |> filter(team == t))
  rec_then <- function(t, wk) record_of(long_played |> filter(team == t, week < wk))
  pick <- function(rows, best) {
    if (!nrow(rows)) return(NULL)
    cand <- rows |> rowwise() |> mutate(r = list(rec_now(opp)), pct = r$pct, gp = r$games, rec = r$text,
                                        then = rec_then(opp, week)$text) |> ungroup()
    cand <- if (best) cand |> arrange(desc(pct), desc(gp), opp) else cand |> arrange(pct, desc(gp), opp)
    x <- cand[1, ]
    list(team = x$opp, record = x$rec, record_then = x$then, pct = x$pct, week = x$week, game_id = x$game_id,
         score = sprintf("%d-%d", x$pts, x$pts_allowed), home = x$home)
  }
  list(best_win = pick(mine |> filter(result == "W"), TRUE), worst_loss = pick(mine |> filter(result == "L"), FALSE))
}

division_standing <- function(team, teams, long_played) {
  div <- teams$team_division[teams$team_abbr == team]
  members <- teams$team_abbr[teams$team_division == div]
  tbl <- map_dfr(members, function(m) {
    mine <- long_played |> filter(team == m)
    r <- record_of(mine)
    tibble(team = m, w = r$w, l = r$l, ties = r$t, pct = r$pct %||% 0, record = r$text,
           diff = sum(mine$pts) - sum(mine$pts_allowed))
  }) |> arrange(desc(pct), desc(diff)) |> mutate(place = row_number())
  list(division = div, place = tbl$place[tbl$team == team], table = tbl)
}

opponent_json <- function(opp_team, sea_week, ctx) {
  opp <- opp_team  # note: schedule_long() frames carry a column named `opp`, so filters use !!opp
  long_all <- ctx$long_all |> filter(team == !!opp)
  long_played <- ctx$long_played
  mine <- long_played |> filter(team == !!opp)
  latest <- long_all |> filter(!is.na(coach)) |> arrange(desc(!is.na(result)), desc(week)) |> slice(1)
  sea_stats <- ctx$ta$long |> filter(team == TEAM)
  opp_stats <- ctx$ta$long |> filter(team == !!opp)
  prior <- ctx$ta_prior$long |> filter(team == !!opp)
  averages <- pmap(STAT_DEFS, function(key, label, group, hib, fmt, n_kind) {
    o <- opp_stats |> filter(key == !!key); s <- sea_stats |> filter(key == !!key); p <- prior |> filter(key == !!key)
    list(key = key, label = label, group = group, fmt = fmt, higher_is_better = hib,
         opp = list(value = o$value %||% NA, rank = o$rank %||% NA, n = o$n %||% NA),
         sea = list(value = s$value %||% NA, rank = s$rank %||% NA),
         prior = list(value = p$value %||% NA, rank = p$rank %||% NA),
         league_avg = o$league_avg %||% NA)
  })
  list(
    team = opp, identity = team_identity(ctx$teams, opp), coach = latest$coach %||% NA,
    record_entering = record_of(mine |> filter(week < sea_week)), record_current = record_of(mine),
    standing = division_standing(opp, ctx$teams, long_played),
    results = long_all |> transmute(week, game_id, opponent = .data$opp, home, pts, pts_allowed, result,
                                    played = !is.na(result), is_sea = .data$opp == TEAM, gameday),
    best_worst = best_worst(opp, long_played),
    averages = averages,
    prior_season = ctx$season - 1,
    situational = list(off = situational_json(ctx$situ, "off", opp, PARAMS), def = situational_json(ctx$situ, "def", opp, PARAMS))
  )
}
