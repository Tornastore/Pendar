extends RefCounted
## Six-level chess AI for the current Mind Bastion chess rules.
## Uses material/positional scoring and bounded alpha-beta search. The base game
## currently uses pseudo-legal moves and king capture rather than full checkmate rules.

const PIECE_VALUES: Array[int] = [0, 100, 320, 330, 500, 900, 20000]
const MATE_SCORE: float = 50000.0

var _difficulty: int = 3
var _nodes: int = 0
var _node_limit: int = 4000
var _branch_limit: int = 8

func choose_move(game, difficulty: int) -> Array:
	_difficulty = clampi(difficulty, 1, 6)
	var moves: Array = game._chess_all_moves(2)
	if moves.is_empty():
		return []

	# Level 1 deliberately plays an unpredictable legal-ish move.
	if _difficulty == 1:
		return moves[randi_range(0, moves.size() - 1)]

	var ordered: Array[Dictionary] = _ordered_moves(game, moves, 2)
	if _difficulty == 2:
		# Easy: prioritize safe material wins and promotions without searching replies.
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

	var depths: Array[int] = [0, 0, 1, 2, 3, 4]
	var node_limits: Array[int] = [0, 0, 0, 800, 2200, 5200]
	var branch_limits: Array[int] = [0, 0, 0, 12, 9, 7]
	var depth: int = depths[_difficulty - 1]
	_node_limit = node_limits[_difficulty - 1]
	_branch_limit = branch_limits[_difficulty - 1]
	_nodes = 0

	var best: Array = ordered[0]["move"]
	var best_value: float = -INF
	var alpha: float = -INF
	for entry in ordered:
		var move: Array = entry["move"]
		var snapshot: Dictionary = _apply_move(game, move)
		var score: float
		if depth <= 1:
			score = _evaluate(game)
		else:
			score = _search(game, 1, depth - 1, alpha, INF)
		_undo_move(game, snapshot)
		if score > best_value:
			best_value = score
			best = move
		alpha = maxf(alpha, best_value)
	return best

func _search(game, turn: int, depth: int, alpha_in: float, beta_in: float) -> float:
	_nodes += 1
	var terminal: float = _king_terminal_score(game)
	if absf(terminal) >= MATE_SCORE:
		return terminal
	if depth <= 0 or _nodes >= _node_limit:
		return _evaluate(game)

	var moves: Array = game._chess_all_moves(turn)
	if moves.is_empty():
		return -MATE_SCORE if turn == 2 else MATE_SCORE
	var ordered: Array[Dictionary] = _ordered_moves(game, moves, turn)
	if depth >= 2 and ordered.size() > _branch_limit:
		ordered.resize(_branch_limit)

	if turn == 2:
		var best_value: float = -INF
		var alpha: float = alpha_in
		for entry in ordered:
			if _nodes >= _node_limit:
				break
			var snapshot: Dictionary = _apply_move(game, entry["move"])
			var value: float = _search(game, 1, depth - 1, alpha, beta_in)
			_undo_move(game, snapshot)
			best_value = maxf(best_value, value)
			alpha = maxf(alpha, best_value)
			if alpha >= beta_in:
				break
		return _evaluate(game) if is_inf(best_value) else best_value

	var worst_value: float = INF
	var beta: float = beta_in
	for entry in ordered:
		if _nodes >= _node_limit:
			break
		var snapshot: Dictionary = _apply_move(game, entry["move"])
		var value: float = _search(game, 2, depth - 1, alpha_in, beta)
		_undo_move(game, snapshot)
		worst_value = minf(worst_value, value)
		beta = minf(beta, worst_value)
		if alpha_in >= beta:
			break
	return _evaluate(game) if is_inf(worst_value) else worst_value

func _ordered_moves(game, moves: Array, turn: int) -> Array[Dictionary]:
	var ranked: Array[Dictionary] = []
	for move_value in moves:
		var move: Array = move_value
		var from: Vector2i = move[0]
		var to: Vector2i = move[1]
		var moving: int = int(game.chess_board[from.y][from.x])
		var target: int = int(game.chess_board[to.y][to.x])
		var score: float = float(_piece_value(target)) * 10.0 - float(_piece_value(moving)) * 0.08
		if (moving == 7 and to.y == 7) or (moving == 1 and to.y == 0):
			score += 950.0
		score += _center_score(to, moving) + randf_range(0.0, 0.1)
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
	var white_king: bool = false
	var black_king: bool = false
	for y in 8:
		for x in 8:
			var piece: int = int(game.chess_board[y][x])
			if piece == 0:
				continue
			var white: bool = piece <= 6
			var typ: int = piece if white else piece - 6
			var sign: float = -1.0 if white else 1.0
			score += sign * float(PIECE_VALUES[typ])
			if piece == 6:
				white_king = true
			elif piece == 12:
				black_king = true
			score += sign * _center_score(Vector2i(x, y), piece)
			if typ == 1:
				var advance: int = (7 - y) if white else y
				score += sign * float(advance) * 4.0
	if not white_king:
		return MATE_SCORE + 1000.0
	if not black_king:
		return -MATE_SCORE - 1000.0
	return score

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
