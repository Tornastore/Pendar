extends RefCounted
## Six-level chess CPU. Uses alpha-beta, move ordering and tactical quiescence.
## The current game rules are still a simplified king-capture variant (not full FIDE checkmate).

const PIECE_VALUES: Array[int] = [0, 100, 320, 330, 500, 900, 20000]
const MATE_SCORE: float = 50000.0

var _difficulty: int = 3
var _nodes: int = 0
var _node_limit: int = 4000
var _branch_limit: int = 8
var _qdepth_limit: int = 3
var _transposition: Dictionary = {}

func choose_move(game, difficulty: int) -> Array:
	_difficulty = clampi(difficulty, 1, 6)
	_transposition.clear()
	var moves: Array = game._chess_all_moves(2)
	if moves.is_empty():
		return []
	if _difficulty == 1:
		return moves[randi_range(0, moves.size() - 1)]

	var ordered: Array[Dictionary] = _ordered_moves(game, moves, 2)
	if _difficulty == 2:
		var best_move: Array = ordered[0]["move"]
		var best_score: float = -INF
		for entry in ordered:
			var move: Array = entry["move"]
			var snapshot: Dictionary = _apply_move(game, move)
			var score: float = _evaluate(game) + randf_range(-12.0, 12.0)
			_undo_move(game, snapshot)
			if score > best_score:
				best_score = score
				best_move = move
		return best_move

	# Hard and above deliberately receive more search, not merely less randomness.
	var depths: Array[int] = [0, 0, 1, 2, 4, 5]
	var node_limits: Array[int] = [0, 0, 0, 1800, 8500, 18000]
	var branch_limits: Array[int] = [0, 0, 0, 12, 10, 8]
	var root_limits: Array[int] = [0, 0, 0, 24, 28, 32]
	var depth: int = depths[_difficulty - 1]
	var total_node_limit: int = node_limits[_difficulty - 1]
	_branch_limit = branch_limits[_difficulty - 1]
	_nodes = 0
	if depth <= 1:
		var best_one_ply: Array = ordered[0]["move"]
		var best_one_ply_score: float = -INF
		for entry in ordered:
			var move: Array = entry["move"]
			var snapshot: Dictionary = _apply_move(game, move)
			var score: float = _evaluate(game)
			_undo_move(game, snapshot)
			if score > best_one_ply_score:
				best_one_ply_score = score
				best_one_ply = move
		return best_one_ply

	# Split the budget between root candidates. Without this, the first candidate
	# could exhaust the whole budget and later candidates would be compared only
	# by static evaluation, undermining Expert/Grandmaster consistency.
	var root_count: int = mini(root_limits[_difficulty - 1], ordered.size())
	var per_root_budget: int = maxi(120, int(float(total_node_limit) / float(maxi(1, root_count))))
	var best: Array = ordered[0]["move"]
	var best_value: float = -INF
	var alpha: float = -INF
	for root_index in range(root_count):
		_nodes = 0
		_node_limit = per_root_budget
		var move: Array = ordered[root_index]["move"]
		var snapshot: Dictionary = _apply_move(game, move)
		var score: float = _search(game, 1, depth - 1, alpha, INF)
		_undo_move(game, snapshot)
		if score > best_value:
			best_value = score
			best = move
		alpha = maxf(alpha, best_value)
	_node_limit = total_node_limit
	return best

