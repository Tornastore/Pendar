extends "res://core/game_module.gd"
## Mastermind with CPU play and real two-device LAN play.
## In LAN mode the host owns the secret; it is never sent to the guessing client.

var mm_difficulty: int = 1
var mm_code_len: int = 4
var mm_color_count: int = 4
# Retained as a compatibility field; multiplayer is network-only, never hot-seat.
var mm_local_two_player: bool = false
# 0 = LAN host composing secret, 1 = guesser may submit, 2 = LAN client waiting for host,
# 3 = LAN host watching guesses, 4 = guess sent and awaiting authoritative response.
var mm_phase: int = 1
var mm_secret: Array = []
var mm_guesses: Array = []
var mm_cur: Array = []
var mm_slot: int = 0
var mm_turn_role: int = 0
var mm_game_over: bool = false
var mm_won: bool = false
var mm_filled: Array = []
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

# Feedback is position-mapped: 2 = exact match, 1 = correct colour in another
# position, 0 = no unmatched secret peg of that colour. Exact matches are claimed first.
func _mm_feedback(guess: Array) -> Array:
	var feedback: Array = []
	var secret_used: Array = []
	for i in range(mm_code_len):
		feedback.append(0)
		secret_used.append(false)
	for i in range(mm_code_len):
		if i < guess.size() and i < mm_secret.size() and guess[i] == mm_secret[i]:
			feedback[i] = 2
			secret_used[i] = true
	for i in range(mm_code_len):
		if feedback[i] == 2 or i >= guess.size():
			continue
		for j in range(mm_code_len):
			if secret_used[j] or j >= mm_secret.size():
				continue
			if guess[i] == mm_secret[j]:
				feedback[i] = 1
				secret_used[j] = true
				break
	return feedback

func _mm_evaluate(guess: Array) -> Array:
	var feedback: Array = _mm_feedback(guess)
	var black: int = 0
	var white: int = 0
	for value in feedback:
		if int(value) == 2:
			black += 1
		elif int(value) == 1:
			white += 1
	return [black, white]

func _reset_mastermind() -> void:
	mm_difficulty = clampi(mm_difficulty, 1, 6)
	# Each harder level adds one peg to the code AND one available colour.
	mm_code_len = clampi(3 + mm_difficulty, 4, 9)
	mm_color_count = clampi(3 + mm_difficulty, 4, 9)
	mm_secret = []
	mm_guesses = []
	mm_cur = _mm_blank_code()
	mm_filled = _mm_blank_filled()
	mm_slot = 0
	mm_phase = 1
	if app._net_on():
		mm_local_two_player = false
		mm_phase = 0 if app.is_host else 2
	else:
		for i in range(mm_code_len):
			mm_secret.append(randi() % mm_color_count)
	mm_game_over = false
	mm_won = false
	mm_turn = 0
	mm_winner = -1

func _mm_my_turn() -> bool:
	if mm_game_over:
		return false
	if app._net_on():
		return (app.is_host and mm_phase == 0) or (not app.is_host and mm_phase == 1)
	return mm_phase == 1

func _mm_slot_pos(i: int) -> Vector2:
	var gap: float = minf(86.0, float(app.VIEW_W - 52) / float(maxi(1, mm_code_len)))
	return Vector2(app.VIEW_W * 0.5 + (float(i) - float(mm_code_len - 1) * 0.5) * gap, 640.0)

func _mm_color_pos(i: int) -> Vector2:
	var gap: float = minf(56.0, float(app.VIEW_W - 32) / float(maxi(1, mm_color_count - 1)))
	return Vector2(app.VIEW_W * 0.5 + (float(i) - float(mm_color_count - 1) * 0.5) * gap, 738.0)

func _mm_pick(c: int) -> void:
	if mm_game_over or not _mm_my_turn() or c < 0 or c >= mm_color_count:
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

func _btns_mastermind() -> void:
	if mm_game_over:
		return
	if app._net_on() and mm_phase in [2, 3, 4]:
		return
	if not _mm_my_turn():
		return
	for i in range(mm_code_len):
		var c: Vector2 = _mm_slot_pos(i)
		app._add_hit(Rect2(c.x - 25, c.y - 25, 50, 50), _mm_pick_slot.bind(i), "mm_s%d" % i)
	for i in range(mm_color_count):
		var c2: Vector2 = _mm_color_pos(i)
		app._add_hit(Rect2(c2.x - 25, 706, 50, 64), _mm_pick.bind(i), "mm_c%d" % i)
	app._add_btn(Rect2(app.VIEW_W - 40 - 150, 800, 150, 56), "پاک کردن", _mm_clear, true, app.TEXT_DIM, "ghost", "undo", "mm_clear")
	var submit_label: String = "ثبت کد مخفی" if app._net_on() and app.is_host and mm_phase == 0 else "ثبت حدس"
	app._add_btn(Rect2(40, 800, 300, 56), submit_label, _mm_submit, _mm_all_filled(), app.GREEN, "solid", "check", "mm_ok")
	app._last_btn().hint = "%s خانه و %s رنگ برای کد؛ تکرار رنگ مجاز است." % [app._fa(mm_code_len), app._fa(mm_color_count)]

