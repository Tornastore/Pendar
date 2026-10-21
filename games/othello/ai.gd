extends RefCounted
## Six-level Othello AI, shared by the 8x8 and 12x12 variants.
## Uses legal-move generation, positional evaluation, mobility/frontier heuristics,
## and bounded alpha-beta minimax for the stronger levels.

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)
]

var _size: int = 8
var _root_player: int = 2
var _node_count: int = 0
var _node_limit: int = 1000
var _branch_limit: int = 8
var _exact_endgame: bool = false
var _transposition: Dictionary = {}

func choose_move(board: Array, board_size: int, player: int, difficulty: int) -> Vector2i:
	_size = board_size
	_root_player = player
	_node_count = 0
	_transposition.clear()
	var level: int = clampi(difficulty, 1, 6)
	var legal: Array[Vector2i] = _legal_moves(board, _size, player)
	if legal.is_empty():
		return Vector2i(-1, -1)

	if level == 1:
		return _choose_greedy(board, legal, player)

	var ordered: Array[Dictionary] = _ordered_moves(board, legal, player)
	if level == 2:
		return _choose_one_ply(board, ordered, player)

	# Deeper levels trade response time for more look-ahead. 12x12 receives a
	# stricter node budget because it has substantially more candidate moves.
	var depth_by_level: Array[int] = [0, 0, 2, 3, 5, 6]
	var depth: int = depth_by_level[level - 1]
	if _size >= 12:
		depth = [0, 0, 2, 3, 4, 5][level - 1]
		_node_limit = [0, 0, 900, 3000, 8500, 15000][level - 1]
	else:
		_node_limit = [0, 0, 1200, 5000, 15000, 24000][level - 1]
	_branch_limit = [0, 0, 12, 10, 9, 8][level - 1]
	var root_limit: int = [0, 0, 16, 18, 14, 20][level - 1]
	if _size >= 12:
		root_limit = [0, 0, 12, 14, 16, 18][level - 1]
	_exact_endgame = level == 6 and _size == 8 and _empty_count(board) <= 7
	if _exact_endgame:
		# In the small 8x8 endgame, solve to completion when practical.
		depth = _empty_count(board)
		_node_limit = 120000
		_branch_limit = 100
		root_limit = ordered.size()

	var best_move: Vector2i = ordered[0]["move"]
	var best_value: float = -INF
	var alpha: float = -INF
	var candidate_count: int = mini(root_limit, ordered.size())
	var total_node_budget: int = _node_limit
	var per_root_budget: int = 120000 if _exact_endgame else maxi(320, int(float(total_node_budget) / float(maxi(1, candidate_count))))
	var examined: int = 0
	for entry in ordered:
		if examined >= root_limit:
			break
		# Give each candidate a bounded share of the search budget so an early
		# branch cannot consume all work before later legal moves are compared.
		_node_count = 0
		_node_limit = per_root_budget
		var move: Vector2i = entry["move"]
		var flips: Array[Vector2i] = _apply_move(board, move, player)
		var value: float = _search(board, 3 - player, depth - 1, alpha, INF)
		_undo_move(board, move, flips, player)
		if value > best_value:
			best_value = value
			best_move = move
		alpha = maxf(alpha, best_value)
		examined += 1
	return best_move

func _choose_greedy(board: Array, moves: Array[Vector2i], player: int) -> Vector2i:
	var best: Vector2i = moves[0]
	var best_score: float = -INF
	for move in moves:
		var flips: Array[Vector2i] = _flips_for(board, _size, move, player)
		var score: float = float(flips.size()) * 1.4 + _position_weight(board, move) * 0.65
		if score > best_score:
			best_score = score
			best = move
	return best

func _choose_one_ply(board: Array, ordered: Array[Dictionary], player: int) -> Vector2i:
	var best: Vector2i = ordered[0]["move"]
	var best_score: float = -INF
	for entry in ordered:
		var move: Vector2i = entry["move"]
		var flips: Array[Vector2i] = _apply_move(board, move, player)
		var score: float = _evaluate(board, player)
		_undo_move(board, move, flips, player)
		if score > best_score:
			best_score = score
			best = move
	return best

