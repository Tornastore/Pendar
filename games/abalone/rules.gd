extends "res://core/game_module.gd"
## Standard two-player Abalone rules on a 61-cell hexagonal board.
## Axial coordinates (q, r) are stored in the 9x9 array with a +4 offset.

const ABA_DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1),
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 1),
]

var aba_board: Array = [] # 9x9; valid hex cells are 0/1/2 and off-hex cells are -1
var aba_turn: int = 1
var aba_sel: Vector2i = Vector2i(-99, -99)
var aba_selection: Array = []
var aba_out: Array = [0, 0] # number of each player's marbles pushed off the board
var aba_game_over: bool = false
var aba_winner: int = 0
var aba_difficulty: int = 3 # 1 random .. 6 opponent-reply search

func reset_game() -> void:
	_reset_abalone()

func _aba_valid_cell(q: int, r: int) -> bool:
	return absi(q) <= 4 and absi(r) <= 4 and absi(q + r) <= 4

func _aba_value(q: int, r: int) -> int:
	if not _aba_valid_cell(q, r):
		return -1
	return int(aba_board[r + 4][q + 4])

func _aba_set(q: int, r: int, value: int) -> void:
	if _aba_valid_cell(q, r):
		aba_board[r + 4][q + 4] = value

func _reset_abalone() -> void:
	aba_board = []
	for gy in range(9):
		var row: Array = []
		for gx in range(9):
			var q: int = gx - 4
			var r: int = gy - 4
			row.append(0 if _aba_valid_cell(q, r) else -1)
		aba_board.append(row)
	# Standard opening: 14 marbles per side (5 + 6 + 3), mirrored around the center.
	for q in range(0, 5):
		_aba_set(q, -4, 2)
	for q in range(-1, 5):
		_aba_set(q, -3, 2)
	for q in range(0, 3):
		_aba_set(q, -2, 2)
	for q in range(-4, 1):
		_aba_set(q, 4, 1)
	for q in range(-4, 2):
		_aba_set(q, 3, 1)
	for q in range(-2, 1):
		_aba_set(q, 2, 1)
	aba_turn = 1
	aba_sel = Vector2i(-99, -99)
	aba_selection.clear()
	aba_out = [0, 0]
	aba_game_over = false
	aba_winner = 0

func _aba_group_axis(cells: Array) -> Vector2i:
	if cells.size() < 2:
		return Vector2i.ZERO
	for direction in ABA_DIRECTIONS:
		var cross_ref: int = int(cells[0].x) * direction.y - int(cells[0].y) * direction.x
		var min_projection: int = 999
		var max_projection: int = -999
		var on_same_line: bool = true
		var projection_seen: Dictionary = {}
		for cell in cells:
			var c: Vector2i = cell
			if c.x * direction.y - c.y * direction.x != cross_ref:
				on_same_line = false
				break
			var projection: int = c.x * direction.x if direction.x != 0 else c.y * direction.y
			if projection_seen.has(projection):
				on_same_line = false
				break
			projection_seen[projection] = true
			min_projection = mini(min_projection, projection)
			max_projection = maxi(max_projection, projection)
		if on_same_line and max_projection - min_projection == cells.size() - 1:
			return direction
	return Vector2i.ZERO

func _aba_normalize_group(cells: Array) -> Array:
	var result: Array = cells.duplicate()
	if result.size() <= 1:
		return result
	var axis: Vector2i = _aba_group_axis(result)
	if axis == Vector2i.ZERO:
		return []
	for i in range(result.size()):
		for j in range(i + 1, result.size()):
			var pi: Vector2i = result[i]
			var pj: Vector2i = result[j]
			var proj_i: int = pi.x * axis.x + pi.y * axis.y
			var proj_j: int = pj.x * axis.x + pj.y * axis.y
			if proj_i > proj_j:
				result[i] = pj
				result[j] = pi
	return result

func _aba_front_cell(cells: Array, direction: Vector2i) -> Vector2i:
	var front: Vector2i = cells[0]
	var max_projection: int = front.x * direction.x + front.y * direction.y
	for raw_cell in cells:
		var cell: Vector2i = raw_cell
		var projection: int = cell.x * direction.x + cell.y * direction.y
		if projection > max_projection:
			max_projection = projection
			front = cell
	return front

