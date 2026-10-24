extends "res://core/game_module.gd"
## Rule engine and authoritative state for pentago.

const PentagoPresentationScript = preload("res://games/pentago/presentation.gd")
var _pent_presentation = PentagoPresentationScript.new()

# ---------- Game-owned state ----------
var pent_board: Array = []      # 6x6
var pent_turn: int = 1
var pent_phase: int = 0         # 0 place, 1 rotate
var pent_last: Vector2i = Vector2i(-1, -1)
var pent_game_over: bool = false
var pent_winner: int = 0
var pent_selected_quad: int = -1
var pent_difficulty: int = 3 # 1 random .. 6 tactical look-ahead
var pent_cpu_planned_quad: int = -1
var pent_cpu_planned_clockwise: bool = true

func reset_game() -> void:
	_reset_pentago()

func _reset_pentago() -> void:
	pent_board = []
	for y in 6:
		var row: Array = []
		for x in 6:
			row.append(0)
		pent_board.append(row)
	pent_turn = 1
	pent_phase = 0
	pent_last = Vector2i(-1, -1)
	pent_game_over = false
	pent_winner = 0
	pent_selected_quad = -1
	pent_cpu_planned_quad = -1
	pent_cpu_planned_clockwise = true

func _pent_check_win(color: int) -> bool:
	# rows
	for y in 6:
		for x in 2:
			if pent_board[y][x] == color and pent_board[y][x+1] == color and pent_board[y][x+2] == color and pent_board[y][x+3] == color and pent_board[y][x+4] == color:
				return true
	# cols
	for x in 6:
		for y in 2:
			if pent_board[y][x] == color and pent_board[y+1][x] == color and pent_board[y+2][x] == color and pent_board[y+3][x] == color and pent_board[y+4][x] == color:
				return true
	# diagonals
	for y in 2:
		for x in 2:
			if pent_board[y][x] == color and pent_board[y+1][x+1] == color and pent_board[y+2][x+2] == color and pent_board[y+3][x+3] == color and pent_board[y+4][x+4] == color:
				return true
			if pent_board[y][x+4] == color and pent_board[y+1][x+3] == color and pent_board[y+2][x+2] == color and pent_board[y+3][x+1] == color and pent_board[y+4][x] == color:
				return true
	return false

func _pent_rotate(quad: int, clockwise: bool) -> void:
	# quads: 0 TL, 1 TR, 2 BL, 3 BR
	var ox: int = 0 if quad % 2 == 0 else 3
	var oy: int = 0 if quad < 2 else 3
	var tmp: Array = []
	for y in 3:
		var row: Array = []
		for x in 3:
			row.append(pent_board[oy + y][ox + x])
		tmp.append(row)
	for y in 3:
		for x in 3:
			if clockwise:
				pent_board[oy + y][ox + x] = tmp[2 - x][y]
			else:
				pent_board[oy + y][ox + x] = tmp[x][2 - y]

func _pent_place(c: Vector2i) -> bool:
	if pent_board[c.y][c.x] != 0:
		return false
	pent_board[c.y][c.x] = pent_turn
	pent_last = c
	if _pent_check_win(pent_turn):
		pent_game_over = true
		pent_winner = pent_turn
		app._go_result()
		return true
	pent_phase = 1
	app._build_pent_rotate_buttons()
	return true

func _pent_do_rotate(quad: int, clockwise: bool) -> void:
	_pent_rotate(quad, clockwise)
	if _pent_check_win(pent_turn):
		pent_game_over = true
		pent_winner = pent_turn
		app._go_result()
		return
	# also check opponent (rare double win)
	if _pent_check_win(3 - pent_turn):
		pent_game_over = true
		pent_winner = 3 - pent_turn
		app._go_result()
		return
	pent_turn = 3 - pent_turn
	pent_phase = 0
	pent_selected_quad = -1
	app._build_playing_buttons()

func _pent_cpu_move() -> void:
	if pent_phase == 0:
		var empties: Array[Vector2i] = []
		for y in range(6):
			for x in range(6):
				if pent_board[y][x] == 0:
					empties.append(Vector2i(x, y))
		if empties.is_empty():
			return
		var place: Vector2i = empties[randi() % empties.size()]
		pent_cpu_planned_quad = randi() % 4
		pent_cpu_planned_clockwise = randi() % 2 == 0
		if pent_difficulty >= 2:
			var plan: Dictionary = _pent_choose_cpu_plan()
			place = plan.get("place", place)
			pent_cpu_planned_quad = int(plan.get("quad", pent_cpu_planned_quad))
			pent_cpu_planned_clockwise = bool(plan.get("clockwise", pent_cpu_planned_clockwise))
		_pent_place(place)
	else:
		var quad: int = randi() % 4
		var clockwise: bool = randi() % 2 == 0
		if pent_difficulty >= 2 and pent_cpu_planned_quad >= 0:
			quad = pent_cpu_planned_quad
			clockwise = pent_cpu_planned_clockwise
		_pent_do_rotate(quad, clockwise)
		pent_cpu_planned_quad = -1

