extends RefCounted
## UNO screen rendering and button layout. The rules module remains authoritative.

const COLORS: Array[Color] = [Color("#e9434f"), Color("#2289e8"), Color("#32a765"), Color("#f3c735")]
const COLOR_NAMES: Array[String] = ["قرمز", "آبی", "سبز", "زرد"]

func handle_tap(_app, _game, _point: Vector2) -> void:
	# UNO uses explicit action/card buttons rather than direct table taps.
	pass

func build_buttons(app, game) -> void:
	if game.uno_game_over or game.uno_round_over:
		return
	var seat: int = app._my_seat()
	var local_turn: bool = game._uno_is_local_turn()
	if local_turn and game.uno_catch_seat >= 0 and game.uno_catch_seat != seat and not game.uno_challenge_available:
		app._add_btn(Rect2(18, 634, 504, 42), "گرفتن اعلام UNO · جریمه ۲ کارت", game._uno_catch_request, true, Color("#ef9d45"), "soft", "alert", "uno_catch")
	if local_turn and game.uno_challenge_available:
		app._add_btn(Rect2(18, 632, 244, 46), "چالش +۴", game._uno_challenge_request.bind(true), true, Color("#ef626b"), "soft", "alert", "uno_challenge")
		app._add_btn(Rect2(278, 632, 244, 46), "قبول +۴ · کشیدن ۴ کارت", game._uno_challenge_request.bind(false), true, Color("#6da4ff"), "soft", "check", "uno_accept")
		return
	if not local_turn:
		return
	var hand_size: int = game.uno_hands[seat].size()
	var start: int = mini(game.uno_hand_page * 7, maxi(0, hand_size - 1))
	var visible: int = mini(7, hand_size - start)
	for i in range(visible):
		var index: int = start + i
		var card: Dictionary = game.uno_hands[seat][index]
		app._add_btn(Rect2(14 + i * 73, 687, 68, 100), "", game._uno_select_card.bind(index), true, COLORS[maxi(0, game._uno_card_color(card))] if game._uno_card_color(card) >= 0 else Color("#9b79ea"), "ghost", "", "uno_hand_%d" % index)
	if hand_size > 7:
		app._add_btn(Rect2(18, 644, 74, 34), "◀", func(): game.uno_hand_page = maxi(0, game.uno_hand_page - 1); app._rebuild_buttons(), true, app.ACCENT, "ghost", "", "uno_hand_prev")
		app._add_btn(Rect2(448, 644, 74, 34), "▶", func(): game.uno_hand_page = mini(int(ceil(float(hand_size) / 7.0)) - 1, game.uno_hand_page + 1); app._rebuild_buttons(), true, app.ACCENT, "ghost", "", "uno_hand_next")
	if game.uno_selected_card >= 0 and game.uno_selected_card < hand_size:
		var selected: Dictionary = game.uno_hands[seat][game.uno_selected_card]
		if game._uno_card_kind(selected) in ["wild", "wild4"]:
			for c in range(4):
				app._add_btn(Rect2(18 + c * 128, 802, 120, 36), COLOR_NAMES[c], func(): game.uno_pending_color = c; app._rebuild_buttons(), true, COLORS[c], "soft", "", "uno_color_%d" % c)
		if hand_size == 2:
			var color_ready: bool = game._uno_card_kind(selected) not in ["wild", "wild4"] or game.uno_pending_color >= 0
			app._add_btn(Rect2(16, 844, 246, 38), "اعلام UNO و بازی" if color_ready else "رنگ را انتخاب کنید", func(): game._uno_submit_play(game.uno_selected_card, game.uno_pending_color, true), color_ready, app.GREEN, "solid", "check", "uno_play_call")
			app._add_btn(Rect2(278, 844, 246, 38), "بدون اعلام و بازی" if color_ready else "رنگ را انتخاب کنید", func(): game._uno_submit_play(game.uno_selected_card, game.uno_pending_color, false), color_ready, app.RED, "soft", "alert", "uno_play_nocall")
		else:
			var color_ready: bool = game._uno_card_kind(selected) not in ["wild", "wild4"] or game.uno_pending_color >= 0
			app._add_btn(Rect2(18, 844, 244, 38), "بازی کارت" if color_ready else "رنگ را انتخاب کنید", func(): game._uno_submit_play(game.uno_selected_card, game.uno_pending_color, false), color_ready, app.GREEN, "solid", "check", "uno_play")
			if game.uno_drawn_card_index >= 0:
				app._add_btn(Rect2(278, 844, 244, 38), "رد نوبت", game._uno_pass_request, true, app.TEXT_DIM, "ghost", "skip", "uno_pass")
	else:
		# A second draw is not permitted after a playable card has been drawn.
		if game.uno_drawn_card_index < 0:
			app._add_btn(Rect2(18, 844, 244, 38), "برداشتن کارت", game._uno_draw_request, true, app.BLUE, "solid", "download", "uno_draw")
		if game.uno_drawn_card_index >= 0:
			app._add_btn(Rect2(278, 844, 244, 38), "رد نوبت", game._uno_pass_request, true, app.TEXT_DIM, "ghost", "skip", "uno_pass")

