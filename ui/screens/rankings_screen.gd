extends RefCounted
## Rankings page presentation. Ranking data and tier calculations remain in RankingService.

const RankingServiceScript = preload("res://services/ranking_service.gd")


func build_buttons(host, theme: Dictionary) -> void:
	host._add_btn(Rect2(16, 16, 44, 44), "", host._open_rankings_help, true, theme["TEXT"], "icon", "help", "rankings_help")
	host._scroll_top = 262.0
	host._scroll_bottom = 868.0
	host._content_h = host.GAMES.size() * 66.0 + 16.0
	host._btns_nav()


func render(host, theme: Dictionary) -> void:
	var rows: Array = RankingServiceScript.build_game_rows(host.GAMES, host.scoring_service.game_stats)
	var medals: Array = [Color(1.0, 0.80, 0.30), Color(0.80, 0.86, 0.94), Color(0.85, 0.55, 0.30)]
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var rect := Rect2(16, host._scroll_top + 8.0 + i * 66.0 - host.scroll_y, float(theme["VIEW_W"]) - 32.0, 58)
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
		host._txt_r(str(row.name), rect.end.x - 80, rect.position.y + 26, 16, theme["TEXT"], true, 190)
		host._txt_r("مهارت %s · برد %s · مساوی %s · باخت %s" % [host._fa(row.rating), host._fa(row.w), host._fa(row.d), host._fa(row.l)], rect.end.x - 80, rect.position.y + 47, 10, theme["TEXT_DIM"], false, 190)
		var points: int = int(row.pts)
		host._txt_c(("+" if points > 0 else ("−" if points < 0 else "")) + host._fa(absi(points)), Rect2(rect.position.x + 8, rect.position.y, 100, rect.size.y), 20, theme["GREEN"] if points > 0 else (theme["RED"] if points < 0 else theme["TEXT_DIM"]), true)

	host.draw_rect(Rect2(0, 0, float(theme["VIEW_W"]), host._scroll_top - 4), theme["BAR"])
	host.draw_rect(Rect2(0, host._scroll_top - 5, float(theme["VIEW_W"]), 1), theme["LINE"])
	host._vgrad(Rect2(0, host._scroll_top - 4, float(theme["VIEW_W"]), 16), Color(theme["BAR"].r, theme["BAR"].g, theme["BAR"].b, 0.95), Color(theme["BAR"].r, theme["BAR"].g, theme["BAR"].b, 0.0))
	host._txt_c("رتبه‌بندی", Rect2(70, 10, float(theme["VIEW_W"]) - 140, 40), 24, theme["TEXT"], true)

	var tier: Array = host._tier_info()
	var tier_color: Color = tier[1]
	var card := Rect2(16, 62, float(theme["VIEW_W"]) - 32, 180)
	host._panel(card, Color(0.15, 0.18, 0.34), 24, Color(tier_color.r, tier_color.g, tier_color.b, 0.55), 1.5, 12, 5)
	host._glow(Vector2(card.end.x - 80, card.position.y + 70), 130, Color(tier_color.r, tier_color.g, tier_color.b, 0.28))
	var crown_center := Vector2(card.end.x - 74, card.position.y + 78)
	host.draw_circle(crown_center, 44, Color(tier_color.r * 0.3, tier_color.g * 0.3, tier_color.b * 0.3))
	host._ring(crown_center, 44, tier_color, 3.0)
	host._draw_icon("crown", crown_center, 44, tier_color, 2.0)
	host._txt_r(str(tier[0]), card.end.x - 140, card.position.y + 70, 30, theme["TEXT"], true, 240)
	host._txt_r("امتیاز: " + host._fa(host.scoring_service.global_rating), card.end.x - 140, card.position.y + 98, 15, theme["TEXT_DIM"], false, 240)

	var lower_bound: int = int(tier[2])
	var upper_bound: int = int(tier[3])
	var fraction: float = 1.0 if upper_bound <= lower_bound else clampf(float(host.scoring_service.global_rating - lower_bound) / float(upper_bound - lower_bound), 0.0, 1.0)
	var progress_bar := Rect2(card.position.x + 20, card.end.y - 46, card.size.x - 40, 12)
	host._panel(progress_bar, Color(1, 1, 1, 0.08), 6)
	host._panel(Rect2(progress_bar.position, Vector2(maxf(12.0, progress_bar.size.x * fraction), 12)), tier_color, 6)
	var note: String = "به بالاترین رتبه مهارتی رسیده‌اید" if upper_bound <= lower_bound else "تا رتبه مهارتی بعد: " + host._fa(upper_bound - host.scoring_service.global_rating)
	host._txt_c(note, Rect2(card.position.x, card.end.y - 28, card.size.x, 22), 11, theme["TEXT_DIM"])

	var month_points: int = host.scoring_service.current_month_points()
	var season_tier: Array = RankingServiceScript.season_tier_info(month_points)
	host._txt_r("لیگ این ماه", card.position.x + 20, card.position.y + 40, 12, theme["TEXT_DIM"], true, 150)
	host._txt_r(str(season_tier[0]), card.position.x + 20, card.position.y + 66, 18, season_tier[1], true, 160)
	host._txt_r("امتیاز فصل: " + host._fa(month_points), card.position.x + 20, card.position.y + 92, 12, theme["TEXT_DIM"], false, 160)
	host._txt_r("تمام‌دوران: " + host._fa(host.scoring_service.global_lifetime_points), card.position.x + 20, card.position.y + 116, 11, theme["TEXT_DIM"], false, 160)
	host._draw_bottom_nav()
