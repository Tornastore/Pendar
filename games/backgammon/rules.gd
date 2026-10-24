extends "res://core/game_module.gd"
## Rule engine and authoritative state for backgammon.

const BackgammonAIScript = preload("res://games/backgammon/ai.gd")
const BackgammonPresentationScript = preload("res://games/backgammon/presentation.gd")

var _presentation = BackgammonPresentationScript.new()

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

# Turn UX state. Dice stay concealed until a roll is requested; both dice and
# checker movements animate before their results are committed to the board.
const ROLL_ANIM_SECONDS: float = 0.95
const MOVE_ANIM_SECONDS: float = 0.46
var _bg_needs_roll: bool = true
var _bg_opening_roll: bool = true
var _bg_roll_animating: bool = false
var _bg_roll_started_at: float = 0.0
var _bg_roll_result: Array = [0, 0]
var _bg_roll_player: int = -1
var _bg_roll_serial: int = 0
var _bg_cpu_busy: bool = false
var _bg_animating_move: bool = false
var _bg_move_anim_started_at: float = 0.0
var _bg_anim_move: Dictionary = {}
var _bg_last_move: Dictionary = {}
var _bg_move_choice_pending: Array[Dictionary] = []
var _bg_combined_hint_cache_key: String = ""
var _bg_combined_hint_cache: Array[Dictionary] = []

func reset_game() -> void:
	_reset_backgammon()

func _reset_backgammon() -> void:
	# Standard 15-checker start. The view maps this route so seat 0's home board
	# is at bottom-right and its increasing point indices move toward that corner.
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
	# Opening roll is player-triggered. The winner of the unequal dice starts,
	# and those two values are also the first turn's dice.
	bg_turn = 0
	bg_dice = [0, 0]
	bg_moves_left = []
	bg_sel = -2
	bg_game_over = false
	bg_winner = -1
	_bg_needs_roll = true
	_bg_opening_roll = true
	_bg_roll_animating = false
	_bg_roll_started_at = 0.0
	_bg_roll_result = [0, 0]
	_bg_roll_player = -1
	_bg_roll_serial += 1
	_bg_cpu_busy = false
	_bg_animating_move = false
	_bg_move_anim_started_at = 0.0
	_bg_anim_move = {}
	_bg_last_move = {}
	_bg_move_choice_pending.clear()
	_bg_invalidate_legal_cache()

func _bg_roll() -> void:
	# Compatibility entry point: a roll is now animated and user-visible.
	_bg_roll_button()

func _bg_roll_button() -> void:
	if bg_game_over or _bg_roll_animating or _bg_animating_move or not _bg_needs_roll:
		return
	if app.vs_cpu and bg_turn == 1:
		return
	if app._net_on() and not _bg_opening_roll and bg_turn != _bg_me():
		return
	var dice: Array = [randi_range(1, 6), randi_range(1, 6)]
	if _bg_opening_roll:
		while int(dice[0]) == int(dice[1]):
			dice = [randi_range(1, 6), randi_range(1, 6)]
	_bg_play_roll_animation(int(dice[0]), int(dice[1]), _bg_opening_roll)

func _bg_play_roll_animation(d1: int, d2: int, opening: bool) -> void:
	if bg_game_over or _bg_roll_animating:
		return
	_bg_roll_serial += 1
	var serial: int = _bg_roll_serial
	var game_epoch: int = int(app._game_epoch)
	_bg_roll_animating = true
	_bg_roll_started_at = float(Time.get_ticks_msec()) / 1000.0
	_bg_roll_result = [d1, d2]
	_bg_roll_player = bg_turn
	_bg_needs_roll = true
	bg_dice = [0, 0]
	bg_moves_left = []
	bg_sel = -2
	_bg_move_choice_pending.clear()
	_bg_invalidate_legal_cache()
	app._rebuild_buttons()
	await app.get_tree().create_timer(ROLL_ANIM_SECONDS).timeout
	if serial != _bg_roll_serial or game_epoch != int(app._game_epoch) or str(app.selected_game) != "backgammon" or bg_game_over:
		return
	_bg_roll_animating = false
	bg_dice = [d1, d2]
	if opening:
		bg_turn = 0 if d1 > d2 else 1
		_bg_opening_roll = false
	_bg_roll_player = bg_turn
	bg_moves_left = _bg_expand_dice(bg_dice)
	_bg_needs_roll = false
	bg_sel = -2
	_bg_invalidate_legal_cache()
	app._rebuild_buttons()
	# A human can review a blocked roll and explicitly pass. CPU passes after its
	# short visible result pause so the turn does not stall.
	if app.vs_cpu and bg_turn == 1 and _bg_turn_legal_moves(bg_turn).is_empty():
		await app.get_tree().create_timer(0.55).timeout
		if not bg_game_over and bg_turn == 1 and not _bg_needs_roll:
			_bg_request_end_turn()

