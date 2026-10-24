extends "res://core/game_module.gd"
## Classic UNO (112-card deck; four blank/customizable cards default to standard Wilds).
## 2-10 players, 7 cards each, points from opponents' remaining cards, first to 500 wins.

const UnoPresentationScript = preload("res://games/uno/presentation.gd")
var _uno_presentation = UnoPresentationScript.new()

var uno_player_count: int = 4
var uno_difficulty: int = 3
var uno_hands: Array = []
var uno_draw_pile: Array = []
var uno_discard_pile: Array = []
var uno_scores: Array = []
var uno_turn: int = 0
var uno_direction: int = 1
var uno_current_color: int = 0
var uno_game_over: bool = false
var uno_round_over: bool = false
var uno_winner: int = -1
var uno_round_winner: int = -1
var uno_last_round_points: int = 0
var uno_round_number: int = 1
var uno_round_duration_seconds: float = 0.0
var uno_round_started_msec: int = 0
var uno_selected_card: int = -1
var uno_hand_page: int = 0
var uno_pending_color: int = -1
var uno_challenge_available: bool = false
var uno_challenge_target: int = -1
var uno_last_wild4_actor: int = -1
var uno_last_wild4_illegal: bool = false
var uno_pending_round_winner: int = -1
var uno_catch_seat: int = -1
var uno_drawn_card_index: int = -1
var uno_last_action: String = ""
var uno_status: String = ""

func reset_game() -> void:
	_uno_reset_match()

func _uno_reset_match() -> void:
	uno_player_count = clampi(uno_player_count, 2, 10)
	uno_scores = []
	for _i in range(uno_player_count):
		uno_scores.append(0)
	uno_round_number = 1
	_uno_reset_round(false)

func _uno_make_card(color_id: int, kind: String, value: int = 0) -> Dictionary:
	return {"c": color_id, "k": kind, "v": value}

func _uno_make_deck() -> Array:
	var deck: Array = []
	for c in range(4):
		deck.append(_uno_make_card(c, "num", 0))
		for n in range(1, 10):
			deck.append(_uno_make_card(c, "num", n))
			deck.append(_uno_make_card(c, "num", n))
		for _i in range(2):
			deck.append(_uno_make_card(c, "skip"))
			deck.append(_uno_make_card(c, "reverse"))
			deck.append(_uno_make_card(c, "draw2"))
	for _i in range(4):
		deck.append(_uno_make_card(-1, "wild"))
		deck.append(_uno_make_card(-1, "wild4"))
		deck.append(_uno_make_card(-1, "wild")) # blank/custom cards default to ordinary Wild
	deck.shuffle()
	return deck

func _uno_reset_round(preserve_scores: bool = true) -> void:
	uno_player_count = clampi(uno_player_count, 2, 10)
	if not preserve_scores or uno_scores.size() != uno_player_count:
		uno_scores = []
		for _i in range(uno_player_count):
			uno_scores.append(0)
	uno_hands = []
	for _i in range(uno_player_count):
		uno_hands.append([])
	uno_draw_pile = _uno_make_deck()
	uno_discard_pile = []
	uno_turn = 0
	uno_direction = 1
	uno_current_color = randi_range(0, 3)
	uno_game_over = false
	uno_round_over = false
	uno_winner = -1
	uno_round_winner = -1
	uno_last_round_points = 0
	uno_selected_card = -1
	uno_hand_page = 0
	uno_pending_color = -1
	uno_challenge_available = false
	uno_challenge_target = -1
	uno_last_wild4_actor = -1
	uno_last_wild4_illegal = false
	uno_pending_round_winner = -1
	uno_catch_seat = -1
	uno_drawn_card_index = -1
	uno_last_action = ""
	uno_round_started_msec = Time.get_ticks_msec()
	for _card in range(7):
		for seat in range(uno_player_count):
			uno_hands[seat].append(uno_draw_pile.pop_back())
	# Current Mattel UNO instructions: if an Action Card is revealed to start,
	# ignore it and reveal another card. Keep ignored actions below the active top card.
	var opening: Dictionary = uno_draw_pile.pop_back()
	while str(opening.get("k", "num")) != "num":
		uno_discard_pile.append(opening)
		if uno_draw_pile.is_empty():
			_uno_refill_draw()
		if uno_draw_pile.is_empty():
			break
		opening = uno_draw_pile.pop_back()
	uno_discard_pile.append(opening)
	uno_current_color = int(opening.get("c", 0))
	var dealer: int = randi_range(0, uno_player_count - 1)
	uno_turn = _uno_next_seat(dealer)
	uno_status = "دور %s · نخستین نوبت" % str(uno_round_number)
	if app != null:
		app._rebuild_buttons()

