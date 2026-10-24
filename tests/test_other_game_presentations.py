"""Structural regression tests for presentation/rules boundaries in legacy game modules."""
from pathlib import Path
import re

PROJECT_ROOT = Path(__file__).resolve().parents[1]


def _read(game: str, filename: str) -> str:
    return (PROJECT_ROOT / "games" / game / filename).read_text(encoding="utf-8")


def test_remaining_game_presenters_are_loaded_and_rules_remain_authoritative() -> None:
    cases = {
        "quoridor": {
            "class": "QuoridorPresentationScript",
            "instance": "_quo_presentation",
            "prefix": "quo_",
            "render_wrapper": "_quo_presentation.render(app, self)",
            "tap_wrapper": None,
            "critical": ("_quo_legal_moves", "_quo_wall_placement_legal", "_quo_place_wall", "_quo_advance_turn"),
            "presenter_methods": ("edge_at", "build_buttons", "player_color", "draw_four_player_hud", "render"),
        },
        "gobblet": {
            "class": "GobbletPresentationScript",
            "instance": "_gob_presentation",
            "prefix": "gob_",
            "render_wrapper": "_gob_presentation.render(app, self)",
            "tap_wrapper": "_gob_presentation.handle_tap(app, self, p)",
            "critical": ("_gob_can_place", "_gob_can_move", "_gob_place", "_gob_move", "_gob_cpu"),
            "presenter_methods": ("hand_rect", "handle_tap", "build_buttons", "render"),
        },
        "pasoor": {
            "class": "PasoorPresentationScript",
            "instance": "_pas_presentation",
            "prefix": "pas_",
            "render_wrapper": "_pas_presentation.render(app, self)",
            "tap_wrapper": "_pas_presentation.handle_tap(app, self, p)",
            "critical": ("_pas_find_captures", "_pas_best_capture", "_pas_play", "_pas_cpu_move"),
            "presenter_methods": ("hand_rects", "table_rects", "handle_tap", "build_buttons", "render"),
        },
        "hokm": {
            "class": "HokmPresentationScript",
            "instance": "_hokm_presentation",
            "prefix": "hokm_",
            "render_wrapper": "_hokm_presentation.render(app, self)",
            "tap_wrapper": "_hokm_presentation.handle_tap(app, self, p)",
            "critical": ("_hokm_legal", "_hokm_play", "_hokm_cpu", "_hokm_card_beats"),
            "presenter_methods": ("hand_rects", "handle_tap", "render"),
        },
        "abalone": {
            "class": "AbalonePresentationScript",
            "instance": "_aba_presentation",
            "prefix": "aba_",
            "render_wrapper": "_aba_presentation.render(app, self)",
            "tap_wrapper": "_aba_presentation.handle_tap(app, self, p)",
            "critical": ("_aba_valid_cell", "_aba_moves_for_selection", "_aba_apply_group_move", "_aba_generate_all_moves"),
            "presenter_methods": ("cell_center", "hit_cell", "handle_tap", "render"),
        },
    }
    for game_id, case in cases.items():
        rules = _read(game_id, "rules.gd")
        presenter = _read(game_id, "presentation.gd")
        assert f'preload("res://games/{game_id}/presentation.gd")' in rules
        assert f"var {case['instance']} = {case['class']}.new()" in rules
        assert case["render_wrapper"] in rules
        for method in case["presenter_methods"]:
            assert re.search(rf"^func\s+{method}\(", presenter, re.M), (game_id, method)
        if case["tap_wrapper"]:
            assert case["tap_wrapper"] in rules
        for method in case["critical"]:
            assert re.search(rf"^func\s+{method}\(", rules, re.M), (game_id, method)
        assert not re.search(rf"^\s*game\.{case['prefix']}[A-Za-z0-9_]*\s*=(?!=)", presenter, re.M), game_id


def test_pasoor_and_hokm_presenters_do_not_call_back_into_layout_wrappers() -> None:
    pasoor = _read("pasoor", "presentation.gd")
    hokm = _read("hokm", "presentation.gd")
    assert "game._pas_hand_rects()" not in pasoor
    assert "game._pas_table_rects()" not in pasoor
    assert "game._hokm_rects()" not in hokm
    assert "game._pas_me()" in pasoor
    assert "game._hokm_me()" in hokm


def test_presenters_call_only_host_methods_defined_in_main() -> None:
    main = (PROJECT_ROOT / "main.gd").read_text(encoding="utf-8")
    main_methods = set(re.findall(r"^func\s+(\w+)\s*\(", main, re.M))
    for game_id in ("quoridor", "gobblet", "pasoor", "hokm", "abalone"):
        presenter = _read(game_id, "presentation.gd")
        app_calls = {name for name in re.findall(r"\bapp\.(\w+)\s*\(", presenter) if name.startswith("_")}
        assert app_calls <= main_methods, (game_id, sorted(app_calls - main_methods))
