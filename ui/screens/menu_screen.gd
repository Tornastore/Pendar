extends RefCounted
## Game catalog/menu presenter. Selection callbacks and filter state remain in main.gd.
## This module owns the menu layout and drawing, not application navigation or game state.

func filtered_games(host) -> Array:
	var result: Array = []
	for game in host.GAMES:
		if host.menu_filter == "all" or game.cat == host.menu_filter:
			result.append(game)
	return result


func tile_rect(host, index: int) -> Rect2:
	var column: int = index % 2
	var row: int = int(index / 2)
	var x: float = float(host.VIEW_W) - 16.0 - float(host.TILE_W) - column * (float(host.TILE_W) + float(host.TILE_GAP))
	var y: float = host._scroll_top + 14.0 + row * (float(host.TILE_H) + float(host.TILE_GAP))
	return Rect2(x, y, host.TILE_W, host.TILE_H)


func build_buttons(host, theme: Dictionary) -> void:
	host._scroll_top = 176.0
	host._scroll_bottom = 868.0
	var games: Array = filtered_games(host)
	var rows: int = int((games.size() + 1) / 2)
	host._content_h = 14.0 + rows * (float(host.TILE_H) + float(host.TILE_GAP)) + 16.0
	for index in games.size():
		var game_id: String = str(games[index].id)
		host._add_hit(tile_rect(host, index), host._select_game.bind(game_id), "game_" + game_id, true)
	host._add_btn(Rect2(16, 22, 44, 44), "", host._confirm_exit_app, true, theme["TEXT_DIM"], "icon", "power", "exit")
	host._add_btn(Rect2(214, 22, 44, 44), "", host._toggle_music, true, theme["ACCENT"] if host.scoring_service.music_on else theme["TEXT_DIM"], "icon", host._music_icon(), "music")
	host._add_btn(Rect2(16, 72, 104, 34), "راهنما", host._open_general_help, true, theme["BLUE"], "soft", "help", "menu_help")
	var quests_done: int = 0
	for q in host.scoring_service.quests_daily:
		if bool(q.get("done", false)):
			quests_done += 1
	var quests_total: int = host.scoring_service.quests_daily.size()
	var all_done: bool = quests_total > 0 and quests_done >= quests_total
	host._add_btn(Rect2(128, 72, 176, 34), "ماموریت امروز %s/%s" % [host._fa(quests_done), host._fa(quests_total)], host._open_quests, quests_total > 0, theme["GREEN"] if all_done else theme["ACCENT"], "soft", "star", "menu_quests")
	var x: float = float(theme["VIEW_W"]) - 16.0
	for key in ["all", "strategy", "cards", "classic"]:
		var label: String = theme["CATEGORY_LABELS"][key]
		var width: float = host._txt_w(label, 16, true) + 32.0
		x -= width
		host._add_btn(Rect2(x, 124, width, 38), label, host._set_filter.bind(key), true, theme["ACCENT"], "seg_on" if key == host.menu_filter else "ghost", "", "chip_" + key)
		x -= 8.0
	host._btns_nav()


func render(host, theme: Dictionary) -> void:
	var games: Array = filtered_games(host)
	for index in games.size():
		var rect: Rect2 = tile_rect(host, index)
		rect.position.y -= host.scroll_y
		if rect.end.y < host._scroll_top - 10.0 or rect.position.y > host._scroll_bottom + 10.0:
			continue
		render_game_tile(host, games[index], rect, host._press_active and host._press_id == "game_" + str(games[index].id), theme)
	host._draw_bar_top(170.0)
	# Keep the official logo inside the top utility strip. The old 166px square
	# overlapped the category filters and made their hit areas visually unclear.
	if host._brand_logo != null:
		var logo_size: float = minf(60.0, maxf(48.0, float(theme["VIEW_W"]) * 0.11))
		var logo_rect := Rect2(float(theme["VIEW_W"]) - logo_size - 12.0, 8.0, logo_size, logo_size)
		host.draw_texture_rect(host._brand_logo, logo_rect, false)
	var tier: Array = host._tier_info()
	var tier_color: Color = tier[1]
	var pill := Rect2(68, 26, 138, 36)
	host._panel(pill, Color(1, 1, 1, 0.06), 18, Color(tier_color.r, tier_color.g, tier_color.b, 0.5), 1.0)
	host.draw_circle(Vector2(pill.end.x - 18, pill.get_center().y), 7, tier_color)
	var pill_text: String = "%s · %s" % [str(host.scoring_service.global_tier()["title"]), tier[0]]
	host._txt_c(pill_text, Rect2(pill.position.x + 4, pill.position.y, pill.size.x - 36, pill.size.y), host._fit_size(pill_text, pill.size.x - 40.0, 14, true), theme["TEXT"], true)
	if games.is_empty():
		host._txt_c("بازی‌ای پیدا نشد", Rect2(0, 400, float(theme["VIEW_W"]), 40), 18, theme["TEXT_DIM"])
	if host._scroll_max() > 4.0 and host.scroll_y < host._scroll_max() - 4.0:
		var alpha: float = 0.55 + 0.25 * sin(host._time * 3.0)
		host._draw_icon("back", Vector2(float(theme["VIEW_W"]) * 0.5, 858), 14, Color(1, 1, 1, alpha * 0.7), 2.0)
	host._draw_bottom_nav()


