extends RefCounted
## Rankings page presentation (league hero card + 3 tabs). Ranking data and tier calculations remain in RankingService /
## LeagueService; this presenter only reads host.scoring_service and never mutates scores or navigation state.

const RankingServiceScript = preload("res://services/ranking_service.gd")
const LeagueScript = preload("res://services/league_service.gd")
const QuestScript = preload("res://services/quest_service.gd")
const TextWrapScript = preload("res://ui/text_wrap.gd")

const HERO := Rect2(16, 58, 508, 196)
const ROW_H := 66.0
const QUEST_H := 84.0
const BADGE_H := 96.0
const TIPS: Array[String] = [
	"بازی با سختی بالاتر و حریف قوی‌تر امتیاز بیشتری می‌دهد.",
	"چند برد پشت‌سرهم ضریب امتیاز را تا ۴۰٪ بالا می‌برد.",
	"اولین برد هر روز ۵۰٪ امتیاز اضافه دارد.",
	"بعد از ۳ باخت پشت‌سرهم، باخت بعدی نصف امتیاز کم می‌کند.",
	"هر بازی لیگ و رتبه‌ی مهارتی جداگانه دارد؛ حریف هم‌سطح هر بازی جدا پیدا می‌شود.",
	"لیگی که به آن رسیده‌ای تا پایان فصل از دست نمی‌رود.",
	"امتیاز تمرین با CPU تا لیگ طلا می‌رسد؛ بالاتر از آن فقط با انسان.",
]


func build_buttons(host, theme: Dictionary) -> void:
	host._add_btn(Rect2(16, 16, 44, 44), "", host._open_rankings_help, true, theme["TEXT"], "icon", "help", "rankings_help")
	host._scroll_top = 310.0
	host._scroll_bottom = 868.0
	host._content_h = _content_height(host)
	var done: int = 0
	for q in host.scoring_service.quests_daily:
		if bool(q.get("done", false)):
			done += 1
	var tabs: Array = ["لیگ و بازی‌ها", "ماموریت‌ها %s/%s" % [host._fa(done), host._fa(host.scoring_service.quests_daily.size())], "نشان‌ها"]
	for i in range(3):
		var w: float = 164.0
		var x: float = float(theme["VIEW_W"]) - 16.0 - w - i * (w + 8.0)
		host._add_btn(Rect2(x, 262, w, 38), tabs[i], host._set_rank_tab.bind(i), true, theme["ACCENT"], "seg_on" if i == host.rank_tab else "ghost", "", "rtab_%d" % i)
	host._btns_nav()


func _content_height(host) -> float:
	match host.rank_tab:
		1:
			return 30.0 + host.scoring_service.quests_daily.size() * QUEST_H + 36.0 + host.scoring_service.quests_weekly.size() * QUEST_H + 24.0
		2:
			var rows: int = int(ceil(float(QuestScript.BADGES.size()) / 2.0))
			return 30.0 + rows * BADGE_H + 40.0 + maxf(1.0, float(host.scoring_service.season_history.size())) * 62.0 + 24.0
	return 70.0 + host.GAMES.size() * ROW_H + 16.0


