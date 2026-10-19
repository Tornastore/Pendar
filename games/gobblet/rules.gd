extends "res://core/game_module.gd"
## Rule engine and authoritative state for gobblet.

# ---------- Game-owned state ----------
var gob_board: Array = []  # 4x4 stacks of {owner, size}
var gob_turn: int = 1
var gob_hand: Array = [[3,3,3], [3,3,3]]  # count of sizes 1,2,3 per player
var gob_sel_size: int = -1
var gob_game_over: bool = false
var gob_winner: int = 0

func reset_game() -> void:
	_reset_gobblet()

func _reset_gobblet() -> void:
	gob_board = []
	for y in 4:
		var row: Array = []
		for x in 4:
			row.append([])  # stack of {o, s}
		gob_board.append(row)
	gob_turn = 1
	gob_hand = [[3, 3, 3], [3, 3, 3]]
	gob_sel_size = -1
	gob_game_over = false
	gob_winner = 0

func _gob_top(x: int, y: int) -> Dictionary:
	var st: Array = gob_board[y][x]
	if st.size() == 0:
		return {}
	return st[st.size() - 1]

func _gob_check_win(p: int) -> bool:
	# rows cols diags of top owner
	for y in 4:
		var ok := true
		for x in 4:
			var t: Dictionary = _gob_top(x, y)
			if t.is_empty() or int(t.o) != p:
				ok = false
				break
		if ok:
			return true
	for x in 4:
		var ok2 := true
		for y in 4:
			var t2: Dictionary = _gob_top(x, y)
			if t2.is_empty() or int(t2.o) != p:
				ok2 = false
				break
		if ok2:
			return true
	var okd := true
	for i in 4:
		var t3: Dictionary = _gob_top(i, i)
		if t3.is_empty() or int(t3.o) != p:
			okd = false
			break
	if okd:
		return true
	okd = true
	for i in 4:
		var t4: Dictionary = _gob_top(i, 3 - i)
		if t4.is_empty() or int(t4.o) != p:
			okd = false
			break
	return okd

func _gob_place(x: int, y: int, size: int, player: int) -> bool:
	var top: Dictionary = _gob_top(x, y)
	if not top.is_empty() and int(top.s) >= size:
		return false
	var hand_idx: int = size - 1
	if gob_hand[player - 1][hand_idx] <= 0:
		return false
	gob_hand[player - 1][hand_idx] -= 1
	gob_board[y][x].append({"o": player, "s": size})
	if _gob_check_win(player):
		gob_game_over = true
		gob_winner = player
		app.state = State.RESULT
		app._build_result_buttons()
		return true
	gob_turn = 3 - gob_turn
	gob_sel_size = -1
	return true

func _gob_cpu() -> void:
	if gob_game_over or gob_turn != 2:
		return
	for size in [3, 2, 1]:
		if gob_hand[1][size - 1] <= 0:
			continue
		var cells: Array = []
		for y in 4:
			for x in 4:
				var top: Dictionary = _gob_top(x, y)
				if top.is_empty() or int(top.s) < size:
					cells.append(Vector2i(x, y))
		if cells.size() > 0:
			var c: Vector2i = cells[randi() % cells.size()]
			_gob_place(c.x, c.y, size, 2)
			return

func _gob_my_turn() -> bool:
	return gob_turn == 1 and not gob_game_over

func _gob_tap(p: Vector2) -> void:
	if not _gob_my_turn() or gob_sel_size < 1:
		return
	var gx: int = int(floor((p.x - app.GOB_ORIGIN.x) / app.GOB_CELL))
	var gy: int = int(floor((p.y - app.GOB_ORIGIN.y) / app.GOB_CELL))
	if gx >= 0 and gx < 4 and gy >= 0 and gy < 4:
		if not _gob_place(gx, gy, gob_sel_size, 1):
			app._show_toast("این مهره روی این خانه نمی‌نشیند؛ باید از مهره موجود بزرگ‌تر باشد.")

func _gob_pick(s: int) -> void:
	gob_sel_size = s if gob_sel_size != s else -1

func _btns_gobblet() -> void:
	for s in 3:
		var r := Rect2(app.VIEW_W - 16 - 160 - s * 170, 640, 160, 92)
		var ok: bool = _gob_my_turn() and gob_hand[0][s] > 0
		app._add_hit(r, _gob_pick.bind(s + 1), "gob_%d" % s, false, ok)

