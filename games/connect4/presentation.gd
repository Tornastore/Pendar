extends RefCounted
## Connect Four board geometry and drawing; all move validation remains in rules.gd.
const BOARD := Rect2(32, 270, 476, 408)
const CELL_W := BOARD.size.x / 7.0
const CELL_H := BOARD.size.y / 6.0

func handle_tap(app, game, point: Vector2) -> void:
	if not game._c4_my_turn() or game.c4_game_over or not BOARD.has_point(point):
		return
	var column: int = clampi(int(floor((point.x - BOARD.position.x) / CELL_W)), 0, 6)
	game._c4_submit_column(column)

func build_buttons(app, game) -> void:
	if game.c4_game_over or not game._c4_my_turn():
		return
	for col in range(7):
		var enabled: bool = game._c4_landing_row(col) >= 0
		app._add_btn(Rect2(BOARD.position.x + col * CELL_W + 2, 218, CELL_W - 4, 42), str(app._fa(col + 1)), game._c4_submit_column.bind(col), enabled, app.ACCENT if enabled else app.DISABLED, "soft" if enabled else "ghost", "", "c4_col_%d" % col)

func render(app, game) -> void:
	var human_turn: bool = game._c4_my_turn()
	var p0_name: String = "شما" if app.vs_cpu or app.local_seat == 0 else "بازیکن اول"
	var p1_name: String = "CPU" if app.vs_cpu else ("شما" if app.local_seat == 1 else "بازیکن دوم")
	var p0: Dictionary = app._pl(p0_name, app.BLUE, "مهرهٔ قرمز", game.c4_turn == 0 and not game.c4_game_over, true, "۴ مهره در یک خط")
	var p1: Dictionary = app._pl(p1_name, app.YELLOW, "مهرهٔ زرد", game.c4_turn == 1 and not game.c4_game_over, false, "۴ مهره در یک خط")
	app._draw_hud("دوز چهار‌تایی · Connect Four", p0, p1)
	app._draw_ai_difficulty_chip_at(game.c4_difficulty, 150)
	app._panel(Rect2(BOARD.position - Vector2(8, 8), BOARD.size + Vector2(16, 16)), Color("#143f92"), 22, Color("#548cff"), 2, 14, 8)
	var flat: Array = []
	for y in range(6):
		for x in range(7):
			flat.append(int(game.c4_board[y][x]))
	app._track_board("c4", flat)
	for y in range(6):
		for x in range(7):
			var rect := Rect2(BOARD.position.x + x * CELL_W + 3, BOARD.position.y + y * CELL_H + 3, CELL_W - 6, CELL_H - 6)
			app._panel(rect, Color("#1c4ca5"), 11)
			var center: Vector2 = rect.get_center()
			var value: int = int(game.c4_board[y][x])
			app.draw_circle(center + Vector2(0, 2), minf(CELL_W, CELL_H) * 0.37, Color(0, 0, 0, 0.3))
			if value < 0:
				app.draw_circle(center, minf(CELL_W, CELL_H) * 0.35, Color("#0a1534"))
			else:
				var col: Color = Color("#ff626b") if value == 0 else Color("#ffd452")
				app.draw_circle(center, minf(CELL_W, CELL_H) * 0.36, col.darkened(0.35))
				app.draw_circle(center + Vector2(0, -1), minf(CELL_W, CELL_H) * 0.31, col)
				app.draw_circle(center + Vector2(-7, -8), 5, Color(1, 1, 1, 0.40))
	var status: String = "بازی تمام شد؛ نتیجه را ببینید" if game.c4_game_over else ("نوبت شماست؛ ستون را انتخاب کنید" if human_turn else "CPU در حال محاسبه است…")
	app._hint(status, 715, app.GREEN if human_turn and not game.c4_game_over else app.TEXT_DIM)
	app._txt_c("هدف: ۴ مهرهٔ هم‌رنگ در یک خط افقی، عمودی یا مورب", Rect2(28, 762, 484, 34), 13, app.TEXT_DIM)
	app._txt_c("در صورت پرشدن تمام خانه‌ها بدون خط چهار‌تایی، بازی مساوی است.", Rect2(28, 798, 484, 34), 12, app.TEXT_FAINT)
