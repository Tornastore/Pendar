from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def test_othello_rendering_and_board_hit_testing_are_separated_from_rules():
    rules = (ROOT / "games" / "othello" / "rules.gd").read_text(encoding="utf-8")
    presentation = (ROOT / "games" / "othello" / "presentation.gd").read_text(encoding="utf-8")
    main = (ROOT / "main.gd").read_text(encoding="utf-8")

    assert 'preload("res://games/othello/presentation.gd")' in rules
    assert "var _presentation = OthelloPresentationScript.new()" in rules
    for method in ("cell_size", "board_origin", "is_my_turn", "handle_tap", "render"):
        assert re.search(rf"^func {method}\(", presentation, re.M)

    # Public/legacy module methods stay stable so main.gd's existing dispatch works.
    assert "func _oth_cell() -> float:\n\treturn _presentation.cell_size(self)" in rules
    assert "func _oth_origin() -> Vector2:\n\treturn _presentation.board_origin(app, self)" in rules
    assert "func _oth_my_turn() -> bool:\n\treturn _presentation.is_my_turn(app, self)" in rules
    assert "func _othello_tap(p: Vector2) -> void:\n\t_presentation.handle_tap(app, self, p)" in rules
    assert "func _draw_othello() -> void:\n\t_presentation.render(app, self)" in rules

    # Rules keep authority: a tap is converted to a cell then checked by the rules method.
    assert "game._othello_place(Vector2i(gx, gy))" in presentation
    assert "func _othello_place(c: Vector2i) -> bool:" in rules
    assert "func _othello_apply_place(c: Vector2i) -> void:" in rules
    assert "app._draw_hud(" in presentation and "app._panel(" in presentation
    assert "func _othello_tap(p: Vector2) -> void:" in rules
    assert '"othello", "othello12": _othello_tap(p)' in main
    assert '"othello", "othello12": _draw_othello()' in main


def test_othello_presentation_does_not_mutate_game_state_or_own_rules():
    presentation = (ROOT / "games" / "othello" / "presentation.gd").read_text(encoding="utf-8")
    forbidden_mutations = re.findall(
        r"^\s*game\.(?:oth_size|othello_board|othello_turn|othello_scores|othello_valid|othello_game_over|othello_last_move)\s*=",
        presentation,
        re.M,
    )
    assert forbidden_mutations == []
    assert "game.othello_board[y][x] =" not in presentation
    assert not re.search(r"^\s*game\.othello_turn\s*=(?!=)", presentation, re.M)
    assert "func _othello_update_valid(" not in presentation
    assert "func _othello_would_flip(" not in presentation
