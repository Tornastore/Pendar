extends RefCounted
const RankingServiceScript = preload("res://services/ranking_service.gd")
## Game-mode screen presenter. Reads selection state from main.gd and creates UI controls.
## Difficulty changes, mode starts and navigation remain controller-owned callbacks.

func build_buttons(host, theme: Dictionary) -> void:
	var info: Dictionary = host._game_info(host.selected_game)
	var web_build: bool = OS.has_feature("web")
	# Godot Web does not support low-level ENet/UDP networking in browsers.
	var net: bool = info.get("net", false) and not web_build
	var online_net: bool = bool(info.get("net", false))
	var option_y: float = 346.0
	var difficulty_labels: Array[String] = ["خیلی آسان", "آسان", "متوسط", "سخت", "استاد", "استادتمام"]
	host._back_btn()
	host._add_btn(Rect2(16, 16, 44, 44), "", host._open_rules, true, theme["TEXT"], "icon", "help", "help")
	if host.selected_game == "mastermind":
		for i in range(6):
			var active: bool = host.mm_difficulty == i + 1
			var color: Color = theme["GREEN"] if active else theme["ACCENT"]
			host._add_btn(Rect2(8 + i * 84, 345, 80, 40), difficulty_labels[i], host._set_mastermind_difficulty.bind(i + 1), true, color, "seg_on" if active else "ghost", "", "mastermind_difficulty_%d" % (i + 1))
		option_y = 410.0
	elif host.selected_game == "quoridor":
		var qmod = host._game_modules["quoridor"]
		for i in range(6):
			var active: bool = int(qmod.quo_difficulty) == i + 1
			var color: Color = theme["GREEN"] if active else theme["ACCENT"]
			host._add_btn(Rect2(8 + i * 84, 345, 80, 40), difficulty_labels[i], host._set_quoridor_difficulty.bind(i + 1), true, color, "seg_on" if active else "ghost", "", "quo_difficulty_%d" % (i + 1))
		option_y = 410.0
	elif host.selected_game in ["othello", "othello12"]:
		for i in range(6):
			var active: bool = host.oth_difficulty == i + 1
			var color: Color = theme["GREEN"] if active else theme["ACCENT"]
			host._add_btn(Rect2(8 + i * 84, 345, 80, 40), difficulty_labels[i], host._set_othello_difficulty.bind(i + 1), true, color, "seg_on" if active else "ghost", "", "oth_difficulty_%d" % (i + 1))
		option_y = 410.0
	elif host.selected_game == "chess":
		for i in range(6):
			var active: bool = host.chess_difficulty == i + 1
			var color: Color = theme["GREEN"] if active else theme["ACCENT"]
			host._add_btn(Rect2(8 + i * 84, 345, 80, 40), difficulty_labels[i], host._set_chess_difficulty.bind(i + 1), true, color, "seg_on" if active else "ghost", "", "chess_difficulty_%d" % (i + 1))
		option_y = 410.0
	elif host.selected_game == "backgammon":
		for i in range(6):
			var active: bool = host.bg_difficulty == i + 1
			var color: Color = theme["GREEN"] if active else theme["ACCENT"]
			host._add_btn(Rect2(8 + i * 84, 345, 80, 40), difficulty_labels[i], host._set_backgammon_difficulty.bind(i + 1), true, color, "seg_on" if active else "ghost", "", "backgammon_difficulty_%d" % (i + 1))
		option_y = 410.0
	elif host.selected_game == "pentago":
		var pmod = host._game_modules["pentago"]
		for i in range(6):
			var active: bool = int(pmod.pent_difficulty) == i + 1
			var color: Color = theme["GREEN"] if active else theme["ACCENT"]
			host._add_btn(Rect2(8 + i * 84, 345, 80, 40), difficulty_labels[i], host._set_pentago_difficulty.bind(i + 1), true, color, "seg_on" if active else "ghost", "", "pentago_difficulty_%d" % (i + 1))
		option_y = 410.0
	elif host.selected_game == "domino":
		var dmod = host._game_modules["domino"]
		for i in range(6):
			var active: bool = int(dmod.dom_difficulty) == i + 1
			var color: Color = theme["GREEN"] if active else theme["ACCENT"]
			host._add_btn(Rect2(8 + i * 84, 345, 80, 40), difficulty_labels[i], host._set_domino_difficulty.bind(i + 1), true, color, "seg_on" if active else "ghost", "", "domino_difficulty_%d" % (i + 1))
		option_y = 410.0
	elif host.selected_game == "pasoor":
		var pasmod = host._game_modules["pasoor"]
		for i in range(6):
			var active: bool = int(pasmod.pas_difficulty) == i + 1
			var color: Color = theme["GREEN"] if active else theme["ACCENT"]
			host._add_btn(Rect2(8 + i * 84, 345, 80, 40), difficulty_labels[i], host._set_pasoor_difficulty.bind(i + 1), true, color, "seg_on" if active else "ghost", "", "pasoor_difficulty_%d" % (i + 1))
		option_y = 410.0
	elif host.selected_game == "hokm":
		var hmod = host._game_modules["hokm"]
		for i in range(6):
			var active: bool = int(hmod.hokm_difficulty) == i + 1
			var color: Color = theme["GREEN"] if active else theme["ACCENT"]
			host._add_btn(Rect2(8 + i * 84, 345, 80, 40), difficulty_labels[i], host._set_hokm_difficulty.bind(i + 1), true, color, "seg_on" if active else "ghost", "", "hokm_difficulty_%d" % (i + 1))
		option_y = 410.0
	elif host.selected_game == "gobblet":
		var gobmod = host._game_modules["gobblet"]
		for i in range(6):
			var active: bool = int(gobmod.gob_difficulty) == i + 1
			var color: Color = theme["GREEN"] if active else theme["ACCENT"]
			host._add_btn(Rect2(8 + i * 84, 345, 80, 40), difficulty_labels[i], host._set_gobblet_difficulty.bind(i + 1), true, color, "seg_on" if active else "ghost", "", "gobblet_difficulty_%d" % (i + 1))
		option_y = 410.0
	elif host.selected_game == "abalone":
		var abamod = host._game_modules["abalone"]
		for i in range(6):
			var active: bool = int(abamod.aba_difficulty) == i + 1
			var color: Color = theme["GREEN"] if active else theme["ACCENT"]
			host._add_btn(Rect2(8 + i * 84, 345, 80, 40), difficulty_labels[i], host._set_abalone_difficulty.bind(i + 1), true, color, "seg_on" if active else "ghost", "", "abalone_difficulty_%d" % (i + 1))
		option_y = 410.0
	elif host.selected_game == "blockace":
		var blkmod = host._game_modules["blockace"]
		for i in range(6):
			var active: bool = int(blkmod.blk_difficulty) == i + 1
			var color: Color = theme["GREEN"] if active else theme["ACCENT"]
			host._add_btn(Rect2(8 + i * 84, 345, 80, 40), difficulty_labels[i], host._set_blockace_difficulty.bind(i + 1), true, color, "seg_on" if active else "ghost", "", "blockace_difficulty_%d" % (i + 1))
		option_y = 410.0
	elif host.selected_game == "quarto":
		var qtomod = host._game_modules["quarto"]
		for i in range(6):
			var active: bool = int(qtomod.qto_difficulty) == i + 1
			var color: Color = theme["GREEN"] if active else theme["ACCENT"]
			host._add_btn(Rect2(8 + i * 84, 345, 80, 40), difficulty_labels[i], host._set_quarto_difficulty.bind(i + 1), true, color, "seg_on" if active else "ghost", "", "quarto_difficulty_%d" % (i + 1))
		option_y = 410.0
	elif host.selected_game == "connect4":
		var c4mod = host._game_modules["connect4"]
		for i in range(6):
			var active: bool = int(c4mod.c4_difficulty) == i + 1
			host._add_btn(Rect2(8 + i * 84, 345, 80, 40), difficulty_labels[i], host._set_connect4_difficulty.bind(i + 1), true, theme["GREEN"] if active else theme["ACCENT"], "seg_on" if active else "ghost", "", "c4_difficulty_%d" % (i + 1))
		option_y = 410.0
	elif host.selected_game == "jenga":
		var jmod = host._game_modules["jenga"]
		for i in range(6):
			var active: bool = int(jmod.jenga_difficulty) == i + 1
			host._add_btn(Rect2(8 + i * 84, 345, 80, 40), difficulty_labels[i], host._set_jenga_difficulty.bind(i + 1), true, theme["GREEN"] if active else theme["ACCENT"], "seg_on" if active else "ghost", "", "jenga_difficulty_%d" % (i + 1))
		for i in range(3):
			var count: int = i + 2
			var active_count: bool = int(jmod.jenga_player_count) == count
			host._add_btn(Rect2(54 + i * 146, 394, 138, 32), "%s نفر" % host._fa(count), host._set_jenga_player_count.bind(count), true, theme["GREEN"] if active_count else theme["ACCENT"], "seg_on" if active_count else "ghost", "", "jenga_players_%d" % count)
		option_y = 436.0
	elif host.selected_game == "mafia":
		var mfmod = host._game_modules["mafia"]
		for i in range(6):
			var active: bool = int(mfmod.mafia_difficulty) == i + 1
			host._add_btn(Rect2(8 + i * 84, 345, 80, 40), difficulty_labels[i], host._set_mafia_difficulty.bind(i + 1), true, theme["GREEN"] if active else theme["ACCENT"], "seg_on" if active else "ghost", "", "mafia_difficulty_%d" % (i + 1))
		for i in range(4):
			var count: int = [6, 8, 10, 12][i]
			var active_count: bool = int(mfmod.mafia_player_count) == count
			host._add_btn(Rect2(18 + i * 128, 394, 122, 32), "%s نفر" % host._fa(count), host._set_mafia_player_count.bind(count), true, theme["GREEN"] if active_count else theme["ACCENT"], "seg_on" if active_count else "ghost", "", "mafia_players_%d" % count)
		option_y = 436.0
	elif host.selected_game == "uno":
		var um = host._game_modules["uno"]
		for i in range(6):
			var active: bool = int(um.uno_difficulty) == i + 1
			var color: Color = theme["GREEN"] if active else theme["ACCENT"]
			host._add_btn(Rect2(8 + i * 84, 345, 80, 40), difficulty_labels[i], host._set_uno_difficulty.bind(i + 1), true, color, "seg_on" if active else "ghost", "", "uno_difficulty_%d" % (i + 1))
		for i in range(5):
			var count1: int = i + 2
			var active1: bool = um.uno_player_count == count1
			host._add_btn(Rect2(16 + i * 103, 394, 96, 32), "%s نفر" % host._fa(count1), host._set_uno_player_count.bind(count1), true, theme["GREEN"] if active1 else theme["ACCENT"], "seg_on" if active1 else "ghost", "", "uno_players_%d" % count1)
		for i in range(4):
			var count2: int = i + 7
			var active2: bool = um.uno_player_count == count2
			host._add_btn(Rect2(68 + i * 103, 431, 96, 32), "%s نفر" % host._fa(count2), host._set_uno_player_count.bind(count2), true, theme["GREEN"] if active2 else theme["ACCENT"], "seg_on" if active2 else "ghost", "", "uno_players_%d" % count2)
		option_y = 470.0
	if host.selected_game == "uno":
		host._add_btn(Rect2(24, option_y, 492, 54), "مسابقه با CPU · %s نفر" % host._fa(host._game_modules["uno"].uno_player_count), host._start_vs_cpu, true, theme["GREEN"], "option", "cpu", "m_cpu", "یک بازیکن و حریف‌های CPU تا ۱۰ نفر")
		host._add_btn(Rect2(24, option_y + 58, 492, 54), "میزبانی روی وای‌فای", host._start_host, net, theme["BLUE"], "option", "wifi", "m_host", "میزبانی UNO برای ۲ تا ۱۰ بازیکن")
		host._add_btn(Rect2(24, option_y + 116, 492, 54), "اتصال با IP", host._go_ip_entry, net, theme["ACCENT"], "option", "keypad", "m_join", "به لابی UNO بپیوندید")
		host._add_btn(Rect2(24, option_y + 174, 492, 54), "بازی آنلاین · صف انتظار", host._open_online_for_game, online_net, theme["PINK"], "option", "globe", "m_online", "جفت‌شدن با بازیکنان آنلاین UNO")
		return
	if host.selected_game == "jenga":
		host._add_btn(Rect2(24, option_y, 492, 54), "بازی با CPU · %s نفر" % host._fa(host._game_modules["jenga"].jenga_player_count), host._start_vs_cpu, true, theme["GREEN"], "option", "cpu", "m_cpu", "بازی شما در برابر حریف‌های رایانه‌ای")
		host._add_btn(Rect2(24, option_y + 58, 492, 54), "میزبانی روی وای‌فای", host._start_host, net, theme["BLUE"], "option", "wifi", "m_host", "میزبانی برای ۲ تا ۴ بازیکن")
		host._add_btn(Rect2(24, option_y + 116, 492, 54), "اتصال با IP", host._go_ip_entry, net, theme["ACCENT"], "option", "keypad", "m_join", "پیوستن به میزبان در شبکه محلی")
		host._add_btn(Rect2(24, option_y + 174, 492, 54), "بازی آنلاین · صف انتظار", host._open_online_for_game, online_net, theme["PINK"], "option", "globe", "m_online", "تطبیق آنلاین Jenga")
		return
	if host.selected_game == "mafia":
		host._add_btn(Rect2(24, option_y, 492, 54), "مافیا با CPU · %s نفر" % host._fa(host._game_modules["mafia"].mafia_player_count), host._start_vs_cpu, true, theme["GREEN"], "option", "cpu", "m_cpu", "یک انسان و بازیکنان CPU؛ سناریوی کلاسیک")
		host._add_btn(Rect2(24, option_y + 58, 492, 54), "میزبانی روی وای‌فای", host._start_host, net, theme["BLUE"], "option", "wifi", "m_host", "میزبانی مافیا برای ۶ تا ۱۲ بازیکن")
		host._add_btn(Rect2(24, option_y + 116, 492, 54), "اتصال با IP", host._go_ip_entry, net, theme["ACCENT"], "option", "keypad", "m_join", "پیوستن به میزبان در شبکه محلی")
		host._add_btn(Rect2(24, option_y + 174, 492, 54), "بازی آنلاین · صف انتظار", host._open_online_for_game, online_net, theme["PINK"], "option", "globe", "m_online", "تطبیق آنلاین مافیا؛ حداقل ۶ بازیکن")
		return
	if host.selected_game == "connect4":
		host._add_btn(Rect2(24, option_y, 492, 62), "بازی با CPU", host._start_vs_cpu, true, theme["GREEN"], "option", "cpu", "m_cpu", "هوش مصنوعی با ۶ درجه سختی")
		host._add_btn(Rect2(24, option_y + 66, 492, 62), "میزبانی روی وای‌فای", host._start_host, net, theme["BLUE"], "option", "wifi", "m_host", "بازی دونفره در شبکه محلی")
		host._add_btn(Rect2(24, option_y + 132, 492, 62), "اتصال با IP", host._go_ip_entry, net, theme["ACCENT"], "option", "keypad", "مقابل میزبان بازی کنید")
		host._add_btn(Rect2(24, option_y + 198, 492, 62), "بازی آنلاین · صف انتظار", host._open_online_for_game, online_net, theme["PINK"], "option", "globe", "صف انتظار آنلاین")
		return
	if host.selected_game == "quoridor":
		host._add_btn(Rect2(24, option_y, 492, 62), "بازی با CPU · دو نفره", host._start_vs_cpu, true, theme["GREEN"], "option", "cpu", "m_cpu", "شما در برابر یک CPU")
		host._add_btn(Rect2(24, option_y + 66, 492, 62), "چهارنفره · شما در برابر ۳ CPU", host._start_quoridor_vs_three_cpu, true, Color(0.35, 0.78, 0.62), "option", "users", "m_cpu3", "چهار مسیر، سه حریف کامپیوتری")
		host._add_btn(Rect2(24, option_y + 132, 492, 62), "میزبانی روی وای‌فای", host._start_host, net, theme["BLUE"], "option", "wifi", "m_host", "میزبان بازی دونفره یا چهارنفره")
		host._add_btn(Rect2(24, option_y + 198, 492, 62), "اتصال با IP", host._go_ip_entry, net, theme["ACCENT"], "option", "keypad", "m_join", "به بازی میزبان بپیوندید")
		host._add_btn(Rect2(24, option_y + 264, 492, 62), "بازی آنلاین", host._open_online_for_game, online_net, theme["PINK"], "option", "globe", "m_online", "صف انتظار آنلاین")
		host._add_btn(Rect2(24, option_y + 330, 492, 62), "چهارنفره روی یک دستگاه", host._start_quoridor_local_four_player, true, theme["ACCENT"], "option", "users", "m_local4", "چهار نفر، نوبتی روی یک صفحه")
		if web_build:
			host.buttons[host.buttons.size() - 3].hint = "نسخه وب برای اتصال مستقیم IP به WebSocket نیاز دارد."
			host.buttons[host.buttons.size() - 2].hint = "اتصال مستقیم IP در APK/Desktop فعال است."
			host.buttons[host.buttons.size() - 1].hint = "برای نسخه وب از صف انتظار و WebSocket استفاده کنید."
		return
	if host.selected_game == "mastermind":
		host._add_btn(Rect2(24, option_y, 492, 62), "بازی با CPU · حل یک کد", host._start_vs_cpu, true, theme["GREEN"], "option", "cpu", "m_cpu", "یک کد را حدس بزنید")
		host._add_btn(Rect2(24, option_y + 66, 492, 62), "مسابقه با ۳ CPU · چهار نفره", host._start_mastermind_vs_three_cpu, true, Color(0.35, 0.78, 0.62), "option", "users", "m_cpu3", "هر نفر مستقل حدس می‌زند؛ رتبه‌بندی زنده")
		host._add_btn(Rect2(24, option_y + 132, 492, 62), "میزبانی روی وای‌فای", host._start_host, net, theme["BLUE"], "option", "wifi", "m_host", "میزبان کد را نگه می‌دارد")
		host._add_btn(Rect2(24, option_y + 198, 492, 62), "اتصال با IP", host._go_ip_entry, net, theme["ACCENT"], "option", "keypad", "m_join", "به مسابقه LAN بپیوندید")
		host._add_btn(Rect2(24, option_y + 264, 492, 62), "بازی آنلاین", host._open_online_for_game, online_net, theme["PINK"], "option", "globe", "m_online", "صف انتظار آنلاین")
		if web_build:
			host.buttons[host.buttons.size() - 3].hint = "نسخه وب برای LAN مستقیم از WebSocket استفاده می‌کند."
			host.buttons[host.buttons.size() - 2].hint = "اتصال IP فقط در APK/Desktop فعال است."
			host.buttons[host.buttons.size() - 1].hint = "با صف انتظار آنلاین، خودکار حریف پیدا می‌کنید."
		return
	host._add_btn(Rect2(24, option_y, 492, 84), "بازی با کامپیوتر", host._start_vs_cpu, true, theme["GREEN"], "option", "cpu", "m_cpu", "تک‌نفره · بدون نیاز به اینترنت")
	var network_y: float = option_y + 98.0
	host._add_btn(Rect2(24, network_y, 492, 84), "میزبانی روی وای‌فای", host._start_host, net, theme["BLUE"], "option", "wifi", "m_host", "شما میزبان باشید، دوستتان با IP وصل می‌شود")
	host._add_btn(Rect2(24, network_y + 98, 492, 84), "اتصال با IP", host._go_ip_entry, net, theme["ACCENT"], "option", "keypad", "m_join", "به بازی میزبانِ دیگر بپیوندید")
	host._add_btn(Rect2(24, network_y + 196, 492, 84), "بازی آنلاین", host._open_online_for_game, online_net, theme["PINK"], "option", "globe", "m_online", "جستجوی حریف از طریق سرور آنلاین")
	if web_build:
		host.buttons[host.buttons.size() - 3].hint = "میزبانی مستقیم ENet/UDP در مرورگر ممکن نیست."
		host.buttons[host.buttons.size() - 2].hint = "اتصال مستقیم IP فقط در APK/Desktop فعال است."
		host.buttons[host.buttons.size() - 1].hint = "برای نسخه وب از صف انتظار و WebSocket امن استفاده کنید."
	elif not net:
		host.buttons[host.buttons.size() - 3].hint = "این بازی فعلاً فقط با کامپیوتر قابل بازی است."
		host.buttons[host.buttons.size() - 2].hint = "این بازی فعلاً فقط با کامپیوتر قابل بازی است."
		host.buttons[host.buttons.size() - 1].hint = "این بازی فعلاً فقط با کامپیوتر قابل بازی است."


