extends RefCounted
## Abalone geometry and board presentation; all selection, push and movement rules remain in rules.gd.

func cell_center(app, q: int, r: int) -> Vector2:
	var cell_size: float = app.ABA_CELL
	return app.ABA_ORIGIN + Vector2((float(q) + float(r) * 0.5) * cell_size, float(r) * cell_size * 0.8660254)

func hit_cell(app, game, p: Vector2) -> Vector2i:
	var best_cell := Vector2i(-99, -99)
	var best_distance: float = INF
	for r in range(-4, 5):
		for q in range(-4, 5):
			if not game._aba_valid_cell(q, r):
				continue
			var distance: float = cell_center(app, q, r).distance_to(p)
			if distance < best_distance:
				best_distance = distance
				best_cell = Vector2i(q, r)
	if best_distance > app.ABA_CELL * 0.46:
		return Vector2i(-99, -99)
	return best_cell

func handle_tap(app, game, point: Vector2) -> void:
	game._aba_handle_cell_tap(hit_cell(app, game, point))

func render(app, game) -> void:
	var flat: Array = []
	for gy in range(9):
		for gx in range(9):
			flat.append(game.aba_board[gy][gx])
	app._track_board("aba", flat)
	var me: int = game._aba_me()
	var white_col: Color = Color(0.9, 0.9, 0.95)
	var black_col: Color = Color(0.15, 0.15, 0.2)
	var pa: Dictionary = app._pl("شما", white_col if me == 1 else black_col, app._fa(game.aba_out[me - 1]), game.aba_turn == me and not game.aba_game_over, true, "مهره‌ی خارج‌شده", 1 if me == 1 else 0)
	var pb: Dictionary = app._pl("حریف", black_col if me == 1 else white_col, app._fa(game.aba_out[2 - me]), game.aba_turn == 3 - me and not game.aba_game_over, false, "مهره‌ی خارج‌شده", 0 if me == 1 else 1)
	app._draw_hud("ابلون", pa, pb)
	app._draw_ai_difficulty_chip(game.aba_difficulty)
	var o: Vector2 = app.ABA_ORIGIN
	var cs: float = app.ABA_CELL
	app._panel(Rect2(o - Vector2(cs * 4.9, cs * 4.05), Vector2(cs * 9.8, cs * 8.1)), Color(0.10, 0.12, 0.23), 30, Color(0.55, 0.5, 0.95, 0.40), 1.5, 22, 8)
	var legal_targets: Array[Vector2i] = []
	if not game.aba_selection.is_empty() and game._aba_me() == game.aba_turn:
		for move in game._aba_moves_for_selection(game.aba_selection, game.aba_turn):
			var target: Vector2i = move.click
			if not legal_targets.has(target):
				legal_targets.append(target)
	for r in range(-4, 5):
		for q in range(-4, 5):
			if not game._aba_valid_cell(q, r):
				continue
			var cell := Vector2i(q, r)
			var center: Vector2 = cell_center(app, q, r)
			app.draw_circle(center + Vector2(0, 2), cs * 0.43, Color(0.03, 0.04, 0.10, 0.8))
			app.draw_circle(center, cs * 0.40, Color(0.20, 0.23, 0.39))
			if legal_targets.has(cell):
				app.draw_circle(center, cs * 0.16, Color(app.ACCENT.r, app.ACCENT.g, app.ACCENT.b, 0.88))
			var value: int = game._aba_value(q, r)
			if value != 0:
				var idx: int = (r + 4) * 9 + q + 4
				var t: float = app._cell_t("aba", idx)[0]
				app._draw_disc(center, cs * 0.35 * (app._ease_back(t) if t < 1.0 else 1.0), value == 1)
			if legal_targets.has(cell):
				# Outline occupied push targets too, so their marker remains visible above the marble.
				app._ring(center, cs * 0.44, app.ACCENT, 2.5)
			if game.aba_selection.has(cell):
				app._ring(center, cs * 0.43, app.ACCENT, 3.0)
	if not game.aba_game_over:
		if game.aba_turn != me:
			app._hint("حریف در حال بازی…", 668, app.TEXT_DIM)
		elif game.aba_selection.is_empty():
			app._hint("یک، دو یا سه مهره‌ی هم‌رنگ و هم‌راستا را انتخاب کنید", 668, app.TEXT_DIM)
		else:
			app._hint("خانه‌ی علامت‌خورده را بزنید تا مهره‌ها حرکت کنند", 668, app.TEXT_DIM)
		app._hint("با برتری عددی می‌توان مهره‌های حریف را هل داد؛ خروج ۶ مهره = برد", 708, app.TEXT_DIM)