func _bg_expand_dice(dice: Array) -> Array:
	var expanded: Array = [int(dice[0]), int(dice[1])]
	if int(dice[0]) == int(dice[1]):
		expanded = [int(dice[0]), int(dice[0]), int(dice[0]), int(dice[0])]
	return expanded

func _bg_invalidate_legal_cache() -> void:
	bg_legal_cache_key = ""
	bg_legal_cache.clear()
	_bg_combined_hint_cache_key = ""
	_bg_combined_hint_cache.clear()

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
		var entry: int = die - 1 if player == 0 else 24 - die
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
	if bg_game_over or not app.vs_cpu or bg_turn != 1 or _bg_cpu_busy or _bg_roll_animating or _bg_animating_move:
		return
	_bg_cpu_busy = true
	if _bg_needs_roll:
		var cpu_dice: Array = [randi_range(1, 6), randi_range(1, 6)]
		await _bg_play_roll_animation(int(cpu_dice[0]), int(cpu_dice[1]), false)
	if bg_game_over or bg_turn != 1:
		_bg_cpu_busy = false
		return
	var ai = BackgammonAIScript.new()
	var applied_count: int = 0
	while not bg_moves_left.is_empty() and applied_count < 4 and not bg_game_over:
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
		if die not in bg_moves_left:
			break
		await _bg_commit_human_move(chosen, false)
		applied_count += 1
		if int(bg_off[1]) >= 15:
			bg_game_over = true
			bg_winner = 1
			bg_sel = -2
			_bg_cpu_busy = false
			app._go_result()
			return
	# Handoff to the human. The old CPU dice remain in last-move history but the
	# current dice faces are blank until the next explicit roll.
	bg_moves_left.clear()
	bg_turn = 0
	_bg_needs_roll = true
	bg_sel = -2
	_bg_move_choice_pending.clear()
	_bg_cpu_busy = false
	_bg_invalidate_legal_cache()
	app._rebuild_buttons()

func _bg_cpu_apply_source(source: int, die: int) -> void:
	# Kept as a compatibility wrapper for older callers; new plans include targets.
	var target: int = 24 - die if source == -1 else source - die
	if source >= 0 and target < 0:
		target = -1
	_bg_apply_board_move(1, {"source": source, "target": target, "die": die})

func _bg_pt_x(col: int) -> float:
	# Compatibility wrapper; board geometry belongs to the presentation module.
	return _presentation.point_x(col)

func _bg_me() -> int:
	return app._my_seat()

func _bg_request_end_turn() -> void:
	if bg_game_over or _bg_roll_animating or _bg_animating_move:
		return
	var seat: int = bg_turn
	if not _bg_turn_legal_moves(seat).is_empty():
		app._show_toast("هنوز حرکت قانونی با تاس‌های باقی‌مانده دارید.")
		return
	bg_sel = -2
	_bg_move_choice_pending.clear()
	if app.vs_cpu and not app._net_on():
		bg_moves_left.clear()
		bg_turn = 1 - seat
		_bg_needs_roll = true
		_bg_invalidate_legal_cache()
		app._rebuild_buttons()
		return
	if app._net_on():
		# Legacy network turn packet carries the next player's result. The receiver
		# plays it through the same visible roll animation before allowing moves.
		var d1: int = randi_range(1, 6)
		var d2: int = randi_range(1, 6)
		app._send_game_action("_rpc_bg_end_turn", [seat, d1, d2])
		return
	bg_moves_left.clear()
	bg_turn = 1 - seat
	_bg_needs_roll = true
	_bg_invalidate_legal_cache()
	app._rebuild_buttons()

func _bg_end_turn_apply(seat: int, d1: int, d2: int) -> bool:
	if bg_game_over or seat != bg_turn or d1 < 1 or d1 > 6 or d2 < 1 or d2 > 6:
		return false
	if not _bg_turn_legal_moves(seat).is_empty():
		return false
	bg_turn = 1 - seat
	bg_dice = [0, 0]
	bg_moves_left.clear()
	_bg_needs_roll = true
	bg_sel = -2
	_bg_invalidate_legal_cache()
	_bg_play_roll_animation(d1, d2, false)
	return true

