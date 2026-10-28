extends "res://core/game_module.gd"
## A playable, deterministic digital Jenga ruleset. Each level has three slots; -1 means empty.
const PresentationScript = preload("res://games/jenga/presentation.gd")
var _presentation = PresentationScript.new()

var jenga_layers: Array = []
var jenga_turn: int = 0
var jenga_player_count: int = 2
var jenga_difficulty: int = 3
var jenga_phase: String = "remove"
var jenga_pending_piece: Dictionary = {}
var jenga_game_over: bool = false
var jenga_winner: int = -1
var jenga_last_successful_seat: int = -1
var jenga_moves: int = 0
var jenga_status: String = ""

func reset_game() -> void:
	_reset_jenga()

func _reset_jenga() -> void:
	jenga_player_count = clampi(jenga_player_count, 2, 4)
	jenga_layers = []
	for _level in range(18):
		jenga_layers.append([true, true, true])
	jenga_turn = 0
	jenga_phase = "remove"
	jenga_pending_piece = {}
	jenga_game_over = false
	jenga_winner = -1
	jenga_last_successful_seat = -1
	jenga_moves = 0
	jenga_status = "بلوک را از زیر بالاترین طبقهٔ کامل بیرون بکشید."
	if app != null:
		app._rebuild_buttons()

func _jenga_my_turn() -> bool:
	if jenga_game_over:
		return false
	return jenga_turn == (0 if app.vs_cpu else app.local_seat)

func _jenga_highest_complete_layer() -> int:
	for level in range(jenga_layers.size() - 1, -1, -1):
		var layer: Array = jenga_layers[level]
		if bool(layer[0]) and bool(layer[1]) and bool(layer[2]):
			return level
	return -1

func _jenga_legal_removal(level: int, slot: int) -> bool:
	if jenga_game_over or jenga_phase != "remove" or level < 0 or level >= jenga_layers.size() or slot < 0 or slot > 2:
		return false
	var highest: int = _jenga_highest_complete_layer()
	if highest < 1 or level >= highest:
		return false
	if not bool(jenga_layers[level][slot]):
		return false
	# A level already missing two blocks is structurally too weak to remove from.
	var remaining: int = 0
	for present in jenga_layers[level]:
		if bool(present):
			remaining += 1
	return remaining >= 2

func _jenga_legal_place_slots() -> Array[int]:
	var result: Array[int] = []
	if jenga_phase != "place" or jenga_game_over:
		return result
	var top: Array = jenga_layers[jenga_layers.size() - 1]
	for slot in range(3):
		if not bool(top[slot]):
			result.append(slot)
	return result

func _jenga_submit_remove(level: int, slot: int) -> void:
	if not _jenga_my_turn() or not _jenga_legal_removal(level, slot):
		return
	var seat: int = 0 if app.vs_cpu else app.local_seat
	var roll: float = randf()
	if app._net_on():
		app._send_game_action("_rpc_jenga_action", [seat, "remove", level, slot, roll])
	else:
		_jenga_apply_action(seat, "remove", level, slot, roll)
		if app.vs_cpu and not jenga_game_over:
			app._schedule_cpu(0.35, _jenga_cpu_turn)

func _jenga_submit_place(slot: int) -> void:
	if not _jenga_my_turn() or jenga_phase != "place" or slot < 0 or slot > 2 or slot not in _jenga_legal_place_slots():
		return
	var seat: int = 0 if app.vs_cpu else app.local_seat
	if app._net_on():
		app._send_game_action("_rpc_jenga_action", [seat, "place", jenga_layers.size() - 1, slot, 0.0])
	else:
		_jenga_apply_action(seat, "place", jenga_layers.size() - 1, slot, 0.0)

func _jenga_layer_count(level: int) -> int:
	if level < 0 or level >= jenga_layers.size():
		return 0
	var count: int = 0
	for piece in jenga_layers[level]:
		if bool(piece):
			count += 1
	return count


