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
    # Leading-underscore fields are module-private implementation/animation state;
    # only public game state must be exposed to compatibility aliases in main.gd.
    state_vars = {name for name in re.findall(r"^var\s+(\w+)(?::[^\n]+)?$", rules, re.M) if not name.startswith("_")}
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
    if game_id == "chess":
        aliased_module_members |= {
            "chess_castling_rights", "chess_en_passant", "chess_fullmove_number",
            "chess_halfmove_clock", "chess_history", "chess_last_notation",
            "chess_move_log", "chess_position_history", "chess_promotion_pending",
            "chess_terminal_reason",
        }
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
if "scoring_service.record_result" not in main:
    errors.append("main.gd is not delegating result recording to ScoringService")
ranking_screen_text = (ROOT / "ui" / "screens" / "rankings_screen.gd").read_text(encoding="utf-8") if (ROOT / "ui" / "screens" / "rankings_screen.gd").is_file() else ""
if "RankingServiceScript.build_game_rows" not in main and "RankingServiceScript.build_game_rows" not in ranking_screen_text:
    errors.append("rankings page is not delegating row composition to RankingService")
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

# Dashboard and rankings are view modules; main.gd keeps stable dispatcher wrappers.
for screen_path, preload_line, entry_point in (
    ("ui/screens/dashboard_screen.gd", 'preload("res://ui/screens/dashboard_screen.gd")', "_dashboard_screen.render(self, _ui_screen_theme)"),
    ("ui/screens/rankings_screen.gd", 'preload("res://ui/screens/rankings_screen.gd")', "_rankings_screen.render(self, _ui_screen_theme)"),
):
    path = ROOT / screen_path
    if not path.is_file():
        errors.append(f"missing screen module: {screen_path}")
        continue
    if preload_line not in main:
        errors.append(f"main.gd does not preload {screen_path}")
    screen_source = path.read_text(encoding="utf-8")
    if "func render(host, theme: Dictionary) -> void:" not in screen_source:
        errors.append(f"{screen_path} is missing render(host, theme) entry point")
    if entry_point not in main:
        errors.append(f"main.gd does not delegate rendering to {screen_path}")

# Mode setup is a presentation module. It creates controls and renders descriptions,
# but all actual difficulty changes and game-start actions stay as callbacks in main.gd.
mode_screen_path = ROOT / "ui" / "screens" / "mode_screen.gd"
if not mode_screen_path.is_file():
    errors.append("missing screen module: ui/screens/mode_screen.gd")
else:
    mode_screen = mode_screen_path.read_text(encoding="utf-8")
    if 'preload("res://ui/screens/mode_screen.gd")' not in main or "var _mode_screen = ModeScreenScript.new()" not in main:
        errors.append("main.gd does not load/instantiate ModeScreen")
    for method in ("build_buttons", "render"):
        if not re.search(rf"^func\s+{method}\(", mode_screen, re.M):
            errors.append(f"ModeScreen is missing {method}()")
    if "_mode_screen.build_buttons(self, _ui_screen_theme)" not in main:
        errors.append("main.gd does not delegate mode buttons to ModeScreen")
    if "_mode_screen.render(self, _ui_screen_theme)" not in main:
        errors.append("main.gd does not delegate mode rendering to ModeScreen")
    if (re.search(r"host\.selected_game\s*=(?!=)", mode_screen)
            or re.search(r"host\.state\s*=(?!=)", mode_screen)
            or re.search(r"host\.vs_cpu\s*=(?!=)", mode_screen)):
        errors.append("ModeScreen must not own application or game-selection state")

# Result screen presentation is delegated, but result calculations and persistence stay in main.gd.
result_screen_path = ROOT / "ui" / "screens" / "result_screen.gd"
if not result_screen_path.is_file():
    errors.append("missing result screen module: ui/screens/result_screen.gd")
else:
    result_screen = result_screen_path.read_text(encoding="utf-8")
    if 'preload("res://ui/screens/result_screen.gd")' not in main or "var _result_screen = ResultScreenScript.new()" not in main:
        errors.append("main.gd does not load/instantiate ResultScreen")
    for method in ("build_buttons", "render", "render_popup"):
        if not re.search(rf"^func\s+{method}\(", result_screen, re.M):
            errors.append(f"ResultScreen is missing {method}()")
    for entry_point in (
        "_result_screen.build_buttons(self, _ui_screen_theme)",
        "_result_screen.render(self, _ui_screen_theme)",
        "_result_screen.render_popup(self, _ui_screen_theme)",
    ):
        if entry_point not in main:
            errors.append(f"main.gd missing result screen delegation: {entry_point}")
    if "host.scoring_service.record_result" in result_screen or "host.state =" in result_screen:
        errors.append("ResultScreen must not own scoring persistence or application state transitions")
