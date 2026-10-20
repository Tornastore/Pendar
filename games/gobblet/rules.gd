extends "res://core/game_module.gd"
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
var gob_difficulty: int = 3 # 1 random .. 6 tactical one-ply search

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
	app.state = app.State.RESULT
	app._build_result_buttons()

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
	gob_turn = 3 - player
	return true

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
	var noise_by_level: Array[float] = [0.0, 19.0, 10.0, 4.0, 1.2, 0.2]
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
		var search_count: int = mini(ranked.size(), 10 if level == 5 else 18)
		var saved_board: Array = gob_board.duplicate(true)
		var saved_hand: Array = gob_hand.duplicate(true)
		var best_score: float = -INF
		for index in range(search_count):
			var candidate: Dictionary = ranked[index].action
			gob_board = saved_board.duplicate(true)
			gob_hand = saved_hand.duplicate(true)
			_gob_simulate_action(candidate, 2)
			var score: float = float(ranked[index].score)
			if _gob_check_win(2):
				score += 100000.0
			elif _gob_check_win(1):
				score -= 200000.0
			else:
				var replies: Array = _gob_generate_actions(1)
				var strongest_reply: float = -INF
				for reply in replies:
					strongest_reply = maxf(strongest_reply, _gob_action_score(reply, 1))
				if strongest_reply > -INF:
					score -= strongest_reply * (0.72 if level == 5 else 1.0)
			if score > best_score:
				best_score = score
				chosen = candidate
		gob_board = saved_board
		gob_hand = saved_hand
	if str(chosen.kind) == "place":
		_gob_place(int(chosen.x), int(chosen.y), int(chosen.size), 2)
	else:
		_gob_move(chosen.from, chosen.to, 2)

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
	if not _gob_my_turn():
		return
	var gx: int = int(floor((p.x - app.GOB_ORIGIN.x) / app.GOB_CELL))
	var gy: int = int(floor((p.y - app.GOB_ORIGIN.y) / app.GOB_CELL))
	if gx < 0 or gx >= 4 or gy < 0 or gy >= 4:
		return
	var me: int = _gob_me()
	if gob_sel_size > 0:
		if not _gob_can_place(gx, gy, gob_sel_size, me):
			app._show_toast("مهره‌ی تازه معمولاً روی خانه‌ی خالی قرار می‌گیرد؛ فقط برای شکستن ردیف سه‌تایی حریف می‌توان روی مهره‌ی او گذاشت.")
		elif app._net_on():
			app.rpc("_rpc_gob_place", gx, gy, gob_sel_size, me)
		else:
			_gob_place(gx, gy, gob_sel_size, me)
		return
	var tapped_top: Dictionary = _gob_top(gx, gy)
	if gob_sel_from.x >= 0:
		var destination := Vector2i(gx, gy)
		if _gob_can_move(gob_sel_from, destination, me):
			if app._net_on():
				app.rpc("_rpc_gob_move", gob_sel_from.x, gob_sel_from.y, gx, gy, me)
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
	var col: int = index % 2
	var row: int = int(index / 2)
	return Rect2(20.0 + col * 260.0, 612.0 + row * 92.0, 240.0, 80.0)

func _btns_gobblet() -> void:
	for s in range(4):
		var r: Rect2 = _gob_hand_rect(s)
		var ok: bool = _gob_my_turn() and gob_hand[_gob_me() - 1][s] > 0
		app._add_hit(r, _gob_pick.bind(s + 1), "gob_%d" % s, false, ok)

