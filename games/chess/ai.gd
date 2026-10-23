extends RefCounted
## Six-level chess AI using legal moves, iterative deepening, alpha-beta,
## transposition caching, move ordering, and check-aware quiescence search.
## Scores are from Black's perspective: positive is good for Black.

const PIECE_VALUES: Array[int] = [0, 100, 320, 335, 500, 900, 20000]
const MATE_SCORE: float = 100000.0
const DRAW_SCORE: float = 0.0
const WHITE_CASTLING_MASK: int = 3
const BLACK_CASTLING_MASK: int = 12

var _difficulty: int = 3
var _nodes: int = 0
var _node_limit: int = 0
var _deadline_usec: int = 0
var _search_aborted: bool = false
var _qdepth_limit: int = 5
var _transposition: Dictionary = {}
var _path_repetitions: Dictionary = {}
var should_claim_draw: bool = false

func choose_move(game, difficulty: int) -> Array:
	_difficulty = clampi(difficulty, 1, 6)
	should_claim_draw = false
	_transposition.clear()
	_path_repetitions.clear()
	_nodes = 0
	_search_aborted = false
	var side: int = int(game.chess_turn)
	var legal_moves: Array = game._chess_all_moves(side)
	if legal_moves.is_empty():
		return []
	# Never miss an immediate checkmate, even at the lowest difficulty or when
	# the deeper search is close to its time/node budget. This tactical pre-pass
	# also makes mate-in-one behavior deterministic across difficulty settings.
	var mate_in_one: Array = _find_mate_in_one(game, legal_moves)
	if not mate_in_one.is_empty():
		return mate_in_one
	var ordered: Array[Dictionary] = _ordered_moves(game, legal_moves, side)
	if _difficulty == 1:
		return ordered[randi_range(0, ordered.size() - 1)]["move"]
	if _difficulty == 2:
		return _choose_greedy(game, ordered, side)
	var root_can_claim_draw: bool = _can_claim_draw_position(game)
	var last_completed_root_score: float = _evaluate(game)

	# Difficulty levels grow in both depth and node budget. Iterative deepening
	# keeps a valid move ready even when the top iteration hits its budget.
	var depth_by_level: Array[int] = [0, 0, 1, 2, 3, 4, 5]
	var node_limit_by_level: Array[int] = [0, 0, 1800, 3600, 7200, 14000, 24000]
	var time_limit_usec_by_level: Array[int] = [0, 0, 180000, 300000, 450000, 650000, 900000]
	var max_depth: int = depth_by_level[_difficulty]
	_node_limit = node_limit_by_level[_difficulty]
	_deadline_usec = Time.get_ticks_usec() + time_limit_usec_by_level[_difficulty]
	var best_move: Array = ordered[0]["move"]
	for depth in range(1, max_depth + 1):
		_nodes = 0
		_search_aborted = false
		var iteration_best: Array = []
		var iteration_best_score: float = -INF if side == 2 else INF
		var alpha: float = -INF
		var beta: float = INF
		var root_order: Array[Dictionary] = _ordered_moves(game, legal_moves, side, best_move)
		for entry in root_order:
			if _budget_reached():
				_search_aborted = true
				break
			var move: Array = entry["move"]
			var snapshot: Dictionary = game._chess_simulate_move(move[0], move[1], _promotion_type_from_move(move))
			if snapshot.is_empty():
				continue
			_push_path_position(game)
			var score: float = _search(game, depth - 1, alpha, beta, 1)
			_pop_path_position(game)
			game._chess_restore_simulation(snapshot)
			if side == 2:
				if score > iteration_best_score:
					iteration_best_score = score
					iteration_best = move
				alpha = maxf(alpha, iteration_best_score)
			else:
				if score < iteration_best_score:
					iteration_best_score = score
					iteration_best = move
				beta = minf(beta, iteration_best_score)
			if _search_aborted:
				break
		# Do not replace a fully completed iteration with partial search results.
		if _search_aborted or iteration_best.is_empty():
			break
		best_move = iteration_best
		last_completed_root_score = iteration_best_score
	if root_can_claim_draw and ((side == 2 and last_completed_root_score < 0.0) or (side == 1 and last_completed_root_score > 0.0)):
		should_claim_draw = true
	return best_move

