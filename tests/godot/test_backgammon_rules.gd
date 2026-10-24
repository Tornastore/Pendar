extends SceneTree
## Headless regression suite for backgammon legality, mandatory dice use,
## bearing off, bar entry, hit handling, hit-testing and AI state safety.

const BackgammonRulesScript = preload("res://games/backgammon/rules.gd")
const BackgammonAIScript = preload("res://games/backgammon/ai.gd")

class MockApp extends Node2D:
	var vs_cpu: bool = false
	var local_seat: int = 0
	var toasts: Array[String] = []

	func _net_on() -> bool:
		return false

	func _my_seat() -> int:
		return local_seat

	func _show_toast(message: String) -> void:
		toasts.append(message)

	func _rebuild_buttons() -> void:
		pass

	func _go_result() -> void:
		pass

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

func _new_game(vs_cpu: bool = false) -> Dictionary:
	var host := MockApp.new()
	root.add_child(host)
	_hosts.append(host)
	host.vs_cpu = vs_cpu
	var game = BackgammonRulesScript.new()
	game.bind(host, "backgammon")
	game.reset_game()
	return {"game": game, "host": host}

func _empty_points() -> Array:
	var points: Array = []
	for _i in range(24):
		points.append(0)
	return points

func _has_move(moves: Array[Dictionary], source: int, target: int, die: int = -1) -> bool:
	for move in moves:
		if int(move.get("source", -99)) == source and int(move.get("target", -99)) == target:
			if die < 0 or int(move.get("die", -99)) == die:
				return true
	return false

func _set_position(game, points: Array, bar: Array, off: Array, turn: int, dice: Array) -> void:
	game.bg_points = points.duplicate()
	game.bg_bar = bar.duplicate()
	game.bg_off = off.duplicate()
	game.bg_turn = turn
	game.bg_dice = dice.duplicate()
	game.bg_moves_left = game._bg_expand_dice(dice)
	game.bg_game_over = false
	game.bg_winner = -1
	game.bg_sel = -2
	game._bg_invalidate_legal_cache()

func _run_tests() -> void:
	_test_standard_setup()
	_test_bar_entry_and_blocked_points()
	_test_hits_and_bearing_off()
	_test_mandatory_dice_and_doubles()
	_test_input_hit_testing()
	_test_end_turn_guard()
	_test_ai_legality_and_state_safety()
	_test_ai_bar_and_home_board_heuristics()
	print("BACKGAMMON_RULES_TESTS: checks=%d, failures=%d" % [_checks, _failures])
	for host in _hosts:
		if is_instance_valid(host):
			host.free()
	quit(1 if _failures > 0 else 0)

func _test_standard_setup() -> void:
	var ctx: Dictionary = _new_game()
	var game = ctx.game
	var player0: int = int(game.bg_bar[0]) + int(game.bg_off[0])
	var player1: int = int(game.bg_bar[1]) + int(game.bg_off[1])
	for value in game.bg_points:
		if int(value) > 0:
			player0 += int(value)
		elif int(value) < 0:
			player1 += -int(value)
	_expect(player0 == 15 and player1 == 15, "standard setup has fifteen checkers per player")
	_expect(game.bg_moves_left.size() == 2, "opening roll supplies both non-equal dice")
	_expect(game.bg_dice[0] != game.bg_dice[1], "opening dice are rerolled on ties")

func _test_bar_entry_and_blocked_points() -> void:
	var game = _new_game().game
	var points: Array = _empty_points()
	points[10] = 1
	_set_position(game, points, [1, 0], [0, 0], 0, [4, 2])
	var turn_moves: Array[Dictionary] = game._bg_turn_legal_moves(0)
	var only_bar_moves: bool = not turn_moves.is_empty()
	for move in turn_moves:
		if int(move.source) != -1:
			only_bar_moves = false
	_expect(only_bar_moves, "checkers on bar force entry before all board moves")
	_expect(_has_move(turn_moves, -1, 20, 4), "bar entry uses 24 minus the die for player zero")

	points = _empty_points()
	points[20] = -2
	_set_position(game, points, [1, 0], [0, 0], 0, [4, 2])
	_expect(game._bg_legal_moves_for_die(0, 4).is_empty(), "two opposing checkers block a bar entry point")

func _test_hits_and_bearing_off() -> void:
	var game = _new_game().game
	var points: Array = _empty_points()
	points[3] = 1
	points[5] = -1
	_set_position(game, points, [0, 0], [0, 0], 0, [2, 3])
	var capture: Dictionary = {}
	for move in game._bg_legal_moves_for_die(0, 2):
		if int(move.source) == 3 and int(move.target) == 5:
			capture = move
	_expect(not capture.is_empty(), "a checker may hit a lone opposing blot")
	if not capture.is_empty():
		game._bg_apply_board_move(0, capture)
	_expect(int(game.bg_points[5]) == 1 and int(game.bg_bar[1]) == 1, "a hit sends the opposing checker to the bar")

	points = _empty_points()
	points[3] = 1
	points[5] = -2
	_set_position(game, points, [0, 0], [0, 0], 0, [2, 3])
	_expect(not _has_move(game._bg_legal_moves_for_die(0, 2), 3, 5, 2), "a made point cannot be hit or occupied")

	points = _empty_points()
	points[18] = 1
	_set_position(game, points, [0, 0], [0, 0], 0, [6, 2])
	_expect(_has_move(game._bg_legal_moves_for_die(0, 6), 18, -1, 6), "all-home checker can bear off with an exact die")

	points = _empty_points()
	points[22] = 1
	points[23] = 1
	_set_position(game, points, [0, 0], [0, 0], 0, [6, 2])
	var overshoot_moves: Array[Dictionary] = game._bg_legal_moves_for_die(0, 6)
	_expect(not _has_move(overshoot_moves, 22, -1, 6), "overshoot bearing off is forbidden while a farther checker remains")
	_expect(_has_move(overshoot_moves, 23, -1, 6), "overshoot bearing off is allowed from the farthest occupied point")

