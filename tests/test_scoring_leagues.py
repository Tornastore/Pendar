from pathlib import Path


def test_scoring_service_separates_monthly_points_from_skill_mmr():
    root = Path(__file__).resolve().parents[1]
    scoring = (root / "services" / "scoring_service.gd").read_text(encoding="utf-8")
    ranking = (root / "services" / "ranking_service.gd").read_text(encoding="utf-8")
    main = (root / "main.gd").read_text(encoding="utf-8")
    assert 'const WIN_PTS := 24' in scoring
    assert 'const DRAW_PTS := 4' in scoring
    assert 'const LOSS_PTS := -12' in scoring
    assert '"season_points": 0' in scoring
    assert '"rating": INITIAL_RATING' in scoring
    assert 'func _roll_season_if_needed()' in scoring
    assert 'if ranked_human:' in scoring
    assert 'stats["rating"] = clampi' in scoring
    assert 'func season_tier_info(points: int)' in ranking
    assert 'scoring_service.record_result' in main


def test_cpu_rewards_scale_by_difficulty_and_do_not_change_competitive_mmr():
    root = Path(__file__).resolve().parents[1]
    scoring = (root / "services" / "scoring_service.gd").read_text(encoding="utf-8")
    assert 'CPU_DIFFICULTY_MULTIPLIERS: Array[float] = [0.15, 0.25, 0.38, 0.52, 0.68, 0.82]' in scoring
    assert 'elif against_cpu:' in scoring
    assert 'if ranked_human:' in scoring
    assert 'global_rating = clampi(global_rating + global_rating_delta' in scoring
    assert 'rating_schema_version' in scoring
    assert 'else INITIAL_RATING' in scoring
    assert 'if outcome == "draw":' in scoring
    assert 'raw_delta = maxi(1, raw_delta)' in scoring


def test_scoring_design_documents_honest_online_leaderboard_limitations():
    root = Path(__file__).resolve().parents[1]
    doc = (root / "docs" / "SCORING_AND_LEAGUES_FA.md").read_text(encoding="utf-8")
    assert "MMR" in doc
    assert "امتیاز لیگ" in doc
    assert "جهانی و مشترک میان تمام کاربران نیست" in doc
    assert "ضدتقلب" in doc
