extends RefCounted
## Online and lobby screen presenter.
## It reads connection/lobby state from the controller and builds views only.
## Matchmaking, transport, seat assignment and state transitions remain in main.gd.

func online_extra(host) -> float:
	var rows: int = int(ceil(float(host.NET_GAMES.size()) / 3.0))
	var end_y: float = 156.0 + (rows - 1) * 44.0 + 38.0
	return maxf(0.0, end_y - 254.0)

func build_online_buttons(host, theme: Dictionary) -> void:
	var web_build: bool = OS.has_feature("web")
	host._add_btn(Rect2(16, 16, 44, 44), "", host._open_online_help, true, theme["TEXT"], "icon", "help", "online_help")
	host._scroll_top = 76.0
	host._scroll_bottom = 868.0
	host._content_h = 0.0
	var i: int = 0
	for id in host.NET_GAMES:
		var col: int = i % 3
		var row: int = int(i / 3)
		var w: float = 156.0
		var x: float = theme["VIEW_W"] - 16.0 - w - col * (w + 10.0)
		var y: float = 156.0 + row * 44.0
		var nm: String = str(host._game_info(id).name)
		host._add_btn(Rect2(x, y, w, 38), nm, host._pick_online_game.bind(id), true, host._game_info(id).icon_col, "seg_on" if id == host.online_game else "ghost", "", "og_" + id)
		i += 1
	var ex: float = online_extra(host)
	if host.online_searching:
		host._add_btn(Rect2(24, 292 + ex, 492, 84), "لغو انتظار برای حریف", host._cancel_online_search, true, theme["RED"], "option", "close", "o_cancel_queue", "در صورت لغو، از صف بازی خارج می‌شوید")
	else:
		host._add_btn(Rect2(24, 292 + ex, 492, 84), "جستجوی هم‌بازی آنلاین", host._quick_match_search, not host._online_server_url().is_empty(), theme["PINK"], "option", "globe", "به صف بازی انتخاب‌شده می‌پیوندید و با اولین بازیکن همان بازی جفت می‌شوید")
		if host._online_server_url().is_empty():
			host._last_btn().hint = "پس از میزبانی سرور آنلاین، نشانی WSS را در project.godot تنظیم کنید."
	if host.username_editing:
		host._add_btn(Rect2(374, 91, 140, 40), "ثبت نام", host._save_online_username, true, theme["GREEN"], "solid", "check", "o_username_save")
	else:
		host._add_btn(Rect2(24, 91, 118, 40), "ویرایش نام", host._edit_online_username, true, theme["BLUE"], "soft", "user", "o_username")
	host._add_btn(Rect2(24, 488 + ex, 492, 84), "اتصال مستقیم با IP (فقط APK/Desktop)", host._go_ip_entry, not web_build, theme["ACCENT"], "option", "keypad", "o_lan", "اتصال مستقیم روی شبکه محلی")
	if web_build:
		host._last_btn().hint = "در مرورگر از جستجوی هم‌بازی با WebSocket استفاده کنید. اتصال ENet/IP فقط در نسخه نصب‌شدنی است."
	host._btns_nav()

