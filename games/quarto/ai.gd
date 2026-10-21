extends RefCounted
## Bounded tactical AI for Quarto. Immediate wins/safety always precede heuristic search.

var _nodes: int = 0
var _node_limit: int = 1800
var _exhausted: bool = false

func _configure(level: int) -> void:
	_nodes = 0
	_exhausted = false
	var budgets: Array[int] = [0, 450, 650, 950, 1500, 2300]
	_node_limit = budgets[clampi(level, 1, 6) - 1]

func _touch() -> bool:
	_nodes += 1
	if _nodes > _node_limit:
		_exhausted = true
		return false
	return true

func _winning_count(game, piece: int) -> int:
	var count: int = 0
	for y in range(4):
		for x in range(4):
			if int(game.qto_board[y][x]) >= 0:
				continue
			if not _touch():
				return -1
			game.qto_board[y][x] = piece
			if game._qto_has_quarto():
				count += 1
			game.qto_board[y][x] = -1
	return count

func _safe_piece_count(game, pieces: Array) -> int:
	var safe: int = 0
	for value in pieces:
		var wins: int = _winning_count(game, int(value))
		if wins < 0:
			return -1
		if wins == 0:
			safe += 1
	return safe

func _sample_cells(game, max_count: int) -> Array[Vector2i]:
	var preferred: Array[Vector2i] = [
		Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2),
		Vector2i(0, 0), Vector2i(3, 0), Vector2i(0, 3), Vector2i(3, 3),
		Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(3, 1),
		Vector2i(0, 2), Vector2i(3, 2), Vector2i(1, 3), Vector2i(2, 3)
	]
	var result: Array[Vector2i] = []
	for cell in preferred:
		if int(game.qto_board[cell.y][cell.x]) < 0:
			result.append(cell)
			if result.size() >= max_count:
				break
	return result

func choose_piece(game, difficulty: int) -> int:
	var level: int = clampi(difficulty, 1, 6)
	if game.qto_remaining.is_empty():
		return -1
	if level <= 1:
		return int(game.qto_remaining[randi() % game.qto_remaining.size()])
	_configure(level)
	var ranked: Array[Dictionary] = []
	for value in game.qto_remaining:
		var piece: int = int(value)
		var danger: int = _winning_count(game, piece)
		if danger < 0:
			break
		ranked.append({"piece": piece, "danger": danger})
	if ranked.is_empty():
		return int(game.qto_remaining[0])
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.danger) == int(b.danger):
			return int(a.piece) < int(b.piece)
		return int(a.danger) < int(b.danger)
	)
	var min_danger: int = int(ranked[0].danger)
	var safest: Array[int] = []
	for entry in ranked:
		if int(entry.danger) != min_danger:
			break
		safest.append(int(entry.piece))
	if level <= 3 or safest.size() <= 1:
		return safest[randi() % safest.size()]
	# On strong levels, examine likely replies for only the safest candidates.
	var candidate_limit: int = 1 if level == 4 else (2 if level == 5 else 3)
	var sample_count: int = 4 if level == 4 else (6 if level == 5 else 8)
	var best_piece: int = safest[0]
	var best_score: float = -INF
	var checked: int = 0
	for piece in safest:
		if checked >= candidate_limit or _exhausted:
			break
		checked += 1
		var after_piece: Array[int] = game.qto_remaining.duplicate()
		after_piece.erase(piece)
		var worst_safe_for_cpu: int = 0
		var samples: Array[Vector2i] = _sample_cells(game, sample_count)
		for cell in samples:
			if _exhausted:
				break
			game.qto_board[cell.y][cell.x] = piece
			var continuation: int = 0
			if not game._qto_has_quarto():
				continuation = _safe_piece_count(game, after_piece)
			game.qto_board[cell.y][cell.x] = -1
			if continuation < 0:
				break
			worst_safe_for_cpu = maxi(worst_safe_for_cpu, continuation)
		var score: float = -float(worst_safe_for_cpu) * 100.0 - float(min_danger) * 10000.0
		if score > best_score:
			best_score = score
			best_piece = piece
	# If the budget expired, a legal piece with minimum immediate danger is still returned.
	return best_piece

