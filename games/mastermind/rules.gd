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
var mm_online_race: bool = false
var mm_lan_race: bool = false
var mm_cpu_race: bool = false
var mm_cpu_racers: Array = []
var mm_cpu_race_started_msec: int = 0
var mm_online_progress: Array = []
var mm_race_finished: bool = false
var mm_race_status: String = ""

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
	var requested_cpu_race: bool = mm_cpu_race and app.vs_cpu and app.selected_game == "mastermind"
	mm_difficulty = clampi(mm_difficulty, 1, 6)
	# Higher difficulty increases both code length and available colours.
	mm_code_len = clampi(3 + mm_difficulty, 4, 9)
	mm_color_count = clampi(3 + mm_difficulty, 4, 9)
	mm_secret = []
	mm_guesses = []
	mm_cur = _mm_blank_code()
	mm_filled = _mm_blank_filled()
	mm_slot = 0
	mm_phase = 1
	mm_online_race = app.ws_match_active and app.selected_game == "mastermind"
	mm_lan_race = (not app.ws_match_active and app.multiplayer.multiplayer_peer != null and app.connected_players >= 2 and app.selected_game == "mastermind")
	mm_cpu_race = requested_cpu_race and not mm_online_race and not mm_lan_race
	if mm_online_race:
		# The online matchmaker stores the secret on the server only.
		mm_secret = []
		mm_phase = 1
	elif mm_lan_race:
		# In IP/LAN races, the host evaluates guesses. Other clients never receive the secret.
		if app.is_host:
			for i in range(mm_code_len):
				mm_secret.append(randi() % mm_color_count)
		mm_phase = 1
	elif app._net_on():
		mm_local_two_player = false
		mm_phase = 0 if app.is_host else 2
	else:
		for i in range(mm_code_len):
			mm_secret.append(randi() % mm_color_count)
	mm_game_over = false
	mm_won = false
	mm_turn = 0
	mm_winner = -1
	mm_online_progress = []
	mm_cpu_racers = []
	mm_cpu_race_started_msec = Time.get_ticks_msec()
	mm_race_finished = false
	mm_race_status = ""
	if mm_cpu_race:
		for seat in range(4):
			mm_cpu_racers.append({
				"seat": seat,
				"username": "شما" if seat == 0 else "CPU %s" % app._fa(seat),
				"attempts_used": 0,
				"latest_black": 0,
				"status": "active",
				"solve_ms": 0,
				"history": [],
				"tried": {},
				"next_guess_msec": mm_cpu_race_started_msec + (900 if seat == 0 else randi_range(1600, 2400))
			})
		_mm_cpu_race_refresh_progress()

func _mm_is_race_mode() -> bool:
	return mm_online_race or mm_lan_race or mm_cpu_race

func _mm_my_turn() -> bool:
	if mm_game_over:
		return false
	if _mm_is_race_mode():
		if mm_cpu_race and not mm_cpu_racers.is_empty() and str(mm_cpu_racers[0].get("status", "active")) != "active":
			return false
		return mm_phase == 1
	if app._net_on():
		return (app.is_host and mm_phase == 0) or (not app.is_host and mm_phase == 1)
	return mm_phase == 1

func _mm_slot_pos(i: int) -> Vector2:
	var panel_width: float = 360.0 if _mm_is_race_mode() else float(app.VIEW_W - 52)
	var center_x: float = 188.0 if _mm_is_race_mode() else app.VIEW_W * 0.5
	var gap: float = minf(44.0 if _mm_is_race_mode() else 86.0, (panel_width - 72.0) / float(maxi(1, mm_code_len - 1)))
	return Vector2(center_x + (float(i) - float(mm_code_len - 1) * 0.5) * gap, 640.0)

