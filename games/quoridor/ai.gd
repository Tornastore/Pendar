extends RefCounted
## Quoridor CPU policy. Difficulty changes the actual move/wall evaluation, not just timing.

const DIRS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)
]
const MASTER_SEARCH_DEPTH: int = 4 # CPU move plus up to three opponent/CPU replies.
const MASTER_WALL_BRANCH: int = 2 # Keep search practical while retaining tactical wall choices.
const WIN_SCORE: float = 100000.0

func choose_action(game, difficulty: int) -> Dictionary:
	var level: int = clampi(difficulty, 1, 6)
	if level == 6:
		return _choose_master_grandmaster(game)
	var cpu_pos: Vector2i = game.quo_pawns[1]
	var human_pos: Vector2i = game.quo_pawns[0]
	var cpu_distance: int = _distance(game, 1, cpu_pos)
	var human_distance: int = _distance(game, 0, human_pos)
	var moves: Array[Dictionary] = []

	for target in game._quo_legal_moves(1):
		var dist: int = _distance(game, 1, target)
		moves.append({"type": "move", "to": target, "distance": dist})

	if moves.is_empty():
		var forced_wall: Dictionary = _first_legal_wall(game, 1)
		return forced_wall if not forced_wall.is_empty() else {"type": "pass"}

	var best_move: Dictionary = _best_move(moves, cpu_distance, level)
	if level == 1 or game.quo_walls_left[1] <= 0:
		return best_move
	if level == 2 and human_distance > 3:
		return best_move

	var wall: Dictionary = _best_wall(game, level, cpu_distance, human_distance)
	if wall.is_empty():
		return best_move

	if level == 2:
		# Beginner AI uses a wall only as an emergency defense and avoids slowing itself.
		if human_distance <= 3 and int(wall.get("enemy_delta", 0)) >= 1 and int(wall.get("self_delta", 0)) <= 0:
			return wall
		return best_move

	var move_score: float = float(cpu_distance - int(best_move.distance)) * 100.0
	if float(wall.get("score", -INF)) > move_score:
		return wall
	return best_move



func _first_legal_wall(game, player: int) -> Dictionary:
	if int(game.quo_walls_left[player]) <= 0:
		return {}
	for y in range(8):
		for x in range(8):
			if game._quo_wall_placement_legal(x, y, false):
				return {"type": "wall", "x": x, "y": y, "vertical": false}
	for y in range(8):
		for x in range(8):
			if game._quo_wall_placement_legal(x, y, true):
				return {"type": "wall", "x": x, "y": y, "vertical": true}
	return {}

## Level 6: adversarial alpha-beta search across pawn moves and tactically useful walls.
## The live board is temporarily mutated and restored for each branch; only the final action is returned.
func _choose_master_grandmaster(game) -> Dictionary:
	var actions: Array[Dictionary] = _search_actions(game, 1, 3)
	if actions.is_empty():
		var forced_wall: Dictionary = _first_legal_wall(game, 1)
		return forced_wall if not forced_wall.is_empty() else {"type": "pass"}
	var best_action: Dictionary = actions[0]
	var best_score: float = -INF
	var alpha: float = -INF
	for action in actions:
		var snapshot: Dictionary = _save_search_state(game)
		_apply_search_action(game, 1, action)
		var score: float = _minimax(game, 0, MASTER_SEARCH_DEPTH - 1, alpha, INF)
		_restore_search_state(game, snapshot)
		if score > best_score:
			best_score = score
			best_action = action
		alpha = maxf(alpha, best_score)
	return best_action

