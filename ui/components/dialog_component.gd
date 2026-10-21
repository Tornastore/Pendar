extends RefCounted
## Generic confirmation-dialog presentation. Callback execution and state cleanup stay in main.gd.

func layout(host, theme: Dictionary) -> Dictionary:
	var body: String = str(host.dialog.get("body", ""))
	var body_height: float = host._wrap_h(body, 360.0, 15)
	var panel_height: float = 150.0 + body_height + 24.0 + 54.0 + 12.0 + 50.0 + 24.0
	return {"rect": Rect2(40.0, (float(theme["VIEW_H"]) - panel_height) * 0.5, float(theme["VIEW_W"]) - 80.0, panel_height), "bh": body_height}


func build_buttons(host, theme: Dictionary) -> void:
	var layout_data: Dictionary = layout(host, theme)
	var rect: Rect2 = layout_data["rect"]
	var danger: bool = bool(host.dialog.get("danger", true))
	var button_y: float = rect.end.y - 24.0 - 50.0 - 12.0 - 54.0
	host._add_ov_btn(Rect2(rect.position.x + 24, button_y, rect.size.x - 48, 54), str(host.dialog.get("confirm", "تأیید")), host._dialog_confirm, theme["RED"] if danger else theme["GREEN"], "solid", "", "d_confirm")
	host._add_ov_btn(Rect2(rect.position.x + 24, button_y + 66, rect.size.x - 48, 50), str(host.dialog.get("cancel", "انصراف")), host._go_back, theme["TEXT_DIM"], "ghost", "", "d_cancel")


func render(host, theme: Dictionary) -> void:
	host._scrim(0.74)
	var layout_data: Dictionary = layout(host, theme)
	var base_rect: Rect2 = layout_data["rect"]
	var progress: float = host._ease_back(host._ov_t / 0.28)
	var pop_scale: float = 0.88 + 0.12 * progress
	var rect: Rect2 = Rect2(base_rect.get_center() - base_rect.size * 0.5 * pop_scale, base_rect.size * pop_scale)
	var danger: bool = bool(host.dialog.get("danger", true))
	var color: Color = theme["RED"] if danger else theme["GREEN"]
	host._panel(rect, Color(0.11, 0.14, 0.28), 28, Color(color.r, color.g, color.b, 0.5), 1.5, 26, 10)
	var icon_center := Vector2(float(theme["VIEW_W"]) * 0.5, rect.position.y + 54)
	host.draw_circle(icon_center, 34, Color(color.r, color.g, color.b, 0.18))
	host._ring(icon_center, 34, Color(color.r, color.g, color.b, 0.6), 1.5)
	host._draw_icon(str(host.dialog.get("icon", "warning")), icon_center, 32, color.lightened(0.15), 2.6)
	host._txt_c(str(host.dialog.get("title", "")), Rect2(rect.position.x, rect.position.y + 96, rect.size.x, 40), 23, theme["TEXT"], true)
	host._wrap(str(host.dialog.get("body", "")), rect.position.x + 40, rect.position.y + 150, rect.size.x - 80, 15, theme["TEXT_DIM"], HORIZONTAL_ALIGNMENT_CENTER)