func _pent_choose_cpu_plan() -> Dictionary:
	var base_board: Array = pent_board.duplicate(true)
	var plans: Array[Dictionary] = []
	for y in range(6):
		for x in range(6):
			if int(base_board[y][x]) != 0:
				continue
			# Placement alone may complete five before a rotation is requested.
			pent_board = base_board.duplicate(true)
			pent_board[y][x] = 2
			if _pent_check_win(2):
				pent_board = base_board
				return {"place": Vector2i(x, y), "quad": 0, "clockwise": true}
			for quad in range(4):
				for direction in range(2):
					pent_board = base_board.duplicate(true)
					pent_board[y][x] = 2
					var clockwise: bool = direction == 0
					_pent_rotate(quad, clockwise)
					var score: float
					if _pent_check_win(2):
						score = 1000000.0
					elif _pent_check_win(1):
						score = -1000000.0
					else:
						score = _pent_evaluate_board(2, pent_difficulty)
						var centre_bonus: float = 5.0 - abs(float(x) - 2.5) - abs(float(y) - 2.5)
						score += centre_bonus * float(pent_difficulty) * 0.6
						# Strong profiles follow the evaluation consistently; only lower tiers
						# retain randomness, so a near-equal move doesn't overrule a tactic.
						var noise_scale: float = 0.35 if pent_difficulty == 5 else (0.0 if pent_difficulty >= 6 else 8.0 / float(pent_difficulty))
						score += randf_range(-noise_scale, noise_scale)
					plans.append({"place": Vector2i(x, y), "quad": quad, "clockwise": clockwise, "score": score, "board": pent_board.duplicate(true)})
	pent_board = base_board
	if plans.is_empty():
		return {}
	plans.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"])
	)
	var best_plan: Dictionary = plans[0]
	var best_score: float = -INF
	var lookahead_count: int = mini(24 if pent_difficulty == 5 else 64, plans.size()) if pent_difficulty >= 5 else 0
	for i in range(plans.size()):
		var candidate: Dictionary = plans[i]
		var score: float = float(candidate["score"])
		if i < lookahead_count and score < 900000.0:
			pent_board = candidate["board"].duplicate(true)
			if _pent_opponent_has_winning_turn():
				score -= 900000.0 if pent_difficulty >= 6 else 350000.0
		if score > best_score:
			best_score = score
			best_plan = candidate
	pent_board = base_board
	return best_plan

func _pent_evaluate_board(player: int, level: int) -> float:
	var weights: Array[float] = [0.0, 1.0, 6.0, 38.0, 260.0, 0.0]
	match level:
		2: weights = [0.0, 1.0, 4.0, 20.0, 120.0, 0.0]
		3: weights = [0.0, 1.5, 8.0, 48.0, 340.0, 0.0]
		4: weights = [0.0, 2.0, 11.0, 70.0, 480.0, 0.0]
		5: weights = [0.0, 2.0, 13.0, 85.0, 600.0, 0.0]
		6: weights = [0.0, 2.5, 16.0, 105.0, 760.0, 0.0]
	var result: float = 0.0
	var directions: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
	for y in range(6):
		for x in range(6):
			for direction in directions:
				var end_x: int = x + direction.x * 4
				var end_y: int = y + direction.y * 4
				if end_x < 0 or end_x >= 6 or end_y < 0 or end_y >= 6:
					continue
				var own_count: int = 0
				var enemy_count: int = 0
				for step in range(5):
					var cell: int = int(pent_board[y + direction.y * step][x + direction.x * step])
					if cell == player:
						own_count += 1
					elif cell == 3 - player:
						enemy_count += 1
				if own_count > 0 and enemy_count == 0:
					result += weights[own_count]
				elif enemy_count > 0 and own_count == 0:
					result -= weights[enemy_count] * 1.12
	return result

func _pent_opponent_has_winning_turn() -> bool:
	var base_board: Array = pent_board.duplicate(true)
	for y in range(6):
		for x in range(6):
			if int(base_board[y][x]) != 0:
				continue
			pent_board = base_board.duplicate(true)
			pent_board[y][x] = 1
			if _pent_check_win(1):
				pent_board = base_board
				return true
			for quad in range(4):
				for direction in range(2):
					pent_board = base_board.duplicate(true)
					pent_board[y][x] = 1
					_pent_rotate(quad, direction == 0)
					if _pent_check_win(1):
						pent_board = base_board
						return true
	pent_board = base_board
	return false

func _pent_origin() -> Vector2:
	return _pent_presentation.board_origin(app)

func _pent_cell_pos(x: int, y: int) -> Vector2:
	return _pent_presentation.cell_pos(app, x, y)

func _pent_my_turn() -> bool:
	if app.vs_cpu:
		return pent_turn == 1
	return app._is_my_turn()

func _pent_tap(p: Vector2) -> void:
	_pent_presentation.handle_tap(app, self, p)

func _pent_handle_cell_tap(c: Vector2i) -> void:
	# Authoritative guards stay in rules.gd; presentation only maps pointer to a cell.
	if pent_game_over or pent_phase != 0 or not _pent_my_turn():
		return
	if c.x < 0 or c.x >= 6 or c.y < 0 or c.y >= 6:
		return
	if pent_board[c.y][c.x] != 0:
		return
	if app._net_on():
		app._send_game_action("_rpc_pent_place", [c.x, c.y])
	else:
		_pent_place(c)

func _pent_rot(q: int, cw: bool) -> void:
	if not _pent_my_turn() or pent_phase != 1:
		return
	if app._net_on():
		app._send_game_action("_rpc_pent_rotate", [q, cw])
	else:
		_pent_do_rotate(q, cw)

func _pent_quad_rect(q: int) -> Rect2:
	return _pent_presentation.quad_rect(app, q)

func _btns_pentago() -> void:
	_pent_presentation.build_buttons(app, self)

func _draw_pentago() -> void:
	_pent_presentation.render(app, self)
