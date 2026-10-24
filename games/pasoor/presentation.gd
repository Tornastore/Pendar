extends RefCounted
## Pasoor cards/table layout and presentation; capture scoring and play legality stay in rules.gd.

func hand_rects(app, game) -> Array:
	return app._fan_rects(game.pas_hands[game._pas_me()].size(), 66.0, 96.0, 776.0, 500.0, 8.0)

func table_rects(app, game) -> Array:
	var n: int = game.pas_table.size()
	var res: Array = []
	if n <= 14:
		var r1: int = mini(7, n)
		var a: Array = app._fan_rects(r1, 56.0, 80.0, 244.0, 480.0, 6.0)
		res.append_array(a)
		if n > 7:
			res.append_array(app._fan_rects(n - 7, 56.0, 80.0, 334.0, 480.0, 6.0))
	else:
		res = app._fan_rects(n, 56.0, 80.0, 286.0, 480.0, 6.0)
	return res

func handle_tap(app, game, point: Vector2) -> void:
	var index: int = app._fan_hit(hand_rects(app, game), point)
	game._pas_handle_hand_index(index)

func build_buttons(app, game) -> void:
	if not game._pas_my_turn() or game.pas_selected < 0:
		return
	var me: int = game._pas_me()
	if game.pas_selected >= game.pas_hands[me].size():
		return
	var card: Dictionary = game.pas_hands[me][game.pas_selected]
	var captures: Array = game._pas_find_captures(card)
	if captures.size() > 0:
		var best: Array = game._pas_best_capture(card)
		app._add_btn(Rect2(60, 710, app.VIEW_W - 120, 54), "گرفتن %s کارت" % app._fa(best.size() + 1), game._pas_confirm, true, app.GREEN, "solid", "check", "pas_go")
	else:
		app._add_btn(Rect2(60, 710, app.VIEW_W - 120, 54), "گذاشتن روی میز", game._pas_confirm, true, app.ACCENT, "solid", "play", "pas_go")

func render(app, game) -> void:
	var me: int = game._pas_me()
	var opp: int = 1 - me
	var pa: Dictionary = app._pl("شما", app.BLUE, app._fa(game.pas_match_scores[me]), game.pas_turn == me and not game.pas_game_over, true, "سور: " + app._fa(game.pas_surs[me]))
	var pb: Dictionary = app._pl("حریف", app.PINK, app._fa(game.pas_match_scores[opp]), game.pas_turn == opp and not game.pas_game_over, false, "سور: " + app._fa(game.pas_surs[opp]))
	if game.pas_turn == me and not game.pas_game_over:
		pa.sub = "نوبت شما"
	if game.pas_turn == opp and not game.pas_game_over:
		pb.sub = "نوبت حریف"
	app._draw_hud("پاسور (چهاربرگ)", pa, pb)
	app._draw_ai_difficulty_chip(game.pas_difficulty)
	var orr: Array = app._fan_rects(game.pas_hands[opp].size(), 40.0, 58.0, 150.0, 300.0, 6.0)
	for r in orr:
		app._draw_card_back(r)
	var info := Rect2(16, 150, 100, 34)
	app._panel(info, Color(0, 0, 0, 0.3), 17)
	app._txt_c("دسته: " + app._fa(game.pas_deck.size()), info, 13, app.TEXT_DIM, true)
	var felt := Rect2(16, 204, app.VIEW_W - 32, 232)
	app._panel(felt, Color(0.07, 0.24, 0.20), 26, Color(0.25, 0.65, 0.5, 0.4), 1.5, 18, 6)
	app._txt_c("میز (" + app._fa(game.pas_table.size()) + ")", Rect2(felt.position.x, felt.position.y + 4, felt.size.x, 30), 13, Color(1, 1, 1, 0.45), true)
	var hl: Array = []
	var me_hand: Array = game.pas_hands[me]
	if game.pas_selected >= 0 and game.pas_selected < me_hand.size() and game._pas_my_turn():
		hl = game._pas_best_capture(me_hand[game.pas_selected])
	var trs: Array = table_rects(app, game)
	for i in trs.size():
		var r: Rect2 = trs[i]
		app._draw_card(r, game.pas_table[i], false, false, i in hl)
	if game.pas_table.size() == 0:
		app._txt_c("میز خالی است", Rect2(felt.position.x, felt.position.y + 80, felt.size.x, 60), 16, Color(1, 1, 1, 0.3))
	var cap_me := Rect2(16, 446, 240, 30)
	app._panel(cap_me, Color(app.GREEN.r, app.GREEN.g, app.GREEN.b, 0.12), 15)
	app._txt_c("کارت‌های گرفته‌شده شما: " + app._fa(game.pas_captured[me].size()), cap_me, 12, app.GREEN, true)
	var cap_op := Rect2(app.VIEW_W - 16 - 240, 446, 240, 30)
	app._panel(cap_op, Color(app.RED.r, app.RED.g, app.RED.b, 0.12), 15)
	app._txt_c("حریف: " + app._fa(game.pas_captured[opp].size()), cap_op, 12, app.RED, true)
	var rects: Array = hand_rects(app, game)
	for i in rects.size():
		var r: Rect2 = rects[i]
		var sel: bool = (i == game.pas_selected)
		if sel:
			r.position.y -= 20.0
		app._draw_card(r, me_hand[i], sel, false, false)
	if not game.pas_game_over:
		if game._pas_my_turn():
			if game.pas_selected < 0:
				app._hint("یک کارت انتخاب کنید", 740, app.ACCENT)
		else:
			app._hint("حریف در حال بازی…", 740, app.TEXT_DIM)
