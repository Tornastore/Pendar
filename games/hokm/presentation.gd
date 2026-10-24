extends RefCounted
## Hokm card layout and table rendering; turn legality and tricks remain in rules.gd.

func hand_rects(app, game) -> Array:
	return app._fan_rects(game.hokm_hands[game._hokm_me()].size(), 58.0, 86.0, 762.0, 500.0, 6.0)

func handle_tap(app, game, point: Vector2) -> void:
	var index: int = app._fan_hit(hand_rects(app, game), point)
	game._hokm_handle_card_index(index)

func render(app, game) -> void:
	var me: int = game._hokm_me()
	var pa: Dictionary = app._pl("شما", app.BLUE, app._fa(game.hokm_scores[me]), game.hokm_turn == me and not game.hokm_game_over, true, "دست برده")
	var pb: Dictionary = app._pl("حریف", app.PINK, app._fa(game.hokm_scores[1 - me]), game.hokm_turn == 1 - me and not game.hokm_game_over, false, "دست برده")
	if pa.active:
		pa.sub = "نوبت شما"
	app._draw_hud("حکم", pa, pb)
	app._draw_ai_difficulty_chip(game.hokm_difficulty)
	var orr: Array = app._fan_rects(game.hokm_hands[1 - me].size(), 36.0, 52.0, 150.0, 240.0, 4.0)
	for r in orr:
		app._draw_card_back(r)
	var badge := Rect2(16, 150, 118, 40)
	app._panel(badge, Color(1, 1, 1, 0.07), 20, app.ACCENT, 1.2)
	app._txt_r("حکم", badge.end.x - 14, badge.position.y + 26, 15, app.TEXT, true, 60)
	var sc: Color = Color(0.9, 0.25, 0.3) if (game.hokm_trump == 1 or game.hokm_trump == 2) else Color(0.95, 0.96, 1.0)
	app._draw_suit(game.hokm_trump, Vector2(badge.position.x + 34, badge.get_center().y), 22, sc)
	var table := Rect2(16, 210, app.VIEW_W - 32, 380)
	app._panel(table, Color(0.07, 0.24, 0.20), 26, Color(0.25, 0.65, 0.5, 0.4), 1.5, 18, 6)
	var slot_opp := Rect2(app.VIEW_W * 0.5 - 45, 236, 90, 126)
	var slot_me := Rect2(app.VIEW_W * 0.5 - 45, 424, 90, 126)
	for s in [slot_opp, slot_me]:
		app._panel(s, Color(1, 1, 1, 0.05), 12, Color(1, 1, 1, 0.15), 1.0)
	var showing_last: bool = game.hokm_trick.size() == 0 and game.hokm_last.size() == 2 and app._time - game.hokm_last_t < 1.4
	var plays: Array = game.hokm_last if showing_last else game.hokm_trick
	for it in plays:
		var rr: Rect2 = slot_me if int(it.p) == me else slot_opp
		var won: bool = showing_last and int(it.p) == game.hokm_last_winner
		app._draw_card(rr, it.c, false, false, won)
	if showing_last:
		app._txt_c("برنده این دست: " + ("شما" if game.hokm_last_winner == me else "حریف"), Rect2(table.position.x, table.position.y + 4, table.size.x, 26), 13, app.ACCENT, true)
	app._txt_c("هنوز ۱۳ دست: " + app._fa(13 - game.hokm_hands[me].size()) + " / " + app._fa(13), Rect2(table.position.x, table.end.y - 30, table.size.x, 24), 12, Color(1, 1, 1, 0.4))
	var rects: Array = hand_rects(app, game)
	for i in rects.size():
		var c: Dictionary = game.hokm_hands[me][i]
		var ok: bool = game.hokm_turn == me and game._hokm_legal(me, c)
		app._draw_card(rects[i], c, false, game.hokm_turn == me and not ok, false)
	if not game.hokm_game_over:
		app._hint("کارت بزنید تا بازی شود" if game.hokm_turn == me else "حریف در حال بازی…", 706, app.TEXT_DIM)