func _bg_commit_human_move(move: Dictionary, allow_turn_handoff: bool = true) -> void:
	if bg_game_over or _bg_needs_roll or _bg_roll_animating or _bg_animating_move or int(move.get("die", -1)) not in bg_moves_left:
		return
	var player: int = bg_turn
	var authorized: bool = false
	for legal in _bg_turn_legal_moves(player):
		if int(legal.source) == int(move.get("source", -99)) and int(legal.target) == int(move.get("target", -99)) and int(legal.die) == int(move.get("die", -1)):
			authorized = true
			break
	if not authorized:
		return
	_bg_animating_move = true
	_bg_move_anim_started_at = float(Time.get_ticks_msec()) / 1000.0
	var game_epoch: int = int(app._game_epoch)
	_bg_anim_move = move.duplicate(true)
	_bg_anim_move["player"] = player
	_bg_move_choice_pending.clear()
	app._rebuild_buttons()
	await app.get_tree().create_timer(MOVE_ANIM_SECONDS).timeout
	if game_epoch != int(app._game_epoch) or str(app.selected_game) != "backgammon" or bg_game_over or bg_turn != player:
		_bg_animating_move = false
		_bg_anim_move = {}
		return
	_bg_animating_move = false
	_bg_anim_move = {}
	_bg_last_move = move.duplicate(true)
	_bg_last_move["player"] = player
	_bg_apply_board_move(player, move)
	var die_index: int = bg_moves_left.find(int(move.die))
	if die_index >= 0:
		bg_moves_left.remove_at(die_index)
	bg_sel = -2
	_bg_invalidate_legal_cache()
	if int(bg_off[player]) >= 15:
		bg_game_over = true
		bg_winner = player
		app._go_result()
		return
	app._rebuild_buttons()
	if allow_turn_handoff and (bg_moves_left.is_empty() or _bg_turn_legal_moves(bg_turn).is_empty()):
		# Only the host finishes an online turn. Clients wait for the authoritative roll.
		if not app._net_on() or app.is_host:
			_bg_request_end_turn()

func _bg_apply_net_move(seat: int, source: int, target: int, die: int) -> void:
	if bg_game_over or _bg_animating_move or _bg_roll_animating or _bg_needs_roll or seat != bg_turn or die not in bg_moves_left:
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
	# Keep the old entry point for input dispatch while keeping geometry out of rules.
	return _presentation.point_from_tap(p)

func _bg_tap(p: Vector2) -> void:
	if bg_game_over or app._ov_active() or _bg_needs_roll or _bg_roll_animating or _bg_animating_move or not _bg_move_choice_pending.is_empty() or (app.vs_cpu and bg_turn == 1):
		return
	if app._net_on() and bg_turn != _bg_me():
		return
	var clicked: int = _bg_point_from_tap(p)
	var sign_value: int = 1 if bg_turn == 0 else -1
	if clicked == -1:
		if int(bg_bar[bg_turn]) > 0 and not _bg_turn_legal_moves(bg_turn).is_empty():
			bg_sel = -1
			_bg_move_choice_pending.clear()
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
			var unique: Array[Dictionary] = []
			var seen_options: Dictionary = {}
			for option in destinations:
				var option_key: String = "%d:%d:%d" % [int(option.source), int(option.target), int(option.die)]
				if not seen_options.has(option_key):
					seen_options[option_key] = true
					unique.append(option.duplicate(true))
			if unique.size() > 1:
				_bg_move_choice_pending = unique
				app._rebuild_buttons()
				return
			var chosen: Dictionary = unique[0]
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
		_bg_move_choice_pending.clear()
		app._rebuild_buttons()
	else:
		app._show_toast("ابتدا مهره‌ی خود را انتخاب کنید، سپس خانه‌ی مقصد را بزنید.")

func _bg_bear_off_selected() -> void:
	if bg_sel < -1 or bg_sel >= 24 or bg_game_over or _bg_needs_roll or _bg_roll_animating or _bg_animating_move or (app.vs_cpu and bg_turn == 1):
		return
	var choices: Array[Dictionary] = []
	for move in _bg_turn_legal_moves(bg_turn):
		if int(move.source) == bg_sel and int(move.target) == -1:
			choices.append(move)
	if choices.is_empty():
		app._show_toast("این مهره هنوز نمی‌تواند از صفحه خارج شود.")
		return
	if choices.size() > 1:
		_bg_move_choice_pending = choices.duplicate(true)
		app._rebuild_buttons()
		return
	var chosen: Dictionary = choices[0]
	if app._net_on():
		app._send_game_action("_rpc_bg_move", [bg_turn, int(chosen.source), -1, int(chosen.die)])
	else:
		_bg_commit_human_move(chosen)
	app._rebuild_buttons()

func _bg_choose_pending_move(index: int) -> void:
	if index < 0 or index >= _bg_move_choice_pending.size() or bg_game_over or _bg_roll_animating or _bg_animating_move:
		return
	var chosen: Dictionary = _bg_move_choice_pending[index].duplicate(true)
	_bg_move_choice_pending.clear()
	if app._net_on():
		app._send_game_action("_rpc_bg_move", [bg_turn, int(chosen.source), int(chosen.target), int(chosen.die)])
	else:
		_bg_commit_human_move(chosen)
	app._rebuild_buttons()