if "func _result_info() -> Dictionary:" not in main or "scoring_service.record_result" not in main:
    errors.append("result calculation and persistence must remain in main.gd/ScoringService")

# Pause, rules/help and generic confirmation dialogs are presentation modules.
overlay_modules = (
    ("ui/screens/pause_screen.gd", 'preload("res://ui/screens/pause_screen.gd")', "_pause_screen", ("layout", "build_buttons", "render")),
    ("ui/screens/rules_screen.gd", 'preload("res://ui/screens/rules_screen.gd")', "_rules_screen", ("lines", "title", "page_count", "layout", "build_buttons", "render")),
    ("ui/components/dialog_component.gd", 'preload("res://ui/components/dialog_component.gd")', "_dialog_component", ("layout", "build_buttons", "render")),
)
for module_path, preload_line, instance_name, methods in overlay_modules:
    path = ROOT / module_path
    if not path.is_file():
        errors.append(f"missing overlay presentation module: {module_path}")
        continue
    source = path.read_text(encoding="utf-8")
    if not source.startswith("extends RefCounted"):
        errors.append(f"{module_path} should extend RefCounted")
    if preload_line not in main or f"var {instance_name} =" not in main:
        errors.append(f"main.gd does not load/instantiate {module_path}")
    for method in methods:
        if not re.search(rf"^func\s+{method}\(", source, re.M):
            errors.append(f"{module_path} is missing {method}()")
    if "host.dialog =" in source or "host.pause_open =" in source or "host.rules_open =" in source:
        errors.append(f"{module_path} must not own overlay open/close state")

# The controller's old entry points remain stable but delegate presentation work.
for entry_point in (
    "return _pause_screen.layout(self, _ui_screen_theme)",
    "_pause_screen.build_buttons(self, _ui_screen_theme)",
    "_pause_screen.render(self, _ui_screen_theme)",
    "return _rules_screen.lines(self)",
    "_rules_screen.build_buttons(self, _ui_screen_theme)",
    "_rules_screen.render(self, _ui_screen_theme)",
    "return _dialog_component.layout(self, _ui_screen_theme)",
    "_dialog_component.build_buttons(self, _ui_screen_theme)",
    "_dialog_component.render(self, _ui_screen_theme)",
):
    if entry_point not in main:
        errors.append(f"main.gd missing overlay delegation: {entry_point}")

# Stateful operations intentionally remain on the controller, not view presenters.
for entry_point in (
    "func _show_confirm(", "func _dialog_confirm()", "func _close_pause()",
    "func _close_rules()", "func _rules_prev_page()", "func _rules_next_page()",
):
    if entry_point not in main:
        errors.append(f"main.gd missing overlay state/action entry point: {entry_point}")


# Online and LAN lobby are presentation modules. Transport, matchmaking and state changes stay in main.gd.
online_screen_path = ROOT / "ui" / "screens" / "online_screen.gd"
if not online_screen_path.is_file():
    errors.append("missing screen module: ui/screens/online_screen.gd")
else:
    online_screen = online_screen_path.read_text(encoding="utf-8")
    if 'preload("res://ui/screens/online_screen.gd")' not in main or "var _online_screen = OnlineScreenScript.new()" not in main:
        errors.append("main.gd does not load/instantiate OnlineScreen")
    for method in ("online_extra", "build_online_buttons", "render_online", "build_lobby_buttons", "render_lobby"):
        if not re.search(rf"^func\s+{method}\(", online_screen, re.M):
            errors.append(f"OnlineScreen is missing {method}()")
    for entry_point in (
        "return _online_screen.online_extra(self)",
        "_online_screen.build_online_buttons(self, _ui_screen_theme)",
        "_online_screen.render_online(self, _ui_screen_theme)",
        "_online_screen.build_lobby_buttons(self, _ui_screen_theme)",
        "_online_screen.render_lobby(self, _ui_screen_theme)",
    ):
        if entry_point not in main:
            errors.append(f"main.gd missing online screen delegation: {entry_point}")
    if "host.state =" in online_screen or "host.online_searching =" in online_screen or "host.ws_match_active =" in online_screen:
        errors.append("OnlineScreen must not own matchmaking or application state transitions")
    if "WebSocketPeer.new()" in online_screen or "host._ws_send_json(" in online_screen or "host._quick_match_search()" in online_screen:
        # Buttons may expose existing callbacks; they must not perform transport directly.
        if "WebSocketPeer.new()" in online_screen or "host._ws_send_json(" in online_screen:
            errors.append("OnlineScreen must not own or manipulate the WebSocket transport")


# Main game catalog/menu is a presentation module; filter and selection state remain in main.gd.
menu_screen_path = ROOT / "ui" / "screens" / "menu_screen.gd"
if not menu_screen_path.is_file():
    errors.append("missing screen module: ui/screens/menu_screen.gd")
