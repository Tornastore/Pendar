extends SceneTree
## Quarto rule regressions: offered pieces, legal placement, shared-attribute victory and guards.

const QuartoRulesScript = preload("res://games/quarto/rules.gd")

class MockApp extends Node2D:
	var vs_cpu: bool = false
	var local_seat: int = 0
	var rebuild_calls: int = 0
	var result_calls: int = 0
	var toasts: Array[String] = []
	var sent_actions: Array = []

	func _net_on() -> bool:
		return false

	func _is_my_turn() -> bool:
		return true

	func _rebuild_buttons() -> void:
		rebuild_calls += 1

	func _go_result(_won: bool = false) -> void:
		result_calls += 1

	func _show_toast(message: String) -> void:
		toasts.append(message)

	func _send_game_action(action: String, args: Array) -> void:
		sent_actions.append({"action": action, "args": args.duplicate()})

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

func _new_game() -> Dictionary:
	var host := MockApp.new()
	root.add_child(host)
	_hosts.append(host)
	var game = QuartoRulesScript.new()
	game.bind(host, "quarto")
	game.reset_game()
	return {"game": game, "host": host}

func _run_tests() -> void:
	_test_reset_and_piece_count()
	_test_piece_offer_and_legal_placement()
	_test_shared_attribute_win()
	_test_invalid_actions_are_rejected()
	print("QUARTO_RULES_TESTS: checks=%d, failures=%d" % [_checks, _failures])
	for host in _hosts:
		if is_instance_valid(host):
			host.free()
	quit(1 if _failures > 0 else 0)

func _test_reset_and_piece_count() -> void:
	var fixture: Dictionary = _new_game()
	var game = fixture["game"]
	var empty_count: int = 0
	for row in game.qto_board:
		_expect(row.size() == 4, "board row has four cells")
		for piece in row:
			if int(piece) == -1:
				empty_count += 1
	_expect(game.qto_board.size() == 4 and empty_count == 16, "reset creates a 4x4 empty board")
	_expect(game.qto_remaining.size() == 16, "all sixteen pieces start available")
	_expect(game.qto_turn == 1 and game.qto_phase == 0, "first actor chooses a piece for the opponent")

func _test_piece_offer_and_legal_placement() -> void:
	var fixture: Dictionary = _new_game()
	var game = fixture["game"]
	var host = fixture["host"]
	_expect(game._qto_choose_piece(6, 1), "current actor can offer an available piece")
	_expect(game.qto_phase == 1 and game.qto_turn == 2, "offering a piece transfers placement to opponent")
	_expect(6 not in game.qto_remaining and game.qto_piece_to_place == 6, "offered piece is removed from available set")
	_expect(game._qto_place(0, 0, 2), "opponent can place offered piece into an empty cell")
	_expect(int(game.qto_board[0][0]) == 6, "placed piece is stored in the selected cell")
	_expect(game.qto_phase == 0 and game.qto_turn == 2, "placer chooses the next piece after a safe placement")
	_expect(host.rebuild_calls >= 2, "state transitions refresh controls")

func _test_shared_attribute_win() -> void:
	var fixture: Dictionary = _new_game()
	var game = fixture["game"]
	var host = fixture["host"]
	game.qto_board[0][0] = 0
	game.qto_board[0][1] = 2
	game.qto_board[0][2] = 4
	game.qto_phase = 1
	game.qto_turn = 2
	game.qto_piece_to_place = 6
	_expect(game._qto_place(3, 0, 2), "completing a shared-attribute line is a legal placement")
	_expect(game.qto_game_over and game.qto_winner == 2, "placing the fourth matching piece wins Quarto")
	_expect(host.result_calls == 1, "win requests the result screen")

func _test_invalid_actions_are_rejected() -> void:
	var fixture: Dictionary = _new_game()
	var game = fixture["game"]
	var host = fixture["host"]
	_expect(not game._qto_choose_piece(-1, 1), "invalid piece id is rejected")
	_expect(not game._qto_choose_piece(0, 2), "non-current actor cannot offer a piece")
	game.qto_phase = 1
	game.qto_turn = 1
	game.qto_piece_to_place = 0
	_expect(not game._qto_place(-1, 0, 1), "out-of-bounds placement is rejected")
	_expect(int(game.qto_board[0][0]) == -1, "invalid placement does not alter board")
	game._qto_handle_board_tap(Vector2i(-1, 0))
	_expect(not host.toasts.is_empty(), "invalid screen cell gives feedback")