func _aba_moves_for_selection(raw_cells: Array, player: int) -> Array:
	var moves: Array = []
	if aba_game_over or player < 1 or player > 2 or player != aba_turn:
		return moves
	if raw_cells.is_empty() or raw_cells.size() > 3:
		return moves
	var cells: Array = _aba_normalize_group(raw_cells)
	if cells.size() != raw_cells.size():
		return moves
	for cell in cells:
		var c: Vector2i = cell
		if not _aba_valid_cell(c.x, c.y) or _aba_value(c.x, c.y) != player:
			return moves
	var axis: Vector2i = _aba_group_axis(cells)
	if cells.size() > 1 and axis == Vector2i.ZERO:
		return moves
	var opponent: int = 3 - player
	for direction in ABA_DIRECTIONS:
		var inline: bool = cells.size() == 1 or direction == axis or direction == -axis
		if inline:
			var front: Vector2i = _aba_front_cell(cells, direction)
			var next_cell: Vector2i = front + direction
			if not _aba_valid_cell(next_cell.x, next_cell.y):
				continue
			var next_value: int = _aba_value(next_cell.x, next_cell.y)
			if next_value == 0:
				moves.append({"cells": cells.duplicate(), "dx": direction.x, "dy": direction.y, "push": 0, "out": 0, "click": next_cell, "inline": true})
			elif next_value == opponent and cells.size() > 1:
				var enemy_count: int = 0
				var cursor: Vector2i = next_cell
				while _aba_valid_cell(cursor.x, cursor.y) and _aba_value(cursor.x, cursor.y) == opponent:
					enemy_count += 1
					cursor += direction
				if enemy_count > 0 and enemy_count < cells.size() and enemy_count <= 2:
					if not _aba_valid_cell(cursor.x, cursor.y) or _aba_value(cursor.x, cursor.y) == 0:
						var pushed_out: int = 0
						var enemy_cell: Vector2i = next_cell
						for n in range(enemy_count):
							if not _aba_valid_cell(enemy_cell.x + direction.x, enemy_cell.y + direction.y):
								pushed_out += 1
							enemy_cell += direction
						moves.append({"cells": cells.duplicate(), "dx": direction.x, "dy": direction.y, "push": enemy_count, "out": pushed_out, "click": next_cell, "inline": true})
		else:
			var target_cells: Array = []
			var all_clear: bool = true
			for cell in cells:
				var target: Vector2i = Vector2i(cell) + direction
				if not _aba_valid_cell(target.x, target.y) or _aba_value(target.x, target.y) != 0:
					all_clear = false
					break
				target_cells.append(target)
			if all_clear:
				var click_cell: Vector2i = Vector2i(cells[0]) + direction
				moves.append({"cells": cells.duplicate(), "dx": direction.x, "dy": direction.y, "push": 0, "out": 0, "click": click_cell, "inline": false})
	return moves

func _aba_move_key(cells: Array, dx: int, dy: int) -> String:
	var pieces: Array[String] = []
	for raw_cell in cells:
		var cell: Vector2i = raw_cell
		pieces.append("%d,%d" % [cell.x, cell.y])
	pieces.sort()
	var joined: String = ""
	for piece in pieces:
		joined += (";" if joined != "" else "") + piece
	return joined + (":%d,%d" % [dx, dy])

func _aba_generate_all_moves(player: int) -> Array:
	var moves: Array = []
	var seen: Dictionary = {}
	if aba_game_over or player != aba_turn:
		return moves
	for r in range(-4, 5):
		for q in range(-4, 5):
			if _aba_value(q, r) != player:
				continue
			var start := Vector2i(q, r)
			for axis in ABA_DIRECTIONS:
				for count in range(1, 4):
					var group: Array = []
					var group_ok: bool = true
					for n in range(count):
						var cell: Vector2i = start + axis * n
						if not _aba_valid_cell(cell.x, cell.y) or _aba_value(cell.x, cell.y) != player:
							group_ok = false
							break
						group.append(cell)
					if not group_ok:
						break
					for move in _aba_moves_for_selection(group, player):
						var key: String = _aba_move_key(move.cells, int(move.dx), int(move.dy))
						if not seen.has(key):
							seen[key] = true
							moves.append(move)
	return moves