else:
    menu_screen = menu_screen_path.read_text(encoding="utf-8")
    if 'preload("res://ui/screens/menu_screen.gd")' not in main or "var _menu_screen = MenuScreenScript.new()" not in main:
        errors.append("main.gd does not load/instantiate MenuScreen")
    for method in ("filtered_games", "tile_rect", "build_buttons", "render", "render_game_tile"):
        if not re.search(rf"^func\s+{method}\(", menu_screen, re.M):
            errors.append(f"MenuScreen is missing {method}()")
    for entry_point in (
        "return _menu_screen.filtered_games(self)",
        "return _menu_screen.tile_rect(self, i)",
        "_menu_screen.build_buttons(self, _ui_screen_theme)",
        "_menu_screen.render(self, _ui_screen_theme)",
        "_menu_screen.render_game_tile(self, g, r, pressed, _ui_screen_theme)",
    ):
        if entry_point not in main:
            errors.append(f"main.gd missing menu screen delegation: {entry_point}")
    if (re.search(r"host\.menu_filter\s*=(?!=)", menu_screen)
            or re.search(r"host\.selected_game\s*=(?!=)", menu_screen)
            or re.search(r"host\.state\s*=(?!=)", menu_screen)):
        errors.append("MenuScreen must not own filter, game-selection or application state")



# Chess is the second presentation pilot; chess rules and move/RPC decisions stay authoritative in rules.gd.
chess_rules_path = ROOT / "games" / "chess" / "rules.gd"
chess_presentation_path = ROOT / "games" / "chess" / "presentation.gd"
if not chess_presentation_path.is_file():
    errors.append("missing Chess presentation module: games/chess/presentation.gd")
else:
    chess_rules = chess_rules_path.read_text(encoding="utf-8")
    chess_presentation = chess_presentation_path.read_text(encoding="utf-8")
    if 'preload("res://games/chess/presentation.gd")' not in chess_rules:
        errors.append("Chess rules module does not preload its presentation module")
    if "var _presentation = ChessPresentationScript.new()" not in chess_rules:
        errors.append("Chess rules module does not instantiate ChessPresentation")
    for method in ("is_flipped", "orient_cell", "cell_center", "screen_to_board_cell", "render"):
        if not re.search(rf"^func\s+{method}\(", chess_presentation, re.M):
            errors.append(f"ChessPresentation is missing {method}()")
    for wrapper in (
        "return _presentation.is_flipped(app)",
        "return _presentation.orient_cell(app, c)",
        "return _presentation.cell_center(app, c)",
        "var c: Vector2i = _presentation.screen_to_board_cell(app, p)",
        "_presentation.render(app, self)",
    ):
        if wrapper not in chess_rules:
            errors.append(f"Chess compatibility wrapper missing: {wrapper}")
    if 'app._send_game_action("_rpc_chess_move"' not in chess_rules or "func _chess_make_move(" not in chess_rules:
        errors.append("Chess move/RPC authority must remain in the rules module")
    if re.search(r"^\s*game\.(?:chess_difficulty|chess_board|chess_turn|chess_selected|chess_valid|chess_game_over|chess_winner|chess_last)\s*=(?!=)", chess_presentation, re.M):
        errors.append("Chess presentation must not mutate authoritative game state")
    if "app._draw_chess_piece(" not in chess_presentation or "app._draw_hud(" not in chess_presentation:
        errors.append("Chess presentation is missing expected drawing delegation")

# Chess legality, complete move history, Undo and AI search are verified alongside the presentation adapter.
chess_rules_path = ROOT / "games" / "chess" / "rules.gd"
chess_ai_path = ROOT / "games" / "chess" / "ai.gd"
if chess_rules_path.is_file():
    chess_rules = chess_rules_path.read_text(encoding="utf-8")
    for method in (
        "_chess_is_square_attacked", "_chess_move_keeps_king_safe",
        "_chess_castle_transit_safe", "_chess_update_terminal_state",
        "_chess_position_key", "_chess_undo", "_chess_can_undo",
        "_chess_choose_promotion", "_chess_can_claim_draw",
    ):
        if not re.search(rf"^func\s+{method}\(", chess_rules, re.M):
            errors.append(f"ChessRules is missing {method}()")
    if "for promotion_type in [5, 4, 3, 2]:" not in chess_rules:
        errors.append("Chess AI must receive separate underpromotion candidates")
    if "var promotion_type: int = int(best[2]) if best.size() >= 3 else 5" not in chess_rules:
        errors.append("Chess CPU move must preserve the AI's underpromotion choice")
    if 'app._add_btn(Rect2(32.0, 812.0, 154.0, 48.0), "برگشت حرکت"' not in chess_rules:
        errors.append("Chess undo control is not exposed")
