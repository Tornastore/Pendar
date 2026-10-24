"""Regression contracts for stronger Expert and Grandmaster AI profiles."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_chess_uses_legal_move_search_quiescence_transposition_and_time_budgets():
    ai = read("games/chess/ai.gd")
    rules = read("games/chess/rules.gd")
    assert "func _quiescence(" in ai
    assert "var _transposition: Dictionary = {}" in ai
    assert "func _tt_key(game) -> String:" in ai
    assert "var depth_by_level: Array[int] = [0, 0, 1, 2, 3, 4, 5]" in ai
    assert "var node_limit_by_level: Array[int] = [0, 0, 1800, 3600, 7200, 14000, 24000]" in ai
    assert "func _budget_reached() -> bool:" in ai
    assert '_transposition[position_key] = {"depth": depth, "score": best_score' in ai
    assert "func _chess_move_keeps_king_safe(" in rules
    assert "func _chess_castle_transit_safe(" in rules
    assert "func _chess_undo() -> void:" in rules


def test_othello_has_transposition_table_exact_small_endgame_and_pass_depth_fix():
    ai = read("games/othello/ai.gd")
    assert "var _transposition: Dictionary = {}" in ai
    assert "func _board_key(board: Array, turn: int) -> String:" in ai
    assert "depth = _empty_count(board)" in ai
    assert "var pass_depth: int = depth if _exact_endgame else depth - 1" in ai
    assert "_stable_edge_count(board, perspective)" in ai
    assert "_potential_mobility_diff(board, perspective)" in ai


def test_backgammon_prefers_maximum_legal_dice_usage_before_position_score():
    ai = read("games/backgammon/ai.gd")
    assert 'var used: int = int(candidate.get("used", 0))' in ai
    assert "if used > best_used or (used == best_used and score > best_score):" in ai
    assert "var branch_limits: Array[int] = [0, 4, 5, 6, 7, 8, 10]" in ai
    assert "if int(game.bg_off[1]) >= 15:" in ai
    assert "for point in range(23, -1, -1):" in ai


def test_strong_profiles_have_tactical_lookahead_across_the_game_catalog():
    source_by_game = {
        "games/quoridor/ai.gd": ("_minimax(", "_move_repetition_penalty("),
        "games/gobblet/rules.gd": ("_gob_rank_actions(replies", "worst_continuation"),
        "games/abalone/rules.gd": ("_aba_rank_actions(replies", "worst_line"),
        "games/blockace/rules.gd": ("opponent_best", "our_future_moves"),
        "games/domino/rules.gd": ("_dom_second_ply_value(", "_dom_unknown_matches("),
        "games/hokm/rules.gd": ("_hokm_sample_opponent_hands(", "_hokm_lead_beaten_probability("),
        "games/pasoor/rules.gd": ("_pas_future_table_risk(", "_pas_table_capture_risk("),
        "games/pentago/rules.gd": ("lookahead_count", "_pent_opponent_has_winning_turn("),
    }
    for path, required in source_by_game.items():
        src = read(path)
        for marker in required:
            assert marker in src, f"Missing advanced AI contract {marker!r} in {path}"


def test_grandmaster_profiles_reduce_randomness_or_search_noise():
    checks = {
        "games/chess/ai.gd": "var time_limit_usec_by_level: Array[int] = [0, 0, 180000, 300000, 450000, 650000, 900000]",
        "games/othello/ai.gd": "_transposition[key] =",
        "games/gobblet/rules.gd": "var noise_by_level: Array[float] = [0.0, 19.0, 10.0, 4.0, 0.35, 0.0]",
        "games/abalone/rules.gd": "var noise_by_level: Array[float] = [0.0, 18.0, 8.0, 3.5, 0.6, 0.0]",
        "games/blockace/rules.gd": "var noise_by_level: Array[float] = [0.0, 12.0, 7.0, 3.0, 0.35, 0.0]",
        "games/hokm/rules.gd": "var noise: float = [0.0, 7.0, 4.5, 2.5, 0.7, 0.0][level - 1]",
        "games/pasoor/rules.gd": "var noise: float = [0.0, 16.0, 9.0, 5.0, 0.45, 0.0][level - 1]",
    }
    for path, marker in checks.items():
        assert marker in read(path), f"Expected deterministic/low-noise top-tier profile in {path}"


def test_hokm_sampling_comment_is_valid_gdscript_not_a_bare_prose_line():
    lines = read("games/hokm/rules.gd").splitlines()
    for index, line in enumerate(lines):
        if line.strip() == "opponent hand. Played cards and our current hand are removed from the pool.":
            raise AssertionError(f"Uncommented prose in GDScript at line {index + 1}")


def test_gobblet_exposed_opponent_win_takes_precedence_in_grandmaster_root_search():
    ai = read("games/gobblet/rules.gd")
    root = ai.index("func _gob_cpu()")
    opponent_win = ai.index("if _gob_check_win(1):", root)
    cpu_win = ai.index("elif _gob_check_win(2):", root)
    assert opponent_win < cpu_win
    assert "_gob_finish(3 - player)" in ai


def test_backgammon_stops_search_after_terminal_bear_off():
    ai = read("games/backgammon/ai.gd")
    fn = ai.index("func _search_plan(")
    terminal = ai.index("if int(game.bg_off[1]) >= 15 or int(game.bg_off[0]) >= 15:", fn)
    finish = ai.index("if index >= dice.size():", fn)
    assert terminal < finish

def test_quoridor_expert_and_grandmaster_search_is_hard_bounded_for_web():
    ai = read("games/quoridor/ai.gd")
    assert "EXPERT_SEARCH_BUDGET_USEC: int = 80000" in ai
    assert "GRANDMASTER_SEARCH_BUDGET_USEC: int = 135000" in ai
    assert "EXPERT_NODE_BUDGET: int = 48" in ai
    assert "GRANDMASTER_NODE_BUDGET: int = 88" in ai
    assert "func _should_abort_search() -> bool:" in ai
    assert "if alpha >= beta or _search_aborted:" in ai
    assert "_route_wall_candidates(game, 1 - player, _active_wall_route_segments)" in ai


def test_quoridor_minimax_no_longer_scans_all_128_walls_at_every_node():
    ai = read("games/quoridor/ai.gd")
    actions = ai[ai.index("func _search_actions("):ai.index("func _route_wall_candidates(")]
    assert "_route_wall_candidates(" in actions
    assert "for y in range(8)" not in actions
    assert "_wall_evaluations_remaining <= 0" in actions
    assert "Always include legal pawn moves first" in actions


def test_backgammon_six_levels_are_wired_to_cpu_turn_and_catalog_is_not_beta():
    root = Path(__file__).resolve().parents[1]
    ai = read("games/backgammon/ai.gd")
    rules = read("games/backgammon/rules.gd")
    presentation = read("games/backgammon/presentation.gd")
    main = read("main.gd")
    mode_screen = read("ui/screens/mode_screen.gd")
    catalog = read("core/game_catalog.gd")
    assert "ai.choose_turn(self, bg_difficulty)" in rules
    assert "if bg_moves_left.is_empty():" in rules
    assert '"backgammon":' in main
    assert "_schedule_cpu(0.45, _bg_cpu)" in main
    assert "host._set_backgammon_difficulty.bind(i + 1)" in mode_screen
    assert '"id": "backgammon"' in catalog and '"beta": false' in catalog[catalog.index('"id": "backgammon"'):catalog.index('"id": "backgammon"') + 260]
    assert "var branch_limits: Array[int] = [0, 4, 5, 6, 7, 8, 10]" in ai
    assert "if level == 1:" in ai and "if level == 2:" in ai
    assert "if level >= 5:" in ai and "if level >= 6:" in ai
    assert "while opening_dice[0] == opening_dice[1]:" in rules
    assert "bg_turn = 0 if opening_dice[0] > opening_dice[1] else 1" in rules
    assert 'opponent_name: String = "CPU" if app.vs_cpu else "حریف"' in presentation


def test_backgammon_cpu_uses_only_rule_authorized_moves_and_respects_difficulty():
    rules = read("games/backgammon/rules.gd")
    presentation = read("games/backgammon/presentation.gd")
    ai = read("games/backgammon/ai.gd")
    main = read("main.gd")
    assert "var legal_turn_moves: Array[Dictionary] = _bg_turn_legal_moves(1)" in rules
    assert "ai.choose_legal_first_move(self, legal_turn_moves, bg_difficulty)" in rules
    assert "ai.choose_turn(self, bg_difficulty)" in rules
    assert "func choose_legal_first_move(game, legal_moves: Array[Dictionary], difficulty: int)" in ai
    assert "var branch_limits: Array[int] = [0, 4, 5, 6, 7, 8, 10]" in ai
    assert "levels[clampi(game.bg_difficulty, 1, 6) - 1]" in presentation
    assert "_schedule_cpu(0.45, _bg_cpu)" in main
