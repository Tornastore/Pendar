extends RefCounted
## Rules/help overlay presenter. The main controller retains context navigation and close actions.

const UIContentScript = preload("res://core/ui_content.gd")
const RULES_PAGE_SIZE := 4
const CONN_HELP := [
	"بدون مودم: روی یک گوشی هات‌اسپات را روشن کنید و گوشی دوم را به وای‌فای همان هات‌اسپات وصل کنید. اینترنت لازم نیست.",
	"گوشی میزبان: وارد لابی شود و IP نمایش‌داده‌شده را به دوستش بدهد. (دکمه‌ی کپی کنار IP است.) IP هات‌اسپات معمولاً 192.168.43.1 است.",
	"گوشی مهمان: گزینه‌ی پیوستن را بزند و IP میزبان را کامل وارد کند. مثل 192.168.43.1",
	"اگر وای‌فای معمولی دارید، هر دو گوشی باید به همان وای‌فای وصل باشند. VPN را هم خاموش کنید.",
	"اگر IP کار نکرد، آن را از تنظیمات وای‌فای گوشی میزبان بخوانید. IP باید با 192.168 یا 10 یا 172 شروع شود.",
	"اگر «اتصال ناموفق بود» آمد، یعنی دو گوشی همدیگر را نمی‌بینند. از هات‌اسپات استفاده کنید یا گزینه‌ی AP/Client Isolation روتر را خاموش کنید.",
	"اگر «خطا در اتصال» همراه با یک کد آمد، آن کد را برای سازنده بفرستید.",
]


func lines(host) -> Array:
	if host._conn_help_active():
		return CONN_HELP
	match host.rules_context:
		"general": return UIContentScript.GENERAL_HELP
		"online": return UIContentScript.ONLINE_HELP
		"dashboard": return UIContentScript.DASHBOARD_HELP
		"rankings": return UIContentScript.RANKINGS_HELP
		_: return UIContentScript.RULES.get(host.selected_game, [])


func title(host) -> String:
	if host._conn_help_active():
		return "راهنمای اتصال"
	match host.rules_context:
		"general": return "راهنمای برنامه"
		"online": return "راهنمای بازی آنلاین"
		"dashboard": return "راهنمای آمار"
		"rankings": return "راهنمای رتبه‌بندی"
		_: return "راهنمای " + str(host._game_info(host.selected_game).get("name", "بازی"))


func page_count(host) -> int:
	return maxi(1, int(ceil(float(lines(host).size()) / float(RULES_PAGE_SIZE))))


func layout(host, theme: Dictionary) -> Dictionary:
	var all_lines: Array = lines(host)
	var pages: int = maxi(1, int(ceil(float(all_lines.size()) / float(RULES_PAGE_SIZE))))
	var page_index: int = clampi(host.rules_page, 0, pages - 1)
	var start_index: int = page_index * RULES_PAGE_SIZE
	var page_lines: Array = []
	for index in range(start_index, mini(start_index + RULES_PAGE_SIZE, all_lines.size())):
		page_lines.append(all_lines[index])
	var text_width: float = 392.0
	var total_height: float = 0.0
	var line_heights: Array = []
	for text in page_lines:
		var line_height: float = host._wrap_h(str(text), text_width, 15)
		line_heights.append(line_height)
		total_height += line_height + 16.0
	var footer_height: float = 132.0 if pages > 1 else 84.0
	var panel_height: float = minf(float(theme["VIEW_H"]) - 48.0, 96.0 + total_height + footer_height)
	var panel_y: float = maxf(24.0, (float(theme["VIEW_H"]) - panel_height) * 0.5)
	return {
		"rect": Rect2(24.0, panel_y, float(theme["VIEW_W"]) - 48.0, panel_height),
		"hs": line_heights,
		"tw": text_width,
		"lines": page_lines,
		"page": page_index,
		"pages": pages,
	}


func build_buttons(host, theme: Dictionary) -> void:
	var layout_data: Dictionary = layout(host, theme)
	var rect: Rect2 = layout_data["rect"]
	if int(layout_data["pages"]) > 1:
		var nav_y: float = rect.end.y - 122.0
		var page_index: int = int(layout_data["page"])
		host._add_ov_btn(Rect2(rect.position.x + 20, nav_y, 130, 42), "قبلی", host._rules_prev_page, theme["TEXT_DIM"], "ghost", "back", "r_prev", page_index > 0)
		host._add_ov_btn(Rect2(rect.end.x - 150, nav_y, 130, 42), "بعدی", host._rules_next_page, theme["ACCENT"], "soft", "next", "r_next", page_index < int(layout_data["pages"]) - 1)
	host._add_ov_btn(Rect2(rect.position.x + 24, rect.end.y - 64, rect.size.x - 48, 48), "متوجه شدم", host._close_rules, theme["GREEN"], "solid", "check", "r_ok")


func render(host, theme: Dictionary) -> void:
	host._scrim(0.70)
	var layout_data: Dictionary = layout(host, theme)
	var rect: Rect2 = layout_data["rect"]
	var color: Color = host._game_info(host.selected_game).get("icon_col", theme["ACCENT"])
	if host.rules_context != "game":
		color = theme["BLUE"] if host.rules_context == "online" or host.rules_context == "connection" else theme["ACCENT"]
	host._panel(rect, Color(0.11, 0.14, 0.28), 28, Color(color.r, color.g, color.b, 0.5), 1.5, 24, 10)
	host._gloss(rect, 28, 0.04)
	host._txt_c(title(host), Rect2(rect.position.x, rect.position.y + 18, rect.size.x, 40), 22, theme["TEXT"], true)
	host.draw_rect(Rect2(rect.position.x + 28, rect.position.y + 68, rect.size.x - 56, 1), theme["LINE"])
	var page_lines: Array = layout_data["lines"]
	var line_heights: Array = layout_data["hs"]
	var y: float = rect.position.y + 90.0
	for index in range(page_lines.size()):
		var line_height: float = line_heights[index]
		var dot_center := Vector2(rect.end.x - 40, y + 12)
		host.draw_circle(dot_center, 13, Color(color.r, color.g, color.b, 0.25))
		host._txt_c(host._fa(int(layout_data["page"]) * RULES_PAGE_SIZE + index + 1), Rect2(dot_center.x - 13, dot_center.y - 13, 26, 26), 13, color.lightened(0.35), true)
		host._wrap(str(page_lines[index]), rect.position.x + 24, y + 16, float(layout_data["tw"]), 15, theme["TEXT"], HORIZONTAL_ALIGNMENT_RIGHT)
		y += line_height + 16.0
	if int(layout_data["pages"]) > 1:
		host._txt_c("صفحه %s از %s" % [host._fa(int(layout_data["page"]) + 1), host._fa(int(layout_data["pages"]))], Rect2(rect.position.x + 154, rect.end.y - 122, rect.size.x - 308, 42), 13, theme["TEXT_DIM"], true)
