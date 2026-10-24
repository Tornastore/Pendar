extends SceneTree
## Runtime regressions for rule modules that did not yet have dedicated Godot tests.
## UI drawing and pointer mapping are deliberately not invoked from these tests.

const OthelloRulesScript = preload("res://games/othello/rules.gd")
const QuoridorRulesScript = preload("res://games/quoridor/rules.gd")
const GobbletRulesScript = preload("res://games/gobblet/rules.gd")
const HokmRulesScript = preload("res://games/hokm/rules.gd")
const PasoorRulesScript = preload("res://games/pasoor/rules.gd")
const AbaloneRulesScript = preload("res://games/abalone/rules.gd")
const BlockaceRulesScript = preload("res://games/blockace/rules.gd")

class MockApp extends Node2D:
	var vs_cpu: bool = false
	var local_seat: int = 0
	var _time: float = 12.0
	var result_calls: int = 0
	var toasts: Array[String] = []
	var sent_actions: Array = []
	var rebuild_calls: int = 0

	func _net_on() -> bool:
		return false

	func _is_my_turn() -> bool:
		return true

	func _go_result(_won: bool = false) -> void:
		result_calls += 1

	func _show_toast(message: String) -> void:
		toasts.append(message)

	func _send_game_action(action: String, args: Array) -> void:
		sent_actions.append({"action": action, "args": args.duplicate()})

	func _rebuild_buttons() -> void:
		rebuild_calls += 1

var _checks: int = 0
var _failures: int = 0
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

func _new_game(script: Script, module_id: String) -> Dictionary:
	var host := MockApp.new()
	root.add_child(host)
	_hosts.append(host)
	var game = script.new()
	game.bind(host, module_id)
	game.reset_game()
	return {"game": game, "host": host}

func _run_tests() -> void:
	_test_othello_opening_and_capture()
	_test_quoridor_moves_and_walls()
	_test_gobblet_stack_and_win()
	_test_hokm_follow_suit_and_trick()
	_test_pasoor_capture_sum()
	_test_abalone_board_and_legal_move()
	_test_blockace_first_placement_and_piece_inventory()
	print("REMAINING_RULES_TESTS: checks=%d, failures=%d" % [_checks, _failures])
	for host in _hosts:
		if is_instance_valid(host):
			host.free()
	quit(1 if _failures > 0 else 0)

func _test_othello_opening_and_capture() -> void:
	var fixture: Dictionary = _new_game(OthelloRulesScript, "othello")
	var game = fixture["game"]
	_expect(game.oth_size == 8 and game.othello_board.size() == 8, "Othello reset creates the standard 8x8 board")
	_expect(game.othello_valid.size() == 4, "Othello opening has four legal moves")
	_expect(game._othello_would_flip(Vector2i(3, 2), 1).size() == 1, "Othello detects the expected opening flip")
	_expect(not game._othello_place(Vector2i(0, 0)), "Othello rejects an empty non-capturing move")
	_expect(game._othello_place(Vector2i(3, 2)), "Othello accepts a legal capturing move")
	_expect(int(game.othello_board[2][3]) == 1 and int(game.othello_board[3][3]) == 1, "Othello places the disc and flips the bracketed disc")
	_expect(game.othello_turn == 2 and int(game.othello_scores[1]) == 4 and int(game.othello_scores[2]) == 1, "Othello advances the turn and updates scores")

func _test_quoridor_moves_and_walls() -> void:
	var fixture: Dictionary = _new_game(QuoridorRulesScript, "quoridor")
	var game = fixture["game"]
	_expect(game.quo_pawns == [Vector2i(4, 0), Vector2i(4, 8)], "Quoridor reset places both pawns on their start rows")
	_expect(game._quo_legal_moves(0).size() == 3, "Quoridor opening pawn has three in-bounds moves")
	_expect(game._quo_path_exists(0) and game._quo_path_exists(1), "Quoridor reset leaves a goal path for both players")
	_expect(not game._quo_wall_placement_legal(-1, 3, false), "Quoridor rejects a wall outside the board")
	_expect(game._quo_wall_placement_legal(3, 3, false), "Quoridor accepts a legal wall anchor")
	_expect(game._quo_place_wall(3, 3, false), "Quoridor stores a legal wall")
	_expect(not game._quo_place_wall(3, 3, false), "Quoridor rejects a duplicate wall")
	_expect(not game._quo_can_move(Vector2i(3, 3), Vector2i(3, 4)), "Quoridor wall blocks the covered pawn edge")
	_expect(game._quo_path_exists(0) and game._quo_path_exists(1), "Quoridor wall placement preserves routes to both goals")

func _test_gobblet_stack_and_win() -> void:
	var fixture: Dictionary = _new_game(GobbletRulesScript, "gobblet")
	var game = fixture["game"]
	var host = fixture["host"]
	_expect(game.gob_board.size() == 4 and game.gob_board[0].size() == 4, "Gobblet reset creates a 4x4 stack board")
	_expect(game._gob_can_place(0, 0, 1, 1), "Gobblet allows a current player's available piece on an empty cell")
	_expect(not game._gob_can_place(0, 0, 5, 1), "Gobblet rejects a piece size outside the supported range")
	_expect(game._gob_place(0, 0, 1, 1), "Gobblet accepts a legal placement")
	_expect(int(game.gob_hand[0][0]) == 2 and game.gob_turn == 2, "Gobblet consumes one piece and advances the turn")
	_expect(not game._gob_can_place(0, 0, 1, 2), "Gobblet rejects a piece that is not larger than the visible top piece")

	var win_fixture: Dictionary = _new_game(GobbletRulesScript, "gobblet")
	var win_game = win_fixture["game"]
	var win_host = win_fixture["host"]
	for x in range(3):
		win_game.gob_board[0][x].append({"o": 1, "s": 3})
	_expect(win_game._gob_place(3, 0, 1, 1), "Gobblet accepts the move that completes a visible four-in-a-row")
	_expect(win_game.gob_game_over and win_game.gob_winner == 1, "Gobblet recognizes the four-in-a-row winner")
	_expect(win_host.result_calls == 1, "Gobblet publishes the result exactly once")

