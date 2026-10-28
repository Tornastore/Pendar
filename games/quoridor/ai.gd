extends RefCounted
## Quoridor CPU policy. Difficulty changes the actual move/wall evaluation, not just timing.

const DIRS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)
]
const MASTER_SEARCH_DEPTH: int = 5 # Grandmaster searches one ply deeper under a larger hard budget.
const MASTER_WALL_BRANCH: int = 2
const WIN_SCORE: float = 100000.0
# A browser game's main thread must never be occupied by an unbounded search.
# These budgets cap wall evaluations, minimax nodes and wall-clock time per move.
const EXPERT_SEARCH_BUDGET_USEC: int = 180000
const GRANDMASTER_SEARCH_BUDGET_USEC: int = 320000
const EXPERT_NODE_BUDGET: int = 144
const GRANDMASTER_NODE_BUDGET: int = 360
const EXPERT_WALL_EVALUATION_BUDGET: int = 96
const GRANDMASTER_WALL_EVALUATION_BUDGET: int = 192
var _active_search_depth: int = MASTER_SEARCH_DEPTH
var _active_wall_branch: int = MASTER_WALL_BRANCH
var _root_wall_branch: int = 2
var _active_wall_route_segments: int = 8
var _search_deadline_usec: int = 0
var _nodes_remaining: int = 0
var _wall_evaluations_remaining: int = 0
var _search_aborted: bool = false
const IMMEDIATE_REVERSAL_PENALTY: float = 175.0
const RECENT_REVISIT_PENALTY: float = 42.0
const HISTORY_LOOKBACK: int = 9

func choose_action(game, difficulty: int) -> Dictionary:
	var level: int = clampi(difficulty, 1, 6)
	# Never miss an immediate win, regardless of the selected difficulty.
	for target in game._quo_legal_moves(1):
		if game._quo_goal_reached(1, target):
			return {"type": "move", "to": target}
	# If the human can finish on their next move, spend a wall to block that route
	# whenever a legal defensive wall exists. This prevents avoidable instant losses
	# on every difficulty, including levels 1-4.
	var urgent_block: Dictionary = _block_immediate_opponent_win(game)
	if not urgent_block.is_empty():
		return urgent_block
	if level >= 5:
		# Expert and Grandmaster use bounded adversarial search. The prior budgets
		# interrupted most wall analysis before useful choices were explored.
		_active_search_depth = 4 if level == 5 else MASTER_SEARCH_DEPTH
		_active_wall_branch = 2 if level == 5 else 3
		_root_wall_branch = 2 if level == 5 else 3
		_search_deadline_usec = Time.get_ticks_usec() + (EXPERT_SEARCH_BUDGET_USEC if level == 5 else GRANDMASTER_SEARCH_BUDGET_USEC)
		_nodes_remaining = EXPERT_NODE_BUDGET if level == 5 else GRANDMASTER_NODE_BUDGET
		_wall_evaluations_remaining = EXPERT_WALL_EVALUATION_BUDGET if level == 5 else GRANDMASTER_WALL_EVALUATION_BUDGET
		_active_wall_route_segments = 10 if level == 5 else 12
		_search_aborted = false
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

	var best_move: Dictionary = _best_move(game, moves, cpu_distance, level)
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



func _block_immediate_opponent_win(game) -> Dictionary:
	if int(game.quo_player_count) != 2 or int(game.quo_walls_left[1]) <= 0:
		return {}
	var immediate_threat: bool = false
	for target in game._quo_legal_moves(0):
		if game._quo_goal_reached(0, target):
			immediate_threat = true
			break
	if not immediate_threat:
		return {}
	var cpu_distance: int = _distance(game, 1, game.quo_pawns[1])
	var human_distance: int = _distance(game, 0, game.quo_pawns[0])
	var best: Dictionary = {}
	var best_score: float = -INF
	for info in _route_wall_candidates(game, 0, 12):
		var candidate: Dictionary = _evaluate_wall(game, str(info.key), int(info.x), int(info.y), bool(info.vertical), cpu_distance, human_distance)
		if candidate.is_empty() or int(candidate.get("enemy_delta", 0)) <= 0:
			continue
		# When the human is one move from the goal, any wall that raises the true
		# shortest-path distance above one prevents the immediate win.
		var score: float = float(candidate.enemy_delta) * 500.0
		score -= maxf(0.0, float(candidate.get("self_delta", 0))) * 90.0
		score += 14.0 if int(candidate.get("self_delta", 0)) <= 0 else 0.0
		if score > best_score:
			best_score = score
			best = candidate
	if not best.is_empty():
		best["score"] = best_score
	return best