func _aba_apply_group_move(raw_cells: Array, dx: int, dy: int, player: int) -> bool:
	if aba_game_over or player != aba_turn:
		return false
	var cells: Array = _aba_normalize_group(raw_cells)
	var legal_move: Dictionary = {}
	for candidate in _aba_moves_for_selection(cells, player):
		if int(candidate.dx) == dx and int(candidate.dy) == dy:
			legal_move = candidate
			break
	if legal_move.is_empty():
		return false
	var direction := Vector2i(dx, dy)
	var opponent: int = 3 - player
	var pushed: int = int(legal_move.push)
	if pushed > 0:
		var front: Vector2i = _aba_front_cell(cells, direction)
		# Shift the farthest opposing marble first, so no marble is overwritten.
		for index in range(pushed - 1, -1, -1):
			var source: Vector2i = front + direction * (index + 1)
			var target: Vector2i = source + direction
			if not _aba_valid_cell(target.x, target.y):
				_aba_set(source.x, source.y, 0)
				aba_out[opponent - 1] += 1
			else:
				_aba_set(target.x, target.y, opponent)
				_aba_set(source.x, source.y, 0)
	# Clear all source cells first; this is necessary for in-line movement.
	for source in cells:
		var from_cell: Vector2i = source
		_aba_set(from_cell.x, from_cell.y, 0)
	for source in cells:
		var from_cell2: Vector2i = source
		var to_cell: Vector2i = from_cell2 + direction
		_aba_set(to_cell.x, to_cell.y, player)
	aba_selection.clear()
	aba_sel = Vector2i(-99, -99)
	if aba_out[opponent - 1] >= 6:
		aba_game_over = true
		aba_winner = player
		app._go_result()
	else:
		aba_turn = opponent
	return true

func _aba_cpu_move_score(move: Dictionary, player: int = 2) -> float:
	var level: int = clampi(aba_difficulty, 1, 6)
	var push_weights: Array[float] = [5.0, 8.0, 12.0, 16.0, 20.0, 24.0]
	var out_weights: Array[float] = [80.0, 105.0, 130.0, 155.0, 180.0, 210.0]
	var edge_weights: Array[float] = [0.35, 0.65, 1.0, 1.4, 1.8, 2.2]
	var cohesion_weights: Array[float] = [0.35, 0.6, 0.95, 1.25, 1.6, 1.9]
	var score: float = float(move.push) * push_weights[level - 1] + float(move.out) * out_weights[level - 1]
	var direction := Vector2i(int(move.dx), int(move.dy))
	var moved_cells: Array = move.cells
	for raw_cell in moved_cells:
		var cell: Vector2i = raw_cell
		var target: Vector2i = cell + direction
		var margin: int = mini(4 - absi(target.x), mini(4 - absi(target.y), 4 - absi(target.x + target.y)))
		score += float(margin) * edge_weights[level - 1]
		# Prefer cohesive groups, but avoid measuring the selected group's old positions as support.
		var adjacent_friends: int = 0
		for d in ABA_DIRECTIONS:
			var neighbor: Vector2i = target + d
			if moved_cells.has(neighbor):
				continue
			if _aba_value(neighbor.x, neighbor.y) == player:
				adjacent_friends += 1
		score += float(adjacent_friends) * cohesion_weights[level - 1]
	var noise_by_level: Array[float] = [0.0, 18.0, 8.0, 3.5, 0.6, 0.0]
	var noise: float = noise_by_level[level - 1]
	return score + randf_range(-noise, noise)

func _aba_simulate_move_for_ai(move: Dictionary, player: int) -> void:
	var cells: Array = _aba_normalize_group(move.cells)
	var direction := Vector2i(int(move.dx), int(move.dy))
	var opponent: int = 3 - player
	var pushed: int = int(move.push)
	if pushed > 0:
		var front: Vector2i = _aba_front_cell(cells, direction)
		for index in range(pushed - 1, -1, -1):
			var source: Vector2i = front + direction * (index + 1)
			var target: Vector2i = source + direction
			if not _aba_valid_cell(target.x, target.y):
				_aba_set(source.x, source.y, 0)
				aba_out[opponent - 1] += 1
			else:
				_aba_set(target.x, target.y, opponent)
				_aba_set(source.x, source.y, 0)
	for raw_source in cells:
		var source_cell: Vector2i = raw_source
		_aba_set(source_cell.x, source_cell.y, 0)
	for raw_source in cells:
		var from_cell: Vector2i = raw_source
		var to_cell: Vector2i = from_cell + direction
		_aba_set(to_cell.x, to_cell.y, player)

