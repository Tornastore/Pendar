extends RefCounted
## Pause overlay presenter. It reads host state and delegates actions back to the controller.
## It does not own game state, confirmation actions, music settings, or navigation.

func layout(host, theme: Dictionary) -> Rect2:
	var rows: int = 6 if host.vs_cpu else 5
	var height: float = 104.0 + rows * 62.0 + 24.0 + (28.0 if not host.vs_cpu else 0.0)
	return Rect2(36.0, (float(theme["VIEW_H"]) - height) * 0.5, float(theme["VIEW_W"]) - 72.0, height)


func build_buttons(host, theme: Dictionary) -> void:
	var panel: Rect2 = layout(host, theme)
	var y: float = panel.position.y + 92.0
	var x: float = panel.position.x + 20.0
	var width: float = panel.size.x - 40.0

	host._add_ov_btn(Rect2(x, y, width, 54), "ادامه بازی", host._close_pause, theme["GREEN"], "solid", "play", "p_resume")
	y += 62.0
	host._add_ov_btn(Rect2(x, y, width, 54), "راهنمای بازی", host._open_rules, theme["BLUE"], "soft", "help", "p_rules")
	y += 62.0
	host._add_ov_btn(Rect2(x, y, width, 54), host._music_label(), host._toggle_music, theme["ACCENT"], "soft", host._music_icon(), "p_music")
	y += 62.0
	if host.vs_cpu:
		host._add_ov_btn(Rect2(x, y, width, 54), "بازی جدید", host._confirm_restart, theme["ACCENT"], "soft", "restart", "p_new")
		y += 62.0
	host._add_ov_btn(Rect2(x, y, width, 54), "تسلیم", host._confirm_resign, theme["RED"], "soft", "flag", "p_resign")
	y += 62.0
	host._add_ov_btn(Rect2(x, y, width, 54), "خروج به منوی اصلی", host._confirm_exit_game, theme["TEXT_DIM"], "ghost", "door", "p_exit")


func render(host, theme: Dictionary) -> void:
	host._scrim()
	var panel: Rect2 = layout(host, theme)
	var progress: float = host._ease_out(host._ov_t / 0.22)
	var rect := Rect2(panel.position + Vector2(0, (1.0 - progress) * 30.0), panel.size)
	host._panel(rect, Color(0.11, 0.14, 0.28), 28, theme["LINE_STRONG"], 1.0, 24, 10)
	host._gloss(rect, 28, 0.04)
	host._txt_c("توقف بازی", Rect2(rect.position.x, rect.position.y + 18, rect.size.x, 36), 24, theme["TEXT"], true)
	host._txt_c(str(host._game_info(host.selected_game).get("name", "")), Rect2(rect.position.x, rect.position.y + 54, rect.size.x, 24), 14, theme["TEXT_DIM"])
	if not host.vs_cpu:
		host._txt_c("بازی برای حریف متوقف نمی‌شود", Rect2(rect.position.x, rect.end.y - 38, rect.size.x, 24), 12, theme["ACCENT"])
