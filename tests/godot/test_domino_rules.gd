extends SceneTree
## Headless regression tests for domino legal actions and turn guards.

const DominoRulesScript = preload("res://games/domino/rules.gd")

class MockApp extends Node2D:
	var result_calls: int = 0
	var toasts: Array[String] = []
	var vs_cpu: bool = false
	var local_seat: int = 0

	func _go_result() -> void:
		result_calls += 1

	func _show_toast(message: String) -> void:
		toasts.append(message)

	func _net_on() -> bool:
		return false

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
	var game = DominoRulesScript.new()
	game.bind(host, "domino")
	game.reset_game()
	return {"game": game, "host": host}

func _configure(game, host) -> void:
	game.dom_hands = [[Vector2i(2, 5), Vector2i(0, 0)], [Vector2i(3, 6)]]
	game.dom_boneyard = []
	game.dom_chain = [Vector2i(2, 3)]
	game.dom_left = 2
	game.dom_right = 3
	game.dom_turn = 0
	game.dom_game_over = false
	game.dom_winner = -1
	game.dom_selected = -1
	game.dom_scores = [0, 0]
	host.result_calls = 0

func _run_tests() -> void:
	_test_standard_double_six_deal()
	_test_safe_legal_play_and_endpoint_orientation()
	_test_invalid_actions_do_not_mutate_state()
	_test_draw_and_pass_guards()
	print("DOMINO_RULES_TESTS: checks=%d, failures=%d" % [_checks, _failures])
	for host in _hosts:
		if is_instance_valid(host):
			host.free()
	quit(1 if _failures > 0 else 0)

func _test_standard_double_six_deal() -> void:
	var game = _new_game().game
	_expect(game.dom_chain.size() == 1, "new game starts with one table tile")
	_expect(game.dom_hands[0].size() + game.dom_hands[1].size() == 13, "opening tile is removed from the starter's seven-tile hand")
	_expect(game.dom_hands[0].size() <= 7 and game.dom_hands[1].size() <= 7, "neither hand exceeds the seven-tile deal")
	_expect(game.dom_boneyard.size() == 14, "double-six boneyard contains fourteen tiles after dealing and starter")
	var seen: Dictionary = {}
	for tile in game.dom_chain + game.dom_hands[0] + game.dom_hands[1] + game.dom_boneyard:
		var key: String = "%d-%d" % [mini(tile.x, tile.y), maxi(tile.x, tile.y)]
		seen[key] = true
	_expect(seen.size() == 28, "all 28 double-six tiles are unique")

func _test_safe_legal_play_and_endpoint_orientation() -> void:
	var ctx: Dictionary = _new_game()
	var game = ctx.game
	_configure(game, ctx.host)
	_expect(game._dom_can_play(Vector2i(2, 5), "L"), "matching left endpoint is playable")
	_expect(game._dom_can_play(Vector2i(3, 6), "R"), "matching right endpoint is playable")
	_expect(not game._dom_can_play(Vector2i(2, 5), "X"), "unknown endpoint labels are rejected")
	_expect(game._dom_play(0, 0, "L"), "legal left-side tile is accepted")
	_expect(game.dom_chain[0] == Vector2i(5, 2), "left tile is flipped to preserve chain matching")
	_expect(game.dom_left == 5 and game.dom_right == 3, "only the chosen chain endpoint changes")
	_expect(game.dom_turn == 1, "legal play advances turn once")

func _test_invalid_actions_do_not_mutate_state() -> void:
	var ctx: Dictionary = _new_game()
	var game = ctx.game
	_configure(game, ctx.host)
	var original_chain: Array = game.dom_chain.duplicate()
	var original_hand: Array = game.dom_hands[0].duplicate()
	_expect(not game._dom_play(1, 0, "R"), "out-of-turn tile play is rejected")
	_expect(not game._dom_play(0, -1, "L"), "negative hand index is rejected")
	_expect(not game._dom_play(0, 99, "L"), "out-of-range hand index is rejected")
	_expect(not game._dom_play(0, 0, "X"), "invalid endpoint action is rejected")
	_expect(game.dom_chain == original_chain and game.dom_hands[0] == original_hand, "invalid plays leave board and hand unchanged")
	game.dom_game_over = true
	_expect(not game._dom_play(0, 0, "L"), "play after game end is rejected")

func _test_draw_and_pass_guards() -> void:
	var ctx: Dictionary = _new_game()
	var game = ctx.game
	_configure(game, ctx.host)
	game.dom_boneyard = [Vector2i(4, 6)]
	var hand_count: int = game.dom_hands[0].size()
	game._dom_draw(1)
	_expect(game.dom_hands[1].size() == 1, "opponent cannot draw out of turn")
	game.dom_hands[0] = [Vector2i(2, 4)]
	game._dom_draw(0)
	_expect(game.dom_hands[0].size() == 1 and game.dom_boneyard.size() == 1, "player cannot draw while a legal play exists")
	game.dom_hands[0] = [Vector2i(4, 5)]
	game.dom_hands[1] = [Vector2i(3, 6)]
	game._dom_pass(0)
	_expect(game.dom_turn == 0 and not game.dom_game_over, "passing is rejected while boneyard has tiles")
	game._dom_draw(0)
	_expect(game.dom_boneyard.is_empty() and game.dom_hands[0].size() == 2, "blocked player may draw when no tile is playable")
	game._dom_pass(0)
	_expect(game.dom_turn == 1 and not game.dom_game_over, "pass advances to opponent when opponent still has a legal play")
	game.dom_hands[1] = [Vector2i(4, 6)]
	game._dom_pass(1)
	_expect(game.dom_game_over, "game ends when both players are blocked and boneyard is empty")
	_expect(ctx.host.result_calls == 1, "blocked game publishes the result exactly once")
