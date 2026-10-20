#!/usr/bin/env python3
"""Static contract tests for Mastermind hot-seat mode and difficulty UI."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
RULES = (ROOT / "games/mastermind/rules.gd").read_text(encoding="utf-8")
MAIN = (ROOT / "main.gd").read_text(encoding="utf-8")


class MastermindFeatureTests(unittest.TestCase):
    def test_six_levels_map_to_four_through_nine_pegs(self):
        self.assertIn("mm_code_len = clampi(3 + mm_difficulty, 4, 9)", RULES)
        self.assertIn("_set_mastermind_difficulty.bind(i + 1)", MAIN)
        self.assertIn('"طول کد: %s مهره"', MAIN)

    def test_local_two_player_code_maker_and_handoff(self):
        self.assertIn("mm_local_two_player", RULES)
        self.assertIn('"دو نفره روی یک دستگاه"', MAIN)
        self.assertIn('"ثبت کد مخفی"', RULES)
        self.assertIn('"شروع حدس · بازیکن دوم"', RULES)
        self.assertIn('mm_winner = 0 # secret maker wins if the code is not cracked in ten attempts', RULES)

    def test_feedback_markers_are_drawn_in_a_single_row(self):
        self.assertIn("One horizontal feedback row per guess", RULES)
        self.assertIn("Vector2(panel.position.x + 26.0 + float(k) * feedback_gap, y)", RULES)
        self.assertNotIn("(k % 2) * 18", RULES)

    def test_code_and_guess_controls_follow_dynamic_length(self):
        self.assertIn("for i in range(mm_code_len):", RULES)
        self.assertIn("g.size() != mm_code_len", RULES)
        self.assertIn("for i in range(mm_code_len):", MAIN)


if __name__ == "__main__":
    unittest.main(verbosity=2)
