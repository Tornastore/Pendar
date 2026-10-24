"""Quarto UI layout and authoritative state boundary checks."""
from pathlib import Path
import re

PROJECT_ROOT = Path(__file__).resolve().parents[1]


def test_quarto_presentation_mapping_rendering_and_wrappers() -> None:
    rules = (PROJECT_ROOT / "games" / "quarto" / "rules.gd").read_text(encoding="utf-8")
    presenter = (PROJECT_ROOT / "games" / "quarto" / "presentation.gd").read_text(encoding="utf-8")
    main = (PROJECT_ROOT / "main.gd").read_text(encoding="utf-8")
    for method in ("board_origin", "piece_rect", "handle_tap", "build_buttons", "render"):
        assert re.search(rf"^func\s+{method}\(", presenter, re.M)
    assert 'preload("res://games/quarto/presentation.gd")' in rules
    assert "_qto_presentation.handle_tap(app, self, p)" in rules
    assert "_qto_presentation.build_buttons(app, self)" in rules
    assert "_qto_presentation.render(app, self)" in rules
    assert 'func _draw_quarto() -> void:\n\t_game_modules[\"quarto\"]._draw_quarto()' in main
    assert 'return _game_modules["quarto"]._qto_piece_rect(piece)' in main
    assert "game._qto_handle_board_tap(cell)" in presenter
    assert "game._draw_quarto_piece" not in presenter
    assert "app._draw_quarto_piece(" in presenter
    assert not re.search(r"^\s*game\.qto_[A-Za-z0-9_]*\s*=(?!=)", presenter, re.M)
    for method in ("_qto_has_quarto", "_qto_choose_piece", "_qto_place", "_qto_cpu_step"):
        assert re.search(rf"^func\s+{method}\(", rules, re.M)


def test_quarto_main_draw_and_piece_geometry_are_wrappers() -> None:
    main = (PROJECT_ROOT / "main.gd").read_text(encoding="utf-8")
    qto_rect = main[main.index("func _quarto_piece_rect("):main.index("func _draw_quarto_piece(")]
    draw = main[main.index("func _draw_quarto() -> void:"):main.index("# ======================================================================\n#  LOGIC REPLACEMENTS")]
    assert 'return _game_modules["quarto"]._qto_piece_rect(piece)' in qto_rect
    assert '_game_modules["quarto"]._draw_quarto()' in draw