func _find_mate_in_one(game, moves: Array) -> Array:
	for move_value in moves:
		var move: Array = move_value
		var snapshot: Dictionary = game._chess_simulate_move(move[0], move[1], _promotion_type_from_move(move))
		if snapshot.is_empty():
			continue
		var defending_side: int = int(game.chess_turn)
		var replies: Array = game._chess_all_moves(defending_side)
		var is_mate: bool = replies.is_empty() and game._chess_king_in_check(defending_side).x >= 0
		game._chess_restore_simulation(snapshot)
		if is_mate:
			return move
	return []


func _choose_greedy(game, ordered: Array[Dictionary], side: int) -> Array:
	var best_move: Array = ordered[0]["move"]
	var best_score: float = -INF if side == 2 else INF
	var can_claim_draw: bool = _can_claim_draw_position(game)
	for entry in ordered:
		var move: Array = entry["move"]
		var snapshot: Dictionary = game._chess_simulate_move(move[0], move[1], _promotion_type_from_move(move))
		if snapshot.is_empty():
			continue
		var score: float = _terminal_or_static(game, int(game.chess_turn), 1)
		game._chess_restore_simulation(snapshot)
		if side == 2 and score > best_score:
			best_score = score
			best_move = move
		elif side == 1 and score < best_score:
			best_score = score
			best_move = move
	if can_claim_draw and ((side == 2 and best_score < 0.0) or (side == 1 and best_score > 0.0)):
		should_claim_draw = true
	return best_move

func _search(game, depth: int, alpha_in: float, beta_in: float, ply: int) -> float:
	_nodes += 1
	if _budget_reached():
		_search_aborted = true
		return _evaluate(game)
	var side: int = int(game.chess_turn)
	var moves: Array = game._chess_all_moves(side)
	if moves.is_empty():
		if game._chess_king_in_check(side).x >= 0:
			return (-MATE_SCORE + float(ply)) if side == 2 else (MATE_SCORE - float(ply))
		return DRAW_SCORE # stalemate
	if _is_draw_position(game):
		return DRAW_SCORE
	var can_claim_draw: bool = _can_claim_draw_position(game)
	if depth <= 0:
		return _quiescence(game, alpha_in, beta_in, ply, _qdepth_limit)

	var alpha: float = alpha_in
	var beta: float = beta_in
	var alpha_original: float = alpha
	var beta_original: float = beta
	var position_key: String = _tt_key(game)
	var preferred_move: Array = []
	if _transposition.has(position_key):
		var cached: Dictionary = _transposition[position_key]
		preferred_move = cached.get("move", [])
		if int(cached.get("depth", -1)) >= depth:
			var cached_score: float = float(cached.get("score", 0.0))
			match str(cached.get("bound", "exact")):
				"exact": return _apply_draw_claim_option(cached_score, side, can_claim_draw)
				"lower": alpha = maxf(alpha, cached_score)
				"upper": beta = minf(beta, cached_score)
			if alpha >= beta:
				return _apply_draw_claim_option(cached_score, side, can_claim_draw)

	var ordered: Array[Dictionary] = _ordered_moves(game, moves, side, preferred_move)
	var maximizing: bool = side == 2
	var best_score: float = 0.0 if can_claim_draw else (-INF if maximizing else INF)
	if can_claim_draw:
		if maximizing:
			alpha = maxf(alpha, 0.0)
		else:
			beta = minf(beta, 0.0)
		if alpha >= beta:
			return DRAW_SCORE
	var best_move: Array = []
	var cutoff: bool = false
	for entry in ordered:
		if _budget_reached():
			_search_aborted = true
			cutoff = true
			break
		var move: Array = entry["move"]
		var snapshot: Dictionary = game._chess_simulate_move(move[0], move[1], _promotion_type_from_move(move))
		if snapshot.is_empty():
			continue
		_push_path_position(game)
		var score: float = _search(game, depth - 1, alpha, beta, ply + 1)
		_pop_path_position(game)
		game._chess_restore_simulation(snapshot)
		if _search_aborted:
			cutoff = true
			break
		if maximizing:
			if score > best_score:
				best_score = score
				best_move = move
			alpha = maxf(alpha, best_score)
		else:
			if score < best_score:
				best_score = score
				best_move = move
			beta = minf(beta, best_score)
		if alpha >= beta:
			cutoff = true
			break
	if is_inf(best_score):
		return _evaluate(game)
	# Do not store incomplete budget-cutoff results in the transposition table.
	if not _search_aborted and not is_inf(best_score) and absf(best_score) < MATE_SCORE - 1000.0:
		var bound: String = "exact"
		if best_score <= alpha_original:
			bound = "upper"
		elif best_score >= beta_original:
			bound = "lower"
		_transposition[position_key] = {"depth": depth, "score": best_score, "bound": bound, "move": best_move}
	return best_score

