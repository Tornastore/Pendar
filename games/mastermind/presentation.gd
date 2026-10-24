extends RefCounted
## Mastermind UI presentation. The rules module owns secret, guess state, phases,
## scoring, CPU race progress and all authoritative online/LAN transitions.

func slot_pos(app, game, i: int) -> Vector2:
	var panel_width: float = 360.0 if game._mm_is_race_mode() else float(app.VIEW_W - 52)
	var center_x: float = 188.0 if game._mm_is_race_mode() else app.VIEW_W * 0.5
	var gap: float = minf(44.0 if game._mm_is_race_mode() else 86.0, (panel_width - 72.0) / float(maxi(1, game.mm_code_len - 1)))
	return Vector2(center_x + (float(i) - float(game.mm_code_len - 1) * 0.5) * gap, 640.0)

func color_pos(app, game, i: int) -> Vector2:
	var panel_width: float = 360.0 if game._mm_is_race_mode() else float(app.VIEW_W)
	var center_x: float = 188.0 if game._mm_is_race_mode() else app.VIEW_W * 0.5
	var gap: float = minf(38.0 if game._mm_is_race_mode() else 56.0, (panel_width - 36.0) / float(maxi(1, game.mm_color_count - 1)))
	return Vector2(center_x + (float(i) - float(game.mm_color_count - 1) * 0.5) * gap, 738.0)

func build_buttons(app, game) -> void:
	if game.mm_game_over:
		return
	if app._net_on() and game.mm_phase in [2, 3, 4]:
		return
	if not game._mm_my_turn():
		return
	for i in range(game.mm_code_len):
		var c: Vector2 = slot_pos(app, game, i)
		app._add_hit(Rect2(c.x - 25, c.y - 25, 50, 50), game._mm_pick_slot.bind(i), "mm_s%d" % i)
	for i in range(game.mm_color_count):
		var c2: Vector2 = color_pos(app, game, i)
		app._add_hit(Rect2(c2.x - 25, 706, 50, 64), game._mm_pick.bind(i), "mm_c%d" % i)
	app._add_btn(Rect2(app.VIEW_W - 40 - 150, 800, 150, 56), "پاک کردن", game._mm_clear, true, app.TEXT_DIM, "ghost", "undo", "mm_clear")
	var submit_label: String = "ثبت کد مخفی" if app._net_on() and app.is_host and game.mm_phase == 0 else "ثبت حدس"
	app._add_btn(Rect2(40, 800, 300, 56), submit_label, game._mm_submit, game._mm_all_filled(), app.GREEN, "solid", "check", "mm_ok")
	app._last_btn().hint = "%s خانه و %s رنگ برای کد؛ تکرار رنگ مجاز است." % [app._fa(game.mm_code_len), app._fa(game.mm_color_count)]

