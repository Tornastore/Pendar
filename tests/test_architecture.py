"""Smoke test for modular source layout (requires Python, not Godot)."""
import subprocess
import sys
from pathlib import Path


def test_modular_structure_check_passes() -> None:
    project_root = Path(__file__).resolve().parents[1]
    result = subprocess.run(
        [sys.executable, str(project_root / "tools" / "verify_structure.py")],
        cwd=project_root,
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "STRUCTURE CHECK PASSED" in result.stdout


def test_quoridor_ai_has_six_difficulty_profiles_and_master_search() -> None:
    project_root = Path(__file__).resolve().parents[1]
    ai = (project_root / "games" / "quoridor" / "ai.gd").read_text(encoding="utf-8")
    rules = (project_root / "games" / "quoridor" / "rules.gd").read_text(encoding="utf-8")
    main = (project_root / "main.gd").read_text(encoding="utf-8")
    assert "func choose_action(game, difficulty: int)" in ai
    assert "if level == 1" in ai
    assert "if level == 2" in ai
    assert "if level >= 5:" in ai
    assert "func _minimax(" in ai
    assert "func _search_actions(" in ai
    assert "MASTER_SEARCH_DEPTH: int = 4" in ai
    assert "_active_search_depth = 3 if level == 5 else MASTER_SEARCH_DEPTH" in ai
    for level in ("\t\t3:", "\t\t4:", "\t\t5:"):
        assert level in ai
    assert "QuoridorAIScript = preload(\"res://games/quoridor/ai.gd\")" in rules
    assert "_set_quoridor_difficulty.bind(i + 1)" in main
    assert '"quo_difficulty_%d"' in main
    assert '"خیلی آسان", "آسان", "متوسط", "سخت", "استاد", "استادتمام"' in main
    assert "clampi(level, 1, 6)" in main


def test_quoridor_uses_two_edge_walls_and_supports_four_player_hotseat() -> None:
    project_root = Path(__file__).resolve().parents[1]
    rules = (project_root / "games" / "quoridor" / "rules.gd").read_text(encoding="utf-8")
    main = (project_root / "main.gd").read_text(encoding="utf-8")
    catalog = (project_root / "core" / "game_catalog.gd").read_text(encoding="utf-8")
    assert "quo_pawns = [Vector2i(4, 0), Vector2i(8, 4), Vector2i(4, 8), Vector2i(0, 4)]" in rules
    assert "quo_walls_left = [5, 5, 5, 5]" in rules
    assert "cell * 2 - 6" in rules
    assert 'quo_walls.has("v%d,%d" % [boundary_x, from.y - 1])' in rules
    assert 'quo_walls.has("h%d,%d" % [from.x - 1, boundary_y])' in rules
    assert "func _quo_wall_geometry_clear(" in rules
    assert "func _quo_wall_placement_legal(" in rules
    assert "func _quo_legal_moves_from(" in rules
    assert "func _quo_advance_turn(" in rules
    assert "func _quo_has_legal_wall(" in rules
    assert "var can_wall: bool = int(quo_walls_left[candidate]) > 0" in rules
    assert "func _first_legal_wall(" in (project_root / "games" / "quoridor" / "ai.gd").read_text(encoding="utf-8")
    assert "_start_quoridor_local_four_player" in main
    assert '"m_local4"' in main
    assert '"چهارنفره · شما در برابر ۳ CPU"' in main
    assert '_start_quoridor_vs_three_cpu' in main
    assert '"players": "۲ یا ۴ نفر", "max_p": 4' in catalog


def test_othello_ai_has_six_levels_and_supports_twelve_by_twelve() -> None:
    project_root = Path(__file__).resolve().parents[1]
    ai = (project_root / "games" / "othello" / "ai.gd").read_text(encoding="utf-8")
    rules = (project_root / "games" / "othello" / "rules.gd").read_text(encoding="utf-8")
    main = (project_root / "main.gd").read_text(encoding="utf-8")
    assert "func choose_move(board: Array, board_size: int, player: int, difficulty: int) -> Vector2i" in ai
    assert "var depth_by_level: Array[int] = [0, 0, 2, 3, 5, 6]" in ai
    assert "_node_limit = [0, 0, 1200, 5000, 15000, 24000][level - 1]" in ai
    assert "func _search(" in ai
    assert "func _evaluate(" in ai
    assert "func _legal_moves(" in ai
    assert "func _terminal_value(" in ai
    assert 'const OthelloAIScript = preload("res://games/othello/ai.gd")' in rules
    assert "ai.choose_move(othello_board, oth_size, othello_turn, oth_difficulty)" in rules
    assert 'elif selected_game in ["othello", "othello12"]:' in main
    assert "_set_othello_difficulty.bind(i + 1)" in main
    assert '"oth_difficulty_%d"' in main
    assert 'oth_size = 12' in main


def test_web_export_preset_and_github_workflows_are_present() -> None:
    project_root = Path(__file__).resolve().parents[1]
    presets = (project_root / "export_presets.cfg").read_text(encoding="utf-8")
    build_workflow = (project_root / ".github" / "workflows" / "build-web.yml").read_text(encoding="utf-8")
    deploy_workflow = (project_root / ".github" / "workflows" / "deploy-web.yml").read_text(encoding="utf-8")
    main = (project_root / "main.gd").read_text(encoding="utf-8")
    readme = (project_root / "README.md").read_text(encoding="utf-8")

    assert 'name="Web"' in presets
    assert 'platform="Web"' in presets
    assert 'export_path="build/web/index.html"' in presets
    assert 'progressive_web_app/enabled=true' in presets
    assert 'variant/thread_support=false' in presets
    assert 'actions/upload-artifact@v4' in build_workflow
    assert 'actions/deploy-pages@v4' in deploy_workflow
    assert 'OS.has_feature("web")' in main
    assert 'info.get("net", false) and not web_build' in main
    assert 'not web_build, ACCENT' in main
    assert 'نسخه وب از اتصال شبکه‌ای ENet پشتیبانی نمی‌کند' in main
    assert 'ENet/UDP' in readme


def test_chess_ai_has_six_difficulty_levels_and_alpha_beta_search() -> None:
    project_root = Path(__file__).resolve().parents[1]
    ai = (project_root / "games" / "chess" / "ai.gd").read_text(encoding="utf-8")
    rules = (project_root / "games" / "chess" / "rules.gd").read_text(encoding="utf-8")
    main = (project_root / "main.gd").read_text(encoding="utf-8")
    assert "func choose_move(game, difficulty: int) -> Array" in ai
    assert "var depths: Array[int] = [0, 0, 1, 2, 4, 5]" in ai
    assert "func _search(" in ai
    assert "func _evaluate(" in ai
    assert "ChessAIScript = preload(\"res://games/chess/ai.gd\")" in rules
    assert "ai.choose_move(self, chess_difficulty)" in rules
    assert 'elif selected_game == "chess":' in main
    assert "_set_chess_difficulty.bind(i + 1)" in main
    assert '"chess_difficulty_%d"' in main


def test_backgammon_ai_has_six_levels_and_turn_sequence_search() -> None:
    project_root = Path(__file__).resolve().parents[1]
    ai = (project_root / "games" / "backgammon" / "ai.gd").read_text(encoding="utf-8")
    rules = (project_root / "games" / "backgammon" / "rules.gd").read_text(encoding="utf-8")
    main = (project_root / "main.gd").read_text(encoding="utf-8")
    assert "func choose_turn(game, difficulty: int) -> Array" in ai
    assert "func _search_plan(" in ai
    assert "func _evaluate(game, level: int) -> float" in ai
    assert "func _cpu_can_hit(" in ai and "func _human_can_hit(" in ai
    assert "BackgammonAIScript = preload(\"res://games/backgammon/ai.gd\")" in rules
    assert "ai.choose_turn(self, bg_difficulty)" in rules
    assert 'elif selected_game == "backgammon":' in main
    assert "_set_backgammon_difficulty.bind(i + 1)" in main
    assert '"backgammon_difficulty_%d"' in main


def test_pentago_and_domino_difficulty_selectors_reach_their_ai_and_hud() -> None:
    project_root = Path(__file__).resolve().parents[1]
    main = (project_root / "main.gd").read_text(encoding="utf-8")
    pentago = (project_root / "games" / "pentago" / "rules.gd").read_text(encoding="utf-8")
    domino = (project_root / "games" / "domino" / "rules.gd").read_text(encoding="utf-8")

    # Both games must expose all six choices and update the module-owned value.
    assert '"pentago_difficulty_%d"' in main
    assert '"domino_difficulty_%d"' in main
    assert "_set_pentago_difficulty.bind(i + 1)" in main
    assert "_set_domino_difficulty.bind(i + 1)" in main
    assert '_game_modules["pentago"].pent_difficulty = clampi(level, 1, 6)' in main
    assert '_game_modules["domino"].dom_difficulty = clampi(level, 1, 6)' in main
    assert '"pentago", "domino"' in main and "سطح هوش کامپیوتر را انتخاب کنید" in main

    # The selected level must influence decision-making, not just the menu.
    assert "if pent_difficulty >= 2" in pentago
    assert "_pent_evaluate_board(2, pent_difficulty)" in pentago
    assert "if pent_difficulty >= 5" in pentago
    assert "match dom_difficulty:" in domino
    for level in ("2:", "3:", "4:", "5:", "6:"):
        assert f"		{level}" in domino
    assert "if dom_difficulty <= 1" in domino

    # In-game labels make the effective selected profile visible to the player.
    assert "func _draw_ai_difficulty_chip(level: int) -> void:" in main
    assert "app._draw_ai_difficulty_chip(pent_difficulty)" in pentago
    assert "app._draw_ai_difficulty_chip(dom_difficulty)" in domino


def test_pasoor_and_hokm_difficulty_profiles_reach_ai_and_hud() -> None:
    project_root = Path(__file__).resolve().parents[1]
    main = (project_root / "main.gd").read_text(encoding="utf-8")
    pasoor = (project_root / "games" / "pasoor" / "rules.gd").read_text(encoding="utf-8")
    hokm = (project_root / "games" / "hokm" / "rules.gd").read_text(encoding="utf-8")

    for game_id, setter, profile_var in (("pasoor", "_set_pasoor_difficulty", "pas_difficulty"),
                                         ("hokm", "_set_hokm_difficulty", "hokm_difficulty")):
        assert f'elif selected_game == "{game_id}":' in main
        assert f'"{game_id}_difficulty_%d"' in main
        assert f"{setter}.bind(i + 1)" in main
        assert f'_game_modules["{game_id}"].{profile_var} = clampi(level, 1, 6)' in main
        assert f"app._draw_ai_difficulty_chip({profile_var})" in (pasoor if game_id == "pasoor" else hokm)

    # Four Cards evaluates captures, card points, sweeps, and exposed table risk.
    assert "func _pas_exposure_cost(card: Dictionary) -> float:" in pasoor
    assert "func _pas_cpu_move() -> void:" in pasoor
    assert "if level <= 1:" in pasoor
    assert "_pas_exposure_cost(card)" in pasoor
    assert "pas_difficulty" in pasoor

    # Hokm uses six decision profiles and records public void/trick information.
    assert "func _hokm_lead_score(card: Dictionary, level: int) -> float:" in hokm
    assert "func _hokm_response_score(card: Dictionary, led_card: Dictionary, level: int) -> float:" in hokm
    assert "if level <= 1:" in hokm
    assert "hokm_voids[p].append(int(led_card.s))" in hokm
    assert "hokm_seen_cards.append(card.duplicate())" in hokm
    assert "hokm_difficulty" in hokm


def test_gobblet_has_four_piece_sizes_in_rules_and_ui() -> None:
    project_root = Path(__file__).resolve().parents[1]
    gobblet = (project_root / "games" / "gobblet" / "rules.gd").read_text(encoding="utf-8")
    main = (project_root / "main.gd").read_text(encoding="utf-8")

    assert "var gob_hand: Array = [[3, 3, 3, 3], [3, 3, 3, 3]]" in gobblet
    assert "gob_hand = [[3, 3, 3, 3], [3, 3, 3, 3]]" in gobblet
    assert "for size in [4, 3, 2, 1]:" in gobblet
    assert "func _gob_hand_rect(index: int) -> Rect2:" in gobblet
    assert gobblet.count("for s in range(4):") >= 3
    assert '["کوچک", "متوسط", "بزرگ", "خیلی بزرگ"]' in gobblet
    assert "size < 1 or size > 4" in gobblet
    assert "خیلی بزرگ" in gobblet



def test_gobblet_supports_board_moves_and_reveal_loss_rule() -> None:
    project_root = Path(__file__).resolve().parents[1]
    gobblet = (project_root / "games" / "gobblet" / "rules.gd").read_text(encoding="utf-8")
    main = (project_root / "main.gd").read_text(encoding="utf-8")

    assert "var gob_sel_from: Vector2i" in gobblet
    assert "func _gob_can_move(" in gobblet
    assert "func _gob_move(" in gobblet
    assert "if _gob_check_win(3 - player):" in gobblet
    assert "_gob_move(gob_sel_from, destination, me)" in gobblet
    assert 'func _rpc_gob_move(fx: int, fy: int, tx: int, ty: int, player: int)' in main
    assert "_gob_cpu()" in gobblet


def test_abalone_has_standard_hex_board_sumito_and_six_marble_win() -> None:
    project_root = Path(__file__).resolve().parents[1]
    abalone = (project_root / "games" / "abalone" / "rules.gd").read_text(encoding="utf-8")
    main = (project_root / "main.gd").read_text(encoding="utf-8")
    readme = (project_root / "games" / "abalone" / "README.md").read_text(encoding="utf-8")
    catalog = (project_root / "core" / "game_catalog.gd").read_text(encoding="utf-8")

    assert '"id": "abalone"' in catalog and '"beta": false' in catalog.split('"id": "abalone"', 1)[1].split("},", 1)[0]
    assert "Vector2i(1, -1)" in abalone and "Vector2i(-1, 1)" in abalone
    assert "func _aba_valid_cell(q: int, r: int) -> bool:" in abalone
    assert "var enemy_count: int = 0" in abalone
    assert "enemy_count < cells.size() and enemy_count <= 2" in abalone
    assert "aba_out[opponent - 1] >= 6" in abalone
    assert "func _aba_generate_all_moves(player: int) -> Array:" in abalone
    assert "func _aba_apply_group_move(raw_cells: Array, dx: int, dy: int, player: int) -> bool:" in abalone
    assert "ابلون (آزمایشی)" not in abalone
    assert "نسخه آزمایشی" not in main
    assert "۶۱ خانه" in readme and "۱۴ مهره" in readme and "بیرون‌راندن ۶ مهره" in readme
    # The conventional axial-coordinate hex has 61 valid cells and the opening has 14 per side.
    cells = [(q, r) for r in range(-4, 5) for q in range(-4, 5) if abs(q) <= 4 and abs(r) <= 4 and abs(q + r) <= 4]
    assert len(cells) == 61
    top = [(q, -4) for q in range(0, 5)] + [(q, -3) for q in range(-1, 5)] + [(q, -2) for q in range(0, 3)]
    bottom = [(q, 4) for q in range(-4, 1)] + [(q, 3) for q in range(-4, 2)] + [(q, 2) for q in range(-2, 1)]
    assert len(top) == 14 and len(bottom) == 14


def test_gobblet_and_abalone_have_six_ai_difficulty_levels():
    project_root = Path(__file__).resolve().parents[1]
    main = (project_root / "main.gd").read_text(encoding="utf-8")
    gobblet = (project_root / "games" / "gobblet" / "rules.gd").read_text(encoding="utf-8")
    abalone = (project_root / "games" / "abalone" / "rules.gd").read_text(encoding="utf-8")

    for game_id, setter, field, rules in (
        ("gobblet", "_set_gobblet_difficulty", "gob_difficulty", gobblet),
        ("abalone", "_set_abalone_difficulty", "aba_difficulty", abalone),
    ):
        assert f'elif selected_game == "{game_id}":' in main
        assert f'"{game_id}_difficulty_%d"' in main
        assert f"{setter}.bind(i + 1)" in main
        assert f'_game_modules["{game_id}"].{field} = clampi(level, 1, 6)' in main
        assert f"var {field}: int = 3" in rules
        assert (f"app._draw_ai_difficulty_chip({field})" in rules) or (f"app._draw_ai_difficulty_chip_at({field}" in rules)

    assert "func _gob_generate_actions(player: int) -> Array:" in gobblet
    assert "if level == 1:" in gobblet and "if level >= 5:" in gobblet
    assert "strongest_reply" in gobblet and "_gob_action_score(reply, 1)" in gobblet
    assert "func _aba_simulate_move_for_ai(move: Dictionary, player: int) -> void:" in abalone
    assert "if level == 1:" in abalone and "if level >= 5:" in abalone
    assert "_aba_rank_actions(replies, 1" in abalone and "worst_line" in abalone


def test_quoridor_master_ai_penalizes_repeated_cpu_pawn_positions() -> None:
    project_root = Path(__file__).resolve().parents[1]
    ai = (project_root / "games" / "quoridor" / "ai.gd").read_text(encoding="utf-8")
    rules = (project_root / "games" / "quoridor" / "rules.gd").read_text(encoding="utf-8")

    # Real CPU positions are retained across turns and bounded to recent history.
    assert "var quo_cpu_position_history: Array[Vector2i] = []" in rules
    assert "quo_cpu_position_history.append(quo_pawns[1])" in rules
    assert "quo_cpu_position_history.append(step)" in rules
    assert "while quo_cpu_position_history.size() > 12:" in rules

    # Root search and other non-random profiles penalize reversals/revisits.
    assert "func _master_root_preference(" in ai
    assert "func _move_repetition_penalty(" in ai
    assert "IMMEDIATE_REVERSAL_PENALTY: float = 175.0" in ai
    assert "RECENT_REVISIT_PENALTY: float = 42.0" in ai
    assert "score += _master_root_preference(game, action, root_distance)" in ai
    assert "quality -= _move_repetition_penalty(game, target)" in ai
    assert "_minimax(game, 0, _active_search_depth - 1, -INF, INF)" in ai


def test_multiplayer_games_offer_cpu_opponents_and_mastermind_cpu_race() -> None:
    project_root = Path(__file__).resolve().parents[1]
    main = (project_root / "main.gd").read_text(encoding="utf-8")
    quo = (project_root / "games" / "quoridor" / "rules.gd").read_text(encoding="utf-8")
    quo_ai = (project_root / "games" / "quoridor" / "ai.gd").read_text(encoding="utf-8")
    mm = (project_root / "games" / "mastermind" / "rules.gd").read_text(encoding="utf-8")
    assert "_start_quoridor_vs_three_cpu" in main
    assert '"چهارنفره · شما در برابر ۳ CPU"' in main
    assert "choose_action_for_player(self, quo_difficulty, player)" in quo
    assert "func choose_action_for_player(game, difficulty: int, player: int)" in quo_ai
    assert "_start_mastermind_vs_three_cpu" in main
    assert "مسابقه با ۳ CPU · چهار نفره" in main
    assert 'mm_cpu_racers.size() != 4' in mm
    assert "_mm_cpu_race_tick()" in main


def test_quarto_piece_renderer_distinguishes_all_four_standard_attributes() -> None:
    project_root = Path(__file__).resolve().parents[1]
    main = (project_root / "main.gd").read_text(encoding="utf-8")
    fn = main[main.index("func _draw_quarto_piece("):main.index("func _draw_quarto()", main.index("func _draw_quarto_piece("))]
    for token in ("var tall: bool", "var round_piece: bool", "var dark_piece: bool", "var hollow_piece: bool"):
        assert token in fn
    assert "(30.0 if tall else 17.0)" in fn
    assert "if round_piece:" in fn and "if hollow_piece:" in fn
    assert "_draw_quarto_piece(Vector2(pr.position.x + 26, pr.get_center().y), piece, 0.80" in main