func choose_action_for_player(game, difficulty: int, player: int) -> Dictionary:
	# Multiplayer CPU policy for the four-seat variant. This uses one shared rules
	# engine but evaluates every opponent against their own edge goal, instead of
	# treating seat 0 as the only human and seat 1 as the only CPU.
	var level: int = clampi(difficulty, 1, 6)
	if int(game.quo_player_count) != 4 or player < 1 or player > 3:
		return choose_action(game, level)
	var own_pos: Vector2i = game.quo_pawns[player]
	var own_distance: int = _distance(game, player, own_pos)
	var moves: Array[Dictionary] = []
	for target in game._quo_legal_moves(player):
		if game._quo_goal_reached(player, target):
			return {"type": "move", "to": target}
		var target_distance: int = _distance(game, player, target)
		var score: float = float(own_distance - target_distance) * 105.0
		# Prefer the centre when progress is equivalent, but do not overvalue it.
		score -= absf(float(target.x) - 4.0) * 0.45 + absf(float(target.y) - 4.0) * 0.20
		var history: Array = game.quo_cpu_position_history_by_player.get(str(player), [])
		if history.size() >= 2 and target == history[history.size() - 2]:
			score -= 150.0
		elif target in history.slice(maxi(0, history.size() - 5), history.size()):
			score -= 32.0
		var noise: Array[float] = [0.0, 24.0, 14.0, 8.0, 3.0, 0.8, 0.0]
		score += randf_range(-noise[level], noise[level])
		moves.append({"type": "move", "to": target, "score": score})
	moves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.score) > float(b.score))
	var best_move: Dictionary = moves[0] if not moves.is_empty() else {"type": "pass"}
	var best_score: float = float(best_move.get("score", -INF))
	if level < 3 or int(game.quo_walls_left[player]) <= 0:
		return best_move

	var opponents: Array[Dictionary] = []
	for other in range(4):
		if other == player:
			continue
		opponents.append({"player": other, "distance": _distance(game, other, game.quo_pawns[other])})
	opponents.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.distance) < int(b.distance))
	var candidate_map: Dictionary = {}
	var target_limit: int = 1 if level == 3 else (2 if level < 5 else 3)
	for oi in range(mini(target_limit, opponents.size())):
		var target_player: int = int(opponents[oi].player)
		for wall in _route_wall_candidates(game, target_player, 7 if level < 5 else 10):
			candidate_map[str(wall.key)] = wall
	var candidates: Array = candidate_map.values()
	var wall_budget: int = 20 if level == 3 else (32 if level < 6 else 48)
	var inspected: int = 0
	var best_wall: Dictionary = {}
	var best_wall_score: float = -INF
	for wall_info in candidates:
		if inspected >= wall_budget:
			break
		inspected += 1
		var hx: int = int(wall_info.x)
		var hy: int = int(wall_info.y)
		var vertical: bool = bool(wall_info.vertical)
		var key: String = str(wall_info.key)
		if not game._quo_wall_geometry_clear(hx, hy, vertical):
			continue
		game.quo_walls[key] = true
		var paths_ok: bool = true
		for candidate_player in range(4):
			if not game._quo_path_exists(candidate_player):
				paths_ok = false
				break
		if not paths_ok:
			game.quo_walls.erase(key)
			continue
		var new_own_distance: int = _distance(game, player, game.quo_pawns[player])
		var wall_score: float = -maxf(0.0, float(new_own_distance - own_distance)) * 112.0
		for opponent_info in opponents:
			var other_player: int = int(opponent_info.player)
			var old_distance: int = int(opponent_info.distance)
			var new_distance: int = _distance(game, other_player, game.quo_pawns[other_player])
			var delta: int = new_distance - old_distance
			var weight: float = 74.0 if other_player == int(opponents[0].player) else (38.0 if other_player == int(opponents[1].player) else 20.0)
			wall_score += float(delta) * weight
		game.quo_walls.erase(key)
		wall_score -= 25.0 + float(5 - int(game.quo_walls_left[player])) * 8.0
		wall_score += randf_range(-2.0, 2.0) if level < 6 else 0.0
		if wall_score > best_wall_score:
			best_wall_score = wall_score
			best_wall = {"type": "wall", "x": hx, "y": hy, "vertical": vertical, "score": wall_score}
	# A wall must provide a meaningful delay to a rival to justify losing a turn.
	var wall_threshold: float = [INF, INF, 125.0, 78.0, 42.0, 25.0, 15.0][level]
	if not best_wall.is_empty() and best_wall_score > maxf(best_score * 0.75, wall_threshold):
		return best_wall
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
	var actions: Array[Dictionary] = _search_actions(game, 1, _root_wall_branch)
	if actions.is_empty():
		var forced_wall: Dictionary = _first_legal_wall(game, 1)
		return forced_wall if not forced_wall.is_empty() else {"type": "pass"}
	# _search_actions always adds legal pawn moves before wall analysis. If its
	# bounded wall scan already used the deadline, return the top ordered move now.
	if _search_aborted:
		return actions[0]
	var best_action: Dictionary = actions[0]
	var best_score: float = -INF
	var root_distance: int = _distance(game, 1, game.quo_pawns[1])
	for action in actions:
		if _should_abort_search():
			break
		var snapshot: Dictionary = _save_search_state(game)
		_apply_search_action(game, 1, action)
		# Use a full window for every root action: the history penalty is applied
		# after minimax, so sharing an alpha adjusted for another root action could
		# prune a move whose anti-repetition bonus makes it the better choice.
		var score: float = _minimax(game, 0, _active_search_depth - 1, -INF, INF)
		_restore_search_state(game, snapshot)
		# Penalize repeated pawn positions and keep the best completed candidate so
		# far. If a deadline is reached, return that candidate instead of freezing UI.
		score += _master_root_preference(game, action, root_distance)
		if score > best_score:
			best_score = score
			best_action = action
		if _search_aborted:
			break
	return best_action

