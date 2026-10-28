extends RefCounted
## Result presentation for finished games and the compact in-game result popup.
## Result calculation, score persistence, state transitions and actions stay in main.gd.
## The popup only reads host._last_score_result (produced by ScoringService) and never writes scores.
const RankingServiceScript = preload("res://services/ranking_service.gd")
const LeagueScript = preload("res://services/league_service.gd")


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
		# Large rosters (Mafia and UNO) must not push the score summary or action
		# buttons off-screen. Keep every player visible in a compact two-column grid.
		var compact_grid: bool = rows.size() > 6
		var rows_per_column: int = int(ceil(float(rows.size()) / 2.0)) if compact_grid else rows.size()
		var row_height: float = 29.0 if compact_grid else 40.0
		var card_height: float = 16.0 + float(rows_per_column) * row_height
		var card := Rect2(40, y, float(theme["VIEW_W"]) - 80, card_height)
		host._panel(card, theme["CARD"], 20, theme["LINE_STRONG"], 1.0, 10, 4)
		for i in rows.size():
			var column: int = int(i / rows_per_column) if compact_grid else 0
			var row_in_column: int = i % rows_per_column if compact_grid else i
			var cell_width: float = card.size.x * 0.5 if compact_grid else card.size.x
			var cell_x: float = card.position.x + float(column) * cell_width
			var ry: float = card.position.y + 8.0 + float(row_in_column) * row_height
			if compact_grid:
				var cell := Rect2(cell_x + 4.0, ry, cell_width - 8.0, row_height - 3.0)
				if row_in_column > 0:
					host.draw_rect(Rect2(cell.position.x + 6.0, cell.position.y, cell.size.x - 12.0, 1.0), theme["LINE"])
				var label_width: float = minf(78.0, cell.size.x * 0.38)
				host._txt_r(str(rows[i][0]), cell.end.x - 6.0, cell.position.y + 18.0, 12, theme["TEXT_DIM"], false, label_width)
				var value_rect := Rect2(cell.position.x + 4.0, cell.position.y, cell.size.x - label_width - 18.0, cell.size.y)
				var value_text: String = str(rows[i][1])
				host._txt_c(value_text, value_rect, host._fit_size(value_text, value_rect.size.x - 4.0, 12, true), theme["TEXT"], true)
			else:
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


func _signed(_host, v: int) -> String:
	return RankingServiceScript.signed(v)


