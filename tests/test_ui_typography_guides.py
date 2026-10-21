from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class TypographyAndGuideTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.main = (ROOT / "main.gd").read_text(encoding="utf-8")
        cls.catalog = (ROOT / "core" / "game_catalog.gd").read_text(encoding="utf-8")
        cls.readme = (ROOT / "README.md").read_text(encoding="utf-8")

    def test_every_catalog_game_has_a_guide(self):
        game_ids = [
            "othello", "othello12", "pentago", "quoridor", "chess", "domino",
            "pasoor", "hokm", "backgammon", "gobblet", "mastermind", "abalone", "blockace", "quarto",
        ]
        for game_id in game_ids:
            with self.subTest(game_id=game_id):
                self.assertIn(f'"{game_id}": [', self.main)

    def test_general_sections_have_context_help(self):
        for helper in ["_open_general_help", "_open_online_help", "_open_dashboard_help", "_open_rankings_help"]:
            with self.subTest(helper=helper):
                self.assertIn(f"func {helper}()", self.main)
        self.assertIn('"general": return GENERAL_HELP', self.main)
        self.assertIn('"online": return ONLINE_HELP', self.main)
        self.assertIn('"dashboard": return DASHBOARD_HELP', self.main)
        self.assertIn('"rankings": return RANKINGS_HELP', self.main)
        self.assertIn("func _rules_prev_page()", self.main)
        self.assertIn("func _rules_next_page()", self.main)
        self.assertIn("const RULES_PAGE_SIZE := 4", self.main)

    def test_persian_normalization_and_direction_are_centralized(self):
        self.assertIn('value.replace("ي", "ی").replace("ى", "ی").replace("ك", "ک")', self.main)
        self.assertGreaterEqual(self.main.count("TextServer.DIRECTION_AUTO"), 4)
        # Only the centralized render helpers should issue string drawing calls.
        draw_lines = [line.strip() for line in self.main.splitlines() if "draw_string(" in line or "draw_multiline_string(" in line]
        self.assertEqual(len(draw_lines), 4)
        self.assertTrue(all("display_text" in line for line in draw_lines))

    def test_username_input_uses_rtl_and_shared_font(self):
        self.assertIn("username_edit.text_direction = Control.TEXT_DIRECTION_RTL", self.main)
        self.assertIn('username_edit.add_theme_font_override("font", font)', self.main)
        self.assertIn('username_edit.add_theme_font_size_override("font_size", 16)', self.main)

    def test_web_and_android_builds_download_persian_font_and_license(self):
        for rel in [
            ".github/workflows/build-web.yml",
            ".github/workflows/deploy-web.yml",
            ".github/workflows/build-apk.yml",
        ]:
            text = (ROOT / rel).read_text(encoding="utf-8")
            with self.subTest(workflow=rel):
                self.assertIn("Download Persian fonts (Vazirmatn)", text)
                self.assertIn('download_font "Vazirmatn-Regular.ttf"', text)
                self.assertIn('download_font "Vazirmatn-Bold.ttf"', text)
                self.assertIn("fonts/OFL.txt", text)

    def test_similar_game_roadmap_is_documented(self):
        for name in ["Gomoku", "Checkers", "Nine Men's Morris", "Quarto", "Battleship", "Ludo", "Connect6", "Rummikub", "Hearts", "Hive"]:
            with self.subTest(game=name):
                self.assertIn(name, self.readme)
        self.assertIn("بازی‌های پیشنهادی برای توسعه‌ی آینده", self.readme)


if __name__ == "__main__":
    unittest.main()
