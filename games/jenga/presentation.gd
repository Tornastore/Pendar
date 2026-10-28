extends RefCounted
## Jenga presentation: isometric pseudo-3D tower plus front, side and top reference views.
## Rules remain authoritative; taps are resolved against the same block polygons that are drawn.
const BASE_CENTER := Vector2(270.0, 574.0)
const BLOCK_LENGTH: float = 116.0
const BLOCK_WIDTH: float = 29.0
const DEPTH_AXIS := Vector2(-0.55, 0.40)
const MAIN_TOWER_HIT_RECT := Rect2(128.0, 258.0, 284.0, 372.0)

func _layer_step(game) -> float:
	return minf(15.0, 300.0 / maxf(17.0, float(game.jenga_layers.size() - 1)))

func _block_height(game) -> float:
	return minf(8.5, _layer_step(game) * 0.66)

func _block_geometry(game, level: int, slot: int) -> Dictionary:
	var horizontal: bool = level % 2 == 0
	var long_axis: Vector2 = Vector2.RIGHT if horizontal else DEPTH_AXIS
	var width_axis: Vector2 = DEPTH_AXIS if horizontal else Vector2.RIGHT
	var center: Vector2 = BASE_CENTER + Vector2(0.0, -float(level) * _layer_step(game))
	center += width_axis * (float(slot) - 1.0) * BLOCK_WIDTH
	var long_half: Vector2 = long_axis * (BLOCK_LENGTH * 0.5)
	var width_half: Vector2 = width_axis * (BLOCK_WIDTH * 0.5)
	var p1: Vector2 = center - long_half - width_half
	var p2: Vector2 = center + long_half - width_half
	var p3: Vector2 = center + long_half + width_half
	var p4: Vector2 = center - long_half + width_half
	var drop := Vector2(0.0, _block_height(game))
	return {
		"top": PackedVector2Array([p1, p2, p3, p4]),
		"front": PackedVector2Array([p4, p3, p3 + drop, p4 + drop]),
		"side": PackedVector2Array([p2, p3, p3 + drop, p2 + drop]),
		"center": center,
		"drop": drop,
	}

func handle_tap(app, game, point: Vector2) -> void:
	if not game._jenga_my_turn() or game.jenga_game_over or game.jenga_phase != "remove":
		return
	if not MAIN_TOWER_HIT_RECT.has_point(point):
		return
	# Test from the upper/frontmost pieces back to the base. The hit polygons exactly
	# match the visible 3D faces, so tapping a slanted block does not select a neighbour.
	for level in range(game.jenga_layers.size() - 1, -1, -1):
		for slot in range(2, -1, -1):
			var geometry: Dictionary = _block_geometry(game, level, slot)
			for face_name in ["top", "front", "side"]:
				if not Geometry2D.is_point_in_polygon(point, geometry[face_name]):
					continue
				# Stop at the first visible block hit, even when this block is illegal;
				# otherwise a tap on a top block could accidentally select a hidden block behind it.
				if game._jenga_legal_removal(level, slot):
					game._jenga_submit_remove(level, slot)
				return

func build_buttons(app, game) -> void:
	if game.jenga_game_over or not game._jenga_my_turn():
		return
	if game.jenga_phase == "place":
		for slot in game._jenga_legal_place_slots():
			app._add_btn(Rect2(28 + slot * 166, 790, 158, 46), "جایگاه %s" % app._fa(slot + 1), game._jenga_submit_place.bind(slot), true, app.GREEN, "soft", "check", "jenga_place_%d" % slot)

func _draw_block(app, game, level: int, slot: int) -> void:
	var geometry: Dictionary = _block_geometry(game, level, slot)
	var top: PackedVector2Array = geometry["top"]
	var front: PackedVector2Array = geometry["front"]
	var side: PackedVector2Array = geometry["side"]
	var wood: Color = Color("#d7a46a") if level % 2 == 0 else Color("#c58a4d")
	wood = wood.lightened(0.025 * float(slot))
	if game.jenga_phase == "remove" and game._jenga_my_turn() and game._jenga_legal_removal(level, slot):
		wood = wood.lightened(0.12)
	app.draw_colored_polygon(front, wood.darkened(0.34))
	app.draw_colored_polygon(side, wood.darkened(0.22))
	app.draw_colored_polygon(top, wood.lightened(0.08))
	app.draw_polyline(PackedVector2Array([top[0], top[1], top[2], top[3], top[0]]), Color("#704727"), 1.15, true)
	# Fine grain and a subtle beveled edge make each block read as a solid wooden piece.
	var center: Vector2 = geometry["center"]
	var drop: Vector2 = geometry["drop"]
	app.draw_line(top[0].lerp(top[3], 0.35), top[1].lerp(top[2], 0.35), Color(1.0, 0.91, 0.72, 0.30), 1.0, true)
	if game.jenga_phase == "remove" and game._jenga_my_turn() and game._jenga_legal_removal(level, slot):
		app.draw_polyline(PackedVector2Array([top[0], top[1], top[2], top[3], top[0]]), Color("#ffe08a"), 1.6, true)

