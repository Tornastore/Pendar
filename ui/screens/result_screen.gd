extends RefCounted
## Result presentation for finished games and the compact in-game result popup.
## Result calculation, score persistence, state transitions and actions stay in main.gd.


func build_buttons(host, theme: Dictionary) -> void:
	var can_restart: bool = host.vs_cpu or host.is_host
	var label: String = "بازی دوباره"
	if host.selected_game == "pasoor" and not host._pas_match_over():
		label = "دست بعدی"
	if host.selected_game == "uno" and bool(host._game_modules["uno"].uno_round_over) and not bool(host._game_modules["uno"].uno_game_over):
		label = "دست بعدی"
	host._add_btn(Rect2(40, 668, float(theme["VIEW_W"]) - 80, 62), label if can_restart else "منتظر میزبان…", host._restart_current, can_restart, theme["GREEN"], "solid", "restart", "again")
	host._last_btn().hint = "فقط میزبان می‌تواند بازی جدید را شروع کند."
	host._add_btn(Rect2(float(theme["VIEW_W"]) - 40 - 242, 746, 242, 54), "تغییر حالت", host._change_mode, true, theme["BLUE"], "soft", "swap", "mode")
	host._add_btn(Rect2(40, 746, 242, 54), "منوی اصلی", host._back_to_menu, true, theme["ACCENT"], "soft", "home", "home")
	host._add_btn(Rect2(40, 816, float(theme["VIEW_W"]) - 80, 48), "مشاهده آمار", host._open_dashboard, true, theme["TEXT_DIM"], "ghost", "chart", "stats")


