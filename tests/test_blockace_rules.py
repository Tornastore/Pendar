#!/usr/bin/env python3
"""Static and data checks for the production Blokus Duo module."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
RULES = (ROOT / "games/blockace/rules.gd").read_text(encoding="utf-8")
MAIN = (ROOT / "main.gd").read_text(encoding="utf-8")
MODE_SCREEN = (ROOT / "ui/screens/mode_screen.gd").read_text(encoding="utf-8")
CATALOG = (ROOT / "core/game_catalog.gd").read_text(encoding="utf-8")
GAME_JSON = (ROOT / "games/blockace/game.json").read_text(encoding="utf-8")


def extract_piece_shapes():
    start = RULES.index("func _blk_piece_set()")
    end = RULES.index("func _reset_blockace()", start)
    body = RULES[start:end]
    shapes = []
    for line in body.splitlines():
        if line.startswith("\t\t["):
            shapes.append([tuple(map(int, pair)) for pair in re.findall(r"Vector2i\((-?\d+),\s*(-?\d+)\)", line)])
    return shapes


def normalize(points):
    min_x = min(x for x, _ in points)
    min_y = min(y for _, y in points)
    return tuple(sorted((x - min_x, y - min_y) for x, y in points))


def symmetry_forms(points):
    forms = []
    for reflected in (False, True):
        for rotations in range(4):
            moved = []
            for original_x, original_y in points:
                x = -original_x if reflected else original_x
                y = original_y
                for _ in range(rotations):
                    x, y = -y, x
                moved.append((x, y))
            forms.append(normalize(moved))
    return forms


def is_connected(points):
    point_set = set(points)
    seen = {next(iter(point_set))}
    stack = list(seen)
    while stack:
        x, y = stack.pop()
        for neighbour in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if neighbour in point_set and neighbour not in seen:
                seen.add(neighbour)
                stack.append(neighbour)
    return len(seen) == len(point_set)


class BlockaceRulesTests(unittest.TestCase):
    def test_full_21_piece_polyomino_set_is_connected_and_unique(self):
        shapes = extract_piece_shapes()
        self.assertEqual(len(shapes), 21)
        self.assertEqual(sorted(map(len, shapes)), [1, 2, 3, 3] + [4] * 5 + [5] * 12)
        self.assertEqual(sum(map(len, shapes)), 89)
        self.assertTrue(all(is_connected(shape) for shape in shapes))
        canonical = [min(symmetry_forms(shape)) for shape in shapes]
        self.assertEqual(len(set(canonical)), 21)

    def test_standard_corner_contact_and_no_edge_contact_rules_exist(self):
        self.assertIn("const BOARD_SIZE: int = 14", RULES)
        self.assertIn("var start_cell := Vector2i(4, 4) if player == 0 else Vector2i(9, 9)", RULES)
        self.assertIn("own_diagonal_contact = true", RULES)
        self.assertIn("return false", RULES)
        self.assertIn("var score: int = -remaining", RULES)
        self.assertIn("score += 15", RULES)
        self.assertIn("score += 5", RULES)

    def test_ip_lan_difficulty_and_production_listing(self):
        self.assertIn('"blockace"', MAIN[MAIN.index("const NET_GAMES"):MAIN.index("const NET_GAMES") + 400])
        self.assertIn('"blockace":', MAIN[MAIN.index("func _cpu_tick") : MAIN.index("func _ui_sig")])
        self.assertIn('"blockace"', CATALOG)
        self.assertIn('"beta": false', GAME_JSON)
        self.assertIn('host._set_blockace_difficulty.bind(i + 1)', MODE_SCREEN)
        self.assertIn('func _rpc_blk_place(px: int, py: int, sel: int, rot: int, flipped: bool, player: int)', MAIN)
        self.assertIn('multiplayer.get_remote_sender_id()', MAIN)
        self.assertIn('int(peer_to_seat[sender_id]) != player', MAIN)


if __name__ == "__main__":
    unittest.main(verbosity=2)