func _tint(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


# Capsule chips flow right-to-left and wrap; returns the y after the last line.
func _draw_chips(host, theme: Dictionary, chips: Array, right_x: float, left_x: float, y: float, max_lines: int) -> float:
	var x: float = right_x
	var line := 0
	for chip in chips:
		var text: String = "%s %s" % [str(chip.get("label", "")), str(chip.get("text", ""))]
		var f: float = float(chip.get("factor", 1.0))
		var cc: Color = theme["GREEN"] if f > 1.04 else (theme["RED"] if f < 0.96 else theme["TEXT_DIM"])
		var w: float = host._txt_w(text, 11, true) + 18.0
		if x - w < left_x:
			line += 1
			if line >= max_lines:
				break
			x = right_x
		var r := Rect2(x - w, y + line * 27.0, w, 23)
		host._panel(r, _tint(cc, 0.14), 11, _tint(cc, 0.55), 1.0)
		host._txt_c(text, r, 11, cc.lightened(0.25), true)
		x -= w + 6.0
	return y + float(mini(line + 1, max_lines)) * 27.0


func render_popup(host, theme: Dictionary) -> void:
	host._scrim(0.62)
	var info: Dictionary = host._result_info()
	var won: bool = host._player_won_current()
	var result_draw: bool = host._result_draw
	var col: Color = theme["TEXT_DIM"] if result_draw else (theme["GREEN"] if won else theme["RED"])
	var res: Dictionary = host._last_score_result
	var recorded: bool = bool(res.get("recorded", false))
	var t: float = host._time - host._result_t0
	var panel := Rect2(24, 96, float(theme["VIEW_W"]) - 48, 760)
	var left_x: float = panel.position.x + 18.0
	var right_x: float = panel.end.x - 18.0
	var inner_w: float = panel.size.x - 36.0
	host._panel(panel, Color(0.10, 0.13, 0.27), 26, _tint(col, 0.58), 1.5, 22, 8)
	host._gloss(panel, 26, 0.04)
	# --- header ---
	var ic := Vector2(float(theme["VIEW_W"]) * 0.5, panel.position.y + 48)
	var pop: float = host._ease_back(t / 0.45)
	host.draw_circle(ic, 30 * pop, _tint(col, 0.16))
	host._ring(ic, 30 * pop, _tint(col, 0.64), 1.5)
	host._draw_icon("swap" if result_draw else ("trophy" if won else "flag"), ic, 27 * pop, col, 2.4)
	host._txt_c(str(info.get("title", "پایان بازی")), Rect2(panel.position.x + 14, panel.position.y + 86, panel.size.x - 28, 40), 26, col.lightened(0.12), true)
	var y: float = panel.position.y + 130.0
	var sub: String = str(info.get("sub", ""))
	if sub != "":
		host._txt_c(sub, Rect2(panel.position.x + 14, y - 2, panel.size.x - 28, 22), 13, theme["TEXT_DIM"])
		y += 24.0
	var rows: Array = info.get("rows", [])
	for i in range(mini(rows.size(), 3)):
		var r := Rect2(left_x, y + i * 35.0, inner_w, 31)
		host._panel(r, Color(1, 1, 1, 0.045), 10)
		host._txt_r(str(rows[i][0]), r.end.x - 10, r.position.y + 21, 12, theme["TEXT_DIM"], false, r.size.x * 0.62)
		host._txt_c(str(rows[i][1]), Rect2(r.position.x + 8, r.position.y, r.size.x * 0.36, r.size.y), 14, theme["TEXT"], true)
	y += float(mini(rows.size(), 3)) * 35.0 + 8.0
	if not recorded:
		var note_rect := Rect2(left_x, y, inner_w, 46)
		host._panel(note_rect, Color(1, 1, 1, 0.05), 14)
		host._txt_c("مسابقه‌ی دوستانه · امتیاز رتبه‌ای ثبت نشد", note_rect, 14, theme["TEXT_DIM"], true)
		host._txt_c("صفحه‌ی نهایی پشت این پنجره حفظ شده است", Rect2(panel.position.x + 12, panel.end.y - 30, panel.size.x - 24, 20), 11, theme["TEXT_FAINT"], false)
		return
	# --- league points block ---
	var delta: int = int(res.get("delta", 0))
	var game_delta: int = int(res.get("game_delta", 0))
	var dcol: Color = theme["GREEN"] if delta > 0 else (theme["RED"] if delta < 0 else theme["TEXT_DIM"])
	var count_t: float = clampf((t - 0.25) / 0.7, 0.0, 1.0)
	var shown: int = int(round(float(delta) * host._ease_out(count_t)))
	var chips: Array = res.get("chips", [])
	var chip_lines: int = clampi(int(ceil(float(chips.size()) / 3.0)), 1, 2) if chips.size() > 0 else 0
	var lp_h: float = 70.0 + float(chip_lines) * 27.0
	var lp_rect := Rect2(left_x, y, inner_w, lp_h)
	host._panel(lp_rect, _tint(dcol, 0.10), 18, _tint(dcol, 0.45), 1.2)
	host._txt_c((_signed(host, shown) if delta != 0 else "۰") + " امتیاز لیگ", Rect2(lp_rect.position.x, lp_rect.position.y + 4, lp_rect.size.x, 38), 28, dcol.lightened(0.15), true)
	var sub_line: String = "این بازی %s" % _signed(host, game_delta)
	if int(res.get("rating_delta", 0)) != 0 or int(res.get("game_rating_delta", 0)) != 0:
		sub_line += " · رتبه‌ی مهارتی %s (%s)" % [_signed(host, int(res.get("rating_delta", 0))), host._fa(int(res.get("rating", 0)))]
	host._txt_c(sub_line, Rect2(lp_rect.position.x + 8, lp_rect.position.y + 42, lp_rect.size.x - 16, 20), 12, theme["TEXT_DIM"])
	if chips.size() > 0:
		_draw_chips(host, theme, chips, lp_rect.end.x - 12, lp_rect.position.x + 12, lp_rect.position.y + 66, 2)
	y += lp_h + 10.0
	# --- league progress ---
	var tb: Dictionary = res.get("tier_before", {})
	var ta: Dictionary = res.get("tier_after", {})
	if not ta.is_empty():
		var tcol: Color = ta["col"]
		var lg_rect := Rect2(left_x, y, inner_w, 104)
		host._panel(lg_rect, Color(1, 1, 1, 0.045), 18, _tint(tcol, 0.4), 1.0)
		var bc := Vector2(lg_rect.end.x - 36, lg_rect.position.y + 34)
		host.draw_circle(bc, 22, Color(tcol.r * 0.3, tcol.g * 0.3, tcol.b * 0.3))
		host._ring(bc, 22, tcol, 2.5)
		host._draw_icon("crown", bc, 22, tcol, 1.8)
		host._txt_r("لیگ ماهانه", lg_rect.end.x - 70, lg_rect.position.y + 14, 10, theme["TEXT_FAINT"], false, 200)
		host._txt_r(str(ta["label"]), lg_rect.end.x - 70, lg_rect.position.y + 34, 20, theme["TEXT"], true, 200)
		host._txt_r("لقب: " + str(ta["title"]), lg_rect.end.x - 70, lg_rect.position.y + 54, 12, _tint(tcol.lightened(0.2), 1.0), true, 200)
		var gt: Dictionary = res.get("game_tier_after", {})
		if not gt.is_empty():
			host._txt_r("%s · %s" % [str(host._game_info(str(res.get("game_id", ""))).get("name", "")), str(gt["label"])], lg_rect.position.x + 14 + 190, lg_rect.position.y + 30, 12, theme["TEXT_DIM"], false, 190)
		var same_div: bool = int(tb.get("league", -1)) == int(ta["league"]) and int(tb.get("division", -1)) == int(ta["division"])
		var from_f: float = float(tb.get("progress", 0.0)) if same_div else (0.0 if int(ta["points"]) >= int(tb.get("points", 0)) else 1.0)
		var frac: float = lerpf(from_f, float(ta["progress"]), host._ease_out(clampf((t - 0.5) / 0.8, 0.0, 1.0)))
		var bar := Rect2(lg_rect.position.x + 16, lg_rect.position.y + 66, lg_rect.size.x - 32, 12)
		host._panel(bar, Color(1, 1, 1, 0.08), 6)
		host._panel(Rect2(bar.position, Vector2(maxf(12.0, bar.size.x * frac), 12)), tcol, 6)
		var hint: String
		if bool(ta.get("is_top", false)):
			hint = "در بالاترین لیگ هستی"
		else:
			var win_value: int = int(host.scoring_service.preview_points(str(res.get("game_id", "")), str(res.get("mode", "cpu")), int(res.get("difficulty", 3)), host._opp_match_rating, host._match_player_count()).get("win_applied", 0))
			hint = RankingServiceScript.progress_hint(ta, win_value) if win_value > 0 else "%s امتیاز تا %s" % [host._fa(int(ta.get("to_next", 0))), str(ta.get("next_label", ""))]
		host._txt_c(hint, Rect2(lg_rect.position.x + 8, lg_rect.position.y + 80, lg_rect.size.x - 16, 20), 12, theme["TEXT_DIM"])
		if bool(res.get("league_up", false)) or bool(res.get("division_up", false)):
			var up_text: String = ("ارتقا به لیگ %s!" % str(ta["name"])) if bool(res.get("league_up", false)) else ("ارتقا به %s" % str(ta["label"]))
			var pulse: float = 0.6 + 0.4 * sin(host._time * 6.0)
			var banner := Rect2(lg_rect.position.x + 14, lg_rect.position.y - 14, 170, 26)
			host._panel(banner, Color(theme["ACCENT"].r, theme["ACCENT"].g, theme["ACCENT"].b, 0.25 + 0.1 * pulse), 13, theme["ACCENT"], 1.5)
			host._txt_c(up_text, banner, host._fit_size(up_text, 156.0, 13, true), theme["ACCENT"].lightened(0.3), true)
		y += 114.0
	# --- XP / level / streak ---
	var xr := Rect2(left_x, y, inner_w, 46)
	host._panel(xr, Color(1, 1, 1, 0.045), 14)
	var li: Dictionary = res.get("level_info", {})
	host._txt_r("%s تجربه" % _signed(host, int(res.get("xp_gain", 0))), xr.end.x - 12, xr.position.y + 20, 14, theme["BLUE"], true, 130)
	host._txt_r("سطح %s" % host._fa(int(res.get("level_after", 1))), xr.end.x - 12, xr.position.y + 38, 11, theme["TEXT_DIM"], false, 130)
	var xbar := Rect2(xr.position.x + 150, xr.position.y + 28, xr.size.x - 300, 8)
	host._panel(xbar, Color(1, 1, 1, 0.08), 4)
	host._panel(Rect2(xbar.position, Vector2(maxf(8.0, xbar.size.x * float(li.get("progress", 0.0))), 8)), theme["BLUE"], 4)
	if bool(res.get("level_up", false)):
		host._txt_c("سطح جدید!", Rect2(xbar.position.x, xr.position.y + 4, xbar.size.x, 20), 12, theme["ACCENT"], true)
	var streak: int = int(res.get("win_streak", 0))
	if streak >= 2:
		host._draw_icon("star", Vector2(xr.position.x + 26, xr.position.y + 23), 18, theme["ACCENT"], 1.8)
		host._txt_c("رشته‌ی برد %s" % host._fa(streak), Rect2(xr.position.x + 40, xr.position.y + 4, 100, 38), 12, theme["ACCENT"], true)
	y += 54.0
	# --- notices (priority order, max 4 lines) ---
	var notes: Array = []
	var cap: String = str(res.get("cap_reason", ""))
	if cap == "practice":
		notes.append([theme["ACCENT"], "سقف امتیاز تمرین پر شد؛ برای لیگ‌های بالاتر با انسان آنلاین بازی کن."])
	elif cap == "gate" and not ta.is_empty() and int(ta["league"]) + 1 < LeagueScript.LEAGUES.size():
		notes.append([theme["ACCENT"], "ورود به لیگ بعد نیاز به رتبه‌ی مهارتی %s دارد." % host._fa(LeagueScript.gate_rating_for_league(int(ta["league"]) + 1))])
	for q in res.get("quests_completed", []):
		notes.append([theme["GREEN"], "ماموریت کامل شد: %s (%s تجربه، %s امتیاز)" % [str(q["title"]), _signed(host, int(q["xp"])), _signed(host, int(q["lp"]))]])
	for b in res.get("badges_unlocked", []):
		notes.append([theme["PINK"], "نشان جدید: " + str(b["name"])])
	if bool(res.get("mastery_up", false)):
		notes.append([theme["ACCENT"], "تسلط در این بازی به ستاره‌ی %s رسید" % host._fa(int(res.get("mastery_after", 1)))])
	if bool(res.get("first_win_of_game", false)):
		notes.append([theme["BLUE"], "اولین برد در این بازی ثبت شد (%s تجربه)" % _signed(host, 40)])
	var rv: Dictionary = res.get("rival", {})
	if not rv.is_empty():
		notes.append([theme["TEXT_DIM"], "رکورد شما با «%s»: %s برد · %s مساوی · %s باخت" % [str(rv["name"]), host._fa(int(rv["w"])), host._fa(int(rv["d"])), host._fa(int(rv["l"]))]])
	for i in range(mini(notes.size(), 4)):
		var line_y: float = y + i * 22.0
		if line_y > panel.end.y - 160.0:
			break
		host._txt_c(str(notes[i][1]), Rect2(left_x, line_y, inner_w, 20), host._fit_size(str(notes[i][1]), inner_w - 8.0, 12, true), notes[i][0], true)
	host._txt_c("صفحه‌ی نهایی پشت این پنجره حفظ شده است", Rect2(panel.position.x + 12, panel.end.y - 26, panel.size.x - 24, 20), 11, theme["TEXT_FAINT"], false)
