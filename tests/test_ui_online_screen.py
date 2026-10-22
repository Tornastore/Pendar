from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def test_online_and_lobby_views_delegate_to_online_screen_presenter():
    main = (ROOT / "main.gd").read_text(encoding="utf-8")
    module = (ROOT / "ui/screens/online_screen.gd").read_text(encoding="utf-8")
    assert 'preload("res://ui/screens/online_screen.gd")' in main
    assert "var _online_screen = OnlineScreenScript.new()" in main
    expected = (
        "func _btns_online() -> void:\n\t_online_screen.build_online_buttons(self, _ui_screen_theme)",
        "func _draw_online() -> void:\n\t_online_screen.render_online(self, _ui_screen_theme)",
        "func _btns_lobby() -> void:\n\t_online_screen.build_lobby_buttons(self, _ui_screen_theme)",
        "func _draw_lobby() -> void:\n\t_online_screen.render_lobby(self, _ui_screen_theme)",
    )
    for entry in expected:
        assert entry in main
    for method in ("online_extra", "build_online_buttons", "render_online", "build_lobby_buttons", "render_lobby"):
        assert re.search(rf"^func {method}\(", module, re.M)


def test_online_screen_does_not_own_transport_or_matchmaking_state():
    module = (ROOT / "ui/screens/online_screen.gd").read_text(encoding="utf-8")
    for forbidden in ("WebSocketPeer.new()", "host.state =", "host.online_searching =", "host.ws_match_active =", "host._ws_send_json("):
        assert forbidden not in module
    # Existing behavior handlers are passed as callbacks; they remain implemented by the controller.
    main = (ROOT / "main.gd").read_text(encoding="utf-8")
    for action in ("_quick_match_search", "_cancel_online_search", "_start_network_game", "_request_leave_lobby"):
        assert f"func {action}(" in main
        assert f"host.{action}" in module