if chess_ai_path.is_file():
    chess_ai = chess_ai_path.read_text(encoding="utf-8")
    for method in ("_search", "_quiescence", "_evaluate", "_budget_reached", "_ordered_moves"):
        if not re.search(rf"^func\s+{method}\(", chess_ai, re.M):
            errors.append(f"ChessAI is missing {method}()")
    if "func _promotion_type_from_move(move: Array) -> int:" not in chess_ai:
        errors.append("ChessAI must preserve underpromotion choices during search")
# Production Web workflows run the legal-move, terminal-state and Undo suite in real Godot.
for workflow_path in (ROOT / ".github" / "workflows" / "build-web.yml", ROOT / ".github" / "workflows" / "deploy-web.yml"):
    workflow_text = workflow_path.read_text(encoding="utf-8")
    if "Run chess rules regression tests" not in workflow_text or "res://tests/godot/test_chess_rules.gd" not in workflow_text:
        errors.append(f"{workflow_path.relative_to(ROOT)} does not run Godot chess regression tests")

# Domino display and pointer mapping are kept outside authoritative move rules.
domino_rules_path = ROOT / "games" / "domino" / "rules.gd"
domino_presentation_path = ROOT / "games" / "domino" / "presentation.gd"
if not domino_presentation_path.is_file():
    errors.append("missing Domino presentation module: games/domino/presentation.gd")
else:
    domino_rules = domino_rules_path.read_text(encoding="utf-8")
    domino_presentation = domino_presentation_path.read_text(encoding="utf-8")
    if 'preload("res://games/domino/presentation.gd")' not in domino_rules:
        errors.append("Domino rules module does not preload its presentation module")
    if "var _domino_presentation = DominoPresentationScript.new()" not in domino_rules:
        errors.append("Domino rules module does not instantiate DominoPresentation")
    for method in ("hand_rects", "handle_tap", "build_buttons", "render"):
        if not re.search(rf"^func\s+{method}\(", domino_presentation, re.M):
            errors.append(f"DominoPresentation is missing {method}()")
    for wrapper in (
        "return _domino_presentation.hand_rects(app, self)",
        "_domino_presentation.handle_tap(app, self, p)",
        "_domino_presentation.build_buttons(app, self)",
        "_domino_presentation.render(app, self)",
    ):
        if wrapper not in domino_rules:
            errors.append(f"Domino compatibility wrapper missing: {wrapper}")
    if "app._draw_dom_tile(" in domino_rules or "app._draw_hud(" in domino_rules:
        errors.append("Domino drawing must be delegated to DominoPresentation")
    domino_app_calls = {name for name in re.findall(r"\bapp\.(\w+)\s*\(", domino_presentation) if name.startswith("_")}
    missing_domino_app_calls = sorted(domino_app_calls - main_funcs)
    if missing_domino_app_calls:
        errors.append(f"Domino presentation calls missing app methods: {missing_domino_app_calls}")
    if "game._dom_select(index)" not in domino_presentation:
        errors.append("Domino pointer mapping must delegate selection to authoritative rules")
    if re.search(r"^\s*game\.(?:dom_hands|dom_boneyard|dom_chain|dom_left|dom_right|dom_turn|dom_game_over|dom_winner|dom_selected|dom_scores)\s*=(?!=)", domino_presentation, re.M):
        errors.append("Domino presentation must not mutate authoritative game state")

# Othello is the first pilot for separating game presentation/input from authoritative rules.
othello_rules_path = ROOT / "games" / "othello" / "rules.gd"
othello_presentation_path = ROOT / "games" / "othello" / "presentation.gd"
if not othello_presentation_path.is_file():
    errors.append("missing Othello presentation module: games/othello/presentation.gd")
else:
    othello_rules = othello_rules_path.read_text(encoding="utf-8")
    othello_presentation = othello_presentation_path.read_text(encoding="utf-8")
    if 'preload("res://games/othello/presentation.gd")' not in othello_rules:
        errors.append("Othello rules module does not preload its presentation module")
    if "var _presentation = OthelloPresentationScript.new()" not in othello_rules:
        errors.append("Othello rules module does not instantiate OthelloPresentation")
    for method in ("cell_size", "board_origin", "is_my_turn", "handle_tap", "render"):
        if not re.search(rf"^func\s+{method}\(", othello_presentation, re.M):
            errors.append(f"OthelloPresentation is missing {method}()")
    for wrapper in (
        "return _presentation.cell_size(self)",
        "return _presentation.board_origin(app, self)",
        "return _presentation.is_my_turn(app, self)",
        "_presentation.handle_tap(app, self, p)",
        "_presentation.render(app, self)",
    ):
        if wrapper not in othello_rules:
            errors.append(f"Othello compatibility wrapper missing: {wrapper}")
    if "game._othello_place(Vector2i(gx, gy))" not in othello_presentation:
        errors.append("Othello presentation input is not delegated to authoritative rules")
    if re.search(r"^\s*game\.(?:oth_size|othello_board|othello_turn|othello_scores|othello_valid|othello_game_over|othello_last_move)\s*=", othello_presentation, re.M):
        errors.append("Othello presentation must not mutate authoritative game state")
    if "app._panel(" not in othello_presentation or "app._draw_hud(" not in othello_presentation:
        errors.append("Othello presentation is missing expected drawing delegation")

