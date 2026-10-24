extends RefCounted
## Backgammon board rendering and pointer hit-testing.
## Rules/state, roll lifecycle, legal move sequencing and CPU actions stay in rules.gd.

const BOARD_LEFT: float = 25.0
const BOARD_TOP: float = 170.0
const BOARD_WIDTH: float = 490.0
const BOARD_HEIGHT: float = 500.0
const TOP_POINTS_MIN_Y: float = 178.0
const TOP_POINTS_MAX_Y: float = 332.0
const BOTTOM_POINTS_MIN_Y: float = 508.0
const BOTTOM_POINTS_MAX_Y: float = 662.0
const BAR_MIN_X: float = 244.0
const BAR_MAX_X: float = 280.0
const BAR_MIN_Y: float = 338.0
const BAR_MAX_Y: float = 500.0

func point_x(col: int) -> float:
	return 40.0 + col * 36.0 + (24.0 if col >= 6 else 0.0)


func point_column(point: int) -> int:
	# Seat 0 moves toward the bottom-right home board; seat 1 moves toward top-right.
	return 11 - point if point < 12 else point - 12


func point_center(point: int, stack_index: int = 0) -> Vector2:
	if point < 0 or point >= 24:
		return Vector2(268.0, 400.0)
	var col: int = point_column(point)
	var x: float = point_x(col) + 17.0
	var stack: int = clampi(stack_index, 0, 4)
	if point < 12:
		return Vector2(x, 198.0 + float(stack) * 27.0)
	return Vector2(x, 642.0 - float(stack) * 27.0)


func point_tip_center(point: int) -> Vector2:
	if point < 0 or point >= 24:
		return Vector2(268.0, 400.0)
	var col: int = point_column(point)
	return Vector2(point_x(col) + 17.0, 322.0 if point < 12 else 518.0)


func point_from_tap(p: Vector2) -> int:
	# The bar is the central vertical channel. Only its active checker area selects it.
	if p.x >= BAR_MIN_X and p.x <= BAR_MAX_X and p.y >= BAR_MIN_Y and p.y <= BAR_MAX_Y:
		return -1
	var top_row: bool = p.y >= TOP_POINTS_MIN_Y and p.y <= TOP_POINTS_MAX_Y
	var bottom_row: bool = p.y >= BOTTOM_POINTS_MIN_Y and p.y <= BOTTOM_POINTS_MAX_Y
	if not top_row and not bottom_row:
		return -2
	for candidate in range(12):
		var x0: float = point_x(candidate) - 2.0
		if p.x >= x0 and p.x <= x0 + 36.0:
			# Mirrored horizontal mapping: point 0 is top-right and point 23 bottom-right.
			return 11 - candidate if top_row else 12 + candidate
	return -2


func _draw_arrow(app, start: Vector2, finish: Vector2, color: Color, width: float = 3.0) -> void:
	app.draw_line(start, finish, color, width, true)
	var delta: Vector2 = finish - start
	if delta.length() < 12.0:
		return
	var direction: Vector2 = delta.normalized()
	var normal: Vector2 = Vector2(-direction.y, direction.x)
	var tip: Vector2 = finish - direction * 3.0
	var base: Vector2 = finish - direction * 15.0
	app.draw_colored_polygon(PackedVector2Array([tip, base + normal * 6.0, base - normal * 6.0]), color)


func _move_end(game, point: int, is_start: bool, player: int) -> Vector2:
	if point == -1:
		return Vector2(268.0, 380.0 if player == 0 else 420.0)
	if point == -2:
		return Vector2(500.0, 685.0 if player == 0 else 154.0)
	if point < 0 or point >= 24:
		return Vector2(268.0, 400.0)
	var stack: int = absi(int(game.bg_points[point]))
	if not is_start:
		stack += 1
	return point_center(point, mini(maxi(stack - 1, 0), 4))


