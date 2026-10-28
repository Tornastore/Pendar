extends RefCounted
const RankingServiceScript = preload("res://services/ranking_service.gd")
## Dashboard page presentation. State and score ownership remain in the main controller/services.

func build_buttons(host, theme: Dictionary) -> void:
	host._add_btn(Rect2(16, 16, 44, 44), "", host._open_dashboard_help, true, theme["TEXT"], "icon", "help", "dashboard_help")
	host._scroll_top = 312.0
	host._scroll_bottom = 868.0
	host._content_h = host.GAMES.size() * 66.0 + 16.0
	var tabs: Array = ["تمام‌دوران", "این هفته", "ماه جاری"]
	for i in range(3):
		var w: float = 156.0
		var x: float = float(theme["VIEW_W"]) - 16.0 - w - i * (w + 10.0)
		host._add_btn(Rect2(x, 256, w, 42), tabs[i], host._set_tab.bind(i), true, theme["ACCENT"], "seg_on" if i == host.dash_tab else "ghost", "", "tab_%d" % i)
	host._btns_nav()


func stat_points(host, game_id: String) -> int:
	var stats: Dictionary = host.scoring_service.game_stats.get(game_id, {})
	if host.dash_tab == 0:
		return int(stats.get("points", 0))
	if host.dash_tab == 2:
		return host.scoring_service.current_month_points(game_id)
	return host._points_in_period(game_id, 7)


func render(host, theme: Dictionary) -> void:
	var max_abs: int = 1
	for game in host.GAMES:
		max_abs = maxi(max_abs, absi(stat_points(host, str(game.id))))

	for i in range(host.GAMES.size()):
		var game: Dictionary = host.GAMES[i]
		var game_id: String = str(game.id)
		var stats: Dictionary = host.scoring_service.game_stats.get(game_id, {})
		var points: int = stat_points(host, game_id)
		var rect := Rect2(16, host._scroll_top + 8.0 + i * 66.0 - host.scroll_y, float(theme["VIEW_W"]) - 32.0, 58)
		if rect.end.y < host._scroll_top - 4.0 or rect.position.y > host._scroll_bottom + 4.0:
			continue

		var color: Color = game.icon_col
		host._panel(rect, theme["CARD"], 16, theme["LINE"], 1.0)
		host._panel(Rect2(rect.end.x - 8, rect.position.y + 12, 4, rect.size.y - 24), color, 2)
		host._txt_r(str(game.name), rect.end.x - 20, rect.position.y + 25, 16, theme["TEXT"], true, 190)

		var wins: int = int(stats.get("wins", 0))
		var losses: int = int(stats.get("losses", 0))
		var draws: int = int(stats.get("draws", 0))
		host._txt_r("%s برد · %s مساوی · %s باخت" % [host._fa(wins), host._fa(draws), host._fa(losses)], rect.end.x - 20, rect.position.y + 46, 11, theme["TEXT_DIM"], false, 190)

		var bar := Rect2(rect.position.x + 104, rect.position.y + 36, 116, 8)
		host._panel(bar, Color(1, 1, 1, 0.07), 4)
		var fraction: float = clampf(float(absi(points)) / float(max_abs), 0.0, 1.0)
		if fraction > 0.0:
			host._panel(Rect2(bar.position, Vector2(maxf(8.0, bar.size.x * fraction), 8)), theme["GREEN"] if points >= 0 else theme["RED"], 4)
		var point_text: String = ("+" if points > 0 else ("−" if points < 0 else "")) + host._fa(absi(points))
		host._txt_c(point_text, Rect2(rect.position.x + 8, rect.position.y + 6, 90, 26), 18, theme["GREEN"] if points > 0 else (theme["RED"] if points < 0 else theme["TEXT_DIM"]), true)

	# Fixed header and global score card stay outside the scrollable list.
	host.draw_rect(Rect2(0, 0, float(theme["VIEW_W"]), host._scroll_top - 4), theme["BAR"])
	host.draw_rect(Rect2(0, host._scroll_top - 5, float(theme["VIEW_W"]), 1), theme["LINE"])
	host._vgrad(Rect2(0, host._scroll_top - 4, float(theme["VIEW_W"]), 16), Color(theme["BAR"].r, theme["BAR"].g, theme["BAR"].b, 0.95), Color(theme["BAR"].r, theme["BAR"].g, theme["BAR"].b, 0.0))
	host._txt_c("آمار و امتیازات", Rect2(70, 10, float(theme["VIEW_W"]) - 140, 40), 24, theme["TEXT"], true)

	var win_loss_draw: Array = host._total_wins_losses()
	var total_matches: int = int(win_loss_draw[0]) + int(win_loss_draw[1]) + int(win_loss_draw[2])
	var win_rate: int = int(round(100.0 * float(win_loss_draw[0]) / float(maxi(1, total_matches)))) if total_matches > 0 else 0
	var card := Rect2(16, 58, float(theme["VIEW_W"]) - 32, 184)
	# This card shows permanent skill (MMR); the monthly league lives on the rankings page.
	var tier: Array = RankingServiceScript.tier_info(host.scoring_service.global_rating)
	var tier_color: Color = tier[1]
	host._panel(card, Color(0.15, 0.18, 0.34), 24, Color(tier_color.r, tier_color.g, tier_color.b, 0.5), 1.5, 12, 5)
	host._glow(Vector2(card.end.x - 90, card.position.y + 60), 120, Color(tier_color.r, tier_color.g, tier_color.b, 0.25))
	host._txt_r("رتبه‌ی مهارتی", card.end.x - 22, card.position.y + 34, 14, theme["TEXT_DIM"], true, 200)
	var level_info: Dictionary = host.scoring_service.level()
	host._txt_r("سطح %s · %s" % [host._fa(level_info["level"]), str(host._tier_info()[0])], card.position.x + 230, card.position.y + 34, 13, theme["TEXT"], true, 210)
	host._txt_r("بهترین رشته‌ی برد: %s" % host._fa(host.scoring_service.best_streak), card.position.x + 230, card.position.y + 58, 11, theme["TEXT_DIM"], false, 210)
	host._txt_r(host._fa(host.scoring_service.global_rating), card.end.x - 22, card.position.y + 90, 52, theme["TEXT"], true, 300)
	var tier_chip_width: float = host._txt_w(str(tier[0]), 14, true) + 30.0
	var tier_chip := Rect2(card.end.x - 22 - tier_chip_width, card.position.y + 102, tier_chip_width, 28)
	host._panel(tier_chip, Color(tier_color.r, tier_color.g, tier_color.b, 0.18), 14, tier_color, 1.0)
	host._txt_c(str(tier[0]), tier_chip, 14, tier_color.lightened(0.2), true)

	var summary_columns: Array = [["برد", host._fa(win_loss_draw[0]), theme["GREEN"]], ["باخت", host._fa(win_loss_draw[1]), theme["RED"]], ["درصد برد", host._fa(win_rate) + "٪", theme["ACCENT"]]]
	for i in range(3):
		var column_x: float = card.position.x + 20 + i * 100.0
		host._panel(Rect2(column_x, card.position.y + 134, 92, 40), Color(1, 1, 1, 0.05), 12)
		host._txt_c(str(summary_columns[i][1]), Rect2(column_x, card.position.y + 134, 92, 24), 17, summary_columns[i][2], true)
		host._txt_c(str(summary_columns[i][0]), Rect2(column_x, card.position.y + 154, 92, 18), 11, theme["TEXT_DIM"])
	host._draw_bottom_nav()
