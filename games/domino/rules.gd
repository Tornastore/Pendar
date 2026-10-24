extends "res://core/game_module.gd"
## Rule engine and authoritative state for domino.

const DominoPresentationScript = preload("res://games/domino/presentation.gd")
var _domino_presentation = DominoPresentationScript.new()

# ---------- Game-owned state ----------
var dom_hands: Array = [[], []]   # player 0 and 1
var dom_boneyard: Array = []
var dom_chain: Array = []         # list of tiles in order on table
var dom_left: int = -1            # current left end value
var dom_right: int = -1
var dom_turn: int = 0
var dom_game_over: bool = false
var dom_winner: int = -1
var dom_selected: int = -1        # index in hand
var dom_scores: Array = [0, 0]
var dom_difficulty: int = 3 # 1 random .. 6 flexible, blocking play

func reset_game() -> void:
	_reset_domino()

func _reset_domino() -> void:
	dom_hands = [[], []]
	dom_boneyard = []
	dom_chain = []
	dom_left = -1
	dom_right = -1
	dom_turn = 0
	dom_game_over = false
	dom_winner = -1
	dom_selected = -1
	dom_scores = [0, 0]
	# generate double-six
	var all: Array = []
	for a in range(7):
		for b in range(a, 7):
			all.append(Vector2i(a, b))
	all.shuffle()
	# deal 7 each
	for i in 7:
		dom_hands[0].append(all.pop_back())
		dom_hands[1].append(all.pop_back())
	dom_boneyard = all
	# starter: highest double or highest tile
	var best_idx := -1
	var best_val := -1
	var starter_p := 0
	for p in 2:
		for i in dom_hands[p].size():
			var t: Vector2i = dom_hands[p][i]
			var v: int = t.x + t.y + (10 if t.x == t.y else 0)
			if v > best_val:
				best_val = v
				best_idx = i
				starter_p = p
	var start_tile: Vector2i = dom_hands[starter_p][best_idx]
	dom_hands[starter_p].remove_at(best_idx)
	dom_chain.append(start_tile)
	dom_left = start_tile.x
	dom_right = start_tile.y
	dom_turn = 1 - starter_p

func _dom_can_play(tile: Vector2i, end: String) -> bool:
	if dom_chain.is_empty() or end not in ["L", "R"]:
		return false
	if end == "L":
		return tile.x == dom_left or tile.y == dom_left
	return tile.x == dom_right or tile.y == dom_right

func _dom_playable(p: int) -> Array:
	var res: Array = []
	if p < 0 or p >= dom_hands.size() or dom_game_over:
		return res
	for i in dom_hands[p].size():
		var t: Vector2i = dom_hands[p][i]
		if _dom_can_play(t, "L") or _dom_can_play(t, "R"):
			res.append(i)
	return res

func _dom_play(p: int, idx: int, end: String) -> bool:
	if dom_game_over or p < 0 or p >= dom_hands.size() or p != dom_turn:
		return false
	if idx < 0 or idx >= dom_hands[p].size() or end not in ["L", "R"]:
		return false
	var tile: Vector2i = dom_hands[p][idx]
	if not _dom_can_play(tile, end):
		return false
	dom_hands[p].remove_at(idx)
	if end == "L":
		if tile.y == dom_left:
			dom_left = tile.x
		else:
			# flip
			dom_left = tile.y
			tile = Vector2i(tile.y, tile.x)
		dom_chain.push_front(tile)
	else:
		if tile.x == dom_right:
			dom_right = tile.y
		else:
			dom_right = tile.x
			tile = Vector2i(tile.y, tile.x)
		dom_chain.append(tile)
	dom_selected = -1
	# check win
	if dom_hands[p].size() == 0:
		dom_game_over = true
		dom_winner = p
		_dom_calc_scores()
		app._go_result()
		return true
	# next turn
	dom_turn = 1 - p
	# if opponent cannot play and boneyard empty -> blocked
	if _dom_playable(dom_turn).size() == 0 and dom_boneyard.size() == 0:
		# both blocked?
		if _dom_playable(p).size() == 0:
			dom_game_over = true
			_dom_calc_scores()
			if dom_scores[0] < dom_scores[1]:
				dom_winner = 0
			elif dom_scores[1] < dom_scores[0]:
				dom_winner = 1
			else:
				dom_winner = -1
			app._go_result()
	return true

func _dom_draw(p: int) -> void:
	# Drawing is legal only for the active player when no tile can be played.
	if dom_game_over or p < 0 or p >= dom_hands.size() or p != dom_turn:
		return
	if not _dom_playable(p).is_empty() or dom_boneyard.is_empty():
		return
	dom_hands[p].append(dom_boneyard.pop_back())

func _dom_calc_scores() -> void:
	for p in 2:
		var s := 0
		for t in dom_hands[p]:
			s += t.x + t.y
		dom_scores[p] = s

