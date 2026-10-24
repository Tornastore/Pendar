extends RefCounted
## Pentago board presentation, pointer mapping, and rotation-control layout.
## All game state changes, CPU plans, and network actions stay in Pentago rules.

func board_origin(app) -> Vector2:
	return Vector2((app.VIEW_W - (app.PENT_CELL * 6.0 + app.PENT_GAP)) * 0.5, 196.0)

func cell_pos(app, x: int, y: int) -> Vector2:
	var origin: Vector2 = board_origin(app)
	return origin + Vector2(x * app.PENT_CELL + (app.PENT_GAP if x >= 3 else 0.0), y * app.PENT_CELL + (app.PENT_GAP if y >= 3 else 0.0))

func quad_rect(app, q: int) -> Rect2:
	var origin: Vector2 = board_origin(app)
	var quad_size: float = app.PENT_CELL * 3.0
	return Rect2(origin.x + (q % 2) * (quad_size + app.PENT_GAP), origin.y + int(q / 2) * (quad_size + app.PENT_GAP), quad_size, quad_size)

func handle_tap(app, game, point: Vector2) -> void:
	# Convert the pointer to a logical cell; the rules module makes the legal decision.
	for y in range(6):
		for x in range(6):
			var cell_rect := Rect2(cell_pos(app, x, y), Vector2(app.PENT_CELL, app.PENT_CELL))
			if cell_rect.has_point(point):
				game._pent_handle_cell_tap(Vector2i(x, y))
				return

func build_buttons(app, game) -> void:
	if game.pent_phase != 1 or not game._pent_my_turn() or game.pent_game_over:
		return
	for q in range(4):
		var quad: Rect2 = quad_rect(app, q)
		var row_y: float = 676.0 + int(q / 2) * 64.0
		var left_x: float = quad.position.x
		app._add_btn(Rect2(left_x, row_y, 62, 52), "", game._pent_rot.bind(q, false), true, app.ACCENT, "disc", "rot_ccw", "rot_%d_ccw" % q)
		app._add_btn(Rect2(left_x + quad.size.x - 62, row_y, 62, 52), "", game._pent_rot.bind(q, true), true, app.ACCENT, "disc", "rot_cw", "rot_%d_cw" % q)

func render(app, game) -> void:
	var flat: Array = []
	for y in range(6):
		for x in range(6):
			flat.append(game.pent_board[y][x])
	app._track_board("pent", flat)
	var player_a: Dictionary = app._pl("سیاه", Color(0.1, 0.1, 0.14), "", game.pent_turn == 1 and not game.pent_game_over, app._seat_me(0), "", 0)
	var player_b: Dictionary = app._pl("سفید", Color(0.9, 0.9, 0.95), "", game.pent_turn == 2 and not game.pent_game_over, app._seat_me(1), "", 1)
	var phase_text: String = "قرار دادن مهره" if game.pent_phase == 0 else "چرخش یک بخش"
	if game.pent_turn == 1:
		player_a.sub = phase_text if not game.pent_game_over else ""
	else:
		player_b.sub = phase_text if not game.pent_game_over else ""
	app._draw_hud("پنتاگو", player_a, player_b)
	app._draw_ai_difficulty_chip(game.pent_difficulty)

	var hovered_quad: int = -1
	if app._press_active and app._press_id.begins_with("rot_"):
		hovered_quad = int(app._press_id.substr(4, 1))
	for q in range(4):
		var quad: Rect2 = quad_rect(app, q)
		var rotate_phase: bool = game.pent_phase == 1 and game._pent_my_turn() and not game.pent_game_over
		var is_hovered: bool = q == hovered_quad
		app._panel(quad.grow(6), Color(0.33, 0.22, 0.12) if not is_hovered else Color(0.55, 0.38, 0.18), 22, Color(app.ACCENT.r, app.ACCENT.g, app.ACCENT.b, 0.9) if is_hovered else (Color(0.8, 0.6, 0.3, 0.35 + 0.15 * sin(app._time * 3.0)) if rotate_phase else Color(0.8, 0.6, 0.3, 0.25)), 2.0 if is_hovered else 1.5, 14, 6)
	for y in range(6):
		for x in range(6):
			var top_left: Vector2 = cell_pos(app, x, y)
			var center: Vector2 = top_left + Vector2(app.PENT_CELL, app.PENT_CELL) * 0.5
			app.draw_circle(center, 27, Color(0.12, 0.08, 0.04))
			app.draw_circle(center + Vector2(0, 1.5), 25, Color(0.20, 0.13, 0.07))
			var piece: int = int(game.pent_board[y][x])
			if piece != 0:
				var cell_anim: float = app._cell_t("pent", y * 6 + x)[0]
				var radius: float = 23.0 * (app._ease_back(cell_anim) if cell_anim < 1.0 else 1.0)
				app._draw_disc(center, radius, piece == 2)
	if game.pent_last.x >= 0:
		var last_center: Vector2 = cell_pos(app, game.pent_last.x, game.pent_last.y) + Vector2(app.PENT_CELL, app.PENT_CELL) * 0.5
		app._ring(last_center, 28, Color(app.ACCENT.r, app.ACCENT.g, app.ACCENT.b, 0.9), 2.5)
	if not game.pent_game_over:
		if game.pent_phase == 0:
			app._hint("یک خانه خالی را انتخاب کنید" if game._pent_my_turn() else "حریف در حال حرکت…", 650, app.TEXT_DIM)
		elif game._pent_my_turn():
			app._hint("یک بخش را با دکمه‌های زیر بچرخانید", 646, app.ACCENT)
		else:
			app._hint("حریف در حال چرخاندن…", 646, app.TEXT_DIM)
	if game.pent_phase == 1 and game._pent_my_turn() and not game.pent_game_over:
		var quad_names: Array[String] = ["بالا چپ", "بالا راست", "پایین چپ", "پایین راست"]
		for q in range(4):
			var quad: Rect2 = quad_rect(app, q)
			var row_y: float = 676.0 + int(q / 2) * 64.0
			app._txt_c(quad_names[q], Rect2(quad.position.x + 62, row_y, quad.size.x - 124, 52), 14, app.TEXT_DIM, true)