func _draw_mastermind() -> void:
	var used: int = mm_guesses.size()
	var net: bool = app._net_on()
	if net and app.is_host and mm_phase == 0:
		app._draw_hud("فکر بکر · ساخت کد مخفی", app._pl("طول کد", app.ACCENT, app._fa(mm_code_len), true, true, "%s رنگ در دسترس" % app._fa(mm_color_count)))
	elif net and not app.is_host and mm_phase == 2:
		app._draw_hud("فکر بکر · اتصال شبکه‌ای", app._pl("وضعیت", app.ACCENT, "انتظار", false, true, "میزبان کد مخفی را ثبت می‌کند"))
	elif net and app.is_host:
		app._draw_hud("فکر بکر · میزبان", app._pl("حدس‌ها", app.ACCENT, "%s/10" % app._fa(used), false, true, "کد روی این دستگاه پنهان است"))
	elif net:
		app._draw_hud("فکر بکر · حدس آنلاین", app._pl("تلاش", app.ACCENT, "%s/10" % app._fa(used), true, true, "%s خانه · %s رنگ" % [app._fa(mm_code_len), app._fa(mm_color_count)]))
	else:
		var difficulty_text: String = "سطح %s · %s خانه · %s رنگ" % [app._fa(mm_difficulty), app._fa(mm_code_len), app._fa(mm_color_count)]
		app._draw_hud("فکر بکر", app._pl("تلاش‌ها", app.ACCENT, "%s/10" % app._fa(used), true, true, difficulty_text))

	if net and not app.is_host and mm_phase == 2:
		var wait_panel := Rect2(28, 220, app.VIEW_W - 56, 250)
		app._panel(wait_panel, app.CARD, 24, app.LINE, 1.0, 14, 4)
		app._txt_c("منتظر میزبان…", Rect2(44, 270, app.VIEW_W - 88, 40), 25, app.ACCENT, true)
		app._wrap("میزبان باید کد مخفی را بسازد و ثبت کند. کد به دستگاه شما ارسال نمی‌شود؛ فقط بازخورد حدس‌ها می‌رسد.", 52, 328, app.VIEW_W - 104, 17, app.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		return
	if net and app._net_on() and not app.is_host and mm_phase == 4:
		app._hint("حدس ارسال شد؛ منتظر پاسخ میزبان بمانید…", 620, app.TEXT_DIM)

	var setup: bool = net and app.is_host and mm_phase == 0
	if setup:
		var setup_panel := Rect2(28, 150, app.VIEW_W - 56, 126)
		app._panel(setup_panel, app.CARD, 20, app.LINE, 1.0, 10, 4)
		app._txt_c("میزبان: کد مخفی را بساز", Rect2(42, 174, app.VIEW_W - 84, 34), 20, app.TEXT, true)
		app._wrap("بعد از ثبت، بازیکن متصل کد را حدس می‌زند. خود کد به دستگاه مهمان فرستاده نمی‌شود.", 52, 214, app.VIEW_W - 104, 16, app.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)

	if setup:
		var instructions := Rect2(28, 310, app.VIEW_W - 56, 220)
		app._panel(instructions, app.CARD, 20, app.LINE, 1.0, 12, 4)
		app._txt_c("چطور کد بسازید؟", Rect2(44, 334, app.VIEW_W - 88, 32), 18, app.TEXT, true)
		app._wrap("خانه‌های کد را انتخاب کنید و برای هر خانه یک رنگ بگذارید. سپس «ثبت کد مخفی» را بزنید تا گوشی دیگر بتواند حدس بزند. کد روی گوشی میزبان می‌ماند و برای مهمان ارسال نمی‌شود.", 52, 378, app.VIEW_W - 104, 17, app.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		var panel := Rect2(16, 150, app.VIEW_W - 32, 400)
		app._panel(panel, app.CARD, 22, app.LINE, 1.0, 12, 4)
		var guess_gap: float = minf(44.0, (panel.size.x - 116.0) / float(maxi(1, mm_code_len - 1)))
		var peg_radius: float = 13.0 if mm_code_len <= 5 else (11.0 if mm_code_len <= 7 else 9.5)
		for gi in range(10):
			var y: float = panel.position.y + 22.0 + float(gi) * 38.0
			if y + 18.0 > panel.end.y - 2.0:
				break
			var active: bool = (gi == used) and mm_phase != 4
			if active:
				app._panel(Rect2(panel.position.x + 8, y - 17, panel.size.x - 16, 34), Color(app.ACCENT.r, app.ACCENT.g, app.ACCENT.b, 0.10), 14, Color(app.ACCENT.r, app.ACCENT.g, app.ACCENT.b, 0.5), 1.0)
			app._txt_c(app._fa(gi + 1), Rect2(panel.end.x - 34, y - 14, 24, 28), 10, app.TEXT_FAINT, true)
			var peg_start_x: float = panel.get_center().x - float(mm_code_len - 1) * guess_gap * 0.5
			for i in range(mm_code_len):
				var peg: Vector2 = Vector2(peg_start_x + float(i) * guess_gap, y)
				if gi < used:
					var guess_row: Dictionary = mm_guesses[gi]
					app._draw_marble(peg, peg_radius, app.MM_COLORS[int(guess_row.g[i])])
				elif active and mm_filled[i]:
					app._draw_marble(peg, peg_radius, app.MM_COLORS[mm_cur[i]])
				else:
					app.draw_circle(peg, peg_radius, Color(1, 1, 1, 0.06))
					app._ring(peg, peg_radius, Color(1, 1, 1, 0.14), 1.0)
				if gi < used:
					var feedback: Array = mm_guesses[gi].get("f", [])
					var state_value: int = int(feedback[i]) if feedback.size() == mm_code_len else 0
					var mark := Vector2(peg.x, y + 14.0)
					if state_value == 2:
						app.draw_circle(mark, 5.4, Color(0.04, 0.05, 0.08))
						app._ring(mark, 5.4, Color(1, 1, 1, 0.48), 0.9)
					elif state_value == 1:
						app.draw_circle(mark, 5.4, Color(0.96, 0.97, 1.0))
						app._ring(mark, 5.4, Color(0.22, 0.24, 0.30), 0.8)
					else:
						app.draw_circle(mark, 4.6, Color(1, 1, 1, 0.04))
						app._ring(mark, 4.6, Color(1, 1, 1, 0.10), 0.8)
		app._txt_r("نشان زیر هر مهره متعلق به همان خانه است · سیاه: دقیق · سفید: رنگ درست", app.VIEW_W - 24, 574, 11, app.TEXT_DIM, false, 470)

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
		for i in range(mm_color_count):
			var pos: Vector2 = _mm_color_pos(i)
			var pressed: bool = app._press_active and app._press_id == "mm_c%d" % i
			app._draw_marble(pos, 18 if not pressed else 16, app.MM_COLORS[i])

func _mm_submit() -> void:
	if mm_game_over or not _mm_all_filled() or not _mm_my_turn():
		return
	if app._net_on() and app.is_host and mm_phase == 0:
		# Never send the secret itself over the network.
		mm_secret = mm_cur.duplicate()
		mm_phase = 3
		mm_cur = _mm_blank_code()
		mm_filled = _mm_blank_filled()
		mm_slot = 0
		if app.ws_match_active:
			if not app._ws_send_json({"type": "mastermind_secret_ready", "code_length": mm_code_len, "color_count": mm_color_count}):
				app._show_toast("کد ثبت شد اما ارسال به حریف ناموفق بود؛ اتصال را بررسی کنید.")
		else:
			var client_id: int = -1
			for pid in app.peer_to_seat.keys():
				if int(app.peer_to_seat[pid]) == 1:
					client_id = int(pid)
					break
			if client_id >= 0:
				app.rpc_id(client_id, "_rpc_mm_secret_ready", mm_code_len, mm_color_count)
			else:
				app._show_toast("بازیکن مهمان پیدا نشد؛ اتصال را بررسی کنید.")
		app._rebuild_buttons()
		return
	if app._net_on() and not app.is_host and mm_phase == 1:
		mm_phase = 4
		if app.ws_match_active:
			if not app._ws_send_json({"type": "mastermind_guess", "guess": mm_cur.duplicate()}):
				mm_phase = 1
				app._show_toast("حدس ارسال نشد؛ اتصال را بررسی کنید.")
		else:
			app.rpc_id(1, "_rpc_mm_submit", mm_cur.duplicate(), 1)
		app._rebuild_buttons()
		return
	_mm_apply(mm_cur.duplicate(), 0)

func _mm_apply(g: Array, player: int) -> void:
	if mm_game_over or g.size() != mm_code_len or mm_secret.size() != mm_code_len:
		return
	for colour in g:
		if int(colour) < 0 or int(colour) >= mm_color_count:
			return
	var feedback: Array = _mm_feedback(g)
	var black: int = 0
	var white: int = 0
	for val in feedback:
		if int(val) == 2:
			black += 1
		elif int(val) == 1:
			white += 1
	mm_guesses.append({"g": g.duplicate(), "b": black, "w": white, "f": feedback, "p": player})
	if black == mm_code_len:
		mm_game_over = true
		mm_winner = player
	elif mm_guesses.size() >= 10:
		mm_game_over = true
		mm_winner = 0 if app._net_on() else (1 if app.vs_cpu else -1)
	else:
		mm_cur = _mm_blank_code()
		mm_filled = _mm_blank_filled()
		mm_slot = 0
	mm_won = mm_winner == app._my_seat() if mm_game_over else false
	if mm_game_over:
		app._go_result(false)
	else:
		app._build_playing_buttons()
	if app._net_on() and app.is_host:
		if app.ws_match_active:
			app._ws_send_json({"type": "mastermind_sync", "guesses": mm_guesses, "is_over": mm_game_over, "winner": mm_winner})
		else:
			for pid in app.peer_to_seat.keys():
				if int(app.peer_to_seat[pid]) == 1:
					app.rpc_id(int(pid), "_rpc_mm_sync_state", mm_guesses, mm_game_over, mm_winner)
					break