func _search(game, turn: int, depth: int, alpha_in: float, beta_in: float) -> float:
	_nodes += 1
	var terminal: float = _king_terminal_score(game)
	if absf(terminal) >= MATE_SCORE:
		return terminal
	if _nodes >= _node_limit:
		return _evaluate(game)
	if depth <= 0:
		if _difficulty >= 5:
			return _quiescence(game, turn, alpha_in, beta_in, _qdepth_limit)
		return _evaluate(game)

	var alpha_original: float = alpha_in
	var beta_original: float = beta_in
	var alpha: float = alpha_in
	var beta: float = beta_in
	var key: String = _position_key(game, turn)
	var preferred_move: Array = []
	if _transposition.has(key):
		var cached: Dictionary = _transposition[key]
		preferred_move = cached.get("move", [])
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

	var moves: Array = game._chess_all_moves(turn)
	if moves.is_empty():
		return -MATE_SCORE if turn == 2 else MATE_SCORE
	var ordered: Array[Dictionary] = _ordered_moves(game, moves, turn, preferred_move)
	if depth >= 2 and ordered.size() > _branch_limit:
		ordered.resize(_branch_limit)

	var best_move: Array = []
	var best_value: float = -INF if turn == 2 else INF
	var cutoff: bool = false
	if turn == 2:
		for entry in ordered:
			if _nodes >= _node_limit:
				cutoff = true
				break
			var move: Array = entry["move"]
			var snapshot: Dictionary = _apply_move(game, move)
			var value: float = _search(game, 1, depth - 1, alpha, beta)
			_undo_move(game, snapshot)
			if value > best_value:
				best_value = value
				best_move = move
			alpha = maxf(alpha, best_value)
			if alpha >= beta:
				cutoff = true
				break
	else:
		for entry in ordered:
			if _nodes >= _node_limit:
				cutoff = true
				break
			var move: Array = entry["move"]
			var snapshot: Dictionary = _apply_move(game, move)
			var value: float = _search(game, 2, depth - 1, alpha, beta)
			_undo_move(game, snapshot)
			if value < best_value:
				best_value = value
				best_move = move
			beta = minf(beta, best_value)
			if alpha >= beta:
				cutoff = true
				break
	if is_inf(best_value):
		best_value = _evaluate(game)
	# Only cache fully searched nodes; a node cut off by the runtime budget is an
	# evaluation boundary, not a valid minimax result.
	if not cutoff and _nodes < _node_limit:
		var bound: String = "exact"
		if best_value <= alpha_original:
			bound = "upper"
		elif best_value >= beta_original:
			bound = "lower"
		_transposition[key] = {"depth": depth, "score": best_value, "bound": bound, "move": best_move}
	return best_value

func _position_key(game, turn: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append(str(turn))
	for y in range(8):
		for x in range(8):
			parts.append(str(int(game.chess_board[y][x])))
	return ",".join(parts)

## Resolve capture sequences at leaves so the AI does not stop a search halfway
## through a material exchange. This is especially valuable at Expert/Grandmaster.
func _quiescence(game, turn: int, alpha_in: float, beta_in: float, qdepth: int) -> float:
	_nodes += 1
	var terminal: float = _king_terminal_score(game)
	if absf(terminal) >= MATE_SCORE:
		return terminal
	var stand_pat: float = _evaluate(game)
	if qdepth <= 0 or _nodes >= _node_limit:
		return stand_pat

	var alpha: float = alpha_in
	var beta: float = beta_in
	if turn == 2:
		if stand_pat >= beta:
			return stand_pat
		alpha = maxf(alpha, stand_pat)
	else:
		if stand_pat <= alpha:
			return stand_pat
		beta = minf(beta, stand_pat)

	var captures: Array = []
	for move_value in game._chess_all_moves(turn):
		var move: Array = move_value
		var from: Vector2i = move[0]
		var to: Vector2i = move[1]
		var moving: int = int(game.chess_board[from.y][from.x])
		var target: int = int(game.chess_board[to.y][to.x])
		var promotes: bool = (moving == 7 and to.y == 7) or (moving == 1 and to.y == 0)
		if target != 0 or promotes:
			captures.append(move)
	if captures.is_empty():
		return stand_pat
	var ordered: Array[Dictionary] = _ordered_moves(game, captures, turn)
	if ordered.size() > 8:
		ordered.resize(8)
	var best: float = stand_pat
	for entry in ordered:
		if _nodes >= _node_limit:
			break
		var snapshot: Dictionary = _apply_move(game, entry["move"])
		var child: float = _quiescence(game, 1 if turn == 2 else 2, alpha, beta, qdepth - 1)
		_undo_move(game, snapshot)
		if turn == 2:
			best = maxf(best, child)
			alpha = maxf(alpha, best)
		else:
			best = minf(best, child)
			beta = minf(beta, best)
		if alpha >= beta:
			break
	return best

func _ordered_moves(game, moves: Array, turn: int, preferred_move: Array = []) -> Array[Dictionary]:
	var ranked: Array[Dictionary] = []
	for move_value in moves:
		var move: Array = move_value
		var from: Vector2i = move[0]
		var to: Vector2i = move[1]
		var moving: int = int(game.chess_board[from.y][from.x])
		var target: int = int(game.chess_board[to.y][to.x])
		# MVV-LVA style capture ordering: search high-value captures early.
		var score: float = float(_piece_value(target)) * 10.0 - float(_piece_value(moving)) * 0.08
		if (moving == 7 and to.y == 7) or (moving == 1 and to.y == 0):
			score += 1200.0
		score += _center_score(to, moving)
		if preferred_move.size() >= 2 and move[0] == preferred_move[0] and move[1] == preferred_move[1]:
			score += 1000000.0
		if _difficulty < 5:
			score += randf_range(0.0, 0.1)
		ranked.append({"move": move, "score": score})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"])
	)
	return ranked