func _minimax(game, player: int, depth: int, alpha: float, beta: float) -> float:
	# Player 1 is the computer and maximizes the evaluation; player 0 minimizes it.
	if game.quo_pawns[1].y == 0:
		return WIN_SCORE + float(depth)
	if game.quo_pawns[0].y == 8:
		return -WIN_SCORE - float(depth)
	if depth <= 0:
		return _evaluate_master_position(game)

	var actions: Array[Dictionary] = _search_actions(game, player, MASTER_WALL_BRANCH)
	if actions.is_empty():
		return _evaluate_master_position(game)
	if player == 1:
		var max_value: float = -INF
		for action in actions:
			var snapshot: Dictionary = _save_search_state(game)
			_apply_search_action(game, player, action)
			var child: float = _minimax(game, 0, depth - 1, alpha, beta)
			_restore_search_state(game, snapshot)
			max_value = maxf(max_value, child)
			alpha = maxf(alpha, max_value)
			if alpha >= beta:
				break
		return max_value
	else:
		var min_value: float = INF
		for action in actions:
			var snapshot: Dictionary = _save_search_state(game)
			_apply_search_action(game, player, action)
			var child: float = _minimax(game, 1, depth - 1, alpha, beta)
			_restore_search_state(game, snapshot)
			min_value = minf(min_value, child)
			beta = minf(beta, min_value)
			if alpha >= beta:
				break
		return min_value

func _search_actions(game, player: int, wall_limit: int) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var pawn: Vector2i = game.quo_pawns[player]
	var other_pawn: Vector2i = game.quo_pawns[1 - player]
	var own_distance: int = _distance(game, player, pawn)
	var enemy_distance: int = _distance(game, 1 - player, other_pawn)

	# Include standard straight jumps and diagonal evasions around blocked jumps.
	for target in game._quo_legal_moves_from(player, pawn):
		var target_distance: int = _distance(game, player, target)
		var move_order: float = float(own_distance - target_distance) * 100.0
		if (player == 1 and target.y == 0) or (player == 0 and target.y == 8):
			move_order = WIN_SCORE
		else:
			move_order += -absf(float(target.x) - 4.0) * 0.2
		actions.append({"type": "move", "to": target, "order_score": move_order})

	# Wall actions are the most important branching factor. Evaluate all board edges,
	# then retain only the strongest few for this ply, without touching the real turn.
	if int(game.quo_walls_left[player]) > 0:
		var wall_actions: Array[Dictionary] = []
		for y in range(8):
			for x in range(8):
				var h_key: String = "h%d,%d" % [x, y]
				var candidate: Dictionary = _search_wall_candidate(game, player, h_key, x, y, false, own_distance, enemy_distance)
				if not candidate.is_empty():
					wall_actions.append(candidate)
		for y in range(8):
			for x in range(8):
				var v_key: String = "v%d,%d" % [x, y]
				var candidate: Dictionary = _search_wall_candidate(game, player, v_key, x, y, true, own_distance, enemy_distance)
				if not candidate.is_empty():
					wall_actions.append(candidate)
		wall_actions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("order_score", -INF)) > float(b.get("order_score", -INF))
		)
		for index in range(mini(wall_limit, wall_actions.size())):
			actions.append(wall_actions[index])

	actions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("order_score", -INF)) > float(b.get("order_score", -INF))
	)
	return actions

func _search_wall_candidate(game, player: int, key: String, x: int, y: int, vertical: bool, own_distance: int, enemy_distance: int) -> Dictionary:
	if not game._quo_wall_geometry_clear(x, y, vertical):
		return {}
	game.quo_walls[key] = true
	var paths_ok: bool = true
	for path_player in range(game.quo_player_count):
		if not game._quo_path_exists(path_player):
			paths_ok = false
			break
	var new_own_distance: int = _distance(game, player, game.quo_pawns[player]) if paths_ok else 999
	var new_enemy_distance: int = _distance(game, 1 - player, game.quo_pawns[1 - player]) if paths_ok else 999
	game.quo_walls.erase(key)
	if not paths_ok or new_own_distance >= 999 or new_enemy_distance >= 999:
		return {}
	var enemy_delta: int = new_enemy_distance - enemy_distance
	if enemy_delta <= 0:
		return {}
	var own_delta: int = new_own_distance - own_distance
	var walls_spent: int = 10 - int(game.quo_walls_left[player])
	var order_score: float = float(enemy_delta) * 108.0 - maxf(0.0, float(own_delta)) * 92.0
	order_score -= 12.0 + float(walls_spent) * 5.0
	if enemy_distance <= 2:
		order_score += 28.0
	return {
		"type": "wall", "x": x, "y": y, "vertical": vertical,
		"enemy_delta": enemy_delta, "self_delta": own_delta,
		"order_score": order_score,
	}

