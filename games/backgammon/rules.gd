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
var bg_sel: int = -2
var bg_game_over: bool = false
var bg_winner: int = -1
var bg_legal_cache_key: String = ""
var bg_legal_cache: Array[Dictionary] = []

func reset_game() -> void:
	_reset_backgammon()

func _reset_backgammon() -> void:
	# Standard 15-checker start. Positive checkers are player 0 and move toward point 23;
	# negative checkers are player 1 and move toward point 0.
	bg_points = []
	for i in range(24):
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
	# Standard opening roll: each player rolls one die; the higher die starts
	# and both opening values are used as the first turn's dice. Ties reroll.
	var opening_dice: Array[int] = [randi_range(1, 6), randi_range(1, 6)]
	while opening_dice[0] == opening_dice[1]:
		opening_dice = [randi_range(1, 6), randi_range(1, 6)]
	bg_turn = 0 if opening_dice[0] > opening_dice[1] else 1
	bg_dice = [opening_dice[0], opening_dice[1]]
	bg_moves_left = _bg_expand_dice(bg_dice)
	bg_sel = -2
	bg_game_over = false
	bg_winner = -1
	_bg_invalidate_legal_cache()

func _bg_expand_dice(dice: Array) -> Array:
	var expanded: Array = [int(dice[0]), int(dice[1])]
	if int(dice[0]) == int(dice[1]):
		expanded = [int(dice[0]), int(dice[0]), int(dice[0]), int(dice[0])]
	return expanded

func _bg_roll() -> void:
	bg_dice = [randi() % 6 + 1, randi() % 6 + 1]
	bg_moves_left = _bg_expand_dice(bg_dice)
	bg_sel = -2
	_bg_invalidate_legal_cache()

func _bg_invalidate_legal_cache() -> void:
	bg_legal_cache_key = ""
	bg_legal_cache.clear()

func _bg_save_board() -> Dictionary:
	return {"points": bg_points.duplicate(), "bar": bg_bar.duplicate(), "off": bg_off.duplicate()}

func _bg_restore_board(snapshot: Dictionary) -> void:
	bg_points = snapshot["points"].duplicate()
	bg_bar = snapshot["bar"].duplicate()
	bg_off = snapshot["off"].duplicate()
	_bg_invalidate_legal_cache()

func _bg_all_home(player: int) -> bool:
	if player < 0 or player > 1 or int(bg_bar[player]) > 0:
		return false
	if player == 0:
		for point in range(18):
			if int(bg_points[point]) > 0:
				return false
	else:
		for point in range(6, 24):
			if int(bg_points[point]) < 0:
				return false
	return true

func _bg_can_land(player: int, target: int) -> bool:
	if target < 0 or target >= 24:
		return false
	if player == 0:
		return int(bg_points[target]) >= -1
	return int(bg_points[target]) <= 1

func _bg_legal_moves_for_die(player: int, die: int) -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	if player < 0 or player > 1 or die < 1 or die > 6:
		return moves
	var direction: int = 1 if player == 0 else -1
	if int(bg_bar[player]) > 0:
		var entry: int = 24 - die if player == 0 else die - 1
		if _bg_can_land(player, entry):
			moves.append({"source": -1, "target": entry, "die": die})
		return moves
	for source in range(24):
		var count: int = int(bg_points[source])
		if (player == 0 and count <= 0) or (player == 1 and count >= 0):
			continue
		var target: int = source + die * direction
		if target >= 0 and target < 24:
			if _bg_can_land(player, target):
				moves.append({"source": source, "target": target, "die": die})
			continue
		if not _bg_all_home(player):
			continue
		var exact_distance: int = 24 - source if player == 0 else source + 1
		var can_bear_off: bool = die == exact_distance
		if die > exact_distance:
			can_bear_off = true
			if player == 0:
				for farther in range(source + 1, 24):
					if int(bg_points[farther]) > 0:
						can_bear_off = false
						break
			else:
				for farther in range(0, source):
					if int(bg_points[farther]) < 0:
						can_bear_off = false
						break
		if can_bear_off:
			moves.append({"source": source, "target": -1, "die": die})
	return moves

func _bg_apply_board_move(player: int, move: Dictionary) -> void:
	var source: int = int(move.get("source", -2))
	var target: int = int(move.get("target", -2))
	var sign_value: int = 1 if player == 0 else -1
	if source == -1:
		bg_bar[player] = maxi(0, int(bg_bar[player]) - 1)
	elif source >= 0 and source < 24:
		bg_points[source] -= sign_value
	if target == -1:
		bg_off[player] = int(bg_off[player]) + 1
	elif target >= 0 and target < 24:
		if player == 0 and int(bg_points[target]) == -1:
			bg_points[target] = 0
			bg_bar[1] = int(bg_bar[1]) + 1
		elif player == 1 and int(bg_points[target]) == 1:
			bg_points[target] = 0
			bg_bar[0] = int(bg_bar[0]) + 1
		bg_points[target] += sign_value
	_bg_invalidate_legal_cache()

