"""Regression contracts for stronger Expert and Grandmaster AI profiles."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_chess_uses_quiescence_transposition_table_and_balanced_root_budget():
    ai = read("games/chess/ai.gd")
    assert "func _quiescence(" in ai
    assert "var _transposition: Dictionary = {}" in ai
    assert "func _position_key(game, turn: int) -> String:" in ai
    assert "var root_limits: Array[int] = [0, 0, 0, 24, 28, 32]" in ai
    assert "per_root_budget: int = maxi(120" in ai
    assert "_transposition[key] = {\"depth\": depth, \"score\": best_value" in ai


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
    assert "var branch_limits: Array[int] = [0, 0, 0, 5, 8, 12, 15]" in ai
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
        "games/chess/ai.gd": "if _difficulty < 5:",
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