func _search(board: Array, turn: int, depth: int, alpha_in: float, beta_in: float) -> float:
	_node_count += 1
	var moves: Array[Vector2i] = _legal_moves(board, _size, turn)
	if moves.is_empty():
		var other_moves: Array[Vector2i] = _legal_moves(board, _size, 3 - turn)
		if other_moves.is_empty():
			return _terminal_value(board, _root_player)
		if depth <= 0 or _node_count >= _node_limit:
			return _evaluate(board, _root_player)
		# In an exact endgame a pass is not a placement, so it must not consume
		# one of the remaining-empty-square plies.
		var pass_depth: int = depth if _exact_endgame else depth - 1
		return _search(board, 3 - turn, pass_depth, alpha_in, beta_in)
	if depth <= 0 or _node_count >= _node_limit:
		return _evaluate(board, _root_player)

	var alpha_original: float = alpha_in
	var beta_original: float = beta_in
	var alpha: float = alpha_in
	var beta: float = beta_in
	var key: String = _board_key(board, turn)
	var preferred: Vector2i = Vector2i(-1, -1)
	if _transposition.has(key):
		var cached: Dictionary = _transposition[key]
		preferred = cached.get("move", Vector2i(-1, -1))
		if int(cached.get("depth", -1)) >= depth:
			var cached_score: float = float(cached.get("score", 0.0))
			match str(cached.get("bound", "exact")):
				"exact":
					return cached_score
				"lower":
					alpha = maxf(alpha, cached_score)
				"upper":
					beta = minf(beta, cached_score)
			if alpha >= beta:
				return cached_score

	var ordered: Array[Dictionary] = _ordered_moves(board, moves, turn, preferred)
	if ordered.size() > _branch_limit:
		ordered.resize(_branch_limit)
	var best_move: Vector2i = Vector2i(-1, -1)
	var best_value: float = -INF if turn == _root_player else INF
	var cutoff: bool = false
	if turn == _root_player:
		for entry in ordered:
			if _node_count >= _node_limit:
				cutoff = true
				break
			var move: Vector2i = entry["move"]
			var flips: Array[Vector2i] = _apply_move(board, move, turn)
			var value: float = _search(board, 3 - turn, depth - 1, alpha, beta)
			_undo_move(board, move, flips, turn)
			if value > best_value:
				best_value = value
				best_move = move
			alpha = maxf(alpha, best_value)
			if alpha >= beta:
				cutoff = true
				break
	else:
		for entry in ordered:
			if _node_count >= _node_limit:
				cutoff = true
				break
			var move: Vector2i = entry["move"]
			var flips: Array[Vector2i] = _apply_move(board, move, turn)
			var value: float = _search(board, 3 - turn, depth - 1, alpha, beta)
			_undo_move(board, move, flips, turn)
			if value < best_value:
				best_value = value
				best_move = move
			beta = minf(beta, best_value)
			if alpha >= beta:
				cutoff = true
				break
	if is_inf(best_value):
		best_value = _evaluate(board, _root_player)
	if not cutoff and _node_count < _node_limit:
		var bound: String = "exact"
		if best_value <= alpha_original:
			bound = "upper"
		elif best_value >= beta_original:
			bound = "lower"
		_transposition[key] = {"depth": depth, "score": best_value, "bound": bound, "move": best_move}
	return best_value