# UNO drawing/buttons are presentation-only; rule actions and state transitions stay in UnoRules.
uno_rules_path = ROOT / "games" / "uno" / "rules.gd"
uno_presentation_path = ROOT / "games" / "uno" / "presentation.gd"
if not uno_presentation_path.is_file():
    errors.append("missing UNO presentation module: games/uno/presentation.gd")
else:
    uno_rules = uno_rules_path.read_text(encoding="utf-8")
    uno_presentation = uno_presentation_path.read_text(encoding="utf-8")
    if 'preload("res://games/uno/presentation.gd")' not in uno_rules:
        errors.append("UNO rules module does not preload its presentation module")
    if "var _uno_presentation = UnoPresentationScript.new()" not in uno_rules:
        errors.append("UNO rules module does not instantiate UnoPresentation")
    for method in ("handle_tap", "build_buttons", "draw_card_visual", "render"):
        if not re.search(rf"^func\s+{method}\(", uno_presentation, re.M):
            errors.append(f"UnoPresentation is missing {method}()")
    for wrapper in (
        "_uno_presentation.build_buttons(app, self)",
        "_uno_presentation.handle_tap(app, self, p)",
        "_uno_presentation.draw_card_visual(app, self, r, card, selected, small)",
        "_uno_presentation.render(app, self)",
    ):
        if wrapper not in uno_rules:
            errors.append(f"UNO compatibility wrapper missing: {wrapper}")
    if any(token in uno_rules for token in ("app._draw_hud(", "app._panel(", "app._txt_c(", "app._add_btn(")):
        errors.append("UNO drawing/button construction must be delegated to UnoPresentation")
    if "game._uno_select_card.bind(index)" not in uno_presentation or "game._uno_submit_play(" not in uno_presentation:
        errors.append("UNO presentation must bind buttons to existing authoritative action methods")
    uno_app_calls = {name for name in re.findall(r"\bapp\.(\w+)\s*\(", uno_presentation) if name.startswith("_")}
    missing_uno_app_calls = sorted(uno_app_calls - main_funcs)
    if missing_uno_app_calls:
        errors.append(f"UNO presentation calls missing app methods: {missing_uno_app_calls}")
    forbidden_uno_state = (
        "uno_hands", "uno_draw_pile", "uno_discard_pile", "uno_scores", "uno_turn",
        "uno_direction", "uno_current_color", "uno_game_over", "uno_round_over",
        "uno_winner", "uno_round_winner", "uno_challenge_available", "uno_challenge_target",
        "uno_last_wild4_actor", "uno_last_wild4_illegal", "uno_pending_round_winner",
        "uno_catch_seat", "uno_drawn_card_index",
    )
    forbidden_pattern = r"^\s*game\.(?:" + "|".join(forbidden_uno_state) + r")\s*=(?!=)"
    if re.search(forbidden_pattern, uno_presentation, re.M):
        errors.append("UNO presentation must not mutate authoritative round state")
    if "if game.uno_drawn_card_index < 0:" not in uno_presentation:
        errors.append("UNO UI must not expose a second draw after a playable card was drawn")
if "func _uno_is_wild4_legal(seat: int, card_index: int = -1) -> bool:" not in uno_rules_path.read_text(encoding="utf-8"):
    errors.append("UNO Wild Draw Four legality/challenge check is missing")
if "or uno_drawn_card_index >= 0" not in uno_rules_path.read_text(encoding="utf-8"):
    errors.append("UNO rules must reject a second draw in the same turn")
for workflow_path in (ROOT / ".github" / "workflows" / "build-web.yml", ROOT / ".github" / "workflows" / "deploy-web.yml"):
    workflow_text = workflow_path.read_text(encoding="utf-8")
    if "Run UNO rules regression tests" not in workflow_text or "res://tests/godot/test_uno_rules.gd" not in workflow_text:
        errors.append(f"{workflow_path.relative_to(ROOT)} does not run UNO rules regression tests")

