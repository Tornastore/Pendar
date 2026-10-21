extends "res://core/game_module.gd"
## Blokus Duo (2-player) with the full 21-piece polyomino set and LAN turn sync.
## Rule: first piece covers the player's start square; later pieces must touch own colour
## diagonally, never along an edge. Opponent pieces may be touched by edges or corners.

const BOARD_SIZE: int = 14
const ORTHO: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIAGONAL: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

var blk_grid: Array = []
var blk_turn: int = 0
var blk_pieces: Array = []
var blk_used: Array = [[], []]
var blk_sel: int = 0
var blk_game_over: bool = false
var blk_winner: int = -1
var blk_rot: int = 0
var blk_flip: bool = false
var blk_prev: Vector2i = Vector2i(-1, -1)
var blk_difficulty: int = 3
var blk_scores: Array = [0, 0]
var blk_last_piece_size: Array = [0, 0]

func reset_game() -> void:
	_reset_blockace()

func _blk_piece_set() -> Array:
	# Standard 21 free polyominoes: 1 monomino, 1 domino, 2 trominoes,
	# 5 tetrominoes and all 12 pentominoes.
	return [
		[Vector2i(0, 0)],
		[Vector2i(0, 0), Vector2i(1, 0)],
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
		[Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)],
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)],
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)],
		[Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)],
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)],
		# Pentominoes: F, I, L, P, N, T, U, V, W, X, Y, Z.
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2)],
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)],
		[Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(1, 3)],
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2)],
		[Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3)],
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(1, 2)],
		[Vector2i(0, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)],
		[Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 2)],
		[Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)],
		[Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(1, 1)],
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 2)],
	]

func _reset_blockace() -> void:
	blk_grid = []
	for y in range(BOARD_SIZE):
		var row: Array = []
		for x in range(BOARD_SIZE):
			row.append(0)
		blk_grid.append(row)
	blk_pieces = _blk_piece_set()
	blk_used = [[], []]
	for p in range(2):
		for i in range(blk_pieces.size()):
			blk_used[p].append(false)
	blk_turn = 0
	blk_sel = 0
	blk_game_over = false
	blk_winner = -1
	blk_rot = 0
	blk_flip = false
	blk_prev = Vector2i(-1, -1)
	blk_scores = [0, 0]
	blk_last_piece_size = [0, 0]

func _blk_used_count(player: int) -> int:
	var count: int = 0
	if player < 0 or player > 1 or blk_used.size() <= player:
		return 0
	for value in blk_used[player]:
		if bool(value):
			count += 1
	return count

func _blk_first_available(player: int) -> int:
	for i in range(blk_pieces.size()):
		if not bool(blk_used[player][i]):
			return i
	return 0

func _blk_cells(idx: int, rot: int, flipped: bool = false) -> Array:
	if idx < 0 or idx >= blk_pieces.size():
		return []
	var cells: Array = []
	for origin in blk_pieces[idx]:
		var v: Vector2i = Vector2i(-origin.x, origin.y) if flipped else origin
		for k in range(rot % 4):
			v = Vector2i(-v.y, v.x)
		cells.append(v)
	var min_x: int = 999
	var min_y: int = 999
	for v in cells:
		min_x = mini(min_x, v.x)
		min_y = mini(min_y, v.y)
	var normalized: Array = []
	for v in cells:
		normalized.append(Vector2i(v.x - min_x, v.y - min_y))
	return normalized