func _mm_color_pos(i: int) -> Vector2:
	var panel_width: float = 360.0 if _mm_is_race_mode() else float(app.VIEW_W)
	var center_x: float = 188.0 if _mm_is_race_mode() else app.VIEW_W * 0.5
	var gap: float = minf(38.0 if _mm_is_race_mode() else 56.0, (panel_width - 36.0) / float(maxi(1, mm_color_count - 1)))
	return Vector2(center_x + (float(i) - float(mm_color_count - 1) * 0.5) * gap, 738.0)

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
	if mm_cpu_race:
		var human_done: bool = not mm_cpu_racers.is_empty() and str(mm_cpu_racers[0].get("status", "active")) != "active"
		app._draw_hud("فکر بکر · مسابقه با ۳ CPU", app._pl("تلاش‌های شما", app.ACCENT, "%s/10" % app._fa(used), not human_done and not mm_game_over, true, "هر حریف کد را جداگانه حدس می‌زند"))
	elif _mm_is_race_mode():
		app._draw_hud("فکر بکر · مسابقه %s نفره" % app._fa(app.connected_players), app._pl("تلاش‌های شما", app.ACCENT, "%s/10" % app._fa(used), not mm_game_over, true, "رقابت سرعتی · کد در سرور پنهان است"))
	elif net and app.is_host and mm_phase == 0:
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
		var panel := Rect2(8, 150, 360, 400) if _mm_is_race_mode() else Rect2(16, 150, app.VIEW_W - 32, 400)
		app._panel(panel, app.CARD, 22, app.LINE, 1.0, 12, 4)
		var guess_gap: float = minf(44.0, (panel.size.x - 116.0) / float(maxi(1, mm_code_len - 1)))
		var peg_radius: float = 13.0 if mm_code_len <= 5 else (11.0 if mm_code_len <= 7 else 9.5)
		for gi in range(10):
			var y: float = panel.position.y + 22.0 + float(gi) * 38.0
			if y + 18.0 > panel.end.y - 2.0:
				break
			var active: bool = (gi == used) and (mm_phase != 4 or _mm_is_race_mode())
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
		if not mm_online_race:
			app._txt_r("نشان زیر هر مهره متعلق به همان خانه است · سیاه: دقیق · سفید: رنگ درست", app.VIEW_W - 24, 574, 11, app.TEXT_DIM, false, 470)

	if _mm_is_race_mode():
		_draw_mm_online_sidebar()

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