func _aba_cpu() -> void:
	if aba_game_over or aba_turn != 2:
		return
	var moves: Array = _aba_generate_all_moves(2)
	if moves.is_empty():
		aba_turn = 1
		return
	var level: int = clampi(aba_difficulty, 1, 6)
	if level == 1:
		var random_move: Dictionary = moves[randi() % moves.size()]
		_aba_apply_group_move(random_move.cells, int(random_move.dx), int(random_move.dy), 2)
		return
	var ranked: Array = []
	for move in moves:
		ranked.append({"move": move, "score": _aba_cpu_move_score(move, 2)})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.score) > float(b.score)
	)
	var chosen: Dictionary = ranked[0].move
	if level >= 5:
		var search_count: int = mini(ranked.size(), 10 if level == 5 else 18)
		var saved_board: Array = aba_board.duplicate(true)
		var saved_out: Array = aba_out.duplicate()
		var saved_turn: int = aba_turn
		var best_score: float = -INF
		for index in range(search_count):
			var candidate: Dictionary = ranked[index].move
			aba_board = saved_board.duplicate(true)
			aba_out = saved_out.duplicate()
			aba_turn = 2
			_aba_simulate_move_for_ai(candidate, 2)
			var score: float = float(ranked[index].score)
			if aba_out[0] >= 6:
				score += 100000.0
			elif aba_out[1] >= 6:
				score -= 200000.0
			else:
				var candidate_board: Array = aba_board.duplicate(true)
				var candidate_out: Array = aba_out.duplicate()
				aba_turn = 1
				var replies: Array = _aba_generate_all_moves(1)
				var reply_ranked: Array = _aba_rank_actions(replies, 1, 10 if level == 5 else 12)
				var strongest_reply: float = -INF
				for reply_entry in reply_ranked:
					strongest_reply = maxf(strongest_reply, float(reply_entry.score))
				if strongest_reply > -INF and level == 5:
					score -= strongest_reply * 0.82
				if level == 6:
					# Grandmaster continues after the opponent's strongest plausible replies.
					var worst_line: float = INF
					for reply_entry in reply_ranked.slice(0, mini(8, reply_ranked.size())):
						aba_board = candidate_board.duplicate(true)
						aba_out = candidate_out.duplicate()
						aba_turn = 1
						_aba_simulate_move_for_ai(reply_entry.move, 1)
						var line_value: float
						if aba_out[1] >= 6:
							line_value = -100000.0
						elif aba_out[0] >= 6:
							line_value = 100000.0
						else:
							aba_turn = 2
							var cpu_replies: Array = _aba_generate_all_moves(2)
							var cpu_ranked: Array = _aba_rank_actions(cpu_replies, 2, 7)
							var continuation: float = -INF
							for cpu_entry in cpu_ranked:
								continuation = maxf(continuation, float(cpu_entry.score))
							line_value = -float(reply_entry.score) * 0.72 + (continuation if continuation > -INF else 0.0) * 0.55
						worst_line = minf(worst_line, line_value)
					if worst_line < INF:
						score += worst_line * 0.58
			if score > best_score:
				best_score = score
				chosen = candidate
		aba_board = saved_board
		aba_out = saved_out
		aba_turn = saved_turn

	_aba_apply_group_move(chosen.cells, int(chosen.dx), int(chosen.dy), 2)


func _aba_rank_actions(moves: Array, player: int, limit: int) -> Array:
	var result: Array = []
	for move in moves:
		result.append({"move": move, "score": _aba_cpu_move_score(move, player)})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.score) > float(b.score)
	)
	if limit > 0 and result.size() > limit:
		result.resize(limit)
	return result

func _aba_me() -> int:
	return app._my_seat() + 1

func _aba_pixel(q: int, r: int) -> Vector2:
	var cell_size: float = app.ABA_CELL
	return app.ABA_ORIGIN + Vector2((float(q) + float(r) * 0.5) * cell_size, float(r) * cell_size * 0.8660254)

func _aba_hit_cell(p: Vector2) -> Vector2i:
	var best_cell := Vector2i(-99, -99)
	var best_distance: float = INF
	for r in range(-4, 5):
		for q in range(-4, 5):
			if not _aba_valid_cell(q, r):
				continue
			var distance: float = _aba_pixel(q, r).distance_to(p)
			if distance < best_distance:
				best_distance = distance
				best_cell = Vector2i(q, r)
	if best_distance > app.ABA_CELL * 0.46:
		return Vector2i(-99, -99)
	return best_cell

