extends RefCounted
## Tower geometry and input hit testing; rules own legal moves and collapse outcomes.
const TOWER := Rect2(30, 218, 480, 522)
const ROW_H := 28.0
const BLOCK_W := 156.0
const BLOCK_GAP := 3.0
const TOWER_X := 32.0
const TOWER_BOTTOM := 736.0

func handle_tap(app, game, point: Vector2) -> void:
	if not game._jenga_my_turn() or game.jenga_game_over:
		return
	if game.jenga_phase != "remove" or point.x < TOWER_X or point.x > TOWER_X + 3.0 * BLOCK_W or point.y < TOWER.position.y or point.y > TOWER_BOTTOM:
		return
	var slot: int = clampi(int(floor((point.x - TOWER_X) / BLOCK_W)), 0, 2)
	var row_h: float = minf(ROW_H, (TOWER_BOTTOM - TOWER.position.y) / float(game.jenga_layers.size()))
	var level: int = int(floor((TOWER_BOTTOM - point.y) / row_h))
	if game._jenga_legal_removal(level, slot):
		game._jenga_submit_remove(level, slot)

func build_buttons(app, game) -> void:
	if game.jenga_game_over or not game._jenga_my_turn():
		return
	if game.jenga_phase == "place":
		var slots: Array[int] = game._jenga_legal_place_slots()
		for slot in slots:
			app._add_btn(Rect2(28 + slot * 166, 800, 158, 48), "جایگاه %s" % app._fa(slot + 1), game._jenga_submit_place.bind(slot), true, app.GREEN, "soft", "check", "jenga_place_%d" % slot)

func render(app, game) -> void:
	var seat_names: Array[String] = []
	var local_seat: int = 0 if app.vs_cpu else app.local_seat
	for seat in range(game.jenga_player_count):
		seat_names.append("شما" if seat == local_seat else ("CPU %s" % app._fa(seat + 1) if app.vs_cpu else "بازیکن %s" % app._fa(seat + 1)))
	var active_name: String = seat_names[game.jenga_turn] if game.jenga_turn < seat_names.size() else "—"
	var a: Dictionary = app._pl(seat_names[0], app.GREEN, app._fa(game.jenga_moves), game.jenga_turn == 0 and not game.jenga_game_over, true, "بازیکن اول")
	var b: Dictionary = app._pl(active_name if game.jenga_turn != 0 else seat_names[min(1, seat_names.size() - 1)], app.ACCENT, "طبقه %s" % app._fa(game.jenga_layers.size()), not game.jenga_game_over, game.jenga_turn != 0, "نوبت فعلی")
	app._draw_hud("برج هیجان · Jenga", a, b)
	app._draw_ai_difficulty_chip_at(game.jenga_difficulty, 150)
	app._panel(TOWER, Color("#3b281b"), 18, Color("#bf8a4c"), 1.4, 12, 6)
	var row_h: float = minf(ROW_H, (TOWER_BOTTOM - TOWER.position.y) / float(game.jenga_layers.size()))
	for level in range(game.jenga_layers.size()):
		var layer: Array = game.jenga_layers[level]
		var row_y: float = TOWER_BOTTOM - (level + 1) * row_h
		var highest: int = game._jenga_highest_complete_layer()
		for slot in range(3):
			var rect := Rect2(TOWER_X + slot * BLOCK_W, row_y + 1, BLOCK_W - BLOCK_GAP, row_h - 2)
			if bool(layer[slot]):
				var tone: Color = Color("#bd8550") if level % 2 == 0 else Color("#e0b77c")
				if game.jenga_phase == "remove" and game._jenga_legal_removal(level, slot) and game._jenga_my_turn():
					tone = tone.lightened(0.15)
				app._panel(rect, tone, 4, Color("#6b462a"), 1.0, 2, 1)
				app.draw_line(Vector2(rect.position.x + 8, rect.position.y + 4), Vector2(rect.end.x - 8, rect.position.y + 4), Color(1, 1, 1, 0.18), 1.0)
				if level == highest and game.jenga_phase == "remove" and game._jenga_legal_removal(level, slot):
					app.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 2)), Color(1, 0.85, 0.45, 0.9), true)
			else:
				app._panel(rect, Color("#211b1b", 0.75), 4, Color("#5a4837", 0.25), 0.5)
	if game.jenga_phase == "remove":
		var line: String = "بلوک برج را انتخاب کنید" if game._jenga_my_turn() else "منتظر نوبت بازیکن %s" % app._fa(game.jenga_turn + 1)
		app._hint(line, 758, app.GREEN if game._jenga_my_turn() else app.TEXT_DIM)
	else:
		app._hint("بلوک را در بالای برج قرار دهید", 758, app.GREEN)
	app._txt_c(game.jenga_status, Rect2(20, 852, 500, 34), 12, app.TEXT_DIM)
	app._txt_c("قانون: از زیر بالاترین طبقهٔ کامل بردارید؛ بلوکِ کشیده‌شده باید روی برج قرار بگیرد.", Rect2(20, 886, 500, 36), 10, app.TEXT_FAINT)