func _board_key(board: Array, turn: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append(str(turn))
	for y in _size:
		for x in _size:
			parts.append(str(int(board[y][x])))
	return ",".join(parts)

func _legal_moves(board: Array, size: int, color: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in size:
		for x in size:
			if int(board[y][x]) != 0:
				continue
			var move := Vector2i(x, y)
			if not _flips_for(board, size, move, color).is_empty():
				result.append(move)
	return result

func _flips_for(board: Array, size: int, move: Vector2i, color: int) -> Array[Vector2i]:
	var flips: Array[Vector2i] = []
	if move.x < 0 or move.x >= size or move.y < 0 or move.y >= size:
		return flips
	if int(board[move.y][move.x]) != 0:
		return flips
	for direction in DIRS:
		var line: Array[Vector2i] = []
		var pos: Vector2i = move + direction
		while pos.x >= 0 and pos.x < size and pos.y >= 0 and pos.y < size and int(board[pos.y][pos.x]) == 3 - color:
			line.append(pos)
			pos += direction
		if not line.is_empty() and pos.x >= 0 and pos.x < size and pos.y >= 0 and pos.y < size and int(board[pos.y][pos.x]) == color:
			flips.append_array(line)
	return flips

func _apply_move(board: Array, move: Vector2i, color: int) -> Array[Vector2i]:
	var flips: Array[Vector2i] = _flips_for(board, _size, move, color)
	board[move.y][move.x] = color
	for pos in flips:
		board[pos.y][pos.x] = color
	return flips

func _undo_move(board: Array, move: Vector2i, flips: Array[Vector2i], color: int) -> void:
	board[move.y][move.x] = 0
	for pos in flips:
		board[pos.y][pos.x] = 3 - color

func _ordered_moves(board: Array, moves: Array[Vector2i], color: int, preferred: Vector2i = Vector2i(-1, -1)) -> Array[Dictionary]:
	var ranked: Array[Dictionary] = []
	for move in moves:
		var flips: Array[Vector2i] = _flips_for(board, _size, move, color)
		var score: float = _position_weight(board, move) * 2.0 + float(flips.size()) * 0.15
		# Prefer moves adjacent to an enemy frontier only when they do not concede a corner.
		var last: int = _size - 1
		if (move.x == 0 or move.x == last) and (move.y == 0 or move.y == last):
			score += 1000.0
		elif _position_weight(board, move) < -20.0:
			score -= 25.0
		if move == preferred:
			score += 1000000.0
		ranked.append({"move": move, "score": score})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"])
	)
	return ranked

func _position_weight(board: Array, pos: Vector2i) -> float:
	var last: int = _size - 1
	var left: bool = pos.x == 0
	var right: bool = pos.x == last
	var top: bool = pos.y == 0
	var bottom: bool = pos.y == last
	if (left or right) and (top or bottom):
		return 120.0
	# Avoid squares directly next to an unclaimed corner: these often give the
	# opponent access to the corner on their next turn.
	var adjacent_corner: bool = (pos.x == 1 and (top or bottom)) or (pos.x == last - 1 and (top or bottom)) or (pos.y == 1 and (left or right)) or (pos.y == last - 1 and (left or right))
	if adjacent_corner:
		var corner := Vector2i(0 if pos.x <= 1 else last, 0 if pos.y <= 1 else last)
		if int(board[corner.y][corner.x]) == 0:
			return -34.0
		return 2.0
	var diagonal_corner: bool = (pos.x == 1 or pos.x == last - 1) and (pos.y == 1 or pos.y == last - 1)
	if diagonal_corner:
		var corner2 := Vector2i(0 if pos.x == 1 else last, 0 if pos.y == 1 else last)
		if int(board[corner2.y][corner2.x]) == 0:
			return -42.0
		return 1.0
	if left or right or top or bottom:
		return 12.0
	var center: float = float(_size - 1) * 0.5
	var center_distance: float = absf(float(pos.x) - center) + absf(float(pos.y) - center)
	return maxf(-1.0, 5.0 - center_distance * 0.30)

func _evaluate(board: Array, perspective: int) -> float:
	var opponent: int = 3 - perspective
	var own_discs: int = 0
	var opponent_discs: int = 0
	var positional: float = 0.0
	var own_frontier: int = 0
	var opponent_frontier: int = 0
	var occupied: int = 0
	for y in _size:
		for x in _size:
			var piece: int = int(board[y][x])
			if piece == 0:
				continue
			occupied += 1
			var weight: float = _position_weight(board, Vector2i(x, y))
			if piece == perspective:
				own_discs += 1
				positional += weight
				if _is_frontier(board, Vector2i(x, y)):
					own_frontier += 1
			else:
				opponent_discs += 1
				positional -= weight
				if _is_frontier(board, Vector2i(x, y)):
					opponent_frontier += 1

	var own_mobility: int = _legal_moves(board, _size, perspective).size()
	var opponent_mobility: int = _legal_moves(board, _size, opponent).size()
	var phase: float = float(occupied) / float(_size * _size)
	var mobility_weight: float = 10.0 - phase * 6.0
	var frontier_weight: float = 4.5 * (1.0 - phase)
	var disc_weight: float = 0.8 + phase * phase * 12.0
	var disc_diff: int = own_discs - opponent_discs
	var mobility_diff: int = own_mobility - opponent_mobility
	var frontier_diff: int = opponent_frontier - own_frontier
	var potential_diff: int = _potential_mobility_diff(board, perspective)
	var stable_diff: int = _stable_edge_count(board, perspective) - _stable_edge_count(board, opponent)
	var potential_weight: float = 5.0 * (1.0 - phase) + 0.8
	var stable_weight: float = 2.0 + phase * 5.0
	return positional + float(mobility_diff) * mobility_weight + float(frontier_diff) * frontier_weight + float(potential_diff) * potential_weight + float(stable_diff) * stable_weight + float(disc_diff) * disc_weight

func _potential_mobility_diff(board: Array, perspective: int) -> int:
	var own_potential: int = 0
	var opponent_potential: int = 0
	for y in _size:
		for x in _size:
			if int(board[y][x]) != 0:
				continue
			var near_own: bool = false
			var near_opponent: bool = false
			for direction in DIRS:
				var nx: int = x + direction.x
				var ny: int = y + direction.y
				if nx < 0 or nx >= _size or ny < 0 or ny >= _size:
					continue
				var neighbor: int = int(board[ny][nx])
				near_own = near_own or neighbor == perspective
				near_opponent = near_opponent or neighbor == 3 - perspective
			if near_opponent:
				own_potential += 1
			if near_own:
				opponent_potential += 1
	return own_potential - opponent_potential

func _stable_edge_count(board: Array, color: int) -> int:
	var stable: Dictionary = {}
	var corners: Array[Vector2i] = [Vector2i(0, 0), Vector2i(_size - 1, 0), Vector2i(0, _size - 1), Vector2i(_size - 1, _size - 1)]
	for corner in corners:
		if int(board[corner.y][corner.x]) != color:
			continue
		stable[corner] = true
		var dirs: Array[Vector2i] = []
		dirs.append(Vector2i(1 if corner.x == 0 else -1, 0))
		dirs.append(Vector2i(0, 1 if corner.y == 0 else -1))
		for direction in dirs:
			var pos: Vector2i = corner + direction
			while pos.x >= 0 and pos.x < _size and pos.y >= 0 and pos.y < _size and int(board[pos.y][pos.x]) == color:
				stable[pos] = true
				pos += direction
	return stable.size()

func _empty_count(board: Array) -> int:
	var result: int = 0
	for y in _size:
		for x in _size:
			if int(board[y][x]) == 0:
				result += 1
	return result

func _is_frontier(board: Array, pos: Vector2i) -> bool:
	for direction in DIRS:
		var neighbor: Vector2i = pos + direction
		if neighbor.x >= 0 and neighbor.x < _size and neighbor.y >= 0 and neighbor.y < _size and int(board[neighbor.y][neighbor.x]) == 0:
			return true
	return false

func _terminal_value(board: Array, perspective: int) -> float:
	var own: int = 0
	var opponent: int = 0
	for y in _size:
		for x in _size:
			if int(board[y][x]) == perspective:
				own += 1
			elif int(board[y][x]) == 3 - perspective:
				opponent += 1
	return float(own - opponent) * 10000.0