func _draw_gobblet() -> void:
	var tot0: int = 0
	var tot1: int = 0
	for s in 3:
		tot0 += gob_hand[0][s]
		tot1 += gob_hand[1][s]
	var c0 := Color(1.0, 0.45, 0.35)
	var c1 := Color(0.35, 0.58, 1.0)
	var pa: Dictionary = app._pl("شما", c0, app._fa(tot0), gob_turn == 1 and not gob_game_over, true, "مهره باقی‌مانده")
	var pb: Dictionary = app._pl("حریف", c1, app._fa(tot1), gob_turn == 2 and not gob_game_over, false, "مهره باقی‌مانده")
	if pa.active:
		pa.sub = "نوبت شما"
	app._draw_hud("گابلت", pa, pb)
	var flat: Array = []
	for y in 4:
		for x in 4:
			var st: Array = gob_board[y][x]
			flat.append(st.size() * 10 + (int(st[st.size() - 1].s) + int(st[st.size() - 1].o) * 100 if st.size() > 0 else 0))
	app._track_board("gob", flat)
	var o: Vector2 = app.GOB_ORIGIN
	app._panel(Rect2(o - Vector2(10, 10), Vector2(app.GOB_CELL * 4 + 20, app.GOB_CELL * 4 + 20)), Color(0.16, 0.12, 0.10), 24, Color(0.9, 0.6, 0.3, 0.4), 1.5, 22, 8)
	for y in 4:
		for x in 4:
			var r := Rect2(o.x + x * app.GOB_CELL + 3, o.y + y * app.GOB_CELL + 3, app.GOB_CELL - 6, app.GOB_CELL - 6)
			app._panel(r, Color(0.27, 0.21, 0.17), 14)
			var ok_cell: bool = false
			if _gob_my_turn() and gob_sel_size > 0:
				var tp: Dictionary = _gob_top(x, y)
				ok_cell = tp.is_empty() or int(tp.s) < gob_sel_size
				if ok_cell:
					app._panel(r, Color(app.ACCENT.r, app.ACCENT.g, app.ACCENT.b, 0.10), 14, Color(app.ACCENT.r, app.ACCENT.g, app.ACCENT.b, 0.45), 1.5)
			var cc: Vector2 = r.get_center()
			var st2: Array = gob_board[y][x]
			var t: float = app._cell_t("gob", y * 4 + x)[0]
			for k in st2.size():
				var pc: Dictionary = st2[k]
				var col: Color = c0 if int(pc.o) == 1 else c1
				var rad: float = 14.0 + int(pc.s) * 11.0
				if k == st2.size() - 1 and t < 1.0:
					rad *= app._ease_back(t)
				app.draw_circle(cc + Vector2(0, 2), rad, Color(0, 0, 0, 0.30))
				app.draw_circle(cc, rad, col.darkened(0.35))
				app.draw_circle(cc + Vector2(0, -1), rad - 3.5, col)
				if k == st2.size() - 1:
					app.draw_circle(cc + Vector2(-rad * 0.3, -rad * 0.36), rad * 0.2, Color(1, 1, 1, 0.4))
	for s in 3:
		var r := Rect2(app.VIEW_W - 16 - 160 - s * 170, 640, 160, 92)
		var n: int = gob_hand[0][s]
		var sel: bool = (gob_sel_size == s + 1)
		var can: bool = _gob_my_turn() and n > 0
		app._panel(r, app.CARD_H if sel else app.CARD, 20, app.ACCENT if sel else app.LINE_STRONG, 2.5 if sel else 1.0, 8, 3)
		var rad2: float = 14.0 + (s + 1) * 11.0
		var cc2 := Vector2(r.end.x - 52, r.get_center().y)
		app.draw_circle(cc2, rad2, (c0 if can else Color(0.4, 0.4, 0.45)).darkened(0.35))
		app.draw_circle(cc2, rad2 - 3.5, c0 if can else Color(0.45, 0.45, 0.5))
		app._txt_c(["کوچک", "متوسط", "بزرگ"][s], Rect2(r.position.x, r.position.y + 14, r.size.x - 100, 28), 15, app.TEXT if can else app.TEXT_FAINT, true)
		app._txt_c("× " + app._fa(n), Rect2(r.position.x, r.position.y + 46, r.size.x - 100, 28), 18, app.ACCENT if can else app.TEXT_FAINT, true)
	if not gob_game_over:
		if _gob_my_turn():
			app._hint("اندازه مهره را انتخاب و روی صفحه بگذارید" if gob_sel_size < 1 else "یکی از خانه‌های مجاز را بزنید", 590, app.TEXT_DIM)
		else:
			app._hint("حریف در حال بازی…", 590, app.TEXT_DIM)