# Mastermind is a presentation module while state, the secret and race transitions remain in rules.gd.
mastermind_rules_path = ROOT / "games" / "mastermind" / "rules.gd"
mastermind_presentation_path = ROOT / "games" / "mastermind" / "presentation.gd"
if not mastermind_presentation_path.is_file():
    errors.append("missing Mastermind presentation module: games/mastermind/presentation.gd")
else:
    mastermind_rules = mastermind_rules_path.read_text(encoding="utf-8")
    mastermind_presentation = mastermind_presentation_path.read_text(encoding="utf-8")
    if 'preload("res://games/mastermind/presentation.gd")' not in mastermind_rules:
        errors.append("Mastermind rules module does not preload its presentation module")
    if "var _mm_presentation = MastermindPresentationScript.new()" not in mastermind_rules:
        errors.append("Mastermind rules module does not instantiate its presenter")
    for method in ("slot_pos", "color_pos", "build_buttons", "render", "render_online_sidebar"):
        if not re.search(rf"^func\s+{method}\(", mastermind_presentation, re.M):
            errors.append(f"MastermindPresentation is missing {method}()")
    for wrapper in (
        "return _mm_presentation.slot_pos(app, self, i)",
        "return _mm_presentation.color_pos(app, self, i)",
        "_mm_presentation.build_buttons(app, self)",
        "_mm_presentation.render(app, self)",
        "_mm_presentation.render_online_sidebar(app, self)",
    ):
        if wrapper not in mastermind_rules:
            errors.append(f"Mastermind compatibility wrapper missing: {wrapper}")
    if "game.mm_secret" in mastermind_presentation:
        errors.append("Mastermind presentation must not read the hidden secret")
    if re.search(r"^\s*game\.mm_[A-Za-z0-9_]+\s*=(?!=)", mastermind_presentation, re.M):
        errors.append("Mastermind presentation must not mutate game state")
    for callback in ("game._mm_pick_slot.bind", "game._mm_pick.bind", "game._mm_clear", "game._mm_submit"):
        if callback not in mastermind_presentation:
            errors.append(f"Mastermind presentation is missing authoritative callback {callback}")
    for method in ("_mm_apply", "_mm_feedback", "_mm_submit", "_mm_accept_race_feedback"):
        if not re.search(rf"^func\s+{method}\(", mastermind_rules, re.M):
            errors.append(f"Mastermind rules module lost authoritative method {method}()")
    for workflow_path in (ROOT / ".github" / "workflows" / "build-web.yml", ROOT / ".github" / "workflows" / "deploy-web.yml"):
        workflow_text = workflow_path.read_text(encoding="utf-8")
        if "Run Mastermind rules regression tests" not in workflow_text or "res://tests/godot/test_mastermind_rules.gd" not in workflow_text:
            errors.append(f"{workflow_path.relative_to(ROOT)} does not run Mastermind regression tests")


# Blockace board drawing, piece-tray buttons and pointer mapping are presentation-only;
# placement rules, CPU decisions and online application remain in rules.gd.
blockace_rules_path = ROOT / "games" / "blockace" / "rules.gd"
blockace_presentation_path = ROOT / "games" / "blockace" / "presentation.gd"
if not blockace_presentation_path.is_file():
    errors.append("missing Blockace presentation module: games/blockace/presentation.gd")
else:
    blockace_rules = blockace_rules_path.read_text(encoding="utf-8")
    blockace_presentation = blockace_presentation_path.read_text(encoding="utf-8")
    if 'preload("res://games/blockace/presentation.gd")' not in blockace_rules:
        errors.append("Blockace rules module does not preload its presentation module")
    if "var _blockace_presentation = BlockacePresentationScript.new()" not in blockace_rules:
        errors.append("Blockace rules module does not instantiate its presenter")
    for method in ("handle_tap", "build_buttons", "draw_cell", "render"):
        if not re.search(rf"^func\s+{method}\(", blockace_presentation, re.M):
            errors.append(f"BlockacePresentation is missing {method}()")
    for wrapper in (
        "_blockace_presentation.handle_tap(app, self, p)",
        "_blockace_presentation.build_buttons(app, self)",
        "_blockace_presentation.draw_cell(app, r, col)",
        "_blockace_presentation.render(app, self)",
    ):
        if wrapper not in blockace_rules:
            errors.append(f"Blockace compatibility wrapper missing: {wrapper}")
    if "game._blk_handle_target(Vector2i(gx, gy))" not in blockace_presentation:
        errors.append("Blockace pointer mapping must delegate the selected cell to rules.gd")
    if re.search(r"^\s*game\.blk_[A-Za-z0-9_]+\s*=(?!=)", blockace_presentation, re.M):
        errors.append("Blockace presentation must not mutate authoritative game state")
    for method in ("_blk_can_place", "_blk_place", "_blk_cpu", "_blk_apply_net"):
        if not re.search(rf"^func\s+{method}\(", blockace_rules, re.M):
            errors.append(f"Blockace rules module lost authoritative method {method}()")
    blockace_app_calls = {name for name in re.findall(r"\bapp\.(\w+)\s*\(", blockace_presentation) if name.startswith("_")}
    missing_blockace_app_calls = sorted(blockace_app_calls - main_funcs)
    if missing_blockace_app_calls:
        errors.append(f"Blockace presentation calls missing app methods: {missing_blockace_app_calls}")