const DIFFICULTY_LABELS: Array[String] = ["خیلی آسان", "آسان", "متوسط", "سخت", "استاد", "استادتمام"]


func _points_text(host, preview: Dictionary) -> String:
	var win: int = int(preview.get("win_applied", 0))
	var loss: int = int(preview.get("loss_applied", 0))
	return "برد %s · باخت %s" % [RankingServiceScript.signed(win) if win > 0 else "۰", RankingServiceScript.signed(loss) if loss < 0 else "۰"]


# Shows what a win / loss is worth right now so players can see the risk-reward of harder levels and online matches.
func _draw_reward_preview(host, theme: Dictionary, hero: Rect2, rx: float) -> void:
	var svc = host.scoring_service
	var gid: String = host.selected_game
	var level: int = host._current_game_difficulty()
	var cpu_pv: Dictionary = svc.preview_points(gid, "cpu", level)
	var human_pv: Dictionary = svc.preview_points(gid, "human_online", level, svc.match_rating(gid))
	var cpu_line: String = "کامپیوتر (این سطح) · " + _points_text(host, cpu_pv)
	if int(cpu_pv.get("win_applied", 0)) == 0 and int(cpu_pv.get("win", 0)) > 0:
		cpu_line = "کامپیوتر · سقف امتیاز تمرین پر است"
	var on_line: String = "آنلاین با انسان · " + _points_text(host, human_pv)
	host._txt_r(cpu_line, rx, hero.position.y + 190, host._fit_size(cpu_line, 250.0, 13, true), theme["TEXT_DIM"], true, 252)
	host._txt_r(on_line, rx, hero.position.y + 210, host._fit_size(on_line, 250.0, 13, true), theme["GREEN"], true, 252)


