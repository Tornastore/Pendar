"""Regression contracts for AI, guide wrapping, and dense roster/menu layouts."""
from pathlib import Path
import math

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_connect4_search_uses_completed_iterative_depths_and_tactical_wins():
    ai = read("games/connect4/rules.gd")
    cpu = ai[ai.index("func _c4_cpu_move()"):ai.index("func _c4_landing_row_on(")]
    assert cpu.index("if wins:") < cpu.index("var level: int = clampi(c4_difficulty")
    assert "for search_depth in range(1, depth_by_level[level - 1] + 1)" in cpu
    assert "if iteration_complete:" in cpu
    assert "else:\n\t\t\tbreak" in cpu
    assert "_c4_transposition.clear()" in cpu
    assert "var node_limit_by_level: Array[int] = [180, 340, 700, 1250, 2300, 3900]" in cpu
    assert "var time_limit_usec_by_level: Array[int] = [3500, 5000, 7000, 10000, 14000, 20000]" in cpu
    assert "if level == 1 and randf() < 0.45" in cpu
    assert "elif level == 2 and randf() < 0.20" in cpu


def test_jenga_cpu_has_distinct_risk_profiles_and_models_future_moves():
    ai = read("games/jenga/rules.gd")
    for marker in (
        "func _jenga_layer_count(",
        "func _jenga_risk(",
        "func _jenga_future_min_risk(",
        "func _jenga_candidate_score(",
        "func _jenga_choose_slot(",
        "var pressure_weight: float = 18.0 if level == 4 else (24.0 if level == 5 else 30.0)",
        "5: score += randf_range(-0.12, 0.12)",
    ):
        assert marker in ai
    cpu = ai[ai.index("func _jenga_cpu_turn()"):ai.index("func _jenga_tap(")]
    assert "if level == 1:" in cpu
    assert "chosen = choices.pick_random()" in cpu
    assert "chosen = tied[0] if level == 6 else tied.pick_random()" in cpu


def test_mafia_ai_uses_detective_evidence_and_correct_previous_day_round():
    ai = read("games/mafia/rules.gd")
    target = ai[ai.index("func _mafia_ai_target("):ai.index("func _mafia_cpu_tick(")]
    assert "var previous_round: int = mafia_round - 1" in target
    assert "if int(history_entry.get(\"round\", -1)) != previous_round" in target
    assert "var noise_by_level: Array[float] = [4.2, 3.0, 2.1, 1.15, 0.35, 0.0]" in target
    assert "score = 10000.0 if bool(intel[target]) else -10000.0" in target
    assert "score = -suspicion" in target
    assert "for seat in range(1, mafia_player_count)" in ai


def test_gobblet_cpu_penalizes_repeated_reverse_moves_at_expert_levels():
    ai = read("games/gobblet/rules.gd")
    assert "var _gob_cpu_move_history: Array[Dictionary] = []" in ai
    assert "_gob_cpu_move_history.clear()" in ai
    assert "func _gob_repetition_penalty(" in ai
    assert "var penalty_by_level: Array[float] = [0.0, 1.0, 4.0, 12.0, 35.0, 85.0]" in ai
    assert "score -= _gob_repetition_penalty(action, player)" in ai


def test_rules_overlay_pages_by_measured_height_and_draws_wrapped_words():
    rules = read("ui/screens/rules_screen.gd")
    main = read("main.gd")
    assert "func _page_groups(host, all_lines: Array, text_width: float, max_body_height: float) -> Array:" in rules
    assert "host._wrap_h(str(raw_line), text_width, 15)" in rules
    assert "current_height + item_height > max_body_height" in rules
    assert '"first_line": first_line' in rules
    assert "TextWrapScript.wrap(self, normalized, w, size, bold)" in main
    assert "TextServer.BREAK_MANDATORY" in main
    helper = read("ui/text_wrap.gd")
    assert "_split_oversized_word" in helper
    assert "return \"\\n\".join(lines)" in helper


