extends RefCounted
## Quoridor presentation: wall geometry, mode controls, HUD and board rendering.
## Wall legality, turn transitions, CPU decisions and network actions stay in rules.gd.

func edge_at(app, p: Vector2) -> Dictionary:
	var gx: int = int(floor((p.x - app.QUO_ORIGIN.x) / app.QUO_CELL))
	var gy: int = int(floor((p.y - app.QUO_ORIGIN.y) / app.QUO_CELL))
	if gx < 0 or gx > 8 or gy < 0 or gy > 8:
		return {}
	var fx: float = p.x - app.QUO_ORIGIN.x - gx * app.QUO_CELL
	var fy: float = p.y - app.QUO_ORIGIN.y - gy * app.QUO_CELL
	var cands: Array = [
		{"d": app.QUO_CELL - fy, "x": gx, "y": gy, "v": false, "ok": gx <= 7 and gy <= 7},
		{"d": fy, "x": gx, "y": gy - 1, "v": false, "ok": gx <= 7 and gy - 1 >= 0 and gy - 1 <= 7},
		{"d": app.QUO_CELL - fx, "x": gx, "y": gy, "v": true, "ok": gx <= 7 and gy <= 7},
		{"d": fx, "x": gx - 1, "y": gy, "v": true, "ok": gx - 1 >= 0 and gx - 1 <= 7 and gy <= 7},
	]
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.d) < float(b.d))
	for candidate in cands:
		if bool(candidate.ok):
			return candidate
	return {}

func build_buttons(app, game) -> void:
	if game.quo_game_over:
		return
	var mine: bool = game._quo_my_turn()
	var walls: int = int(game.quo_walls_left[game.quo_turn]) if mine else 0
	app._add_btn(Rect2(app.VIEW_W - 16 - 240, 826, 240, 50), "حرکت مهره", game._set_quo_mode.bind(0), mine, app.BLUE, "seg_on" if game.quo_mode == 0 else "ghost", "", "qm_move")
	app._add_btn(Rect2(16, 826, 240, 50), "دیوار (%s)" % app._fa(walls) if mine else "دیوار", game._set_quo_mode.bind(1), mine and walls > 0, app.ACCENT, "seg_on" if game.quo_mode == 1 else "ghost", "", "qm_wall")

func player_color(_app, _game, player: int) -> Color:
	match player:
		0: return Color(0.35, 0.60, 1.0)
		1: return Color(1.0, 0.45, 0.50)
		2: return Color(0.34, 0.82, 0.58)
		3: return Color(1.0, 0.78, 0.30)
	return Color.WHITE

func draw_four_player_hud(app, game) -> void:
	app._draw_bar_top(72.0)
	app._txt_c("کوریدور · چهار نفره", Rect2(70, 10, app.VIEW_W - 140, 48), 22, app.TEXT, true)
	for player in range(4):
		var rect := Rect2(16.0 + float(player % 2) * 254.0, 76.0 + floor(float(player) / 2.0) * 42.0, 246.0, 36.0)
		var color: Color = player_color(app, game, player)
		var active: bool = player == game.quo_turn and not game.quo_game_over
		app._panel(rect, Color(0.14, 0.17, 0.32) if active else app.CARD, 11.0, Color(color.r, color.g, color.b, 0.95 if active else 0.35), 1.5 if active else 1.0)
		app.draw_circle(Vector2(rect.position.x + 16.0, rect.get_center().y), 7.0, color)
		var player_label: String = "شما" if app.vs_cpu and player == 0 else ("CPU %s" % app._fa(player) if app.vs_cpu else "بازیکن %s" % app._fa(player + 1))
		app._txt_r(player_label, rect.end.x - 9.0, rect.position.y + 15.0, 13, app.TEXT, true, 100.0)
		app._txt_r("دیوار: %s" % app._fa(game.quo_walls_left[player]), rect.end.x - 112.0, rect.position.y + 29.0, 10, app.ACCENT if active else app.TEXT_DIM, false, 100.0)
		if active:
			app._txt("نوبت", rect.position.x + 28.0, rect.position.y + 23.0, 10, app.ACCENT, HORIZONTAL_ALIGNMENT_LEFT, 48.0, true)

