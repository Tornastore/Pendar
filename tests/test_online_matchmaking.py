from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_online_matchmaker_server_and_liara_config_exist():
    server = ROOT / "online-server" / "server.js"
    package = ROOT / "online-server" / "package.json"
    liara = ROOT / "online-server" / "liara.json"
    assert server.is_file() and package.is_file() and liara.is_file()
    text = server.read_text(encoding="utf-8")
    assert "join_queue" in text
    assert "match_found" in text
    assert "mastermind_secret_ready" in text
    assert "opponent_left" in text
    assert "ALLOWED_ORIGINS" in text


def test_websocket_client_routes_received_actions_to_correct_handler():
    main = (ROOT / "main.gd").read_text(encoding="utf-8")
    assert '"action":\n\t\t\t_receive_ws_game_action(message)' in main
    assert "func _receive_ws_game_action(message: Dictionary)" in main
    assert "_ws_receive_game_action" not in main


def test_endpoint_is_configurable_and_native_networking_is_preserved():
    project = (ROOT / "project.godot").read_text(encoding="utf-8")
    main = (ROOT / "main.gd").read_text(encoding="utf-8")
    assert "matchmaking_url=\"wss://REPLACE-WITH-YOUR-LIARA-APP-DOMAIN/ws\"" in project
    assert "ENetMultiplayerPeer" in main
    assert "WebSocketPeer.new()" in main
    assert "_send_game_action" in main


def test_online_docs_do_not_claim_server_is_already_deployed():
    guide = (ROOT / "ONLINE_SERVER_FA.txt").read_text(encoding="utf-8")
    assert "تا وقتی این سرویس را" in guide
    assert "liara deploy --app YOUR_LIARA_APP_ID" in guide
    assert "wss://mind-bastion-matchmaker-123.liara.run/ws" in guide


def test_liara_deploy_workflow_uses_repository_secret_and_app_variable():
    workflow = (ROOT / ".github" / "workflows" / "deploy-matchmaker.yml").read_text(encoding="utf-8")
    assert "workflow_dispatch" in workflow
    assert "vars.LIARA_MATCHMAKER_APP" in workflow
    assert "secrets.LIARA_API_TOKEN" in workflow
    assert "working-directory: online-server" in workflow
    assert "liara deploy" in workflow
