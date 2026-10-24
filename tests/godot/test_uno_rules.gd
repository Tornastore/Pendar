extends SceneTree
## UNO regression tests for challengeable Wild Draw Four, turn guards and action cards.

const UnoRulesScript = preload("res://games/uno/rules.gd")

class MockApp extends Node2D:
	var vs_cpu: bool = false
	var local_seat: int = 0
	var online_username: String = ""
	var online_player_roster: Array = []
	var result_calls: int = 0
	var rebuild_calls: int = 0
	var toasts: Array[String] = []
	var is_host: bool = true
	var ws_match_active: bool = false
	var _result_logged: bool = false
	var _result_popup_open: bool = false
	var _game_epoch: int = 0
	var _cpu_pending: bool = false
	var state: int = 4

	func _my_seat() -> int:
		return local_seat

	func _net_on() -> bool:
		return false

	func _is_my_turn() -> bool:
		return true

	func _rebuild_buttons() -> void:
		rebuild_calls += 1

	func _show_toast(message: String) -> void:
		toasts.append(message)

	func _go_result(_won: bool = false) -> void:
		result_calls += 1

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

func _new_game(player_count: int = 4) -> Dictionary:
	var host := MockApp.new()
	root.add_child(host)
	_hosts.append(host)
	var game = UnoRulesScript.new()
	game.bind(host, "uno")
	game.uno_player_count = player_count
	game.reset_game()
	return {"game": game, "host": host}

func _card(color_id: int, kind: String, value: int = 0) -> Dictionary:
	return {"c": color_id, "k": kind, "v": value}

func _fill_cards(game, count: int) -> Array:
	var cards: Array = []
	for i in range(count):
		cards.append(game._uno_make_card(i % 4, "num", (i % 9) + 1))
	return cards

func _configure(game, hands: Array, top: Dictionary, current_color: int, draw_cards: Array, turn: int = 0) -> void:
	game.uno_player_count = hands.size()
	game.uno_hands = hands.duplicate(true)
	game.uno_draw_pile = draw_cards.duplicate(true)
	game.uno_discard_pile = [top.duplicate(true)]
	game.uno_scores = []
	for _i in range(hands.size()):
		game.uno_scores.append(0)
	game.uno_turn = turn
	game.uno_direction = 1
	game.uno_current_color = current_color
	game.uno_game_over = false
	game.uno_round_over = false
	game.uno_winner = -1
	game.uno_round_winner = -1
	game.uno_last_round_points = 0
	game.uno_selected_card = -1
	game.uno_hand_page = 0
	game.uno_pending_color = -1
	game.uno_challenge_available = false
	game.uno_challenge_target = -1
	game.uno_last_wild4_actor = -1
	game.uno_last_wild4_illegal = false
	game.uno_pending_round_winner = -1
	game.uno_catch_seat = -1
	game.uno_drawn_card_index = -1
	game.uno_last_action = ""
	game.uno_status = ""
	game.uno_round_started_msec = Time.get_ticks_msec()

func _run_tests() -> void:
	_test_deck_and_deal_invariants()
	_test_wild4_bluff_can_be_challenged()
	_test_legal_wild4_failed_challenge_penalty()
	_test_only_one_draw_per_turn()
	_test_two_player_reverse_and_skip()
	print("UNO_RULES_TESTS: checks=%d, failures=%d" % [_checks, _failures])
	for host in _hosts:
		if is_instance_valid(host):
			host.free()
	quit(1 if _failures > 0 else 0)

func _test_deck_and_deal_invariants() -> void:
	var game = _new_game(4).game
	var deck: Array = game._uno_make_deck()
	var colored_counts: Array[int] = [0, 0, 0, 0]
	var wild_count: int = 0
	var wild4_count: int = 0
	for card in deck:
		var color_id: int = int(card.c)
		if color_id >= 0 and color_id < 4:
			colored_counts[color_id] += 1
		if str(card.k) == "wild":
			wild_count += 1
		elif str(card.k) == "wild4":
			wild4_count += 1
	_expect(deck.size() == 112, "classic UNO deck includes 112 standard and blank-as-Wild cards")
	_expect(colored_counts == [25, 25, 25, 25], "each color has 25 colored number/action cards")
	_expect(wild_count == 8 and wild4_count == 4, "four Wild and four Wild Draw Four cards plus four blank-as-Wild cards")
	for hand in game.uno_hands:
		_expect(hand.size() == 7, "every player receives seven opening cards")
	var total: int = game.uno_draw_pile.size() + game.uno_discard_pile.size()
	for hand in game.uno_hands:
		total += hand.size()
	_expect(total == 112, "all cards remain accounted for after dealing and opening-card reveal")