func _draw_angle_views(app, game) -> void:
	var boxes: Array[Rect2] = [Rect2(16, 630, 160, 90), Rect2(190, 630, 160, 90), Rect2(364, 630, 160, 90)]
	var labels: Array[String] = ["نمای روبه‌رو", "نمای کناری", "نمای بالا"]
	for index in range(boxes.size()):
		var box: Rect2 = boxes[index]
		app._panel(box, Color("#1a203b"), 12, Color("#64739c", 0.42), 1.0)
		app._txt_c(labels[index], Rect2(box.position.x + 4, box.position.y + 3, box.size.x - 8, 18), 10, app.TEXT_DIM, true)
	var layer_count: int = game.jenga_layers.size()
	var row_count: int = mini(layer_count, 16)
	# Front view: alternating rows show whether a level runs along or across the viewer.
	var front_x: float = boxes[0].position.x + 28.0
	var front_y: float = boxes[0].end.y - 9.0
	for offset in range(row_count):
		var level: int = clampi(layer_count - 1 - int(round(float(offset) * float(layer_count - 1) / float(maxi(1, row_count - 1)))), 0, layer_count - 1)
		var step_y: float = 3.0
		var row_width: float = 104.0
		for slot in range(3):
			if bool(game.jenga_layers[level][slot]):
				var rw: float = 31.0 if level % 2 == 0 else 16.0
				var rx: float = front_x + (slot - 1) * (rw + (2.0 if level % 2 == 0 else 27.0))
				app._panel(Rect2(rx, front_y - offset * step_y, rw, 2.2), Color("#d7a46a") if level % 2 == 0 else Color("#ba7d43"), 1)
	# Side view: a different projection of the same alternating stack.
	var side_box: Rect2 = boxes[1]
	var side_base: Vector2 = Vector2(side_box.get_center().x, side_box.end.y - 14.0)
	for offset in range(row_count):
		var level: int = clampi(layer_count - 1 - int(round(float(offset) * float(layer_count - 1) / float(maxi(1, row_count - 1)))), 0, layer_count - 1)
		var y: float = side_base.y - offset * 3.0
		for slot in range(3):
			if bool(game.jenga_layers[level][slot]):
				var w: float = 28.0 if level % 2 == 1 else 15.0
				var xx: float = side_base.x + (slot - 1) * (w + (2.0 if level % 2 == 1 else 27.0))
				app._panel(Rect2(xx - w * 0.5, y, w, 2.2), Color("#d7a46a") if level % 2 == 0 else Color("#ba7d43"), 1)
	# Top view shows the three lanes and the gaps that can be used for the next placement.
	var top_box: Rect2 = boxes[2]
	var board := Rect2(top_box.position.x + 30, top_box.position.y + 31, 100, 46)
	app._panel(board, Color("#6e492b"), 5, Color("#d5a56e", 0.65), 1.0)
	var top_level: Array = game.jenga_layers[layer_count - 1]
	for slot in range(3):
		var lane := Rect2(board.position.x + 5, board.position.y + 4 + slot * 13, board.size.x - 10, 10)
		if bool(top_level[slot]):
			app._panel(lane, Color("#d7a46a"), 3, Color("#704727"), 0.8)
		else:
			app._panel(lane, Color("#1a203b"), 3, Color("#e5bd7c", 0.35), 0.8)

func render(app, game) -> void:
	var seat_names: Array[String] = []
	var local_seat: int = 0 if app.vs_cpu else app.local_seat
	for seat in range(game.jenga_player_count):
		seat_names.append("شما" if seat == local_seat else ("CPU %s" % app._fa(seat + 1) if app.vs_cpu else "بازیکن %s" % app._fa(seat + 1)))
	var active_name: String = seat_names[game.jenga_turn] if game.jenga_turn < seat_names.size() else "—"
	var a: Dictionary = app._pl(seat_names[0], app.GREEN, app._fa(game.jenga_moves), game.jenga_turn == 0 and not game.jenga_game_over, true, "حرکت‌های موفق")
	var b: Dictionary = app._pl(active_name, app.ACCENT, "طبقه %s" % app._fa(game.jenga_layers.size()), not game.jenga_game_over, game.jenga_turn != 0, "نوبت فعلی")
	app._draw_hud("برج هیجان · Jenga", a, b)
	app._draw_ai_difficulty_chip_at(game.jenga_difficulty, 151)
	app._panel(Rect2(24, 200, 492, 420), Color("#242038", 0.52), 22, Color("#be8e59", 0.36), 1.1)
	app.draw_colored_polygon(PackedVector2Array([Vector2(135, 594), Vector2(405, 594), Vector2(378, 608), Vector2(162, 608)]), Color(0.02, 0.025, 0.05, 0.55))
	# Draw lower levels first; each layer alternates its long axis by the rules of Jenga.
	for level in range(game.jenga_layers.size()):
		for slot in range(3):
			if bool(game.jenga_layers[level][slot]):
				_draw_block(app, game, level, slot)
	app._txt_c("لمس بلوک روشن برای بیرون‌کشیدن", Rect2(28, 608, 484, 20), 11, app.GREEN if game._jenga_my_turn() else app.TEXT_DIM, true)
	_draw_angle_views(app, game)
	var line: String = "یک بلوک قانونی را لمس کنید" if game._jenga_my_turn() else "منتظر نوبت %s بمانید" % active_name
	if game.jenga_phase == "place":
		line = "بلوک را در یکی از جایگاه‌های خالی بالای برج بگذارید"
	app._hint(line, 726, app.GREEN if game._jenga_my_turn() else app.TEXT_DIM)
	app._txt_c("هر طبقه در جهت مخالف قبلی است؛ از طبقات بالایی بلوک برندارید.", Rect2(20, 761, 500, 24), 10, app.TEXT_FAINT)
	app._wrap(game.jenga_status, 24, 844, 492, 12, app.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
