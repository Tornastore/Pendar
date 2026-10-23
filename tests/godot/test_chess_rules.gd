extends SceneTree
## Headless regression suite for chess legality, special moves, undo and CPU safety.

const ChessRulesScript = preload("res://games/chess/rules.gd")
const ChessAIScript = preload("res://games/chess/ai.gd")

class MockApp extends Node2D:
	var vs_cpu: bool = false
	var local_seat: int = 0
	var result_overlay_requested: bool = false
	var rebuild_count: int = 0

	func _net_on() -> bool:
		return false

	func _is_my_turn() -> bool:
		return true

	func _go_result(_won: bool = false) -> void:
		result_overlay_requested = true

	func _rebuild_buttons() -> void:
		rebuild_count += 1

var _failures: int = 0
var _checks: int = 0
var _hosts: Array[Node] = []

func _initialize() -> void:
	call_deferred("_run_tests")

func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)

func _square(name: String) -> Vector2i:
	return Vector2i("abcdefgh".find(name.substr(0, 1)), 8 - int(name.substr(1, 1)))

func _new_game(vs_cpu: bool = false) -> Dictionary:
	var host := MockApp.new()
	root.add_child(host)
	_hosts.append(host)
	host.vs_cpu = vs_cpu
	var game = ChessRulesScript.new()
	game.bind(host, "chess")
	game.reset_game()
	return {"game": game, "host": host}

func _set_position(game, pieces: Dictionary, turn: int = 1, rights: int = 0, ep: Vector2i = Vector2i(-1, -1), halfmove: int = 0) -> void:
	var board: Array = []
	for y in range(8):
		var row: Array = []
		for x in range(8):
			row.append(0)
		board.append(row)
	for square_name in pieces.keys():
		var square: Vector2i = _square(str(square_name))
		board[square.y][square.x] = int(pieces[square_name])
	game.chess_board = board
	game.chess_turn = turn
	game.chess_castling_rights = rights
	game.chess_en_passant = ep
	game.chess_halfmove_clock = halfmove
	game.chess_fullmove_number = 1
	game.chess_selected = Vector2i(-1, -1)
	game.chess_valid = []
	game.chess_game_over = false
	game.chess_winner = 0
	game.chess_last = [Vector2i(-1, -1), Vector2i(-1, -1)]
	game.chess_history.clear()
	game.chess_position_history.clear()
	game.chess_move_log.clear()
	game.chess_promotion_pending = {}
	game.chess_terminal_reason = ""
	game.chess_last_notation = ""
	game.chess_position_history.append(game._chess_position_key())

func _run_tests() -> void:
	_test_initial_position_and_sliders()
	_test_start_position_perft()
	_test_king_safety_and_pins()
	_test_castling_and_undo()
	_test_capture_undo_and_move_counters()
	_test_en_passant_and_undo()
	_test_promotion_and_undo()
	_test_mate_stalemate_and_draw_claims()
	_test_cpu_undo()
	_test_ai_returns_legal_move_without_mutating_state()
	_test_ai_finds_mate_in_one()
	_test_ai_generates_underpromotion_choices()
	print("CHESS_RULES_TESTS: checks=%d, failures=%d" % [_checks, _failures])
	for host in _hosts:
		if is_instance_valid(host):
			host.free()
	quit(1 if _failures > 0 else 0)

func _test_initial_position_and_sliders() -> void:
	var fixture: Dictionary = _new_game()
	var game = fixture["game"]
	_expect(game._chess_all_moves(1).size() == 20, "initial white has 20 legal moves")
	_expect(game._chess_all_moves(2).size() == 20, "initial black has 20 legal moves")
	_expect(game._chess_gen_moves(_square("a1")).is_empty(), "initial rook is blocked by own pieces")
	_set_position(game, {"e1": 6, "h8": 12, "a1": 4})
	var rook_moves: Array = game._chess_gen_moves(_square("a1"))
	_expect(rook_moves.has(_square("a8")), "rook ray scans across empty squares")
	_expect(rook_moves.has(_square("a4")), "rook can reach intermediate empty squares")
	_expect(not rook_moves.has(_square("a9")), "rook ray stays inside board")

