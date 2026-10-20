extends "res://core/game_module.gd"
## Rule engine and authoritative state for chess.

const ChessAIScript = preload("res://games/chess/ai.gd")

# ---------- Game-owned state ----------
var chess_difficulty: int = 3
var chess_board: Array = []
var chess_turn: int = 1           # 1 white, 2 black
var chess_selected: Vector2i = Vector2i(-1, -1)
var chess_valid: Array = []
var chess_game_over: bool = false
var chess_winner: int = 0
var chess_last: Array = [Vector2i(-1,-1), Vector2i(-1,-1)]  # from, to

func reset_game() -> void:
	_reset_chess()

func _reset_chess() -> void:
	chess_board = []
	# standard start
	var back := [4, 2, 3, 5, 6, 3, 2, 4]  # R N B Q K B N R
	for y in 8:
		var row: Array = []
		for x in 8:
			row.append(0)
		chess_board.append(row)
	for x in 8:
		chess_board[0][x] = back[x] + 6   # black
		chess_board[1][x] = 7            # black pawn
		chess_board[6][x] = 1            # white pawn
		chess_board[7][x] = back[x]      # white
	chess_turn = 1
	chess_selected = Vector2i(-1, -1)
	chess_valid = []
	chess_game_over = false
	chess_winner = 0
	chess_last = [Vector2i(-1,-1), Vector2i(-1,-1)]

func _chess_color(piece: int) -> int:
	if piece == 0:
		return 0
	return 1 if piece <= 6 else 2

