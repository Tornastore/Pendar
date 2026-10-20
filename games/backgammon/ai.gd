extends RefCounted
## Six-level backgammon AI for Mind Bastion's current simplified point-movement rules.
## Stronger levels search full sequences of the rolled dice and value hits, bear-offs,
## pip race, made points and exposed blots. This does not add official bar re-entry rules.

func choose_turn(game, difficulty: int) -> Array:
	var level: int = clampi(difficulty, 1, 6)
	var dice: Array = game.bg_moves_left.duplicate()
	if dice.is_empty():
		return []
	if level == 1:
		return _random_plan(game, dice)
	if level == 2:
		return _greedy_plan(game, dice, level)
	var result: Dictionary = _search_plan(game, dice, 0, level)
	return result.get("moves", [])

func _random_plan(game, dice: Array) -> Array:
	var saved: Dictionary = _save_state(game)
	var plan: Array = []
	for die_value in dice:
		var die: int = int(die_value)
		var sources: Array[int] = _legal_sources(game, die)
		var source: int = -1
		if not sources.is_empty():
			source = sources[randi_range(0, sources.size() - 1)]
			_apply_source(game, source, die)
		plan.append({"die": die, "source": source})
	_restore_state(game, saved)
	return plan

func _greedy_plan(game, dice: Array, level: int) -> Array:
	var saved: Dictionary = _save_state(game)
	var plan: Array = []
	for die_value in dice:
		var die: int = int(die_value)
		var sources: Array[int] = _legal_sources(game, die)
		var best_source: int = -1
		var best_score: float = -INF
		for source in sources:
			var snap: Dictionary = _apply_source(game, source, die)
			var score: float = _evaluate(game, level) + randf_range(0.0, 0.05)
			_undo_source(game, snap)
			if score > best_score:
				best_score = score
				best_source = source
		if best_source >= 0:
			_apply_source(game, best_source, die)
		plan.append({"die": die, "source": best_source})
	_restore_state(game, saved)
	return plan

func _search_plan(game, dice: Array, index: int, level: int) -> Dictionary:
	if index >= dice.size():
		return {"score": _evaluate(game, level), "moves": []}

	var die: int = int(dice[index])
	var sources: Array[int] = _legal_sources(game, die)
	if sources.is_empty():
		var skipped_tail: Dictionary = _search_plan(game, dice, index + 1, level)
		var skipped_moves: Array = [{"die": die, "source": -1}]
		skipped_moves.append_array(skipped_tail.get("moves", []))
		return {"score": float(skipped_tail.get("score", _evaluate(game, level))), "moves": skipped_moves}

	var ordered: Array[Dictionary] = _order_sources(game, sources, die, level)
	var branch_limits: Array[int] = [0, 0, 0, 3, 4, 5, 7]
	var branch_limit: int = branch_limits[level]
	if ordered.size() > branch_limit:
		ordered.resize(branch_limit)

	var best_score: float = -INF
	var best_moves: Array = []
	for entry in ordered:
		var source: int = int(entry["source"])
		var snapshot: Dictionary = _apply_source(game, source, die)
		var tail: Dictionary = _search_plan(game, dice, index + 1, level)
		_undo_source(game, snapshot)
		var score: float = float(tail.get("score", _evaluate(game, level)))
		if score > best_score:
			best_score = score
			best_moves = [{"die": die, "source": source}]
			best_moves.append_array(tail.get("moves", []))
	return {"score": best_score if not is_inf(best_score) else _evaluate(game, level), "moves": best_moves}

func _order_sources(game, sources: Array[int], die: int, level: int) -> Array[Dictionary]:
	var ranked: Array[Dictionary] = []
	for source in sources:
		var snapshot: Dictionary = _apply_source(game, source, die)
		var score: float = _evaluate(game, level)
		_undo_source(game, snapshot)
		ranked.append({"source": source, "score": score})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"])
	)
	return ranked

func _legal_sources(game, die: int) -> Array[int]:
	var result: Array[int] = []
	for source in range(23, -1, -1):
		if int(game.bg_points[source]) >= 0:
			continue
		var destination: int = source - die
		if destination < 0 or int(game.bg_points[destination]) <= 1:
			result.append(source)
	return result