func _aba_tap(p: Vector2) -> void:
	if aba_game_over or aba_turn != _aba_me():
		return
	var tapped: Vector2i = _aba_hit_cell(p)
	if tapped.x == -99:
		return
	if not aba_selection.is_empty():
		var moves: Array = _aba_moves_for_selection(aba_selection, aba_turn)
		for move in moves:
			if Vector2i(move.click) == tapped:
				if app._net_on():
					var encoded: PackedInt32Array = PackedInt32Array()
					for raw_cell in aba_selection:
						var source_cell: Vector2i = raw_cell
						encoded.append(source_cell.x)
						encoded.append(source_cell.y)
					app._send_game_action("_rpc_aba_move", [encoded, int(move.dx), int(move.dy), aba_turn])
				else:
					_aba_apply_group_move(aba_selection.duplicate(), int(move.dx), int(move.dy), aba_turn)
				return
	if _aba_value(tapped.x, tapped.y) == aba_turn:
		if aba_selection.has(tapped):
			if aba_selection.size() == 1:
				aba_selection.clear()
				aba_sel = Vector2i(-99, -99)
			else:
				aba_selection = [tapped]
				aba_sel = tapped
			return
		var candidate: Array = aba_selection.duplicate()
		candidate.append(tapped)
		if candidate.size() <= 3 and (candidate.size() == 1 or _aba_group_axis(candidate) != Vector2i.ZERO):
			aba_selection = _aba_normalize_group(candidate)
			aba_sel = tapped
		else:
			aba_selection = [tapped]
			aba_sel = tapped
		return
	if not aba_selection.is_empty():
		app._show_toast("خانه‌ی انتخاب‌شده مقصد مجازی نیست؛ یکی از خانه‌های علامت‌خورده را بزنید.")

func _draw_abalone() -> void:
	var flat: Array = []
	for gy in range(9):
		for gx in range(9):
			flat.append(aba_board[gy][gx])
	app._track_board("aba", flat)
	var me: int = _aba_me()
	var white_col: Color = Color(0.9, 0.9, 0.95)
	var black_col: Color = Color(0.15, 0.15, 0.2)
	var pa: Dictionary = app._pl("شما", white_col if me == 1 else black_col, app._fa(aba_out[me - 1]), aba_turn == me and not aba_game_over, true, "مهره‌ی خارج‌شده", 1 if me == 1 else 0)
	var pb: Dictionary = app._pl("حریف", black_col if me == 1 else white_col, app._fa(aba_out[2 - me]), aba_turn == 3 - me and not aba_game_over, false, "مهره‌ی خارج‌شده", 0 if me == 1 else 1)
	app._draw_hud("ابلون", pa, pb)
	app._draw_ai_difficulty_chip(aba_difficulty)
	var o: Vector2 = app.ABA_ORIGIN
	var cs: float = app.ABA_CELL
	app._panel(Rect2(o - Vector2(cs * 4.9, cs * 4.05), Vector2(cs * 9.8, cs * 8.1)), Color(0.10, 0.12, 0.23), 30, Color(0.55, 0.5, 0.95, 0.40), 1.5, 22, 8)
	var legal_targets: Array[Vector2i] = []
	if not aba_selection.is_empty() and _aba_me() == aba_turn:
		for move in _aba_moves_for_selection(aba_selection, aba_turn):
			var target: Vector2i = move.click
			if not legal_targets.has(target):
				legal_targets.append(target)
	for r in range(-4, 5):
		for q in range(-4, 5):
			if not _aba_valid_cell(q, r):
				continue
			var cell := Vector2i(q, r)
			var center: Vector2 = _aba_pixel(q, r)
			app.draw_circle(center + Vector2(0, 2), cs * 0.43, Color(0.03, 0.04, 0.10, 0.8))
			app.draw_circle(center, cs * 0.40, Color(0.20, 0.23, 0.39))
			if legal_targets.has(cell):
				app.draw_circle(center, cs * 0.16, Color(app.ACCENT.r, app.ACCENT.g, app.ACCENT.b, 0.88))
			var value: int = _aba_value(q, r)
			if value != 0:
				var idx: int = (r + 4) * 9 + q + 4
				var t: float = app._cell_t("aba", idx)[0]
				app._draw_disc(center, cs * 0.35 * (app._ease_back(t) if t < 1.0 else 1.0), value == 1)
			if legal_targets.has(cell):
				# Outline occupied push targets too, so their marker remains visible above the marble.
				app._ring(center, cs * 0.44, app.ACCENT, 2.5)
			if aba_selection.has(cell):
				app._ring(center, cs * 0.43, app.ACCENT, 3.0)
	if not aba_game_over:
		if aba_turn != me:
			app._hint("حریف در حال بازی…", 668, app.TEXT_DIM)
		elif aba_selection.is_empty():
			app._hint("یک، دو یا سه مهره‌ی هم‌رنگ و هم‌راستا را انتخاب کنید", 668, app.TEXT_DIM)
		else:
			app._hint("خانه‌ی علامت‌خورده را بزنید تا مهره‌ها حرکت کنند", 668, app.TEXT_DIM)
		app._hint("با برتری عددی می‌توان مهره‌های حریف را هل داد؛ خروج ۶ مهره = برد", 708, app.TEXT_DIM)
