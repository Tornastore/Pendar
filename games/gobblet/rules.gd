extends "res://core/game_module.gd"
const GobbletPresentationScript = preload("res://games/gobblet/presentation.gd")
var _gob_presentation = GobbletPresentationScript.new()
## Rule engine and authoritative state for Gobblet.
## Board pieces may move to any legal square. Revealing an opponent's four-in-a-row
## during a move loses unless the move itself covers that exposed line.

var gob_board: Array = []  # 4x4 stacks of {o: owner, s: size}; last element is visible
var gob_turn: int = 1
var gob_hand: Array = [[3, 3, 3, 3], [3, 3, 3, 3]]
var gob_sel_size: int = -1
var gob_sel_from: Vector2i = Vector2i(-1, -1)
var gob_game_over: bool = false
var gob_winner: int = 0
var gob_difficulty: int = 3 # 1 random .. 6 tactical multi-ply search
var _gob_cpu_move_history: Array[Dictionary] = []

func reset_game() -> void:
	_reset_gobblet()

func _reset_gobblet() -> void:
	gob_board = []
	for y in range(4):
		var row: Array = []
		for x in range(4):
			row.append([])
		gob_board.append(row)
	gob_turn = 1
	gob_hand = [[3, 3, 3, 3], [3, 3, 3, 3]]
	gob_sel_size = -1
	gob_sel_from = Vector2i(-1, -1)
	gob_game_over = false
	gob_winner = 0
	_gob_cpu_move_history.clear()

func _gob_top(x: int, y: int) -> Dictionary:
	if x < 0 or x >= 4 or y < 0 or y >= 4:
		return {}
	var st: Array = gob_board[y][x]
	if st.is_empty():
		return {}
	return st[st.size() - 1]

func _gob_lines() -> Array:
	var lines: Array = []
	for y in range(4):
		var row: Array = []
		for x in range(4):
			row.append(Vector2i(x, y))
		lines.append(row)
	for x in range(4):
		var col: Array = []
		for y in range(4):
			col.append(Vector2i(x, y))
		lines.append(col)
	var diag_a: Array = []
	var diag_b: Array = []
	for i in range(4):
		diag_a.append(Vector2i(i, i))
		diag_b.append(Vector2i(3 - i, i))
	lines.append(diag_a)
	lines.append(diag_b)
	return lines

func _gob_check_win(p: int) -> bool:
	for line in _gob_lines():
		var complete: bool = true
		for cell in line:
			var top: Dictionary = _gob_top(cell.x, cell.y)
			if top.is_empty() or int(top.o) != p:
				complete = false
				break
		if complete:
			return true
	return false

func _gob_opponent_three_at(x: int, y: int, player: int) -> bool:
	var opponent: int = 3 - player
	for line in _gob_lines():
		var opponent_count: int = 0
		var target_is_opponent: bool = false
		for cell in line:
			var top: Dictionary = _gob_top(cell.x, cell.y)
			if not top.is_empty() and int(top.o) == opponent:
				opponent_count += 1
				if cell == Vector2i(x, y):
					target_is_opponent = true
		if opponent_count >= 3 and target_is_opponent:
			return true
	return false

func _gob_can_place(x: int, y: int, size: int, player: int) -> bool:
	if gob_game_over or player < 1 or player > 2 or player != gob_turn:
		return false
	if x < 0 or x >= 4 or y < 0 or y >= 4 or size < 1 or size > 4:
		return false
	if gob_hand[player - 1][size - 1] <= 0:
		return false
	var top: Dictionary = _gob_top(x, y)
	if top.is_empty():
		return true
	if int(top.s) >= size:
		return false
	# Rule: an off-board Gobblet normally enters an empty square. It may cover
	# an opponent's visible piece only to break that opponent's three-in-a-row.
	return int(top.o) == 3 - player and _gob_opponent_three_at(x, y, player)

func _gob_can_move(from: Vector2i, to: Vector2i, player: int) -> bool:
	if gob_game_over or player < 1 or player > 2 or player != gob_turn:
		return false
	if from.x < 0 or from.x >= 4 or from.y < 0 or from.y >= 4:
		return false
	if to.x < 0 or to.x >= 4 or to.y < 0 or to.y >= 4 or from == to:
		return false
	var source_top: Dictionary = _gob_top(from.x, from.y)
	if source_top.is_empty() or int(source_top.o) != player:
		return false
	var target_top: Dictionary = _gob_top(to.x, to.y)
	return target_top.is_empty() or int(source_top.s) > int(target_top.s)