func _apply_source(game, source: int, die: int) -> Dictionary:
	var destination: int = source - die
	var snapshot: Dictionary = {
		"source": source,
		"destination": destination,
		"source_before": int(game.bg_points[source]),
		"destination_before": int(game.bg_points[destination]) if destination >= 0 else 0,
		"bar_before": int(game.bg_bar[0]),
		"off_before": int(game.bg_off[1])
	}
	game.bg_points[source] = int(game.bg_points[source]) + 1
	if destination < 0:
		game.bg_off[1] = int(game.bg_off[1]) + 1
	else:
		if int(game.bg_points[destination]) == 1:
			game.bg_points[destination] = 0
			game.bg_bar[0] = int(game.bg_bar[0]) + 1
		game.bg_points[destination] = int(game.bg_points[destination]) - 1
	return snapshot

func _undo_source(game, snapshot: Dictionary) -> void:
	var source: int = int(snapshot["source"])
	var destination: int = int(snapshot["destination"])
	game.bg_points[source] = int(snapshot["source_before"])
	if destination >= 0:
		game.bg_points[destination] = int(snapshot["destination_before"])
	game.bg_bar[0] = int(snapshot["bar_before"])
	game.bg_off[1] = int(snapshot["off_before"])

func _save_state(game) -> Dictionary:
	return {
		"points": game.bg_points.duplicate(),
		"bar": game.bg_bar.duplicate(),
		"off": game.bg_off.duplicate()
	}

func _restore_state(game, snapshot: Dictionary) -> void:
	game.bg_points = snapshot["points"].duplicate()
	game.bg_bar = snapshot["bar"].duplicate()
	game.bg_off = snapshot["off"].duplicate()

func _evaluate(game, level: int) -> float:
	var cpu_pips: int = 0
	var human_pips: int = 0
	var score: float = float(int(game.bg_off[1]) - int(game.bg_off[0])) * 22.0
	score += float(int(game.bg_bar[0]) - int(game.bg_bar[1])) * 18.0
	# Hit checkers still count as pip distance; in this prototype, a checker on the
	# bar cannot re-enter yet, so it is valued as far away from bearing off.
	human_pips += int(game.bg_bar[0]) * 25
	cpu_pips += int(game.bg_bar[1]) * 25
	var cpu_made: int = 0
	var human_made: int = 0
	var blot_adjustment: float = 0.0
	for point in range(24):
		var count: int = int(game.bg_points[point])
		if count > 0:
			human_pips += count * (24 - point)
			if count >= 2:
				human_made += 1
			elif level >= 4:
				# An exposed human checker is a tactical target for the CPU.
				blot_adjustment += float(_cpu_can_hit(game, point)) * 2.5
		elif count < 0:
			cpu_pips += -count * (point + 1)
			if count <= -2:
				cpu_made += 1
			elif level >= 4:
				# Penalize a CPU blot when a human checker can hit it.
				blot_adjustment -= float(_human_can_hit(game, point)) * 3.0
	score += float(human_pips - cpu_pips) * 0.55
	if level >= 5:
		score += float(cpu_made - human_made) * 2.0
	if level >= 6:
		score += _prime_score(game)
	return score + blot_adjustment

func _cpu_can_hit(game, human_blot: int) -> int:
	for die in range(1, 7):
		var source: int = human_blot + die
		if source < 24 and int(game.bg_points[source]) < 0:
			return 1
	return 0

func _human_can_hit(game, cpu_blot: int) -> int:
	for die in range(1, 7):
		var source: int = cpu_blot - die
		if source >= 0 and int(game.bg_points[source]) > 0:
			return 1
	return 0

func _prime_score(game) -> float:
	var score: float = 0.0
	var cpu_run: int = 0
	var human_run: int = 0
	for point in range(24):
		if int(game.bg_points[point]) <= -2:
			cpu_run += 1
			if cpu_run >= 2:
				score += 1.2
		else:
			cpu_run = 0
		if int(game.bg_points[point]) >= 2:
			human_run += 1
			if human_run >= 2:
				score -= 1.2
		else:
			human_run = 0
	return score