func render(host, theme: Dictionary) -> void:
	var info: Dictionary = host._result_info()
	var won: bool = host._player_won_current()
	var result_draw: bool = host._result_draw
	var tcol: Color = theme["TEXT_DIM"] if result_draw else (theme["GREEN"] if won else theme["RED"])
	var t: float = host._time - host._result_t0
	# Glow and emblem animation remain presentation-only; result state is owned by main.gd.
	host._glow(Vector2(float(theme["VIEW_W"]) * 0.5, 190), 230, Color(tcol.r, tcol.g, tcol.b, 0.30))
	var pop: float = host._ease_back(t / 0.5)
	var c := Vector2(float(theme["VIEW_W"]) * 0.5, 190)
	host.draw_circle(c, 78 * pop, Color(tcol.r * 0.28, tcol.g * 0.28, tcol.b * 0.28, 1.0))
	host._ring(c, 78 * pop, tcol, 3.0)
	host._ring(c, 92 * pop + 3.0 * sin(t * 3.0), Color(tcol.r, tcol.g, tcol.b, 0.30), 2.0)
	var icon: String = "swap" if result_draw else ("trophy" if won else "flag")
	host._draw_icon(icon, c, 76 * pop, tcol.lightened(0.2), 4.0)
	if won and not result_draw:
		for i in 28:
			var seed_v: float = float(i) * 12.9898
			var px: float = fposmod(sin(seed_v) * 43758.5453, 1.0)
			var spd: float = 70.0 + fposmod(sin(seed_v * 1.7) * 9231.13, 1.0) * 110.0
			var py: float = fposmod(-40.0 + t * spd + fposmod(sin(seed_v * 2.3) * 1111.1, 1.0) * 300.0, 560.0) + 40.0
			if t * spd > 600.0:
				py = 2000.0
			var cc: Color = theme["MM_COLORS"][i % 6]
			var rot: float = t * (2.0 + px * 3.0) + i
			var cp := Vector2(24.0 + px * (float(theme["VIEW_W"]) - 48.0), py)
			host.draw_set_transform(cp, rot, Vector2.ONE)
			host.draw_rect(Rect2(-4, -2.5, 8, 5), Color(cc.r, cc.g, cc.b, clampf(1.0 - t / 4.0, 0.0, 1.0)))
			host.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	host._txt_c(str(info.get("title", "")), Rect2(0, 296, float(theme["VIEW_W"]), 52), 34, tcol.lightened(0.15), true)
	if str(info.get("sub", "")) != "":
		host._txt_c(str(info.get("sub", "")), Rect2(24, 346, float(theme["VIEW_W"]) - 48, 30), 16, theme["TEXT_DIM"])
	var rows: Array = info.get("rows", [])
	var y: float = 392.0
	if rows.size() > 0:
		var card := Rect2(40, y, float(theme["VIEW_W"]) - 80, 20 + rows.size() * 40)
		host._panel(card, theme["CARD"], 20, theme["LINE_STRONG"], 1.0, 10, 4)
		for i in rows.size():
			var ry: float = card.position.y + 10 + i * 40
			host._txt_r(str(rows[i][0]), card.end.x - 18, ry + 27, 16, theme["TEXT_DIM"], false, 260)
			host._txt_c(str(rows[i][1]), Rect2(card.position.x + 12, ry, 180, 40), 20, theme["TEXT"], true)
			if i < rows.size() - 1:
				host.draw_rect(Rect2(card.position.x + 16, ry + 40, card.size.x - 32, 1), theme["LINE"])
		y = card.end.y + 14.0
	if host.selected_game == "mastermind":
		var sy: float = maxf(y, 440.0)
		host._txt_c("کد مخفی", Rect2(0, sy, float(theme["VIEW_W"]), 24), 14, theme["TEXT_DIM"])
		var code_len: int = int(host.mm_code_len)
		var result_gap: float = minf(56.0, (float(theme["VIEW_W"]) - 56.0) / float(maxi(1, code_len)))
		if host.mm_secret.size() == code_len:
			for i in range(code_len):
				var mc: Color = theme["MM_COLORS"][host.mm_secret[i]]
				var sc := Vector2(float(theme["VIEW_W"]) * 0.5 + (float(i) - float(code_len - 1) * 0.5) * result_gap, sy + 54)
				host.draw_circle(sc, 22 if code_len <= 7 else 17, mc.darkened(0.3))
				host.draw_circle(sc + Vector2(0, -1), 19 if code_len <= 7 else 14, mc)
				host.draw_circle(sc + Vector2(-6, -8), 5 if code_len <= 7 else 4, Color(1, 1, 1, 0.35))
		else:
			host._txt_c("کد مخفی روی دستگاه میزبان نگهداری شد", Rect2(20, sy + 30, float(theme["VIEW_W"]) - 40, 40), 15, theme["TEXT_DIM"], true)
		y = sy + 96.0
	# Rating delta is read-only here; ScoringService remains the owner of rating values.
	var delta: int = int(host._result_delta)
	var dtxt: String
	var dcol: Color
	if delta == 0:
		dtxt = "امتیاز رتبه‌ای ثبت نشد"
		dcol = theme["TEXT_DIM"]
	elif result_draw and delta > 0:
		dtxt = "مساوی · +%s امتیاز لیگ" % host._fa(delta)
		dcol = theme["GREEN"]
	else:
		dtxt = ("+%s امتیاز لیگ" % host._fa(delta)) if delta > 0 else ("−%s امتیاز لیگ" % host._fa(absi(delta)))
		dcol = theme["GREEN"] if delta > 0 else theme["RED"]
	var cw: float = host._txt_w(dtxt, 17, true) + 44.0
	var dy: float = minf(y + 6.0, 604.0)
	var cr := Rect2((float(theme["VIEW_W"]) - cw) * 0.5, dy, cw, 40)
	var dp: float = host._ease_back((t - 0.4) / 0.4)
	if dp > 0.0:
		host._panel(cr.grow_individual(-(1.0 - dp) * cw * 0.25, 0, -(1.0 - dp) * cw * 0.25, 0), Color(dcol.r, dcol.g, dcol.b, 0.16), 20, dcol, 1.5)
		host._txt_c(dtxt, cr, 17, dcol, true)
		if delta != 0:
			host._txt_c("رتبه: " + host._fa(host.scoring_service.global_rating), Rect2(0, cr.end.y + 4, float(theme["VIEW_W"]), 22), 12, theme["TEXT_DIM"])