func _draw_move_trace(app, game, move: Dictionary, animated: bool) -> void:
	if move.is_empty():
		return
	var player: int = int(move.get("player", 0))
	var source: int = int(move.get("source", -2))
	var target: int = int(move.get("target", -2))
	var color: Color = Color(0.25, 0.95, 0.93, 0.9) if player == 0 else Color(1.0, 0.54, 0.28, 0.95)
	var start: Vector2 = _move_end(game, source, true, player)
	var finish: Vector2 = _move_end(game, target, false, player)
	if source >= 0:
		var source_count: int = absi(int(game.bg_points[source]))
		var source_stack: int = mini(maxi(source_count - 1 if animated else source_count, 0), 4)
		start = point_center(source, source_stack)
	if target == -1:
		finish = Vector2(500.0, 685.0 if player == 0 else 154.0)
	elif target >= 0:
		var target_count: int = absi(int(game.bg_points[target]))
		var target_stack: int = mini(maxi(target_count if animated else target_count - 1, 0), 4)
		finish = point_center(target, target_stack)
	if not animated:
		color.a = 0.52
		app._ring(start, 17.0, color, 2.5)
		app._ring(finish, 17.0, color, 2.5)
	_draw_arrow(app, start, finish, color, 3.0 if animated else 2.0)
	if animated:
		var elapsed: float = maxf(0.0, float(Time.get_ticks_msec()) / 1000.0 - float(game._bg_move_anim_started_at))
		var t: float = clampf(elapsed / game.MOVE_ANIM_SECONDS, 0.0, 1.0)
		var pos: Vector2 = start.lerp(finish, t) + Vector2(0, -sin(t * PI) * 52.0)
		app._draw_disc(pos, 15.0, player == 0)
		app._ring(pos, 17.0, app.ACCENT, 2.5)


func _draw_badge(app, center: Vector2, label: String, fill: Color, width: float = 25.0) -> void:
	var rect := Rect2(center.x - width * 0.5, center.y - 10.0, width, 20.0)
	app._panel(rect, fill, 7.0, Color(1, 1, 1, 0.85), 1.0)
	app._txt_c(label, rect, 10, Color(1, 1, 1), true)


