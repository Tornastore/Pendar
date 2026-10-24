from pathlib import Path
import re


def test_pentago_presentation_is_separate_and_rules_remain_authoritative() -> None:
    root = Path(__file__).resolve().parents[1]
    rules = (root / "games" / "pentago" / "rules.gd").read_text(encoding="utf-8")
    presentation = (root / "games" / "pentago" / "presentation.gd").read_text(encoding="utf-8")
    main = (root / "main.gd").read_text(encoding="utf-8")

    assert 'preload("res://games/pentago/presentation.gd")' in rules
    assert "var _pent_presentation = PentagoPresentationScript.new()" in rules

    for method in ("board_origin", "cell_pos", "quad_rect", "handle_tap", "build_buttons", "render"):
        assert re.search(rf"^func\s+{method}\(", presentation, re.M), method

    for wrapper in (
        "return _pent_presentation.board_origin(app)",
        "return _pent_presentation.cell_pos(app, x, y)",
        "_pent_presentation.handle_tap(app, self, p)",
        "return _pent_presentation.quad_rect(app, q)",
        "_pent_presentation.build_buttons(app, self)",
        "_pent_presentation.render(app, self)",
    ):
        assert wrapper in rules, wrapper

    # Pointer geometry is presented separately; rule validity and network dispatch stay authoritative.
    assert "game._pent_handle_cell_tap(Vector2i(x, y))" in presentation
    assert "func _pent_handle_cell_tap(c: Vector2i) -> void:" in rules
    assert "if pent_game_over or pent_phase != 0 or not _pent_my_turn():" in rules
    assert 'app._send_game_action("_rpc_pent_place", [c.x, c.y])' in rules
    assert "game._pent_rot.bind(q, false)" in presentation
    assert "game._pent_rot.bind(q, true)" in presentation

    # Rendering must be read-only with respect to state owned by the rules module.
    assert not re.search(r"^\s*game\.pent_[A-Za-z0-9_]+\s*=(?!=)", presentation, re.M)
    for method in ("_pent_check_win", "_pent_rotate", "_pent_place", "_pent_do_rotate", "_pent_cpu_move", "_pent_choose_cpu_plan", "_pent_evaluate_board"):
        assert re.search(rf"^func\s+{method}\(", rules, re.M), method

    assert '"pentago": _btns_pentago()' in main
    assert '"pentago": _draw_pentago()' in main
    assert "func _pent_tap(p: Vector2) -> void:" in main


def test_pentago_presenter_uses_only_existing_app_drawing_helpers() -> None:
    root = Path(__file__).resolve().parents[1]
    presentation = (root / "games" / "pentago" / "presentation.gd").read_text(encoding="utf-8")
    main = (root / "main.gd").read_text(encoding="utf-8")
    app_functions = set(re.findall(r"^func\s+(\w+)\s*\(", main, re.M))
    app_calls = {name for name in re.findall(r"\bapp\.(\w+)\s*\(", presentation) if name.startswith("_")}
    assert not (app_calls - app_functions), sorted(app_calls - app_functions)
    for helper in ("_track_board", "_draw_hud", "_panel", "_draw_disc", "_ring", "_hint", "_txt_c"):
        assert f"app.{helper}(" in presentation