func _master_root_preference(game, action: Dictionary, root_distance: int) -> float:
	if str(action.get("type", "move")) != "move":
		return float(action.get("order_score", 0.0)) * 0.01
	var target: Vector2i = action.get("to", game.quo_pawns[1])
	var target_distance: int = _distance(game, 1, target)
	var progress: int = root_distance - target_distance
	var preference: float = float(progress) * 12.0
	preference -= _move_repetition_penalty(game, target)
	return preference

func _move_repetition_penalty(game, target: Vector2i) -> float:
	var history: Array[Vector2i] = game.quo_cpu_position_history
	if history.is_empty():
		return 0.0
	var penalty: float = 0.0
	# A -> B -> A is the exact oscillation seen in the report. Do not forbid
	# it absolutely (a newly placed wall can make it tactically necessary),
	# but make another legal route preferable whenever scores are close.
	if history.size() >= 2 and target == history[history.size() - 2]:
		penalty += IMMEDIATE_REVERSAL_PENALTY
	var first_recent: int = maxi(0, history.size() - HISTORY_LOOKBACK)
	for index in range(first_recent, history.size() - 1):
		if history[index] == target:
			var age: int = (history.size() - 2) - index
			penalty += RECENT_REVISIT_PENALTY + maxf(0.0, 4.0 - float(age)) * 6.0
	return penalty

func _should_abort_search() -> bool:
	if _search_aborted:
		return true
	if _search_deadline_usec > 0 and Time.get_ticks_usec() >= _search_deadline_usec:
		_search_aborted = true
		return true
	if _nodes_remaining <= 0:
		_search_aborted = true
		return true
	return false