func _gob_finish(winner: int) -> void:
	gob_game_over = true
	gob_winner = winner
	gob_sel_size = -1
	gob_sel_from = Vector2i(-1, -1)
	app._go_result()

func _gob_place(x: int, y: int, size: int, player: int) -> bool:
	if not _gob_can_place(x, y, size, player):
		return false
	gob_hand[player - 1][size - 1] -= 1
	gob_board[y][x].append({"o": player, "s": size})
	gob_sel_size = -1
	gob_sel_from = Vector2i(-1, -1)
	if _gob_check_win(3 - player):
		# A covered piece cannot be part of a visible line, so this is defensive.
		_gob_finish(3 - player)
		return true
	if _gob_check_win(player):
		_gob_finish(player)
		return true
	gob_turn = 3 - player
	return true

func _gob_move(from: Vector2i, to: Vector2i, player: int) -> bool:
	if not _gob_can_move(from, to, player):
		return false
	var source_stack: Array = gob_board[from.y][from.x]
	var piece: Dictionary = source_stack.pop_back()
	gob_board[to.y][to.x].append(piece)
	gob_sel_size = -1
	gob_sel_from = Vector2i(-1, -1)
	# The whole move is evaluated atomically. If lifting the piece exposes four
	# of the opponent's visible pieces and this move doesn't cover the line, mover loses.
	if _gob_check_win(3 - player):
		_gob_finish(3 - player)
		return true
	if _gob_check_win(player):
		_gob_finish(player)
		return true
	if player == 2:
		_gob_cpu_move_history.append({"from": from, "to": to, "size": int(piece.s)})
		if _gob_cpu_move_history.size() > 8:
			_gob_cpu_move_history.pop_front()
	gob_turn = 3 - player
	return true

func _gob_repetition_penalty(action: Dictionary, player: int) -> float:
	if player != 2 or str(action.get("kind", "")) != "move" or _gob_cpu_move_history.is_empty():
		return 0.0
	var source: Vector2i = action.from
	var target: Vector2i = action.to
	var level: int = clampi(gob_difficulty, 1, 6)
	var penalty_by_level: Array[float] = [0.0, 1.0, 4.0, 12.0, 35.0, 85.0]
	var penalty: float = penalty_by_level[level - 1]
	for history_index in range(_gob_cpu_move_history.size() - 1, maxi(-1, _gob_cpu_move_history.size() - 5), -1):
		var previous: Dictionary = _gob_cpu_move_history[history_index]
		if source == previous.get("to", Vector2i(-1, -1)) and target == previous.get("from", Vector2i(-1, -1)):
			var recency_scale: float = 1.0 if history_index == _gob_cpu_move_history.size() - 1 else 0.65
			return penalty * recency_scale
	return 0.0

func _gob_action_score(action: Dictionary, player: int) -> float:
	var saved_board: Array = gob_board.duplicate(true)
	var saved_hand: Array = gob_hand.duplicate(true)
	if str(action.kind) == "place":
		gob_hand[player - 1][int(action.size) - 1] -= 1
		gob_board[int(action.y)][int(action.x)].append({"o": player, "s": int(action.size)})
	else:
		var source: Vector2i = action.from
		var target: Vector2i = action.to
		var stack: Array = gob_board[source.y][source.x]
		var pc: Dictionary = stack.pop_back()
		gob_board[target.y][target.x].append(pc)
	var score: float = 0.0
	if _gob_check_win(3 - player):
		score = -100000.0
	elif _gob_check_win(player):
		score = 100000.0
	else:
		for line in _gob_lines():
			var own_count: int = 0
			var enemy_count: int = 0
			for cell in line:
				var top: Dictionary = _gob_top(cell.x, cell.y)
				if not top.is_empty():
					if int(top.o) == player:
						own_count += 1
					else:
						enemy_count += 1
			if enemy_count == 0:
				if own_count == 3:
					score += 12.0 + float(gob_difficulty) * 4.0
				elif own_count == 2:
					score += 2.0 + float(gob_difficulty) * 1.4
			if own_count == 0 and enemy_count >= 3:
				score -= 28.0 + float(gob_difficulty) * 18.0
		if str(action.kind) == "place":
			score += float(action.size) * (0.15 + float(gob_difficulty) * 0.12)
		else:
			var dest: Vector2i = action.to
			score += (0.8 + float(gob_difficulty) * 0.25) - Vector2(dest.x, dest.y).distance_to(Vector2(1.5, 1.5)) * (0.15 + float(gob_difficulty) * 0.07)
	gob_board = saved_board
	gob_hand = saved_hand
	score -= _gob_repetition_penalty(action, player)
	var noise_by_level: Array[float] = [0.0, 19.0, 10.0, 4.0, 0.35, 0.0]
	var noise: float = noise_by_level[clampi(gob_difficulty, 1, 6) - 1]
	return score + randf_range(-noise, noise)

