extends "res://core/game_module.gd"
## Rule engine and authoritative state for abalone.

# ---------- Game-owned state ----------
var aba_board: Array = []  # hex simplified as 9x9 with nulls
var aba_turn: int = 1
var aba_sel: Vector2i = Vector2i(-1, -1)
var aba_out: Array = [0, 0]
var aba_game_over: bool = false
var aba_winner: int = 0

func reset_game() -> void:
	_reset_abalone()

func _reset_abalone() -> void:
	# 9x9 grid, center playable roughly; 1 white 2 black 0 empty -1 invalid
	aba_board = []
	for y in 9:
		var row: Array = []
		for x in 9:
			row.append(0)
		aba_board.append(row)
	# place some pieces
	for x in range(2, 7):
		aba_board[0][x] = 2
		aba_board[1][x] = 2
	for x in range(2, 7):
		aba_board[8][x] = 1
		aba_board[7][x] = 1
	aba_turn = 1
	aba_sel = Vector2i(-1, -1)
	aba_out = [0, 0]
	aba_game_over = false
	aba_winner = 0

func _aba_cpu() -> void:
	for y in 9:
		for x in 9:
			if aba_board[y][x] == 2:
				for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
					var n: Vector2i = Vector2i(x, y) + d
					if n.x >= 0 and n.x < 9 and n.y >= 0 and n.y < 9 and aba_board[n.y][n.x] == 0:
						aba_board[n.y][n.x] = 2
						aba_board[y][x] = 0
						aba_turn = 1
						return
	aba_turn = 1

func _aba_me() -> int:
	return app._my_seat() + 1

func _aba_apply_move(from: Vector2i, to: Vector2i) -> void:
	if aba_game_over or aba_board[from.y][from.x] != aba_turn or aba_board[to.y][to.x] != 0:
		return
	aba_board[to.y][to.x] = aba_turn
	aba_board[from.y][from.x] = 0
	aba_sel = Vector2i(-1, -1)
	aba_turn = 3 - aba_turn

func _aba_tap(p: Vector2) -> void:
	if aba_game_over or aba_turn != _aba_me():
		return
	var gx: int = int(floor((p.x - app.ABA_ORIGIN.x) / app.ABA_CELL))
	var gy: int = int(floor((p.y - app.ABA_ORIGIN.y) / app.ABA_CELL))
	if gx < 0 or gx > 8 or gy < 0 or gy > 8:
		return
	if aba_board[gy][gx] == aba_turn:
		aba_sel = Vector2i(gx, gy)
		return
	if aba_sel.x >= 0:
		var dx: int = gx - aba_sel.x
		var dy: int = gy - aba_sel.y
		if absi(dx) + absi(dy) == 1 and aba_board[gy][gx] == 0:
			if app._net_on():
				app.rpc("_rpc_aba_move", aba_sel.x, aba_sel.y, gx, gy)
				aba_sel = Vector2i(-1, -1)
			else:
				_aba_apply_move(aba_sel, Vector2i(gx, gy))
		else:
			aba_sel = Vector2i(-1, -1)

func _draw_abalone() -> void:
	var flat: Array = []
	for y in 9:
		for x in 9:
			flat.append(aba_board[y][x])
	app._track_board("aba", flat)
	var me: int = _aba_me()
	var pa: Dictionary = app._pl("شما", Color(0.9, 0.9, 0.95) if me == 1 else Color(0.15, 0.15, 0.2), app._fa(aba_out[me - 1]), aba_turn == me and not aba_game_over, true, "", 1 if me == 1 else 0)
	var pb: Dictionary = app._pl("حریف", Color(0.15, 0.15, 0.2) if me == 1 else Color(0.9, 0.9, 0.95), app._fa(aba_out[2 - me]), aba_turn == 3 - me and not aba_game_over, false, "", 0 if me == 1 else 1)
	app._draw_hud("ابلون (آزمایشی)", pa, pb)
	var o: Vector2 = app.ABA_ORIGIN
	var cs: float = app.ABA_CELL
	app._panel(Rect2(o - Vector2(12, 12), Vector2(cs * 9 + 24, cs * 9 + 24)), Color(0.12, 0.12, 0.26), 26, Color(0.55, 0.5, 0.95, 0.4), 1.5, 22, 8)
	for y in 9:
		for x in 9:
			var cc := Vector2(o.x + x * cs + cs * 0.5, o.y + y * cs + cs * 0.5)
			app.draw_circle(cc, cs * 0.42, Color(0.06, 0.06, 0.16))
			app.draw_circle(cc + Vector2(0, 1), cs * 0.39, Color(0.15, 0.15, 0.32))
	for y in 9:
		for x in 9:
			var v: int = aba_board[y][x]
			var cc2 := Vector2(o.x + x * cs + cs * 0.5, o.y + y * cs + cs * 0.5)
			if v != 0:
				var t: float = app._cell_t("aba", y * 9 + x)[0]
				app._draw_disc(cc2, cs * 0.36 * (app._ease_back(t) if t < 1.0 else 1.0), v == 1)
			if aba_sel == Vector2i(x, y):
				app._ring(cc2, cs * 0.44, app.ACCENT, 3.0)
	if aba_sel.x >= 0:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = aba_sel + d
			if n.x >= 0 and n.x < 9 and n.y >= 0 and n.y < 9 and aba_board[n.y][n.x] == 0:
				app._hint_dot(Vector2(o.x + n.x * cs + cs * 0.5, o.y + n.y * cs + cs * 0.5), 7, app.ACCENT)
	app._hint("مهره را انتخاب و به خانه کناری ببرید" if aba_turn == me else "حریف در حال بازی…", 668, app.TEXT_DIM)
	app._hint("نسخه آزمایشی: قانون هل‌دادن هنوز اضافه نشده", 708, Color(1.0, 0.8, 0.45))