func draw_card_visual(app, game, r: Rect2, card: Dictionary, selected: bool = false, small: bool = false) -> void:
	var color_id: int = game._uno_card_color(card)
	var fill: Color = COLORS[color_id] if color_id >= 0 and color_id < COLORS.size() else Color("#8b62d9")
	var radius: float = 9.0 if small else 12.0
	app._panel(Rect2(r.position + Vector2(0, 3), r.size), Color(0, 0, 0, 0.45), radius)
	app._panel(r, fill, radius, app.ACCENT if selected else Color(1, 1, 1, 0.9), 2.5 if selected else 1.0)
	var inner: Rect2 = r.grow(-r.size.x * 0.13)
	app._panel(inner, Color(0.06, 0.07, 0.12, 0.90), radius * 0.8)
	var label: String = game._uno_card_label(card)
	if game._uno_card_kind(card) == "num":
		app._txt_c(label, inner, int(minf(r.size.x * 0.66, 26.0 if not small else 18.0)), Color.WHITE, true)
	else:
		app._txt_c(label, inner, int(minf(r.size.x * 0.34, 17.0 if not small else 12.0)), Color.WHITE, true)

func render(app, game) -> void:
	app._draw_bar_top(72.0)
	app._txt_c("اونو · UNO", Rect2(70, 10, 400, 42), 24, app.TEXT, true)
	app._draw_ai_difficulty_chip_at(game.uno_difficulty, 50.0)
	var me: int = app._my_seat()
	var top: Dictionary = game._uno_top_card()
	var cols: Array[Color] = [app.BLUE, app.GREEN, app.RED, app.ACCENT, app.PINK, Color("#8b8ef0")]
	var row_w: float = 504.0 / float(game.uno_player_count)
	if game.uno_player_count > 5:
		row_w = 504.0 / 5.0
	for seat in range(game.uno_player_count):
		var col_idx: int = seat % 5
		var row_idx: int = int(seat / 5)
		var r := Rect2(18 + col_idx * row_w, 88 + row_idx * 58, row_w - 5, 51)
		var active: bool = seat == game.uno_turn and not game.uno_round_over
		app._panel(r, Color(0.15, 0.19, 0.34) if active else app.CARD, 10, cols[seat % cols.size()] if active else app.LINE_STRONG, 1.5 if active else 0.7)
		app._txt_r(game._uno_player_name(seat), r.end.x - 6, r.position.y + 18, 10 if game.uno_player_count > 5 else 12, app.TEXT if active else app.TEXT_DIM, true, r.size.x - 38)
		app._txt_c(str(game.uno_hands[seat].size()) + " کارت", Rect2(r.position.x + 2, r.position.y + 24, r.size.x * 0.55, 23), 11, app.TEXT_DIM)
		app._txt_c(str(game.uno_scores[seat]), Rect2(r.end.x - 36, r.position.y + 24, 32, 23), 11, app.ACCENT if active else app.TEXT_DIM, true)
	var mid_y: float = 300.0 if game.uno_player_count <= 5 else 326.0
	app._panel(Rect2(30, mid_y - 68, 480, 228), Color(0.07, 0.08, 0.15, 0.88), 24, app.LINE_STRONG, 1.0, 10, 4)
	app._txt_c("رنگ فعال: " + COLOR_NAMES[game.uno_current_color], Rect2(70, mid_y - 56, 400, 28), 15, COLORS[game.uno_current_color], true)
	var top_rect := Rect2(210, mid_y - 15, 120, 162)
	draw_card_visual(app, game, top_rect, top, false, false)
	app._panel(Rect2(58, mid_y + 10, 104, 120), Color(0.13, 0.15, 0.25), 12, app.LINE_STRONG)
	app._txt_c("دسته", Rect2(58, mid_y + 22, 104, 26), 14, app.TEXT_DIM, true)
	app._txt_c(str(game.uno_draw_pile.size()), Rect2(58, mid_y + 56, 104, 30), 22, app.TEXT, true)
	app._txt_c("کارت", Rect2(58, mid_y + 84, 104, 24), 12, app.TEXT_DIM)
	app._txt_c("کارت رو شده", Rect2(350, mid_y + 48, 140, 25), 12, app.TEXT_DIM)
	if game.uno_challenge_available:
		app._hint("+۴ بازی شده؛ می‌توانید چالش کنید یا ۴ کارت بکشید.", 544, app.RED)
	elif game.uno_catch_seat >= 0:
		app._hint("بازیکن هنوز اعلام UNO نکرده؛ پیش از بازی کارت بگیرید.", 544, Color("#efb253"))
	else:
		app._hint(game.uno_status if not game.uno_status.is_empty() else ("نوبت شما" if game.uno_turn == me else "در انتظار حرکت بازیکن"), 544, app.ACCENT if game.uno_turn == me else app.TEXT_DIM)
	if me >= 0 and me < game.uno_hands.size():
		var hand: Array = game.uno_hands[me]
		var start: int = mini(game.uno_hand_page * 7, maxi(0, hand.size() - 1))
		var count: int = mini(7, hand.size() - start)
		for i in range(count):
			var index: int = start + i
			draw_card_visual(app, game, Rect2(14 + i * 73, 687, 68, 100), hand[index], index == game.uno_selected_card, true)
		app._txt_c("دست شما · %s از %s کارت" % [start + 1 if hand.size() > 0 else 0, hand.size()], Rect2(35, 650, 470, 24), 13, app.TEXT_DIM)
	if game.uno_round_over:
		app._hint("پایان دست · برنده %s · امتیاز این دست %s" % [game._uno_player_name(game.uno_round_winner), game.uno_last_round_points], 588, app.GREEN)
	elif game.uno_turn != me:
		app._hint("نوبت %s" % game._uno_player_name(game.uno_turn), 588, app.TEXT_DIM)
	app._txt_c("مسابقه تا ۵۰۰ امتیاز · بدون قانون جمع‌کردن +۲ و +۴", Rect2(35, 610, 470, 24), 11, app.TEXT_FAINT)
