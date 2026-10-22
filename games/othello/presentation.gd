extends RefCounted
## Othello presentation and board hit-testing.
## Rules and authoritative state remain in games/othello/rules.gd.

func cell_size(game) -> float:
	return 60.0 if game.oth_size == 8 else 40.0


func board_origin(app, game) -> Vector2:
	var cell: float = cell_size(game)
	return Vector2((app.VIEW_W - cell * game.oth_size) * 0.5, 200.0)


func is_my_turn(app, game) -> bool:
	if app.vs_cpu:
		return game.othello_turn == 1
	return app._is_my_turn()


func handle_tap(app, game, p: Vector2) -> void:
	if game.othello_game_over or not is_my_turn(app, game):
		return
	var cell: float = cell_size(game)
	var origin: Vector2 = board_origin(app, game)
	var gx: int = int(floor((p.x - origin.x) / cell))
	var gy: int = int(floor((p.y - origin.y) / cell))
	if gx >= 0 and gx < game.oth_size and gy >= 0 and gy < game.oth_size:
		if not game._othello_place(Vector2i(gx, gy)):
			app._show_toast("این خانه حرکت مجاز نیست؛ خانه‌های نقطه‌دار را انتخاب کنید.")


func render(app, game) -> void:
	var flat: Array = []
	for y in game.oth_size:
		for x in game.oth_size:
			flat.append(game.othello_board[y][x])
	app._track_board("oth", flat)
	var mine_turn: bool = is_my_turn(app, game)
	var pa: Dictionary = app._pl("سیاه", Color(0.1, 0.1, 0.14), app._fa(game.othello_scores[1]), game.othello_turn == 1 and not game.othello_game_over, app._seat_me(0), "", 0)
	var pb: Dictionary = app._pl("سفید", Color(0.9, 0.9, 0.95), app._fa(game.othello_scores[2]), game.othello_turn == 2 and not game.othello_game_over, app._seat_me(1), "", 1)
	app._draw_hud("اتلو %s×%s" % [app._fa(game.oth_size), app._fa(game.oth_size)], pa, pb)
	var cell: float = cell_size(game)
	var o: Vector2 = board_origin(app, game)
	var bs: float = cell * game.oth_size
	app._panel(Rect2(o - Vector2(12, 12), Vector2(bs + 24, bs + 24)), Color(0.07, 0.22, 0.17), 22, Color(0.25, 0.65, 0.5, 0.45), 1.5, 22, 8)
	for y in game.oth_size:
		for x in game.oth_size:
			var r := Rect2(o.x + x * cell + 1, o.y + y * cell + 1, cell - 2, cell - 2)
			var shade: float = 0.0 if (x + y) % 2 == 0 else 0.025
			app._panel(r, Color(0.13 + shade, 0.46 + shade, 0.33 + shade), 5 if game.oth_size == 8 else 4)
	for y in game.oth_size:
		for x in game.oth_size:
			var idx: int = y * game.oth_size + x
			var cc := Vector2(o.x + x * cell + cell * 0.5, o.y + y * cell + cell * 0.5)
			var pr: float = cell * 0.37
			var v: int = game.othello_board[y][x]
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
			elif mine_turn and not game.othello_game_over and Vector2i(x, y) in game.othello_valid:
				app._hint_dot(cc, cell * 0.10, app.ACCENT)
	if game.othello_last_move.x >= 0:
		var lm := Vector2(o.x + game.othello_last_move.x * cell + cell * 0.5, o.y + game.othello_last_move.y * cell + cell * 0.5)
		app._ring(lm, cell * 0.43, Color(app.ACCENT.r, app.ACCENT.g, app.ACCENT.b, 0.9), 2.5)
	# score bar
	var total: float = float(maxi(1, game.othello_scores[1] + game.othello_scores[2]))
	var bar := Rect2(o.x, o.y + bs + 34, bs, 14)
	app._panel(bar, Color(0.9, 0.9, 0.95), 7)
	var bw: float = bs * float(game.othello_scores[1]) / total
	if bw > 0.0:
		app._panel(Rect2(bar.position, Vector2(maxf(14.0, bw), 14)), Color(0.08, 0.09, 0.13), 7, Color(1, 1, 1, 0.25), 1.0)
	if mine_turn and not game.othello_game_over:
		app._hint("خانه‌های نقطه‌دار حرکت‌های مجاز هستند", o.y + bs + 62, app.TEXT_DIM)
	elif not game.othello_game_over:
		app._hint("حریف در حال حرکت…", o.y + bs + 62, app.TEXT_DIM)