func _chess_in(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < 8 and c.y >= 0 and c.y < 8

func _chess_gen_moves(from: Vector2i) -> Array:
	var piece: int = chess_board[from.y][from.x]
	if piece == 0:
		return []
	var col := _chess_color(piece)
	var typ := piece if col == 1 else piece - 6
	var moves: Array = []
	var enemy := 3 - col

	match typ:
		1:  # pawn
			var dir := -1 if col == 1 else 1
			var one := from + Vector2i(0, dir)
			if _chess_in(one) and chess_board[one.y][one.x] == 0:
				moves.append(one)
				var start_row := 6 if col == 1 else 1
				var two := from + Vector2i(0, dir * 2)
				if from.y == start_row and chess_board[two.y][two.x] == 0:
					moves.append(two)
			for dx in [-1, 1]:
				var cap: Vector2i = from + Vector2i(dx, dir)
				if _chess_in(cap) and _chess_color(chess_board[cap.y][cap.x]) == enemy:
					moves.append(cap)
		2:  # knight
			for d in [Vector2i(1,2), Vector2i(2,1), Vector2i(-1,2), Vector2i(-2,1), Vector2i(1,-2), Vector2i(2,-1), Vector2i(-1,-2), Vector2i(-2,-1)]:
				var dir: Vector2i = d
				var n: Vector2i = from + dir
				if _chess_in(n) and _chess_color(chess_board[n.y][n.x]) != col:
					moves.append(n)
		3, 4, 5:  # bishop, rook, queen
			var dirs: Array = []
			if typ == 3 or typ == 5:
				dirs.append_array([Vector2i(1,1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(-1,-1)])
			if typ == 4 or typ == 5:
				dirs.append_array([Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)])
			for d in dirs:
				var dir: Vector2i = d
				var n: Vector2i = from + dir
				while _chess_in(n):
					var pc: int = chess_board[n.y][n.x]
					if pc == 0:
						moves.append(n)
					elif _chess_color(pc) == enemy:
						moves.append(n)
						break
					else:
						break
					n += dir
		6:  # king
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var n := from + Vector2i(dx, dy)
					if _chess_in(n) and _chess_color(chess_board[n.y][n.x]) != col:
						moves.append(n)
	return moves

func _chess_all_moves(col: int) -> Array:
	var res: Array = []
	for y in 8:
		for x in 8:
			if _chess_color(chess_board[y][x]) == col:
				var from := Vector2i(x, y)
				for to in _chess_gen_moves(from):
					res.append([from, to])
	return res

func _chess_make_move(from: Vector2i, to: Vector2i) -> void:
	var piece: int = chess_board[from.y][from.x]
	# promotion
	if (piece == 1 and to.y == 0) or (piece == 7 and to.y == 7):
		piece = 5 if piece == 1 else 11  # queen
	chess_board[to.y][to.x] = piece
	chess_board[from.y][from.x] = 0
	chess_last = [from, to]
	chess_selected = Vector2i(-1, -1)
	chess_valid = []
	# check king captured (simple win condition for prototype)
	var has_king := [false, false, false]
	for y in 8:
		for x in 8:
			var p: int = chess_board[y][x]
			if p == 6:
				has_king[1] = true
			elif p == 12:
				has_king[2] = true
	if not has_king[1]:
		chess_game_over = true
		chess_winner = 2
		app.state = State.RESULT
		app._build_result_buttons()
		return
	if not has_king[2]:
		chess_game_over = true
		chess_winner = 1
		app.state = State.RESULT
		app._build_result_buttons()
		return
	chess_turn = 3 - chess_turn

func _chess_cpu_move() -> void:
	if chess_game_over or chess_turn != 2:
		return
	var ai = ChessAIScript.new()
	var best: Array = ai.choose_move(self, chess_difficulty)
	if best.is_empty():
		chess_game_over = true
		chess_winner = 1
		app.state = State.RESULT
		app._build_result_buttons()
		return
	_chess_make_move(best[0], best[1])

func _chess_king_in_check(col: int) -> Vector2i:
	var kp := Vector2i(-1, -1)
	var kv: int = 6 if col == 1 else 12
	for y in 8:
		for x in 8:
			if chess_board[y][x] == kv:
				kp = Vector2i(x, y)
	if kp.x < 0:
		return kp
	for y in 8:
		for x in 8:
			if _chess_color(chess_board[y][x]) == 3 - col:
				if kp in _chess_gen_moves(Vector2i(x, y)):
					return kp
	return Vector2i(-1, -1)

func _chess_flip() -> bool:
	return not app.vs_cpu and app.local_seat == 1

func _chess_scr(c: Vector2i) -> Vector2i:
	return Vector2i(7 - c.x, 7 - c.y) if _chess_flip() else c

func _chess_center(c: Vector2i) -> Vector2:
	var s: Vector2i = _chess_scr(c)
	return app.CHESS_ORIGIN + Vector2(s.x * app.CHESS_CELL + app.CHESS_CELL * 0.5, s.y * app.CHESS_CELL + app.CHESS_CELL * 0.5)

func _chess_my_turn() -> bool:
	if app.vs_cpu:
		return chess_turn == 1
	return app._is_my_turn()

func _chess_tap(p: Vector2) -> void:
	if chess_game_over or not _chess_my_turn():
		return
	var gx: int = int(floor((p.x - app.CHESS_ORIGIN.x) / app.CHESS_CELL))
	var gy: int = int(floor((p.y - app.CHESS_ORIGIN.y) / app.CHESS_CELL))
	if gx < 0 or gx > 7 or gy < 0 or gy > 7:
		return
	var c: Vector2i = _chess_scr(Vector2i(gx, gy))
	if chess_selected.x >= 0:
		if c in chess_valid:
			if not app.vs_cpu and app.multiplayer.multiplayer_peer != null:
				app.rpc("_rpc_chess_move", chess_selected.x, chess_selected.y, c.x, c.y)
			else:
				_chess_make_move(chess_selected, c)
			return
		chess_selected = Vector2i(-1, -1)
		chess_valid = []
	if _chess_color(chess_board[c.y][c.x]) == chess_turn:
		chess_selected = c
		chess_valid = _chess_gen_moves(c)

func _draw_chess() -> void:
	var flat: Array = []
	for y in 8:
		for x in 8:
			flat.append(chess_board[y][x])
	app._track_board("chess", flat)
	var pa: Dictionary = app._pl("سفید", Color(0.9, 0.9, 0.95), "", chess_turn == 1 and not chess_game_over, app._seat_me(0), "", 1)
	var pb: Dictionary = app._pl("سیاه", Color(0.1, 0.1, 0.14), "", chess_turn == 2 and not chess_game_over, app._seat_me(1), "", 0)
	var cnt: Array = [0, 0, 0]
	for y in 8:
		for x in 8:
			var cc: int = _chess_color(chess_board[y][x])
			cnt[cc] += 1
	pa.score = app._fa(cnt[1])
	pb.score = app._fa(cnt[2])
	app._draw_hud("شطرنج", pa, pb)
	var cs: float = app.CHESS_CELL
	app._panel(Rect2(app.CHESS_ORIGIN - Vector2(10, 10), Vector2(cs * 8 + 20, cs * 8 + 20)), Color(0.20, 0.14, 0.10), 18, Color(0.7, 0.5, 0.3, 0.4), 1.5, 22, 8)
	var light := Color(0.91, 0.82, 0.65)
	var dark := Color(0.47, 0.33, 0.23)
	var chk1: Vector2i = _chess_king_in_check(1)
	var chk2: Vector2i = _chess_king_in_check(2)
	var files := "abcdefgh"
	for sy in 8:
		for sx in 8:
			var r := Rect2(app.CHESS_ORIGIN.x + sx * cs, app.CHESS_ORIGIN.y + sy * cs, cs, cs)
			var is_light: bool = (sx + sy) % 2 == 0
			app.draw_rect(r, light if is_light else dark)
			var bc: Vector2i = _chess_scr(Vector2i(sx, sy))
			if chess_last[0] == bc or chess_last[1] == bc:
				app.draw_rect(r, Color(1.0, 0.85, 0.25, 0.38))
			if chess_selected == bc:
				app.draw_rect(r, Color(0.35, 0.65, 1.0, 0.55))
			if bc == chk1 or bc == chk2:
				app._glow(r.get_center(), 36, Color(1.0, 0.2, 0.25, 0.75))
			var lc: Color = dark if is_light else light
			if sx == 0:
				app._txt(str(8 - bc.y), r.position.x + 3, r.position.y + 13, 10, lc, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
			if sy == 7:
				app._txt(files[bc.x], r.end.x - 11, r.end.y - 4, 10, lc, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	for by in 8:
		for bx in 8:
			var piece: int = chess_board[by][bx]
			if piece == 0:
				continue
			var cc2: Vector2 = _chess_center(Vector2i(bx, by))
			var at: Array = app._cell_t("chess", by * 8 + bx, 0.28)
			if at[1] != 0 or (at[0] < 1.0 and chess_last[1] == Vector2i(bx, by)):
				if at[0] < 1.0 and chess_last[1] == Vector2i(bx, by) and chess_last[0].x >= 0:
					cc2 = _chess_center(chess_last[0]).lerp(cc2, app._ease_out(at[0]))
			var white: bool = piece <= 6
			var typ: int = piece if white else piece - 6
			app._draw_chess_piece(typ, white, cc2, cs * 0.86)
	for v in chess_valid:
		var vc: Vector2 = _chess_center(v)
		if chess_board[v.y][v.x] != 0:
			app._ring(vc, 27, Color(1.0, 0.35, 0.40, 0.95), 3.0)
		else:
			app._hint_dot(vc, 8, Color(0.2, 0.9, 0.5))
	# captured
	var start: Array = [0, 8, 2, 2, 2, 1, 1]
	var have_w: Array = [0, 0, 0, 0, 0, 0, 0]
	var have_b: Array = [0, 0, 0, 0, 0, 0, 0]
	for y in 8:
		for x in 8:
			var pv: int = chess_board[y][x]
			if pv >= 1 and pv <= 6:
				have_w[pv] += 1
			elif pv >= 7:
				have_b[pv - 6] += 1
	var rows_y: Array = [692.0, 726.0]
	for side in 2:
		var white_side: bool = (side == 0)
		var x: float = app.VIEW_W - 24.0
		app._txt_r("گرفته‌شده توسط " + ("سفید" if white_side else "سیاه"), app.VIEW_W - 24, rows_y[side] - 6, 11, app.TEXT_FAINT, false, 200)
		x = 24.0
		for typ in [1, 2, 3, 4, 5]:
			var miss: int = start[typ] - (have_b[typ] if white_side else have_w[typ])
			for k in miss:
				app._draw_chess_piece(typ, not white_side, Vector2(x + 11, rows_y[side] + 8), 24.0)
				x += 15.0
	if not chess_game_over:
		if _chess_my_turn():
			app._hint("مهره خود را انتخاب کنید" if chess_selected.x < 0 else "مقصد را انتخاب کنید", 764, app.TEXT_DIM)
		else:
			app._hint("حریف در حال فکر کردن…", 764, app.TEXT_DIM)
