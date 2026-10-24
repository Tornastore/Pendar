extends RefCounted
## Domino presentation and pointer hit-testing.
## The rules module remains authoritative for tile selection, turns, draws and plays.

func hand_rects(app, game) -> Array:
	return app._fan_rects(game.dom_hands[game._dom_me()].size(), 54.0, 88.0, 756.0, 500.0, 8.0)


func handle_tap(app, game, point: Vector2) -> void:
	if not game._dom_my_turn():
		return
	var rects: Array = hand_rects(app, game)
	var index: int = app._fan_hit(rects, point)
	game._dom_select(index)


func build_buttons(app, game) -> void:
	if not game._dom_my_turn():
		return
	var me: int = game._dom_me()
	var playable: Array = game._dom_playable(me)
	if game.dom_selected >= 0 and game.dom_selected < game.dom_hands[me].size():
		var tile: Vector2i = game.dom_hands[me][game.dom_selected]
		var can_left: bool = game._dom_can_play(tile, "L")
		var can_right: bool = game._dom_can_play(tile, "R")
		if can_left and can_right:
			app._add_btn(Rect2(app.VIEW_W - 16 - 244, 676, 244, 56), "ابتدا (%s)" % app._fa(game.dom_left), game._dom_do_play.bind("L"), true, app.DOM_END_A, "solid", "", "dom_l")
			app._add_btn(Rect2(16, 676, 244, 56), "انتها (%s)" % app._fa(game.dom_right), game._dom_do_play.bind("R"), true, app.DOM_END_B, "solid", "", "dom_r")
		elif can_left:
			app._add_btn(Rect2(60, 676, app.VIEW_W - 120, 56), "گذاشتن در ابتدا (%s)" % app._fa(game.dom_left), game._dom_do_play.bind("L"), true, app.DOM_END_A, "solid", "", "dom_l")
		elif can_right:
			app._add_btn(Rect2(60, 676, app.VIEW_W - 120, 56), "گذاشتن در انتها (%s)" % app._fa(game.dom_right), game._dom_do_play.bind("R"), true, app.DOM_END_B, "solid", "", "dom_r")
	elif playable.is_empty():
		if not game.dom_boneyard.is_empty():
			app._add_btn(Rect2(60, 676, app.VIEW_W - 120, 56), "برداشتن از انبار (%s)" % app._fa(game.dom_boneyard.size()), game._dom_do_draw, true, app.ACCENT, "solid", "", "dom_draw")
		else:
			app._add_btn(Rect2(60, 676, app.VIEW_W - 120, 56), "پاس دادن", game._dom_do_pass, true, app.ACCENT, "solid", "", "dom_pass")


func render(app, game) -> void:
	var me: int = game._dom_me()
	var opponent: int = 1 - me
	var player_panel: Dictionary = app._pl("شما", app.BLUE, app._fa(game.dom_hands[me].size()), game.dom_turn == me and not game.dom_game_over, true, "مهره‌ها")
	var opponent_panel: Dictionary = app._pl("حریف", app.PINK, app._fa(game.dom_hands[opponent].size()), game.dom_turn == opponent and not game.dom_game_over, false, "مهره‌ها")
	if player_panel.active:
		player_panel.sub = "نوبت شما"
	app._draw_hud("دومینو", player_panel, opponent_panel)

	# Opponent's hand is shown face down.
	var opponent_rects: Array = app._fan_rects(game.dom_hands[opponent].size(), 28.0, 40.0, 152.0, 360.0, 6.0)
	for rect in opponent_rects:
		app._draw_dom_back(rect)

	var boneyard_rect := Rect2(16, 152, 94, 34)
	app._panel(boneyard_rect, Color(0, 0, 0, 0.3), 17)
	app._txt_c("انبار: " + app._fa(game.dom_boneyard.size()), boneyard_rect, 13, app.TEXT_DIM, true)
	app._draw_ai_difficulty_chip(game.dom_difficulty)

	var table := Rect2(16, 200, app.VIEW_W - 32, 456)
	app._panel(table, Color(0.07, 0.24, 0.20), 26, Color(0.25, 0.65, 0.5, 0.4), 1.5, 18, 6)
	var count: int = game.dom_chain.size()
	var rows: int = int((count + app.DOM_PER_ROW - 1) / app.DOM_PER_ROW)
	var step_x: float = app.DOM_L + 3.0
	var row_h: float = app.DOM_W + 12.0
	var top_y: float = table.get_center().y - rows * row_h * 0.5
	for i in count:
		var row: int = int(i / app.DOM_PER_ROW)
		var col: int = i % app.DOM_PER_ROW
		var in_row: int = mini(app.DOM_PER_ROW, count - row * app.DOM_PER_ROW)
		var reversed: bool = (row % 2 == 1)
		var visible_col: int = (in_row - 1 - col) if reversed else col
		var row_width: float = in_row * step_x
		var x: float = table.get_center().x - row_width * 0.5 + visible_col * step_x
		var rect := Rect2(x, top_y + row * row_h, app.DOM_L, app.DOM_W)
		var tile: Vector2i = game.dom_chain[i]
		var left_pip: int = tile.y if reversed else tile.x
		var right_pip: int = tile.x if reversed else tile.y
		var glow := Color(0, 0, 0, 0)
		if i == 0:
			glow = app.DOM_END_A
		elif i == count - 1:
			glow = app.DOM_END_B
		app._draw_dom_tile(rect, left_pip, right_pip, false, false, true, glow)

	if count > 0:
		var left_rect := Rect2(table.position.x + 14, table.end.y - 40, 118, 28)
		app._panel(left_rect, Color(app.DOM_END_A.r, app.DOM_END_A.g, app.DOM_END_A.b, 0.18), 14, app.DOM_END_A, 1.0)
		app._txt_c("ابتدا: " + app._fa(game.dom_left), left_rect, 13, app.DOM_END_A.lightened(0.3), true)
		var right_rect := Rect2(table.position.x + 142, table.end.y - 40, 118, 28)
		app._panel(right_rect, Color(app.DOM_END_B.r, app.DOM_END_B.g, app.DOM_END_B.b, 0.18), 14, app.DOM_END_B, 1.0)
		app._txt_c("انتها: " + app._fa(game.dom_right), right_rect, 13, app.DOM_END_B.lightened(0.3), true)

	var hand_rects_value: Array = hand_rects(app, game)
	var my_turn: bool = game._dom_my_turn()
	for i in hand_rects_value.size():
		var rect: Rect2 = hand_rects_value[i]
		var tile: Vector2i = game.dom_hands[me][i]
		var playable_tile: bool = game._dom_can_play(tile, "L") or game._dom_can_play(tile, "R")
		var selected: bool = i == game.dom_selected
		if selected:
			rect.position.y -= 16.0
		app._draw_dom_tile(rect, tile.x, tile.y, selected, my_turn and not playable_tile, false)
	if not game.dom_game_over:
		if my_turn:
			if game.dom_selected < 0 and not game._dom_playable(me).is_empty():
				app._hint("یک مهره انتخاب کنید", 640, app.ACCENT)
			elif game.dom_selected < 0:
				app._hint("مهره مناسب ندارید", 640, app.ACCENT)
		else:
			app._hint("حریف در حال بازی…", 640, app.TEXT_DIM)