func _dom_cpu_move() -> void:
	var playable: Array = _dom_playable(1)
	if playable.is_empty():
		if dom_boneyard.size() > 0:
			_dom_draw(1)
			playable = _dom_playable(1)
			if playable.is_empty():
				dom_turn = 0
				return
		else:
			dom_turn = 0
			return
	var action: Dictionary = _dom_choose_cpu_action(playable)
	var idx: int = int(action.get("index", playable[0]))
	var end: String = str(action.get("end", "R"))
	_dom_play(1, idx, end)

func _dom_choose_cpu_action(playable: Array) -> Dictionary:
	var options: Array[Dictionary] = []
	for raw_idx in playable:
		var idx: int = int(raw_idx)
		var tile: Vector2i = dom_hands[1][idx]
		if _dom_can_play(tile, "L"):
			options.append(_dom_score_cpu_option(idx, tile, "L"))
		if _dom_can_play(tile, "R"):
			options.append(_dom_score_cpu_option(idx, tile, "R"))
	if options.is_empty():
		return {"index": int(playable[0]), "end": "R"}
	if dom_difficulty <= 1:
		return options[randi() % options.size()]
	var best: Dictionary = options[0]
	var best_score: float = -INF
	for option in options:
		var score: float = float(option.get("score", 0.0))
		if dom_difficulty <= 3:
			score += randf_range(-2.5, 2.5)
		elif dom_difficulty == 4:
			score += randf_range(-0.8, 0.8)
		elif dom_difficulty == 5:
			score += randf_range(-0.12, 0.12)
		if score > best_score:
			best_score = score
			best = option
	return best

func _dom_score_cpu_option(idx: int, tile: Vector2i, end: String) -> Dictionary:
	var remaining: Array = dom_hands[1].duplicate()
	remaining.remove_at(idx)
	var next_left: int = dom_left
	var next_right: int = dom_right
	if end == "L":
		next_left = tile.x if tile.y == dom_left else tile.y
	else:
		next_right = tile.y if tile.x == dom_right else tile.x
	var pips: int = tile.x + tile.y
	var is_double: bool = tile.x == tile.y
	var mobility: int = _dom_count_playable_for_ends(remaining, next_left, next_right)
	var left_matches: int = _dom_count_matching(remaining, next_left)
	var right_matches: int = _dom_count_matching(remaining, next_right)
	var score: float = 0.0
	var unknown_pressure: int = 0
	var followup: float = 0.0
	match dom_difficulty:
		2:
			score = float(pips) + (0.5 if is_double else 0.0)
		3:
			score = float(pips) * 1.5 + (2.0 if is_double else 0.0) + float(mobility) * 0.8
		4:
			score = float(pips) * 1.2 + (1.0 if is_double else 0.0) + float(mobility) * 2.4 + float(left_matches + right_matches) * 0.9
		5:
			unknown_pressure = _dom_unknown_matches(next_left, remaining, tile) + _dom_unknown_matches(next_right, remaining, tile)
			score = float(pips) * 1.35 + float(mobility) * 3.0 + float(left_matches + right_matches) * 1.2 - float(unknown_pressure) * 0.32
		6:
			unknown_pressure = _dom_unknown_matches(next_left, remaining, tile) + _dom_unknown_matches(next_right, remaining, tile)
			followup = _dom_followup_potential(remaining, next_left, next_right)
			var second_ply: float = _dom_second_ply_value(remaining, next_left, next_right)
			# Grandmaster balances shedding pips, preserving exits from the hand,
			# and steering the open ends toward values the unseen pool may lack.
			score = float(pips) * 1.45 + float(mobility) * 3.4 + float(left_matches + right_matches) * 1.8 - float(unknown_pressure) * 0.72 + followup * 0.9 + second_ply * 1.35
		_:
			score = float(pips) + (1.0 if is_double else 0.0)
	return {"index": idx, "end": end, "score": score}

func _dom_count_playable_for_ends(hand: Array, left_end: int, right_end: int) -> int:
	var count: int = 0
	for raw_tile in hand:
		var tile: Vector2i = raw_tile
		if tile.x == left_end or tile.y == left_end or tile.x == right_end or tile.y == right_end:
			count += 1
	return count

func _dom_count_matching(hand: Array, pip: int) -> int:
	var count: int = 0
	for raw_tile in hand:
		var tile: Vector2i = raw_tile
		if tile.x == pip or tile.y == pip:
			count += 1
	return count

func _dom_same_tile(a: Vector2i, b: Vector2i) -> bool:
	return (a.x == b.x and a.y == b.y) or (a.x == b.y and a.y == b.x)

func _dom_contains_tile(hand: Array, target: Vector2i) -> bool:
	for raw_tile in hand:
		var tile: Vector2i = raw_tile
		if _dom_same_tile(tile, target):
			return true
	return false