func render_online(host, theme: Dictionary) -> void:
	host._draw_topbar("بازی آنلاین", "انتخاب بازی و جفت‌سازی خودکار با بازیکن منتظر")
	var profile := Rect2(16, 82, theme["VIEW_W"] - 32, 56)
	host._panel(profile, theme["CARD"], 16, theme["LINE_STRONG"], 1.0)
	if host.username_editing:
		host._txt_r("نام کاربری", theme["VIEW_W"] - 22, 113, 12, theme["TEXT_DIM"], true, 100)
	else:
		host._txt_r("نام کاربری", theme["VIEW_W"] - 22, 113, 12, theme["TEXT_DIM"], true, 100)
		host._txt_r(host.online_username, theme["VIEW_W"] - 138, 113, 15, theme["TEXT"], true, 190)
	host._txt_r("۱. بازی را انتخاب کنید", theme["VIEW_W"] - 24, 138, 15, theme["TEXT_DIM"], true, 300)
	var ex: float = online_extra(host)
	host._txt_r("۲. جستجوی حریف", theme["VIEW_W"] - 24, 280 + ex, 15, theme["TEXT_DIM"], true, 300)
	var note := Rect2(24, 592 + ex, 492, 134)
	host._panel(note, Color(0.38, 0.62, 1.0, 0.10), 18, Color(0.38, 0.62, 1.0, 0.35), 1.0)
	host._draw_icon("info", Vector2(note.end.x - 28, note.position.y + 30), 22, theme["BLUE"], 2.0)
	var status_text: String = host.online_status
	if host.online_searching:
		status_text = "در صف انتظار برای «%s» هستید؛ با ورود نفر بعدی بازی شروع می‌شود." % str(host._game_info(host.online_game).get("name", host.online_game))
	elif host.ws_match_active:
		status_text = "متصل به %s در بازی %s" % [host.opponent_name, str(host._game_info(host.selected_game).get("name", host.selected_game))]
	elif host._online_server_url().is_empty():
		status_text = "برای فعال‌شدن صف آنلاین، سرور WebSocket را میزبانی و network/matchmaking_url را تنظیم کنید."
	elif status_text.is_empty():
		status_text = "بازیکنان بر اساس بازی انتخاب‌شده جفت می‌شوند؛ نام کاربری و ایموجی‌ها به حریف نمایش داده می‌شود."
	host._wrap(status_text, note.position.x + 18, note.position.y + 32, note.size.x - 36, 14, theme["TEXT"], HORIZONTAL_ALIGNMENT_RIGHT)
	host._wrap("اتصال مستقیم IP در APK حفظ شده است؛ نسخه‌ی وب برای بازی آنلاین از WSS استفاده می‌کند.", note.position.x + 18, note.position.y + 86, note.size.x - 36, 13, theme["TEXT_DIM"], HORIZONTAL_ALIGNMENT_RIGHT)
	host._draw_bottom_nav()

# ---------------- LOBBY ----------------

func build_lobby_buttons(host, theme: Dictionary) -> void:
	host._back_btn()
	host._add_btn(Rect2(16, 16, 44, 44), "", host._open_rules, true, theme["TEXT"], "icon", "help", "help")
	if host.is_host:
		var can_start: bool = host.connected_players >= 2 and not (host.selected_game == "quoridor" and host.connected_players == 3)
		host._add_btn(Rect2(40, 706, theme["VIEW_W"] - 80, 62), "شروع بازی", host._start_network_game, can_start, theme["GREEN"], "solid", "play", "start")
		host._last_btn().hint = "کوریدور با ۲ یا ۴ بازیکن شروع می‌شود؛ سایر بازی‌ها طبق ظرفیت خود شروع می‌شوند."
		var ips: Array = host.host_ips
		for j in ips.size():
			var y: float = 250.0 + 82.0 + j * 42.0
			host._add_btn(Rect2(30, y - 2, 40, 36), "", host._copy_ip.bind(str(ips[j])), true, theme["ACCENT"], "icon", "copy", "copy_%d" % j)
	host._add_btn(Rect2(40, 782, theme["VIEW_W"] - 80, 54), "ترک لابی", host._request_leave_lobby, true, theme["RED"], "soft", "door", "leave")

func _draw_seat(host, theme: Dictionary, r: Rect2, seat: int, present: bool, me: bool, col: Color) -> void:
	var live: bool = present
	host._panel(r, theme["CARD"], 20, Color(col.r, col.g, col.b, 0.7 if live else 0.2), 1.5 if live else 1.0, 12, 5)
	var ac := Vector2(r.end.x - 42, r.position.y + 46)
	if live:
		host.draw_circle(ac, 28, Color(col.r, col.g, col.b, 0.25))
		host.draw_circle(ac, 22, col)
		host._draw_icon("user", ac, 22, host._lum_text(col), 2.0)
	else:
		host.draw_circle(ac, 26, Color(1, 1, 1, 0.05))
		for k in 3:
			var ph: float = fmod(host._time * 1.6 + k * 0.33, 1.0)
			host.draw_circle(ac + Vector2((k - 1) * 12, 0), 3.0 + 2.0 * sin(ph * PI), Color(1, 1, 1, 0.25 + 0.35 * sin(ph * PI)))
	var title: String = "بازیکن " + host._fa(seat + 1)
	host._txt_r(title, r.end.x - 82, r.position.y + 40, 17, theme["TEXT"] if live else theme["TEXT_DIM"], true, 140)
	var sub: String = "متصل" if live else "در انتظار…"
	host._txt_r(sub, r.end.x - 82, r.position.y + 64, 13, theme["GREEN"] if live else theme["TEXT_FAINT"], false, 140)
	if me:
		var tag := Rect2(r.position.x + 12, r.position.y + 12, 46, 22)
		host._panel(tag, Color(theme["ACCENT"].r, theme["ACCENT"].g, theme["ACCENT"].b, 0.2), 11, theme["ACCENT"], 1.0)
		host._txt_c("شما", tag, 12, theme["ACCENT"], true)
	var role: String = "میزبان" if seat == 0 else "مهمان"
	host._txt_c(role, Rect2(r.position.x, r.end.y - 30, r.size.x, 24), 12, theme["TEXT_DIM"])