func render_popup(host, theme: Dictionary) -> void:
	host._scrim(0.58)
	var info: Dictionary = host._result_info()
	var won: bool = host._player_won_current()
	var result_draw: bool = host._result_draw
	var col: Color = theme["TEXT_DIM"] if result_draw else (theme["GREEN"] if won else theme["RED"])
	var panel := Rect2(28, 218, float(theme["VIEW_W"]) - 56, 508)
	host._panel(panel, Color(0.10, 0.13, 0.27), 26, Color(col.r, col.g, col.b, 0.58), 1.5, 22, 8)
	host._gloss(panel, 26, 0.04)
	var ic := Vector2(float(theme["VIEW_W"]) * 0.5, panel.position.y + 56)
	host.draw_circle(ic, 30, Color(col.r, col.g, col.b, 0.16))
	host._ring(ic, 30, Color(col.r, col.g, col.b, 0.64), 1.5)
	host._draw_icon("swap" if result_draw else ("trophy" if won else "flag"), ic, 27, col, 2.4)
	host._txt_c(str(info.get("title", "پایان بازی")), Rect2(panel.position.x + 14, panel.position.y + 96, panel.size.x - 28, 40), 26, col.lightened(0.12), true)
	var sub: String = str(info.get("sub", ""))
	if sub.is_empty():
		sub = "صفحه‌ی نهایی بازی پشت این پنجره حفظ شده است."
		host._wrap(sub, panel.position.x + 28, panel.position.y + 143, panel.size.x - 56, 14, theme["TEXT_DIM"], HORIZONTAL_ALIGNMENT_CENTER)
	var rows: Array = info.get("rows", [])
	var row_y: float = panel.position.y + 198
	for i in range(mini(rows.size(), 3)):
		var r := Rect2(panel.position.x + 24, row_y + i * 40, panel.size.x - 48, 34)
		host._panel(r, Color(1, 1, 1, 0.045), 10)
		host._txt_r(str(rows[i][0]), r.end.x - 10, r.position.y + 22, 12, theme["TEXT_DIM"], false, r.size.x * 0.62)
		host._txt_c(str(rows[i][1]), Rect2(r.position.x + 8, r.position.y, r.size.x * 0.36, r.size.y), 14, theme["TEXT"], true)
	var rating_note := ""
	var rating_delta: int = int(host._result_rating_delta)
	var game_rating_delta: int = int(host._result_game_rating_delta)
	if rating_delta != 0 or game_rating_delta != 0:
		rating_note = " · مهارت کلی %s%s / این بازی %s%s" % ["+" if rating_delta > 0 else ("−" if rating_delta < 0 else ""), host._fa(absi(rating_delta)), "+" if game_rating_delta > 0 else ("−" if game_rating_delta < 0 else ""), host._fa(absi(game_rating_delta))]
	var league_note: String = ""
	if int(host._result_delta) == 0 and rating_note.is_empty():
		league_note = "مسابقه‌ی دوستانه · امتیاز رتبه‌ای ثبت نشد"
	else:
		var delta: int = int(host._result_delta)
		league_note = "لیگ ماهانه %s%s%s" % ["+" if delta > 0 else ("−" if delta < 0 else ""), host._fa(absi(delta)), rating_note]
	host._txt_c(league_note, Rect2(panel.position.x + 12, panel.end.y - 76, panel.size.x - 24, 20), 10 if rating_note.length() > 20 else 12, theme["GREEN"] if int(host._result_delta) > 0 else (theme["RED"] if int(host._result_delta) < 0 else theme["TEXT_DIM"]), true)
	host._txt_c("صفحه‌ی نهایی پشت این پنجره حفظ شده است", Rect2(panel.position.x + 12, panel.end.y - 34, panel.size.x - 24, 20), 11, theme["TEXT_FAINT"], false)
