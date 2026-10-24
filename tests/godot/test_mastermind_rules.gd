extends SceneTree
## Headless regression tests for Mastermind feedback, input validation and online secret privacy.

const MastermindRulesScript = preload("res://games/mastermind/rules.gd")

class MockApp extends Node2D:
	var vs_cpu: bool = false
	var selected_game: String = "mastermind"
	var ws_match_active: bool = false
	var connected_players: int = 1
	var is_host: bool = true
	var local_seat: int = 0
	var result_requested: bool = false
	var rebuild_count: int = 0
	var toast_text: String = ""

	func _net_on() -> bool:
		return false

	func _fa(value) -> String:
		return str(value)

	func _my_seat() -> int:
		return local_seat

	func _go_result(_won: bool = false) -> void:
		result_requested = true

	func _build_playing_buttons() -> void:
		rebuild_count += 1

	func _show_toast(message: String) -> void:
		toast_text = message

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
	var game = MastermindRulesScript.new()
	game.bind(host, "mastermind")
	game.reset_game()
	return {"app": host, "game": game}

func _run_tests() -> void:
	_test_feedback_with_duplicate_colours()
	_test_invalid_guess_is_ignored()
	_test_correct_guess_finishes_once()
	_test_online_race_keeps_secret_off_client()
	_test_difficulty_limits_and_selection_state()
	print("MASTERMIND_RULES_TESTS: checks=%d, failures=%d" % [_checks, _failures])
	for host in _hosts:
		if is_instance_valid(host):
			host.free()
	quit(1 if _failures > 0 else 0)

func _test_feedback_with_duplicate_colours() -> void:
	var fixture: Dictionary = _new_game()
	var game = fixture["game"]
	game.mm_code_len = 4
	game.mm_color_count = 6
	game.mm_secret = [0, 0, 1, 2]
	var feedback: Array = game._mm_feedback([0, 1, 0, 0])
	_expect(feedback == [2, 1, 1, 0], "feedback counts duplicate colours only once")
	_expect(game._mm_evaluate([0, 1, 0, 0]) == [1, 2], "feedback aggregate counts exact and misplaced colours")

func _test_invalid_guess_is_ignored() -> void:
	var fixture: Dictionary = _new_game()
	var game = fixture["game"]
	game.mm_code_len = 4
	game.mm_color_count = 6
	game.mm_secret = [0, 1, 2, 3]
	game._mm_apply([0, 1, 2, 99], 0)
	_expect(game.mm_guesses.is_empty(), "out-of-range colour guess is rejected")
	_expect(not game.mm_game_over, "invalid guess cannot end the game")

func _test_correct_guess_finishes_once() -> void:
	var fixture: Dictionary = _new_game()
	var game = fixture["game"]
	var host: MockApp = fixture["app"]
	game.mm_code_len = 4
	game.mm_color_count = 6
	game.mm_secret = [1, 2, 3, 4]
	game._mm_apply([1, 2, 3, 4], 0)
	_expect(game.mm_game_over and game.mm_winner == 0 and game.mm_won, "correct code ends game with the right winner")
	_expect(host.result_requested, "correct code opens result overlay")
	_expect(game.mm_guesses.size() == 1, "winning guess is recorded exactly once")

func _test_online_race_keeps_secret_off_client() -> void:
	var fixture: Dictionary = _new_game()
	var game = fixture["game"]
	var host: MockApp = fixture["app"]
	host.ws_match_active = true
	host.selected_game = "mastermind"
	game.reset_game()
	_expect(game.mm_online_race, "online Mastermind race mode is recognized")
	_expect(game.mm_secret.is_empty(), "online client-side game state never receives the secret")
	_expect(game.mm_phase == 1, "online race starts in guess phase")

func _test_difficulty_limits_and_selection_state() -> void:
	var fixture: Dictionary = _new_game()
	var game = fixture["game"]
	game.mm_difficulty = 4
	game.reset_game()
	_expect(game.mm_code_len == 7 and game.mm_color_count == 7, "difficulty scales code and palette consistently")
	game.mm_slot = 0
	game.mm_filled = game._mm_blank_filled()
	game.mm_cur = game._mm_blank_code()
	game._mm_pick(3)
	_expect(game.mm_filled[0] and game.mm_cur[0] == 3, "colour selection fills the current guess slot")
	_expect(game.mm_slot == 1, "colour selection advances to the next empty slot")