func _uno_next_seat(seat: int, steps: int = 1) -> int:
	if uno_player_count <= 0:
		return 0
	var out: int = seat
	for _i in range(steps):
		out = posmod(out + uno_direction, uno_player_count)
	return out

func _uno_card_kind(card: Dictionary) -> String:
	return str(card.get("k", "num"))

func _uno_card_color(card: Dictionary) -> int:
	return int(card.get("c", -1))

func _uno_card_value(card: Dictionary) -> int:
	return int(card.get("v", 0))

func _uno_top_card() -> Dictionary:
	if uno_discard_pile.is_empty():
		return _uno_make_card(uno_current_color, "num", 0)
	return uno_discard_pile[uno_discard_pile.size() - 1]

func _uno_card_label(card: Dictionary) -> String:
	match _uno_card_kind(card):
		"num": return str(_uno_card_value(card))
		"skip": return "ممنوع"
		"reverse": return "برعکس"
		"draw2": return "+۲"
		"wild": return "وایلد"
		"wild4": return "+۴"
	return "کارت"

func _uno_card_points(card: Dictionary) -> int:
	match _uno_card_kind(card):
		"num": return _uno_card_value(card)
		"skip", "reverse", "draw2": return 20
		"wild", "wild4": return 50
	return 0

func _uno_refill_draw() -> void:
	if uno_draw_pile.size() > 0 or uno_discard_pile.size() <= 1:
		return
	var top: Dictionary = uno_discard_pile.pop_back()
	uno_draw_pile = uno_discard_pile.duplicate()
	uno_draw_pile.shuffle()
	uno_discard_pile = [top]

func _uno_draw_cards(seat: int, amount: int) -> void:
	for _i in range(amount):
		_uno_refill_draw()
		if uno_draw_pile.is_empty():
			return
		uno_hands[seat].append(uno_draw_pile.pop_back())

func _uno_is_playable(card: Dictionary, seat: int) -> bool:
	var kind: String = _uno_card_kind(card)
	# A Wild Draw Four may be played as a bluff so the next player can challenge it.
	# Whether it was legal is recorded separately in _uno_is_wild4_legal().
	if kind in ["wild", "wild4"]:
		return true
	if _uno_card_color(card) == uno_current_color:
		return true
	var top: Dictionary = _uno_top_card()
	return (_uno_card_kind(card) == _uno_card_kind(top) and kind != "wild4") or (kind == "num" and _uno_card_kind(top) == "num" and _uno_card_value(card) == _uno_card_value(top))

func _uno_is_wild4_legal(seat: int, card_index: int = -1) -> bool:
	if seat < 0 or seat >= uno_hands.size():
		return false
	for i in range(uno_hands[seat].size()):
		if i == card_index:
			continue
		var held: Dictionary = uno_hands[seat][i]
		if _uno_card_kind(held) not in ["wild", "wild4"] and _uno_card_color(held) == uno_current_color:
			return false
	return true

func _uno_playable_indices(seat: int) -> Array[int]:
	var result: Array[int] = []
	if seat < 0 or seat >= uno_hands.size():
		return result
	for i in range(uno_hands[seat].size()):
		if _uno_is_playable(uno_hands[seat][i], seat):
			result.append(i)
	return result

func _uno_is_local_turn() -> bool:
	if uno_game_over or uno_round_over:
		return false
	if app.vs_cpu:
		return uno_turn == 0
	return app._is_my_turn()

func _uno_selected_is_wild() -> bool:
	var seat: int = app._my_seat()
	return uno_selected_card >= 0 and seat < uno_hands.size() and uno_selected_card < uno_hands[seat].size() and _uno_card_kind(uno_hands[seat][uno_selected_card]) in ["wild", "wild4"]