func _evaluate_master_position(game) -> float:
	var cpu_pos: Vector2i = game.quo_pawns[1]
	var human_pos: Vector2i = game.quo_pawns[0]
	if cpu_pos.y == 0:
		return WIN_SCORE
	if human_pos.y == 8:
		return -WIN_SCORE
	var cpu_distance: int = _distance(game, 1, cpu_pos)
	var human_distance: int = _distance(game, 0, human_pos)
	if cpu_distance >= 999:
		return -WIN_SCORE * 0.5
	if human_distance >= 999:
		return WIN_SCORE * 0.5
	var score: float = float(human_distance - cpu_distance) * 75.0
	score += float(int(game.quo_walls_left[1]) - int(game.quo_walls_left[0])) * 4.0
	# Prefer useful mobility but keep it a small tie-breaker behind race distance.
	var cpu_options: int = _legal_move_count(game, 1)
	var human_options: int = _legal_move_count(game, 0)
	score += float(cpu_options - human_options) * 0.35
	return score

func _legal_move_count(game, player: int) -> int:
	return game._quo_legal_moves(player).size()

func _save_search_state(game) -> Dictionary:
	return {
		"pawns": game.quo_pawns.duplicate(),
		"walls_left": game.quo_walls_left.duplicate(),
		"walls": game.quo_walls.duplicate(),
	}

func _restore_search_state(game, snapshot: Dictionary) -> void:
	game.quo_pawns = snapshot["pawns"]
	game.quo_walls_left = snapshot["walls_left"]
	game.quo_walls = snapshot["walls"]

func _apply_search_action(game, player: int, action: Dictionary) -> void:
	if str(action.get("type", "move")) == "move":
		game.quo_pawns[player] = action.get("to", game.quo_pawns[player])
	else:
		var key: String = ("v%d,%d" % [int(action.x), int(action.y)]) if bool(action.vertical) else ("h%d,%d" % [int(action.x), int(action.y)])
		game.quo_walls[key] = true
		game.quo_walls_left[player] = maxi(0, int(game.quo_walls_left[player]) - 1)

func _best_move(moves: Array[Dictionary], current_distance: int, level: int) -> Dictionary:
	if level == 1:
		var shortest: int = 999
		for move in moves:
			shortest = mini(shortest, int(move.distance))
		var easy_choices: Array[Dictionary] = []
		for move in moves:
			if int(move.distance) == shortest:
				easy_choices.append(move)
		return easy_choices[randi_range(0, easy_choices.size() - 1)]

	var best: Array[Dictionary] = []
	var best_quality: float = -INF
	for move in moves:
		var progress: int = current_distance - int(move.distance)
		# Higher levels break equal-distance choices toward the board centre.
		var target: Vector2i = move.to
		var centrality: float = -absf(float(target.x) - 4.0)
		var quality: float = float(progress) * 100.0 + (centrality * float(level) * 0.25)
		if quality > best_quality + 0.01:
			best_quality = quality
			best.clear()
			best.append(move)
		elif absf(quality - best_quality) < 0.01:
			best.append(move)
	if best.is_empty():
		return moves[0]
	# Stable tie-breaking at stronger levels avoids random, strategically weak moves.
	best.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ax: Vector2i = a.to
		var bx: Vector2i = b.to
		if ax.x != bx.x:
			return abs(ax.x - 4) < abs(bx.x - 4)
		return ax.y < bx.y
	)
	return best[0]

