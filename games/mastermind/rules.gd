extends "res://core/game_module.gd"
## Mastermind rules and UI. Supports CPU, online turns, and local two-player hot-seat.

# Difficulty 1..6 changes code length from 4 to 9 pegs.
var mm_difficulty: int = 1
var mm_code_len: int = 4
var mm_local_two_player: bool = false
# 0 = player 1 sets a secret, 1 = code-breaker guesses, 2 = pass-device intermission.
var mm_phase: int = 1
var mm_secret: Array = []
var mm_guesses: Array = []
var mm_cur: Array = [0, 0, 0, 0]
var mm_slot: int = 0
var mm_turn_role: int = 0
var mm_game_over: bool = false
var mm_won: bool = false
var mm_filled: Array = [false, false, false, false]
var mm_turn: int = 0
var mm_winner: int = -1

func reset_game() -> void:
	_reset_mastermind()

func _mm_blank_code() -> Array:
	var result: Array = []
	for i in range(mm_code_len):
		result.append(0)
	return result

func _mm_blank_filled() -> Array:
	var result: Array = []
	for i in range(mm_code_len):
		result.append(false)
	return result

func _mm_evaluate(guess: Array) -> Array:
	var black := 0
	var white := 0
	var s_used: Array = []
	var g_used: Array = []
	for i in range(mm_code_len):
		s_used.append(false)
		g_used.append(false)
	for i in range(mm_code_len):
		if i < guess.size() and guess[i] == mm_secret[i]:
			black += 1
			s_used[i] = true
			g_used[i] = true
	for i in range(mm_code_len):
		if g_used[i]:
			continue
		for j in range(mm_code_len):
			if s_used[j]:
				continue
			if i < guess.size() and guess[i] == mm_secret[j]:
				white += 1
				s_used[j] = true
				break
	return [black, white]

func _reset_mastermind() -> void:
	mm_code_len = clampi(3 + mm_difficulty, 4, 9)
	mm_secret = []
	if not mm_local_two_player:
		for i in range(mm_code_len):
			mm_secret.append(randi() % 6)
	mm_guesses = []
	mm_cur = _mm_blank_code()
	mm_filled = _mm_blank_filled()
	mm_slot = 0
	mm_phase = 0 if mm_local_two_player else 1
	mm_game_over = false
	mm_won = false
	mm_turn = 0
	mm_winner = -1

func _mm_my_turn() -> bool:
	if mm_game_over or mm_phase == 2:
		return false
	if mm_local_two_player:
		return true
	return (not app._net_on()) or mm_turn == app._my_seat()

func _mm_slot_pos(i: int) -> Vector2:
	var gap: float = minf(86.0, float(app.VIEW_W - 52) / float(maxi(1, mm_code_len)))
	return Vector2(app.VIEW_W * 0.5 + (float(mm_code_len - 1) * 0.5 - float(i)) * gap, 640.0)

func _mm_pick(c: int) -> void:
	if mm_game_over or not _mm_my_turn() or c < 0 or c > 5:
		return
	if mm_slot < 0 or mm_slot >= mm_code_len:
		mm_slot = 0
	mm_cur[mm_slot] = c
	mm_filled[mm_slot] = true
	for k in range(1, mm_code_len + 1):
		var idx: int = (mm_slot + k) % mm_code_len
		if not mm_filled[idx]:
			mm_slot = idx
			break

func _mm_pick_slot(i: int) -> void:
	if i >= 0 and i < mm_code_len and _mm_my_turn():
		mm_slot = i

func _mm_clear() -> void:
	if mm_game_over or not _mm_my_turn():
		return
	mm_cur = _mm_blank_code()
	mm_filled = _mm_blank_filled()
	mm_slot = 0

func _mm_all_filled() -> bool:
	if mm_filled.size() != mm_code_len:
		return false
	for f in mm_filled:
		if not f:
			return false
	return true

func _mm_begin_guessing() -> void:
	if not mm_local_two_player or mm_phase != 2 or mm_game_over:
		return
	mm_phase = 1
	mm_cur = _mm_blank_code()
	mm_filled = _mm_blank_filled()
	mm_slot = 0
	app._rebuild_buttons()