func _quiescence(game, alpha_in: float, beta_in: float, ply: int, qdepth: int) -> float:
	_nodes += 1
	if _budget_reached():
		_search_aborted = true
		return _evaluate(game)
	var side: int = int(game.chess_turn)
	var moves: Array = game._chess_all_moves(side)
	if moves.is_empty():
		if game._chess_king_in_check(side).x >= 0:
			return (-MATE_SCORE + float(ply)) if side == 2 else (MATE_SCORE - float(ply))
		return DRAW_SCORE
	if _is_draw_position(game):
		return DRAW_SCORE
	var can_claim_draw: bool = _can_claim_draw_position(game)
	var in_check: bool = game._chess_king_in_check(side).x >= 0
	var maximizing: bool = side == 2
	var alpha: float = alpha_in
	var beta: float = beta_in
	var stand_pat: float = _evaluate(game)
	if can_claim_draw:
		stand_pat = maxf(stand_pat, 0.0) if maximizing else minf(stand_pat, 0.0)
	if not in_check:
		if qdepth <= 0:
			return stand_pat
		if maximizing:
			if stand_pat >= beta:
				return stand_pat
			alpha = maxf(alpha, stand_pat)
		else:
			if stand_pat <= alpha:
				return stand_pat
			beta = minf(beta, stand_pat)
	elif qdepth <= 0:
		# Even at the quiescence boundary, consider one legal evasion instead of
		# evaluating a position where the side to move is in check.
		var evasion_best: float = 0.0 if can_claim_draw else (-INF if maximizing else INF)
		for move_value in moves:
			if _budget_reached():
				_search_aborted = true
				break
			var move: Array = move_value
			var snapshot: Dictionary = game._chess_simulate_move(move[0], move[1], _promotion_type_from_move(move))
			if snapshot.is_empty(): continue
			var score: float = _terminal_or_static(game, int(game.chess_turn), ply + 1)
			game._chess_restore_simulation(snapshot)
			if maximizing: evasion_best = maxf(evasion_best, score)
			else: evasion_best = minf(evasion_best, score)
		return evasion_best

	var candidates: Array = []
	if in_check:
		candidates = moves
	else:
		for move_value in moves:
			var move: Array = move_value
			if _is_capture(game, move) or game._chess_is_promotion_move(move[0], move[1]):
				candidates.append(move)
	if candidates.is_empty():
		return stand_pat
	var ordered: Array[Dictionary] = _ordered_moves(game, candidates, side)
	var best: float = 0.0 if can_claim_draw else (-INF if maximizing else INF)
	for entry in ordered:
		if _budget_reached():
			_search_aborted = true
			break
		var move: Array = entry["move"]
		var snapshot: Dictionary = game._chess_simulate_move(move[0], move[1], _promotion_type_from_move(move))
		if snapshot.is_empty():
			continue
		_push_path_position(game)
		var score: float = _quiescence(game, alpha, beta, ply + 1, qdepth - 1)
		_pop_path_position(game)
		game._chess_restore_simulation(snapshot)
		if _search_aborted:
			break
		if maximizing:
			best = maxf(best, score)
			alpha = maxf(alpha, best)
		else:
			best = minf(best, score)
			beta = minf(beta, best)
		if alpha >= beta:
			break
	return stand_pat if is_inf(best) else best

func _budget_reached() -> bool:
	return _nodes >= _node_limit or (_deadline_usec > 0 and Time.get_ticks_usec() >= _deadline_usec)

func _terminal_or_static(game, side: int, ply: int) -> float:
	var moves: Array = game._chess_all_moves(side)
	if moves.is_empty():
		if game._chess_king_in_check(side).x >= 0:
			return (-MATE_SCORE + float(ply)) if side == 2 else (MATE_SCORE - float(ply))
		return DRAW_SCORE
	if _is_draw_position(game):
		return DRAW_SCORE
	return _apply_draw_claim_option(_evaluate(game), side, _can_claim_draw_position(game))