func _tint(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


func _signed(_host, v: int) -> String:
	return RankingServiceScript.signed(v)


func render(host, theme: Dictionary) -> void:
	match host.rank_tab:
		1: _render_quests(host, theme)
		2: _render_badges(host, theme)
		_: _render_games(host, theme)
	# Fixed header covers the scrolling content.
	host.draw_rect(Rect2(0, 0, float(theme["VIEW_W"]), host._scroll_top - 4), theme["BAR"])
	host.draw_rect(Rect2(0, host._scroll_top - 5, float(theme["VIEW_W"]), 1), theme["LINE"])
	host._vgrad(Rect2(0, host._scroll_top - 4, float(theme["VIEW_W"]), 16), Color(theme["BAR"].r, theme["BAR"].g, theme["BAR"].b, 0.95), Color(theme["BAR"].r, theme["BAR"].g, theme["BAR"].b, 0.0))
	host._txt_c("رتبه‌بندی", Rect2(70, 10, float(theme["VIEW_W"]) - 140, 40), 24, theme["TEXT"], true)
	_render_hero(host, theme)
	host._draw_bottom_nav()


func _render_hero(host, theme: Dictionary) -> void:
	var svc = host.scoring_service
	var tier: Dictionary = svc.global_tier()
	var tc: Color = tier["col"]
	var card := HERO
	host._panel(card, Color(0.15, 0.18, 0.34), 24, _tint(tc, 0.55), 1.5, 12, 5)
	host._glow(Vector2(card.end.x - 74, card.position.y + 70), 130, _tint(tc, 0.28))
	var cc := Vector2(card.end.x - 66, card.position.y + 66)
	host.draw_circle(cc, 42, Color(tc.r * 0.3, tc.g * 0.3, tc.b * 0.3))
	host._ring(cc, 42, tc, 3.0)
	host._draw_icon("crown", cc, 42, tc, 2.0)
	host._txt_r(str(tier["label"]), card.end.x - 122, card.position.y + 52, 30, theme["TEXT"], true, 200)
	host._txt_r("لقب: " + str(tier["title"]), card.end.x - 122, card.position.y + 76, 14, tc.lightened(0.2), true, 200)
	host._txt_r("%s امتیاز فصل" % host._fa(svc.global_season_points), card.end.x - 122, card.position.y + 100, 13, theme["TEXT_DIM"], false, 200)
	var lx: float = card.position.x + 196.0
	host._txt_r(svc.season_label(), lx, card.position.y + 34, 13, theme["TEXT"], true, 176)
	var left_days: int = svc.season_days_left()
	host._txt_r("امروز آخرین روز فصل است" if left_days <= 0 else "%s روز تا پایان فصل" % host._fa(left_days), lx, card.position.y + 55, 11, theme["TEXT_DIM"], false, 176)
	var lv: Dictionary = svc.level()
	host._txt_r("سطح %s · %s/%s تجربه" % [host._fa(lv["level"]), host._fa(lv["into"]), host._fa(lv["need"])], lx, card.position.y + 82, 11, theme["TEXT_DIM"], false, 176)
	host._txt_r("مهارت %s · %s" % [host._fa(svc.global_rating), str(svc.skill_tier()["name"])], lx, card.position.y + 102, 11, theme["TEXT_DIM"], false, 176)
	if svc.win_streak >= 2:
		host._txt_r("رشته‌ی برد %s" % host._fa(svc.win_streak), lx, card.position.y + 122, 11, theme["ACCENT"], true, 176)
	var bar := Rect2(card.position.x + 20, card.end.y - 48, card.size.x - 40, 12)
	host._panel(bar, Color(1, 1, 1, 0.08), 6)
	host._panel(Rect2(bar.position, Vector2(maxf(12.0, bar.size.x * float(tier["progress"])), 12)), tc, 6)
	var win_value: int = int(svc.preview_points("chess", "human_online", 3).get("win_applied", 20))
	host._txt_c(RankingServiceScript.progress_hint(tier, maxi(1, win_value)), Rect2(card.position.x, card.end.y - 30, card.size.x, 22), 12, theme["TEXT_DIM"])


func _next_step_note(host, theme: Dictionary) -> Array:
	var svc = host.scoring_service
	var tier: Dictionary = svc.global_tier()
	if not bool(tier["is_top"]):
		var nxt: int = int(tier["league"]) + 1
		var gate: int = LeagueScript.gate_rating_for_league(nxt)
		var cap: int = LeagueScript.gate_cap_points(svc.global_rating)
		if svc.global_season_points >= cap - 20 and gate > svc.global_rating:
			return [theme["ACCENT"], "ورود به لیگ %s نیاز به رتبه‌ی مهارتی %s دارد (الان %s). با حریف انسانی هم‌سطح بازی کن." % [str(LeagueScript.LEAGUES[nxt]["name"]), host._fa(gate), host._fa(svc.global_rating)]]
		if svc.global_season_points >= LeagueScript.PRACTICE_CEILING_GLOBAL - 40:
			return [theme["ACCENT"], "امتیاز تمرین با CPU تا لیگ طلا ۱ است؛ برای ادامه با انسان آنلاین بازی کن."]
	var day_index: int = int(LeagueScript.jalali_from_unix(svc.now())["d"])
	return [theme["BLUE"], "نکته: " + TIPS[day_index % TIPS.size()]]


func _render_games(host, theme: Dictionary) -> void:
	var svc = host.scoring_service
	var rows: Array = RankingServiceScript.build_game_rows(host.GAMES, svc.game_stats)
	var medals: Array = [Color(1.0, 0.80, 0.30), Color(0.80, 0.86, 0.94), Color(0.85, 0.55, 0.30)]
	var note: Array = _next_step_note(host, theme)
	var nrect := Rect2(16, host._scroll_top + 6.0 - host.scroll_y, float(theme["VIEW_W"]) - 32.0, 56)
	if nrect.end.y > host._scroll_top - 4.0:
		host._panel(nrect, _tint(note[0], 0.10), 16, _tint(note[0], 0.4), 1.0)
		var note_text: String = TextWrapScript.wrap(host, str(note[1]), nrect.size.x - 32.0, 12, false, 2)
		var note_y: float = nrect.position.y + (24.0 if TextWrapScript.line_count(note_text) == 1 else 20.0)
		host._wrap(note_text, nrect.position.x + 14, note_y, nrect.size.x - 28, 12, theme["TEXT"], HORIZONTAL_ALIGNMENT_RIGHT)
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var rect := Rect2(16, host._scroll_top + 70.0 + i * ROW_H - host.scroll_y, float(theme["VIEW_W"]) - 32.0, 58)
		if rect.end.y < host._scroll_top - 4.0 or rect.position.y > host._scroll_bottom + 4.0:
			continue
		var has_medal: bool = i < 3 and int(row.pts) > 0
		host._panel(rect, theme["CARD"], 16, medals[i] if has_medal else theme["LINE"], 1.5 if has_medal else 1.0)
		var badge_center := Vector2(rect.end.x - 32, rect.get_center().y)
		if has_medal:
			host.draw_circle(badge_center, 18, medals[i])
			host._txt_c(host._fa(i + 1), Rect2(badge_center.x - 18, badge_center.y - 18, 36, 36), 17, Color(0.1, 0.1, 0.16), true)
		else:
			host.draw_circle(badge_center, 18, Color(1, 1, 1, 0.06))
			host._txt_c(host._fa(i + 1), Rect2(badge_center.x - 18, badge_center.y - 18, 36, 36), 15, theme["TEXT_DIM"], true)
		host.draw_circle(Vector2(rect.end.x - 66, rect.get_center().y), 5, row.col)
		host._txt_r(str(row.name), rect.end.x - 80, rect.position.y + 24, 16, theme["TEXT"], true, 190)
		var mastery: Dictionary = row.mastery
		host._txt_r("مهارت %s · %s برد · %s باخت · تسلط %s" % [host._fa(row.rating), host._fa(row.w), host._fa(row.l), host._fa(mastery["stars"])], rect.end.x - 80, rect.position.y + 45, 10, theme["TEXT_DIM"], false, 200)
		# This game's own league capsule + progress.
		var gt: Dictionary = row.tier
		var gc: Color = gt["col"]
		var cap_w: float = host._txt_w(str(gt["label"]), 12, true) + 20.0
		var cap_r := Rect2(rect.position.x + 96, rect.position.y + 9, cap_w, 22)
		host._panel(cap_r, _tint(gc, 0.16), 11, _tint(gc, 0.65), 1.0)
		host._txt_c(str(gt["label"]), cap_r, 12, gc.lightened(0.25), true)
		var pbar := Rect2(rect.position.x + 96, rect.position.y + 38, 92, 6)
		host._panel(pbar, Color(1, 1, 1, 0.08), 3)
		host._panel(Rect2(pbar.position, Vector2(maxf(4.0, pbar.size.x * float(gt["progress"])), 6)), gc, 3)
		var points: int = int(row.pts)
		host._txt_c(host._fa(points), Rect2(rect.position.x + 6, rect.position.y + 6, 86, 30), 20, theme["GREEN"] if points > 0 else theme["TEXT_DIM"], true)
		host._txt_c("امتیاز بازی", Rect2(rect.position.x + 6, rect.position.y + 34, 86, 18), 10, theme["TEXT_FAINT"])


func _render_quests(host, theme: Dictionary) -> void:
	var svc = host.scoring_service
	var y: float = host._scroll_top + 4.0 - host.scroll_y
	host._txt_r("ماموریت‌های امروز", float(theme["VIEW_W"]) - 20, y + 20, 15, theme["TEXT"], true, 300)
	y += 30.0
	for q in svc.quests_daily:
		_draw_quest(host, theme, q, y)
		y += QUEST_H
	y += 6.0
	host._txt_r("ماموریت‌های این هفته", float(theme["VIEW_W"]) - 20, y + 20, 15, theme["TEXT"], true, 300)
	y += 30.0
	for q in svc.quests_weekly:
		_draw_quest(host, theme, q, y)
		y += QUEST_H
	host._txt_c("ماموریت‌ها برای همه‌ی بازیکنان یکسان است و تمام‌نشدنشان هیچ جریمه‌ای ندارد.", Rect2(20, y + 2, float(theme["VIEW_W"]) - 40, 20), 11, theme["TEXT_FAINT"])


func _draw_quest(host, theme: Dictionary, q: Dictionary, y: float) -> void:
	var rect := Rect2(16, y, float(theme["VIEW_W"]) - 32.0, 76)
	if rect.end.y < host._scroll_top - 4.0 or rect.position.y > host._scroll_bottom + 4.0:
		return
	var done: bool = bool(q.get("done", false))
	var col: Color = theme["GREEN"] if done else theme["ACCENT"]
	host._panel(rect, theme["CARD"], 16, _tint(col, 0.55 if done else 0.25), 1.2)
	host._txt_r(str(q["title"]), rect.end.x - 18, rect.position.y + 26, host._fit_size(str(q["title"]), 330.0, 15, true), theme["TEXT"], true, 340)
	var bar := Rect2(rect.position.x + 110, rect.position.y + 40, rect.size.x - 130, 9)
	host._panel(bar, Color(1, 1, 1, 0.08), 4)
	var frac: float = clampf(float(q["progress"]) / float(maxi(1, int(q["target"]))), 0.0, 1.0)
	host._panel(Rect2(bar.position, Vector2(maxf(frac * bar.size.x, 6.0 if frac > 0.0 else 0.0), 9)), col, 4)
	host._txt_c("%s / %s" % [host._fa(q["progress"]), host._fa(q["target"])], Rect2(rect.position.x + 14, rect.position.y + 30, 92, 24), 14, col, true)
	host._txt_r("پاداش: %s تجربه · %s امتیاز لیگ" % [_signed(host, int(q["xp"])), _signed(host, int(q["lp"]))], rect.end.x - 18, rect.position.y + 66, 11, theme["TEXT_DIM"], false, 300)
	if done:
		host._draw_icon("check", Vector2(rect.position.x + 36, rect.position.y + 62), 16, theme["GREEN"], 2.4)
		host._txt_c("انجام شد", Rect2(rect.position.x + 54, rect.position.y + 52, 80, 20), 11, theme["GREEN"], true)


func _render_badges(host, theme: Dictionary) -> void:
	var svc = host.scoring_service
	var y: float = host._scroll_top + 4.0 - host.scroll_y
	host._txt_r("نشان‌ها (%s از %s)" % [host._fa(svc.badges.size()), host._fa(QuestScript.BADGES.size())], float(theme["VIEW_W"]) - 20, y + 20, 15, theme["TEXT"], true, 300)
	y += 30.0
	var col_w: float = (float(theme["VIEW_W"]) - 40.0) * 0.5
	for i in range(QuestScript.BADGES.size()):
		var b: Dictionary = QuestScript.BADGES[i]
		var owned: bool = svc.badges.has(str(b["id"]))
		var column: int = i % 2
		var rect := Rect2(float(theme["VIEW_W"]) - 16.0 - col_w - column * (col_w + 8.0), y + int(i / 2) * BADGE_H, col_w, BADGE_H - 8.0)
		if rect.end.y < host._scroll_top - 4.0 or rect.position.y > host._scroll_bottom + 4.0:
			continue
		var col: Color = theme["ACCENT"] if owned else theme["TEXT_FAINT"]
		host._panel(rect, theme["CARD"], 14, _tint(col, 0.5 if owned else 0.2), 1.0)
		var c := Vector2(rect.end.x - 28, rect.position.y + 28)
		host.draw_circle(c, 18, _tint(col, 0.2))
		host._ring(c, 18, _tint(col, 0.8), 1.8)
		host._draw_icon("star" if owned else "lock", c, 16, col, 1.8)
		host._txt_r(str(b["name"]), rect.end.x - 54, rect.position.y + 24, host._fit_size(str(b["name"]), col_w - 70.0, 14, true), theme["TEXT"] if owned else theme["TEXT_DIM"], true, col_w - 60.0)
		host._wrap(TextWrapScript.wrap(host, str(b["desc"]), col_w - 24.0, 10, false, 2), rect.position.x + 10, rect.position.y + 60, col_w - 20.0, 10, theme["TEXT_DIM"] if owned else theme["TEXT_FAINT"], HORIZONTAL_ALIGNMENT_RIGHT)
	y += ceil(float(QuestScript.BADGES.size()) / 2.0) * BADGE_H + 8.0
	host._txt_r("تاریخچه‌ی فصل‌ها", float(theme["VIEW_W"]) - 20, y + 20, 15, theme["TEXT"], true, 300)
	y += 30.0
	if svc.season_history.is_empty():
		host._txt_c("هنوز فصل تمام‌شده‌ای وجود ندارد؛ جایزه‌ی هر فصل اینجا بایگانی می‌شود.", Rect2(20, y + 6, float(theme["VIEW_W"]) - 40, 24), 12, theme["TEXT_DIM"])
		return
	for i in range(svc.season_history.size()):
		var h: Dictionary = svc.season_history[i]
		var rect := Rect2(16, y + i * 62.0, float(theme["VIEW_W"]) - 32.0, 54)
		if rect.end.y < host._scroll_top - 4.0 or rect.position.y > host._scroll_bottom + 4.0:
			continue
		host._panel(rect, theme["CARD"], 14, theme["LINE"], 1.0)
		host._txt_r(str(h.get("label", "")), rect.end.x - 16, rect.position.y + 22, 15, theme["TEXT"], true, 260)
		host._txt_r("بالاترین لیگ %s · %s برد · %s باخت" % [str(h.get("peak_label", "")), host._fa(int(h.get("wins", 0))), host._fa(int(h.get("losses", 0)))], rect.end.x - 16, rect.position.y + 42, 11, theme["TEXT_DIM"], false, 300)
		host._txt_c(host._fa(int(h.get("points", 0))), Rect2(rect.position.x + 8, rect.position.y + 6, 90, 42), 20, theme["ACCENT"], true)
