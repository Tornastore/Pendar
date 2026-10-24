from pathlib import Path


def test_uno_registered_as_full_card_game_and_module():
    root = Path(__file__).resolve().parents[1]
    catalog = (root / "core" / "game_catalog.gd").read_text(encoding="utf-8")
    main = (root / "main.gd").read_text(encoding="utf-8")
    assert '"id": "uno"' in catalog
    assert '"players": "۲ تا ۱۰ نفر", "max_p": 10' in catalog
    assert '"uno": preload("res://games/uno/rules.gd")' in main
    assert '"uno": return int(_game_modules["uno"].uno_difficulty)' in main
    assert 'return int(_game_modules["uno"].uno_turn) == local_seat' in main


def test_uno_classic_setup_deck_round_score_and_actions_are_implemented():
    root = Path(__file__).resolve().parents[1]
    rules = (root / "games" / "uno" / "rules.gd").read_text(encoding="utf-8")
    presentation = (root / "games" / "uno" / "presentation.gd").read_text(encoding="utf-8")
    assert 'range(7)' in rules and 'uno_hands' in rules
    assert 'uno_scores[winner] = int(uno_scores[winner]) + points' in rules
    assert '>= 500' in rules
    assert '"skip", "reverse", "draw2": return 20' in rules
    assert '"wild", "wild4": return 50' in rules
    assert 'func _uno_apply_challenge(seat: int, challenge: bool)' in rules
    assert 'func _uno_apply_catch(seat: int)' in rules
    assert 'func _uno_cpu_turn()' in rules
    assert 'uno_difficulty >= 6' in rules or 'uno_difficulty == 6' in rules
    assert 'if hand_size == 2:' in presentation
    assert 'مسابقه تا ۵۰۰ امتیاز' in presentation


def test_uno_lan_and_websocket_protocol_support_up_to_ten_players():
    root = Path(__file__).resolve().parents[1]
    main = (root / "main.gd").read_text(encoding="utf-8")
    protocol = (root / "online-server" / "lib" / "protocol.js").read_text(encoding="utf-8")
    server = (root / "online-server" / "server.js").read_text(encoding="utf-8")
    assert '"uno"' in main[main.index('const NET_GAMES'):main.index(']\n', main.index('const NET_GAMES')) + 2]
    assert "if (game === 'uno') return 10" in protocol
    assert "'_rpc_uno_play'" in protocol
    assert "game === 'uno'" in server
    for method in ('_rpc_uno_play', '_rpc_uno_draw', '_rpc_uno_pass', '_rpc_uno_catch', '_rpc_uno_challenge', '_rpc_uno_next_round'):
        assert f'func {method}(' in main


def test_uno_duration_uses_hand_time_for_league_scoring():
    root = Path(__file__).resolve().parents[1]
    main = (root / "main.gd").read_text(encoding="utf-8")
    rules = (root / "games" / "uno" / "rules.gd").read_text(encoding="utf-8")
    scoring = (root / "services" / "scoring_service.gd").read_text(encoding="utf-8")
    assert 'duration_seconds = float(_game_modules["uno"].uno_round_duration_seconds)' in main
    assert 'uno_round_duration_seconds = maxf(1.0' in rules
    assert 'duration_multiplier' in scoring


def test_uno_metadata_and_host_room_size_selection():
    import json

    root = Path(__file__).resolve().parents[1]
    meta = json.loads((root / "games" / "uno" / "game.json").read_text(encoding="utf-8"))
    main = (root / "main.gd").read_text(encoding="utf-8")
    assert meta["id"] == "uno" and meta["beta"] is False
    assert meta["players"] == {"min": 2, "max": 10}
    assert meta["deck_cards"] == 112 and meta["cards_per_player"] == 7
    assert 'max_players_for_game = clampi(int(_game_modules["uno"].uno_player_count), 2, 10)' in main


def test_uno_wild4_bluff_can_be_challenged_without_losing_legality_check():
    root = Path(__file__).resolve().parents[1]
    rules = (root / "games" / "uno" / "rules.gd").read_text(encoding="utf-8")
    assert 'if kind in ["wild", "wild4"]:' in rules
    assert "func _uno_is_wild4_legal(seat: int, card_index: int = -1) -> bool:" in rules
    assert "_uno_is_wild4_legal(seat, index) if kind == \"wild4\" else true" in rules
    assert "uno_last_wild4_illegal = not legal_wild4" in rules


def test_uno_rejects_second_draw_and_only_offers_draw_once():
    root = Path(__file__).resolve().parents[1]
    rules = (root / "games" / "uno" / "rules.gd").read_text(encoding="utf-8")
    presentation = (root / "games" / "uno" / "presentation.gd").read_text(encoding="utf-8")
    assert "or uno_drawn_card_index >= 0" in rules
    assert "if game.uno_drawn_card_index < 0:" in presentation
    assert "uno_hand_page = int(uno_drawn_card_index / 7)" in rules
