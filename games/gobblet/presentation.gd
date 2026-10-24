extends RefCounted
## Gobblet board and reserve presentation; all stack and win rules stay in rules.gd.

func hand_rect(app, index: int) -> Rect2:
	var col: int = index % 2
	var row: int = int(index / 2)
	return Rect2(20.0 + col * 260.0, 612.0 + row * 92.0, 240.0, 80.0)

func handle_tap(app, game, point: Vector2) -> void:
	var x: int = int(floor((point.x - app.GOB_ORIGIN.x) / app.GOB_CELL))
	var y: int = int(floor((point.y - app.GOB_ORIGIN.y) / app.GOB_CELL))
	game._gob_handle_cell_tap(Vector2i(x, y))

func build_buttons(app, game) -> void:
	for size_index in range(4):
		var rect: Rect2 = hand_rect(app, size_index)
		var allowed: bool = game._gob_my_turn() and int(game.gob_hand[game._gob_me() - 1][size_index]) > 0
		app._add_hit(rect, game._gob_pick.bind(size_index + 1), "gob_%d" % size_index, false, allowed)

func render(app, game) -> void:
	var me: int = game._gob_me()
	var tot0: int = 0
	var tot1: int = 0
	for s in range(4):
		tot0 += game.gob_hand[me - 1][s]
		tot1 += game.gob_hand[2 - me][s]
	var c_p1 := Color(1.0, 0.45, 0.35)
	var c_p2 := Color(0.35, 0.58, 1.0)
	var c0: Color = c_p1 if me == 1 else c_p2
	var c1: Color = c_p2 if me == 1 else c_p1
	var pa: Dictionary = app._pl("شما", c0, app._fa(tot0), game.gob_turn == me and not game.gob_game_over, true, "مهره باقی‌مانده")
	var pb: Dictionary = app._pl("حریف", c1, app._fa(tot1), game.gob_turn == 3 - me and not game.gob_game_over, false, "مهره باقی‌مانده")
	if pa.active:
		pa.sub = "نوبت شما"
	app._draw_hud("گابلت", pa, pb)
	app._draw_ai_difficulty_chip_at(game.gob_difficulty, 140.0)
	var flat: Array = []
	for y in range(4):
		for x in range(4):
			var st: Array = game.gob_board[y][x]
			flat.append(st.size() * 10 + (int(st[st.size() - 1].s) + int(st[st.size() - 1].o) * 100 if st.size() > 0 else 0))
	app._track_board("gob", flat)
	var o: Vector2 = app.GOB_ORIGIN
	app._panel(Rect2(o - Vector2(10, 10), Vector2(app.GOB_CELL * 4 + 20, app.GOB_CELL * 4 + 20)), Color(0.16, 0.12, 0.10), 24, Color(0.9, 0.6, 0.3, 0.4), 1.5, 22, 8)
	for y in range(4):
		for x in range(4):
			var r := Rect2(o.x + x * app.GOB_CELL + 3, o.y + y * app.GOB_CELL + 3, app.GOB_CELL - 6, app.GOB_CELL - 6)
			app._panel(r, Color(0.27, 0.21, 0.17), 14)
			var cell := Vector2i(x, y)
			var ok_cell: bool = false
			if game._gob_my_turn() and game.gob_sel_size > 0:
				ok_cell = game._gob_can_place(x, y, game.gob_sel_size, me)
			elif game._gob_my_turn() and game.gob_sel_from.x >= 0:
				ok_cell = game._gob_can_move(game.gob_sel_from, cell, me)
			if ok_cell:
				app._panel(r, Color(app.ACCENT.r, app.ACCENT.g, app.ACCENT.b, 0.12), 14, Color(app.ACCENT.r, app.ACCENT.g, app.ACCENT.b, 0.50), 1.5)
			var cc: Vector2 = r.get_center()
			var st2: Array = game.gob_board[y][x]
			var t: float = app._cell_t("gob", y * 4 + x)[0]
			for k in range(st2.size()):
				var pc: Dictionary = st2[k]
				var col: Color = c0 if int(pc.o) == me else c1
				var rad: float = 11.0 + int(pc.s) * 10.0
				if k == st2.size() - 1 and t < 1.0:
					rad *= app._ease_back(t)
				app.draw_circle(cc + Vector2(0, 2), rad, Color(0, 0, 0, 0.30))
				app.draw_circle(cc, rad, col.darkened(0.35))
				app.draw_circle(cc + Vector2(0, -1), rad - 3.5, col)
				if k == st2.size() - 1:
					app.draw_circle(cc + Vector2(-rad * 0.3, -rad * 0.36), rad * 0.2, Color(1, 1, 1, 0.4))
			if game.gob_sel_from == cell:
				app._ring(cc, app.GOB_CELL * 0.43, app.ACCENT, 3.0)
	var size_names: Array[String] = ["کوچک", "متوسط", "بزرگ", "خیلی بزرگ"]
	for s in range(4):
		var r: Rect2 = hand_rect(app, s)
		var n: int = game.gob_hand[me - 1][s]
		var sel: bool = (game.gob_sel_size == s + 1)
		var can: bool = game._gob_my_turn() and n > 0
		app._panel(r, app.CARD_H if sel else app.CARD, 18, app.ACCENT if sel else app.LINE_STRONG, 2.5 if sel else 1.0, 8, 3)
		var rad2: float = 10.0 + (s + 1) * 5.0
		var cc2 := Vector2(r.end.x - 48, r.get_center().y)
		app.draw_circle(cc2 + Vector2(0, 2), rad2, (c0 if can else Color(0.4, 0.4, 0.45)).darkened(0.35))
		app.draw_circle(cc2, rad2 - 2.5, c0 if can else Color(0.45, 0.45, 0.5))
		app._txt_c(size_names[s], Rect2(r.position.x + 8, r.position.y + 10, r.size.x - 76, 26), 15, app.TEXT if can else app.TEXT_FAINT, true)
		app._txt_c("× " + app._fa(n), Rect2(r.position.x + 8, r.position.y + 40, r.size.x - 76, 26), 18, app.ACCENT if can else app.TEXT_FAINT, true)
	if not game.gob_game_over:
		if game._gob_my_turn():
			if game.gob_sel_size > 0:
				app._hint("مهره‌ی تازه را روی خانه‌ی مجاز قرار دهید", 804, app.TEXT_DIM)
			elif game.gob_sel_from.x >= 0:
				app._hint("مهره‌ی انتخاب‌شده را به خانه‌ی علامت‌خورده ببرید", 804, app.TEXT_DIM)
			else:
				app._hint("اندازه‌ی تازه را انتخاب کنید یا مهره‌ی روی صفحه را برای جابه‌جایی بزنید", 804, app.TEXT_DIM)
		else:
			app._hint("حریف در حال بازی…", 804, app.TEXT_DIM)