func _mm_code_key(code: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for value in code:
		parts.append(str(int(value)))
	return ",".join(parts)

func _mm_score_guess_for_secret(guess: Array, candidate_secret: Array) -> Array[int]:
	var black: int = 0
	var guess_counts: Dictionary = {}
	var secret_counts: Dictionary = {}
	for index in range(mm_code_len):
		var g: int = int(guess[index])
		var secret_value: int = int(candidate_secret[index])
		if g == secret_value:
			black += 1
		else:
			guess_counts[g] = int(guess_counts.get(g, 0)) + 1
			secret_counts[secret_value] = int(secret_counts.get(secret_value, 0)) + 1
	var white: int = 0
	for key in guess_counts.keys():
		white += mini(int(guess_counts[key]), int(secret_counts.get(key, 0)))
	return [black, white]

func _mm_cpu_candidate_consistent(candidate: Array, history: Array) -> bool:
	for old in history:
		var score: Array[int] = _mm_score_guess_for_secret(old.get("g", []), candidate)
		if score[0] != int(old.get("b", 0)) or score[1] != int(old.get("w", 0)):
			return false
	return true

func _mm_cpu_guess_partition_cost(guess: Array, candidates: Array) -> int:
	var buckets: Dictionary = {}
	var largest: int = 0
	for possible_secret in candidates:
		var score: Array[int] = _mm_score_guess_for_secret(guess, possible_secret)
		var key: String = "%d:%d" % [score[0], score[1]]
		buckets[key] = int(buckets.get(key, 0)) + 1
		largest = maxi(largest, int(buckets[key]))
	var squares: int = 0
	for value in buckets.values():
		squares += int(value) * int(value)
	return largest * 100000 + squares

func _mm_cpu_make_guess(racer: Dictionary) -> Array:
	var history: Array = racer.get("history", [])
	var tried: Dictionary = racer.get("tried", {})
	var level: int = clampi(mm_difficulty, 1, 6)
	var sample_budgets: Array[int] = [0, 80, 180, 350, 600, 950, 1300]
	var pool_limits: Array[int] = [0, 1, 1, 22, 36, 55, 75]
	var pool: Array = []
	var pool_keys: Dictionary = {}
	var require_consistency: bool = level >= 2
	for attempt in range(sample_budgets[level]):
		var candidate: Array = []
		for slot in range(mm_code_len):
			candidate.append(randi() % mm_color_count)
		var key: String = _mm_code_key(candidate)
		if tried.has(key) or pool_keys.has(key):
			continue
		if require_consistency and not _mm_cpu_candidate_consistent(candidate, history):
			continue
		pool_keys[key] = true
		pool.append(candidate)
		if pool.size() >= pool_limits[level]:
			break
	if pool.is_empty():
		for attempt in range(300):
			var fallback: Array = []
			for slot in range(mm_code_len):
				fallback.append(randi() % mm_color_count)
			var fallback_key: String = _mm_code_key(fallback)
			if not tried.has(fallback_key):
				return fallback
		return _mm_blank_code()
	if level >= 5 and pool.size() > 1:
		var best_guess: Array = pool[0]
		var best_cost: int = 2147483647
		for candidate_guess in pool:
			var cost: int = _mm_cpu_guess_partition_cost(candidate_guess, pool)
			if cost < best_cost:
				best_cost = cost
				best_guess = candidate_guess
		return best_guess.duplicate()
	return pool[randi() % pool.size()].duplicate()

func _mm_cpu_race_before(a: Dictionary, b: Dictionary) -> bool:
	var sa: String = str(a.get("status", "active"))
	var sb: String = str(b.get("status", "active"))
	var rank_order: Dictionary = {"solved": 0, "active": 1, "failed": 2}
	var ra: int = int(rank_order.get(sa, 3))
	var rb: int = int(rank_order.get(sb, 3))
	if ra != rb:
		return ra < rb
	if sa == "solved" and int(a.get("solve_ms", 0)) != int(b.get("solve_ms", 0)):
		return int(a.get("solve_ms", 0)) < int(b.get("solve_ms", 0))
	if int(a.get("latest_black", 0)) != int(b.get("latest_black", 0)):
		return int(a.get("latest_black", 0)) > int(b.get("latest_black", 0))
	if int(a.get("attempts_used", 0)) != int(b.get("attempts_used", 0)):
		return int(a.get("attempts_used", 0)) < int(b.get("attempts_used", 0))
	return int(a.get("seat", 0)) < int(b.get("seat", 0))

func _mm_cpu_race_refresh_progress() -> void:
	var progress: Array = mm_cpu_racers.duplicate(true)
	progress.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _mm_cpu_race_before(a, b))
	for index in range(progress.size()):
		var entry: Dictionary = progress[index]
		entry["rank"] = index + 1
		progress[index] = entry
	mm_online_progress = progress

func _mm_cpu_race_finish_if_complete() -> void:
	if not mm_cpu_race or mm_game_over or mm_cpu_racers.size() != 4:
		return
	for racer in mm_cpu_racers:
		if str(racer.get("status", "active")) == "active":
			return
	_mm_cpu_race_refresh_progress()
	mm_game_over = true
	mm_race_finished = true
	var top: Dictionary = mm_online_progress[0] if not mm_online_progress.is_empty() else {}
	mm_winner = int(top.get("seat", -1)) if str(top.get("status", "")) == "solved" else -1
	mm_won = mm_winner == 0
	mm_race_status = "نفر اول شدی!" if mm_won else ("مساوی" if mm_winner < 0 else "CPU %s زودتر کد را پیدا کرد" % app._fa(mm_winner))
	app._go_result(false)

