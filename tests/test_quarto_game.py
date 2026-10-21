from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]


def test_quarto_is_registered_as_a_full_game():
    main = (ROOT / "main.gd").read_text(encoding="utf-8")
    catalog = (ROOT / "core/game_catalog.gd").read_text(encoding="utf-8")
    metadata = json.loads((ROOT / "games/quarto/game.json").read_text(encoding="utf-8"))
    assert '"quarto": preload("res://games/quarto/rules.gd")' in main
    assert '"id": "quarto"' in catalog
    assert metadata["id"] == "quarto"
    assert metadata["variant"] == "Standard Quarto"
    assert metadata["difficulty_levels"] == 6
    assert metadata["beta"] is False
    assert '"quarto"' in main[main.index("const NET_GAMES"):main.index("const TILE_W")]


def test_quarto_standard_rules_cover_all_attributes_and_phases():
    rules = (ROOT / "games/quarto/rules.gd").read_text(encoding="utf-8")
    assert "for piece in range(16)" in rules
    assert "qto_phase: int = 0" in rules
    assert "qto_phase = 1" in rules
    assert "_qto_has_quarto()" in rules
    assert "all_true != 0 or all_false != 0" in rules
    assert "_qto_finish(actor)" in rules


def test_quarto_has_six_cpu_levels_and_prefers_winning_or_safe_moves():
    main = (ROOT / "main.gd").read_text(encoding="utf-8")
    ai = (ROOT / "games/quarto/ai.gd").read_text(encoding="utf-8")
    assert "_set_quarto_difficulty.bind(i + 1)" in main
    assert "var budgets: Array[int] = [0, 450, 650, 950, 1500, 2300]" in ai
    assert "_winning_count(game, piece)" in ai
    assert "Never miss a direct win" in ai


def test_quarto_actions_are_wired_to_lan_and_websocket_paths():
    main = (ROOT / "main.gd").read_text(encoding="utf-8")
    protocol = (ROOT / "online-server/lib/protocol.js").read_text(encoding="utf-8")
    for action in ("_rpc_quarto_choose_piece", "_rpc_quarto_place"):
        assert action in main
        assert action in protocol
    assert "func _quarto_rpc_seat_allowed" in main
    assert "_ws_game_turn_seat" in main


def test_quarto_rules_and_persian_help_exist():
    help_content = (ROOT / "core/ui_content.gd").read_text(encoding="utf-8")
    readme = (ROOT / "games/quarto/README.md").read_text(encoding="utf-8")
    assert '"quarto": [' in help_content
    assert "توخالی" in help_content
    assert "هر مهره فقط یک‌بار استفاده می‌شود" in readme
    assert "هوش CPU" in readme


def test_quarto_piece_encoding_has_sixteen_unique_values_and_standard_line_rule():
    pieces = list(range(16))
    assert len(pieces) == len(set(pieces)) == 16

    def line_wins(line):
        all_true = 15
        all_false = 15
        for piece in line:
            all_true &= piece
            all_false &= (~piece) & 15
        return all_true != 0 or all_false != 0

    assert line_wins([1, 3, 5, 7])  # bit zero is common
    assert line_wins([0, 2, 4, 6])  # bit zero is false in all four
    assert not line_wins([0, 1, 2, 12])