func _test_wild4_bluff_can_be_challenged() -> void:
	var ctx: Dictionary = _new_game(2)
	var game = ctx.game
	var actor_hand: Array = [_card(-1, "wild4"), _card(0, "num", 5)]
	var opponent_hand: Array = [_card(1, "num", 3)]
	_configure(game, [actor_hand, opponent_hand], _card(0, "num", 2), 0, _fill_cards(game, 12))
	_expect(not game._uno_is_wild4_legal(0, 0), "Wild Draw Four is marked illegal if the player holds a matching color")
	_expect(game._uno_is_playable(game.uno_hands[0][0], 0), "an illegal Wild Draw Four bluff is still available to challenge")
	_expect(game._uno_apply_play(0, 0, 2, false), "Wild Draw Four bluff can be played for challenge resolution")
	_expect(game.uno_challenge_available and game.uno_last_wild4_illegal and game.uno_challenge_target == 1, "illegal Wild Draw Four exposes the correct challenge target")
	game._uno_apply_challenge(1, true)
	_expect(not game.uno_challenge_available and game.uno_turn == 1, "successful challenge returns turn to challenger")
	_expect(game.uno_hands[0].size() == 5, "successful challenge makes the illegal player draw four cards")

func _test_legal_wild4_failed_challenge_penalty() -> void:
	var ctx: Dictionary = _new_game(2)
	var game = ctx.game
	_configure(game, [[_card(-1, "wild4"), _card(1, "num", 5)], [_card(2, "num", 3)]], _card(0, "num", 2), 0, _fill_cards(game, 12))
	_expect(game._uno_is_wild4_legal(0, 0), "Wild Draw Four is legal when player has no card of the active color")
	_expect(game._uno_apply_play(0, 0, 2, true), "legal Wild Draw Four is accepted")
	var before: int = game.uno_hands[1].size()
	game._uno_apply_challenge(1, true)
	_expect(game.uno_hands[1].size() == before + 6, "unsuccessful challenge draws six cards for challenger")
	_expect(not game.uno_challenge_available and game.uno_turn == 0, "failed challenge advances turn after penalty")

func _test_only_one_draw_per_turn() -> void:
	var ctx: Dictionary = _new_game(2)
	var game = ctx.game
	_configure(game, [[_card(1, "num", 4)], [_card(2, "num", 3)]], _card(0, "num", 2), 0, [_card(1, "num", 5), _card(0, "num", 8)])
	game._uno_apply_draw(0)
	_expect(game.uno_drawn_card_index == 1 and game.uno_hands[0].size() == 2, "drawing a playable card keeps the turn open for that card")
	var hand_before: int = game.uno_hands[0].size()
	var pile_before: int = game.uno_draw_pile.size()
	game._uno_apply_draw(0)
	_expect(game.uno_hands[0].size() == hand_before and game.uno_draw_pile.size() == pile_before, "second draw in the same turn is rejected without mutation")
	game._uno_apply_pass(0)
	_expect(game.uno_turn == 1 and game.uno_drawn_card_index == -1, "passing after the drawn card ends the turn and clears draw marker")

func _test_two_player_reverse_and_skip() -> void:
	var ctx: Dictionary = _new_game(2)
	var game = ctx.game
	_configure(game, [[_card(0, "reverse"), _card(1, "num", 4)], [_card(2, "num", 2)]], _card(0, "num", 6), 0, _fill_cards(game, 8))
	_expect(game._uno_apply_play(0, 0, -1, true), "two-player Reverse action is accepted")
	_expect(game.uno_direction == -1 and game.uno_turn == 0, "Reverse acts like Skip in a two-player hand")
	_configure(game, [[_card(0, "skip"), _card(1, "num", 4)], [_card(2, "num", 2)], [_card(3, "num", 7)]], _card(0, "num", 6), 0, _fill_cards(game, 8))
	_expect(game._uno_apply_play(0, 0, -1, true), "Skip action is accepted")
	_expect(game.uno_turn == 2, "Skip bypasses exactly the next player")