func _uno_select_card(index: int) -> void:
	if not _uno_is_local_turn() or uno_challenge_available:
		return
	var seat: int = app._my_seat()
	if index < 0 or index >= uno_hands[seat].size():
		return
	if uno_drawn_card_index >= 0 and index != uno_drawn_card_index:
		app._show_toast("پس از کشیدن کارت، فقط همان کارت قابل بازی است.")
		return
	if not _uno_is_playable(uno_hands[seat][index], seat):
		app._show_toast("این کارت با رنگ یا نماد فعلی جور نیست.")
		return
	uno_selected_card = index
	uno_pending_color = -1
	app._rebuild_buttons()

func _uno_submit_play(index: int, chosen_color: int, declared_uno: bool) -> void:
	if not _uno_is_local_turn():
		return
	var seat: int = app._my_seat()
	if index < 0 or index >= uno_hands[seat].size():
		return
	var card: Dictionary = uno_hands[seat][index]
	var kind: String = _uno_card_kind(card)
	if kind in ["wild", "wild4"] and (chosen_color < 0 or chosen_color > 3):
		app._show_toast("رنگ بعدی را انتخاب کنید.")
		return
	var args: Array = [seat, index, chosen_color, declared_uno]
	if app._net_on():
		app._send_game_action("_rpc_uno_play", args)
	else:
		_uno_apply_play(seat, index, chosen_color, declared_uno)

func _uno_draw_request() -> void:
	if not _uno_is_local_turn() or uno_challenge_available or uno_drawn_card_index >= 0:
		return
	var seat: int = app._my_seat()
	if app._net_on():
		app._send_game_action("_rpc_uno_draw", [seat])
	else:
		_uno_apply_draw(seat)

func _uno_pass_request() -> void:
	if not _uno_is_local_turn() or uno_challenge_available:
		return
	var seat: int = app._my_seat()
	if app._net_on():
		app._send_game_action("_rpc_uno_pass", [seat])
	else:
		_uno_apply_pass(seat)

func _uno_catch_request() -> void:
	if not _uno_is_local_turn() or uno_catch_seat < 0:
		return
	var seat: int = app._my_seat()
	if app._net_on():
		app._send_game_action("_rpc_uno_catch", [seat])
	else:
		_uno_apply_catch(seat)

func _uno_challenge_request(challenge: bool) -> void:
	if not _uno_is_local_turn() or not uno_challenge_available:
		return
	var seat: int = app._my_seat()
	if app._net_on():
		app._send_game_action("_rpc_uno_challenge", [seat, challenge])
	else:
		_uno_apply_challenge(seat, challenge)

func _uno_apply_play(seat: int, index: int, chosen_color: int, declared_uno: bool) -> bool:
	if uno_game_over or uno_round_over or uno_challenge_available or seat != uno_turn:
		return false
	if seat < 0 or seat >= uno_hands.size() or index < 0 or index >= uno_hands[seat].size():
		return false
	var card: Dictionary = uno_hands[seat][index]
	if uno_drawn_card_index >= 0 and seat == uno_turn and index != uno_drawn_card_index:
		return false
	if not _uno_is_playable(card, seat):
		return false
	var kind: String = _uno_card_kind(card)
	var legal_wild4: bool = _uno_is_wild4_legal(seat, index) if kind == "wild4" else true
	if kind in ["wild", "wild4"] and chosen_color not in range(4):
		return false
	uno_hands[seat].remove_at(index)
	uno_discard_pile.append(card)
	# Keep the hand-page index valid after the number of cards shrinks.
	var max_hand_page: int = int(maxi(0, uno_hands[seat].size() - 1) / 7)
	uno_hand_page = mini(uno_hand_page, max_hand_page)
	uno_selected_card = -1
	uno_pending_color = -1
	uno_drawn_card_index = -1
	uno_catch_seat = -1
	uno_last_action = "%s کارت %s بازی کرد" % [_uno_player_name(seat), _uno_card_label(card)]
	if kind in ["wild", "wild4"]:
		uno_current_color = chosen_color
	else:
		uno_current_color = _uno_card_color(card)
	var next_seat: int = _uno_next_seat(seat)
	match kind:
		"skip":
			uno_turn = _uno_next_seat(next_seat)
		"reverse":
			uno_direction *= -1
			uno_turn = seat if uno_player_count == 2 else _uno_next_seat(seat)
		"draw2":
			_uno_draw_cards(next_seat, 2)
			uno_turn = _uno_next_seat(next_seat)
		"wild4":
			uno_last_wild4_actor = seat
			uno_last_wild4_illegal = not legal_wild4
			uno_challenge_available = true
			uno_challenge_target = next_seat
			uno_turn = next_seat
			uno_pending_round_winner = seat if uno_hands[seat].is_empty() else -1
		_:
			uno_turn = next_seat
	if uno_hands[seat].size() == 1 and not declared_uno:
		uno_catch_seat = seat
	if uno_hands[seat].size() != 1:
		uno_catch_seat = -1
	if kind != "wild4" and uno_hands[seat].is_empty():
		if kind == "draw2":
			_uno_finish_round(seat)
		else:
			_uno_finish_round(seat)
	elif kind == "wild4" and uno_hands[seat].is_empty():
		uno_pending_round_winner = seat
	app._rebuild_buttons()
	return true

