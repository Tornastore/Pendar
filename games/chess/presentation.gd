extends RefCounted
## Chess rendering and pointer-to-square mapping.
## Rules, selection state, moves, and network actions remain in rules.gd.

func is_flipped(app) -> bool:
	return not app.vs_cpu and app.local_seat == 1


func orient_cell(app, cell: Vector2i) -> Vector2i:
	return Vector2i(7 - cell.x, 7 - cell.y) if is_flipped(app) else cell


func cell_center(app, cell: Vector2i) -> Vector2:
	var screen_cell: Vector2i = orient_cell(app, cell)
	return app.CHESS_ORIGIN + Vector2(
		screen_cell.x * app.CHESS_CELL + app.CHESS_CELL * 0.5,
		screen_cell.y * app.CHESS_CELL + app.CHESS_CELL * 0.5
	)


func screen_to_board_cell(app, point: Vector2) -> Vector2i:
	if app.CHESS_CELL <= 0.0:
		return Vector2i(-1, -1)
	var gx: int = int(floor((point.x - app.CHESS_ORIGIN.x) / app.CHESS_CELL))
	var gy: int = int(floor((point.y - app.CHESS_ORIGIN.y) / app.CHESS_CELL))
	if gx < 0 or gx > 7 or gy < 0 or gy > 7:
		return Vector2i(-1, -1)
	return orient_cell(app, Vector2i(gx, gy))


func render(app, game) -> void:
	var flat: Array = []
	for y in 8:
		for x in 8:
			flat.append(game.chess_board[y][x])
	app._track_board("chess", flat)
	var pa: Dictionary = app._pl("سفید", Color(0.9, 0.9, 0.95), "", game.chess_turn == 1 and not game.chess_game_over, app._seat_me(0), "", 1)
	var pb: Dictionary = app._pl("سیاه", Color(0.1, 0.1, 0.14), "", game.chess_turn == 2 and not game.chess_game_over, app._seat_me(1), "", 0)
	var cnt: Array = [0, 0, 0]
	for y in 8:
		for x in 8:
			var cc: int = game._chess_color(game.chess_board[y][x])
			cnt[cc] += 1
	pa.score = app._fa(cnt[1])
	pb.score = app._fa(cnt[2])
	app._draw_hud("شطرنج", pa, pb)
	var cs: float = app.CHESS_CELL
	app._panel(Rect2(app.CHESS_ORIGIN - Vector2(10, 10), Vector2(cs * 8 + 20, cs * 8 + 20)), Color(0.20, 0.14, 0.10), 18, Color(0.7, 0.5, 0.3, 0.4), 1.5, 22, 8)
	var light := Color(0.91, 0.82, 0.65)
	var dark := Color(0.47, 0.33, 0.23)
	var chk1: Vector2i = game._chess_king_in_check(1)
	var chk2: Vector2i = game._chess_king_in_check(2)
	var files := "abcdefgh"
	for sy in 8:
		for sx in 8:
			var r := Rect2(app.CHESS_ORIGIN.x + sx * cs, app.CHESS_ORIGIN.y + sy * cs, cs, cs)
			var is_light: bool = (sx + sy) % 2 == 0
			app.draw_rect(r, light if is_light else dark)
			var bc: Vector2i = orient_cell(app, Vector2i(sx, sy))
			if game.chess_last[0] == bc or game.chess_last[1] == bc:
				app.draw_rect(r, Color(1.0, 0.85, 0.25, 0.38))
			if game.chess_selected == bc:
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
			var piece: int = game.chess_board[by][bx]
			if piece == 0:
				continue
			var cc2: Vector2 = cell_center(app, Vector2i(bx, by))
			var at: Array = app._cell_t("chess", by * 8 + bx, 0.28)
			if at[1] != 0 or (at[0] < 1.0 and game.chess_last[1] == Vector2i(bx, by)):
				if at[0] < 1.0 and game.chess_last[1] == Vector2i(bx, by) and game.chess_last[0].x >= 0:
					cc2 = cell_center(app, game.chess_last[0]).lerp(cc2, app._ease_out(at[0]))
			var white: bool = piece <= 6
			var typ: int = piece if white else piece - 6
			app._draw_chess_piece(typ, white, cc2, cs * 0.86)
	for v in game.chess_valid:
		var vc: Vector2 = cell_center(app, v)
		if game.chess_board[v.y][v.x] != 0:
			app._ring(vc, 27, Color(1.0, 0.35, 0.40, 0.95), 3.0)
		else:
			app._hint_dot(vc, 8, Color(0.2, 0.9, 0.5))
	# captured
	var start: Array = [0, 8, 2, 2, 2, 1, 1]
	var have_w: Array = [0, 0, 0, 0, 0, 0, 0]
	var have_b: Array = [0, 0, 0, 0, 0, 0, 0]
	for y in 8:
		for x in 8:
			var pv: int = game.chess_board[y][x]
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
	if game.chess_game_over:
		app._hint(game.chess_terminal_reason if game.chess_terminal_reason != "" else "بازی پایان یافت", 764, app.ACCENT)
	elif game._chess_king_in_check(game.chess_turn).x >= 0:
		app._hint("شاه در کیش است؛ حرکت قانونی را انتخاب کنید", 764, app.RED)
	elif game._chess_can_claim_draw():
		app._hint("امکان اعلام مساوی با قانون ۵۰ حرکت یا تکرار موقعیت", 764, app.ACCENT)
	elif not game.chess_promotion_pending.is_empty():
		app._hint("نوع مهره ارتقا را انتخاب کنید", 764, app.TEXT_DIM)
	elif game._chess_my_turn():
		app._hint("مهره خود را انتخاب کنید" if game.chess_selected.x < 0 else "مقصد را انتخاب کنید", 764, app.TEXT_DIM)
	else:
		app._hint("حریف در حال فکر کردن…", 764, app.TEXT_DIM)
