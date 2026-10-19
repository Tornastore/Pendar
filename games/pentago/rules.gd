extends "res://core/game_module.gd"
## Rule engine and authoritative state for pentago.

# ---------- Game-owned state ----------
var pent_board: Array = []      # 6x6
var pent_turn: int = 1
var pent_phase: int = 0         # 0 place, 1 rotate
var pent_last: Vector2i = Vector2i(-1, -1)
var pent_game_over: bool = false
var pent_winner: int = 0
var pent_selected_quad: int = -1

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
		app.state = State.RESULT
		app._build_result_buttons()
		return true
	pent_phase = 1
	app._build_pent_rotate_buttons()
	return true

func _pent_do_rotate(quad: int, clockwise: bool) -> void:
	_pent_rotate(quad, clockwise)
	if _pent_check_win(pent_turn):
		pent_game_over = true
		pent_winner = pent_turn
		app.state = State.RESULT
		app._build_result_buttons()
		return
	# also check opponent (rare double win)
	if _pent_check_win(3 - pent_turn):
		pent_game_over = true
		pent_winner = 3 - pent_turn
		app.state = State.RESULT
		app._build_result_buttons()
		return
	pent_turn = 3 - pent_turn
	pent_phase = 0
	pent_selected_quad = -1
	app._build_playing_buttons()

func _pent_cpu_move() -> void:
	if pent_phase == 0:
		# random empty
		var empties: Array = []
		for y in 6:
			for x in 6:
				if pent_board[y][x] == 0:
					empties.append(Vector2i(x, y))
		if empties.size() > 0:
			_pent_place(empties[randi() % empties.size()])
	else:
		_pent_do_rotate(randi() % 4, randi() % 2 == 0)

func _pent_origin() -> Vector2:
	return Vector2((app.VIEW_W - (app.PENT_CELL * 6.0 + app.PENT_GAP)) * 0.5, 196.0)

func _pent_cell_pos(x: int, y: int) -> Vector2:
	var o: Vector2 = _pent_origin()
	return o + Vector2(x * app.PENT_CELL + (app.PENT_GAP if x >= 3 else 0.0), y * app.PENT_CELL + (app.PENT_GAP if y >= 3 else 0.0))

func _pent_my_turn() -> bool:
	if app.vs_cpu:
		return pent_turn == 1
	return app._is_my_turn()

func _pent_tap(p: Vector2) -> void:
	if pent_game_over or pent_phase != 0 or not _pent_my_turn():
		return
	for y in 6:
		for x in 6:
			var r := Rect2(_pent_cell_pos(x, y), Vector2(app.PENT_CELL, app.PENT_CELL))
			if r.has_point(p):
				if pent_board[y][x] != 0:
					return
				if not app.vs_cpu and app.multiplayer.multiplayer_peer != null:
					app.rpc("_rpc_pent_place", x, y)
				else:
					_pent_place(Vector2i(x, y))
				return

func _pent_rot(q: int, cw: bool) -> void:
	if not _pent_my_turn() or pent_phase != 1:
		return
	if not app.vs_cpu and app.multiplayer.multiplayer_peer != null:
		app.rpc("_rpc_pent_rotate", q, cw)
	else:
		_pent_do_rotate(q, cw)

func _pent_quad_rect(q: int) -> Rect2:
	var o: Vector2 = _pent_origin()
	var qs: float = app.PENT_CELL * 3.0
	return Rect2(o.x + (q % 2) * (qs + app.PENT_GAP), o.y + int(q / 2) * (qs + app.PENT_GAP), qs, qs)

func _btns_pentago() -> void:
	if pent_phase != 1 or not _pent_my_turn() or pent_game_over:
		return
	var names: Array = ["بالا چپ", "بالا راست", "پایین چپ", "پایین راست"]
	for q in 4:
		var qr: Rect2 = _pent_quad_rect(q)
		var gy: float = 676.0 + int(q / 2) * 64.0
		var x0: float = qr.position.x
		app._add_btn(Rect2(x0, gy, 62, 52), "", _pent_rot.bind(q, false), true, app.ACCENT, "disc", "rot_ccw", "rot_%d_ccw" % q)
		app._add_btn(Rect2(x0 + qr.size.x - 62, gy, 62, 52), "", _pent_rot.bind(q, true), true, app.ACCENT, "disc", "rot_cw", "rot_%d_cw" % q)

