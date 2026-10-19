#!/usr/bin/env python3
"""Static architecture check for Mind Bastion's modular Godot source tree.

This check deliberately needs only Python 3; it does not replace a Godot runtime test.
Run from the project root: python tools/verify_structure.py
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAIN_PATH = ROOT / "main.gd"
main = MAIN_PATH.read_text(encoding="utf-8")
errors: list[str] = []

# The shipped app currently has 12 independent rule modules; Othello 8x8 and 12x12 share one engine.
expected_modules = {
    "othello", "pentago", "quoridor", "domino", "chess", "pasoor",
    "mastermind", "gobblet", "hokm", "backgammon", "abalone", "blockace",
}
module_paths = re.findall(r'"([a-z]+)": preload\("res://games/([a-z]+)/rules\.gd"\)', main)
preloaded = {key for key, folder in module_paths if key == folder}
if preloaded != expected_modules:
    errors.append(f"module preload mismatch: expected {sorted(expected_modules)}, found {sorted(preloaded)}")

# Validate each game package and every method wrapper.
main_funcs = set(re.findall(r"^func\s+(\w+)\(", main, re.M))
module_method_count = 0
state_count = 0
for game_id in sorted(expected_modules):
    folder = ROOT / "games" / game_id
    rules_path = folder / "rules.gd"
    metadata_path = folder / "game.json"
    readme_path = folder / "README.md"
    for path in (rules_path, metadata_path, readme_path):
        if not path.is_file():
            errors.append(f"missing package file: {path.relative_to(ROOT)}")
    if not rules_path.is_file() or not metadata_path.is_file():
        continue
    rules = rules_path.read_text(encoding="utf-8")
    if not rules.startswith('extends "res://core/game_module.gd"'):
        errors.append(f"{game_id}: rules.gd must implement the shared GameModule base")
    try:
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        if metadata.get("id") != game_id:
            errors.append(f"{game_id}: game.json id does not match the folder")
    except json.JSONDecodeError as exc:
        errors.append(f"{game_id}: invalid game.json: {exc}")
    funcs = set(re.findall(r"^func\s+(\w+)\(", rules, re.M))
    moved = {name for name in funcs if name.startswith("_")}
    module_method_count += len(moved)
    missing_wrappers = sorted(moved - main_funcs)
    if missing_wrappers:
        errors.append(f"{game_id}: missing main compatibility wrappers for {missing_wrappers}")
    state_vars = set(re.findall(r"^var\s+(\w+)(?::[^\n]+)?$", rules, re.M))
    # Every module-owned state field is exposed as a property to legacy UI code.
    state_proxies = set(re.findall(r"^var\s+(\w+)(?::[^\n]+)?:\s*$", main, re.M))
    missing_proxies = sorted(state_vars - state_proxies)
    if missing_proxies:
        errors.append(f"{game_id}: state fields without compatibility properties: {missing_proxies}")
    state_count += len(state_vars)

# Verify standalone service separation and backwards-compatible persistence.
for required in (
    "services/scoring_service.gd", "services/ranking_service.gd",
    "core/game_catalog.gd", "core/game_module.gd",
):
    if not (ROOT / required).is_file():
        errors.append(f"missing core/service file: {required}")
scoring = (ROOT / "services/scoring_service.gd").read_text(encoding="utf-8")
ranking = (ROOT / "services/ranking_service.gd").read_text(encoding="utf-8")
catalog = (ROOT / "core/game_catalog.gd").read_text(encoding="utf-8")
for method in ("record_match_result", "points_in_period", "total_wins_losses", "load_scores", "save_scores"):
    if not re.search(rf"^func\s+{method}\(", scoring, re.M):
        errors.append(f"ScoringService is missing {method}()")
for method in ("build_game_rows", "tier_info"):
    if not re.search(rf"^static func\s+{method}\(", ranking, re.M):
        errors.append(f"RankingService is missing {method}()")
if 'user://mind_bastion_scores.cfg' not in scoring:
    errors.append("ScoringService no longer uses the legacy save path")
if not re.search(r"static func all_games\(\) -> Array", catalog):
    errors.append("GameCatalog does not expose all_games()")

catalog_ids = re.findall(r'\{"id":\s*"([a-z0-9]+)"', catalog)
if len(catalog_ids) != 13 or len(set(catalog_ids)) != 13:
    errors.append(f"catalog should define 13 unique game IDs, got {len(catalog_ids)} entries")
if "scoring_service.record_match_result" not in main or "RankingServiceScript.build_game_rows" not in main:
    errors.append("main.gd is not delegating result recording and ranking to separate services")
if "GAMES = GameCatalogScript.all_games()" not in main:
    errors.append("main.gd does not initialize its catalogue from GameCatalog")

if errors:
    print("STRUCTURE CHECK FAILED")
    for error in errors:
        print(" -", error)
    sys.exit(1)

print("STRUCTURE CHECK PASSED")
print(f"- {len(expected_modules)} independent game rule modules")
print(f"- {module_method_count} module methods exposed through compatibility wrappers")
print(f"- {state_count} module-owned state fields checked")
print("- scoring, ranking, and game catalog services found")
print("NOTE: this is a static structural check, not a Godot runtime test.")