func _blk_can_place(px: int, py: int, piece: Array, player: int, piece_id: int = -1) -> bool:
	if player < 0 or player > 1 or piece.is_empty():
		return false
	if piece_id >= 0 and (piece_id >= blk_used[player].size() or bool(blk_used[player][piece_id])):
		return false
	var absolute_cells: Array = []
	for offset in piece:
		var x: int = px + offset.x
		var y: int = py + offset.y
		if x < 0 or x >= BOARD_SIZE or y < 0 or y >= BOARD_SIZE:
			return false
		if int(blk_grid[y][x]) != 0:
			return false
		absolute_cells.append(Vector2i(x, y))

	# The first piece must cover the player's marked starting corner.
	if _blk_used_count(player) == 0:
		# Blokus Duo places its marked start squares inside the 14×14 field so every piece can cover them.
		var start_cell := Vector2i(4, 4) if player == 0 else Vector2i(9, 9)
		return absolute_cells.has(start_cell)

	# Later pieces may touch own pieces diagonally, but never by an edge.
	var own_diagonal_contact: bool = false
	for cell in absolute_cells:
		for delta in ORTHO:
			var neighbor: Vector2i = cell + delta
			if neighbor.x >= 0 and neighbor.x < BOARD_SIZE and neighbor.y >= 0 and neighbor.y < BOARD_SIZE:
				if int(blk_grid[neighbor.y][neighbor.x]) == player + 1:
					return false
		for delta in DIAGONAL:
			var neighbor2: Vector2i = cell + delta
			if neighbor2.x >= 0 and neighbor2.x < BOARD_SIZE and neighbor2.y >= 0 and neighbor2.y < BOARD_SIZE:
				if int(blk_grid[neighbor2.y][neighbor2.x]) == player + 1:
					own_diagonal_contact = true
	return own_diagonal_contact

func _blk_has_move(player: int) -> bool:
	for i in range(blk_pieces.size()):
		if bool(blk_used[player][i]):
			continue
		for flip in range(2):
			for r in range(4):
				var cells: Array = _blk_cells(i, r, flip == 1)
				for y in range(BOARD_SIZE):
					for x in range(BOARD_SIZE):
						if _blk_can_place(x, y, cells, player, i):
							return true
	return false

func _blk_place(px: int, py: int, piece: Array, player: int, piece_id: int, rot: int, flipped: bool) -> void:
	if blk_game_over or not _blk_can_place(px, py, piece, player, piece_id):
		return
	for offset in piece:
		blk_grid[py + offset.y][px + offset.x] = player + 1
	blk_used[player][piece_id] = true
	blk_last_piece_size[player] = piece.size()
	blk_prev = Vector2i(-1, -1)
	blk_rot = 0
	blk_flip = false
	blk_turn = 1 - player
	blk_sel = _blk_first_available(blk_turn)

	if _blk_has_move(blk_turn):
		return
	if _blk_has_move(player):
		blk_turn = player
		blk_sel = _blk_first_available(player)
		app._show_toast("حریف حرکت مجاز ندارد؛ نوبت او رد شد.")
		return
	_blk_finish_game()

func _blk_remaining_points(player: int) -> int:
	var remaining: int = 0
	for i in range(blk_pieces.size()):
		if not bool(blk_used[player][i]):
			remaining += blk_pieces[i].size()
	return remaining

func _blk_score_player(player: int) -> int:
	var remaining: int = _blk_remaining_points(player)
	var score: int = -remaining
	if _blk_used_count(player) == blk_pieces.size():
		score += 15
		if int(blk_last_piece_size[player]) == 1:
			score += 5
	return score

func _blk_finish_game() -> void:
	blk_game_over = true
	blk_scores = [_blk_score_player(0), _blk_score_player(1)]
	blk_winner = 0 if blk_scores[0] > blk_scores[1] else (1 if blk_scores[1] > blk_scores[0] else -1)
	app.state = State.RESULT
	app._build_result_buttons()