func _minimax(game, player: int, depth: int, alpha: float, beta: float) -> float:
	# Player 1 is the computer and maximizes the evaluation; player 0 minimizes it.
	if _should_abort_search():
		return _evaluate_master_position(game)
	_nodes_remaining -= 1
	if game.quo_pawns[1].y == 0:
		return WIN_SCORE + float(depth)
	if game.quo_pawns[0].y == 8:
		return -WIN_SCORE - float(depth)
	if depth <= 0:
		return _evaluate_master_position(game)

	var actions: Array[Dictionary] = _search_actions(game, player, _active_wall_branch)
	if actions.is_empty():
		return _evaluate_master_position(game)
	if player == 1:
		var max_value: float = -INF
		for action in actions:
			if _should_abort_search():
				break
			var snapshot: Dictionary = _save_search_state(game)
			_apply_search_action(game, player, action)
			var child: float = _minimax(game, 0, depth - 1, alpha, beta)
			_restore_search_state(game, snapshot)
			max_value = maxf(max_value, child)
			alpha = maxf(alpha, max_value)
			if alpha >= beta or _search_aborted:
				break
		return max_value if max_value > -INF else _evaluate_master_position(game)
	else:
		var min_value: float = INF
		for action in actions:
			if _should_abort_search():
				break
			var snapshot: Dictionary = _save_search_state(game)
			_apply_search_action(game, player, action)
			var child: float = _minimax(game, 1, depth - 1, alpha, beta)
			_restore_search_state(game, snapshot)
			min_value = minf(min_value, child)
			beta = minf(beta, min_value)
			if alpha >= beta or _search_aborted:
				break
		return min_value if min_value < INF else _evaluate_master_position(game)

func _search_actions(game, player: int, wall_limit: int) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var pawn: Vector2i = game.quo_pawns[player]
	var other_pawn: Vector2i = game.quo_pawns[1 - player]
	var own_distance: int = _distance(game, player, pawn)
	var enemy_distance: int = _distance(game, 1 - player, other_pawn)

	# Always include legal pawn moves first so there is a usable fallback even if
	# the search deadline is reached while considering defensive walls.
	for target in game._quo_legal_moves_from(player, pawn):
		var target_distance: int = _distance(game, player, target)
		var move_order: float = float(own_distance - target_distance) * 100.0
		if (player == 1 and target.y == 0) or (player == 0 and target.y == 8):
			move_order = WIN_SCORE
		else:
			move_order += -absf(float(target.x) - 4.0) * 0.2
		actions.append({"type": "move", "to": target, "order_score": move_order})

	if int(game.quo_walls_left[player]) > 0 and not _should_abort_search():
		var wall_actions: Array[Dictionary] = []
		# Only inspect walls that could cut edges on the opponent's current shortest
		# route. The old 128-position full scan at every minimax node caused seconds
		# of synchronous work in HTML5 exports.
		var candidates: Array[Dictionary] = _route_wall_candidates(game, 1 - player, _active_wall_route_segments)
		for wall_info in candidates:
			if _should_abort_search() or _wall_evaluations_remaining <= 0:
				break
			var candidate: Dictionary = _search_wall_candidate(
				game, player, str(wall_info.key), int(wall_info.x), int(wall_info.y),
				bool(wall_info.vertical), own_distance, enemy_distance
			)
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

func _route_wall_candidates(game, target_player: int, max_segments: int) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var seen: Dictionary = {}
	var route: Array[Vector2i] = _shortest_route_cells(game, target_player)
	if route.size() < 2:
		return candidates
	var edge_count: int = mini(max_segments, route.size() - 1)
	for index in range(edge_count):
		var from: Vector2i = route[index]
		var to: Vector2i = route[index + 1]
		if from.x != to.x:
			# A vertical wall can block this horizontal edge from either adjacent row.
			var anchor_x: int = mini(from.x, to.x)
			for anchor_y in [from.y, from.y - 1]:
				if anchor_x < 0 or anchor_x > 7 or anchor_y < 0 or anchor_y > 7:
					continue
				var v_key: String = "v%d,%d" % [anchor_x, anchor_y]
				if not seen.has(v_key):
					seen[v_key] = true
					candidates.append({"key": v_key, "x": anchor_x, "y": anchor_y, "vertical": true})
		else:
			# A horizontal wall can block this vertical edge from either adjacent column.
			var anchor_y: int = mini(from.y, to.y)
			for anchor_x in [from.x, from.x - 1]:
				if anchor_x < 0 or anchor_x > 7 or anchor_y < 0 or anchor_y > 7:
					continue
				var h_key: String = "h%d,%d" % [anchor_x, anchor_y]
				if not seen.has(h_key):
					seen[h_key] = true
					candidates.append({"key": h_key, "x": anchor_x, "y": anchor_y, "vertical": false})
	return candidates