func _bg_search_best_prefix(player: int, dice: Array) -> Dictionary:
	if dice.is_empty():
		return {"used": 0, "moves": []}
	var best_used: int = 0
	var first_moves: Array[Dictionary] = []
	var seen_first: Dictionary = {}
	var unique_dice: Array[int] = []
	for value in dice:
		if int(value) not in unique_dice:
			unique_dice.append(int(value))
	for die in unique_dice:
		var legal: Array[Dictionary] = _bg_legal_moves_for_die(player, die)
		for move in legal:
			var snap: Dictionary = _bg_save_board()
			_bg_apply_board_move(player, move)
			var rest: Array = dice.duplicate()
			rest.erase(die)
			var tail: Dictionary = _bg_search_best_prefix(player, rest)
			_bg_restore_board(snap)
			var used: int = 1 + int(tail.get("used", 0))
			var key: String = "%d:%d:%d" % [int(move.source), int(move.target), int(move.die)]
			if used > best_used:
				best_used = used
				first_moves.clear()
				seen_first.clear()
			if used == best_used and not seen_first.has(key):
				seen_first[key] = true
				first_moves.append(move.duplicate(true))
	if best_used == 1 and dice.size() >= 2:
		var high: int = 0
		var low: int = 7
		for value in dice:
			high = maxi(high, int(value))
			low = mini(low, int(value))
		if high != low:
			var high_moves: Array[Dictionary] = _bg_legal_moves_for_die(player, high)
			if not high_moves.is_empty():
				first_moves = high_moves
	return {"used": best_used, "moves": first_moves}

func _bg_turn_legal_moves(player: int = -1) -> Array[Dictionary]:
	var active_player: int = bg_turn if player < 0 else player
	var key: String = "%s|%s|%s|%s|%s|%d" % [str(bg_points), str(bg_bar), str(bg_off), str(bg_moves_left), str(bg_dice), active_player]
	if key == bg_legal_cache_key:
		return bg_legal_cache.duplicate(true)
	var result: Dictionary = _bg_search_best_prefix(active_player, bg_moves_left.duplicate())
	bg_legal_cache_key = key
	bg_legal_cache = result.get("moves", []).duplicate(true)
	return bg_legal_cache.duplicate(true)

func _bg_move_exists(player: int, source: int, target: int, die: int) -> bool:
	for move in _bg_turn_legal_moves(player):
		if int(move.source) == source and int(move.target) == target and int(move.die) == die:
			return true
	return false

func _bg_cpu() -> void:
	if bg_game_over or not app.vs_cpu or bg_turn != 1:
		return
	# The human turn clears the dice when it hands control to the CPU. Roll only
	# in that case so a prepared CPU roll is never silently replaced.
	if bg_moves_left.is_empty():
		_bg_roll()
	var ai = BackgammonAIScript.new()
	var applied_count: int = 0
	while not bg_moves_left.is_empty() and applied_count < 4 and not bg_game_over:
		# The rules engine computes the exact set of first moves that preserves
		# maximum dice usage and the high-die rule. Never let a pruned AI branch
		# violate mandatory rules; evaluate only inside this legal set.
		var legal_turn_moves: Array[Dictionary] = _bg_turn_legal_moves(1)
		if legal_turn_moves.is_empty():
			break
		var plan: Array = ai.choose_turn(self, bg_difficulty)
		var chosen: Dictionary = {}
		if not plan.is_empty():
			var proposed: Dictionary = plan[0]
			for legal in legal_turn_moves:
				if int(legal.source) == int(proposed.get("source", -999)) and int(legal.target) == int(proposed.get("target", -999)) and int(legal.die) == int(proposed.get("die", -1)):
					chosen = legal.duplicate(true)
					break
		if chosen.is_empty():
			chosen = ai.choose_legal_first_move(self, legal_turn_moves, bg_difficulty)
		if chosen.is_empty():
			break
		var die: int = int(chosen.get("die", -1))
		var die_index: int = bg_moves_left.find(die)
		if die_index < 0:
			break
		_bg_apply_board_move(1, chosen)
		bg_moves_left.remove_at(die_index)
		_bg_invalidate_legal_cache()
		applied_count += 1
		if int(bg_off[1]) >= 15:
			bg_game_over = true
			bg_winner = 1
			bg_sel = -2
			app._go_result()
			return
	bg_moves_left.clear()
	bg_turn = 0
	bg_sel = -2
	_bg_roll()
	_bg_invalidate_legal_cache()