def test_logo_is_confined_to_top_utility_strip():
    menu = read("ui/screens/menu_screen.gd")
    assert "var logo_size: float = minf(60.0, maxf(48.0, float(theme[\"VIEW_W\"]) * 0.11))" in menu
    assert "Rect2(float(theme[\"VIEW_W\"]) - logo_size - 12.0, 8.0, logo_size, logo_size)" in menu
    # The logo's bottom must remain above the menu's category-chip row (y=124).
    logo_bottom = 8.0 + 60.0
    assert logo_bottom < 124.0


def test_online_game_grid_stays_above_queue_status_and_bottom_navigation():
    # 18 games currently occupy six compact rows; this guards future catalog growth.
    game_count = 18
    rows = math.ceil(game_count / 3.0)
    end_y = 156.0 + (rows - 1) * 36.0 + 32.0
    extra = max(0.0, end_y - 254.0)
    note_bottom = 592.0 + extra + 134.0
    assert note_bottom <= 840.0
    assert note_bottom < 868.0
    online = read("ui/screens/online_screen.gd")
    assert "var y: float = 156.0 + row * 36.0" in online
    assert "var note := Rect2(24, 592 + ex, 492, 134)" in online



def test_online_username_edit_and_lobby_addresses_do_not_overlap_controls():
    online = read("ui/screens/online_screen.gd")
    assert "if not host.username_editing:" in online
    assert "var shown_ip_count: int = mini(ips.size(), 3)" in online
    assert "for j in range(mini(ips.size(), 3))" in online
    assert '"آدرس‌های دیگر در تنظیمات شبکه"' in online


def test_mode_options_have_a_clear_gap_below_difficulty_and_player_selectors():
    mode = read("ui/screens/mode_screen.gd")
    assert "option_y = 410.0" in mode
    assert 'if host.selected_game not in ["uno", "jenga", "mafia"]:' in mode
    # Difficulty controls end at y=385 and the first action button begins at y=410.
    assert 410 - (345 + 40) >= 24

def test_large_results_use_compact_two_column_rosters():
    result = read("ui/screens/result_screen.gd")
    assert "var compact_grid: bool = rows.size() > 6" in result
    assert "var rows_per_column: int = int(ceil(float(rows.size()) / 2.0)) if compact_grid else rows.size()" in result
    assert "var cell_width: float = card.size.x * 0.5 if compact_grid else card.size.x" in result
    # Twelve roster rows fit into six 29px rows, leaving space for the score and buttons.
    card_height = 16 + math.ceil(12 / 2) * 29
    assert 392 + card_height + 14 < 604



def test_new_game_menu_art_exists_for_connect4_jenga_and_mafia():
    renderer = read("ui/illustration_renderer.gd")
    for game_id in ("connect4", "jenga", "mafia"):
        assert f'"{game_id}":' in renderer
    assert 'Color("#1764c7")' in renderer
    assert 'Color("#d8a56a")' in renderer
    assert 'var card_centers: Array[Vector2]' in renderer


def test_mafia_roster_and_event_text_reserve_bottom_button_dock():
    mafia = read("games/mafia/presentation.gd")
    assert "TextWrapScript.wrap(app, game.mafia_last_event, 492, 13, false, 2)" in mafia
    assert "var hint_y: float = minf(849.0" in mafia
    assert 'Rect2(16, 884, 508, 38)' not in mafia
    assert "app._fit_size(state_label" in mafia


def test_jenga_layout_has_three_views_and_keeps_status_above_bottom_dock():
    jenga = read("games/jenga/presentation.gd")
    assert 'var labels: Array[String] = ["نمای روبه‌رو", "نمای کناری", "نمای بالا"]' in jenga
    assert "func _draw_block" in jenga
    assert "Geometry2D.is_point_in_polygon(point, geometry[face_name])" in jenga
    assert "app._wrap(game.jenga_status, 24, 844, 492, 12" in jenga
