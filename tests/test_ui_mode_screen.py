from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def test_mode_screen_is_wired_through_legacy_controller_entry_points():
    main = (ROOT / "main.gd").read_text(encoding="utf-8")
    mode = (ROOT / "ui/screens/mode_screen.gd").read_text(encoding="utf-8")

    assert 'preload("res://ui/screens/mode_screen.gd")' in main
    assert "var _mode_screen = ModeScreenScript.new()" in main
    assert "func _btns_mode() -> void:\n\t_mode_screen.build_buttons(self, _ui_screen_theme)" in main
    assert "func _draw_mode() -> void:\n\t_mode_screen.render(self, _ui_screen_theme)" in main
    assert mode.startswith("extends RefCounted")
    assert "func build_buttons(host, theme: Dictionary) -> void:" in mode
    assert "func render(host, theme: Dictionary) -> void:" in mode


def test_mode_screen_keeps_game_actions_and_state_changes_as_host_callbacks():
    mode = (ROOT / "ui/screens/mode_screen.gd").read_text(encoding="utf-8")
    main = (ROOT / "main.gd").read_text(encoding="utf-8")

    # The screen offers the existing game modes, but it does not mutate core state itself.
    for token in (
        '"m_cpu"', '"m_host"', '"m_join"', '"m_online"',
        '"m_local4"', '"m_cpu3"', 'host._set_uno_player_count.bind(count1)',
        'host._set_quoridor_difficulty.bind(i + 1)',
    ):
        assert token in mode
    assert not re.search(r"host\.selected_game\s*=(?!=)", mode)
    assert not re.search(r"host\.vs_cpu\s*=(?!=)", mode)
    assert not re.search(r"host\.state\s*=(?!=)", mode)
    for callback in ("_start_vs_cpu", "_start_host", "_go_ip_entry", "_open_online_for_game"):
        assert f"func {callback}(" in main
        assert f"host.{callback}" in mode