func _bg_cpu_apply_source(source: int, die: int) -> void:
	# Kept as a compatibility wrapper for older callers; new plans include targets.
	var target: int = die - 1 if source == -1 else source - die
	if source >= 0 and target < 0:
		target = -1
	_bg_apply_board_move(1, {"source": source, "target": target, "die": die})

func _bg_pt_x(col: int) -> float:
	return 40.0 + col * 36.0 + (24.0 if col >= 6 else 0.0)

func _bg_me() -> int:
	return app._my_seat()

func _bg_request_end_turn() -> void:
	if bg_game_over:
		return
	var seat: int = bg_turn
	if not _bg_turn_legal_moves(seat).is_empty():
		app._show_toast("هنوز حرکت قانونی با تاس‌های باقی‌مانده دارید.")
		return
	bg_sel = -2
	if app.vs_cpu and not app._net_on():
		bg_moves_left.clear()
		if seat == 0:
			bg_turn = 1
		else:
			bg_turn = 0
			_bg_roll()
		_bg_invalidate_legal_cache()
		return
	if app._net_on():
		var d1: int = randi_range(1, 6)
		var d2: int = randi_range(1, 6)
		app._send_game_action("_rpc_bg_end_turn", [seat, d1, d2])
		return
	bg_moves_left.clear()
	bg_turn = 1 - seat
	_bg_roll()
	_bg_invalidate_legal_cache()

func _bg_end_turn_apply(seat: int, d1: int, d2: int) -> bool:
	if bg_game_over or seat != bg_turn or d1 < 1 or d1 > 6 or d2 < 1 or d2 > 6:
		return false
	if not _bg_turn_legal_moves(seat).is_empty():
		return false
	bg_turn = 1 - seat
	bg_dice = [d1, d2]
	bg_moves_left = _bg_expand_dice(bg_dice)
	bg_sel = -2
	_bg_invalidate_legal_cache()
	return true

func _bg_commit_human_move(move: Dictionary) -> void:
	if bg_game_over or int(move.get("die", -1)) not in bg_moves_left:
		return
	_bg_apply_board_move(bg_turn, move)
	bg_moves_left.remove_at(bg_moves_left.find(int(move.die)))
	bg_sel = -2
	if int(bg_off[bg_turn]) >= 15:
		bg_game_over = true
		bg_winner = bg_turn
		app._go_result()
		return
	_bg_invalidate_legal_cache()
	if bg_moves_left.is_empty() or _bg_turn_legal_moves(bg_turn).is_empty():
		# Only the host finishes an online turn. Clients wait for the authoritative roll.
		if not app._net_on() or app.is_host:
			_bg_request_end_turn()

func _bg_apply_net_move(seat: int, source: int, target: int, die: int) -> void:
	if bg_game_over or seat != bg_turn or die not in bg_moves_left:
		return
	var valid: bool = false
	for move in _bg_turn_legal_moves(seat):
		if int(move.source) == source and int(move.target) == target and int(move.die) == die:
			valid = true
			_bg_commit_human_move(move)
			break
	if not valid:
		return

func _bg_step() -> void:
	_bg_request_end_turn()

func _bg_step_apply(d1: int, d2: int) -> void:
	# Legacy action compatibility. Modern turns are advanced only when the player has no legal moves.
	if d1 >= 1 and d1 <= 6 and d2 >= 1 and d2 <= 6:
		_bg_end_turn_apply(bg_turn, d1, d2)
	else:
		_bg_request_end_turn()

func _bg_point_from_tap(p: Vector2) -> int:
	# The centre channel contains the bar; lower-row points are visually mirrored so
	# adjacent point numbers are adjacent around the perimeter, as on a standard board.
	if p.x >= 244.0 and p.x <= 280.0 and p.y >= 338.0 and p.y <= 500.0:
		return -1
	if p.y < 338.0 or p.y > 500.0:
		return -2
	var col: int = -1
	for candidate in range(12):
		var x0: float = _bg_pt_x(candidate) - 2.0
		if p.x >= x0 and p.x <= x0 + 36.0:
			col = candidate
			break
	if col < 0:
		return -2
	return col if p.y < 420.0 else 23 - col

