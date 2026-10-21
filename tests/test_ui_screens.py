from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_dashboard_and_rankings_are_delegated_to_screen_modules():
    main = (ROOT / "main.gd").read_text(encoding="utf-8")
    dashboard = (ROOT / "ui" / "screens" / "dashboard_screen.gd").read_text(encoding="utf-8")
    rankings = (ROOT / "ui" / "screens" / "rankings_screen.gd").read_text(encoding="utf-8")

    assert 'preload("res://ui/screens/dashboard_screen.gd")' in main
    assert 'preload("res://ui/screens/rankings_screen.gd")' in main
    assert "_dashboard_screen.build_buttons(self, _ui_screen_theme)" in main
    assert "_dashboard_screen.render(self, _ui_screen_theme)" in main
    assert "_rankings_screen.build_buttons(self, _ui_screen_theme)" in main
    assert "_rankings_screen.render(self, _ui_screen_theme)" in main
    assert "func stat_points(host, game_id: String) -> int:" in dashboard
    assert "آمار و امتیازات" in dashboard
    assert "func render(host, theme: Dictionary) -> void:" in rankings
    assert "RankingServiceScript.build_game_rows" in rankings
    assert "رتبه‌بندی" in rankings


def test_screen_presenters_do_not_own_game_or_scoring_state():
    dashboard = (ROOT / "ui" / "screens" / "dashboard_screen.gd").read_text(encoding="utf-8")
    rankings = (ROOT / "ui" / "screens" / "rankings_screen.gd").read_text(encoding="utf-8")

    # Presenters read state from the host/service and update only layout/button setup on the host.
    assert "host.scoring_service" in dashboard
    assert "host.scoring_service" in rankings
    assert "host.state =" not in dashboard + rankings
    assert "host.selected_game =" not in dashboard + rankings