func _gob_generate_actions(player: int) -> Array:
	var actions: Array = []
	if gob_game_over:
		return actions
	var previous_turn: int = gob_turn
	gob_turn = player
	for size in [4, 3, 2, 1]:
		if gob_hand[player - 1][size - 1] <= 0:
			continue
		for y in range(4):
			for x in range(4):
				if _gob_can_place(x, y, size, player):
					actions.append({"kind": "place", "x": x, "y": y, "size": size})
	for y in range(4):
		for x in range(4):
			var top: Dictionary = _gob_top(x, y)
			if top.is_empty() or int(top.o) != player:
				continue
			for ty in range(4):
				for tx in range(4):
					var from := Vector2i(x, y)
					var to := Vector2i(tx, ty)
					if _gob_can_move(from, to, player):
						actions.append({"kind": "move", "from": from, "to": to})
	gob_turn = previous_turn
	return actions

func _gob_simulate_action(action: Dictionary, player: int) -> void:
	if str(action.kind) == "place":
		var size: int = int(action.size)
		gob_hand[player - 1][size - 1] -= 1
		gob_board[int(action.y)][int(action.x)].append({"o": player, "s": size})
	else:
		var source: Vector2i = action.from
		var target: Vector2i = action.to
		var stack: Array = gob_board[source.y][source.x]
		var piece: Dictionary = stack.pop_back()
		gob_board[target.y][target.x].append(piece)

func _gob_cpu() -> void:
	if gob_game_over or gob_turn != 2:
		return
	var actions: Array = _gob_generate_actions(2)
	if actions.is_empty():
		gob_turn = 1
		return
	var level: int = clampi(gob_difficulty, 1, 6)
	if level == 1:
		var random_action: Dictionary = actions[randi() % actions.size()]
		if str(random_action.kind) == "place":
			_gob_place(int(random_action.x), int(random_action.y), int(random_action.size), 2)
		else:
			_gob_move(random_action.from, random_action.to, 2)
		return
	var ranked: Array = []
	for action in actions:
		ranked.append({"action": action, "score": _gob_action_score(action, 2)})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.score) > float(b.score)
	)
	var chosen: Dictionary = ranked[0].action
	if level >= 5:
		var search_count: int = mini(ranked.size(), 10 if level == 5 else 20)
		var saved_board: Array = gob_board.duplicate(true)
		var saved_hand: Array = gob_hand.duplicate(true)
		var best_score: float = -INF
		for index in range(search_count):
			var candidate: Dictionary = ranked[index].action
			gob_board = saved_board.duplicate(true)
			gob_hand = saved_hand.duplicate(true)
			_gob_simulate_action(candidate, 2)
			var score: float = float(ranked[index].score)
			# Match the real move resolver: exposing an opponent's four-in-a-row
			# takes precedence over completing our own line on the same action.
			if _gob_check_win(1):
				score -= 200000.0
			elif _gob_check_win(2):
				score += 100000.0
			else:
				var candidate_board: Array = gob_board.duplicate(true)
				var candidate_hand: Array = gob_hand.duplicate(true)
				var replies: Array = _gob_generate_actions(1)
				if level == 5:
					var strongest_reply: float = -INF
					for reply in replies:
						strongest_reply = maxf(strongest_reply, _gob_action_score(reply, 1))
					if strongest_reply > -INF:
						score -= strongest_reply * 0.92
				else:
					# Grandmaster: inspect the opponent's strongest tactical replies and
					# then search our best continuation instead of stopping at one reply.
					var reply_ranked: Array = _gob_rank_actions(replies, 1, 8)
					var worst_continuation: float = INF
					for reply_entry in reply_ranked:
						gob_board = candidate_board.duplicate(true)
						gob_hand = candidate_hand.duplicate(true)
						var reply: Dictionary = reply_entry.action
						_gob_simulate_action(reply, 1)
						var branch_value: float
						if _gob_check_win(1):
							branch_value = -100000.0
						elif _gob_check_win(2):
							branch_value = 100000.0
						else:
							var cpu_actions: Array = _gob_generate_actions(2)
							var cpu_ranked: Array = _gob_rank_actions(cpu_actions, 2, 6)
							var cpu_best: float = -INF
							for cpu_entry in cpu_ranked:
								cpu_best = maxf(cpu_best, float(cpu_entry.score))
							branch_value = -float(reply_entry.score) * 0.72 + (cpu_best if cpu_best > -INF else 0.0) * 0.62
						worst_continuation = minf(worst_continuation, branch_value)
					if worst_continuation < INF:
						score += worst_continuation * 0.48
			if score > best_score:
				best_score = score
				chosen = candidate
		gob_board = saved_board
		gob_hand = saved_hand

	if str(chosen.kind) == "place":
		_gob_place(int(chosen.x), int(chosen.y), int(chosen.size), 2)
	else:
		_gob_move(chosen.from, chosen.to, 2)


