#!/usr/bin/env python3
"""Static regression checks for multiplayer capacity and in-game result overlays."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
MAIN = (ROOT / "main.gd").read_text(encoding="utf-8")
CATALOG = (ROOT / "core/game_catalog.gd").read_text(encoding="utf-8")
MM = (ROOT / "games/mastermind/rules.gd").read_text(encoding="utf-8")
PROTO = (ROOT / "online-server/lib/protocol.js").read_text(encoding="utf-8")
SERVER = (ROOT / "online-server/server.js").read_text(encoding="utf-8")


class MultiplayerCapacityAndResultsTests(unittest.TestCase):
    def test_quoridor_and_mastermind_advertise_four_player_capacity(self):
        self.assertIn('"id": "quoridor"', CATALOG)
        self.assertIn('"players": "۲ یا ۴ نفر", "max_p": 4', CATALOG)
        self.assertIn('"id": "mastermind"', CATALOG)
        self.assertIn('"players": "۲ تا ۴ نفر", "max_p": 4', CATALOG)
        self.assertIn("function playerCapacityForGame(game)", PROTO)
        self.assertIn("if (game === 'mastermind' || game === 'quoridor') return 4", PROTO)

    def test_lan_mastermind_race_keeps_secret_on_host_and_accepts_four_seats(self):
        self.assertIn("var mm_lan_race: bool = false", MM)
        self.assertIn("func _mm_lan_process_guess(guess: Array, seat: int)", MAIN)
        self.assertIn('func _rpc_mm_lan_submit(guess: Array, claimed_seat: int)', MAIN)
        self.assertIn('rpc_id(receiver_id, "_rpc_mm_lan_feedback", packet)', MAIN)
        self.assertIn("func _mm_lan_build_progress() -> Array", MAIN)
        self.assertIn('rpc("_rpc_mm_lan_race_over", progress, mm.mm_secret.duplicate())', MAIN)
        self.assertIn("if mm_online_race:", MM)
        self.assertIn("mm_secret = []", MM)

    def test_lan_players_register_usernames_and_room_capacity(self):
        self.assertIn('rpc_id(1, "_rpc_register_lan_username", online_username)', MAIN)
        self.assertIn('func _rpc_register_lan_username(username: String)', MAIN)
        self.assertIn('func _rpc_lan_roster_sync(players: Array)', MAIN)
        self.assertIn('max_players_for_game = int(_game_info(selected_game).get("max_p", 2))', MAIN)

    def test_match_end_is_an_overlay_and_modules_do_not_switch_to_result_scene(self):
        self.assertIn("func _go_result(_won: bool = false) -> void:", MAIN)
        self.assertIn("_result_popup_open = true", MAIN)
        self.assertIn("func _draw_result_popup() -> void:", MAIN)
        self.assertIn("_draw_result_popup()", MAIN)
        self.assertNotIn("state = State.RESULT", MAIN)
        for module in (ROOT / "games").glob("*/rules.gd"):
            text = module.read_text(encoding="utf-8")
            self.assertNotIn("state = State.RESULT", text, f"{module}: should use in-board result popup")


    def test_ip_lobby_preserves_four_player_seats_and_updates_roster_on_disconnect(self):
        self.assertIn('peer.create_server(PORT, maxi(1, max_players_for_game - 1))', MAIN)
        self.assertIn('for seat in range(maxi(2, max_players_for_game))', MAIN)
        self.assertIn('"connected": connected', MAIN)
        self.assertIn('for seat in range(4):', MAIN[MAIN.index('func _draw_lobby()'):MAIN.index('# ---------------- IP ENTRY')])
        disconnect = MAIN[MAIN.index('func _on_peer_disconnected'):MAIN.index('@rpc("authority", "call_local", "reliable")\nfunc _rpc_lobby_sync')]
        self.assertIn('rpc("_rpc_lan_roster_sync", _build_lan_roster())', disconnect)
        self.assertIn('func _rpc_register_lan_username(username: String)', MAIN)

    def test_mastermind_only_shows_public_exact_progress_for_other_players(self):
        sidebar = MM[MM.index('func _draw_mm_online_sidebar()'):MM.index('func _mm_online_feedback')]
        self.assertIn('latest_black', sidebar)
        self.assertIn('رتبه‌بندی', sidebar)
        self.assertIn('progress_ratio', sidebar)
        self.assertNotIn('attempts_used', sidebar)
        self.assertNotIn('status_text', sidebar)
        self.assertIn('rankMastermindPlayers', SERVER)

    def test_every_game_uses_result_overlay_and_final_board_remains_visible(self):
        self.assertIn('func _go_result(_won: bool = false) -> void:', MAIN)
        self.assertIn('_result_popup_open = true', MAIN)
        result_screen = (ROOT / 'ui' / 'screens' / 'result_screen.gd').read_text(encoding='utf-8')
        self.assertIn('var panel := Rect2(28, 218, float(theme["VIEW_W"]) - 56, 508)', result_screen)
        self.assertIn('_result_screen.render_popup(self, _ui_screen_theme)', MAIN)
        for module in (ROOT / 'games').glob('*/rules.gd'):
            text = module.read_text(encoding='utf-8')
            self.assertIn('_go_result(', text, f'{module}: missing in-HUD result popup trigger')
            self.assertNotIn('state = State.RESULT', text, f'{module}: should preserve final board')

    def test_four_player_quoridor_uses_all_seats_for_move_claims(self):
        self.assertIn('func _rpc_quo_action(kind: int, x: int, y: int, vertical: bool, claimed_seat: int = -1)', MAIN)
        self.assertIn('if claimed_seat != active_seat:', MAIN)
        self.assertIn('"_rpc_quo_action": _rpc_quo_action(int(args[0]), int(args[1]), int(args[2]), bool(args[3]), int(args[4]) if args.size() > 4 else -1)', MAIN)


if __name__ == "__main__":
    unittest.main(verbosity=2)