func _dom_unknown_matches(pip: int, own_remaining: Array, just_played: Vector2i) -> int:
	var unseen: int = 0
	for a in range(7):
		for b in range(a, 7):
			var candidate := Vector2i(a, b)
			if _dom_contains_tile(dom_chain, candidate) or _dom_contains_tile(own_remaining, candidate) or _dom_same_tile(candidate, just_played):
				continue
			if candidate.x == pip or candidate.y == pip:
				unseen += 1
	return unseen

func _dom_followup_potential(hand: Array, left_end: int, right_end: int) -> float:
	var best: float = 0.0
	for i in range(hand.size()):
		var tile: Vector2i = hand[i]
		for end in ["L", "R"]:
			var playable_here: bool = (tile.x == left_end or tile.y == left_end) if end == "L" else (tile.x == right_end or tile.y == right_end)
			if not playable_here:
				continue
			var next_left: int = left_end
			var next_right: int = right_end
			if end == "L":
				next_left = tile.x if tile.y == left_end else tile.y
			else:
				next_right = tile.y if tile.x == right_end else tile.x
			var continuation_count: int = 0
			for j in range(hand.size()):
				if j == i:
					continue
				var other: Vector2i = hand[j]
				if other.x == next_left or other.y == next_left or other.x == next_right or other.y == next_right:
					continuation_count += 1
			var candidate_score: float = float(tile.x + tile.y) + float(continuation_count) * 2.0
			if tile.x == tile.y:
				candidate_score += 1.0
			best = maxf(best, candidate_score)
	return best


func _dom_second_ply_value(hand: Array, left_end: int, right_end: int) -> float:
	var best: float = 0.0
	for i in range(hand.size()):
		var tile: Vector2i = hand[i]
		for end in ["L", "R"]:
			var matches_end: bool = (tile.x == left_end or tile.y == left_end) if end == "L" else (tile.x == right_end or tile.y == right_end)
			if not matches_end:
				continue
			var next_left: int = left_end
			var next_right: int = right_end
			if end == "L":
				next_left = tile.x if tile.y == left_end else tile.y
			else:
				next_right = tile.y if tile.x == right_end else tile.x
			var remaining: Array = hand.duplicate()
			remaining.remove_at(i)
			var mobility: int = _dom_count_playable_for_ends(remaining, next_left, next_right)
			var endpoint_control: int = _dom_count_matching(remaining, next_left) + _dom_count_matching(remaining, next_right)
			var value: float = float(mobility) * 1.7 + float(endpoint_control) * 1.2 + float(tile.x + tile.y) * 0.35
			if tile.x == tile.y:
				value += 2.0
			best = maxf(best, value)
	return best

func _dom_pass(p: int) -> void:
	if dom_game_over or p < 0 or p >= dom_hands.size() or dom_turn != p:
		return
	# In draw-until-play domino, a player may pass only after the boneyard is empty
	# and the current hand has no legal play.
	if not dom_boneyard.is_empty() or not _dom_playable(p).is_empty():
		return
	dom_selected = -1
	dom_turn = 1 - p
	if _dom_playable(dom_turn).is_empty():
		dom_game_over = true
		_dom_calc_scores()
		if dom_scores[0] < dom_scores[1]:
			dom_winner = 0
		elif dom_scores[1] < dom_scores[0]:
			dom_winner = 1
		else:
			dom_winner = -1
		app._go_result()

func _dom_me() -> int:
	return 0 if app.vs_cpu else app.local_seat

func _dom_my_turn() -> bool:
	return dom_turn == _dom_me() and not dom_game_over

func _dom_hand_rects() -> Array:
	return _domino_presentation.hand_rects(app, self)

func _dom_tap(p: Vector2) -> void:
	_domino_presentation.handle_tap(app, self, p)

func _dom_select(index: int) -> void:
	if not _dom_my_turn():
		return
	if index < 0:
		dom_selected = -1
		return
	var me: int = _dom_me()
	if index >= dom_hands[me].size():
		return
	var tile: Vector2i = dom_hands[me][index]
	if not (_dom_can_play(tile, "L") or _dom_can_play(tile, "R")):
		app._show_toast("این مهره با دو سر زنجیر جور نیست.")
		return
	dom_selected = index if dom_selected != index else -1

func _dom_do_play(end: String) -> void:
	var me: int = _dom_me()
	if dom_selected < 0 or dom_selected >= dom_hands[me].size():
		return
	var idx: int = dom_selected
	if app._net_on():
		app._send_game_action("_rpc_dom_play", [me, idx, end])
	else:
		_dom_play(me, idx, end)

func _dom_do_draw() -> void:
	var me: int = _dom_me()
	if app._net_on():
		app._send_game_action("_rpc_dom_draw", [me])
	else:
		_dom_draw(me)

func _dom_do_pass() -> void:
	var me: int = _dom_me()
	if app._net_on():
		app._send_game_action("_rpc_dom_pass", [me])
	else:
		_dom_pass(me)

func _btns_domino() -> void:
	_domino_presentation.build_buttons(app, self)

func _draw_domino() -> void:
	_domino_presentation.render(app, self)
