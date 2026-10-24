extends RefCounted
## Quarto layout, pointer-to-cell mapping, piece palette buttons and rendering.
## Piece selection, legal placement, wins, turns, CPU and network actions stay in rules.gd.

func board_origin(app) -> Vector2:
	return Vector2((app.VIEW_W - (app.QUARTO_CELL * 4.0 + app.QUARTO_GAP * 3.0)) * 0.5, app.QUARTO_ORIGIN_Y)

func piece_rect(app, piece: int) -> Rect2:
	var col: int = piece % 4
	var row: int = int(piece / 4)
	return Rect2(24.0 + col * 124.0, 584.0 + row * 46.0, 116.0, 40.0)

func handle_tap(app, game, point: Vector2) -> void:
	var cell := Vector2i(-1, -1)
	var origin: Vector2 = board_origin(app)
	var cell_size: float = app.QUARTO_CELL
	var gap: float = app.QUARTO_GAP
	for y in range(4):
		for x in range(4):
			var rect := Rect2(origin.x + x * (cell_size + gap), origin.y + y * (cell_size + gap), cell_size, cell_size)
			if rect.has_point(point):
				cell = Vector2i(x, y)
				break
		if cell.x >= 0:
			break
	game._qto_handle_board_tap(cell)

func build_buttons(app, game) -> void:
	if game.qto_game_over or game.qto_phase != 0 or not game._qto_is_local_actor():
		return
	for raw_piece in game.qto_remaining:
		var piece: int = int(raw_piece)
		app._add_hit(piece_rect(app, piece), game._qto_pick_piece.bind(piece), "quarto_piece_%d" % piece, false, true)

func render(app, game) -> void:
	var c1: Color = Color(0.39, 0.67, 1.0)
	var c2: Color = Color(1.0, 0.49, 0.48)
	var pa: Dictionary = app._pl("بازیکن ۱", c1, "", game.qto_turn == 1 and not game.qto_game_over, app._seat_me(0), "انتخاب / جای‌گذاری")
	var pb: Dictionary = app._pl("بازیکن ۲", c2, "", game.qto_turn == 2 and not game.qto_game_over, app._seat_me(1), "انتخاب / جای‌گذاری")
	app._draw_hud("کوارتو · Quarto", pa, pb)
	var mine_turn: bool = game._qto_is_local_actor()
	var instruction: String = "یک مهره برای حریف انتخاب کنید" if game.qto_phase == 0 else "مهره‌ی انتخاب‌شده را روی صفحه بگذارید"
	var status := Rect2(22, 151, app.VIEW_W - 44, 28)
	app._panel(status, app.CARD, 14, Color(0.75, 0.62, 0.92, 0.42), 1.0)
	app._txt_c(instruction if mine_turn else "حریف در حال تصمیم‌گیری…", status, 13, app.TEXT if mine_turn else app.TEXT_DIM, true)
	if game.qto_phase == 1 and game.qto_piece_to_place >= 0:
		app._draw_quarto_piece(Vector2(app.VIEW_W - 48, 165), game.qto_piece_to_place, 0.82, 1.0)
	var origin: Vector2 = board_origin(app)
	var cell: float = app.QUARTO_CELL
	var gap: float = app.QUARTO_GAP
	var board_size := Vector2(cell * 4.0 + gap * 3.0, cell * 4.0 + gap * 3.0)
	var board_rect := Rect2(origin - Vector2(10, 10), board_size + Vector2(20, 20))
	app._panel(board_rect, Color(0.12, 0.12, 0.23), 18, Color(0.75, 0.62, 0.92, 0.58), 1.3, 14, 6)
	for y in range(4):
		for x in range(4):
			var rect := Rect2(origin.x + x * (cell + gap), origin.y + y * (cell + gap), cell, cell)
			var col: Color = Color(0.18, 0.20, 0.34) if (x + y) % 2 == 0 else Color(0.14, 0.16, 0.28)
			app._panel(rect, col, 9, app.LINE, 0.8)
			if Vector2i(x, y) == game.qto_last_cell:
				app._panel(rect.grow(-2), Color(0.24, 0.62, 0.45, 0.14), 8, Color(0.30, 0.92, 0.65, 0.8), 1.8)
			var piece: int = int(game.qto_board[y][x])
			if piece >= 0:
				app._draw_quarto_piece(rect.get_center(), piece, 1.0, 1.0)
			else:
				app._txt_c(app._fa(y * 4 + x + 1), rect, 11, app.TEXT_FAINT, false)
	app._hint("بلند/کوتاه · گرد/مربع · تیره/روشن · توپر/توخالی", 531, app.TEXT_DIM)
	app._txt_r("مهره‌های قابل انتخاب", app.VIEW_W - 24, 559, 13, app.TEXT_DIM, true, 220)
	for piece in range(16):
		var rect: Rect2 = piece_rect(app, piece)
		var available: bool = piece in game.qto_remaining
		var can_pick: bool = available and game.qto_phase == 0 and mine_turn
		app._panel(rect, app.CARD_H if can_pick else (app.CARD if available else Color(0.08, 0.09, 0.15, 0.78)), 9, app.ACCENT if can_pick else app.LINE, 1.1 if can_pick else 0.7)
		app._draw_quarto_piece(Vector2(rect.position.x + 26, rect.get_center().y), piece, 0.80, 1.0 if available else 0.20)
		app._txt_c(app._fa(piece + 1), Rect2(rect.position.x + 48, rect.position.y, rect.size.x - 50, rect.size.y), 12, app.TEXT if available else app.TEXT_FAINT, true)
	if game.qto_game_over:
		app._hint("بازی تمام شد · وضعیت نهایی حفظ شده است", 780, app.TEXT_DIM)
	elif game.qto_phase == 0:
		app._hint("مهره‌ی انتخابی به حریف داده می‌شود؛ ویژگی‌ها را بررسی کنید", 780, app.ACCENT if mine_turn else app.TEXT_DIM)
	else:
		app._hint("یک خانه‌ی خالی انتخاب کنید؛ چهار ویژگی مشترک یعنی برد", 780, app.ACCENT if mine_turn else app.TEXT_DIM)
	app._draw_ai_difficulty_chip_at(game.qto_difficulty, 820.0)
