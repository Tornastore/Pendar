extends "res://core/game_module.gd"
## Rule engine and authoritative state for mastermind.

# ---------- Game-owned state ----------
var mm_secret: Array = []
var mm_guesses: Array = []
var mm_cur: Array = [0, 0, 0, 0]
var mm_slot: int = 0
var mm_turn_role: int = 0  # 0 maker shown as CPU sets, 1 guesser
var mm_game_over: bool = false
var mm_won: bool = false
var mm_filled: Array = [false, false, false, false]

func reset_game() -> void:
	_reset_mastermind()

func _mm_evaluate(guess: Array) -> Array:
	var black := 0
	var white := 0
	var s_used: Array = [false, false, false, false]
	var g_used: Array = [false, false, false, false]
	for i in 4:
		if guess[i] == mm_secret[i]:
			black += 1
			s_used[i] = true
			g_used[i] = true
	for i in 4:
		if g_used[i]:
			continue
		for j in 4:
			if s_used[j]:
				continue
			if guess[i] == mm_secret[j]:
				white += 1
				s_used[j] = true
				break
	return [black, white]

func _reset_mastermind() -> void:
	mm_secret = []
	for i in 4:
		mm_secret.append(randi() % 6)
	mm_guesses = []
	mm_cur = [0, 0, 0, 0]
	mm_filled = [false, false, false, false]
	mm_slot = 0
	mm_game_over = false
	mm_won = false

func _mm_slot_pos(i: int) -> Vector2:
	return Vector2(app.VIEW_W * 0.5 + (1.5 - i) * 86.0, 640.0)

func _mm_pick(c: int) -> void:
	if mm_game_over:
		return
	mm_cur[mm_slot] = c
	mm_filled[mm_slot] = true
	for k in range(1, 5):
		var idx: int = (mm_slot + k) % 4
		if not mm_filled[idx]:
			mm_slot = idx
			return

func _mm_pick_slot(i: int) -> void:
	mm_slot = i

func _mm_clear() -> void:
	mm_cur = [0, 0, 0, 0]
	mm_filled = [false, false, false, false]
	mm_slot = 0

func _mm_all_filled() -> bool:
	for f in mm_filled:
		if not f:
			return false
	return true

func _mm_tap(_p: Vector2) -> void:
	pass

func _btns_mastermind() -> void:
	if mm_game_over:
		return
	for i in 4:
		var c: Vector2 = _mm_slot_pos(i)
		app._add_hit(Rect2(c.x - 36, c.y - 36, 72, 72), _mm_pick_slot.bind(i), "mm_s%d" % i)
	for i in 6:
		var cx: float = app.VIEW_W * 0.5 + (i - 2.5) * 76.0
		app._add_hit(Rect2(cx - 32, 706, 64, 64), _mm_pick.bind(i), "mm_c%d" % i)
	app._add_btn(Rect2(app.VIEW_W - 40 - 150, 800, 150, 56), "پاک کردن", _mm_clear, true, app.TEXT_DIM, "ghost", "undo", "mm_clear")
	app._add_btn(Rect2(40, 800, 300, 56), "ثبت حدس", _mm_submit, _mm_all_filled(), app.GREEN, "solid", "check", "mm_ok")
	app._last_btn().hint = "هر چهار خانه را رنگ کنید."

func _draw_mastermind() -> void:
	var used: int = mm_guesses.size()
	app._draw_hud("فکر بکر", app._pl("تلاش‌ها", app.ACCENT, "%s/%s" % [app._fa(used), app._fa(10)], true, true, "حداکثر ۱۰ تلاش"))
	var panel := Rect2(16, 150, app.VIEW_W - 32, 400)
	app._panel(panel, app.CARD, 22, app.LINE, 1.0, 12, 4)
	for gi in 10:
		var y: float = panel.position.y + 22.0 + gi * 38.0
		var active: bool = (gi == used)
		if active:
			app._panel(Rect2(panel.position.x + 8, y - 17, panel.size.x - 16, 34), Color(app.ACCENT.r, app.ACCENT.g, app.ACCENT.b, 0.10), 14, Color(app.ACCENT.r, app.ACCENT.g, app.ACCENT.b, 0.5), 1.0)
		app._txt_c(app._fa(gi + 1), Rect2(panel.end.x - 46, y - 14, 30, 28), 12, app.TEXT_FAINT, true)
		for i in 4:
			var c := Vector2(panel.end.x - 90 - i * 44.0, y)
			if gi < used:
				var g: Dictionary = mm_guesses[gi]
				app._draw_marble(c, 13, app.MM_COLORS[g.g[i]])
			elif active and mm_filled[i]:
				app._draw_marble(c, 13, app.MM_COLORS[mm_cur[i]])
			else:
				app.draw_circle(c, 13, Color(1, 1, 1, 0.06))
				app._ring(c, 13, Color(1, 1, 1, 0.14), 1.2)
		if gi < used:
			var gg: Dictionary = mm_guesses[gi]
			for k in 4:
				var pc := Vector2(panel.position.x + 40 + (k % 2) * 18, y - 8 + int(k / 2) * 16)
				if k < int(gg.b):
					app.draw_circle(pc, 6, Color(0.05, 0.05, 0.08))
					app._ring(pc, 6, Color(1, 1, 1, 0.5), 1.0)
				elif k < int(gg.b) + int(gg.w):
					app.draw_circle(pc, 6, Color(0.96, 0.96, 1.0))
				else:
					app.draw_circle(pc, 5, Color(1, 1, 1, 0.08))
	app._txt_r("سیاه: رنگ و جای درست · سفید: فقط رنگ درست", app.VIEW_W - 24, 574, 12, app.TEXT_DIM, false, 420)
	if not mm_game_over:
		app._txt_c("حدس فعلی", Rect2(0, 586, app.VIEW_W, 22), 13, app.TEXT_DIM, true)
		for i in 4:
			var c2: Vector2 = _mm_slot_pos(i)
			var sel: bool = (i == mm_slot)
			app.draw_circle(c2, 31, Color(1, 1, 1, 0.06))
			app._ring(c2, 31, app.ACCENT if sel else Color(1, 1, 1, 0.18), 2.5 if sel else 1.2)
			if mm_filled[i]:
				app._draw_marble(c2, 25, app.MM_COLORS[mm_cur[i]])
		for i in 6:
			var cx: float = app.VIEW_W * 0.5 + (i - 2.5) * 76.0
			var pressed: bool = app._press_active and app._press_id == "mm_c%d" % i
			app._draw_marble(Vector2(cx, 738), 24 if not pressed else 21, app.MM_COLORS[i])

func _mm_submit() -> void:
	if mm_game_over or not _mm_all_filled():
		return
	var g: Array = mm_cur.duplicate()
	var ev: Array = _mm_evaluate(g)
	mm_guesses.append({"g": g, "b": ev[0], "w": ev[1]})
	if ev[0] == 4:
		mm_game_over = true
		mm_won = true
		app.state = State.RESULT
		app._build_result_buttons()
	elif mm_guesses.size() >= 10:
		mm_game_over = true
		mm_won = false
		app.state = State.RESULT
		app._build_result_buttons()
	else:
		mm_cur = [0, 0, 0, 0]
		mm_filled = [false, false, false, false]
		mm_slot = 0