func _apply_move(game, move: Array) -> Dictionary:
	var from: Vector2i = move[0]
	var to: Vector2i = move[1]
	var moving: int = int(game.chess_board[from.y][from.x])
	var captured: int = int(game.chess_board[to.y][to.x])
	var placed: int = moving
	if moving == 7 and to.y == 7:
		placed = 11
	elif moving == 1 and to.y == 0:
		placed = 5
	game.chess_board[from.y][from.x] = 0
	game.chess_board[to.y][to.x] = placed
	return {"from": from, "to": to, "moving": moving, "captured": captured}

func _undo_move(game, snapshot: Dictionary) -> void:
	var from: Vector2i = snapshot["from"]
	var to: Vector2i = snapshot["to"]
	game.chess_board[from.y][from.x] = int(snapshot["moving"])
	game.chess_board[to.y][to.x] = int(snapshot["captured"])

func _evaluate(game) -> float:
	var score: float = 0.0
	var white_king_pos: Vector2i = Vector2i(-1, -1)
	var black_king_pos: Vector2i = Vector2i(-1, -1)
	var board_piece_count: int = 0
	var white_pawns_by_file: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
	var black_pawns_by_file: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
	for y in 8:
		for x in 8:
			var piece: int = int(game.chess_board[y][x])
			if piece == 0:
				continue
			board_piece_count += 1
			var white: bool = piece <= 6
			var typ: int = piece if white else piece - 6
			var sign: float = -1.0 if white else 1.0
			score += sign * float(PIECE_VALUES[typ])
			score += sign * _center_score(Vector2i(x, y), piece)
			if piece == 6:
				white_king_pos = Vector2i(x, y)
			elif piece == 12:
				black_king_pos = Vector2i(x, y)
			if typ == 1:
				var advance: int = (7 - y) if white else y
				score += sign * float(advance) * 4.0
				if white:
					white_pawns_by_file[x] += 1
				else:
					black_pawns_by_file[x] += 1
	# Use complete pawn-file counts: evaluation must not depend on board scan order.
	for y in 8:
		for x in 8:
			var piece: int = int(game.chess_board[y][x])
			if piece == 2 or piece == 8:
				var white: bool = piece == 2
				var sign: float = -1.0 if white else 1.0
				var friendly_pawns: int = white_pawns_by_file[x] if white else black_pawns_by_file[x]
				var enemy_pawns: int = black_pawns_by_file[x] if white else white_pawns_by_file[x]
				if friendly_pawns == 0:
					score += sign * 6.0
					if enemy_pawns == 0:
						score += sign * 4.0
	if white_king_pos.x >= 0:
		score -= _king_shelter_score(game, white_king_pos, 1, board_piece_count)
	if black_king_pos.x >= 0:
		score += _king_shelter_score(game, black_king_pos, 2, board_piece_count)
	if white_king_pos.x < 0:
		return MATE_SCORE + 1000.0
	if black_king_pos.x < 0:
		return -MATE_SCORE - 1000.0
	return score

func _king_shelter_score(game, king: Vector2i, player: int, piece_count: int) -> float:
	var friendly_pawn: int = 1 if player == 1 else 7
	var shield: int = 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var x: int = king.x + dx
			var y: int = king.y + dy
			if x < 0 or x >= 8 or y < 0 or y >= 8:
				continue
			if int(game.chess_board[y][x]) == friendly_pawn:
				shield += 1
	var center_exposure: float = maxf(0.0, 3.0 - absf(float(king.x) - 3.5))
	if piece_count > 18:
		return float(shield) * 5.0 - center_exposure * 2.0
	return float(shield) * 1.5 + center_exposure * 1.0

func _king_terminal_score(game) -> float:
	var white_king: bool = false
	var black_king: bool = false
	for y in 8:
		for x in 8:
			var piece: int = int(game.chess_board[y][x])
			if piece == 6:
				white_king = true
			elif piece == 12:
				black_king = true
	if not white_king:
		return MATE_SCORE
	if not black_king:
		return -MATE_SCORE
	return 0.0

func _piece_value(piece: int) -> int:
	if piece == 0:
		return 0
	var typ: int = piece if piece <= 6 else piece - 6
	return PIECE_VALUES[typ]

func _center_score(to: Vector2i, piece: int) -> float:
	var typ: int = piece if piece <= 6 else piece - 6
	var center_distance: float = absf(float(to.x) - 3.5) + absf(float(to.y) - 3.5)
	if typ == 2 or typ == 3:
		return (7.0 - center_distance) * 1.5
	if typ == 1:
		return (7.0 - center_distance) * 0.45
	return 0.0