func _test_hokm_follow_suit_and_trick() -> void:
	var fixture: Dictionary = _new_game(HokmRulesScript, "hokm")
	var game = fixture["game"]
	var host = fixture["host"]
	game.hokm_trump = 3
	game.hokm_hands = [
		[{"r": 13, "s": 1}, {"r": 4, "s": 2}],
		[{"r": 2, "s": 1}, {"r": 1, "s": 2}],
	]
	game.hokm_turn = 0
	game.hokm_trick = []
	game.hokm_led_suit = -1
	game._hokm_play(0, 0)
	_expect(game.hokm_turn == 1 and game.hokm_led_suit == 1, "Hokm records the led suit and gives the response turn")
	_expect(not game._hokm_legal(1, {"r": 1, "s": 2}), "Hokm requires following suit when the player holds the led suit")
	var response_hand_size: int = game.hokm_hands[1].size()
	game._hokm_play(1, 1)
	_expect(game.hokm_trick.size() == 1 and game.hokm_hands[1].size() == response_hand_size, "Hokm rejects an off-suit play while a led-suit card is held")
	game._hokm_play(1, 0)
	_expect(game.hokm_scores == [1, 0], "Hokm awards the trick to the higher card in the led suit")
	_expect(game.hokm_trick.is_empty() and game.hokm_turn == 0, "Hokm clears a completed trick and leads from its winner")
	_expect(game.hokm_seen_cards.size() == 2 and game.hokm_last.size() == 2, "Hokm records played and last-trick cards")
	_expect(host.result_calls == 0, "Hokm does not end the hand while cards remain")

func _test_pasoor_capture_sum() -> void:
	var fixture: Dictionary = _new_game(PasoorRulesScript, "pasoor")
	var game = fixture["game"]
	game.pas_hands = [[{"r": 3, "s": 0}], [{"r": 7, "s": 1}]]
	game.pas_table = [{"r": 8, "s": 2}, {"r": 4, "s": 3}]
	game.pas_captured = [[], []]
	game.pas_turn = 0
	game.pas_game_over = false
	var captures: Array = game._pas_find_captures({"r": 3, "s": 0})
	_expect(captures.size() == 1 and captures[0] == [0], "Pasoor finds the table subset that sums to eleven with the played card")
	_expect(game._pas_must_capture({"r": 3, "s": 0}), "Pasoor marks a card as requiring capture when a valid capture exists")
	game._pas_play(0, 0, [0])
	_expect(game.pas_hands[0].is_empty() and game.pas_captured[0].size() == 2, "Pasoor moves the played card and captured table card into the capture pile")
	_expect(game.pas_table.size() == 1 and int(game.pas_table[0].r) == 4, "Pasoor leaves unselected table cards in place")
	_expect(game.pas_turn == 1 and game.pas_last_capturer == 0, "Pasoor records the capturer and advances the turn")

func _test_abalone_board_and_legal_move() -> void:
	var fixture: Dictionary = _new_game(AbaloneRulesScript, "abalone")
	var game = fixture["game"]
	var count_one: int = 0
	var count_two: int = 0
	var valid_cells: int = 0
	for row in game.aba_board:
		_expect(row.size() == 9, "Abalone uses a 9x9 axial-coordinate storage row")
		for value in row:
			if int(value) == -1:
				continue
			valid_cells += 1
			if int(value) == 1:
				count_one += 1
			elif int(value) == 2:
				count_two += 1
	_expect(valid_cells == 61, "Abalone marks exactly 61 valid hex cells")
	_expect(count_one == 14 and count_two == 14, "Abalone starts with fourteen marbles for each player")
	var moves: Array = game._aba_generate_all_moves(1)
	_expect(not moves.is_empty(), "Abalone opening position has legal moves")
	if not moves.is_empty():
		var move: Dictionary = moves[0]
		_expect(game._aba_apply_group_move(move.cells, int(move.dx), int(move.dy), 1), "Abalone applies a generated legal group move")
		_expect(game.aba_turn == 2, "Abalone advances the turn after a legal move")

func _test_blockace_first_placement_and_piece_inventory() -> void:
	var fixture: Dictionary = _new_game(BlockaceRulesScript, "blockace")
	var game = fixture["game"]
	_expect(game.blk_grid.size() == 14 and game.blk_grid[0].size() == 14, "Blockace reset creates a 14x14 board")
	_expect(game.blk_pieces.size() == 21, "Blockace inventory contains all 21 standard pieces")
	_expect(game._blk_cells(0, 0, false) == [Vector2i(0, 0)], "Blockace monomino orientation is normalized correctly")
	var monomino: Array = game._blk_cells(0, 0, false)
	_expect(game._blk_can_place(4, 4, monomino, 0, 0), "Blockace requires the first move to cover player one's start square")
	_expect(not game._blk_can_place(0, 0, monomino, 0, 0), "Blockace rejects a first move away from the start square")
	game._blk_place(4, 4, monomino, 0, 0, 0, false)
	_expect(int(game.blk_grid[4][4]) == 1 and bool(game.blk_used[0][0]), "Blockace records placed cells and consumes the piece")
	_expect(game.blk_turn == 1, "Blockace advances to the opponent after a legal first placement")
	_expect(not game._blk_can_place(4, 4, monomino, 0, 0), "Blockace does not permit reusing a consumed piece")