func _draw_lobby_slot(host, theme: Dictionary, r: Rect2, seat: int, present: bool, me: bool) -> void:
	var colors: Array[Color] = [theme["BLUE"], theme["ACCENT"], theme["GREEN"], Color(1.0, 0.78, 0.30)]
	var col: Color = colors[seat % colors.size()]
	host._panel(r, theme["CARD"] if present else Color(0.10, 0.12, 0.23), 14, Color(col.r, col.g, col.b, 0.72 if present else 0.22), 1.2)
	host.draw_circle(Vector2(r.position.x + 24, r.get_center().y), 12, col if present else Color(1, 1, 1, 0.08))
	host._draw_icon("user" if present else "clock", Vector2(r.position.x + 24, r.get_center().y), 13, theme["TEXT"] if present else theme["TEXT_FAINT"], 1.7)
	var shown_name: String = "بازیکن %s" % host._fa(seat + 1)
	for roster_entry in host.online_player_roster:
		if int(roster_entry.get("seat", -1)) == seat:
			shown_name = str(roster_entry.get("username", shown_name))
			break
	host._txt_r(shown_name, r.end.x - 12, r.position.y + 30, 14, theme["TEXT"] if present else theme["TEXT_DIM"], true, r.size.x - 56)
	host._txt_r(("شما · متصل" if me else "متصل") if present else "در انتظار…", r.end.x - 12, r.position.y + 52, 11, theme["GREEN"] if present else theme["TEXT_FAINT"], false, r.size.x - 56)