func render(app, game) -> void:
	var me: int = game._bg_me()
	var pa: Dictionary = app._pl("شما", Color(0.96, 0.93, 0.84) if me == 0 else Color(0.12, 0.13, 0.18), app._fa(game.bg_off[me]), game.bg_turn == me and not game.bg_game_over, true, "خارج‌شده", 1 if me == 0 else 0)
	var opponent_name: String = "CPU" if app.vs_cpu else "حریف"
	var pb: Dictionary = app._pl(opponent_name, Color(0.12, 0.13, 0.18) if me == 0 else Color(0.96, 0.93, 0.84), app._fa(game.bg_off[1 - me]), game.bg_turn == 1 - me and not game.bg_game_over, false, "خارج‌شده", 0 if me == 0 else 1)
	if pa.active:
		pa.sub = "نوبت شما"
	var title: String = "تخته‌نرد"
	if app.vs_cpu:
		var levels: Array[String] = ["خیلی آسان", "آسان", "متوسط", "سخت", "استاد", "استادتمام"]
		title += " · " + levels[clampi(game.bg_difficulty, 1, 6) - 1]
	app._draw_hud(title, pa, pb)
	var board := Rect2(25, 170, 490, 500)
	app._panel(board, Color(0.30, 0.18, 0.10), 22, Color(0.8, 0.55, 0.3, 0.5), 2.0, 20, 8)
	app._panel(board.grow(-8), Color(0.12, 0.30, 0.24), 16)
	app._panel(Rect2(point_x(5) + 36, 178, 24, 484), Color(0.30, 0.18, 0.10), 6)

	var target_moves: Dictionary = {}
	var available_sources: Dictionary = {}
	if not game._bg_needs_roll and not game._bg_roll_animating and not game.bg_game_over:
		for move in game._bg_turn_legal_moves(game.bg_turn):
			var source: int = int(move.source)
			var target: int = int(move.target)
			available_sources[source] = true
			if source == game.bg_sel and target >= 0:
				if not target_moves.has(target):
					target_moves[target] = []
				target_moves[target].append(move)
	for i in range(24):
		var top: bool = i < 12
		var col_i: int = point_column(i)
		var x: float = point_x(col_i)
		var y0: float = 180.0 if top else 660.0
		var tipy: float = y0 + (150.0 if top else -150.0)
		var tcol: Color = Color(0.92, 0.70, 0.42) if (col_i + (0 if top else 1)) % 2 == 0 else Color(0.62, 0.22, 0.22)
		app.draw_colored_polygon(PackedVector2Array([Vector2(x, y0), Vector2(x + 34, y0), Vector2(x + 17, tipy)]), tcol)
		var n: int = int(game.bg_points[i])
		var cnt: int = absi(n)
		var draw_count: int = cnt
		if game._bg_animating_move and int(game._bg_anim_move.get("source", -99)) == i:
			draw_count = maxi(0, draw_count - 1)
		for k in range(mini(draw_count, 5)):
			var cy: float = (y0 + 18.0 + k * 27.0) if top else (y0 - 18.0 - k * 27.0)
			app._draw_disc(Vector2(x + 17, cy), 13.5, n > 0)
		if cnt > 5:
			var ly: float = (y0 + 18.0 + 4 * 27.0) if top else (y0 - 18.0 - 4 * 27.0)
			app._txt_c(app._fa(cnt), Rect2(x, ly - 14, 34, 28), 14, app.TEXT if n < 0 else Color(0.1, 0.1, 0.15), true)
		var triangle_center: Vector2 = Vector2(x + 17.0, tipy - 8.0 if top else tipy + 8.0)
		if i == game.bg_sel:
			app._ring(triangle_center, 15.0, app.ACCENT, 2.5)
		if game.bg_sel == -2 and available_sources.has(i):
			app._ring(triangle_center, 13.0, Color(0.25, 0.78, 0.95, 0.8), 1.8)
		if target_moves.has(i):
			app.draw_circle(triangle_center, 7.0, Color(app.GREEN.r, app.GREEN.g, app.GREEN.b, 0.9))
			app._ring(triangle_center, 11.0, app.GREEN, 2.0)
			var die_labels: PackedStringArray = PackedStringArray()
			for move in target_moves[i]:
				var die_label: String = app._fa(int(move.die))
				if die_label not in die_labels:
					die_labels.append(die_label)
			var chip_y: float = triangle_center.y - 18.0 if top else triangle_center.y + 18.0
			_draw_badge(app, Vector2(x + 17, chip_y), "/".join(die_labels), Color(0.10, 0.45, 0.29, 0.95), maxf(24.0, 18.0 + die_labels.size() * 8.0))
		# Familiar point labels make the mirrored orientation explicit: 24 at point 0, 1 at point 23.
		var point_number: String = app._fa(24 - i)
		var number_y: float = y0 + 2.0 if top else y0 - 4.0
		app._txt_c(point_number, Rect2(x + 2, number_y, 30, 14), 9, Color(1, 1, 1, 0.72), false)

	# Draw possible two-die routes in a separate purple style; each step still has to be played legally.
	if game.bg_sel != -2 and not game._bg_needs_roll and not game._bg_roll_animating:
		var combined_hints: Array[Dictionary] = game._bg_combined_move_hints(game.bg_sel)
		for combo_index in range(combined_hints.size()):
			var combo: Dictionary = combined_hints[combo_index]
			var start_point: int = int(combo.get("source", game.bg_sel))
			var via_point: int = int(combo.get("via", -1))
			var end_point: int = int(combo.get("target", -1))
			if via_point >= 0:
				var p0: Vector2 = point_tip_center(start_point) if start_point >= 0 else Vector2(268, 400)
				var p1: Vector2 = point_tip_center(via_point)
				var p2: Vector2 = point_tip_center(end_point) if end_point >= 0 else Vector2(500.0, 685.0 if game.bg_turn == 0 else 154.0)
				app.draw_line(p0, p1, Color(0.72, 0.45, 1.0, 0.65), 2.0, true)
				app.draw_line(p1, p2, Color(0.72, 0.45, 1.0, 0.65), 2.0, true)
				app._ring(p2, 15.0, Color(0.77, 0.53, 1.0), 2.0)
				var label: String = app._fa(int(combo.get("first_die", 0))) + "+" + app._fa(int(combo.get("second_die", 0)))
				var vertical_offset: float = -20.0 if end_point < 12 else 20.0
				vertical_offset += float(combo_index % 3) * 13.0
				_draw_badge(app, p2 + Vector2(0, vertical_offset), label, Color(0.40, 0.22, 0.60, 0.98), 42.0)

	# Bar checkers and selection state.
	for player in range(2):
		for k in range(mini(int(game.bg_bar[player]), 5)):
			var center := Vector2(268.0, 400.0 + (float(player) * 2.0 - 1.0) * (20.0 + float(k) * 20.0))
			app._draw_disc(center, 11.0, player == 0)
		if game.bg_sel == -1 and int(game.bg_bar[game.bg_turn]) > 0 and player == game.bg_turn:
			app._ring(Vector2(268.0, 380.0 if player == 0 else 420.0), 15.0, app.ACCENT, 2.0)
		if game.bg_sel == -2 and available_sources.has(-1) and int(game.bg_bar[player]) > 0 and player == game.bg_turn:
			app._ring(Vector2(268.0, 380.0 if player == 0 else 420.0), 13.0, Color(0.25, 0.78, 0.95, 0.8), 1.8)

	# Dice are hidden until the player presses Roll; the rolling faces change, rotate and then settle on the result.
	for i in range(2):
		var dr := Rect2(238.0 + i * 58.0, 390.0, 46.0, 46.0)
		if game._bg_roll_animating:
			var elapsed: float = maxf(0.0, float(Time.get_ticks_msec()) / 1000.0 - float(game._bg_roll_started_at))
			var fake_value: int = int(floor(elapsed * 19.0 + float(i) * 2.8)) % 6 + 1
			var spin: float = elapsed * 24.0 + float(i) * 1.7
			app.draw_set_transform(dr.get_center(), spin, Vector2.ONE)
			app._draw_dice_face(Rect2(-23.0, -23.0, 46.0, 46.0), fake_value, false)
			app.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		elif not game._bg_needs_roll and int(game.bg_dice[i]) > 0:
			app._draw_dice_face(dr, int(game.bg_dice[i]), false)
		else:
			app._draw_dice_face(dr, 0, true)
	if game._bg_roll_animating:
		app._txt_c("تاس‌ها در حال چرخش‌اند…", Rect2(150, 444, 240, 24), 12, app.ACCENT, true)
	elif game._bg_needs_roll:
		app._txt_c("برای دیدن نتیجه، دکمهٔ ریختن تاس را بزنید", Rect2(116, 444, 308, 26), 11, app.TEXT_DIM, false)
	elif int(game.bg_dice[0]) == int(game.bg_dice[1]):
		app._txt_c("جفت " + app._fa(int(game.bg_dice[0])) + " · چهار حرکت", Rect2(150, 444, 240, 24), 12, app.ACCENT, true)
	else:
		var sum_value: int = int(game.bg_dice[0]) + int(game.bg_dice[1])
		app._txt_c("جمع دو تاس: " + app._fa(int(game.bg_dice[0])) + " + " + app._fa(int(game.bg_dice[1])) + " = " + app._fa(sum_value), Rect2(116, 444, 308, 26), 12, app.ACCENT, true)

	var remaining_text: String = "تاس باقی نمانده"
	if game._bg_needs_roll and int(game._bg_roll_result[0]) > 0:
		var roller: String = "شما" if int(game._bg_roll_player) == 0 else ("CPU" if app.vs_cpu else "حریف")
		remaining_text = "تاس نوبت قبل " + roller + ": " + app._fa(int(game._bg_roll_result[0])) + " + " + app._fa(int(game._bg_roll_result[1])) + " = " + app._fa(int(game._bg_roll_result[0]) + int(game._bg_roll_result[1]))
	elif not game.bg_moves_left.is_empty():
		var parts: PackedStringArray = []
		for value in game.bg_moves_left:
			parts.append(app._fa(int(value)))
		remaining_text = "تاس‌های قابل استفاده: " + " ، ".join(parts)
	app._txt_c(remaining_text, Rect2(24, 676, app.VIEW_W - 48, 20), 11, app.TEXT_DIM, false)
	if not game._bg_last_move.is_empty():
		var last: Dictionary = game._bg_last_move
		var owner: String = "شما" if int(last.get("player", 0)) == 0 else ("CPU" if app.vs_cpu else "حریف")
		var from_label: String = "بار" if int(last.source) == -1 else app._fa(24 - int(last.source))
		var to_label: String = "خارج" if int(last.target) == -1 else app._fa(24 - int(last.target))
		var history_text: String = "آخرین حرکت " + owner + ": " + from_label + " ← " + to_label + " · تاس " + app._fa(int(last.die))
		app._txt_c(history_text, Rect2(20, 697, app.VIEW_W - 40, 20), 11, Color(0.98, 0.75, 0.38), true)
	else:
		app._txt_c("مهرهٔ خود را انتخاب کنید؛ خانه‌های سبز مقصد یک تاس و بنفش مسیر دو تاس‌اند", Rect2(16, 697, app.VIEW_W - 32, 20), 10, app.TEXT_DIM, false)
	if game._bg_animating_move:
		_draw_move_trace(app, game, game._bg_anim_move, true)
	elif not game._bg_last_move.is_empty():
		_draw_move_trace(app, game, game._bg_last_move, false)