func _uno_apply_draw(seat: int) -> void:
	# Once a playable card has been drawn, UNO permits playing that card or passing,
	# not drawing repeatedly. Keep this guard in the rules path as well as the UI.
	if uno_game_over or uno_round_over or uno_challenge_available or seat != uno_turn or uno_drawn_card_index >= 0:
		return
	uno_catch_seat = -1
	uno_selected_card = -1
	uno_pending_color = -1
	_uno_refill_draw()
	if uno_draw_pile.is_empty():
		uno_status = "دسته خالی است؛ نوبت رد شد."
		_uno_advance_turn(seat)
		return
	uno_hands[seat].append(uno_draw_pile.pop_back())
	uno_drawn_card_index = uno_hands[seat].size() - 1
	uno_last_action = "%s یک کارت برداشت" % _uno_player_name(seat)
	if not _uno_is_playable(uno_hands[seat][uno_drawn_card_index], seat):
		uno_drawn_card_index = -1
		uno_status = "کارت قابل بازی نبود؛ نوبت رد شد."
		_uno_advance_turn(seat)
	else:
		# If a long hand is paginated, immediately show the newly drawn playable card.
		uno_hand_page = int(uno_drawn_card_index / 7)
		uno_status = "اگر کارت کشیده‌شده قابل بازی است، می‌توانید همان کارت را بازی کنید یا نوبت را رد کنید."
	app._rebuild_buttons()

func _uno_apply_pass(seat: int) -> void:
	if uno_game_over or uno_round_over or uno_challenge_available or seat != uno_turn or uno_drawn_card_index < 0:
		return
	uno_drawn_card_index = -1
	uno_catch_seat = -1
	uno_status = "نوبت رد شد."
	_uno_advance_turn(seat)

func _uno_advance_turn(seat: int) -> void:
	uno_turn = _uno_next_seat(seat)
	uno_selected_card = -1
	uno_pending_color = -1
	uno_drawn_card_index = -1
	app._rebuild_buttons()

func _uno_apply_catch(seat: int) -> void:
	if uno_game_over or uno_round_over or uno_challenge_available or seat != uno_turn or uno_catch_seat < 0 or uno_catch_seat == seat:
		return
	_uno_draw_cards(uno_catch_seat, 2)
	uno_last_action = "%s اعلام UNO حریف را گرفت؛ ۲ کارت جریمه" % _uno_player_name(seat)
	uno_catch_seat = -1
	app._rebuild_buttons()

func _uno_apply_challenge(seat: int, challenge: bool) -> void:
	if uno_game_over or uno_round_over or not uno_challenge_available or seat != uno_turn or seat != uno_challenge_target:
		return
	var actor: int = uno_last_wild4_actor
	var illegal: bool = uno_last_wild4_illegal
	uno_challenge_available = false
	uno_challenge_target = -1
	if challenge and illegal:
		_uno_draw_cards(actor, 4)
		uno_pending_round_winner = -1
		uno_turn = seat
		uno_status = "چالش موفق بود؛ بازیکن کارت +۴ را غیرقانونی بازی کرده بود."
	elif challenge:
		_uno_draw_cards(seat, 6)
		uno_turn = _uno_next_seat(seat)
		uno_status = "چالش ناموفق بود؛ ۶ کارت جریمه گرفتید."
		if uno_pending_round_winner >= 0:
			_uno_finish_round(uno_pending_round_winner)
	else:
		_uno_draw_cards(seat, 4)
		uno_turn = _uno_next_seat(seat)
		uno_status = "۴ کارت برداشتید و نوبت رد شد."
		if uno_pending_round_winner >= 0:
			_uno_finish_round(uno_pending_round_winner)
	uno_last_action = uno_status
	app._rebuild_buttons()

