#!/usr/bin/env python3
"""Static architecture check for Pendar's modular Godot source tree.

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

# Catch malformed GDScript blocks early. A line ending in ':' starts a block,
# so the next nonblank, noncomment line must be more deeply indented. This
# specifically prevents a parse error from making the web canvas stay blank.
def _leading_indent(line: str) -> int:
    return len(line) - len(line.lstrip("\t "))

for script_path in sorted(ROOT.rglob("*.gd")):
    script_lines = script_path.read_text(encoding="utf-8").splitlines()
    for index, line in enumerate(script_lines):
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or not stripped.endswith(":"):
            continue
        indent = _leading_indent(line)
        for next_index in range(index + 1, len(script_lines)):
            next_line = script_lines[next_index]
            next_stripped = next_line.strip()
            if not next_stripped or next_stripped.startswith("#"):
                continue
            if _leading_indent(next_line) <= indent:
                errors.append(
                    f"{script_path.relative_to(ROOT)}:{index + 1}: block body must be indented "
                    f"more than its header (next code line {next_index + 1})"
                )
            break

# Branch keywords must align with the `if`/`elif` they continue. A single outdented
# `elif` can make a preloaded module fail to parse and leave the web canvas blank.
for script_path in sorted(ROOT.rglob("*.gd")):
    script_lines = script_path.read_text(encoding="utf-8").splitlines()
    for index, line in enumerate(script_lines):
        stripped = line.lstrip("\t ")
        if not (stripped.startswith("elif ") or stripped == "else:"):
            continue
        indent = _leading_indent(line)
        previous_branch = None
        for previous_index in range(index - 1, -1, -1):
            previous_line = script_lines[previous_index]
            previous_stripped = previous_line.lstrip("\t ")
            if not previous_stripped or previous_stripped.startswith("#"):
                continue
            previous_indent = _leading_indent(previous_line)
            if previous_indent > indent:
                continue
            previous_branch = (previous_index + 1, previous_indent, previous_stripped)
            break
        if (
            previous_branch is None
            or previous_branch[1] != indent
            or not (previous_branch[2].startswith("if ") or previous_branch[2].startswith("elif "))
        ):
            errors.append(
                f"{script_path.relative_to(ROOT)}:{index + 1}: {stripped.split(':', 1)[0]} "
                "must align with its matching if/elif branch"
            )

# Game rule modules extend RefCounted, not CanvasItem. Canvas drawing commands
# must be delegated to the main Node2D (app.draw_circle, app.draw_line, etc.).
_canvas_draw_methods = (
    "draw_circle", "draw_line", "draw_rect", "draw_arc", "draw_polyline",
    "draw_polygon", "draw_colored_polygon", "draw_string", "draw_texture",
    "draw_texture_rect", "draw_texture_rect_region",
)
for script_path in sorted((ROOT / "games").rglob("rules.gd")):
    for index, line in enumerate(script_path.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.lstrip("\t ")
        if any(re.match(rf"{re.escape(method)}\s*\(", stripped) for method in _canvas_draw_methods):
            errors.append(
                f"{script_path.relative_to(ROOT)}:{index}: CanvasItem draw command must be called through app."
            )

# The shipped app has 14 independent rule modules; Othello 8x8 and 12x12 share one engine.
expected_modules = {
    "othello", "pentago", "quoridor", "domino", "chess", "pasoor",
    "mastermind", "gobblet", "hokm", "backgammon", "abalone", "blockace", "quarto", "uno",
}
module_paths = re.findall(r'"([a-z]+)": preload\("res://games/([a-z]+)/rules\.gd"\)', main)
preloaded = {key for key, folder in module_paths if key == folder}
if preloaded != expected_modules:
    errors.append(f"module preload mismatch: expected {sorted(expected_modules)}, found {sorted(preloaded)}")

# Validate each game package and the app-facing methods it calls. Internal helpers
# may live entirely inside a module; they do not need compatibility wrappers.
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
    app_calls = {name for name in re.findall(r"\bapp\.(\w+)\s*\(", rules) if name.startswith("_")}
    module_method_count += len(app_calls)
    missing_wrappers = sorted(app_calls - main_funcs)
    if missing_wrappers:
        errors.append(f"{game_id}: app-facing methods missing from main: {missing_wrappers}")
    state_vars = set(re.findall(r"^var\s+(\w+)(?::[^\n]+)?$", rules, re.M))
    # State used by legacy UI is proxied; newer code may access a module-owned
    # field explicitly through _game_modules[game_id] instead. Both are valid.
    state_proxies = set(re.findall(r"^var\s+(\w+)(?::[^\n]+)?:\s*$", main, re.M))
    direct_module_members = set(re.findall(rf'_game_modules\["{re.escape(game_id)}"\]\.(\w+)', main))
    # Mastermind's online-race marker is read through a local alias (`var mm = _game_modules["mastermind"]`)
    # so it is module-owned and does not require a legacy compatibility property in main.gd.
    aliased_module_members = {"mm_online_race", "mm_cpu_racers", "mm_cpu_race_started_msec"} if game_id == "mastermind" else set()
    if game_id == "backgammon":
        aliased_module_members |= {"bg_legal_cache_key", "bg_legal_cache"}
    if game_id == "quoridor":
        aliased_module_members |= {"quo_cpu_position_history_by_player"}
    if game_id == "uno":
        aliased_module_members |= {
            "uno_catch_seat", "uno_challenge_target", "uno_current_color", "uno_direction",
            "uno_drawn_card_index", "uno_hand_page", "uno_last_action", "uno_last_round_points",
            "uno_last_wild4_actor", "uno_last_wild4_illegal", "uno_pending_color",
            "uno_pending_round_winner", "uno_round_started_msec", "uno_round_winner",
            "uno_scores", "uno_status",
        }
    missing_proxies = sorted(state_vars - state_proxies - direct_module_members - aliased_module_members)
    if missing_proxies:
        errors.append(f"{game_id}: state fields without compatibility properties: {missing_proxies}")
    state_count += len(state_vars)

# Verify standalone service separation and backwards-compatible persistence.
for required in (
    "services/online_client.gd", "services/scoring_service.gd", "services/ranking_service.gd",
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
if 'user://pendar_scores.cfg' not in scoring or 'LEGACY_SCORE_PATH := "user://mind_bastion_scores.cfg"' not in scoring:
    errors.append("ScoringService no longer uses the legacy save path")
if not re.search(r"static func all_games\(\) -> Array", catalog):
    errors.append("GameCatalog does not expose all_games()")

catalog_ids = re.findall(r'\{"id":\s*"([a-z0-9]+)"', catalog)
if len(catalog_ids) != 15 or len(set(catalog_ids)) != 15:
    errors.append(f"catalog should define 15 unique game IDs, got {len(catalog_ids)} entries")
if "scoring_service.record_result" not in main or "RankingServiceScript.build_game_rows" not in main:
    errors.append("main.gd is not delegating result recording and ranking to separate services")
if "GAMES = GameCatalogScript.all_games()" not in main:
    errors.append("main.gd does not initialize its catalogue from GameCatalog")

# WebSocket transport is isolated from the game controller; matchmaking policy and
# game-level message handling are intentionally kept in main.gd.
online_client_path = ROOT / "services" / "online_client.gd"
if online_client_path.is_file():
    online_client = online_client_path.read_text(encoding="utf-8")
    if "ws_socket" in main or "WebSocketPeer.new()" in main:
        errors.append("main.gd should delegate the concrete WebSocketPeer to OnlineClient")
    for method in ("connect_to_url", "poll", "send_json", "receive_next_message", "close"):
        if not re.search(rf"^func\s+{method}\(", online_client, re.M):
            errors.append(f"OnlineClient is missing {method}()")
    if 'preload("res://services/online_client.gd")' not in main:
        errors.append("main.gd does not preload OnlineClient")

if errors:
    print("STRUCTURE CHECK FAILED")
    for error in errors:
        print(" -", error)
    sys.exit(1)

print("STRUCTURE CHECK PASSED")
print(f"- {len(expected_modules)} independent game rule modules")
print(f"- {module_method_count} app-facing module calls checked for compatibility")
print(f"- {state_count} module-owned state fields checked")
print("- scoring, ranking, and game catalog services found")
print("NOTE: this is a static structural check, not a Godot runtime test.")