func _best_wall(game, level: int, current_cpu_distance: int, current_human_distance: int) -> Dictionary:
	var best: Dictionary = {}
	var best_score: float = -INF
	var cpu_walls_spent: int = 10 - int(game.quo_walls_left[1])
	var urgency: float = clampf((5.0 - float(current_human_distance)) / 5.0, 0.0, 1.0)
	# Once CPU has a clear route advantage, advancing is usually better than
	# spending more walls merely to widen an already comfortable lead.
	var lead_penalty: float = maxf(0.0, float(current_human_distance - current_cpu_distance)) * 65.0
	var enemy_weight: float = 0.0
	var self_penalty: float = 0.0
	var turn_cost: float = 0.0
	var wall_cost: float = 0.0
	match level:
		2:
			enemy_weight = 112.0
			self_penalty = 100.0
			turn_cost = 25.0
			wall_cost = 4.0 + float(cpu_walls_spent) * 4.0
		3:
			enemy_weight = 115.0
			self_penalty = 65.0
			turn_cost = 32.0
			wall_cost = 5.0 + float(cpu_walls_spent) * 4.0
		4:
			enemy_weight = 128.0
			self_penalty = 55.0
			turn_cost = 30.0
			wall_cost = 7.0 + float(cpu_walls_spent) * 3.5
		5:
			enemy_weight = 124.0 + urgency * 20.0
			self_penalty = 58.0
			turn_cost = 27.0 - urgency * 5.0
			wall_cost = 7.0 + float(cpu_walls_spent) * 3.5 - urgency * 10.0

	# Each candidate is a full two-edge wall; geometry and path legality are checked by rules.gd.
	for y in range(8):
		for x in range(8):
			var key: String = "h%d,%d" % [x, y]
			var candidate: Dictionary = _evaluate_wall(game, key, x, y, false, current_cpu_distance, current_human_distance)
			if not candidate.is_empty():
				var score: float = _wall_score(candidate, level, enemy_weight, self_penalty, turn_cost, wall_cost, urgency, lead_penalty)
				if score > best_score:
					best_score = score
					best = candidate
	for y in range(8):
		for x in range(8):
			var key: String = "v%d,%d" % [x, y]
			var candidate: Dictionary = _evaluate_wall(game, key, x, y, true, current_cpu_distance, current_human_distance)
			if not candidate.is_empty():
				var score: float = _wall_score(candidate, level, enemy_weight, self_penalty, turn_cost, wall_cost, urgency, lead_penalty)
				if score > best_score:
					best_score = score
					best = candidate
	if best.is_empty():
		return {}
	best.score = best_score
	return best

func _evaluate_wall(game, key: String, x: int, y: int, vertical: bool, cpu_distance: int, human_distance: int) -> Dictionary:
	if not game._quo_wall_geometry_clear(x, y, vertical):
		return {}
	game.quo_walls[key] = true
	var valid: bool = true
	for path_player in range(game.quo_player_count):
		if not game._quo_path_exists(path_player):
			valid = false
			break
	var candidate: Dictionary = {}
	if valid:
		var new_cpu_distance: int = _distance(game, 1, game.quo_pawns[1])
		var new_human_distance: int = _distance(game, 0, game.quo_pawns[0])
		var enemy_delta: int = new_human_distance - human_distance
		var self_delta: int = new_cpu_distance - cpu_distance
		if enemy_delta > 0:
			candidate = {
				"type": "wall",
				"x": x,
				"y": y,
				"vertical": vertical,
				"enemy_delta": enemy_delta,
				"self_delta": self_delta,
			}
	game.quo_walls.erase(key)
	return candidate

func _wall_score(candidate: Dictionary, level: int, enemy_weight: float, self_penalty: float, turn_cost: float, wall_cost: float, urgency: float, lead_penalty: float) -> float:
	var score: float = float(candidate.enemy_delta) * enemy_weight
	score -= maxf(0.0, float(candidate.self_delta)) * self_penalty
	score -= turn_cost + wall_cost + lead_penalty
	if level >= 4:
		# Preserve the wall for later unless an opponent is approaching the finish.
		score += urgency * float(candidate.enemy_delta) * 12.0
		if int(candidate.self_delta) == 0:
			score += 8.0
	return score

func _distance(game, player: int, start: Vector2i) -> int:
	var distances: Dictionary = {start: 0}
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		if game._quo_goal_reached(player, current):
			return int(distances[current])
		for next in game._quo_legal_moves_from(player, current):
			if not distances.has(next):
				distances[next] = int(distances[current]) + 1
				queue.append(next)
	return 999
