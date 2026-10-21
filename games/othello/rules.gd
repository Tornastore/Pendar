extends "res://core/game_module.gd"
## Rule engine and authoritative state for othello.

const OthelloAIScript = preload("res://games/othello/ai.gd")

# ---------- Game-owned state ----------
var oth_size: int = 8
var oth_difficulty: int = 3
var othello_board: Array = []    # 8x8, 0 empty, 1 black, 2 white
var othello_turn: int = 1       # 1 black, 2 white
var othello_last_move: Vector2i = Vector2i(-1, -1)
var othello_valid: Array = []
var othello_scores: Array = [0, 0, 0]
var othello_game_over: bool = false
var othello_winner: int = 0

func reset_game() -> void:
	_reset_othello()

func _reset_othello() -> void:
	if oth_size < 8:
		oth_size = 8
	othello_board = []
	for y in oth_size:
		var row: Array = []
		for x in oth_size:
			row.append(0)
		othello_board.append(row)
	var m: int = int(oth_size / 2)
	othello_board[m - 1][m - 1] = 2
	othello_board[m - 1][m] = 1
	othello_board[m][m - 1] = 1
	othello_board[m][m] = 2
	othello_turn = 1
	othello_last_move = Vector2i(-1, -1)
	othello_game_over = false
	othello_winner = 0
	_othello_update_valid()
	_othello_update_scores()

func _othello_update_scores() -> void:
	othello_scores = [0, 0, 0]
	for y in oth_size:
		for x in oth_size:
			othello_scores[othello_board[y][x]] += 1

func _othello_in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < oth_size and c.y >= 0 and c.y < oth_size

func _othello_would_flip(c: Vector2i, color: int) -> Array:
	var flips: Array = []
	if othello_board[c.y][c.x] != 0:
		return flips
	for d in app.OTH_DIRS:
		var dir: Vector2i = d
		var line: Array = []
		var p: Vector2i = c + dir
		while _othello_in_bounds(p) and othello_board[p.y][p.x] == 3 - color:
			line.append(p)
			p += dir
		if line.size() > 0 and _othello_in_bounds(p) and othello_board[p.y][p.x] == color:
			flips.append_array(line)
	return flips

func _othello_update_valid() -> void:
	othello_valid.clear()
	for y in oth_size:
		for x in oth_size:
			var c := Vector2i(x, y)
			if _othello_would_flip(c, othello_turn).size() > 0:
				othello_valid.append(c)

func _othello_place(c: Vector2i) -> bool:
	var flips: Array = _othello_would_flip(c, othello_turn)
	if flips.size() == 0:
		return false
	if app._net_on():
		app._send_game_action("_rpc_othello_place", [c.x, c.y])
	else:
		_othello_apply_place(c)
	return true

func _othello_apply_place(c: Vector2i) -> void:
	var flips: Array = _othello_would_flip(c, othello_turn)
	if flips.size() == 0 and othello_board[c.y][c.x] != 0:
		return
	othello_board[c.y][c.x] = othello_turn
	for f in flips:
		othello_board[f.y][f.x] = othello_turn
	othello_last_move = c
	othello_turn = 3 - othello_turn
	_othello_update_valid()
	_othello_update_scores()
	if othello_valid.size() == 0:
		othello_turn = 3 - othello_turn
		_othello_update_valid()
		if othello_valid.size() == 0:
			othello_game_over = true
			if othello_scores[1] > othello_scores[2]:
				othello_winner = 1
			elif othello_scores[2] > othello_scores[1]:
				othello_winner = 2
			else:
				othello_winner = 0
			app._go_result()

func _othello_cpu_move() -> void:
	if othello_valid.size() == 0 or othello_game_over or othello_turn != 2:
		return
	var ai = OthelloAIScript.new()
	var best: Vector2i = ai.choose_move(othello_board, oth_size, othello_turn, oth_difficulty)
	if best.x < 0 or best.y < 0 or best not in othello_valid:
		best = othello_valid[0]
	_othello_place(best)

func _oth_cell() -> float:
	return 60.0 if oth_size == 8 else 40.0

func _oth_origin() -> Vector2:
	var cell: float = _oth_cell()
	return Vector2((app.VIEW_W - cell * oth_size) * 0.5, 200.0)

func _oth_my_turn() -> bool:
	if app.vs_cpu:
		return othello_turn == 1
	return app._is_my_turn()