func _bg_tap(p: Vector2) -> void:
	if bg_game_over or app._ov_active() or (app.vs_cpu and bg_turn == 1):
		return
	if app._net_on() and bg_turn != _bg_me():
		return
	var clicked: int = _bg_point_from_tap(p)
	var sign_value: int = 1 if bg_turn == 0 else -1
	if clicked == -1:
		if int(bg_bar[bg_turn]) > 0 and not _bg_turn_legal_moves(bg_turn).is_empty():
			bg_sel = -1
			app._rebuild_buttons()
		return
	if clicked < 0:
		return
	if bg_sel != -2:
		var legal_moves: Array[Dictionary] = _bg_turn_legal_moves(bg_turn)
		var destinations: Array[Dictionary] = []
		for move in legal_moves:
			if int(move.source) == bg_sel and int(move.target) == clicked:
				destinations.append(move)
		if not destinations.is_empty():
			# Same source/destination can occur only during bearing off; normal destinations uniquely imply a die.
			var chosen: Dictionary = destinations[0]
			for option in destinations:
				if int(option.die) > int(chosen.die):
					chosen = option
			if app._net_on():
				app._send_game_action("_rpc_bg_move", [bg_turn, int(chosen.source), int(chosen.target), int(chosen.die)])
			else:
				_bg_commit_human_move(chosen)
			app._rebuild_buttons()
			return
	var point_value: int = int(bg_points[clicked])
	if int(bg_bar[bg_turn]) > 0:
		app._show_toast("ابتدا مهره‌ی روی بار را وارد کنید.")
		return
	if (bg_turn == 0 and point_value > 0) or (bg_turn == 1 and point_value < 0):
		bg_sel = -2 if bg_sel == clicked else clicked
		app._rebuild_buttons()
	else:
		app._show_toast("ابتدا مهره‌ی خود را انتخاب کنید، سپس خانه‌ی مقصد را بزنید.")

func _bg_bear_off_selected() -> void:
	if bg_sel < -1 or bg_sel >= 24 or bg_game_over or (app.vs_cpu and bg_turn == 1):
		return
	var choices: Array[Dictionary] = []
	for move in _bg_turn_legal_moves(bg_turn):
		if int(move.source) == bg_sel and int(move.target) == -1:
			choices.append(move)
	if choices.is_empty():
		app._show_toast("این مهره هنوز نمی‌تواند از صفحه خارج شود.")
		return
	var chosen: Dictionary = choices[0]
	for option in choices:
		if int(option.die) > int(chosen.die):
			chosen = option
	if app._net_on():
		app._send_game_action("_rpc_bg_move", [bg_turn, int(chosen.source), -1, int(chosen.die)])
	else:
		_bg_commit_human_move(chosen)
	app._rebuild_buttons()

func _btns_backgammon() -> void:
	if bg_game_over:
		return
	var mine: bool = bg_turn == _bg_me() and not (app.vs_cpu and bg_turn == 1)
	var legal: Array[Dictionary] = _bg_turn_legal_moves(bg_turn)
	var can_bear: bool = false
	if bg_sel != -2:
		for move in legal:
			if int(move.source) == bg_sel and int(move.target) == -1:
				can_bear = true
				break
	if can_bear:
		app._add_btn(Rect2(110, 714, app.VIEW_W - 220, 58), "خارج کردن مهره", _bg_bear_off_selected, mine, app.GREEN, "solid", "check", "bg_bear_off")
	else:
		var label: String = "پایان نوبت" if legal.is_empty() else "انتخاب مهره و مقصد"
		app._add_btn(Rect2(110, 714, app.VIEW_W - 220, 58), label, _bg_step, mine and legal.is_empty(), app.GREEN if legal.is_empty() else app.TEXT_DIM, "solid" if legal.is_empty() else "ghost", "check" if legal.is_empty() else "mouse-pointer", "bg_step")