func _btns_mastermind() -> void:
	if mm_game_over:
		return
	if mm_local_two_player and mm_phase == 2:
		app._add_btn(Rect2(24, 510, 492, 76), "شروع حدس · بازیکن دوم", _mm_begin_guessing, true, app.GREEN, "solid", "play", "mm_start_guessing")
		return
	if not _mm_my_turn():
		return
	for i in range(mm_code_len):
		var c: Vector2 = _mm_slot_pos(i)
		app._add_hit(Rect2(c.x - 27, c.y - 27, 54, 54), _mm_pick_slot.bind(i), "mm_s%d" % i)
	for i in range(6):
		var cx: float = app.VIEW_W * 0.5 + (float(i) - 2.5) * 76.0
		app._add_hit(Rect2(cx - 32, 706, 64, 64), _mm_pick.bind(i), "mm_c%d" % i)
	app._add_btn(Rect2(app.VIEW_W - 40 - 150, 800, 150, 56), "پاک کردن", _mm_clear, true, app.TEXT_DIM, "ghost", "undo", "mm_clear")
	var submit_label: String = "ثبت کد مخفی" if mm_local_two_player and mm_phase == 0 else "ثبت حدس"
	app._add_btn(Rect2(40, 800, 300, 56), submit_label, _mm_submit, _mm_all_filled(), app.GREEN, "solid", "check", "mm_ok")
	app._last_btn().hint = "هر %s خانه را با رنگ انتخابی پر کنید." % app._fa(mm_code_len)