func _jenga_risk(level: int, slot: int) -> float:
	if level < 0 or level >= jenga_layers.size() or slot < 0 or slot > 2:
		return 0.78
	var remaining: int = _jenga_layer_count(level)
	# A compact probabilistic model: lower layers bear more weight, and weak
	# neighboring support layers make a pull riskier. This is a rules heuristic,
	# not a claim of rigid-body physics simulation.
	var risk: float = 0.025 + float(maxi(0, 5 - level)) * 0.045
	var load_above: int = maxi(0, jenga_layers.size() - level - 1)
	risk += minf(0.12, float(load_above) * 0.004)
	if remaining == 2:
		risk += 0.055
	elif remaining == 1:
		risk += 0.42
	if slot == 1 and remaining == 3:
		risk += 0.012
	if level > 0:
		var support_count: int = _jenga_layer_count(level - 1)
		if support_count == 1:
			risk += 0.10
		elif support_count == 2:
			risk += 0.035
	return clampf(risk, 0.01, 0.78)


func _jenga_future_min_risk(candidate: Vector2i) -> float:
	# Estimate the next player's safest legal pull after this block is removed.
	# Restore the live board immediately; no search branch may leak state.
	var old_value: bool = bool(jenga_layers[candidate.x][candidate.y])
	jenga_layers[candidate.x][candidate.y] = false
	var best_future: float = 999.0
	for level in range(jenga_layers.size()):
		for slot in range(3):
			if _jenga_legal_removal(level, slot):
				best_future = minf(best_future, _jenga_risk(level, slot))
	jenga_layers[candidate.x][candidate.y] = old_value
	return 0.0 if best_future == 999.0 else best_future


func _jenga_candidate_score(candidate: Vector2i, level: int) -> float:
	var layer_count: int = _jenga_layer_count(candidate.x)
	var score: float = _jenga_risk(candidate.x, candidate.y) * 100.0
	# Leaving a one-block layer forces future turns downward to a weaker level.
	if layer_count == 2:
		score += 5.0 if level <= 2 else 2.0
	# Levels 4–6 consider whether the move leaves the next player a harder pull.
	if level >= 4:
		var pressure_weight: float = 18.0 if level == 4 else (24.0 if level == 5 else 30.0)
		score -= _jenga_future_min_risk(candidate) * pressure_weight
	return score


func _jenga_choose_slot(options: Array[int]) -> int:
	if options.is_empty():
		return -1
	var level: int = clampi(jenga_difficulty, 1, 6)
	if level == 1:
		return int(options.pick_random())
	var best_slot: int = int(options[0])
	var best_score: float = 9999.0
	for slot in options:
		var score: float = 0.0
		# Prefer balancing the new top row at lower levels; stronger levels make
		# a deterministic placement that keeps the upper stack centered.
		if level <= 3:
			score = absf(float(slot) - 1.0) * 0.30
			score += randf_range(-0.45, 0.45) if level == 2 else (randf_range(-0.12, 0.12) if level == 3 else 0.0)
		else:
			score = absf(float(slot) - 1.0) * 0.12
		if score < best_score:
			best_score = score
			best_slot = slot
	return best_slot

func _jenga_is_collapsed(level: int, slot: int, roll: float) -> bool:
	return roll < _jenga_risk(level, slot)

func _jenga_action_allowed(seat: int, kind: String, level: int, slot: int) -> bool:
	if jenga_game_over or seat != jenga_turn or seat < 0 or seat >= jenga_player_count:
		return false
	if kind == "remove":
		return _jenga_legal_removal(level, slot)
	if kind == "place":
		return jenga_phase == "place" and level == jenga_layers.size() - 1 and slot in _jenga_legal_place_slots()
	return false