# Pentago presentation separates drawing/layout and pointer mapping from authoritative rules.
pentago_rules_path = ROOT / "games" / "pentago" / "rules.gd"
pentago_presentation_path = ROOT / "games" / "pentago" / "presentation.gd"
if not pentago_presentation_path.is_file():
    errors.append("missing Pentago presentation module: games/pentago/presentation.gd")
else:
    pentago_rules = pentago_rules_path.read_text(encoding="utf-8")
    pentago_presentation = pentago_presentation_path.read_text(encoding="utf-8")
    if 'preload("res://games/pentago/presentation.gd")' not in pentago_rules:
        errors.append("Pentago rules module does not preload its presentation module")
    if "var _pent_presentation = PentagoPresentationScript.new()" not in pentago_rules:
        errors.append("Pentago rules module does not instantiate its presenter")
    for method in ("board_origin", "cell_pos", "quad_rect", "handle_tap", "build_buttons", "render"):
        if not re.search(rf"^func\s+{method}\(", pentago_presentation, re.M):
            errors.append(f"PentagoPresentation is missing {method}()")
    for wrapper in (
        "return _pent_presentation.board_origin(app)",
        "return _pent_presentation.cell_pos(app, x, y)",
        "_pent_presentation.handle_tap(app, self, p)",
        "return _pent_presentation.quad_rect(app, q)",
        "_pent_presentation.build_buttons(app, self)",
        "_pent_presentation.render(app, self)",
    ):
        if wrapper not in pentago_rules:
            errors.append(f"Pentago compatibility wrapper missing: {wrapper}")
    if "game._pent_handle_cell_tap(Vector2i(x, y))" not in pentago_presentation:
        errors.append("Pentago pointer mapping must delegate the cell to the rules module")
    if re.search(r"^\s*game\.pent_[A-Za-z0-9_]+\s*=(?!=)", pentago_presentation, re.M):
        errors.append("Pentago presentation must not mutate authoritative game state")
    for method in ("_pent_check_win", "_pent_rotate", "_pent_place", "_pent_do_rotate", "_pent_cpu_move", "_pent_choose_cpu_plan", "_pent_evaluate_board"):
        if not re.search(rf"^func\s+{method}\(", pentago_rules, re.M):
            errors.append(f"Pentago rules module lost authoritative method {method}()")
    pentago_app_calls = {name for name in re.findall(r"\bapp\.(\w+)\s*\(", pentago_presentation) if name.startswith("_")}
    missing_pentago_app_calls = sorted(pentago_app_calls - main_funcs)
    if missing_pentago_app_calls:
        errors.append(f"Pentago presentation calls missing app methods: {missing_pentago_app_calls}")
    for workflow_path in (ROOT / ".github" / "workflows" / "build-web.yml", ROOT / ".github" / "workflows" / "deploy-web.yml"):
        workflow_text = workflow_path.read_text(encoding="utf-8")
        if "Run Pentago rules regression tests" not in workflow_text or "res://tests/godot/test_pentago_rules.gd" not in workflow_text:
            errors.append(f"{workflow_path.relative_to(ROOT)} does not run Pentago regression tests")