func render_lobby(host, theme: Dictionary) -> void:
	var info: Dictionary = host._game_info(host.selected_game)
	var col: Color = info.get("icon_col", theme["ACCENT"])
	host._draw_topbar("لابی بازی", str(info.get("name", "")))
	var seat0_present: bool = true
	var seat1_present: bool = host.connected_players >= 2 if host.is_host else host._client_connected
	if host.selected_game == "uno":
		# UNO supports up to ten seats. Two columns keep the complete lobby visible.
		for seat in range(mini(host.max_players_for_game, 10)):
			var col_idx: int = seat % 2
			var row_idx: int = int(seat / 2)
			var seat_rect := Rect2(16.0 + float(col_idx) * 254.0, 92.0 + float(row_idx) * 58.0, 246.0, 54.0)
			var present: bool = false
			if host.is_host:
				present = seat == 0 or seat in host.peer_to_seat.values()
			else:
				present = seat == host.local_seat
			for roster_entry in host.online_player_roster:
				if int(roster_entry.get("seat", -1)) == seat:
					present = bool(roster_entry.get("connected", present))
					break
			_draw_lobby_slot(host, theme, seat_rect, seat, present, seat == host.local_seat)
	elif host.max_players_for_game >= 4:
		for seat in range(4):
			var col_idx: int = seat % 2
			var row_idx: int = int(seat / 2)
			var seat_rect := Rect2(16.0 + float(col_idx) * 254.0, 96.0 + float(row_idx) * 94.0, 246.0, 84.0)
			var present: bool = false
			if host.is_host:
				present = seat in host.peer_to_seat.values()
			else:
				present = seat == host.local_seat
				for roster_entry in host.online_player_roster:
					if int(roster_entry.get("seat", -1)) == seat:
						present = bool(roster_entry.get("connected", present))
						break
			_draw_lobby_slot(host, theme, seat_rect, seat, present, seat == host.local_seat)
	else:
		_draw_seat(host, theme, Rect2(theme["VIEW_W"] - 16 - 238, 100, 238, 124), 0, seat0_present if host.is_host else host._client_connected, host.local_seat == 0, theme["BLUE"])
		_draw_seat(host, theme, Rect2(16, 100, 238, 124), 1, seat1_present, host.local_seat == 1, theme["ACCENT"])
	if host.is_host:
		var ips: Array = host.host_ips
		var card_y: float = (390.0 if host.selected_game == "uno" else (316.0 if host.max_players_for_game >= 4 else 250.0))
		var card := Rect2(16, card_y, theme["VIEW_W"] - 32, 112 + maxi(ips.size(), 1) * 42)
		host._panel(card, theme["CARD"], 20, theme["LINE_STRONG"], 1.0, 12, 5)
		host._txt_r("آدرس شما برای دوست", card.end.x - 18, card.position.y + 34, 15, theme["TEXT_DIM"], true, 300)
		if host.online_room_code != "":
			var cr := Rect2(card.position.x + 16, card.position.y + 14, 130, 32)
			host._panel(cr, Color(theme["ACCENT"].r, theme["ACCENT"].g, theme["ACCENT"].b, 0.14), 16, theme["ACCENT"], 1.0)
			host._txt_c("کد " + host._fa(host.online_room_code), cr, 14, theme["ACCENT"], true)
		if ips.size() > 0:
			for j in ips.size():
				var y: float = card.position.y + 82.0 + j * 42.0
				host._txt_r(str(ips[j]), card.end.x - 18, y + 24, 26, theme["ACCENT"], true, 300)
		else:
			host._txt_r("IP پیدا نشد — از تنظیمات وای‌فای ببینید", card.end.x - 18, card.position.y + 92, 14, theme["TEXT_DIM"], false, 400)
		host._txt_r("پورت: " + host._fa(host.PORT), card.end.x - 18, card.end.y - 16, 13, theme["TEXT_DIM"], false, 200)
		if host.max_players_for_game >= 4:
			host._txt_r("هر بازیکن IP بالا را وارد کند · ظرفیت %s نفر" % host._fa(host.max_players_for_game), card.end.x - 18, card.position.y + 58, 12, theme["TEXT_DIM"], false, 420)
		var need: int = host.max_players_for_game - host.connected_players
		var msg: String = ("منتظر %s بازیکن دیگر…" % host._fa(need)) if need > 0 else "همه آماده‌اند — بازی را شروع کنید"
		host._txt_c(msg, Rect2(0, 650, theme["VIEW_W"], 36), 17, theme["TEXT_DIM"] if need > 0 else theme["GREEN"], true)
	else:
		var card2 := Rect2(16, 250, theme["VIEW_W"] - 32, 190)
		host._panel(card2, theme["CARD"], 20, theme["LINE_STRONG"], 1.0, 12, 5)
		var cc := Vector2(theme["VIEW_W"] * 0.5, card2.position.y + 66)
		if not host._client_connected:
			host.draw_arc(cc, 26, host._time * 4.0, host._time * 4.0 + PI * 1.4, 24, theme["ACCENT"], 4.0, true)
			host._txt_c("در حال اتصال به " + host.join_ip + " …", Rect2(card2.position.x, card2.position.y + 108, card2.size.x, 28), 17, theme["TEXT"], true)
			host._txt_c("هر دو گوشی باید روی یک وای‌فای باشند", Rect2(card2.position.x, card2.position.y + 140, card2.size.x, 24), 13, theme["TEXT_DIM"])
		else:
			host.draw_circle(cc, 28, Color(theme["GREEN"].r, theme["GREEN"].g, theme["GREEN"].b, 0.2))
			host._draw_icon("check", cc, 30, theme["GREEN"], 3.4)
			host._txt_c("متصل شدید", Rect2(card2.position.x, card2.position.y + 108, card2.size.x, 28), 18, theme["GREEN"], true)
			host._txt_c("منتظر شروع بازی توسط میزبان" + ".".repeat(1 + int(host._time * 2.0) % 3), Rect2(card2.position.x, card2.position.y + 140, card2.size.x, 24), 14, theme["TEXT_DIM"])

# ---------------- IP ENTRY ----------------
