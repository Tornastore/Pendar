"""Smoke test for modular source layout (requires Python, not Godot)."""
import subprocess
import sys
from pathlib import Path


def test_modular_structure_check_passes() -> None:
    project_root = Path(__file__).resolve().parents[1]
    result = subprocess.run(
        [sys.executable, str(project_root / "tools" / "verify_structure.py")],
        cwd=project_root,
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "STRUCTURE CHECK PASSED" in result.stdout


def test_quoridor_ai_has_six_difficulty_profiles_and_master_search() -> None:
    project_root = Path(__file__).resolve().parents[1]
    ai = (project_root / "games" / "quoridor" / "ai.gd").read_text(encoding="utf-8")
    rules = (project_root / "games" / "quoridor" / "rules.gd").read_text(encoding="utf-8")
    main = (project_root / "main.gd").read_text(encoding="utf-8")
    assert "func choose_action(game, difficulty: int)" in ai
    assert "if level == 1" in ai
    assert "if level == 2" in ai
    assert "if level == 6:" in ai
    assert "func _minimax(" in ai
    assert "func _search_actions(" in ai
    assert "MASTER_SEARCH_DEPTH: int = 4" in ai
    for level in ("\t\t3:", "\t\t4:", "\t\t5:"):
        assert level in ai
    assert "QuoridorAIScript = preload(\"res://games/quoridor/ai.gd\")" in rules
    assert "_set_quoridor_difficulty.bind(i + 1)" in main
    assert '"quo_difficulty_%d"' in main
    assert '"خیلی آسان", "آسان", "متوسط", "سخت", "استاد", "استادتمام"' in main
    assert "clampi(level, 1, 6)" in main


def test_quoridor_uses_two_edge_walls_and_supports_four_player_hotseat() -> None:
    project_root = Path(__file__).resolve().parents[1]
    rules = (project_root / "games" / "quoridor" / "rules.gd").read_text(encoding="utf-8")
    main = (project_root / "main.gd").read_text(encoding="utf-8")
    catalog = (project_root / "core" / "game_catalog.gd").read_text(encoding="utf-8")
    assert "quo_pawns = [Vector2i(4, 0), Vector2i(8, 4), Vector2i(4, 8), Vector2i(0, 4)]" in rules
    assert "quo_walls_left = [5, 5, 5, 5]" in rules
    assert "cell * 2 - 6" in rules
    assert 'quo_walls.has("v%d,%d" % [boundary_x, from.y - 1])' in rules
    assert 'quo_walls.has("h%d,%d" % [from.x - 1, boundary_y])' in rules
    assert "func _quo_wall_geometry_clear(" in rules
    assert "func _quo_wall_placement_legal(" in rules
    assert "func _quo_legal_moves_from(" in rules
    assert "func _quo_advance_turn(" in rules
    assert "func _quo_has_legal_wall(" in rules
    assert "var can_wall: bool = int(quo_walls_left[candidate]) > 0" in rules
    assert "func _first_legal_wall(" in (project_root / "games" / "quoridor" / "ai.gd").read_text(encoding="utf-8")
    assert "_start_quoridor_local_four_player" in main
    assert '"m_quoridor_local4"' in main
    assert '"players": "۲ یا ۴ نفر", "max_p": 4' in catalog


def test_othello_ai_has_six_levels_and_supports_twelve_by_twelve() -> None:
    project_root = Path(__file__).resolve().parents[1]
    ai = (project_root / "games" / "othello" / "ai.gd").read_text(encoding="utf-8")
    rules = (project_root / "games" / "othello" / "rules.gd").read_text(encoding="utf-8")
    main = (project_root / "main.gd").read_text(encoding="utf-8")
    assert "func choose_move(board: Array, board_size: int, player: int, difficulty: int) -> Vector2i" in ai
    assert "var depth_by_level: Array[int] = [0, 0, 2, 3, 4, 5]" in ai
    assert "_node_limit = [0, 0, 650, 1500, 2900, 4600][level - 1]" in ai
    assert "func _search(" in ai
    assert "func _evaluate(" in ai
    assert "func _legal_moves(" in ai
    assert "func _terminal_value(" in ai
    assert 'const OthelloAIScript = preload("res://games/othello/ai.gd")' in rules
    assert "ai.choose_move(othello_board, oth_size, othello_turn, oth_difficulty)" in rules
    assert 'elif selected_game in ["othello", "othello12"]:' in main
    assert "_set_othello_difficulty.bind(i + 1)" in main
    assert '"oth_difficulty_%d"' in main
    assert 'oth_size = 12' in main