func render(host, theme: Dictionary) -> void:
	var info: Dictionary = host._game_info(host.selected_game)
	var col: Color = info.get("icon_col", theme["ACCENT"])
	host._draw_bar_top(76.0)
	var hero := Rect2(24, 92, 492, 226)
	host._panel(hero, theme["CARD"], 24, Color(col.r, col.g, col.b, 0.4), 1.5, 16, 6)
	var art := Rect2(hero.position + Vector2(14, 14), Vector2(200, 198))
	host._panel(art, Color(col.r * 0.30 + 0.035, col.g * 0.30 + 0.045, col.b * 0.30 + 0.09, 1.0), 18)
	host._draw_game_art(host.selected_game, Rect2(art.position + Vector2(0, 40), Vector2(art.size.x, 118)), col)
	host._gloss(art, 18, 0.05)
	var rx: float = hero.end.x - 20
	var nm: String = str(info.get("name", ""))
	host._txt_r(nm, rx, hero.position.y + 56, host._fit_size(nm, 250, 30, true), theme["TEXT"], true, 260)
	host._wrap(str(info.get("desc", "")), hero.position.x + 230, hero.position.y + 88, 240, 15, theme["TEXT_DIM"], HORIZONTAL_ALIGNMENT_RIGHT)
	var chip_y: float = hero.position.y + 150
	var cx: float = rx
	var chips: Array = [str(info.get("players", "2 نفره"))]
	if OS.has_feature("web"):
		chips.append("نسخه وب · بازی محلی")
	elif info.get("net", false):
		chips.append("چندنفره شبکه‌ای")
	else:
		chips.append("فقط آفلاین")
	if info.get("beta", false):
		chips.append("آزمایشی")
	for t in chips:
		var w: float = host._txt_w(t, 13, true) + 26.0
		cx -= w
		var cc: Color = Color(1.0, 0.72, 0.25) if t == "آزمایشی" else col
		host._panel(Rect2(cx, chip_y, w, 28), Color(cc.r, cc.g, cc.b, 0.16), 14, Color(cc.r, cc.g, cc.b, 0.6), 1.0)
		host._txt_c(t, Rect2(cx, chip_y, w, 28), 13, cc.lightened(0.3), true)
		cx -= 8.0
	_draw_reward_preview(host, theme, hero, rx)
	var rec_label: String = DIFFICULTY_LABELS[host.scoring_service.recommended_cpu_level(host.selected_game) - 1]
	var prompt_suffix: String = " · پیشنهاد: " + rec_label
	if host.selected_game == "quoridor":
		host._txt_r("سطح هوش کامپیوتر را انتخاب کنید" + prompt_suffix, host.VIEW_W - 28, 333, 13, theme["TEXT_DIM"], true, 380)
		host._txt_r("روش بازی", host.VIEW_W - 28, 389, 13, theme["TEXT_DIM"], true, 180)
	elif host.selected_game in ["othello", "othello12", "pentago", "domino", "gobblet", "abalone", "mastermind", "blockace", "quarto", "backgammon", "uno", "chess", "connect4", "jenga", "mafia"]:
		var difficulty_prompt: String = "درجه سختی، طول کد و تعداد رنگ‌ها" if host.selected_game == "mastermind" else "سطح هوش کامپیوتر را انتخاب کنید"
		host._txt_r(difficulty_prompt + prompt_suffix, host.VIEW_W - 28, 333, 13, theme["TEXT_DIM"], true, 380)
		var mode_prompt: String = "کد: %s خانه · %s رنگ" % [host._fa(3 + host.mm_difficulty), host._fa(3 + host.mm_difficulty)] if host.selected_game == "mastermind" else ("بازیکنان: %s · هدف: ۵۰۰ امتیاز" % host._fa(host._game_modules["uno"].uno_player_count) if host.selected_game == "uno" else ("بازیکنان: %s" % host._fa(host._game_modules["jenga"].jenga_player_count) if host.selected_game == "jenga" else ("بازیکنان: %s · سناریوی کلاسیک" % host._fa(host._game_modules["mafia"].mafia_player_count) if host.selected_game == "mafia" else "روش بازی")))
		if host.selected_game not in ["uno", "jenga", "mafia"]:
			host._txt_r(mode_prompt, host.VIEW_W - 28, 389, 13, theme["TEXT_DIM"], true, 180)
	else:
		host._txt_r("روش بازی را انتخاب کنید", host.VIEW_W - 28, 336, 15, theme["TEXT_DIM"], true, 300)
	host._txt_c(nm, Rect2(70, 10, host.VIEW_W - 140, 40), 22, theme["TEXT"], true)
	host._txt_c("حالت بازی را انتخاب کنید", Rect2(40, 46, host.VIEW_W - 80, 24), 13, theme["TEXT_DIM"])