func _perft(game, depth: int) -> int:
	if depth <= 0:
		return 1
	var nodes: int = 0
	for move_value in game._chess_all_moves(game.chess_turn):
		var move: Array = move_value
		var promotion_type: int = int(move[2]) if move.size() >= 3 else 5
		var snapshot: Dictionary = game._chess_simulate_move(move[0], move[1], promotion_type)
		if snapshot.is_empty():
			continue
		nodes += _perft(game, depth - 1)
		game._chess_restore_simulation(snapshot)
	return nodes

func _test_start_position_perft() -> void:
	var fixture: Dictionary = _new_game()
	var game = fixture["game"]
	_expect(_perft(game, 1) == 20, "starting-position perft depth 1 equals 20")
	_expect(_perft(game, 2) == 400, "starting-position perft depth 2 equals 400")
	_expect(_perft(game, 3) == 8902, "starting-position perft depth 3 equals 8902")
	_expect(game.chess_turn == 1 and game.chess_history.is_empty(), "perft restores turn and does not mutate live move history")
	# This standard tactical perft position stresses king safety and awkward rook/pawn lines.
	_set_position(game, {"c7": 7, "d6": 7, "a5": 6, "b5": 1, "h5": 10, "b4": 4, "f4": 7, "h4": 12, "e2": 1, "g2": 1})
	_expect(_perft(game, 1) == 14, "tactical perft position depth 1 equals 14")
	_expect(_perft(game, 2) == 191, "tactical perft position depth 2 equals 191")
	_expect(_perft(game, 3) == 2812, "tactical perft position depth 3 equals 2812")

func _test_capture_undo_and_move_counters() -> void:
	var fixture: Dictionary = _new_game()
	var game = fixture["game"]
	_set_position(game, {"h1": 6, "h8": 12, "a1": 4, "a8": 8})
	var initial_key: String = game._chess_position_key()
	game._chess_make_move(_square("a1"), _square("a8"))
	_expect(int(game.chess_board[0][0]) == 4 and int(game.chess_board[0][7]) == 12, "capture moves the rook to a8, removes the knight and leaves the black king on h8")
	_expect(game.chess_turn == 2 and game.chess_fullmove_number == 1, "white capture advances turn without incrementing the fullmove number")
	_expect(game.chess_move_log.size() == 1 and game.chess_position_history.size() == 2, "a legal capture is appended to both histories")
	game._chess_undo()
	_expect(game._chess_position_key() == initial_key, "undo restores the exact pre-capture position")
	_expect(int(game.chess_board[7][0]) == 4 and int(game.chess_board[0][0]) == 8, "undo restores the capturing rook and captured knight")
	_expect(game.chess_turn == 1 and game.chess_fullmove_number == 1 and game.chess_move_log.is_empty(), "undo restores move counters and notation history")

func _test_king_safety_and_pins() -> void:
	var fixture: Dictionary = _new_game()
	var game = fixture["game"]
	_set_position(game, {"e1": 6, "a8": 12, "b5": 9})
	var king_moves: Array = game._chess_gen_moves(_square("e1"))
	_expect(not king_moves.has(_square("e2")), "king cannot move onto a bishop-attacked square")
	var before_key: String = game._chess_position_key()
	game._chess_make_move(_square("e1"), _square("e2"))
	_expect(game._chess_position_key() == before_key and game.chess_turn == 1, "illegal king move is rejected without losing the game")
	_expect(not game.chess_game_over and not fixture["host"].result_overlay_requested, "illegal king move does not trigger a loss/result overlay")
	_set_position(game, {"e1": 6, "e8": 10, "a8": 12, "e2": 4})
	var rook_moves: Array = game._chess_gen_moves(_square("e2"))
	_expect(not rook_moves.has(_square("d2")), "pinned rook cannot expose its king to check")