func _draw_pentago() -> void:
	var flat: Array = []
	for y in 6:
		for x in 6:
			flat.append(pent_board[y][x])
	app._track_board("pent", flat)
	var pa: Dictionary = app._pl("سیاه", Color(0.1, 0.1, 0.14), "", pent_turn == 1 and not pent_game_over, app._seat_me(0), "", 0)
	var pb: Dictionary = app._pl("سفید", Color(0.9, 0.9, 0.95), "", pent_turn == 2 and not pent_game_over, app._seat_me(1), "", 1)
	var ph: String = "قرار دادن مهره" if pent_phase == 0 else "چرخش یک بخش"
	if pent_turn == 1:
		pa.sub = ph if not pent_game_over else ""
	else:
		pb.sub = ph if not pent_game_over else ""
	app._draw_hud("پنتاگو", pa, pb)
	var hov: int = -1
	if app._press_active and app._press_id.begins_with("rot_"):
		hov = int(app._press_id.substr(4, 1))
	for q in 4:
		var qr: Rect2 = _pent_quad_rect(q)
		var glow: bool = (pent_phase == 1 and _pent_my_turn() and not pent_game_over)
		var hl: bool = (q == hov)
		app._panel(qr.grow(6), Color(0.33, 0.22, 0.12) if not hl else Color(0.55, 0.38, 0.18), 22, Color(app.ACCENT.r, app.ACCENT.g, app.ACCENT.b, 0.9) if hl else (Color(0.8, 0.6, 0.3, 0.35 + 0.15 * sin(app._time * 3.0)) if glow else Color(0.8, 0.6, 0.3, 0.25)), 2.0 if hl else 1.5, 14, 6)
	for y in 6:
		for x in 6:
			var tl: Vector2 = _pent_cell_pos(x, y)
			var cc: Vector2 = tl + Vector2(app.PENT_CELL, app.PENT_CELL) * 0.5
			app.draw_circle(cc, 27, Color(0.12, 0.08, 0.04))
			app.draw_circle(cc + Vector2(0, 1.5), 25, Color(0.20, 0.13, 0.07))
			var v: int = pent_board[y][x]
			if v != 0:
				var t: float = app._cell_t("pent", y * 6 + x)[0]
				var rr: float = 23.0 * (app._ease_back(t) if t < 1.0 else 1.0)
				app._draw_disc(cc, rr, v == 2)
	if pent_last.x >= 0:
		var lc: Vector2 = _pent_cell_pos(pent_last.x, pent_last.y) + Vector2(app.PENT_CELL, app.PENT_CELL) * 0.5
		app._ring(lc, 28, Color(app.ACCENT.r, app.ACCENT.g, app.ACCENT.b, 0.9), 2.5)
	if not pent_game_over:
		if pent_phase == 0:
			app._hint("یک خانه خالی را انتخاب کنید" if _pent_my_turn() else "حریف در حال حرکت…", 650, app.TEXT_DIM)
		else:
			if _pent_my_turn():
				app._hint("یک بخش را با دکمه‌های زیر بچرخانید", 646, app.ACCENT)
			else:
				app._hint("حریف در حال چرخاندن…", 646, app.TEXT_DIM)
	if pent_phase == 1 and _pent_my_turn() and not pent_game_over:
		var names: Array = ["بالا چپ", "بالا راست", "پایین چپ", "پایین راست"]
		for q in 4:
			var qr2: Rect2 = _pent_quad_rect(q)
			var gy: float = 676.0 + int(q / 2) * 64.0
			app._txt_c(names[q], Rect2(qr2.position.x + 62, gy, qr2.size.x - 124, 52), 14, app.TEXT_DIM, true)