func _othello_tap(p: Vector2) -> void:
	if othello_game_over or not _oth_my_turn():
		return
	var cell: float = _oth_cell()
	var o: Vector2 = _oth_origin()
	var gx: int = int(floor((p.x - o.x) / cell))
	var gy: int = int(floor((p.y - o.y) / cell))
	if gx >= 0 and gx < oth_size and gy >= 0 and gy < oth_size:
		if not _othello_place(Vector2i(gx, gy)):
			app._show_toast("این خانه حرکت مجاز نیست؛ خانه‌های نقطه‌دار را انتخاب کنید.")

func _draw_othello() -> void:
	var flat: Array = []
	for y in oth_size:
		for x in oth_size:
			flat.append(othello_board[y][x])
	app._track_board("oth", flat)
	var mine_turn: bool = _oth_my_turn()
	var pa: Dictionary = app._pl("سیاه", Color(0.1, 0.1, 0.14), app._fa(othello_scores[1]), othello_turn == 1 and not othello_game_over, app._seat_me(0), "", 0)
	var pb: Dictionary = app._pl("سفید", Color(0.9, 0.9, 0.95), app._fa(othello_scores[2]), othello_turn == 2 and not othello_game_over, app._seat_me(1), "", 1)
	app._draw_hud("اتلو %s×%s" % [app._fa(oth_size), app._fa(oth_size)], pa, pb)
	var cell: float = _oth_cell()
	var o: Vector2 = _oth_origin()
	var bs: float = cell * oth_size
	app._panel(Rect2(o - Vector2(12, 12), Vector2(bs + 24, bs + 24)), Color(0.07, 0.22, 0.17), 22, Color(0.25, 0.65, 0.5, 0.45), 1.5, 22, 8)
	for y in oth_size:
		for x in oth_size:
			var r := Rect2(o.x + x * cell + 1, o.y + y * cell + 1, cell - 2, cell - 2)
			var shade: float = 0.0 if (x + y) % 2 == 0 else 0.025
			app._panel(r, Color(0.13 + shade, 0.46 + shade, 0.33 + shade), 5 if oth_size == 8 else 4)
	var valid_col := Color(1, 1, 1, 0.5)
	for y in oth_size:
		for x in oth_size:
			var idx: int = y * oth_size + x
			var cc := Vector2(o.x + x * cell + cell * 0.5, o.y + y * cell + cell * 0.5)
			var pr: float = cell * 0.37
			var v: int = othello_board[y][x]
			if v != 0:
				var at: Array = app._cell_t("oth", idx)
				var t: float = at[0]
				var old: int = at[1]
				if t < 1.0 and old == 0:
					app._draw_disc(cc, pr * app._ease_back(t), v == 2)
				elif t < 1.0 and old != 0 and old != v:
					var sx: float = absf(cos(PI * t))
					var lightv: bool = (v == 2) if t > 0.5 else (old == 2)
					app.draw_set_transform(cc, 0.0, Vector2(maxf(0.08, sx), 1.0))
					app._draw_disc(Vector2.ZERO, pr * (1.0 + 0.12 * sin(PI * t)), lightv)
					app.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				else:
					app._draw_disc(cc, pr, v == 2)
			elif mine_turn and not othello_game_over and Vector2i(x, y) in othello_valid:
				app._hint_dot(cc, cell * 0.10, app.ACCENT)
	if othello_last_move.x >= 0:
		var lm := Vector2(o.x + othello_last_move.x * cell + cell * 0.5, o.y + othello_last_move.y * cell + cell * 0.5)
		app._ring(lm, cell * 0.43, Color(app.ACCENT.r, app.ACCENT.g, app.ACCENT.b, 0.9), 2.5)
	# score bar
	var total: float = float(maxi(1, othello_scores[1] + othello_scores[2]))
	var bar := Rect2(o.x, o.y + bs + 34, bs, 14)
	app._panel(bar, Color(0.9, 0.9, 0.95), 7)
	var bw: float = bs * float(othello_scores[1]) / total
	if bw > 0.0:
		app._panel(Rect2(bar.position, Vector2(maxf(14.0, bw), 14)), Color(0.08, 0.09, 0.13), 7, Color(1, 1, 1, 0.25), 1.0)
	if mine_turn and not othello_game_over:
		app._hint("خانه‌های نقطه‌دار حرکت‌های مجاز هستند", o.y + bs + 62, app.TEXT_DIM)
	elif not othello_game_over:
		app._hint("حریف در حال حرکت…", o.y + bs + 62, app.TEXT_DIM)