func _mm_cpu_race_record_human_guess(guess: Array) -> void:
	if mm_game_over or mm_cpu_racers.size() != 4 or str(mm_cpu_racers[0].get("status", "active")) != "active":
		return
	if guess.size() != mm_code_len or mm_secret.size() != mm_code_len:
		return
	for colour in guess:
		if int(colour) < 0 or int(colour) >= mm_color_count:
			return
	var score: Array[int] = _mm_score_guess_for_secret(guess, mm_secret)
	var black: int = score[0]
	var white: int = score[1]
	var row: Dictionary = {"g": guess.duplicate(), "b": black, "w": white, "f": _mm_feedback(guess), "p": 0}
	mm_guesses.append(row)
	var racer: Dictionary = mm_cpu_racers[0]
	racer["attempts_used"] = int(racer.get("attempts_used", 0)) + 1
	racer["latest_black"] = black
	var history: Array = racer.get("history", [])
	history.append({"g": guess.duplicate(), "b": black, "w": white})
	racer["history"] = history
	if black == mm_code_len:
		racer["status"] = "solved"
		racer["solve_ms"] = maxi(1, Time.get_ticks_msec() - mm_cpu_race_started_msec)
	elif int(racer["attempts_used"]) >= 10:
		racer["status"] = "failed"
	mm_cpu_racers[0] = racer
	if str(racer.get("status", "active")) == "active":
		mm_cur = _mm_blank_code()
		mm_filled = _mm_blank_filled()
		mm_slot = 0
	else:
		mm_phase = 4
	_mm_cpu_race_refresh_progress()
	_mm_cpu_race_finish_if_complete()
	if not mm_game_over:
		app._build_playing_buttons()

func _mm_cpu_race_tick() -> void:
	if not mm_cpu_race or mm_game_over or mm_secret.size() != mm_code_len or mm_cpu_racers.size() != 4:
		return
	var now: int = Time.get_ticks_msec()
	for seat in range(1, 4):
		var racer: Dictionary = mm_cpu_racers[seat]
		if str(racer.get("status", "active")) != "active" or now < int(racer.get("next_guess_msec", now + 1000)):
			continue
		var guess: Array = _mm_cpu_make_guess(racer)
		var score: Array[int] = _mm_score_guess_for_secret(guess, mm_secret)
		var history: Array = racer.get("history", [])
		history.append({"g": guess.duplicate(), "b": score[0], "w": score[1]})
		racer["history"] = history
		var attempts: int = int(racer.get("attempts_used", 0)) + 1
		racer["attempts_used"] = attempts
		racer["latest_black"] = score[0]
		var tried: Dictionary = racer.get("tried", {})
		tried[_mm_code_key(guess)] = true
		racer["tried"] = tried
		if score[0] == mm_code_len:
			racer["status"] = "solved"
			racer["solve_ms"] = maxi(1, now - mm_cpu_race_started_msec)
		elif attempts >= 10:
			racer["status"] = "failed"
		else:
			var delay: int = 2700 - (mm_difficulty - 1) * 250
			racer["next_guess_msec"] = now + maxi(850, delay) + randi_range(0, 400)
		mm_cpu_racers[seat] = racer
		_mm_cpu_race_refresh_progress()
		_mm_cpu_race_finish_if_complete()
		app._rebuild_buttons()
		return


func _mm_submit() -> void:
	if mm_game_over or not _mm_all_filled() or not _mm_my_turn():
		return
	if mm_online_race:
		var guess_to_send: Array = mm_cur.duplicate()
		if app._ws_send_json({"type": "mastermind_guess", "guess": guess_to_send}):
			mm_phase = 4
			app._show_toast("حدس ثبت شد؛ منتظر نتیجه‌ی سرور…")
		else:
			app._show_toast("اتصال مسابقه قطع است؛ حدس ارسال نشد.")
		app._rebuild_buttons()
		return
	if mm_lan_race:
		var lan_guess: Array = mm_cur.duplicate()
		if app.is_host:
			app._mm_lan_process_guess(lan_guess, app.local_seat)
		else:
			mm_phase = 4
			app.rpc_id(1, "_rpc_mm_lan_submit", lan_guess, app.local_seat)
			app._show_toast("حدس ارسال شد؛ منتظر بازخورد هستید…")
			app._rebuild_buttons()
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