func _jenga_apply_action(seat: int, kind: String, level: int, slot: int, roll: float) -> void:
	if not _jenga_action_allowed(seat, kind, level, slot):
		return
	if kind == "remove":
		if not _jenga_legal_removal(level, slot):
			return
		var risk: float = _jenga_risk(level, slot)
		jenga_layers[level][slot] = false
		jenga_moves += 1
		if _jenga_is_collapsed(level, slot, clampf(roll, 0.0, 0.999999)):
			jenga_game_over = true
			jenga_winner = jenga_last_successful_seat if jenga_last_successful_seat >= 0 else posmod(seat + 1, jenga_player_count)
			jenga_status = "برج فرو ریخت؛ بازیکن %s بازنده شد." % app._fa(seat + 1)
			if app != null:
				app._go_result(jenga_winner == (0 if app.vs_cpu else app.local_seat))
		else:
			jenga_pending_piece = {"level": level, "slot": slot}
			# If the previous top row is already full, create the next row as part of
			# the synchronized rules transition, never as a side effect of rendering.
			var old_top: Array = jenga_layers[jenga_layers.size() - 1]
			if bool(old_top[0]) and bool(old_top[1]) and bool(old_top[2]):
				jenga_layers.append([false, false, false])
			jenga_phase = "place"
			jenga_status = "بلوک را در یکی از خانه‌های خالیِ بالاترین طبقه بگذارید. خطر این حرکت: %s٪" % str(round(risk * 100.0))
	elif kind == "place":
		if jenga_phase != "place" or level != jenga_layers.size() - 1 or slot < 0 or slot > 2:
			return
		var top: Array = jenga_layers[jenga_layers.size() - 1]
		if bool(top[slot]):
			return
		top[slot] = true
		jenga_layers[jenga_layers.size() - 1] = top
		jenga_pending_piece = {}
		jenga_phase = "remove"
		jenga_last_successful_seat = seat
		jenga_turn = posmod(seat + 1, jenga_player_count)
		jenga_status = "حرکت موفق؛ نوبت بازیکن %s" % app._fa(jenga_turn + 1)
	if app != null:
		app._rebuild_buttons()

func _jenga_cpu_turn() -> void:
	if not app.vs_cpu or jenga_game_over or jenga_turn == 0:
		return
	if jenga_phase == "remove":
		var choices: Array[Vector2i] = []
		for level in range(jenga_layers.size()):
			for slot in range(3):
				if _jenga_legal_removal(level, slot):
					choices.append(Vector2i(level, slot))
		if choices.is_empty():
			jenga_game_over = true
			jenga_winner = 0
			app._go_result(true)
			return
		var level: int = clampi(jenga_difficulty, 1, 6)
		var chosen: Vector2i = choices[0]
		if level == 1:
			chosen = choices.pick_random()
		else:
			var best_score: float = 99999.0
			var tied: Array[Vector2i] = []
			for candidate in choices:
				var score: float = _jenga_candidate_score(candidate, level)
				match level:
					2: score += randf_range(-3.8, 3.8)
					3: score += randf_range(-1.3, 1.3)
					4: score += randf_range(-0.45, 0.45)
					5: score += randf_range(-0.12, 0.12)
				if score < best_score - 0.001:
					best_score = score
					tied = [candidate]
				elif absf(score - best_score) <= 0.001:
					tied.append(candidate)
			if not tied.is_empty():
				chosen = tied[0] if level == 6 else tied.pick_random()
		var roll: float = randf()
		_jenga_apply_action(jenga_turn, "remove", chosen.x, chosen.y, roll)
		if not jenga_game_over and jenga_phase == "place":
			var slots: Array[int] = _jenga_legal_place_slots()
			if slots.is_empty():
				var top: Array = jenga_layers[jenga_layers.size() - 1]
				if bool(top[0]) and bool(top[1]) and bool(top[2]):
					jenga_layers.append([false, false, false])
				slots = _jenga_legal_place_slots()
			var place_slot: int = _jenga_choose_slot(slots)
			if place_slot >= 0:
				_jenga_apply_action(jenga_turn, "place", jenga_layers.size() - 1, place_slot, 0.0)
		return
	if jenga_phase == "place":
		var options: Array[int] = _jenga_legal_place_slots()
		var slot: int = _jenga_choose_slot(options)
		if slot >= 0:
			_jenga_apply_action(jenga_turn, "place", jenga_layers.size() - 1, slot, 0.0)

func _jenga_tap(point: Vector2) -> void:
	_presentation.handle_tap(app, self, point)

func _draw_jenga() -> void:
	_presentation.render(app, self)

func _btns_jenga() -> void:
	_presentation.build_buttons(app, self)
