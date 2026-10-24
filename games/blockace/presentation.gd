extends RefCounted
## Blockace presentation, button layout and board hit-testing.
## All placement validation and game-state transitions remain in rules.gd.

func handle_tap(app, game, point: Vector2) -> void:
	if game.blk_game_over or game.blk_turn != game._blk_me() or (app.vs_cpu and game.blk_turn == 1):
		return
	var gx: int = int(floor((point.x - app.BLK_ORIGIN.x) / app.BLK_CELL))
	var gy: int = int(floor((point.y - app.BLK_ORIGIN.y) / app.BLK_CELL))
	if gx < 0 or gx >= game.BOARD_SIZE or gy < 0 or gy >= game.BOARD_SIZE:
		return
	game._blk_handle_target(Vector2i(gx, gy))

func build_buttons(app, game) -> void:
	var me: int = game._blk_me()
	for i in range(game.blk_pieces.size()):
		var col: int = i % 7
		var row: int = int(i / 7)
		var r := Rect2(8 + col * 75, 574 + row * 55, 70, 50)
		if not game.blk_game_over and game.blk_turn == me and not bool(game.blk_used[me][i]):
			app._add_hit(r, game._blk_select.bind(i), "blk_p%d" % i)
	var can_interact: bool = not game.blk_game_over and game.blk_turn == me and not (app.vs_cpu and game.blk_turn == 1)
	app._add_btn(Rect2(16, 768, 150, 50), "چرخش", game._blk_rotate, can_interact, app.BLUE, "soft", "rotate-cw", "blk_rot")
	app._add_btn(Rect2(178, 768, 150, 50), "وارونه", game._blk_flip_piece, can_interact, app.ACCENT, "soft", "flip-horizontal", "blk_flip")
	var valid: bool = game.blk_prev.x >= 0 and game.blk_turn == me and not game.blk_game_over and game._blk_can_place(game.blk_prev.x, game.blk_prev.y, game._blk_cells(game.blk_sel, game.blk_rot, game.blk_flip), me, game.blk_sel)
	app._add_btn(Rect2(340, 768, 184, 50), "قراردادن", game._blk_confirm, valid, app.GREEN, "solid", "check", "blk_ok")
	app._last_btn().hint = "هر قطعه باید روی خانه خالی قرار گیرد و با گوشه قطعات خودتان تماس داشته باشد."

func draw_cell(app, r: Rect2, col: Color) -> void:
	app._panel(r, col, 4)
	app._gloss(r, 4, 0.16)

