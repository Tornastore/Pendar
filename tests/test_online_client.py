from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_websocket_transport_is_owned_by_online_client_service():
    main = (ROOT / "main.gd").read_text(encoding="utf-8")
    client = (ROOT / "services" / "online_client.gd").read_text(encoding="utf-8")
    assert 'preload("res://services/online_client.gd")' in main
    assert "var _online_client = OnlineClientScript.new()" in main
    assert "ws_socket" not in main
    assert "WebSocketPeer.new()" in client
    for method in (
        "connect_to_url", "poll", "send_json", "receive_next_message", "close"
    ):
        assert f"func {method}(" in client


def test_online_matchmaking_policy_stays_in_controller():
    main = (ROOT / "main.gd").read_text(encoding="utf-8")
    assert '"type": "join_queue"' in main
    assert "func _ws_handle_server_message(" in main
    assert "func _ws_begin_match(" in main
    assert "func _ws_execute_game_action(" in main