func _draw_mastermind() -> void:
	var used: int = mm_guesses.size()
	var net: bool = app._net_on()
	if mm_local_two_player and mm_phase == 0:
		app._draw_hud("فکر بکر · ساخت کد مخفی", app._pl("تعداد مهره", app.ACCENT, app._fa(mm_code_len), true, true, "طول کد"))
	elif mm_local_two_player:
		app._draw_hud("فکر بکر · دو نفره", app._pl("تلاش", app.ACCENT, "%s/%s" % [app._fa(used), app._fa(10)], true, true, "حداکثر ده تلاش"))
	elif net:
		var na: Dictionary = app._pl("شما", app.BLUE, app._fa(used), mm_turn == app._my_seat() and not mm_game_over, true, "تلاش کل")
		var nb: Dictionary = app._pl("حریف", app.PINK, app._fa(10 - used), mm_turn != app._my_seat() and not mm_game_over, false, "تلاش باقی")
		app._draw_hud("فکر بکر · آنلاین", na, nb)
	else:
		var difficulty_text: String = "سطح %s · کد %s مهره‌ای" % [app._fa(mm_difficulty), app._fa(mm_code_len)]
		app._draw_hud("فکر بکر", app._pl("تلاش‌ها", app.ACCENT, "%s/%s" % [app._fa(used), app._fa(10)], true, true, difficulty_text))

	if mm_local_two_player and mm_phase == 2:
		var pass_panel := Rect2(28, 212, app.VIEW_W - 56, 260)
		app._panel(pass_panel, app.CARD, 24, app.LINE, 1.0, 14, 4)
		app._txt_c("کد مخفی ثبت شد", Rect2(44, 252, app.VIEW_W - 88, 42), 25, app.GREEN, true)
		app._wrap("حالا دستگاه را به بازیکن دوم بده. کد نمایش داده نمی‌شود. بازیکن دوم برای شکستن کد ده تلاش دارد.", 54, 315, app.VIEW_W - 108, 17, app.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		app._hint("برای شروع، بازیکن دوم دکمه را بزند.", 452, app.TEXT_DIM)
		return

	var setup: bool = mm_local_two_player and mm_phase == 0
	if setup:
		var setup_panel := Rect2(28, 174, app.VIEW_W - 56, 176)
		app._panel(setup_panel, app.CARD, 20, app.LINE, 1.0, 10, 4)
		app._txt_c("بازیکن اول: کد مخفی را بساز", Rect2(42, 202, app.VIEW_W - 84, 32), 20, app.TEXT, true)
		app._wrap("از شش رنگ انتخاب کن. تکرار رنگ مجاز است. پس از ثبت کد، صفحه به بازیکن دوم واگذار می‌شود.", 52, 246, app.VIEW_W - 104, 18, app.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		var panel := Rect2(16, 150, app.VIEW_W - 32, 400)
		app._panel(panel, app.CARD, 22, app.LINE, 1.0, 12, 4)
		var guess_gap: float = minf(44.0, 238.0 / float(maxi(1, mm_code_len - 1)))
		var guess_radius: float = 13.0 if mm_code_len <= 5 else (11.0 if mm_code_len <= 7 else 9.5)
		var feedback_gap: float = minf(16.0, 112.0 / float(maxi(1, mm_code_len - 1)))
		for gi in range(10):
			var y: float = panel.position.y + 22.0 + float(gi) * 38.0
			var active: bool = (gi == used)
			if active:
				app._panel(Rect2(panel.position.x + 8, y - 17, panel.size.x - 16, 34), Color(app.ACCENT.r, app.ACCENT.g, app.ACCENT.b, 0.10), 14, Color(app.ACCENT.r, app.ACCENT.g, app.ACCENT.b, 0.5), 1.0)
			app._txt_c(app._fa(gi + 1), Rect2(panel.end.x - 47, y - 14, 28, 28), 11, app.TEXT_FAINT, true)
			for i in range(mm_code_len):
				var peg: Vector2 = Vector2(panel.end.x - 63.0 - float(i) * guess_gap, y)
				if gi < used:
					var guess_row: Dictionary = mm_guesses[gi]
					app._draw_marble(peg, guess_radius, app.MM_COLORS[int(guess_row.g[i])])
				else:
					if active and mm_filled[i]:
						app._draw_marble(peg, guess_radius, app.MM_COLORS[mm_cur[i]])
					else:
						app.draw_circle(peg, guess_radius, Color(1, 1, 1, 0.06))
						app._ring(peg, guess_radius, Color(1, 1, 1, 0.14), 1.0)
			if gi < used:
				var guess_data: Dictionary = mm_guesses[gi]
				# One horizontal feedback row per guess: black pegs first, then white.
				# These are counts, not position-matched markers, as in classic Mastermind.
				for k in range(mm_code_len):
					var feedback_pos: Vector2 = Vector2(panel.position.x + 26.0 + float(k) * feedback_gap, y)
					if k < int(guess_data.b):
						app.draw_circle(feedback_pos, 5.4, Color(0.04, 0.05, 0.08))
						app._ring(feedback_pos, 5.4, Color(1, 1, 1, 0.48), 0.9)
					elif k < int(guess_data.b) + int(guess_data.w):
						app.draw_circle(feedback_pos, 5.4, Color(0.96, 0.97, 1.0))
						app._ring(feedback_pos, 5.4, Color(0.22, 0.24, 0.30), 0.8)
					else:
						app.draw_circle(feedback_pos, 4.6, Color(1, 1, 1, 0.07))
						app._ring(feedback_pos, 4.6, Color(1, 1, 1, 0.10), 0.8)
		if not setup:
			app._txt_r("سیاه: رنگ و جای درست · سفید: فقط رنگ درست", app.VIEW_W - 24, 574, 12, app.TEXT_DIM, false, 420)

	if _mm_my_turn():
		var current_title: String = "کد مخفی شما" if setup else "حدس فعلی"
		app._txt_c(current_title, Rect2(0, 586, app.VIEW_W, 22), 13, app.TEXT_DIM, true)
		for i in range(mm_code_len):
			var c2: Vector2 = _mm_slot_pos(i)
			var sel: bool = (i == mm_slot)
			app.draw_circle(c2, 27, Color(1, 1, 1, 0.06))
			app._ring(c2, 27, app.ACCENT if sel else Color(1, 1, 1, 0.18), 2.5 if sel else 1.2)
			if mm_filled[i]:
				app._draw_marble(c2, 22 if mm_code_len >= 8 else 25, app.MM_COLORS[mm_cur[i]])
		for i in range(6):
			var cx: float = app.VIEW_W * 0.5 + (float(i) - 2.5) * 76.0
			var pressed: bool = app._press_active and app._press_id == "mm_c%d" % i
			app._draw_marble(Vector2(cx, 738), 24 if not pressed else 21, app.MM_COLORS[i])

func _mm_submit() -> void:
	if mm_game_over or not _mm_all_filled() or not _mm_my_turn():
		return
	if mm_local_two_player and mm_phase == 0:
		mm_secret = mm_cur.duplicate()
		mm_phase = 2
		mm_cur = _mm_blank_code()
		mm_filled = _mm_blank_filled()
		mm_slot = 0
		app._rebuild_buttons()
		return
	if app._net_on():
		app.rpc("_rpc_mm_submit", mm_cur.duplicate(), app._my_seat())
		return
	var guessing_player: int = 1 if mm_local_two_player else 0
	_mm_apply(mm_cur.duplicate(), guessing_player)

func _mm_apply(g: Array, player: int) -> void:
	if mm_game_over or g.size() != mm_code_len:
		return
	for colour in g:
		if int(colour) < 0 or int(colour) > 5:
			return
	var ev: Array = _mm_evaluate(g)
	mm_guesses.append({"g": g.duplicate(), "b": ev[0], "w": ev[1], "p": player})
	if int(ev[0]) == mm_code_len:
		mm_game_over = true
		mm_winner = player
		mm_won = (player == app._my_seat()) and not mm_local_two_player or mm_local_two_player
	elif mm_guesses.size() >= 10:
		mm_game_over = true
		mm_won = false
		if mm_local_two_player:
			mm_winner = 0 # secret maker wins if the code is not cracked in ten attempts
		elif app.vs_cpu:
			mm_winner = 1 # computer kept the code hidden
		else:
			mm_winner = -1
	else:
		if not mm_local_two_player:
			mm_turn = 1 - player
		mm_cur = _mm_blank_code()
		mm_filled = _mm_blank_filled()
		mm_slot = 0
	if mm_game_over:
		app._go_result(false)
	else:
		app._build_playing_buttons()
