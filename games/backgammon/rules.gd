extends "res://core/game_module.gd"
## Rule engine and authoritative state for backgammon.

const BackgammonAIScript = preload("res://games/backgammon/ai.gd")

# ---------- Game-owned state ----------
var bg_difficulty: int = 3
var bg_points: Array = []  # 24 points, signed checker counts
var bg_bar: Array = [0, 0]
var bg_off: Array = [0, 0]
var bg_dice: Array = [0, 0]
var bg_turn: int = 0
var bg_moves_left: Array = []
var bg_sel: int = -1
var bg_game_over: bool = false
var bg_winner: int = -1

func reset_game() -> void:
	_reset_backgammon()

func _reset_backgammon() -> void:
	# standard-ish start simplified: points 0..23, positive=player0, negative=player1
	bg_points = []
	for i in 24:
		bg_points.append(0)
	bg_points[0] = 2
	bg_points[11] = 5
	bg_points[16] = 3
	bg_points[18] = 5
	bg_points[23] = -2
	bg_points[12] = -5
	bg_points[7] = -3
	bg_points[5] = -5
	bg_bar = [0, 0]
	bg_off = [0, 0]
	bg_turn = 0
	bg_dice = [randi() % 6 + 1, randi() % 6 + 1]
	bg_moves_left = [bg_dice[0], bg_dice[1]]
	if bg_dice[0] == bg_dice[1]:
		bg_moves_left = [bg_dice[0], bg_dice[0], bg_dice[0], bg_dice[0]]
	bg_sel = -1
	bg_game_over = false
	bg_winner = -1

func _bg_roll() -> void:
	bg_dice = [randi() % 6 + 1, randi() % 6 + 1]
	bg_moves_left = [bg_dice[0], bg_dice[1]]
	if bg_dice[0] == bg_dice[1]:
		bg_moves_left = [bg_dice[0], bg_dice[0], bg_dice[0], bg_dice[0]]

func _bg_cpu() -> void:
	if bg_game_over:
		return
	_bg_roll()
	var ai = BackgammonAIScript.new()
	var plan: Array = ai.choose_turn(self, bg_difficulty)
	for step_value in plan:
		if bg_game_over or bg_moves_left.is_empty():
			break
		var step: Dictionary = step_value
		var die: int = int(bg_moves_left[0])
		if int(step.get("die", die)) != die:
			# A stale or malformed plan must never make an unrelated move.
			bg_moves_left.remove_at(0)
			continue
		var source: int = int(step.get("source", -1))
		if source < 0:
			bg_moves_left.remove_at(0)
			continue
		_bg_cpu_apply_source(source, die)
	while not bg_moves_left.is_empty():
		bg_moves_left.remove_at(0)
	if bg_game_over:
		return
	bg_turn = 0
	_bg_roll()

func _bg_cpu_apply_source(source: int, die: int) -> void:
	if source < 0 or source >= 24 or int(bg_points[source]) >= 0:
		if not bg_moves_left.is_empty():
			bg_moves_left.remove_at(0)
		return
	var dest: int = source - die
	if dest >= 0 and int(bg_points[dest]) > 1:
		if not bg_moves_left.is_empty():
			bg_moves_left.remove_at(0)
		return
	bg_points[source] = int(bg_points[source]) + 1
	if dest < 0:
		bg_off[1] = int(bg_off[1]) + 1
	else:
		if int(bg_points[dest]) == 1:
			bg_points[dest] = 0
			bg_bar[0] = int(bg_bar[0]) + 1
		bg_points[dest] = int(bg_points[dest]) - 1
	if not bg_moves_left.is_empty():
		bg_moves_left.remove_at(0)
	if int(bg_off[1]) >= 15:
		bg_game_over = true
		bg_winner = 1
		app.state = State.RESULT
		app._build_result_buttons()

func _bg_pt_x(col: int) -> float:
	return 40.0 + col * 36.0 + (24.0 if col >= 6 else 0.0)

func _bg_me() -> int:
	return app._my_seat()

func _bg_step() -> void:
	if bg_game_over or (app.vs_cpu and bg_turn == 1):
		return
	if app._net_on():
		if bg_turn != _bg_me():
			return
		app._send_game_action("_rpc_bg_step", [randi() % 6 + 1, randi() % 6 + 1])
	else:
		_bg_step_apply(0, 0)

