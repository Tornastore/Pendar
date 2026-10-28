import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_all_three_games_are_catalogued_as_playable_games():
    catalog = read("core/game_catalog.gd")
    main = read("main.gd")
    protocol = read("online-server/lib/protocol.js")
    for game_id in ("connect4", "jenga", "mafia"):
        assert f'"id": "{game_id}"' in catalog
        assert f'"{game_id}": preload("res://games/{game_id}/rules.gd")' in main
        assert f"'{game_id}'" in protocol
        assert (ROOT / "games" / game_id / "rules.gd").is_file()
        assert (ROOT / "games" / game_id / "presentation.gd").is_file()


def test_new_game_metadata_has_expected_player_and_difficulty_ranges():
    expected = {
        "connect4": {"players": 2},
        "jenga": {"min_players": 2, "max_players": 4},
        "mafia": {"min_players": 6, "max_players": 12},
    }
    for game_id, expected_fields in expected.items():
        meta = json.loads(read(f"games/{game_id}/game.json"))
        assert meta["id"] == game_id
        for field, value in expected_fields.items():
            assert meta[field] == value
        assert meta["difficulty_levels"] == 6
        assert meta["network"]


def test_connect_four_has_standard_board_win_detection_and_cpu_search():
    rules = read("games/connect4/rules.gd")
    assert "for _y in range(6)" in rules
    assert "for _x in range(7)" in rules
    assert "func _c4_has_four" in rules
    assert "Vector2i(1, -1)" in rules
    assert "func _c4_minimax" in rules
    assert "_rpc_connect4_drop" in rules


def test_jenga_enforces_remove_then_place_and_host_authoritative_risk():
    rules = read("games/jenga/rules.gd")
    presentation = read("games/jenga/presentation.gd")
    main = read("main.gd")
    server = read("online-server/server.js")
    assert "func _jenga_legal_removal" in rules
    assert 'jenga_phase = "place"' in rules
    assert '"place"' in rules and "_jenga_legal_place_slots" in rules
    assert "TOWER_BOTTOM - (level + 1) * row_h" in presentation
    assert "roll = randf()" in main
    assert "crypto.randomInt(0, 1_000_000)" in server
    assert "authoritative collapse roll" in main


def test_mafia_classic_roles_phase_resolution_and_online_security_caveat():
    rules = read("games/mafia/rules.gd")
    presentation = read("games/mafia/presentation.gd")
    docs = read("games/mafia/README.md")
    assert all(token in rules for token in ("ROLE_MAFIA", "ROLE_DETECTIVE", "ROLE_DOCTOR", "ROLE_CITIZEN"))
    assert "_mafia_resolve_day_if_ready" in rules
    assert "_mafia_resolve_night_if_ready" in rules
    assert "mafia_private_note" in presentation
    assert "چت متنی ندارد" in docs
    assert "برای بازی دوستانه طراحی شده است" in docs


def test_new_game_instructions_are_in_shared_rules_content():
    content = read("core/ui_content.gd")
    for game_id in ("connect4", "jenga", "mafia"):
        assert f'"{game_id}": [' in content
