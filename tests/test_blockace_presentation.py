from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
RULES = (ROOT / "games" / "blockace" / "rules.gd").read_text(encoding="utf-8")
PRESENTATION = (ROOT / "games" / "blockace" / "presentation.gd").read_text(encoding="utf-8")
MAIN = (ROOT / "main.gd").read_text(encoding="utf-8")


def test_blockace_rules_delegate_rendering_buttons_and_board_hit_testing():
    assert 'preload("res://games/blockace/presentation.gd")' in RULES
    assert "var _blockace_presentation = BlockacePresentationScript.new()" in RULES
    for method in ("handle_tap", "build_buttons", "draw_cell", "render"):
        assert re.search(rf"^func\s+{method}\(", PRESENTATION, re.M)
    for wrapper in (
        "_blockace_presentation.handle_tap(app, self, p)",
        "_blockace_presentation.build_buttons(app, self)",
        "_blockace_presentation.draw_cell(app, r, col)",
        "_blockace_presentation.render(app, self)",
    ):
        assert wrapper in RULES
    assert "app._draw_hud(" not in RULES
    assert "app._panel(" not in RULES
    assert "app._add_btn(" not in RULES


def test_blockace_presentation_delegates_cell_selection_and_never_mutates_rules_state():
    assert "game._blk_handle_target(Vector2i(gx, gy))" in PRESENTATION
    assert "func _blk_handle_target(target: Vector2i) -> void:" in RULES
    assert "if blk_prev == target:" in RULES
    assert "func _blk_confirm() -> void:" in RULES
    assignments = re.findall(r"^\s*game\.(blk_[A-Za-z0-9_]+)\s*=(?!=)", PRESENTATION, re.M)
    assert assignments == [], f"presentation must not mutate Blockace state: {assignments}"


def test_blockace_placement_rules_and_cpu_remain_in_authoritative_module():
    for method in ("_blk_can_place", "_blk_place", "_blk_finish_game", "_blk_cpu", "_blk_apply_net"):
        assert re.search(rf"^func\s+{method}\(", RULES, re.M), f"rules module lost {method}()"
    assert "game._blk_can_place(" in PRESENTATION
    assert "game._blk_cells(" in PRESENTATION
    assert '"_rpc_blk_place"' in RULES
    assert '"blockace": _draw_blockace()' in MAIN
    assert '"blockace": _btns_blockace()' in MAIN


def test_blockace_presentation_only_calls_existing_app_helpers():
    main_functions = set(re.findall(r"^func\s+(\w+)\(", MAIN, re.M))
    used = {name for name in re.findall(r"\bapp\.(\w+)\s*\(", PRESENTATION) if name.startswith("_")}
    missing = sorted(used - main_functions)
    assert missing == [], f"presentation calls missing app methods: {missing}"