func _bg_cancel_pending_move() -> void:
	_bg_move_choice_pending.clear()
	app._rebuild_buttons()

func _btns_backgammon() -> void:
	if bg_game_over:
		return
	var mine: bool = bg_turn == _bg_me() and not (app.vs_cpu and bg_turn == 1)
	if _bg_animating_move:
		app._add_btn(Rect2(70, 714, app.VIEW_W - 140, 58), "مهره در حال حرکت است…", _bg_step, false, app.ACCENT, "solid", "loader", "bg_move_animating")
		return
	if not _bg_move_choice_pending.is_empty():
		app._add_btn(Rect2(18, 714, 362, 58), "لغو انتخاب تاس", _bg_cancel_pending_move, mine, app.TEXT_DIM, "ghost", "x", "bg_cancel_move_choice")
		for i in range(_bg_move_choice_pending.size()):
			var move: Dictionary = _bg_move_choice_pending[i]
			var from_label: String = "بار" if int(move.source) == -1 else str(24 - int(move.source))
			var to_label: String = "خارج" if int(move.target) == -1 else str(24 - int(move.target))
			var label: String = "تاس " + app._fa(int(move.die)) + " · " + to_label + " ← " + from_label
			app._add_btn(Rect2(18 + i * 128, 780, 122, 48), label, _bg_choose_pending_move.bind(i), mine, app.ACCENT, "solid", "dice", "bg_move_choice_%d" % i)
		return
	if _bg_roll_animating:
		app._add_btn(Rect2(70, 714, app.VIEW_W - 140, 58), "تاس‌ها در حال چرخش‌اند…", _bg_roll_button, false, app.ACCENT, "solid", "dice", "_bg_roll_animating")
		return
	if _bg_needs_roll:
		var label: String = "ریختن تاس آغازین" if _bg_opening_roll else "ریختن تاس"
		if app.vs_cpu and bg_turn == 1:
			label = "نوبت CPU · ریختن تاس…"
		elif not mine:
			label = "منتظر نوبت حریف…"
		app._add_btn(Rect2(70, 714, app.VIEW_W - 140, 58), label, _bg_roll_button, mine, app.ACCENT, "solid", "dice", "bg_roll_button")
		return
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

func _bg_combined_move_hints(source: int) -> Array[Dictionary]:
	# Return only real two-step sequences for the same checker. The purple result
	# is a preview, not a direct move: each die must still be played separately.
	var hints: Array[Dictionary] = []
	if source < -1 or source >= 24 or _bg_needs_roll or _bg_roll_animating or bg_moves_left.size() < 2:
		return hints
	var hint_key: String = "%d|%d|%s|%s|%s|%s" % [source, bg_turn, str(bg_points), str(bg_bar), str(bg_off), str(bg_moves_left)]
	if hint_key == _bg_combined_hint_cache_key:
		return _bg_combined_hint_cache.duplicate(true)
	var first_moves: Array[Dictionary] = _bg_turn_legal_moves(bg_turn)
	var snapshot_key: String = bg_legal_cache_key
	var snapshot_cache: Array[Dictionary] = bg_legal_cache.duplicate(true)
	var seen: Dictionary = {}
	for first in first_moves:
		if int(first.source) != source or int(first.target) < 0:
			continue
		var remaining: Array = bg_moves_left.duplicate()
		var first_die_index: int = remaining.find(int(first.die))
		if first_die_index < 0:
			continue
		remaining.remove_at(first_die_index)
		var board_snapshot: Dictionary = _bg_save_board()
		_bg_apply_board_move(bg_turn, first)
		var tail: Dictionary = _bg_search_best_prefix(bg_turn, remaining)
		for second in tail.get("moves", []):
			if int(second.source) != int(first.target):
				continue
			var route_key: String = "%d:%d:%d:%d" % [int(first.target), int(second.target), int(first.die), int(second.die)]
			if seen.has(route_key):
				continue
			seen[route_key] = true
			hints.append({"source": source, "via": int(first.target), "target": int(second.target), "first_die": int(first.die), "second_die": int(second.die)})
		_bg_restore_board(board_snapshot)
	# Search helpers invalidate their cache while simulating; restore the live-turn cache.
	bg_legal_cache_key = snapshot_key
	bg_legal_cache = snapshot_cache
	_bg_combined_hint_cache_key = hint_key
	_bg_combined_hint_cache = hints.duplicate(true)
	return hints

func _draw_backgammon() -> void:
	# Keep main.gd's existing dispatch stable; rendering lives in presentation.gd.
	_presentation.render(app, self)