# Each game has its own league: show it on the card (or "new" for games never played) so players see where to climb.
func _draw_league_chip(host, game_id: String, art: Rect2, theme: Dictionary) -> void:
	var stats: Dictionary = host.scoring_service.game_stats.get(game_id, {})
	var played: int = int(stats.get("wins", 0)) + int(stats.get("draws", 0)) + int(stats.get("losses", 0))
	var label: String = "جدید"
	var col: Color = theme["BLUE"]
	if played > 0:
		var gt: Dictionary = host.scoring_service.game_tier(game_id)
		label = str(gt["label"])
		col = gt["col"]
	var w: float = host._txt_w(label, 12, true) + 20.0
	var chip := Rect2(art.position.x + 8, art.end.y - 30, w, 22)
	host._panel(chip, Color(0, 0, 0, 0.5), 11, Color(col.r, col.g, col.b, 0.85), 1.0)
	host._txt_c(label, chip, 12, col.lightened(0.3), true)

func render_game_tile(host, game: Dictionary, rect: Rect2, pressed: bool, theme: Dictionary) -> void:
	var color: Color = game.icon_col
	if pressed:
		rect = rect.grow(-3)
	host._panel(rect, theme["CARD_H"] if pressed else theme["CARD"], 20, Color(color.r, color.g, color.b, 0.38), 1.5, 14, 6)
	var art := Rect2(rect.position + Vector2(10, 10), Vector2(rect.size.x - 20, 98))
	host._panel(art, Color(color.r * 0.30 + 0.035, color.g * 0.30 + 0.045, color.b * 0.30 + 0.09, 1.0), 14)
	host._draw_game_art(str(game.id), art, color)
	host._gloss(art, 14, 0.05)
	var player_label: String = str(game.get("players", "۲ نفر"))
	var chip_width: float = clampf(host._txt_w(player_label, 12, true) + 18.0, 58.0, 108.0)
	var chip := Rect2(art.position + Vector2(8, 8), Vector2(chip_width, 22))
	host._panel(chip, Color(0, 0, 0, 0.38), 11)
	host._txt_c(player_label, chip, host._fit_size(player_label, chip.size.x - 8.0, 12, true), theme["TEXT"], true)
	if game.net:
		host._draw_icon("wifi", chip.position + Vector2(chip.size.x + 14.0, 11), 14, Color(1, 1, 1, 0.75), 1.6)
	if game.beta:
		var beta_chip := Rect2(art.end.x - 70, art.position.y + 8, 62, 22)
		host._panel(beta_chip, Color(1.0, 0.72, 0.25, 0.22), 11, Color(1.0, 0.72, 0.25, 0.7), 1.0)
		host._txt_c("آزمایشی", beta_chip, 12, Color(1.0, 0.82, 0.45), true)
	var text_width: float = rect.size.x - 28.0
	var name: String = str(game.name)
	_draw_league_chip(host, str(game.id), art, theme)
	host._txt_r(name, rect.end.x - 14, art.end.y + 30, host._fit_size(name, text_width, 19, true), theme["TEXT"], true, text_width)
	host._txt_r(str(game.short), rect.end.x - 14, art.end.y + 52, 13, theme["TEXT_DIM"], false, text_width)
