from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def test_game_catalog_menu_is_delegated_to_its_screen_module():
    main = (ROOT / "main.gd").read_text(encoding="utf-8")
    menu = (ROOT / "ui" / "screens" / "menu_screen.gd").read_text(encoding="utf-8")

    assert 'preload("res://ui/screens/menu_screen.gd")' in main
    assert "var _menu_screen = MenuScreenScript.new()" in main
    assert "return _menu_screen.filtered_games(self)" in main
    assert "return _menu_screen.tile_rect(self, i)" in main
    assert "_menu_screen.build_buttons(self, _ui_screen_theme)" in main
    assert "_menu_screen.render(self, _ui_screen_theme)" in main
    assert "_menu_screen.render_game_tile(self, g, r, pressed, _ui_screen_theme)" in main
    for method in ("filtered_games", "tile_rect", "build_buttons", "render", "render_game_tile"):
        assert f"func {method}(" in menu


def test_menu_screen_does_not_own_application_or_filter_state():
    menu = (ROOT / "ui" / "screens" / "menu_screen.gd").read_text(encoding="utf-8")
    assert "host.state =" not in menu
    assert "host.selected_game =" not in menu
    assert not re.search(r"host\.menu_filter\s*=(?!=)", menu)
    assert "host._set_filter.bind(key)" in menu
    assert "host._select_game.bind(game_id)" in menu


def test_menu_tile_text_call_matches_main_text_helper_signature():
    menu = (ROOT / "ui" / "screens" / "menu_screen.gd").read_text(encoding="utf-8")
    assert 'host._txt_c(player_label, chip, host._fit_size(player_label, chip.size.x - 8.0, 12, true), theme["TEXT"], true)' in menu
    assert 'host._txt_c(player_label, chip, host._fit_size(player_label, chip.size.x - 8.0, 12, true), 12, theme["TEXT"], true)' not in menu
