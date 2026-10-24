extends SceneTree
## Headless regression tests for Pentago placement, rotation, turns and win handling.

const PentagoRulesScript = preload("res://games/pentago/rules.gd")

class MockApp extends Node2D:
	var vs_cpu: bool = false
	var local_seat: int = 0
	var rotate_buttons_requested: int = 0
	var playing_buttons_requested: int = 0
	var result_requested: bool = false
	var sent_actions: Array = []

	func _net_on() -> bool:
		return false

	func _is_my_turn() -> bool:
		return true

	func _build_pent_rotate_buttons() -> void:
		rotate_buttons_requested += 1

	func _build_playing_buttons() -> void:
		playing_buttons_requested += 1

	func _go_result(_won: bool = false) -> void:
		result_requested = true

	func _send_game_action(action: String, args: Array) -> void:
		sent_actions.append({"action": action, "args": args.duplicate()})

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

func _new_game() -> Dictionary:
	var host := MockApp.new()
	root.add_child(host)
	_hosts.append(host)
	var game = PentagoRulesScript.new()
	game.bind(host, "pentago")
	game.reset_game()
	return {"game": game, "host": host}

func _run_tests() -> void:
	_test_initial_board_and_placement_phase()
	_test_clockwise_and_counterclockwise_rotation()
	_test_rotation_advances_turn()
	_test_five_in_a_row_ends_game()
	_test_invalid_cell_input_is_ignored()
	print("PENTAGO_RULES_TESTS: checks=%d, failures=%d" % [_checks, _failures])
	for host in _hosts:
		if is_instance_valid(host):
			host.free()
	quit(1 if _failures > 0 else 0)

func _test_initial_board_and_placement_phase() -> void:
	var fixture: Dictionary = _new_game()
	var game = fixture["game"]
	var host = fixture["host"]
	_expect(game.pent_board.size() == 6, "board starts with six rows")
	var empty_cells: int = 0
	for row in game.pent_board:
		_expect(row.size() == 6, "each row has six cells")
		for cell in row:
			if int(cell) == 0:
				empty_cells += 1
	_expect(empty_cells == 36, "all 36 cells start empty")
	_expect(game._pent_place(Vector2i(0, 0)), "first legal placement is accepted")
	_expect(int(game.pent_board[0][0]) == 1, "placed piece is owned by current player")
	_expect(game.pent_phase == 1, "placement moves game to rotation phase")
	_expect(host.rotate_buttons_requested == 1, "placement asks host to expose rotation controls")

func _test_clockwise_and_counterclockwise_rotation() -> void:
	var fixture: Dictionary = _new_game()
	var game = fixture["game"]
	game.pent_board[0][0] = 1
	game._pent_rotate(0, true)
	_expect(int(game.pent_board[0][2]) == 1, "clockwise rotation moves top-left piece to top-right of quadrant")
	game._reset_pentago()
	game.pent_board[0][0] = 2
	game._pent_rotate(0, false)
	_expect(int(game.pent_board[2][0]) == 2, "counterclockwise rotation moves top-left piece to bottom-left of quadrant")

func _test_rotation_advances_turn() -> void:
	var fixture: Dictionary = _new_game()
	var game = fixture["game"]
	var host = fixture["host"]
	_expect(game._pent_place(Vector2i(1, 1)), "placement before a rotation is accepted")
	game._pent_do_rotate(0, true)
	_expect(game.pent_phase == 0, "rotation returns to placement phase")
	_expect(game.pent_turn == 2, "completed turn passes to opponent")
	_expect(host.playing_buttons_requested == 1, "completed rotation rebuilds play controls")

func _test_five_in_a_row_ends_game() -> void:
	var fixture: Dictionary = _new_game()
	var game = fixture["game"]
	var host = fixture["host"]
	for x in range(4):
		game.pent_board[0][x] = 1
	_expect(game._pent_place(Vector2i(4, 0)), "winning fifth piece is accepted")
	_expect(game.pent_game_over, "five in a row ends game")
	_expect(game.pent_winner == 1, "winner is the player who completed five")
	_expect(host.result_requested, "winning placement opens result flow")

func _test_invalid_cell_input_is_ignored() -> void:
	var fixture: Dictionary = _new_game()
	var game = fixture["game"]
	var host = fixture["host"]
	game._pent_handle_cell_tap(Vector2i(-1, 0))
	game._pent_handle_cell_tap(Vector2i(6, 0))
	_expect(game.pent_board[0][0] == 0, "out-of-bounds cell input does not mutate board")
	_expect(game.pent_phase == 0, "out-of-bounds cell input does not change phase")
	_expect(host.sent_actions.is_empty(), "out-of-bounds cell input does not send a network action")