func choose_cell(game, difficulty: int, offered_piece: int) -> Vector2i:
	var level: int = clampi(difficulty, 1, 6)
	var legal: Array[Vector2i] = game._qto_empty_cells()
	if legal.is_empty():
		return Vector2i(-1, -1)
	# Never miss a direct win, even at the lowest difficulty.
	var winning: Array[Vector2i] = []
	for cell in legal:
		game.qto_board[cell.y][cell.x] = offered_piece
		if game._qto_has_quarto():
			winning.append(cell)
		game.qto_board[cell.y][cell.x] = -1
	if not winning.is_empty():
		return _best_central_cell(winning) if level >= 4 else winning[randi() % winning.size()]
	if level <= 1:
		return legal[randi() % legal.size()]
	_configure(level)
	var plans: Array[Dictionary] = []
	for cell in legal:
		game.qto_board[cell.y][cell.x] = offered_piece
		var safe_count: int = _safe_piece_count(game, game.qto_remaining)
		game.qto_board[cell.y][cell.x] = -1
		if safe_count < 0:
			break
		var center_distance: float = Vector2(float(cell.x), float(cell.y)).distance_to(Vector2(1.5, 1.5))
		var score: float = float(safe_count) * 100.0 - center_distance * (1.0 if level >= 3 else 0.25)
		plans.append({"cell": cell, "score": score, "safe": safe_count})
	if plans.is_empty():
		return legal[0]
	plans.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.score) > float(b.score)
	)
	if level < 5 or plans.size() == 1:
		var top_score: float = float(plans[0].score)
		var tied: Array[Vector2i] = []
		for plan in plans:
			if float(plan.score) < top_score - 0.01:
				break
			tied.append(plan.cell)
		return tied[randi() % tied.size()] if level == 2 else plans[0].cell
	# A bounded second ply estimates whether our next piece choice can trap the opponent.
	var best_cell: Vector2i = plans[0].cell
	var best_score: float = -INF
	var candidate_limit: int = 2 if level == 5 else 3
	var future_sample_count: int = 4 if level == 5 else 6
	var checked: int = 0
	for plan in plans:
		if checked >= candidate_limit or _exhausted:
			break
		checked += 1
		var cell: Vector2i = plan.cell
		game.qto_board[cell.y][cell.x] = offered_piece
		var safe_to_give: Array[int] = []
		for value in game.qto_remaining:
			var wins_for_human: int = _winning_count(game, int(value))
			if wins_for_human < 0:
				break
			if wins_for_human == 0:
				safe_to_give.append(int(value))
		var future_cost: int = 999
		var sampled_safe: Array[int] = []
		for candidate_index in range(mini(2, safe_to_give.size())):
			sampled_safe.append(int(safe_to_give[candidate_index]))
		for give_piece in sampled_safe:
			if _exhausted:
				break
			var remaining_after: Array[int] = game.qto_remaining.duplicate()
			remaining_after.erase(give_piece)
			var worst_safe: int = 0
			for human_cell in _sample_cells(game, future_sample_count):
				game.qto_board[human_cell.y][human_cell.x] = give_piece
				var safe_for_cpu: int = -1
				if not game._qto_has_quarto():
					safe_for_cpu = _safe_piece_count(game, remaining_after)
				game.qto_board[human_cell.y][human_cell.x] = -1
				if safe_for_cpu < 0:
					continue
				worst_safe = maxi(worst_safe, safe_for_cpu)
			future_cost = mini(future_cost, worst_safe)
		game.qto_board[cell.y][cell.x] = -1
		var score: float = float(plan.safe) * 100.0 - float(future_cost) * 24.0
		if score > best_score:
			best_score = score
			best_cell = cell
	return best_cell

func _best_central_cell(cells: Array[Vector2i]) -> Vector2i:
	var best: Vector2i = cells[0]
	var distance: float = INF
	for cell in cells:
		var d: float = Vector2(float(cell.x), float(cell.y)).distance_to(Vector2(1.5, 1.5))
		if d < distance:
			distance = d
			best = cell
	return best
