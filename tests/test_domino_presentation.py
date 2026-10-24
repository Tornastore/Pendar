from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def test_domino_rendering_and_pointer_mapping_are_delegated_to_presentation():
    rules = (ROOT / "games" / "domino" / "rules.gd").read_text(encoding="utf-8")
    presentation = (ROOT / "games" / "domino" / "presentation.gd").read_text(encoding="utf-8")
    main = (ROOT / "main.gd").read_text(encoding="utf-8")

    assert 'preload("res://games/domino/presentation.gd")' in rules
    assert "var _domino_presentation = DominoPresentationScript.new()" in rules
    for method in ("hand_rects", "handle_tap", "build_buttons", "render"):
        assert re.search(rf"^func {method}\(", presentation, re.M)
    for wrapper in (
        "return _domino_presentation.hand_rects(app, self)",
        "_domino_presentation.handle_tap(app, self, p)",
        "_domino_presentation.build_buttons(app, self)",
        "_domino_presentation.render(app, self)",
    ):
        assert wrapper in rules
    assert '"domino": _dom_tap(p)' in main
    assert '"domino": _draw_domino()' in main
    assert "game._dom_select(index)" in presentation
    assert "app._draw_dom_tile(" in presentation and "app._draw_hud(" in presentation
    assert "app._draw_dom_tile(" not in rules
    assert "app._draw_hud(" not in rules


def test_domino_presentation_does_not_mutate_authoritative_domino_state():
    presentation = (ROOT / "games" / "domino" / "presentation.gd").read_text(encoding="utf-8")
    owned_state = ("dom_hands", "dom_boneyard", "dom_chain", "dom_left", "dom_right", "dom_turn", "dom_game_over", "dom_winner", "dom_selected", "dom_scores")
    pattern = r"^\s*game\.(?:" + "|".join(owned_state) + r")\s*=(?!=)"
    assert re.search(pattern, presentation, re.M) is None
    assert "func _dom_play(" not in presentation
    assert "func _dom_draw(" not in presentation
    assert "func _dom_pass(" not in presentation


def test_domino_authoritative_actions_reject_wrong_turn_and_illegal_draw_or_pass():
    rules = (ROOT / "games" / "domino" / "rules.gd").read_text(encoding="utf-8")
    assert 'end not in ["L", "R"]' in rules
    assert "p != dom_turn" in rules
    assert "idx < 0 or idx >= dom_hands[p].size()" in rules
    assert "not _dom_playable(p).is_empty() or dom_boneyard.is_empty()" in rules
    assert "not dom_boneyard.is_empty() or not _dom_playable(p).is_empty()" in rules