func _test_castling_and_undo() -> void:
	var fixture: Dictionary = _new_game()
	var game = fixture["game"]
	_set_position(game, {"e1": 6, "h1": 4, "a8": 12}, 1, 1)
	_expect(game._chess_gen_moves(_square("e1")).has(_square("g1")), "legal king-side castling is generated")
	game._chess_make_move(_square("e1"), _square("g1"))
	_expect(int(game.chess_board[7][6]) == 6 and int(game.chess_board[7][5]) == 4, "castling moves king and rook")
	_expect((game.chess_castling_rights & 1) == 0, "castling permanently removes that right")
	game._chess_undo()
	_expect(int(game.chess_board[7][4]) == 6 and int(game.chess_board[7][7]) == 4, "undo restores king and rook after castling")
	_expect(game.chess_castling_rights == 1 and game.chess_turn == 1, "undo restores castling rights and side to move")
	_set_position(game, {"e1": 6, "h1": 4, "a8": 12, "f8": 10}, 1, 1)
	_expect(not game._chess_gen_moves(_square("e1")).has(_square("g1")), "castling through an attacked square is forbidden")

func _test_en_passant_and_undo() -> void:
	var fixture: Dictionary = _new_game()
	var game = fixture["game"]
	_set_position(game, {"e1": 6, "e8": 12, "e5": 1, "d5": 7}, 1, 0, _square("d6"), 12)
	_expect(game._chess_gen_moves(_square("e5")).has(_square("d6")), "legal en-passant capture is generated")
	game._chess_make_move(_square("e5"), _square("d6"))
	_expect(int(game.chess_board[2][3]) == 1 and int(game.chess_board[3][3]) == 0, "en-passant captures the pawn behind the destination")
	_expect(game.chess_halfmove_clock == 0 and game.chess_en_passant == Vector2i(-1, -1), "en-passant resets the halfmove clock and expires")
	game._chess_undo()
	_expect(int(game.chess_board[3][4]) == 1 and int(game.chess_board[3][3]) == 7, "undo restores both pawns after en-passant")
	_expect(game.chess_en_passant == _square("d6") and game.chess_halfmove_clock == 12, "undo restores en-passant and halfmove metadata")
	_set_position(game, {"e5": 6, "a8": 12, "f5": 1, "g5": 7, "h5": 10}, 1, 0, _square("g6"))
	_expect(not game._chess_gen_moves(_square("f5")).has(_square("g6")), "en-passant is rejected when it opens a rook attack on own king")

func _test_promotion_and_undo() -> void:
	var fixture: Dictionary = _new_game()
	var game = fixture["game"]
	_set_position(game, {"e1": 6, "h8": 12, "c8": 9, "a7": 1})
	_expect(game._chess_is_promotion_move(_square("a7"), _square("a8")), "promotion move is detected")
	game._chess_make_move(_square("a7"), _square("a8"), 2)
	_expect(int(game.chess_board[0][0]) == 2, "underpromotion to knight is supported")
	game._chess_undo()
	_expect(int(game.chess_board[1][0]) == 1 and int(game.chess_board[0][0]) == 0, "undo restores pawn after underpromotion")

func _test_mate_stalemate_and_draw_claims() -> void:
	var fixture: Dictionary = _new_game()
	var game = fixture["game"]
	_set_position(game, {"h8": 12, "g7": 5, "f6": 6}, 2)
	game._chess_update_terminal_state()
	_expect(game.chess_game_over and game.chess_winner == 1 and game.chess_terminal_reason.begins_with("کیش‌ومات"), "checkmate is detected and awarded to the attacker")
	_set_position(game, {"a8": 12, "c6": 6, "b6": 5}, 2)
	game._chess_update_terminal_state()
	_expect(game.chess_game_over and game.chess_winner == 0 and game.chess_terminal_reason.begins_with("پات"), "stalemate is a draw, not a king capture")
	_set_position(game, {"e1": 6, "e8": 12, "a2": 1}, 1, 0, Vector2i(-1, -1), 100)
	_expect(game._chess_can_claim_draw(), "50-move draw can be claimed at 100 halfmoves")
	var cpu_fixture: Dictionary = _new_game(true)
	var cpu_game = cpu_fixture["game"]
	_set_position(cpu_game, {"e1": 6, "e8": 12, "a2": 1}, 2, 0, Vector2i(-1, -1), 100)
	_expect(not cpu_game._chess_can_claim_draw(), "human cannot claim draw on the CPU turn")
	var key: String = game._chess_position_key()
	game.chess_position_history.clear()
	game.chess_position_history.append(key)
	game.chess_position_history.append(key)
	game.chess_position_history.append(key)
	_expect(game._chess_can_claim_draw(), "threefold repetition can be claimed")