func _shortest_route_cells(game, player: int) -> Array[Vector2i]:
	# Cheap adjacent-cell BFS used only to derive relevant wall anchors. It mirrors
	# the route legality rule (a pawn always has at least one open path to its goal).
	var start: Vector2i = game.quo_pawns[player]
	var previous: Dictionary = {start: start}
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	var goal: Vector2i = Vector2i(-1, -1)
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		if game._quo_goal_reached(player, current):
			goal = current
			break
		for direction in DIRS:
			var next: Vector2i = current + direction
			if game._quo_can_move(current, next) and not previous.has(next):
				previous[next] = current
				queue.append(next)
	if goal.x < 0:
		return []
	var path: Array[Vector2i] = [goal]
	var cursor: Vector2i = goal
	while cursor != start:
		cursor = previous[cursor]
		path.push_front(cursor)
	return path

func _search_wall_candidate(game, player: int, key: String, x: int, y: int, vertical: bool, own_distance: int, enemy_distance: int) -> Dictionary:
	if _should_abort_search() or _wall_evaluations_remaining <= 0:
		return {}
	if not game._quo_wall_geometry_clear(x, y, vertical):
		return {}
	_wall_evaluations_remaining -= 1
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
	# Route distance dominates. The weights become more tactical when either pawn
	# is close to the finish, and retaining walls is valuable only while they can matter.
	var urgency: float = clampf((4.0 - float(human_distance)) / 4.0, 0.0, 1.0)
	var score: float = float(human_distance - cpu_distance) * (88.0 + urgency * 24.0)
	var cpu_walls: int = int(game.quo_walls_left[1])
	var human_walls: int = int(game.quo_walls_left[0])
	var wall_value: float = 3.0 + urgency * 3.5
	score += float(cpu_walls - human_walls) * wall_value
	if cpu_distance <= 2:
		score += float(3 - cpu_distance) * 42.0
	if human_distance <= 2:
		score -= float(3 - human_distance) * 48.0
	if cpu_distance == 1:
		score += 850.0
	elif cpu_distance == 2:
		score += 180.0
	if human_distance == 1:
		score -= 1100.0
	elif human_distance == 2:
		score -= 240.0
	# Prefer useful mobility but keep it a secondary tie-breaker behind route distance.
	var cpu_options: int = _legal_move_count(game, 1)
	var human_options: int = _legal_move_count(game, 0)
	score += float(cpu_options - human_options) * 0.7
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

func _best_move(game, moves: Array[Dictionary], current_distance: int, level: int) -> Dictionary:
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
		# At medium and higher difficulty, evaluate the immediate reply after every
		# candidate. This rejects pawn advances that accidentally hand the opponent
		# a direct finish or a very short route.
		if level >= 3:
			var previous_cpu_pos: Vector2i = game.quo_pawns[1]
			game.quo_pawns[1] = target
			var enemy_distance_after: int = _distance(game, 0, game.quo_pawns[0])
			var enemy_wins_next: bool = false
			for reply in game._quo_legal_moves(0):
				if game._quo_goal_reached(0, reply):
					enemy_wins_next = true
					break
			game.quo_pawns[1] = previous_cpu_pos
			if enemy_wins_next:
				quality -= 950.0 if level == 3 else 1450.0
			if enemy_distance_after <= 2:
				quality -= float(3 - enemy_distance_after) * (42.0 if level == 3 else 58.0)
		# Stronger profiles remember recent CPU squares; this stabilizes play
		# even below grandmaster without making beginner play deterministic.
		quality -= _move_repetition_penalty(game, target) * (float(level - 1) / 5.0)
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

	# Evaluate only wall anchors on the opponent's route instead of testing all 128
	# placements. This keeps even levels 2-4 responsive in web exports.
	var route_candidates: Array[Dictionary] = _route_wall_candidates(game, 0, 12)
	for info in route_candidates:
		var candidate: Dictionary = _evaluate_wall(game, str(info.key), int(info.x), int(info.y), bool(info.vertical), current_cpu_distance, current_human_distance)
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