func _is_draw_position(game) -> bool:
	# Only automatic draws are terminal. 50-move and threefold draws are options,
	# not compulsory draws: a winning side should be allowed to keep playing.
	if int(game.chess_halfmove_clock) >= 150 or game._chess_insufficient_material():
		return true
	var key: String = game._chess_position_key()
	var repetitions: int = game._chess_repetition_count(key) + int(_path_repetitions.get(key, 0))
	return repetitions >= 5

func _can_claim_draw_position(game) -> bool:
	if int(game.chess_halfmove_clock) >= 100:
		return true
	var key: String = game._chess_position_key()
	var repetitions: int = game._chess_repetition_count(key) + int(_path_repetitions.get(key, 0))
	return repetitions >= 3

func _apply_draw_claim_option(score: float, side: int, can_claim: bool) -> float:
	if not can_claim:
		return score
	return maxf(score, DRAW_SCORE) if side == 2 else minf(score, DRAW_SCORE)

func _push_path_position(game) -> void:
	var key: String = game._chess_position_key()
	_path_repetitions[key] = int(_path_repetitions.get(key, 0)) + 1

func _pop_path_position(game) -> void:
	var key: String = game._chess_position_key()
	var count: int = int(_path_repetitions.get(key, 0))
	if count <= 1:
		_path_repetitions.erase(key)
	else:
		_path_repetitions[key] = count - 1

func _tt_key(game) -> String:
	var key: String = game._chess_position_key()
	return key + "|h" + str(game.chess_halfmove_clock) + "|r" + str(game._chess_repetition_count(key) + int(_path_repetitions.get(key, 0)))

func _ordered_moves(game, moves: Array, side: int, preferred_move: Array = []) -> Array[Dictionary]:
	var ranked: Array[Dictionary] = []
	for move_value in moves:
		var move: Array = move_value
		var from: Vector2i = move[0]
		var to: Vector2i = move[1]
		var moving: int = int(game.chess_board[from.y][from.x])
		var target: int = int(game.chess_board[to.y][to.x])
		var captured_value: int = _piece_value(target)
		if target == 0 and _piece_type(moving) == 1 and to == game.chess_en_passant and from.x != to.x:
			captured_value = 100
		var score: float = float(captured_value) * 10.0 - float(_piece_value(moving)) * 0.08
		if game._chess_is_promotion_move(from, to):
			var promotion_type: int = _promotion_type_from_move(move)
			score += 8000.0 + float(PIECE_VALUES[promotion_type])
		if _piece_type(moving) == 6 and absi(to.x - from.x) == 2:
			score += 120.0
		var center_distance: float = absf(float(to.x) - 3.5) + absf(float(to.y) - 3.5)
		if _piece_type(moving) in [2, 3]:
			score += (7.0 - center_distance) * 1.8
		var same_preferred_move: bool = preferred_move.size() >= 2 and from == preferred_move[0] and to == preferred_move[1]
		if same_preferred_move and preferred_move.size() >= 3 and move.size() >= 3:
			same_preferred_move = int(move[2]) == int(preferred_move[2])
		if same_preferred_move:
			score += 1000000.0
		ranked.append({"move": move, "score": score})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"])
	)
	return ranked


func _promotion_type_from_move(move: Array) -> int:
	return int(move[2]) if move.size() >= 3 else 5

func _apply_move(game, move: Array) -> Dictionary:
	return game._chess_simulate_move(move[0], move[1], _promotion_type_from_move(move))

func _undo_move(game, snapshot: Dictionary) -> void:
	game._chess_restore_simulation(snapshot)

