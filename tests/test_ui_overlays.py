from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def _method(source: str, name: str) -> str:
    match = re.search(rf"^func {re.escape(name)}\([^\n]*\).*?:\n", source, re.M)
    assert match, f"missing {name}()"
    start = match.end()
    next_method = re.search(r"^func \w+\(", source[start:], re.M)
    end = start + next_method.start() if next_method else len(source)
    return source[start:end]


def test_overlay_rendering_is_delegated_to_dedicated_modules():
    main = (ROOT / "main.gd").read_text(encoding="utf-8")
    expected = {
        "ui/screens/pause_screen.gd": (
            'preload("res://ui/screens/pause_screen.gd")',
            "_pause_screen.build_buttons(self, _ui_screen_theme)",
            "_pause_screen.render(self, _ui_screen_theme)",
        ),
        "ui/screens/rules_screen.gd": (
            'preload("res://ui/screens/rules_screen.gd")',
            "_rules_screen.build_buttons(self, _ui_screen_theme)",
            "_rules_screen.render(self, _ui_screen_theme)",
        ),
        "ui/components/dialog_component.gd": (
            'preload("res://ui/components/dialog_component.gd")',
            "_dialog_component.build_buttons(self, _ui_screen_theme)",
            "_dialog_component.render(self, _ui_screen_theme)",
        ),
    }
    for relative_path, (preload, buttons_delegate, render_delegate) in expected.items():
        module = (ROOT / relative_path).read_text(encoding="utf-8")
        assert preload in main
        assert buttons_delegate in main
        assert render_delegate in main
        assert module.startswith("extends RefCounted")
        assert "func build_buttons(host, theme: Dictionary) -> void:" in module
        assert "func render(host, theme: Dictionary) -> void:" in module
        assert "host.dialog =" not in module
        assert "host.pause_open =" not in module
        assert "host.rules_open =" not in module


def test_rules_data_and_pagination_are_owned_by_rules_presenter():
    main = (ROOT / "main.gd").read_text(encoding="utf-8")
    rules = (ROOT / "ui/screens/rules_screen.gd").read_text(encoding="utf-8")
    assert "const CONN_HELP := [" in rules
    assert "const RULES_PAGE_SIZE := 4" in rules
    assert "host.rules_page =" not in rules
    assert "func page_count(host) -> int:" in rules
    assert "return _rules_screen.lines(self)" in main
    assert "return _rules_screen.title(self)" in main
    assert "var pages: int = _rules_screen.page_count(self)" in main
    assert "const CONN_HELP := [" not in main


def test_confirmation_and_overlay_navigation_state_stay_in_main_controller():
    main = (ROOT / "main.gd").read_text(encoding="utf-8")
    confirm = _method(main, "_show_confirm")
    dialog_confirm = _method(main, "_dialog_confirm")
    close_pause = _method(main, "_close_pause")
    close_rules = _method(main, "_close_rules")
    assert 'dialog = {"kind": kind' in confirm
    assert "cb.call()" in dialog_confirm
    assert "pause_open = false" in close_pause
    assert 'rules_context = "game"' in close_rules