func _draw_mm_online_sidebar() -> void:
	var sidebar := Rect2(376, 150, 156, 400)
	app._panel(sidebar, Color(0.10, 0.13, 0.25), 18, Color(app.ACCENT.r, app.ACCENT.g, app.ACCENT.b, 0.55), 1.0, 8, 3)
	app._txt_c("رتبه‌بندی", Rect2(sidebar.position.x + 4, sidebar.position.y + 9, sidebar.size.x - 8, 26), 14, app.TEXT, true)
	if mm_online_progress.is_empty():
		app._wrap("در انتظار وضعیت بازیکنان…", sidebar.position.x + 12, sidebar.position.y + 52, sidebar.size.x - 24, 11, app.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var row_h: float = 84.0
	for i in range(mini(mm_online_progress.size(), 4)):
		var entry: Dictionary = mm_online_progress[i]
		var row := Rect2(sidebar.position.x + 6, sidebar.position.y + 42 + float(i) * row_h, sidebar.size.x - 12, 78)
		var mine: bool = int(entry.get("seat", -1)) == app.local_seat
		var edge: Color = app.ACCENT if mine else app.LINE
		app._panel(row, Color(app.ACCENT.r, app.ACCENT.g, app.ACCENT.b, 0.10) if mine else Color(1, 1, 1, 0.035), 10, edge, 1.0)
		app._txt_r("#%s" % app._fa(int(entry.get("rank", i + 1))), row.end.x - 5, row.position.y + 20, 12, app.ACCENT if i == 0 else app.TEXT_DIM, true, 28)
		app._txt_r(str(entry.get("username", "بازیکن")), row.end.x - 32, row.position.y + 20, 11, app.TEXT, true, 86)
		var exact_count: int = int(entry.get("latest_black", 0))
		app._txt_r("خانه‌ی دقیق: %s از %s" % [app._fa(exact_count), app._fa(mm_code_len)], row.end.x - 6, row.position.y + 44, 10, app.TEXT_DIM, false, row.size.x - 12)
		# Progress only: never show another player's guesses, attempt count, or feedback pattern.
		var progress_track := Rect2(row.position.x + 8, row.position.y + 54, row.size.x - 16, 7)
		app._panel(progress_track, Color(1, 1, 1, 0.07), 4)
		var progress_ratio: float = clampf(float(exact_count) / float(maxi(1, mm_code_len)), 0.0, 1.0)
		if progress_ratio > 0.0:
			app._panel(Rect2(progress_track.position.x, progress_track.position.y, progress_track.size.x * progress_ratio, progress_track.size.y), app.GREEN if exact_count == mm_code_len else app.ACCENT, 4)

func _mm_online_feedback(message: Dictionary) -> void:
	if not mm_online_race:
		return
	_mm_accept_race_feedback(message)

func _mm_lan_feedback(message: Dictionary) -> void:
	if not mm_lan_race:
		return
	_mm_accept_race_feedback(message)

func _mm_accept_race_feedback(message: Dictionary) -> void:
	if mm_game_over:
		return
	var guess_value: Variant = message.get("guess", [])
	var feedback_value: Variant = message.get("feedback", [])
	if not (guess_value is Array) or not (feedback_value is Array):
		return
	if guess_value.size() != mm_code_len or feedback_value.size() != mm_code_len:
		return
	mm_guesses.append({
		"g": guess_value.duplicate(),
		"f": feedback_value.duplicate(),
		"b": int(message.get("black", 0)),
		"w": int(message.get("white", 0)),
		"p": app.local_seat
	})
	var solved: bool = bool(message.get("solved", false))
	var failed: bool = bool(message.get("failed", false))
	mm_cur = _mm_blank_code()
	mm_filled = _mm_blank_filled()
	mm_slot = 0
	mm_phase = 1
	if solved or failed:
		mm_game_over = true
		mm_won = solved
		mm_winner = app.local_seat if solved else -1
		mm_race_status = "کد را پیدا کردی!" if solved else "فرصت حدس تمام شد"
		# Keep the live leaderboard visible until every racer has finished.
		app._show_toast(mm_race_status)
		app._build_playing_buttons()
	else:
		app._show_toast("بازخورد دریافت شد؛ حدس بعدی را ثبت کن.")
		app._build_playing_buttons()

func _mm_apply(g: Array, player: int) -> void:
	if mm_cpu_race:
		_mm_cpu_race_record_human_guess(g)
		return
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