func _gob_rank_actions(actions: Array, player: int, limit: int) -> Array:
	var ranked_actions: Array = []
	for action in actions:
		ranked_actions.append({"action": action, "score": _gob_action_score(action, player)})
	ranked_actions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.score) > float(b.score)
	)
	if limit > 0 and ranked_actions.size() > limit:
		ranked_actions.resize(limit)
	return ranked_actions

func _gob_me() -> int:
	return app._my_seat() + 1

func _gob_my_turn() -> bool:
	return gob_turn == _gob_me() and not gob_game_over

func _gob_pick(s: int) -> void:
	if not _gob_my_turn():
		return
	gob_sel_size = s if gob_sel_size != s else -1
	gob_sel_from = Vector2i(-1, -1)

func _gob_tap(p: Vector2) -> void:
	_gob_presentation.handle_tap(app, self, p)

func _gob_handle_cell_tap(cell: Vector2i) -> void:
	if not _gob_my_turn():
		return
	var gx: int = cell.x
	var gy: int = cell.y
	if gx < 0 or gx >= 4 or gy < 0 or gy >= 4:
		return
	var me: int = _gob_me()
	var tapped_top: Dictionary = _gob_top(gx, gy)
	if gob_sel_size > 0:
		if not _gob_can_place(gx, gy, gob_sel_size, me):
			app._show_toast("مهره‌ی تازه معمولاً روی خانه‌ی خالی قرار می‌گیرد؛ فقط برای شکستن ردیف سه‌تایی حریف می‌توان روی مهره‌ی او گذاشت.")
		elif app._net_on():
			app._send_game_action("_rpc_gob_place", [gx, gy, gob_sel_size, me])
		else:
			_gob_place(gx, gy, gob_sel_size, me)
		return
	if gob_sel_from.x >= 0:
		var destination := Vector2i(gx, gy)
		if _gob_can_move(gob_sel_from, destination, me):
			if app._net_on():
				app._send_game_action("_rpc_gob_move", [gob_sel_from.x, gob_sel_from.y, gx, gy, me])
			else:
				_gob_move(gob_sel_from, destination, me)
			return
		if not tapped_top.is_empty() and int(tapped_top.o) == me:
			gob_sel_from = destination
			return
		app._show_toast("خانه‌ی مقصد باید خالی باشد یا مهره‌ی روی آن کوچک‌تر باشد.")
		return
	if not tapped_top.is_empty() and int(tapped_top.o) == me:
		gob_sel_from = Vector2i(gx, gy)
		gob_sel_size = -1
		return
	app._show_toast("از پایین یک اندازه انتخاب کنید، یا یکی از مهره‌های روی صفحه را برای جابه‌جایی بزنید.")

func _gob_hand_rect(index: int) -> Rect2:
	return _gob_presentation.hand_rect(app, index)

func _btns_gobblet() -> void:
	_gob_presentation.build_buttons(app, self)

func _draw_gobblet() -> void:
	_gob_presentation.render(app, self)