func _draw_backgammon() -> void:
	var me: int = _bg_me()
	var pa: Dictionary = app._pl("شما", Color(0.96, 0.93, 0.84) if me == 0 else Color(0.12, 0.13, 0.18), app._fa(bg_off[me]), bg_turn == me and not bg_game_over, true, "خارج‌شده", 1 if me == 0 else 0)
	var opponent_name: String = "CPU" if app.vs_cpu else "حریف"
	var pb: Dictionary = app._pl(opponent_name, Color(0.12, 0.13, 0.18) if me == 0 else Color(0.96, 0.93, 0.84), app._fa(bg_off[1 - me]), bg_turn == 1 - me and not bg_game_over, false, "خارج‌شده", 0 if me == 0 else 1)
	if pa.active:
		pa.sub = "نوبت شما"
	var title: String = "تخته‌نرد"
	if app.vs_cpu:
		var levels: Array[String] = ["خیلی آسان", "آسان", "متوسط", "سخت", "استاد", "استادتمام"]
		title += " · " + levels[clampi(bg_difficulty, 1, 6) - 1]
	app._draw_hud(title, pa, pb)
	var board := Rect2(25, 170, 490, 500)
	app._panel(board, Color(0.30, 0.18, 0.10), 22, Color(0.8, 0.55, 0.3, 0.5), 2.0, 20, 8)
	app._panel(board.grow(-8), Color(0.12, 0.30, 0.24), 16)
	app._panel(Rect2(_bg_pt_x(5) + 36, 178, 24, 484), Color(0.30, 0.18, 0.10), 6)
	var selected_targets: Dictionary = {}
	if bg_sel != -2:
		for move in _bg_turn_legal_moves(bg_turn):
			if int(move.source) == bg_sel and int(move.target) >= 0:
				selected_targets[int(move.target)] = true
	for i in range(24):
		var top: bool = i < 12
		var col_i: int = i if top else 23 - i
		var x: float = _bg_pt_x(col_i)
		var y0: float = 180.0 if top else 660.0
		var tipy: float = y0 + (150.0 if top else -150.0)
		var tcol: Color = Color(0.92, 0.70, 0.42) if (col_i + (0 if top else 1)) % 2 == 0 else Color(0.62, 0.22, 0.22)
		app.draw_colored_polygon(PackedVector2Array([Vector2(x, y0), Vector2(x + 34, y0), Vector2(x + 17, tipy)]), tcol)
		var n: int = int(bg_points[i])
		var cnt: int = absi(n)
		for k in range(mini(cnt, 5)):
			var cy: float = (y0 + 18.0 + k * 27.0) if top else (y0 - 18.0 - k * 27.0)
			app._draw_disc(Vector2(x + 17, cy), 13.5, n > 0)
		if cnt > 5:
			var ly: float = (y0 + 18.0 + 4 * 27.0) if top else (y0 - 18.0 - 4 * 27.0)
			app._txt_c(app._fa(cnt), Rect2(x, ly - 14, 34, 28), 14, app.TEXT if n < 0 else Color(0.1, 0.1, 0.15), true)
		var triangle_center: Vector2 = Vector2(x + 17.0, tipy - 8.0 if top else tipy + 8.0)
		if i == bg_sel:
			app._ring(triangle_center, 15.0, app.ACCENT, 2.5)
		if selected_targets.has(i):
			app.draw_circle(triangle_center, 7.0, Color(app.GREEN.r, app.GREEN.g, app.GREEN.b, 0.78))
			app._ring(triangle_center, 11.0, app.GREEN, 1.7)
	# Bar checkers. Click the central channel to select a checker there when required.
	for player in range(2):
		for k in range(mini(int(bg_bar[player]), 5)):
			var center := Vector2(_bg_pt_x(5) + 48.0, 400.0 + (float(player) * 2.0 - 1.0) * (20.0 + float(k) * 20.0))
			app._draw_disc(center, 11.0, player == 0)
		if bg_sel == -1 and int(bg_bar[bg_turn]) > 0:
			app._ring(Vector2(_bg_pt_x(5) + 48.0, 400.0 + (float(bg_turn) * 2.0 - 1.0) * 20.0), 15.0, app.ACCENT, 2.0)
	# Dice and remaining playable values.
	for i in range(2):
		var dr := Rect2(_bg_pt_x(6) + 20 + i * 54 - 28, 396, 44, 44)
		var used: bool = bg_moves_left.is_empty()
		app._draw_dice_face(dr, int(bg_dice[i]), used)
	var rem: String = "—"
	if not bg_moves_left.is_empty():
		var parts: PackedStringArray = []
		for value in bg_moves_left:
			parts.append(app._fa(int(value)))
		rem = " ، ".join(parts)
	app._txt_c("تاس‌های باقی: " + rem, Rect2(0, 678, app.VIEW_W, 26), 14, app.TEXT_DIM, true)
	var help: String = "مهره‌ی خود را انتخاب کنید، سپس مقصد را بزنید" if bg_sel == -2 else "خانه‌های سبز مقصدهای مجازند"
	if int(bg_bar[bg_turn]) > 0 and not (app.vs_cpu and bg_turn == 1):
		help = "ابتدا مهره‌ی روی بار را وارد کنید"
	app._txt_c(help, Rect2(16, 682, app.VIEW_W - 32, 24), 11, app.ACCENT if bg_sel != -2 else app.TEXT_DIM, false)