func render(app, game) -> void:
	if game.quo_player_count == 4:
		draw_four_player_hud(app, game)
	else:
		var pa: Dictionary = app._pl("شما" if app.vs_cpu else "بازیکن ۱", player_color(app, game, 0), "", game.quo_turn == 0 and not game.quo_game_over, app._seat_me(0), "دیوار: " + app._fa(game.quo_walls_left[0]))
		var pb: Dictionary = app._pl("CPU" if app.vs_cpu else "بازیکن ۲", player_color(app, game, 1), "", game.quo_turn == 1 and not game.quo_game_over, app._seat_me(1), "دیوار: " + app._fa(game.quo_walls_left[1]))
		if game.quo_turn == 0 and not game.quo_game_over:
			pa.sub = "نوبت شما" if app._seat_me(0) else "نوبت حریف"
		if game.quo_turn == 1 and not game.quo_game_over:
			pb.sub = "نوبت شما" if app._seat_me(1) else "نوبت حریف"
		pa.score = app._fa(game.quo_walls_left[0])
		pb.score = app._fa(game.quo_walls_left[1])
		app._draw_hud("کوریدور", pa, pb)
	var origin: Vector2 = app.QUO_ORIGIN
	var cell: float = app.QUO_CELL
	app._panel(Rect2(origin - Vector2(10, 10), Vector2(cell * 9 + 20, cell * 9 + 20)), Color(0.12, 0.10, 0.24), 22, Color(0.55, 0.40, 0.95, 0.4), 1.5, 22, 8)
	for y in range(9):
		for x in range(9):
			var rect := Rect2(origin.x + x * cell + 3, origin.y + y * cell + 3, cell - 6, cell - 6)
			var base := Color(0.22, 0.20, 0.40)
			if game.quo_player_count == 2:
				if y == 8:
					base = base.lerp(player_color(app, game, 0), 0.22)
				elif y == 0:
					base = base.lerp(player_color(app, game, 1), 0.22)
			else:
				if y == 8: base = base.lerp(player_color(app, game, 0), 0.18)
				if x == 0: base = base.lerp(player_color(app, game, 1), 0.18)
				if y == 0: base = base.lerp(player_color(app, game, 2), 0.18)
				if x == 8: base = base.lerp(player_color(app, game, 3), 0.18)
			app._panel(rect, base, 8)
	# Show every legal move, including jumps and diagonals.
	var mine: bool = game._quo_my_turn() and not game.quo_game_over
	if mine and game.quo_mode == 0:
		var moves: Array[Vector2i] = game._quo_legal_moves(game.quo_turn)
		for target in moves:
			app._hint_dot(origin + Vector2(target.x * cell + cell * 0.5, target.y * cell + cell * 0.5), 6, app.ACCENT)
	# Every wall spans two cell spaces, matching the rules engine.
	for wall_key in game.quo_walls:
		var parts: PackedStringArray = str(wall_key).split(",")
		var orientation: String = parts[0]
		var wx: int = int(orientation.substr(1))
		var wy: int = int(parts[1])
		var wall_rect: Rect2
		if orientation.begins_with("h"):
			wall_rect = Rect2(origin.x + wx * cell + 3, origin.y + (wy + 1) * cell - 4, cell * 2 - 6, 8)
		else:
			wall_rect = Rect2(origin.x + (wx + 1) * cell - 4, origin.y + wy * cell + 3, 8, cell * 2 - 6)
		app._panel(wall_rect, Color(1.0, 0.78, 0.35), 4, Color(0.6, 0.4, 0.1, 0.8), 1.0, 5, 2)
	# Placement preview also uses the full two-space wall length.
	if mine and game.quo_mode == 1 and game.quo_walls_left[game.quo_turn] > 0:
		var edge: Dictionary = edge_at(app, app._ptr)
		if not edge.is_empty():
			var ghost: Rect2
			if not bool(edge.v):
				ghost = Rect2(origin.x + int(edge.x) * cell + 3, origin.y + (int(edge.y) + 1) * cell - 4, cell * 2 - 6, 8)
			else:
				ghost = Rect2(origin.x + (int(edge.x) + 1) * cell - 4, origin.y + int(edge.y) * cell + 3, 8, cell * 2 - 6)
			var key: String = ("v%d,%d" % [int(edge.x), int(edge.y)]) if bool(edge.v) else ("h%d,%d" % [int(edge.x), int(edge.y)])
			var allowed: bool = game._quo_wall_placement_legal(int(edge.x), int(edge.y), bool(edge.v)) and not game.quo_walls.has(key)
			app._panel(ghost, Color(0.35, 0.95, 0.70, 0.58) if allowed else Color(1.0, 0.30, 0.35, 0.5), 4)
	# Pawns
	for player in range(game.quo_player_count):
		var pawn_center: Vector2 = origin + Vector2(game.quo_pawns[player].x * cell + cell * 0.5, game.quo_pawns[player].y * cell + cell * 0.5)
		var pawn_color: Color = player_color(app, game, player)
		app._draw_marble(pawn_center, 16.5, pawn_color)
		app._txt_c(app._fa(player + 1), Rect2(pawn_center.x - 16, pawn_center.y - 16, 32, 32), 15, app._lum_text(pawn_color), true)
	if not game.quo_game_over:
		if game.quo_mode == 1 and mine:
			app._hint("دیوار را روی شکاف بگذارید؛ هر دیوار دو خانه طول دارد", 668, app.ACCENT)
		elif mine and game._quo_legal_moves(game.quo_turn).is_empty():
			app._hint("حرکت مهره بسته است؛ یک دیوار قرار دهید", 668, app.ACCENT)
		elif mine:
			app._hint("مهره را به یکی از خانه‌های نقطه‌دار ببرید؛ پرش و حرکت مورب مجاز است", 668, app.TEXT_DIM)
		else:
			app._hint("حریف در حال حرکت…", 668, app.TEXT_DIM)
