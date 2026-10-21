extends RefCounted
## Six-level backgammon AI for the standard point-movement rules in rules.gd.
## Searches legal dice sequences, maximizes dice use, respects the high-die rule,
## and evaluates hits, bar exposure, made points, pip race and bearing off.

func choose_turn(game, difficulty: int) -> Array:
	var level: int = clampi(difficulty, 1, 6)
	var dice: Array = game.bg_moves_left.duplicate()
	if dice.is_empty():
		return []
	# Consider both die orders. Backgammon maximizes the number of dice used before
	# considering board quality; the high-die rule is then enforced when only one die can play.
	var saved: Dictionary = _save_state(game)
	var orders: Array = [dice.duplicate()]
	if dice.size() == 2 and int(dice[0]) != int(dice[1]):
		orders.append([int(dice[1]), int(dice[0])])
	var best_score: float = -INF
	var best_used: int = -1
	var best_moves: Array = []
	for order in orders:
		_restore_state(game, saved)
		var candidate: Dictionary = _search_plan(game, order, 0, level)
		var score: float = float(candidate.get("score", -INF))
		var used: int = int(candidate.get("used", 0))
		if used > best_used or (used == best_used and score > best_score):
			best_used = used
			best_score = score
			best_moves = candidate.get("moves", []).duplicate(true)
	_restore_state(game, saved)
	if best_used == 1 and dice.size() >= 2:
		var high: int = 0
		var low: int = 7
		for value in dice:
			high = maxi(high, int(value))
			low = mini(low, int(value))
		if high != low:
			var high_sources: Array[int] = _legal_sources(game, high)
			if not high_sources.is_empty():
				var best_source: int = high_sources[0]
				var best_high_score: float = -INF
				for source in high_sources:
					var snapshot: Dictionary = _apply_source(game, source, high)
					var score: float = _evaluate(game, level)
					_undo_source(game, snapshot)
					if score > best_high_score:
						best_high_score = score
						best_source = source
				best_moves = [{"die": high, "source": best_source, "target": _target_for_source(best_source, high)}]
				for value in dice:
					if int(value) != high:
						best_moves.append({"die": int(value), "source": -99, "target": -99})
	return best_moves

func choose_legal_first_move(game, legal_moves: Array[Dictionary], difficulty: int) -> Dictionary:
	# The rules module supplies only first moves that preserve the mandatory
	# maximum-dice-use/high-die rules. The AI ranks within that legal set only.
	if legal_moves.is_empty():
		return {}
	var level: int = clampi(difficulty, 1, 6)
	if level == 1:
		return legal_moves[randi_range(0, legal_moves.size() - 1)].duplicate(true)
	var best_move: Dictionary = legal_moves[0].duplicate(true)
	var best_score: float = -INF
	for move in legal_moves:
		var snapshot: Dictionary = game._bg_save_board()
		game._bg_apply_board_move(1, move)
		var score: float = _evaluate(game, level)
		game._bg_restore_board(snapshot)
		if level == 2:
			score += randf_range(-38.0, 38.0)
		if score > best_score:
			best_score = score
			best_move = move.duplicate(true)
	return best_move

func _leaf_score(game, level: int) -> float:
	var value: float = _evaluate(game, level)
	if level == 1:
		value += randf_range(-180.0, 180.0)
	elif level == 2:
		value += randf_range(-38.0, 38.0)
	return value

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
	# Once either side has borne off all checkers, no later planned dice may
	# alter the result. Stop here so the search never rewards phantom moves.
	if int(game.bg_off[1]) >= 15 or int(game.bg_off[0]) >= 15:
		return {"score": _leaf_score(game, level), "moves": [], "used": 0}
	if index >= dice.size():
		return {"score": _leaf_score(game, level), "moves": [], "used": 0}

	var die: int = int(dice[index])
	var sources: Array[int] = _legal_sources(game, die)
	if sources.is_empty():
		var skipped_tail: Dictionary = _search_plan(game, dice, index + 1, level)
		var skipped_moves: Array = [{"die": die, "source": -99, "target": -99}]
		skipped_moves.append_array(skipped_tail.get("moves", []))
		return {"score": float(skipped_tail.get("score", _evaluate(game, level))), "moves": skipped_moves, "used": int(skipped_tail.get("used", 0))}

	var ordered: Array[Dictionary] = _order_sources(game, sources, die, level)
	var branch_limits: Array[int] = [0, 4, 5, 6, 7, 8, 10]
	var branch_limit: int = branch_limits[level]
	if ordered.size() > branch_limit:
		ordered.resize(branch_limit)

	var best_score: float = -INF
	var best_used: int = -1
	var best_moves: Array = []
	for entry in ordered:
		var source: int = int(entry["source"])
		var snapshot: Dictionary = _apply_source(game, source, die)
		var tail: Dictionary = _search_plan(game, dice, index + 1, level)
		_undo_source(game, snapshot)
		var score: float = float(tail.get("score", _evaluate(game, level)))
		var used: int = 1 + int(tail.get("used", 0))
		if used > best_used or (used == best_used and score > best_score):
			best_used = used
			best_score = score
			best_moves = [{"die": die, "source": source, "target": _target_for_source(source, die)}]
			best_moves.append_array(tail.get("moves", []))
	return {"score": best_score if not is_inf(best_score) else _leaf_score(game, level), "moves": best_moves, "used": maxi(0, best_used)}

