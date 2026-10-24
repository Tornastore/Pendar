from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

def test_uno_screen_rendering_and_buttons_are_delegated():
    rules = (ROOT / "games" / "uno" / "rules.gd").read_text(encoding="utf-8")
    presentation = (ROOT / "games" / "uno" / "presentation.gd").read_text(encoding="utf-8")
    assert 'preload("res://games/uno/presentation.gd")' in rules
    assert "var _uno_presentation = UnoPresentationScript.new()" in rules
    for method in ("handle_tap", "build_buttons", "draw_card_visual", "render"):
        assert re.search(rf"^func {method}\(", presentation, re.M)
    assert "func _btns_uno() -> void:\n\t_uno_presentation.build_buttons(app, self)" in rules
    assert "func _uno_board_tap(p: Vector2) -> void:\n\t_uno_presentation.handle_tap(app, self, p)" in rules
    assert "func _draw_uno() -> void:\n\t_uno_presentation.render(app, self)" in rules
    assert "app._draw_hud(" not in rules and "app._panel(" not in rules and "app._txt_c(" not in rules
    assert "game._uno_select_card.bind(index)" in presentation
    assert "game._uno_submit_play(" in presentation

def test_uno_presentation_does_not_mutate_authoritative_round_state():
    presentation = (ROOT / "games" / "uno" / "presentation.gd").read_text(encoding="utf-8")
    authoritative = (
        "uno_hands", "uno_draw_pile", "uno_discard_pile", "uno_scores", "uno_turn",
        "uno_direction", "uno_current_color", "uno_game_over", "uno_round_over",
        "uno_winner", "uno_round_winner", "uno_challenge_available", "uno_challenge_target",
        "uno_last_wild4_actor", "uno_last_wild4_illegal", "uno_pending_round_winner",
        "uno_catch_seat", "uno_drawn_card_index",
    )
    pattern = r"^\s*game\.(?:" + "|".join(authoritative) + r")\s*=(?!=)"
    assert re.search(pattern, presentation, re.M) is None