func _test_mandatory_dice_and_doubles() -> void:
	var game = _new_game().game
	var points: Array = _empty_points()
	points[0] = 1
	_set_position(game, points, [0, 0], [0, 0], 0, [1, 2])
	var moves: Array[Dictionary] = game._bg_turn_legal_moves(0)
	_expect(_has_move(moves, 0, 1, 1), "legal prefix retains the low die when both dice can be used")
	_expect(_has_move(moves, 0, 2, 2), "legal prefix retains the high die when both dice can be used")

	# A single home checker can bear off with either die, but can only consume
	# one die in this position; official rules require the higher die.
	points = _empty_points()
	points[22] = 1
	_set_position(game, points, [0, 0], [0, 0], 0, [2, 6])
	var forced_high: Array[Dictionary] = game._bg_turn_legal_moves(0)
	_expect(forced_high.size() == 1 and int(forced_high[0].get("die", -1)) == 6, "higher-die rule applies when only one of two dice can be used")
	_expect(game._bg_expand_dice([4, 4]) == [4, 4, 4, 4], "doubles expand into four moves")

func _test_input_hit_testing() -> void:
	var game = _new_game().game
	_expect(game._bg_point_from_tap(Vector2(57, 250)) == 0, "top-left visible point maps to point zero")
	_expect(game._bg_point_from_tap(Vector2(477, 250)) == 11, "top-right visible point maps to point eleven")
	_expect(game._bg_point_from_tap(Vector2(57, 580)) == 23, "bottom-left visible point maps to point twenty-three")
	_expect(game._bg_point_from_tap(Vector2(477, 580)) == 12, "bottom-right visible point maps to point twelve")
	_expect(game._bg_point_from_tap(Vector2(268, 400)) == -1, "central bar channel maps to bar selection")
	_expect(game._bg_point_from_tap(Vector2(100, 400)) == -2, "blank middle board does not map to a point")
	_expect(game._bg_point_from_tap(Vector2(100, 480)) == -2, "non-point lower channel does not map to a point")

func _test_end_turn_guard() -> void:
	var ctx: Dictionary = _new_game()
	var game = ctx.game
	var host = ctx.host
	var points: Array = _empty_points()
	points[0] = 1
	_set_position(game, points, [0, 0], [0, 0], 0, [1, 2])
	game._bg_request_end_turn()
	_expect(game.bg_turn == 0 and not host.toasts.is_empty(), "player cannot end turn while a legal move remains")

func _test_ai_legality_and_state_safety() -> void:
	var game = _new_game().game
	var points: Array = _empty_points()
	points[12] = -2
	points[18] = 1
	_set_position(game, points, [0, 0], [0, 0], 1, [1, 2])
	var before: Dictionary = game._bg_save_board()
	var ai = BackgammonAIScript.new()
	var plan: Array = ai.choose_turn(game, 4)
	_expect(not plan.is_empty(), "AI returns a turn plan")
	var candidate: Dictionary = {}
	for item in plan:
		if int(item.get("source", -99)) >= -1:
			candidate = item
			break
	var authorized: bool = false
	if not candidate.is_empty():
		for move in game._bg_legal_moves_for_die(1, int(candidate.get("die", -1))):
			if int(move.source) == int(candidate.source) and int(move.target) == int(candidate.target):
				authorized = true
				break
	_expect(authorized, "AI first action is individually legal")
	_expect(game.bg_points == before.points and game.bg_bar == before.bar and game.bg_off == before.off, "AI search leaves the live board unchanged")

func _test_ai_bar_and_home_board_heuristics() -> void:
	var game = _new_game().game
	var ai = BackgammonAIScript.new()
	var points: Array = _empty_points()
	points[6] = 1
	points[8] = -1
	_set_position(game, points, [0, 0], [0, 0], 1, [2, 4])
	_expect(ai._cpu_can_hit(game, 6) == 1, "CPU recognizes a direct hit opportunity when its bar is empty")
	game.bg_bar[1] = 1
	_expect(ai._cpu_can_hit(game, 6) == 0, "CPU does not overvalue on-board hits while it must enter from the bar")
	game.bg_bar = [1, 0]
	_expect(ai._human_can_hit(game, 8) == 0, "human hit threat is suppressed while the human must enter from the bar")

	points = _empty_points()
	points[18] = -2
	_set_position(game, points, [1, 0], [0, 0], 1, [2, 4])
	var block_score: float = ai._home_board_block_score(game)
	_expect(block_score > 0.0, "CPU made points on human entry board are valued when human has a checker on bar")
	points = _empty_points()
	points[2] = 2
	_set_position(game, points, [0, 1], [0, 0], 1, [2, 4])
	block_score = ai._home_board_block_score(game)
	_expect(block_score < 0.0, "human made points blocking CPU entry are penalized when CPU has a checker on bar")