func _test_cpu_undo() -> void:
	var fixture: Dictionary = _new_game(true)
	var game = fixture["game"]
	_set_position(game, {"a1": 4, "b1": 2, "c1": 3, "d1": 5, "e1": 6, "f1": 3, "g1": 2, "h1": 4, "a2": 1, "b2": 1, "c2": 1, "d2": 1, "e2": 1, "f2": 1, "g2": 1, "h2": 1, "a8": 10, "b8": 8, "c8": 9, "d8": 11, "e8": 12, "f8": 9, "g8": 8, "h8": 10, "a7": 7, "b7": 7, "c7": 7, "d7": 7, "e7": 7, "f7": 7, "g7": 7, "h7": 7})
	game._chess_make_move(_square("e2"), _square("e4"))
	game._chess_make_move(_square("e7"), _square("e5"))
	_expect(game.chess_turn == 1 and game.chess_history.size() == 2, "CPU reply fixture has two plies")
	game._chess_undo()
	_expect(game.chess_turn == 1 and game.chess_history.is_empty(), "CPU undo rewinds the reply and the human move")
	_expect(int(game.chess_board[6][4]) == 1 and int(game.chess_board[1][4]) == 7, "CPU undo restores both central pawns")
	_expect(game.chess_move_log.is_empty() and game.chess_position_history.size() == 1, "CPU undo restores move log and repetition history")

func _test_ai_returns_legal_move_without_mutating_state() -> void:
	var fixture: Dictionary = _new_game()
	var game = fixture["game"]
	var before_key: String = game._chess_position_key()
	var before_history: int = game.chess_history.size()
	for level in [3, 5, 6]:
		var ai = ChessAIScript.new()
		var move: Array = ai.choose_move(game, level)
		_expect(move.size() == 2, "AI level %d returns a move" % level)
		if move.size() == 2:
			_expect(game._chess_gen_moves(move[0]).has(move[1]), "AI level %d only returns legal moves" % level)
		_expect(game._chess_position_key() == before_key and game.chess_history.size() == before_history and game.chess_turn == 1, "AI level %d search does not mutate live game state" % level)

func _test_ai_finds_mate_in_one() -> void:
	var fixture: Dictionary = _new_game()
	var game = fixture["game"]
	# Black to move: Qb2 is mate against the king on a1, protected by Kc2.
	_set_position(game, {"a1": 6, "c2": 12, "b3": 11}, 2)
	var ai = ChessAIScript.new()
	var move: Array = ai.choose_move(game, 5)
	var delivers_mate: bool = false
	if move.size() >= 2:
		var promotion_type: int = int(move[2]) if move.size() >= 3 else 5
		var snapshot: Dictionary = game._chess_simulate_move(move[0], move[1], promotion_type)
		if not snapshot.is_empty():
			var defending_side: int = int(game.chess_turn)
			var replies: Array = game._chess_all_moves(defending_side)
			delivers_mate = replies.is_empty() and game._chess_king_in_check(defending_side).x >= 0
			game._chess_restore_simulation(snapshot)
	_expect(delivers_mate, "expert AI finds a forced mate in one")

func _test_ai_generates_underpromotion_choices() -> void:
	var fixture: Dictionary = _new_game()
	var game = fixture["game"]
	_set_position(game, {"e1": 6, "h8": 12, "a7": 1}, 1)
	var promotions: Array[int] = []
	for move_value in game._chess_all_moves(1):
		var move: Array = move_value
		if move.size() >= 3 and move[0] == _square("a7") and move[1] == _square("a8"):
			promotions.append(int(move[2]))
	promotions.sort()
	_expect(promotions == [2, 3, 4, 5], "search sees knight, bishop, rook and queen promotion choices")