# Presentation adapters for the remaining rules modules are read-only views.
remaining_presentations = {
    "quoridor": {
        "instance": "_quo_presentation",
        "class": "QuoridorPresentationScript",
        "state_prefix": "quo_",
        "methods": ("edge_at", "build_buttons", "player_color", "draw_four_player_hud", "render"),
        "critical": ("_quo_legal_moves", "_quo_wall_placement_legal", "_quo_place_wall", "_quo_advance_turn"),
    },
    "gobblet": {
        "instance": "_gob_presentation",
        "class": "GobbletPresentationScript",
        "state_prefix": "gob_",
        "methods": ("hand_rect", "handle_tap", "build_buttons", "render"),
        "critical": ("_gob_can_place", "_gob_can_move", "_gob_place", "_gob_move", "_gob_cpu"),
    },
    "pasoor": {
        "instance": "_pas_presentation",
        "class": "PasoorPresentationScript",
        "state_prefix": "pas_",
        "methods": ("hand_rects", "table_rects", "handle_tap", "build_buttons", "render"),
        "critical": ("_pas_find_captures", "_pas_best_capture", "_pas_play", "_pas_cpu_move"),
    },
    "hokm": {
        "instance": "_hokm_presentation",
        "class": "HokmPresentationScript",
        "state_prefix": "hokm_",
        "methods": ("hand_rects", "handle_tap", "render"),
        "critical": ("_hokm_legal", "_hokm_play", "_hokm_cpu", "_hokm_card_beats"),
    },
    "abalone": {
        "instance": "_aba_presentation",
        "class": "AbalonePresentationScript",
        "state_prefix": "aba_",
        "methods": ("cell_center", "hit_cell", "handle_tap", "render"),
        "critical": ("_aba_valid_cell", "_aba_moves_for_selection", "_aba_apply_group_move", "_aba_generate_all_moves"),
    },
    "quarto": {
        "instance": "_qto_presentation",
        "class": "QuartoPresentationScript",
        "state_prefix": "qto_",
        "methods": ("board_origin", "piece_rect", "handle_tap", "build_buttons", "render"),
        "critical": ("_qto_has_quarto", "_qto_choose_piece", "_qto_place", "_qto_cpu_step"),
    },
}
for game_id, spec in remaining_presentations.items():
    rules_path = ROOT / "games" / game_id / "rules.gd"
    presentation_path = ROOT / "games" / game_id / "presentation.gd"
    if not presentation_path.is_file():
        errors.append(f"missing {game_id.title()} presentation module: games/{game_id}/presentation.gd")
        continue
    rules = rules_path.read_text(encoding="utf-8")
    presentation = presentation_path.read_text(encoding="utf-8")
    if f'preload("res://games/{game_id}/presentation.gd")' not in rules:
        errors.append(f"{game_id.title()} rules module does not preload its presentation module")
    if f"var {spec['instance']} = {spec['class']}.new()" not in rules:
        errors.append(f"{game_id.title()} rules module does not instantiate its presenter")
    for method in spec["methods"]:
        if not re.search(rf"^func\s+{method}\(", presentation, re.M):
            errors.append(f"{game_id.title()} presentation is missing {method}()")
    for method in spec["critical"]:
        if not re.search(rf"^func\s+{method}\(", rules, re.M):
            errors.append(f"{game_id.title()} rules module lost authoritative {method}()")
    if re.search(rf"^\s*game\.{spec['state_prefix']}[A-Za-z0-9_]*\s*=(?!=)", presentation, re.M):
        errors.append(f"{game_id.title()} presentation must not mutate authoritative game state")
    app_calls = {name for name in re.findall(r"\bapp\.(\w+)\s*\(", presentation) if name.startswith("_")}
    missing_calls = sorted(app_calls - main_funcs)
    if missing_calls:
        errors.append(f"{game_id.title()} presentation calls missing app methods: {missing_calls}")

# Quarto main entry points remain wrappers, and CI runs its rule regression suite.
quarto_rules = (ROOT / "games" / "quarto" / "rules.gd").read_text(encoding="utf-8")
quarto_presentation = (ROOT / "games" / "quarto" / "presentation.gd").read_text(encoding="utf-8")
if "_qto_presentation.render(app, self)" not in quarto_rules:
    errors.append("Quarto render entry point does not delegate to the presentation module")
if 'return _game_modules["quarto"]._qto_piece_rect(piece)' not in (ROOT / "main.gd").read_text(encoding="utf-8"):
    errors.append("Quarto piece layout entry point is not a compatibility wrapper")
if "game._qto_handle_board_tap(cell)" not in quarto_presentation:
    errors.append("Quarto pointer mapping must delegate to authoritative rules")
for workflow_path in (ROOT / ".github" / "workflows" / "build-web.yml", ROOT / ".github" / "workflows" / "deploy-web.yml"):
    workflow_text = workflow_path.read_text(encoding="utf-8")
    if "Run Quarto rules regression tests" not in workflow_text or "res://tests/godot/test_quarto_rules.gd" not in workflow_text:
        errors.append(f"{workflow_path.relative_to(ROOT)} does not run Quarto rules regression tests")

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
print("- menu, dashboard, rankings, mode, online/lobby, pause, rules, dialogs and result presentation delegated to UI modules")
print("- Othello, Chess, Pentago, Quoridor, Domino, Backgammon, Gobblet, Pasoor, Hokm, Abalone, Quarto and Blockace presentation/input mapping delegated to game presentation modules")
print("- UNO drawing and action-button layout delegated to its presentation module; Wild Draw Four challenges and draw/pass guards checked")
print("- Chess legality, complete Undo history and bounded AI search checked")
print("- Mastermind state/secret and online race remain in rules; Blockace placement/CPU/network rules remain authoritative; UI delegated to presentation modules")
print("NOTE: this is a static structural check, not a Godot runtime test.")