func _evaluate(game) -> float:
	var score: float = 0.0
	var white_king := Vector2i(-1, -1)
	var black_king := Vector2i(-1, -1)
	var piece_count: int = 0
	var white_pawns: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
	var black_pawns: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
	var white_bishops: int = 0
	var black_bishops: int = 0
	for y in range(8):
		for x in range(8):
			var piece: int = int(game.chess_board[y][x])
			if piece == 0:
				continue
			piece_count += 1
			var white: bool = piece <= 6
			var typ: int = _piece_type(piece)
			var sign: float = -1.0 if white else 1.0
			score += sign * float(PIECE_VALUES[typ])
			var center_distance: float = absf(float(x) - 3.5) + absf(float(y) - 3.5)
			match typ:
				1:
					var advance: int = (6 - y) if white else (y - 1)
					score += sign * float(advance) * 7.0
					if white: white_pawns[x] += 1
					else: black_pawns[x] += 1
					if _is_passed_pawn(game, x, y, 1 if white else 2):
						score += sign * (14.0 + float(advance * advance) * 1.5)
				2: score += sign * (7.0 - center_distance) * 5.0
				3:
					score += sign * (7.0 - center_distance) * 3.0
					if white: white_bishops += 1
					else: black_bishops += 1
				4: score += sign * (3.5 - absf(float(x) - 3.5)) * 1.6
				5: score += sign * (7.0 - center_distance) * 1.2
				6:
					if white: white_king = Vector2i(x, y)
					else: black_king = Vector2i(x, y)
	for x in range(8):
		if white_pawns[x] > 1:
			score += float(white_pawns[x] - 1) * 14.0
		if black_pawns[x] > 1:
			score -= float(black_pawns[x] - 1) * 14.0
		# Penalize actual isolated pawns (a pawn on a file with no friendly
		# pawn on either adjacent file), not empty files beside a pawn.
		if white_pawns[x] > 0 and (x == 0 or white_pawns[x - 1] == 0) and (x == 7 or white_pawns[x + 1] == 0):
			score -= float(white_pawns[x]) * 12.0
		if black_pawns[x] > 0 and (x == 0 or black_pawns[x - 1] == 0) and (x == 7 or black_pawns[x + 1] == 0):
			score += float(black_pawns[x]) * 12.0
	# Rooks are more effective on open and semi-open files.
	for y in range(8):
		for x in range(8):
			var piece: int = int(game.chess_board[y][x])
			if _piece_type(piece) != 4:
				continue
			var white_rook: bool = piece <= 6
			var own_pawns: int = int(white_pawns[x] if white_rook else black_pawns[x])
			var enemy_pawns: int = int(black_pawns[x] if white_rook else white_pawns[x])
			var open_file_bonus: float = 18.0 if enemy_pawns == 0 else (8.0 if own_pawns == 0 else 0.0)
			score += (-1.0 if white_rook else 1.0) * open_file_bonus
	if white_bishops >= 2: score -= 28.0
	if black_bishops >= 2: score += 28.0
	if piece_count > 14:
		if (int(game.chess_castling_rights) & WHITE_CASTLING_MASK) != 0:
			score -= 12.0
		if (int(game.chess_castling_rights) & BLACK_CASTLING_MASK) != 0:
			score += 12.0
	if white_king.x >= 0:
		score -= _king_safety(game, white_king, 1, piece_count)
	if black_king.x >= 0:
		score += _king_safety(game, black_king, 2, piece_count)
	if game._chess_king_in_check(1).x >= 0: score += 42.0
	if game._chess_king_in_check(2).x >= 0: score -= 42.0
	return score

func _is_passed_pawn(game, file_x: int, rank_y: int, side: int) -> bool:
	var enemy_pawn: int = 7 if side == 1 else 1
	var direction: int = -1 if side == 1 else 1
	var y: int = rank_y + direction
	while y >= 0 and y < 8:
		for x in range(maxi(0, file_x - 1), mini(7, file_x + 1) + 1):
			if int(game.chess_board[y][x]) == enemy_pawn:
				return false
		y += direction
	return true

func _king_safety(game, king: Vector2i, side: int, piece_count: int) -> float:
	var friendly_pawn: int = 1 if side == 1 else 7
	var shield: int = 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0: continue
			var x: int = king.x + dx
			var y: int = king.y + dy
			if x >= 0 and x < 8 and y >= 0 and y < 8 and int(game.chess_board[y][x]) == friendly_pawn:
				shield += 1
	var center_exposure: float = maxf(0.0, 3.5 - absf(float(king.x) - 3.5))
	if piece_count > 14:
		return float(shield) * 7.0 - center_exposure * 3.0
	return float(shield) * 1.5 + center_exposure * 1.4

func _is_capture(game, move: Array) -> bool:
	var from: Vector2i = move[0]
	var to: Vector2i = move[1]
	if int(game.chess_board[to.y][to.x]) != 0:
		return true
	var moving: int = int(game.chess_board[from.y][from.x])
	return _piece_type(moving) == 1 and to == game.chess_en_passant and from.x != to.x

func _piece_type(piece: int) -> int:
	if piece <= 0: return 0
	return piece if piece <= 6 else piece - 6

func _piece_value(piece: int) -> int:
	return PIECE_VALUES[_piece_type(piece)]
