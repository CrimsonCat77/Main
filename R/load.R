# Data loading with an on-disk cache under cache/.
#  - Current-season files are always re-downloaded (they change weekly).
#  - Historical seasons never change, so they are cached forever (spec section 10).
CACHE_DIR <- "cache"
dir.create(CACHE_DIR, showWarnings = FALSE, recursive = TRUE)

cached <- function(name, loader, fresh = FALSE) {
  path <- file.path(CACHE_DIR, paste0(name, ".rds"))
  if (!fresh && file.exists(path)) return(readRDS(path))
  message("  loading ", name)
  x <- loader()
  saveRDS(x, path)
  x
}

load_all <- function(season) {
  list(
    pbp        = cached(paste0("pbp_", season),          function() load_pbp(season), fresh = TRUE),
    pbp_prior  = cached(paste0("pbp_", season - 1),      function() load_pbp(season - 1)),
    sched_all  = cached("schedules",                     function() load_schedules(seasons = TRUE), fresh = TRUE),
    rosters    = cached(paste0("rosters_", season),      function() load_rosters(season), fresh = TRUE),
    players    = cached("players",                       function() load_players(), fresh = TRUE),
    team_stats = cached(paste0("team_stats_", season),   function() load_team_stats(season), fresh = TRUE),
    teams      = cached("teams",                         function() load_teams(), fresh = TRUE)
  )
}

# Weekly player stats for one season (historical seasons cached forever on disk; every season is
# memoised in memory for the rest of the run so the current season downloads once per build).
.ps_memo <- new.env()
player_stats_season <- function(s, current_season) {
  key <- as.character(s)
  if (!is.null(.ps_memo[[key]])) return(.ps_memo[[key]])
  x <- cached(paste0("player_stats_", s), function() load_player_stats(s), fresh = (s >= current_season))
  .ps_memo[[key]] <- x
  x
}
