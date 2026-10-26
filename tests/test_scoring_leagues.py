from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(*parts):
    return (ROOT.joinpath(*parts)).read_text(encoding="utf-8")


def test_scoring_service_separates_monthly_points_from_skill_mmr():
    scoring = read("services", "scoring_service.gd")
    ranking = read("services", "ranking_service.gd")
    main = read("main.gd")
    assert "const WIN_PTS := 30" in scoring
    assert "const DRAW_PTS := 6" in scoring
    assert "const LOSS_PTS := -18" in scoring
    assert 'const SCORE_PATH := "user://pendar_scores.cfg"' in scoring
    assert 'const LEGACY_SCORE_PATH := "user://mind_bastion_scores.cfg"' in scoring
    assert "const SCHEMA_VERSION := 3" in scoring
    assert '"season_points": 0' in scoring
    assert '"rating": INITIAL_RATING' in scoring
    assert "func _rollover_season(" in scoring
    assert "if ranked_human:" in scoring
    assert 'stats["rating"] = clampi' in scoring
    assert "func season_tier_info(points: int)" in ranking
    assert "scoring_service.record_result" in main


def test_two_ladders_are_applied_independently_with_floor_ceiling_and_gate():
    scoring = read("services", "scoring_service.gd")
    league = read("services", "league_service.gd")
    assert "ladder_apply(global_season_points" in scoring
    assert 'ladder_apply(int(stats["season_points"])' in scoring
    assert "PRACTICE_CEILING_GLOBAL" in scoring and "PRACTICE_CEILING_GAME" in scoring
    assert "gate_cap_points" in scoring
    assert "scaled_start(LeagueScript.league_index_for_points" in scoring  # league floor
    assert "GAME_LADDER_SCALE := 0.5" in league
    assert "SEASON_CARRY := 0.35" in league
    assert '"id": "legend"' in league and '"id": "bronze"' in league


def test_cpu_rewards_scale_by_difficulty_and_do_not_change_competitive_mmr():
    scoring = read("services", "scoring_service.gd")
    assert "CPU_DIFFICULTY_MULTIPLIERS: Array[float] = [0.10, 0.18, 0.30, 0.45, 0.62, 0.80]" in scoring
    assert "HUMAN_LAN_MULTIPLIER := 0.45" in scoring
    assert "if ranked_human:" in scoring
    assert "global_rating = clampi(global_rating_before + global_rating_delta" in scoring
    assert "rating_schema_version" in scoring
    assert 'lp = maxi(1, lp)' in scoring  # wins/draws always give at least one point
    assert '"human_lan"' in scoring


def test_scoring_design_documents_honest_online_leaderboard_limitations():
    doc = read("docs", "SCORING_AND_LEAGUES_FA.md")
    assert "MMR" in doc
    assert "امتیاز لیگ" in doc
    assert "جهانی و مشترک میان تمام کاربران نیست" in doc
    assert "ضدتقلب" in doc


def test_match_duration_modifies_league_points_but_not_mmr():
    scoring = read("services", "scoring_service.gd")
    assert '"uno": {"weight": 0.85' in scoring
    assert "static func duration_multiplier(duration_seconds: float" in scoring
    assert "clampf(duration_seconds, 0.0, LONG_MATCH_SECONDS)" in scoring
    assert "SHORT_MATCH_SECONDS" in scoring
    assert "duration_seconds: float = 0.0" in scoring
    # Elo/MMR is computed separately; elapsed time only modifies league point awards.
    assert "game_rating_delta := 0" in scoring
    assert 'if outcome != "loss":' in scoring


def test_anti_quit_and_online_integrity_hooks_are_wired():
    main = read("main.gd")
    scoring = read("services", "scoring_service.gd")
    assert "func _settle_unfinished_online_match(" in main
    assert "begin_pending_match" in main and "settle_pending_match" in main
    assert '_settle_unfinished_online_match("win", {"forfeit": true})' in main
    assert '"rating": scoring_service.match_rating(online_game)' in main
    assert "func begin_pending_match(" in scoring
    server = read("online-server", "server.js")
    assert "findBestPair" in server and "pickGroup" in server
    assert "opponent_rating" in server


def test_quests_badges_and_season_calendar_exist():
    quest = read("services", "quest_service.gd")
    league = read("services", "league_service.gd")
    assert "DAILY_POOL" in quest and "WEEKLY_POOL" in quest and "BADGES" in quest
    assert "func jalali_from_unix" in league
    assert "TEHRAN_UTC_OFFSET_SECONDS := 12600" in league


def test_offline_games_are_never_scored_as_network_games():
    main = read("main.gd")
    # Godot 4 always has an OfflineMultiplayerPeer, so "peer != null" alone would score every offline game.
    assert "peer is OfflineMultiplayerPeer" in main
    assert 'return "local_friendly"' in main
    assert "mm_local_two_player" in main and "quo_local_multiplayer" in main


def test_practice_never_costs_points_at_the_ceiling_and_hints_matchmaking():
    scoring = read("services", "scoring_service.gd")
    assert "practice and cur >= practice_ceiling" in scoring
    assert "func practice_hint(" in scoring
    assert "PRACTICE_RATING_HINT" in scoring
    assert "STREAK_MIN_CPU_LEVEL := 3" in scoring
    assert "func refresh_clock()" in scoring
    main = read("main.gd")
    assert "scoring_service.refresh_clock()" in main