func _uno_finish_round(winner: int) -> void:
	if uno_round_over or uno_game_over or winner < 0 or winner >= uno_player_count:
		return
	var points: int = 0
	for seat in range(uno_player_count):
		if seat == winner:
			continue
		for card in uno_hands[seat]:
			points += _uno_card_points(card)
	uno_scores[winner] = int(uno_scores[winner]) + points
	uno_last_round_points = points
	uno_round_winner = winner
	uno_winner = winner
	uno_round_duration_seconds = maxf(1.0, float(Time.get_ticks_msec() - uno_round_started_msec) / 1000.0)
	uno_round_over = true
	if int(uno_scores[winner]) >= 500:
		uno_game_over = true
		uno_status = "%s به ۵۰۰ امتیاز رسید و مسابقه را برد." % _uno_player_name(winner)
	else:
		uno_status = "%s این دست را برد و %s امتیاز گرفت." % [_uno_player_name(winner), points]
	app._go_result(false)

func _uno_next_round_request() -> void:
	if not uno_round_over or uno_game_over:
		return
	if not (app.vs_cpu or app.is_host or not app._net_on()):
		app._show_toast("منتظر میزبان برای شروع دست بعدی بمانید.")
		return
	var rng_seed: int = randi_range(1, 2147483646)
	if app.ws_match_active:
		app._send_game_action("_rpc_uno_next_round", [0, rng_seed])
	elif app.multiplayer.multiplayer_peer != null:
		app.rpc("_rpc_uno_next_round", 0, rng_seed)
	else:
		_uno_begin_next_round(rng_seed)

func _uno_begin_next_round(rng_seed: int) -> void:
	seed(rng_seed)
	uno_round_number += 1
	_uno_reset_round(true)
	app._result_logged = false
	app._result_popup_open = false
	app._game_epoch += 1
	app._cpu_pending = false
	app.state = 4 # Main.State.PLAYING
	app._rebuild_buttons()

func _uno_cpu_turn() -> void:
	if not app.vs_cpu or uno_game_over or uno_round_over or uno_turn <= 0 or uno_turn >= uno_player_count:
		return
	var seat: int = uno_turn
	if uno_challenge_available:
		# The local CPU has full game state, so it can determine whether +4 was illegal.
		_uno_apply_challenge(seat, uno_last_wild4_illegal)
		return
	var playable := _uno_playable_indices(seat)
	if playable.is_empty():
		_uno_apply_draw(seat)
		if uno_turn != seat or uno_round_over:
			return
		if uno_drawn_card_index >= 0:
			var drawn: Dictionary = uno_hands[seat][uno_drawn_card_index]
			if _uno_is_playable(drawn, seat):
				_uno_cpu_play(seat, [uno_drawn_card_index])
			else:
				_uno_apply_pass(seat)
		return
	_uno_cpu_play(seat, playable)

