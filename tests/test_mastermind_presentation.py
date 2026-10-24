from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
RULES = (ROOT / "games" / "mastermind" / "rules.gd").read_text(encoding="utf-8")
PRESENTATION = (ROOT / "games" / "mastermind" / "presentation.gd").read_text(encoding="utf-8")


def test_mastermind_rules_delegate_visuals_to_presentation_module():
    assert 'preload("res://games/mastermind/presentation.gd")' in RULES
    assert "var _mm_presentation = MastermindPresentationScript.new()" in RULES
    assert "_mm_presentation.build_buttons(app, self)" in RULES
    assert "_mm_presentation.render(app, self)" in RULES
    assert "_mm_presentation.render_online_sidebar(app, self)" in RULES
    for method in ("slot_pos", "color_pos", "build_buttons", "render", "render_online_sidebar"):
        assert re.search(rf"^func\s+{method}\(", PRESENTATION, re.M)


def test_mastermind_presenter_does_not_mutate_authoritative_game_state():
    assignments = re.findall(r"^\s*game\.(mm_[A-Za-z0-9_]+)\s*=(?!=)", PRESENTATION, re.M)
    assert assignments == [], f"presentation must not mutate rule state: {assignments}"
    assert "game.mm_secret" not in PRESENTATION, "the secret code must never be read by the presenter"
    assert "game._mm_pick.bind" in PRESENTATION
    assert "game._mm_pick_slot.bind" in PRESENTATION
    assert "game._mm_submit" in PRESENTATION


def test_mastermind_rule_callbacks_remain_authoritative():
    for method in ("_mm_pick", "_mm_pick_slot", "_mm_clear", "_mm_submit", "_mm_apply", "_mm_feedback", "_mm_accept_race_feedback"):
        assert re.search(rf"^func\s+{method}\(", RULES, re.M), f"rules module lost {method}"
    assert "func _btns_mastermind() -> void:\n\t_mm_presentation.build_buttons(app, self)" in RULES
    assert "func _draw_mastermind() -> void:\n\t_mm_presentation.render(app, self)" in RULES