func _bg_step_apply(d1: int, d2: int) -> void:
	if bg_game_over:
		return
	if bg_moves_left.size() == 0:
		bg_turn = 1 - bg_turn
		if app.vs_cpu and bg_turn == 1:
			_bg_cpu()
		elif d1 > 0:
			bg_dice = [d1, d2]
			bg_moves_left = [d1, d2]
			if d1 == d2:
				bg_moves_left = [d1, d1, d1, d1]
		else:
			_bg_roll()
		return
	var die: int = bg_moves_left[0]
	var sg: int = 1 if bg_turn == 0 else -1
	var moved: bool = false
	for i in 24:
		if bg_points[i] * sg > 0:
			var dest: int = i + die * sg
			if dest >= 0 and dest < 24:
				if bg_points[dest] * sg >= -1:
					if bg_points[dest] * sg == -1:
						bg_points[dest] = 0
						bg_bar[1 - bg_turn] += 1
					bg_points[i] -= sg
					bg_points[dest] += sg
					bg_moves_left.remove_at(0)
					moved = true
					break
			else:
				bg_points[i] -= sg
				bg_off[bg_turn] += 1
				bg_moves_left.remove_at(0)
				moved = true
				if bg_off[bg_turn] >= 15:
					bg_game_over = true
					bg_winner = bg_turn
					app.state = State.RESULT
					app._build_result_buttons()
				break
	if not moved:
		bg_moves_left.remove_at(0)
		app._show_toast("با این تاس حرکتی ممکن نیست.")

func _bg_tap(p: Vector2) -> void:
	if Rect2(25, 170, 490, 500).has_point(p):
		_bg_step()

func _btns_backgammon() -> void:
	var mine: bool = bg_turn == _bg_me() and not bg_game_over
	var label: String = "پایان نوبت" if bg_moves_left.size() == 0 else "حرکت بعدی"
	app._add_btn(Rect2(110, 714, app.VIEW_W - 220, 58), label, _bg_step, mine, app.GREEN if bg_moves_left.size() > 0 else app.ACCENT, "solid", "play" if bg_moves_left.size() > 0 else "check", "bg_step")

func _draw_backgammon() -> void:
	var me: int = _bg_me()
	var pa: Dictionary = app._pl("شما", Color(0.9, 0.88, 0.8) if me == 0 else Color(0.15, 0.15, 0.2), app._fa(bg_off[me]), bg_turn == me and not bg_game_over, true, "خارج‌شده", 1 if me == 0 else 0)
	var pb: Dictionary = app._pl("حریف", Color(0.15, 0.15, 0.2) if me == 0 else Color(0.9, 0.88, 0.8), app._fa(bg_off[1 - me]), bg_turn == 1 - me and not bg_game_over, false, "خارج‌شده", 0 if me == 0 else 1)
	if pa.active:
		pa.sub = "نوبت شما"
	app._draw_hud("تخته نرد", pa, pb)
	var board := Rect2(25, 170, 490, 500)
	app._panel(board, Color(0.30, 0.18, 0.10), 22, Color(0.8, 0.55, 0.3, 0.5), 2.0, 20, 8)
	app._panel(board.grow(-8), Color(0.12, 0.30, 0.24), 16)
	app._panel(Rect2(_bg_pt_x(5) + 36, 178, 24, 484), Color(0.30, 0.18, 0.10), 6)
	for i in 24:
		var col_i: int = i % 12
		var top: bool = i < 12
		var x: float = _bg_pt_x(col_i)
		var y0: float = 180.0 if top else 660.0
		var tipy: float = y0 + (150.0 if top else -150.0)
		var tcol: Color = Color(0.92, 0.70, 0.42) if i % 2 == 0 else Color(0.62, 0.22, 0.22)
		app.draw_colored_polygon(PackedVector2Array([Vector2(x, y0), Vector2(x + 34, y0), Vector2(x + 17, tipy)]), tcol)
		var n: int = bg_points[i]
		var cnt: int = absi(n)
		for k in mini(cnt, 5):
			var cy: float = (y0 + 18.0 + k * 27.0) if top else (y0 - 18.0 - k * 27.0)
			app._draw_disc(Vector2(x + 17, cy), 13.5, n > 0)
		if cnt > 5:
			var ly: float = (y0 + 18.0 + 4 * 27.0) if top else (y0 - 18.0 - 4 * 27.0)
			app._txt_c(app._fa(cnt), Rect2(x, ly - 14, 34, 28), 14, app.TEXT if n < 0 else Color(0.1, 0.1, 0.15), true)
	# bar checkers
	for pl in 2:
		for k in bg_bar[pl]:
			app._draw_disc(Vector2(_bg_pt_x(5) + 48, 400.0 + (pl * 2 - 1) * (20.0 + k * 20.0)), 11, pl == 0)
	# dice
	for i in 2:
		var dr := Rect2(_bg_pt_x(6) + 20 + i * 54 - 28, 396, 44, 44)
		var used: bool = bg_moves_left.size() == 0
		app._draw_dice_face(dr, bg_dice[i], used)
	var rem: String = "—"
	if bg_moves_left.size() > 0:
		var parts: PackedStringArray = []
		for m in bg_moves_left:
			parts.append(app._fa(m))
		rem = " ، ".join(parts)
	app._txt_c("حرکت‌های باقی: " + rem, Rect2(0, 678, app.VIEW_W, 26), 14, app.TEXT_DIM, true)