func render(app, game) -> void:
	var flat: Array = []
	var c0: int = 0
	var c1: int = 0
	for y in range(game.BOARD_SIZE):
		for x in range(game.BOARD_SIZE):
			flat.append(game.blk_grid[y][x])
			if game.blk_grid[y][x] == 1:
				c0 += 1
			elif game.blk_grid[y][x] == 2:
				c1 += 1
	app._track_board("blk", flat)
	var ca := Color(0.30, 0.82, 0.76)
	var cb := Color(1.0, 0.62, 0.35)
	var me: int = game._blk_me()
	var pa: Dictionary = app._pl("شما", ca if me == 0 else cb, app._fa(c0 if me == 0 else c1), game.blk_turn == me and not game.blk_game_over, true, "خانه")
	var pb: Dictionary = app._pl("حریف", cb if me == 0 else ca, app._fa(c1 if me == 0 else c0), game.blk_turn == 1 - me and not game.blk_game_over, false, "خانه")
	if pa.active:
		pa.sub = "نوبت شما"
	app._draw_hud("بلاک‌آس · دوه نفره کامل", pa, pb)
	var o: Vector2 = app.BLK_ORIGIN
	var cs: float = app.BLK_CELL
	app._panel(Rect2(o - Vector2(8, 8), Vector2(cs * game.BOARD_SIZE + 16, cs * game.BOARD_SIZE + 16)), Color(0.10, 0.14, 0.22), 14, Color(0.3, 0.8, 0.75, 0.35), 1.5, 10, 4)
	for y in range(game.BOARD_SIZE):
		for x in range(game.BOARD_SIZE):
			var r := Rect2(o.x + x * cs + 1.0, o.y + y * cs + 1.0, cs - 2.0, cs - 2.0)
			var value: int = int(game.blk_grid[y][x])
			if value == 0:
				app._panel(r, Color(1, 1, 1, 0.045), 3)
			else:
				var t: float = app._cell_t("blk", y * game.BOARD_SIZE + x)[0]
				var rr: Rect2 = r if t >= 1.0 else r.grow(-(1.0 - app._ease_out(t)) * 5.0)
				draw_cell(app, rr, ca if value == 1 else cb)
	# Highlight mandatory starting squares until each player makes the first move.
	for player in range(2):
		if game._blk_used_count(player) == 0:
			var start := Vector2i(4, 4) if player == 0 else Vector2i(9, 9)
			var sr := Rect2(o.x + start.x * cs + 1, o.y + start.y * cs + 1, cs - 2, cs - 2)
			app._panel(sr, Color(ca.r, ca.g, ca.b, 0.25) if player == 0 else Color(cb.r, cb.g, cb.b, 0.25), 3, ca if player == 0 else cb, 1.2)
	if game.blk_prev.x >= 0 and game.blk_turn == me and not game.blk_game_over:
		var preview: Array = game._blk_cells(game.blk_sel, game.blk_rot, game.blk_flip)
		var ok: bool = game._blk_can_place(game.blk_prev.x, game.blk_prev.y, preview, me, game.blk_sel)
		for offset in preview:
			var px: int = game.blk_prev.x + offset.x
			var py: int = game.blk_prev.y + offset.y
			if px >= 0 and px < game.BOARD_SIZE and py >= 0 and py < game.BOARD_SIZE:
				var rr2 := Rect2(o.x + px * cs + 1, o.y + py * cs + 1, cs - 2, cs - 2)
				app._panel(rr2, Color(0.3, 0.9, 0.5, 0.60) if ok else Color(1.0, 0.3, 0.35, 0.60), 3, Color(1, 1, 1, 0.75), 1.0)
	# All 21 pieces are available in a compact 7 x 3 inventory tray.
	var current_player: int = game.blk_turn
	var piece_color: Color = ca if current_player == 0 else cb
	for i in range(game.blk_pieces.size()):
		var col: int = i % 7
		var row: int = int(i / 7)
		var rr3 := Rect2(8 + col * 75, 574 + row * 55, 70, 50)
		var used: bool = bool(game.blk_used[current_player][i])
		var selected: bool = (i == game.blk_sel and not used)
		app._panel(rr3, Color(0.10, 0.12, 0.17, 0.65) if used else (app.CARD_H if selected else app.CARD), 8, app.ACCENT if selected else Color(1, 1, 1, 0.13), 1.4 if selected else 0.7)
		var cells: Array = game._blk_cells(i, game.blk_rot if selected else 0, game.blk_flip if selected else false)
		var max_x: int = 0
		var max_y: int = 0
		for cell in cells:
			max_x = maxi(max_x, cell.x)
			max_y = maxi(max_y, cell.y)
		var unit: float = 6.0
		var origin := rr3.get_center() - Vector2(float(max_x + 1) * unit * 0.5, float(max_y + 1) * unit * 0.5)
		for cell in cells:
			var small := Rect2(origin + Vector2(cell.x, cell.y) * unit, Vector2(unit - 0.8, unit - 0.8))
			draw_cell(app, small, Color(piece_color.r * 0.36, piece_color.g * 0.36, piece_color.b * 0.36) if used else piece_color)
		if used:
			app._txt_c("✓", rr3, 15, Color(1, 1, 1, 0.35), true)
	var level_text: String = "سطح CPU: %s" % app._fa(game.blk_difficulty) if app.vs_cpu else "قانون تماس گوشه‌ای"
	app._txt_c(level_text, Rect2(12, 739, app.VIEW_W - 24, 18), 11, app.TEXT_DIM, false)
	if not game.blk_game_over:
		if game.blk_turn == me:
			app._hint("قطعه را انتخاب کن، جهتش را عوض کن و محل را دو بار بزن یا قراردادن را بزن.", 840, app.TEXT_DIM)
		else:
			app._hint("حریف در حال بازی…", 840, app.TEXT_DIM)
