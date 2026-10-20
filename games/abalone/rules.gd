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
		app.state = app.State.RESULT
		app._build_result_buttons()
	else:
		aba_turn = opponent
	return true

func _aba_cpu_move_score(move: Dictionary) -> float:
	var score: float = float(move.push) * 14.0 + float(move.out) * 120.0
	var direction := Vector2i(int(move.dx), int(move.dy))
	for raw_cell in move.cells:
		var cell: Vector2i = raw_cell
		var target: Vector2i = cell + direction
		var margin: int = mini(4 - absi(target.x), mini(4 - absi(target.y), 4 - absi(target.x + target.y)))
		score += float(margin) * 1.2
		# Small preference for keeping friendly marbles in contact.
		var adjacent_friends: int = 0
		for d in ABA_DIRECTIONS:
			if _aba_value(target.x + d.x, target.y + d.y) == 2:
				adjacent_friends += 1
		score += float(adjacent_friends) * 1.4
	return score + randf() * 0.5

func _aba_cpu() -> void:
	if aba_game_over or aba_turn != 2:
		return
	var moves: Array = _aba_generate_all_moves(2)
	if moves.is_empty():
		aba_turn = 1
		return
	var best_score: float = -INF
	var best_moves: Array = []
	for move in moves:
		var score: float = _aba_cpu_move_score(move)
		if score > best_score + 0.001:
			best_score = score
			best_moves = [move]
		elif absf(score - best_score) <= 0.001:
			best_moves.append(move)
	var chosen: Dictionary = best_moves[randi() % best_moves.size()]
	_aba_apply_group_move(chosen.cells, int(chosen.dx), int(chosen.dy), 2)

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
					app.rpc("_rpc_aba_move", encoded, int(move.dx), int(move.dy), aba_turn)
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