func render(app, game) -> void:
	var used: int = game.mm_guesses.size()
	var net: bool = app._net_on()
	if game.mm_cpu_race:
		var human_done: bool = not game.mm_cpu_racers.is_empty() and str(game.mm_cpu_racers[0].get("status", "active")) != "active"
		app._draw_hud("فکر بکر · مسابقه با ۳ CPU", app._pl("تلاش‌های شما", app.ACCENT, "%s/10" % app._fa(used), not human_done and not game.mm_game_over, true, "هر حریف کد را جداگانه حدس می‌زند"))
	elif game._mm_is_race_mode():
		app._draw_hud("فکر بکر · مسابقه %s نفره" % app._fa(app.connected_players), app._pl("تلاش‌های شما", app.ACCENT, "%s/10" % app._fa(used), not game.mm_game_over, true, "رقابت سرعتی · کد در سرور پنهان است"))
	elif net and app.is_host and game.mm_phase == 0:
		app._draw_hud("فکر بکر · ساخت کد مخفی", app._pl("طول کد", app.ACCENT, app._fa(game.mm_code_len), true, true, "%s رنگ در دسترس" % app._fa(game.mm_color_count)))
	elif net and not app.is_host and game.mm_phase == 2:
		app._draw_hud("فکر بکر · اتصال شبکه‌ای", app._pl("وضعیت", app.ACCENT, "انتظار", false, true, "میزبان کد مخفی را ثبت می‌کند"))
	elif net and app.is_host:
		app._draw_hud("فکر بکر · میزبان", app._pl("حدس‌ها", app.ACCENT, "%s/10" % app._fa(used), false, true, "کد روی این دستگاه پنهان است"))
	elif net:
		app._draw_hud("فکر بکر · حدس آنلاین", app._pl("تلاش", app.ACCENT, "%s/10" % app._fa(used), true, true, "%s خانه · %s رنگ" % [app._fa(game.mm_code_len), app._fa(game.mm_color_count)]))
	else:
		var difficulty_text: String = "سطح %s · %s خانه · %s رنگ" % [app._fa(game.mm_difficulty), app._fa(game.mm_code_len), app._fa(game.mm_color_count)]
		app._draw_hud("فکر بکر", app._pl("تلاش‌ها", app.ACCENT, "%s/10" % app._fa(used), true, true, difficulty_text))

	if net and not app.is_host and game.mm_phase == 2:
		var wait_panel := Rect2(28, 220, app.VIEW_W - 56, 250)
		app._panel(wait_panel, app.CARD, 24, app.LINE, 1.0, 14, 4)
		app._txt_c("منتظر میزبان…", Rect2(44, 270, app.VIEW_W - 88, 40), 25, app.ACCENT, true)
		app._wrap("میزبان باید کد مخفی را بسازد و ثبت کند. کد به دستگاه شما ارسال نمی‌شود؛ فقط بازخورد حدس‌ها می‌رسد.", 52, 328, app.VIEW_W - 104, 17, app.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		return
	if net and app._net_on() and not app.is_host and game.mm_phase == 4:
		app._hint("حدس ارسال شد؛ منتظر پاسخ میزبان بمانید…", 620, app.TEXT_DIM)

	var setup: bool = net and app.is_host and game.mm_phase == 0
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
		var panel := Rect2(8, 150, 360, 400) if game._mm_is_race_mode() else Rect2(16, 150, app.VIEW_W - 32, 400)
		app._panel(panel, app.CARD, 22, app.LINE, 1.0, 12, 4)
		var guess_gap: float = minf(44.0, (panel.size.x - 116.0) / float(maxi(1, game.mm_code_len - 1)))
		var peg_radius: float = 13.0 if game.mm_code_len <= 5 else (11.0 if game.mm_code_len <= 7 else 9.5)
		for gi in range(10):
			var y: float = panel.position.y + 22.0 + float(gi) * 38.0
			if y + 18.0 > panel.end.y - 2.0:
				break
			var active: bool = (gi == used) and (game.mm_phase != 4 or game._mm_is_race_mode())
			if active:
				app._panel(Rect2(panel.position.x + 8, y - 17, panel.size.x - 16, 34), Color(app.ACCENT.r, app.ACCENT.g, app.ACCENT.b, 0.10), 14, Color(app.ACCENT.r, app.ACCENT.g, app.ACCENT.b, 0.5), 1.0)
			app._txt_c(app._fa(gi + 1), Rect2(panel.end.x - 34, y - 14, 24, 28), 10, app.TEXT_FAINT, true)
			var peg_start_x: float = panel.get_center().x - float(game.mm_code_len - 1) * guess_gap * 0.5
			for i in range(game.mm_code_len):
				var peg: Vector2 = Vector2(peg_start_x + float(i) * guess_gap, y)
				if gi < used:
					var guess_row: Dictionary = game.mm_guesses[gi]
					app._draw_marble(peg, peg_radius, app.MM_COLORS[int(guess_row.g[i])])
				elif active and game.mm_filled[i]:
					app._draw_marble(peg, peg_radius, app.MM_COLORS[game.mm_cur[i]])
				else:
					app.draw_circle(peg, peg_radius, Color(1, 1, 1, 0.06))
					app._ring(peg, peg_radius, Color(1, 1, 1, 0.14), 1.0)
				if gi < used:
					var feedback: Array = game.mm_guesses[gi].get("f", [])
					var state_value: int = int(feedback[i]) if feedback.size() == game.mm_code_len else 0
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
		if not game.mm_online_race:
			app._txt_r("نشان زیر هر مهره متعلق به همان خانه است · سیاه: دقیق · سفید: رنگ درست", app.VIEW_W - 24, 574, 11, app.TEXT_DIM, false, 470)

	if game._mm_is_race_mode():
		render_online_sidebar(app, game)

	if game._mm_my_turn():
		var current_title: String = "کد مخفی شما" if setup else "حدس فعلی"
		app._txt_c(current_title, Rect2(0, 586, app.VIEW_W, 22), 13, app.TEXT_DIM, true)
		for i in range(game.mm_code_len):
			var c2: Vector2 = slot_pos(app, game, i)
			var sel: bool = (i == game.mm_slot)
			app.draw_circle(c2, 27, Color(1, 1, 1, 0.06))
			app._ring(c2, 27, app.ACCENT if sel else Color(1, 1, 1, 0.18), 2.5 if sel else 1.2)
			if game.mm_filled[i]:
				app._draw_marble(c2, 22 if game.mm_code_len >= 8 else 25, app.MM_COLORS[game.mm_cur[i]])
		for i in range(game.mm_color_count):
			var pos: Vector2 = color_pos(app, game, i)
			var pressed: bool = app._press_active and app._press_id == "mm_c%d" % i
			app._draw_marble(pos, 18 if not pressed else 16, app.MM_COLORS[i])

func render_online_sidebar(app, game) -> void:
	var sidebar := Rect2(376, 150, 156, 400)
	app._panel(sidebar, Color(0.10, 0.13, 0.25), 18, Color(app.ACCENT.r, app.ACCENT.g, app.ACCENT.b, 0.55), 1.0, 8, 3)
	app._txt_c("رتبه‌بندی", Rect2(sidebar.position.x + 4, sidebar.position.y + 9, sidebar.size.x - 8, 26), 14, app.TEXT, true)
	if game.mm_online_progress.is_empty():
		app._wrap("در انتظار وضعیت بازیکنان…", sidebar.position.x + 12, sidebar.position.y + 52, sidebar.size.x - 24, 11, app.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var row_h: float = 84.0
	for i in range(mini(game.mm_online_progress.size(), 4)):
		var entry: Dictionary = game.mm_online_progress[i]
		var row := Rect2(sidebar.position.x + 6, sidebar.position.y + 42 + float(i) * row_h, sidebar.size.x - 12, 78)
		var mine: bool = int(entry.get("seat", -1)) == app.local_seat
		var edge: Color = app.ACCENT if mine else app.LINE
		app._panel(row, Color(app.ACCENT.r, app.ACCENT.g, app.ACCENT.b, 0.10) if mine else Color(1, 1, 1, 0.035), 10, edge, 1.0)
		app._txt_r("#%s" % app._fa(int(entry.get("rank", i + 1))), row.end.x - 5, row.position.y + 20, 12, app.ACCENT if i == 0 else app.TEXT_DIM, true, 28)
		app._txt_r(str(entry.get("username", "بازیکن")), row.end.x - 32, row.position.y + 20, 11, app.TEXT, true, 86)
		var exact_count: int = int(entry.get("latest_black", 0))
		app._txt_r("خانه‌ی دقیق: %s از %s" % [app._fa(exact_count), app._fa(game.mm_code_len)], row.end.x - 6, row.position.y + 44, 10, app.TEXT_DIM, false, row.size.x - 12)
		# Progress only: never show another player's guesses, attempt count, or feedback pattern.
		var progress_track := Rect2(row.position.x + 8, row.position.y + 54, row.size.x - 16, 7)
		app._panel(progress_track, Color(1, 1, 1, 0.07), 4)
		var progress_ratio: float = clampf(float(exact_count) / float(maxi(1, game.mm_code_len)), 0.0, 1.0)
		if progress_ratio > 0.0:
			app._panel(Rect2(progress_track.position.x, progress_track.position.y, progress_track.size.x * progress_ratio, progress_track.size.y), app.GREEN if exact_count == game.mm_code_len else app.ACCENT, 4)