func _draw_gobblet() -> void:
	var me: int = _gob_me()
	var tot0: int = 0
	var tot1: int = 0
	for s in range(4):
		tot0 += gob_hand[me - 1][s]
		tot1 += gob_hand[2 - me][s]
	var c_p1 := Color(1.0, 0.45, 0.35)
	var c_p2 := Color(0.35, 0.58, 1.0)
	var c0: Color = c_p1 if me == 1 else c_p2
	var c1: Color = c_p2 if me == 1 else c_p1
	var pa: Dictionary = app._pl("شما", c0, app._fa(tot0), gob_turn == me and not gob_game_over, true, "مهره باقی‌مانده")
	var pb: Dictionary = app._pl("حریف", c1, app._fa(tot1), gob_turn == 3 - me and not gob_game_over, false, "مهره باقی‌مانده")
	if pa.active:
		pa.sub = "نوبت شما"
	app._draw_hud("گابلت", pa, pb)
	app._draw_ai_difficulty_chip_at(gob_difficulty, 140.0)
	var flat: Array = []
	for y in range(4):
		for x in range(4):
			var st: Array = gob_board[y][x]
			flat.append(st.size() * 10 + (int(st[st.size() - 1].s) + int(st[st.size() - 1].o) * 100 if st.size() > 0 else 0))
	app._track_board("gob", flat)
	var o: Vector2 = app.GOB_ORIGIN
	app._panel(Rect2(o - Vector2(10, 10), Vector2(app.GOB_CELL * 4 + 20, app.GOB_CELL * 4 + 20)), Color(0.16, 0.12, 0.10), 24, Color(0.9, 0.6, 0.3, 0.4), 1.5, 22, 8)
	for y in range(4):
		for x in range(4):
			var r := Rect2(o.x + x * app.GOB_CELL + 3, o.y + y * app.GOB_CELL + 3, app.GOB_CELL - 6, app.GOB_CELL - 6)
			app._panel(r, Color(0.27, 0.21, 0.17), 14)
			var cell := Vector2i(x, y)
			var ok_cell: bool = false
			if _gob_my_turn() and gob_sel_size > 0:
				ok_cell = _gob_can_place(x, y, gob_sel_size, me)
			elif _gob_my_turn() and gob_sel_from.x >= 0:
				ok_cell = _gob_can_move(gob_sel_from, cell, me)
			if ok_cell:
				app._panel(r, Color(app.ACCENT.r, app.ACCENT.g, app.ACCENT.b, 0.12), 14, Color(app.ACCENT.r, app.ACCENT.g, app.ACCENT.b, 0.50), 1.5)
			var cc: Vector2 = r.get_center()
			var st2: Array = gob_board[y][x]
			var t: float = app._cell_t("gob", y * 4 + x)[0]
			for k in range(st2.size()):
				var pc: Dictionary = st2[k]
				var col: Color = c0 if int(pc.o) == me else c1
				var rad: float = 11.0 + int(pc.s) * 10.0
				if k == st2.size() - 1 and t < 1.0:
					rad *= app._ease_back(t)
				app.draw_circle(cc + Vector2(0, 2), rad, Color(0, 0, 0, 0.30))
				app.draw_circle(cc, rad, col.darkened(0.35))
				app.draw_circle(cc + Vector2(0, -1), rad - 3.5, col)
				if k == st2.size() - 1:
					app.draw_circle(cc + Vector2(-rad * 0.3, -rad * 0.36), rad * 0.2, Color(1, 1, 1, 0.4))
			if gob_sel_from == cell:
				app._ring(cc, app.GOB_CELL * 0.43, app.ACCENT, 3.0)
	var size_names: Array[String] = ["کوچک", "متوسط", "بزرگ", "خیلی بزرگ"]
	for s in range(4):
		var r: Rect2 = _gob_hand_rect(s)
		var n: int = gob_hand[me - 1][s]
		var sel: bool = (gob_sel_size == s + 1)
		var can: bool = _gob_my_turn() and n > 0
		app._panel(r, app.CARD_H if sel else app.CARD, 18, app.ACCENT if sel else app.LINE_STRONG, 2.5 if sel else 1.0, 8, 3)
		var rad2: float = 10.0 + (s + 1) * 5.0
		var cc2 := Vector2(r.end.x - 48, r.get_center().y)
		app.draw_circle(cc2 + Vector2(0, 2), rad2, (c0 if can else Color(0.4, 0.4, 0.45)).darkened(0.35))
		app.draw_circle(cc2, rad2 - 2.5, c0 if can else Color(0.45, 0.45, 0.5))
		app._txt_c(size_names[s], Rect2(r.position.x + 8, r.position.y + 10, r.size.x - 76, 26), 15, app.TEXT if can else app.TEXT_FAINT, true)
		app._txt_c("× " + app._fa(n), Rect2(r.position.x + 8, r.position.y + 40, r.size.x - 76, 26), 18, app.ACCENT if can else app.TEXT_FAINT, true)
	if not gob_game_over:
		if _gob_my_turn():
			if gob_sel_size > 0:
				app._hint("مهره‌ی تازه را روی خانه‌ی مجاز قرار دهید", 804, app.TEXT_DIM)
			elif gob_sel_from.x >= 0:
				app._hint("مهره‌ی انتخاب‌شده را به خانه‌ی علامت‌خورده ببرید", 804, app.TEXT_DIM)
			else:
				app._hint("اندازه‌ی تازه را انتخاب کنید یا مهره‌ی روی صفحه را برای جابه‌جایی بزنید", 804, app.TEXT_DIM)
		else:
			app._hint("حریف در حال بازی…", 804, app.TEXT_DIM)