func _blk_move_score(move: Dictionary, player: int, difficulty: int) -> float:
	var cells: Array = _blk_cells(int(move.i), int(move.r), bool(move.f))
	var score: float = float(cells.size()) * 24.0
	var sum_x: float = 0.0
	var sum_y: float = 0.0
	var corner_set: Dictionary = {}
	var enemy_edges: int = 0
	for offset in cells:
		var cell := Vector2i(int(move.x) + offset.x, int(move.y) + offset.y)
		sum_x += float(cell.x)
		sum_y += float(cell.y)
		for diagonal in DIAGONAL:
			var target: Vector2i = cell + diagonal
			if target.x >= 0 and target.x < BOARD_SIZE and target.y >= 0 and target.y < BOARD_SIZE and int(blk_grid[target.y][target.x]) == 0:
				var blocked_by_own_edge: bool = false
				for orth in ORTHO:
					var adj: Vector2i = target + orth
					if adj.x >= 0 and adj.x < BOARD_SIZE and adj.y >= 0 and adj.y < BOARD_SIZE and int(blk_grid[adj.y][adj.x]) == player + 1:
						blocked_by_own_edge = true
						break
				if not blocked_by_own_edge:
					corner_set[target] = true
		for orth in ORTHO:
			var neighbor: Vector2i = cell + orth
			if neighbor.x >= 0 and neighbor.x < BOARD_SIZE and neighbor.y >= 0 and neighbor.y < BOARD_SIZE:
				if int(blk_grid[neighbor.y][neighbor.x]) == (2 if player == 0 else 1):
					enemy_edges += 1
	var avg_x: float = sum_x / float(maxi(1, cells.size()))
	var avg_y: float = sum_y / float(maxi(1, cells.size()))
	var progress: float = avg_x + avg_y if player == 0 else float(2 * (BOARD_SIZE - 1)) - avg_x - avg_y
	var center_distance: float = absf(avg_x - (BOARD_SIZE - 1) * 0.5) + absf(avg_y - (BOARD_SIZE - 1) * 0.5)
	score += progress * (0.4 + float(difficulty) * 0.65)
	if difficulty >= 3:
		score += (float(BOARD_SIZE) - center_distance) * float(difficulty - 2) * 1.4
	if difficulty >= 4:
		score += float(corner_set.size()) * float(difficulty) * 2.2
	if difficulty >= 5:
		score += float(enemy_edges) * float(difficulty - 3) * 1.2
	if difficulty >= 6:
		# Prefer moves that widen multiple diagonal entry points for later pentominoes.
		score += float(corner_set.size()) * 4.0
	score += randf() * (7.0 - float(difficulty)) * 5.0
	return score

func _blk_cpu() -> void:
	if blk_game_over or blk_turn != 1:
		return
	var moves: Array = []
	for i in range(blk_pieces.size()):
		if bool(blk_used[1][i]):
			continue
		for flipped_value in range(2):
			for r in range(4):
				var cells: Array = _blk_cells(i, r, flipped_value == 1)
				for y in range(BOARD_SIZE):
					for x in range(BOARD_SIZE):
						if _blk_can_place(x, y, cells, 1, i):
							moves.append({"x": x, "y": y, "i": i, "r": r, "f": flipped_value == 1})
	if moves.is_empty():
		if _blk_has_move(0):
			blk_turn = 0
			blk_sel = _blk_first_available(0)
		else:
			_blk_finish_game()
		return
	var level: int = clampi(blk_difficulty, 1, 6)
	var chosen: Dictionary = {}
	if level == 1:
		chosen = moves[randi() % moves.size()]
	else:
		for j in range(moves.size()):
			moves[j]["score"] = _blk_move_score(moves[j], 1, level)
		moves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.score) > float(b.score))
		var ratios: Array[float] = [1.0, 0.50, 0.25, 0.12, 0.05, 0.015]
		var pool: int = maxi(1, int(ceil(float(moves.size()) * ratios[level - 1])))
		chosen = moves[randi() % pool]
	_blk_place(int(chosen.x), int(chosen.y), _blk_cells(int(chosen.i), int(chosen.r), bool(chosen.f)), 1, int(chosen.i), int(chosen.r), bool(chosen.f))

func _blk_apply_net(px: int, py: int, sel: int, rot: int, flipped: bool, player: int) -> void:
	if blk_game_over or blk_turn != player or sel < 0 or sel >= blk_pieces.size():
		return
	var cells: Array = _blk_cells(sel, rot, flipped)
	if _blk_can_place(px, py, cells, player, sel):
		_blk_place(px, py, cells, player, sel, rot, flipped)
	blk_prev = Vector2i(-1, -1)

func _blk_me() -> int:
	return app._my_seat()

func _blk_confirm() -> void:
	var me: int = _blk_me()
	if blk_game_over or blk_turn != me or blk_prev.x < 0 or blk_sel < 0 or blk_sel >= blk_pieces.size():
		return
	var cells: Array = _blk_cells(blk_sel, blk_rot, blk_flip)
	if not _blk_can_place(blk_prev.x, blk_prev.y, cells, me, blk_sel):
		app._show_toast("این جای قطعه مجاز نیست؛ گوشه‌ها و خانه‌ی شروع را بررسی کنید.")
		return
	if app._net_on():
		app._send_game_action("_rpc_blk_place", [blk_prev.x, blk_prev.y, blk_sel, blk_rot, blk_flip, me])
	else:
		_blk_place(blk_prev.x, blk_prev.y, cells, me, blk_sel, blk_rot, blk_flip)
		app._rebuild_buttons()