func _order_sources(game, sources: Array[int], die: int, level: int) -> Array[Dictionary]:
	var ranked: Array[Dictionary] = []
	for source in sources:
		var score: float
		if level == 1:
			# Beginner keeps the legal dice-use rules but intentionally samples the
			# candidate order, avoiding a near-expert search with only noisy scoring.
			score = randf()
		else:
			var snapshot: Dictionary = _apply_source(game, source, die)
			score = _evaluate(game, level)
			_undo_source(game, snapshot)
			if level == 2:
				score += randf_range(-38.0, 38.0)
		ranked.append({"source": source, "score": score})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"])
	)
	return ranked

func _legal_sources(game, die: int) -> Array[int]:
	var result: Array[int] = []
	for move in game._bg_legal_moves_for_die(1, die):
		var source: int = int(move.get("source", -99))
		if source not in result:
			result.append(source)
	return result

func _target_for_source(source: int, die: int) -> int:
	if source == -1:
		return die - 1
	var target: int = source - die
	return -1 if target < 0 else target

func _apply_source(game, source: int, die: int) -> Dictionary:
	var board_snapshot: Dictionary = game._bg_save_board()
	var target: int = _target_for_source(source, die)
	game._bg_apply_board_move(1, {"source": source, "target": target, "die": die})
	return {"board": board_snapshot, "source": source, "target": target}

func _undo_source(game, snapshot: Dictionary) -> void:
	game._bg_restore_board(snapshot["board"])

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
	game._bg_invalidate_legal_cache()

func _evaluate(game, level: int) -> float:
	# Terminal positions dominate every heuristic term.
	if int(game.bg_off[1]) >= 15:
		return 1000000.0
	if int(game.bg_off[0]) >= 15:
		return -1000000.0
	var cpu_pips: int = 0
	var human_pips: int = 0
	var score: float = float(int(game.bg_off[1]) - int(game.bg_off[0])) * 22.0
	score += float(int(game.bg_bar[0]) - int(game.bg_bar[1])) * 18.0
	# A checker on the bar is very vulnerable and must re-enter before any board
	# checker can move; it is assigned a high pip and tactical penalty.
	human_pips += int(game.bg_bar[0]) * 30
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
				blot_adjustment += float(_cpu_can_hit(game, point)) * (1.1 if level < 6 else 1.6)
		elif count < 0:
			cpu_pips += -count * (point + 1)
			if count <= -2:
				cpu_made += 1
			elif level >= 4:
				# Penalize a CPU blot in proportion to how many die values expose it.
				blot_adjustment -= float(_human_can_hit(game, point)) * (1.3 if level < 6 else 2.0)
	score += float(human_pips - cpu_pips) * 0.55
	if level >= 5:
		score += float(cpu_made - human_made) * 2.0
	if level >= 6:
		score += _prime_score(game)
	return score + blot_adjustment

func _cpu_can_hit(game, human_blot: int) -> int:
	var opportunities: int = 0
	for die in range(1, 7):
		var source: int = human_blot + die
		if source < 24 and int(game.bg_points[source]) < 0:
			opportunities += 1
	return opportunities

func _human_can_hit(game, cpu_blot: int) -> int:
	var threats: int = 0
	for die in range(1, 7):
		var source: int = cpu_blot - die
		if source >= 0 and int(game.bg_points[source]) > 0:
			threats += 1
	return threats

func _prime_score(game) -> float:
	var score: float = 0.0
	# CPU travels from high points toward zero; human travels from low to high.
	var cpu_run: int = 0
	for point in range(24):
		if int(game.bg_points[point]) <= -2:
			cpu_run += 1
			if cpu_run >= 2:
				score += 1.2 + float(cpu_run - 2) * 0.35
		else:
			cpu_run = 0
	var human_run: int = 0
	for point in range(23, -1, -1):
		if int(game.bg_points[point]) >= 2:
			human_run += 1
			if human_run >= 2:
				score -= 1.2 + float(human_run - 2) * 0.35
		else:
			human_run = 0
	return score