func _uno_cpu_play(seat: int, options: Array) -> void:
	if options.is_empty():
		return
	var best_index: int = int(options[0])
	var best_score: float = -INF
	for raw in options:
		var idx: int = int(raw)
		var card: Dictionary = uno_hands[seat][idx]
		var kind := _uno_card_kind(card)
		var score: float = randf_range(-4.0, 4.0) if uno_difficulty == 1 else 0.0
		# Emptying a hand wins immediately, so always reward the direct win.
		if uno_hands[seat].size() == 1:
			score += 10000.0
		var next_seat: int = _uno_next_seat(seat)
		var next_count: int = uno_hands[next_seat].size()
		if kind == "num":
			score += float(_uno_card_value(card)) * (0.5 if uno_difficulty <= 2 else 1.1)
			score += float(_uno_count_color(seat, _uno_card_color(card))) * (1.2 + uno_difficulty * 0.45)
		elif kind in ["skip", "reverse", "draw2"]:
			score += 3.0 + uno_difficulty * 1.2
			if next_count <= 2:
				score += 12.0 + (3 - next_count) * 3.0
		if kind == "wild":
			score += 1.0
			for c in range(4):
				score += float(_uno_count_color(seat, c)) * (0.7 + uno_difficulty * 0.35)
		if kind == "wild4":
			score += 3.0 + uno_difficulty * 1.4
			if next_count <= 2:
				score += 18.0
			if not _uno_is_wild4_legal(seat, idx):
				# An opponent can challenge a bluff; high CPU levels should avoid it
				# unless preventing an almost-certain loss is worth the risk.
				score -= 8.0 if uno_difficulty <= 2 else 22.0
		if uno_difficulty >= 4:
			score += _uno_opponent_pressure(next_seat) * (1.1 if uno_difficulty == 4 else 2.0)
		if uno_difficulty >= 5:
			# Avoid leaving a color that the next player likely can follow.
			var next_color: int = _uno_card_color(card) if _uno_card_color(card) >= 0 else _uno_best_color(seat)
			score -= float(_uno_count_color(seat, next_color)) * 0.9
		if uno_difficulty >= 6:
			# Limited one-ply opponent-response model; no unbounded recursion on the UI thread.
			score -= _uno_estimate_opponent_reply(seat, next_seat, card) * 2.0
		if uno_difficulty == 2:
			score += randf_range(-2.0, 2.0)
		elif uno_difficulty == 3:
			score += randf_range(-0.8, 0.8)
		elif uno_difficulty == 4:
			score += randf_range(-0.25, 0.25)
		elif uno_difficulty >= 5:
			score += randf_range(-0.03, 0.03)
		if score > best_score:
			best_score = score
			best_index = idx
	var picked: Dictionary = uno_hands[seat][best_index]
	var color_choice: int = _uno_card_color(picked)
	if _uno_card_kind(picked) in ["wild", "wild4"]:
		color_choice = _uno_best_color(seat, best_index)
	_uno_apply_play(seat, best_index, color_choice, uno_hands[seat].size() == 2)

func _uno_count_color(seat: int, color_id: int) -> int:
	var total: int = 0
	for card in uno_hands[seat]:
		if _uno_card_color(card) == color_id:
			total += 1
	return total

func _uno_best_color(seat: int, excluding_index: int = -1) -> int:
	var counts: Array[int] = [0, 0, 0, 0]
	for i in range(uno_hands[seat].size()):
		if i == excluding_index:
			continue
		var card: Dictionary = uno_hands[seat][i]
		var c: int = _uno_card_color(card)
		if c >= 0:
			counts[c] += 1
	var best: int = randi_range(0, 3)
	for c in range(4):
		if counts[c] > counts[best]:
			best = c
	return best

func _uno_opponent_pressure(seat: int) -> float:
	if seat < 0 or seat >= uno_hands.size():
		return 0.0
	return maxf(0.0, 7.0 - float(uno_hands[seat].size()))

func _uno_estimate_opponent_reply(seat: int, opponent: int, played: Dictionary) -> float:
	# Hidden opponent cards are not inspected; use only public card count and current color.
	var threat: float = _uno_opponent_pressure(opponent)
	var kind: String = _uno_card_kind(played)
	if kind in ["skip", "reverse", "draw2", "wild4"]:
		threat *= 0.45
	if uno_hands[opponent].size() <= 2:
		threat += 3.0
	return threat

func _uno_player_name(seat: int) -> String:
	if seat == 0 and not app.online_username.is_empty():
		return app.online_username
	if not app.vs_cpu and seat < app.online_player_roster.size():
		for row in app.online_player_roster:
			if int(row.get("seat", -1)) == seat:
				return str(row.get("username", "بازیکن %d" % (seat + 1)))
	return "شما" if seat == 0 else ("CPU %d" % seat if app.vs_cpu else "بازیکن %d" % (seat + 1))

func _btns_uno() -> void:
	_uno_presentation.build_buttons(app, self)

func _uno_board_tap(p: Vector2) -> void:
	_uno_presentation.handle_tap(app, self, p)

func _uno_draw_card_visual(r: Rect2, card: Dictionary, selected: bool = false, small: bool = false) -> void:
	_uno_presentation.draw_card_visual(app, self, r, card, selected, small)

func _draw_uno() -> void:
	_uno_presentation.render(app, self)