func _blk_tap(p: Vector2) -> void:
	var me: int = _blk_me()
	if blk_game_over or blk_turn != me or app.vs_cpu and blk_turn == 1:
		return
	var gx: int = int(floor((p.x - app.BLK_ORIGIN.x) / app.BLK_CELL))
	var gy: int = int(floor((p.y - app.BLK_ORIGIN.y) / app.BLK_CELL))
	if gx < 0 or gx >= BOARD_SIZE or gy < 0 or gy >= BOARD_SIZE:
		return
	var target := Vector2i(gx, gy)
	if blk_prev == target:
		_blk_confirm()
	else:
		blk_prev = target
		app._rebuild_buttons()

func _blk_select(i: int) -> void:
	var me: int = _blk_me()
	if i < 0 or i >= blk_pieces.size() or blk_game_over or blk_turn != me or bool(blk_used[me][i]):
		return
	blk_sel = i
	blk_rot = 0
	blk_flip = false
	blk_prev = Vector2i(-1, -1)
	app._rebuild_buttons()

func _blk_rotate() -> void:
	blk_rot = (blk_rot + 1) % 4
	blk_prev = Vector2i(-1, -1)
	app._rebuild_buttons()

func _blk_flip_piece() -> void:
	blk_flip = not blk_flip
	blk_prev = Vector2i(-1, -1)
	app._rebuild_buttons()

func _btns_blockace() -> void:
	var me: int = _blk_me()
	for i in range(blk_pieces.size()):
		var col: int = i % 7
		var row: int = int(i / 7)
		var r := Rect2(8 + col * 75, 574 + row * 55, 70, 50)
		if not blk_game_over and blk_turn == me and not bool(blk_used[me][i]):
			app._add_hit(r, _blk_select.bind(i), "blk_p%d" % i)
	var can_interact: bool = not blk_game_over and blk_turn == me and not (app.vs_cpu and blk_turn == 1)
	app._add_btn(Rect2(16, 768, 150, 50), "چرخش", _blk_rotate, can_interact, app.BLUE, "soft", "rotate-cw", "blk_rot")
	app._add_btn(Rect2(178, 768, 150, 50), "وارونه", _blk_flip_piece, can_interact, app.ACCENT, "soft", "flip-horizontal", "blk_flip")
	var valid: bool = blk_prev.x >= 0 and blk_turn == me and not blk_game_over and _blk_can_place(blk_prev.x, blk_prev.y, _blk_cells(blk_sel, blk_rot, blk_flip), me, blk_sel)
	app._add_btn(Rect2(340, 768, 184, 50), "قراردادن", _blk_confirm, valid, app.GREEN, "solid", "check", "blk_ok")
	app._last_btn().hint = "هر قطعه باید روی خانه خالی قرار گیرد و با گوشه قطعات خودتان تماس داشته باشد."

func _draw_blk_cell(r: Rect2, col: Color) -> void:
	app._panel(r, col, 4)
	app._gloss(r, 4, 0.16)

