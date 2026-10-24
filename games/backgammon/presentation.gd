extends RefCounted
## Backgammon board rendering and pointer hit-testing.
## Dice rules, checker state, turn sequencing and CPU/network actions stay in rules.gd.

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


func point_from_tap(p: Vector2) -> int:
	# The bar is the central vertical channel. Only its active checker area selects it.
	if p.x >= BAR_MIN_X and p.x <= BAR_MAX_X and p.y >= BAR_MIN_Y and p.y <= BAR_MAX_Y:
		return -1
	# Point triangles are actually drawn in the top and bottom bands. The old
	# mapping accepted only the blank middle band, causing clicks on visible
	# checkers to be ignored or routed to the opposite side.
	var top_row: bool = p.y >= TOP_POINTS_MIN_Y and p.y <= TOP_POINTS_MAX_Y
	var bottom_row: bool = p.y >= BOTTOM_POINTS_MIN_Y and p.y <= BOTTOM_POINTS_MAX_Y
	if not top_row and not bottom_row:
		return -2
	for candidate in range(12):
		var x0: float = point_x(candidate) - 2.0
		if p.x >= x0 and p.x <= x0 + 36.0:
			return candidate if top_row else 23 - candidate
	return -2


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
	var selected_targets: Dictionary = {}
	if game.bg_sel != -2:
		for move in game._bg_turn_legal_moves(game.bg_turn):
			if int(move.source) == game.bg_sel and int(move.target) >= 0:
				selected_targets[int(move.target)] = true
	for i in range(24):
		var top: bool = i < 12
		var col_i: int = i if top else 23 - i
		var x: float = point_x(col_i)
		var y0: float = 180.0 if top else 660.0
		var tipy: float = y0 + (150.0 if top else -150.0)
		var tcol: Color = Color(0.92, 0.70, 0.42) if (col_i + (0 if top else 1)) % 2 == 0 else Color(0.62, 0.22, 0.22)
		app.draw_colored_polygon(PackedVector2Array([Vector2(x, y0), Vector2(x + 34, y0), Vector2(x + 17, tipy)]), tcol)
		var n: int = int(game.bg_points[i])
		var cnt: int = absi(n)
		for k in range(mini(cnt, 5)):
			var cy: float = (y0 + 18.0 + k * 27.0) if top else (y0 - 18.0 - k * 27.0)
			app._draw_disc(Vector2(x + 17, cy), 13.5, n > 0)
		if cnt > 5:
			var ly: float = (y0 + 18.0 + 4 * 27.0) if top else (y0 - 18.0 - 4 * 27.0)
			app._txt_c(app._fa(cnt), Rect2(x, ly - 14, 34, 28), 14, app.TEXT if n < 0 else Color(0.1, 0.1, 0.15), true)
		var triangle_center: Vector2 = Vector2(x + 17.0, tipy - 8.0 if top else tipy + 8.0)
		if i == game.bg_sel:
			app._ring(triangle_center, 15.0, app.ACCENT, 2.5)
		if selected_targets.has(i):
			app.draw_circle(triangle_center, 7.0, Color(app.GREEN.r, app.GREEN.g, app.GREEN.b, 0.78))
			app._ring(triangle_center, 11.0, app.GREEN, 1.7)
	# Bar checkers. Click the central channel to select a checker there when required.
	for player in range(2):
		for k in range(mini(int(game.bg_bar[player]), 5)):
			var center := Vector2(point_x(5) + 48.0, 400.0 + (float(player) * 2.0 - 1.0) * (20.0 + float(k) * 20.0))
			app._draw_disc(center, 11.0, player == 0)
		if game.bg_sel == -1 and int(game.bg_bar[game.bg_turn]) > 0:
			app._ring(Vector2(point_x(5) + 48.0, 400.0 + (float(game.bg_turn) * 2.0 - 1.0) * 20.0), 15.0, app.ACCENT, 2.0)
	# Dice and remaining playable values.
	for i in range(2):
		var dr := Rect2(point_x(6) + 20 + i * 54 - 28, 396, 44, 44)
		var used: bool = game.bg_moves_left.is_empty()
		app._draw_dice_face(dr, int(game.bg_dice[i]), used)
	var rem: String = "—"
	if not game.bg_moves_left.is_empty():
		var parts: PackedStringArray = []
		for value in game.bg_moves_left:
			parts.append(app._fa(int(value)))
		rem = " ، ".join(parts)
	app._txt_c("تاس‌های باقی: " + rem, Rect2(0, 678, app.VIEW_W, 26), 14, app.TEXT_DIM, true)
	var help: String = "مهره‌ی خود را انتخاب کنید، سپس مقصد را بزنید" if game.bg_sel == -2 else "خانه‌های سبز مقصدهای مجازند"
	if int(game.bg_bar[game.bg_turn]) > 0 and not (app.vs_cpu and game.bg_turn == 1):
		help = "ابتدا مهره‌ی روی بار را وارد کنید"
	app._txt_c(help, Rect2(16, 682, app.VIEW_W - 32, 24), 11, app.ACCENT if game.bg_sel != -2 else app.TEXT_DIM, false)
