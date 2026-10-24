from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_backgammon_rules_delegate_rendering_and_hit_testing_to_presentation():
    rules = read("games/backgammon/rules.gd")
    presentation = read("games/backgammon/presentation.gd")
    assert 'preload("res://games/backgammon/presentation.gd")' in rules
    assert "return _presentation.point_from_tap(p)" in rules
    assert "_presentation.render(app, self)" in rules
    assert "func point_from_tap(p: Vector2) -> int:" in presentation
    assert "func render(app, game) -> void:" in presentation
    assert "func _bg_legal_moves_for_die" in rules
    assert "func _bg_turn_legal_moves" in rules
    assert "func _bg_commit_human_move" in rules
    assert "func _bg_apply_net_move" in rules
    assert "func _bg_point_from_tap(p: Vector2) -> int:\n\t# Keep the old entry point" in rules
    assert "app.draw_colored_polygon" not in rules


def test_backgammon_hit_testing_tracks_visible_top_bottom_rows_and_bar():
    presentation = read("games/backgammon/presentation.gd")
    assert "TOP_POINTS_MIN_Y: float = 178.0" in presentation
    assert "TOP_POINTS_MAX_Y: float = 332.0" in presentation
    assert "BOTTOM_POINTS_MIN_Y: float = 508.0" in presentation
    assert "BOTTOM_POINTS_MAX_Y: float = 662.0" in presentation
    assert "return candidate if top_row else 23 - candidate" in presentation
    assert "return -1" in presentation and "return -2" in presentation


def test_backgammon_ai_accounts_for_bar_priority_and_entry_blocking_points():
    ai = read("games/backgammon/ai.gd")
    assert "if int(game.bg_bar[1]) > 0:" in ai[ai.index("func _cpu_can_hit"):ai.index("func _human_can_hit")]
    assert "if int(game.bg_bar[0]) > 0:" in ai[ai.index("func _human_can_hit"):ai.index("func _prime_score")]
    assert "func _home_board_block_score(game) -> float:" in ai
    assert "score += _home_board_block_score(game)" in ai


def test_backgammon_godot_regression_suite_is_wired_into_both_web_workflows():
    test_script = ROOT / "tests/godot/test_backgammon_rules.gd"
    assert test_script.is_file()
    test = test_script.read_text(encoding="utf-8")
    for marker in (
        "_test_bar_entry_and_blocked_points()",
        "_test_hits_and_bearing_off()",
        "_test_mandatory_dice_and_doubles()",
        "_test_input_hit_testing()",
        "_test_ai_legality_and_state_safety()",
    ):
        assert marker in test
    for workflow_name in ("build-web.yml", "deploy-web.yml"):
        workflow = (ROOT / ".github" / "workflows" / workflow_name).read_text(encoding="utf-8")
        assert "Run backgammon rules and presentation regression tests" in workflow
        assert "BACKGAMMON_RULES_TESTS: checks=" in workflow