func _draw_blockace() -> void:
	var flat: Array = []
	var c0: int = 0
	var c1: int = 0
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			flat.append(blk_grid[y][x])
			if blk_grid[y][x] == 1:
				c0 += 1
			elif blk_grid[y][x] == 2:
				c1 += 1
	app._track_board("blk", flat)
	var ca := Color(0.30, 0.82, 0.76)
	var cb := Color(1.0, 0.62, 0.35)
	var me: int = _blk_me()
	var pa: Dictionary = app._pl("شما", ca if me == 0 else cb, app._fa(c0 if me == 0 else c1), blk_turn == me and not blk_game_over, true, "خانه")
	var pb: Dictionary = app._pl("حریف", cb if me == 0 else ca, app._fa(c1 if me == 0 else c0), blk_turn == 1 - me and not blk_game_over, false, "خانه")
	if pa.active:
		pa.sub = "نوبت شما"
	app._draw_hud("بلاک‌آس · دوه نفره کامل", pa, pb)
	var o: Vector2 = app.BLK_ORIGIN
	var cs: float = app.BLK_CELL
	app._panel(Rect2(o - Vector2(8, 8), Vector2(cs * BOARD_SIZE + 16, cs * BOARD_SIZE + 16)), Color(0.10, 0.14, 0.22), 14, Color(0.3, 0.8, 0.75, 0.35), 1.5, 10, 4)
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			var r := Rect2(o.x + x * cs + 1.0, o.y + y * cs + 1.0, cs - 2.0, cs - 2.0)
			var value: int = int(blk_grid[y][x])
			if value == 0:
				app._panel(r, Color(1, 1, 1, 0.045), 3)
			else:
				var t: float = app._cell_t("blk", y * BOARD_SIZE + x)[0]
				var rr: Rect2 = r if t >= 1.0 else r.grow(-(1.0 - app._ease_out(t)) * 5.0)
				_draw_blk_cell(rr, ca if value == 1 else cb)
	# Highlight mandatory starting squares until each player makes the first move.
	for player in range(2):
		if _blk_used_count(player) == 0:
			var start := Vector2i(4, 4) if player == 0 else Vector2i(9, 9)
			var sr := Rect2(o.x + start.x * cs + 1, o.y + start.y * cs + 1, cs - 2, cs - 2)
			app._panel(sr, Color(ca.r, ca.g, ca.b, 0.25) if player == 0 else Color(cb.r, cb.g, cb.b, 0.25), 3, ca if player == 0 else cb, 1.2)
	if blk_prev.x >= 0 and blk_turn == me and not blk_game_over:
		var preview: Array = _blk_cells(blk_sel, blk_rot, blk_flip)
		var ok: bool = _blk_can_place(blk_prev.x, blk_prev.y, preview, me, blk_sel)
		for offset in preview:
			var px: int = blk_prev.x + offset.x
			var py: int = blk_prev.y + offset.y
			if px >= 0 and px < BOARD_SIZE and py >= 0 and py < BOARD_SIZE:
				var rr2 := Rect2(o.x + px * cs + 1, o.y + py * cs + 1, cs - 2, cs - 2)
				app._panel(rr2, Color(0.3, 0.9, 0.5, 0.60) if ok else Color(1.0, 0.3, 0.35, 0.60), 3, Color(1, 1, 1, 0.75), 1.0)
	# All 21 pieces are available in a compact 7 x 3 inventory tray.
	var current_player: int = blk_turn
	var piece_color: Color = ca if current_player == 0 else cb
	for i in range(blk_pieces.size()):
		var col: int = i % 7
		var row: int = int(i / 7)
		var rr3 := Rect2(8 + col * 75, 574 + row * 55, 70, 50)
		var used: bool = bool(blk_used[current_player][i])
		var selected: bool = (i == blk_sel and not used)
		app._panel(rr3, Color(0.10, 0.12, 0.17, 0.65) if used else (app.CARD_H if selected else app.CARD), 8, app.ACCENT if selected else Color(1, 1, 1, 0.13), 1.4 if selected else 0.7)
		var cells: Array = _blk_cells(i, blk_rot if selected else 0, blk_flip if selected else false)
		var max_x: int = 0
		var max_y: int = 0
		for cell in cells:
			max_x = maxi(max_x, cell.x)
			max_y = maxi(max_y, cell.y)
		var unit: float = 6.0
		var origin := rr3.get_center() - Vector2(float(max_x + 1) * unit * 0.5, float(max_y + 1) * unit * 0.5)
		for cell in cells:
			var small := Rect2(origin + Vector2(cell.x, cell.y) * unit, Vector2(unit - 0.8, unit - 0.8))
			_draw_blk_cell(small, Color(piece_color.r * 0.36, piece_color.g * 0.36, piece_color.b * 0.36) if used else piece_color)
		if used:
			app._txt_c("✓", rr3, 15, Color(1, 1, 1, 0.35), true)
	var level_text: String = "سطح CPU: %s" % app._fa(blk_difficulty) if app.vs_cpu else "قانون تماس گوشه‌ای"
	app._txt_c(level_text, Rect2(12, 739, app.VIEW_W - 24, 18), 11, app.TEXT_DIM, false)
	if not blk_game_over:
		if blk_turn == me:
			app._hint("قطعه را انتخاب کن، جهتش را عوض کن و محل را دو بار بزن یا قراردادن را بزن.", 840, app.TEXT_DIM)
		else:
			app._hint("حریف در حال بازی…", 840, app.TEXT_DIM)
