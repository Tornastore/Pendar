#!/usr/bin/env python3
"""Static contract tests for Mastermind network play, difficulty and slot feedback."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
RULES = (ROOT / "games/mastermind/rules.gd").read_text(encoding="utf-8")
MAIN = (ROOT / "main.gd").read_text(encoding="utf-8")
CATALOG = (ROOT / "core/game_catalog.gd").read_text(encoding="utf-8")


class MastermindFeatureTests(unittest.TestCase):
    def test_each_difficulty_adds_one_peg_and_one_colour(self):
        self.assertIn("mm_code_len = clampi(3 + mm_difficulty, 4, 9)", RULES)
        self.assertIn("mm_color_count = clampi(3 + mm_difficulty, 4, 9)", RULES)
        self.assertIn("mm_code_len = 3 + mm_difficulty", MAIN)
        self.assertIn("mm_color_count = 3 + mm_difficulty", MAIN)
        self.assertIn("_set_mastermind_difficulty.bind(i + 1)", MAIN)

    def test_multiplayer_uses_host_secret_and_ip_networking(self):
        self.assertIn('"mastermind"', MAIN[MAIN.index("const NET_GAMES"):MAIN.index("const NET_GAMES") + 300])
        self.assertIn("mm_phase = 0 if app.is_host else 2", RULES)
        self.assertIn('rpc_id(client_id, "_rpc_mm_secret_ready", mm_code_len, mm_color_count)', RULES)
        self.assertIn('app.rpc_id(1, "_rpc_mm_submit", mm_cur.duplicate(), 1)', RULES)
        self.assertIn('func _rpc_mm_secret_ready(code_length: int, color_count: int)', MAIN)
        self.assertIn('func _rpc_mm_sync_state(guesses: Array, is_over: bool, winner: int)', MAIN)
        self.assertNotIn('"دو نفره روی یک دستگاه"', MAIN)
        self.assertNotIn("func _start_mastermind_local_two_player", MAIN)
        self.assertIn('"net": true', CATALOG)

    def test_feedback_markers_align_under_each_guess_slot(self):
        self.assertIn('var mark := Vector2(peg.x, y + 14.0)', RULES)
        self.assertIn('var state_value: int = int(feedback[i])', RULES)
        self.assertIn('"f": feedback', RULES)

    def test_render_feedback_branches_are_aligned(self):
        lines = RULES.splitlines()
        if_line = next(i for i, line in enumerate(lines) if line.strip() == "if gi < used:")
        elif_line = next(i for i, line in enumerate(lines) if line.strip() == "elif active and mm_filled[i]:")
        feedback_if = next(i for i, line in enumerate(lines) if line.strip() == "if gi < used:" and i > elif_line)
        indent = lambda line: len(line) - len(line.lstrip("\t"))
        self.assertEqual(indent(lines[if_line]), indent(lines[elif_line]))
        self.assertEqual(indent(lines[feedback_if]), indent(lines[if_line]))

    def test_canvas_draw_commands_are_delegated_to_main_node(self):
        # Rule modules are RefCounted objects, not CanvasItems. Drawing calls
        # must go through app (the Node2D currently executing _draw()).
        for line_no, line in enumerate(RULES.splitlines(), 1):
            stripped = line.lstrip("\t ")
            self.assertFalse(
                stripped.startswith("draw_circle("),
                f"Bare draw_circle call at games/mastermind/rules.gd:{line_no}; use app.draw_circle().",
            )
        self.assertEqual(RULES.count("app.draw_circle("), 5)


    def test_race_rank_remains_live_until_every_player_finishes(self):
        feedback = RULES[RULES.index('func _mm_accept_race_feedback'):RULES.index('func _mm_apply')]
        self.assertIn('Keep the live leaderboard visible until every racer has finished.', feedback)
        self.assertNotIn('app._go_result(solved)', feedback)
        self.assertIn('"mastermind_race_over"', MAIN)
        self.assertIn('_go_result(false)', MAIN[MAIN.index('"mastermind_race_over"'):MAIN.index('"restart_game"', MAIN.index('"mastermind_race_over"'))])
        self.assertIn('final_secret', MAIN)

    def test_public_mastermind_sidebar_does_not_expose_other_guess_rows(self):
        sidebar = RULES[RULES.index('func _draw_mm_online_sidebar'):RULES.index('func _mm_online_feedback')]
        self.assertIn('latest_black', sidebar)
        self.assertIn('progress_ratio', sidebar)
        self.assertNotIn('attempts_used', sidebar)
        self.assertNotIn('entry.get(\"guess\"', sidebar)

    def test_guess_slots_and_color_controls_are_dynamic(self):
        self.assertIn("for i in range(mm_code_len):", RULES)
        self.assertIn("for i in range(mm_color_count):", RULES)
        self.assertIn("g.size() != mm_code_len", RULES)
        self.assertIn("int(colour) >= mm_color_count", RULES)


if __name__ == "__main__":
    unittest.main(verbosity=2)
