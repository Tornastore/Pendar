extends RefCounted
## Quoridor CPU policy.
##
## Levels 1 and 2 keep the original gentle heuristics so beginners still get an even game.
## Levels 3-6 are driven by engine.gd (two players) and engine4.gd (four players): bounded
## iterative-deepening search over an exact shortest-path model of the board. The level only
## changes how deep and how long the search may run, how many wall ideas it weighs and how
## much judgement noise it adds, so each step up the ladder is a real step up in strength.

const EngineScript = preload("res://games/quoridor/engine.gd")
const FourPlayerScript = preload("res://games/quoridor/engine4.gd")

const DIRS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)
]
const IMMEDIATE_REVERSAL_PENALTY: float = 175.0
const RECENT_REVISIT_PENALTY: float = 42.0
const HISTORY_LOOKBACK: int = 9

# A browser game's main thread must never be occupied by an unbounded search. Every profile has
# a node cap and a wall-clock cap; whichever is reached first ends the search and the best move
# of the last finished (or provably better partial) iteration is played.
# Two players: depth = deepest iteration, ms = time cap, nodes = node cap, noise = judgement
# noise in points (100 = one pawn step), root_n = root moves weighed when noisy, k = wall
# candidates per remaining depth, exact = remaining depth from which walls are ranked by real
# distance gain.
const PROFILES: Dictionary = {
	3: {"depth": 2, "ms": 70, "nodes": 500, "noise": 55, "root_n": 7, "exact": 99, "k": [0, 2, 3]},
	4: {"depth": 4, "ms": 150, "nodes": 1500, "noise": 18, "root_n": 7, "exact": 3, "k": [0, 3, 4, 5, 5]},
	5: {"depth": 9, "ms": 380, "nodes": 4200, "noise": 0, "root_n": 0, "exact": 3, "k": [0, 3, 5, 6, 7, 8, 8, 8, 8, 8]},
	6: {"depth": 14, "ms": 900, "nodes": 11000, "noise": 0, "root_n": 0, "exact": 3, "k": [0, 3, 5, 6, 7, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8]},
}
# Four players: targets = rivals considered for walls, noise in points, reply_n = best
# candidates that are re-scored after the next player's best reply.
const PROFILES_4P: Dictionary = {
	3: {"targets": 1, "noise": 45.0, "reply_n": 0},
	4: {"targets": 2, "noise": 16.0, "reply_n": 0},
	5: {"targets": 3, "noise": 4.0, "reply_n": 4},
	6: {"targets": 3, "noise": 0.0, "reply_n": 6},
}
# The web export runs the same script a few times slower than desktop.
const WEB_BUDGET_SCALE: float = 0.7

var _engine = null
var _engine4 = null
var _tt_level: int = 0
var _tt_walls: int = -1

func choose_action(game, difficulty: int) -> Dictionary:
	var level: int = clampi(difficulty, 1, 6)
	# Never miss an immediate win, regardless of the selected difficulty.
	for target in game._quo_legal_moves(1):
		if game._quo_goal_reached(1, target):
			return {"type": "move", "to": target}
	if level >= 3:
		var searched: Dictionary = _search_action(game, level)
		if not searched.is_empty():
			return searched
		# The search should always produce a legal action. If it ever does not, fall back to
		# the beginner heuristic below instead of freezing the game.
		level = 2
	# If the human can finish on their next move, spend a wall to block that route whenever a
	# legal defensive wall exists. This prevents avoidable instant losses.
	var urgent_block: Dictionary = _block_immediate_opponent_win(game)
	if not urgent_block.is_empty():
		return urgent_block
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

	var wall: Dictionary = _best_wall(game, cpu_distance, human_distance)
	if wall.is_empty():
		return best_move

	# Beginner AI uses a wall only as an emergency defense and avoids slowing itself.
	if human_distance <= 3 and int(wall.get("enemy_delta", 0)) >= 1 and int(wall.get("self_delta", 0)) <= 0:
		return wall
	return best_move

## Levels 3-6 for two players: iterative-deepening alpha-beta from engine.gd.
func _search_action(game, level: int) -> Dictionary:
	if _engine == null:
		_engine = EngineScript.new()
	var profile: Dictionary = PROFILES[level]
	var budget: int = int(profile.ms) * 1000
	if OS.has_feature("web"):
		budget = int(float(budget) * WEB_BUDGET_SCALE)
	var history: Array = game.quo_cpu_position_history
	# Positions searched on the previous move are still valid on this one (same game, same
	# profile, walls only ever accumulate), so the transposition table is kept between moves.
	var wall_total: int = game.quo_walls.size()
	var keep_tt: bool = level == _tt_level and _tt_walls >= 0 and wall_total >= _tt_walls
	_tt_level = level
	_tt_walls = wall_total
	var params: Dictionary = {
		"keep_tt": keep_tt,
		"depth": int(profile.depth),
		"budget_usec": budget,
		"nodes": int(profile.nodes),
		"noise": int(profile.noise),
		"root_n": int(profile.root_n),
		"exact_depth": int(profile.exact),
		"k": profile.k,
		# Recently visited cells (oldest first, current cell excluded) are discouraged so the
		# CPU never shuffles A-B-A-B when two continuations score the same.
		"avoid": history.slice(maxi(0, history.size() - 6), maxi(0, history.size() - 1)),
	}
	return _validated(game, 1, _engine.think(game, 1, params))

## Levels 3-6 for four players: arrival-time scoring from engine4.gd.
func _search_action_4p(game, level: int, player: int) -> Dictionary:
	if _engine4 == null:
		_engine4 = FourPlayerScript.new()
	var profile: Dictionary = PROFILES_4P[level]
	var history: Array = game.quo_cpu_position_history_by_player.get(str(player), [])
	var params: Dictionary = {
		"targets": int(profile.targets),
		"noise": float(profile.noise),
		"reply_n": int(profile.reply_n),
		"avoid": history.slice(maxi(0, history.size() - 6), maxi(0, history.size() - 1)),
	}
	return _validated(game, player, _engine4.think(game, player, params))

## The search works on its own copy of the board, so double-check its answer against the
## authoritative rules before it reaches the game. An empty result means "use the fallback".
func _validated(game, player: int, action: Dictionary) -> Dictionary:
	match str(action.get("type", "")):
		"move":
			var to: Vector2i = action.get("to", game.quo_pawns[player])
			if to in game._quo_legal_moves(player):
				return action
		"wall":
			if int(game.quo_walls_left[player]) > 0 and game._quo_wall_placement_legal(int(action.get("x", -1)), int(action.get("y", -1)), bool(action.get("vertical", false))):
				return action
		"pass":
			if game._quo_legal_moves(player).is_empty() and (int(game.quo_walls_left[player]) <= 0 or not game._quo_has_legal_wall()):
				return action
	return {}

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
	# Multiplayer CPU policy for the four-seat variant. It uses one shared rules engine but
	# evaluates every opponent against their own edge goal, instead of treating seat 0 as the
	# only human and seat 1 as the only CPU.
	var level: int = clampi(difficulty, 1, 6)
	if int(game.quo_player_count) != 4 or player < 0 or player > 3:
		return choose_action(game, level)
	for target in game._quo_legal_moves(player):
		if game._quo_goal_reached(player, target):
			return {"type": "move", "to": target}
	if level >= 3:
		var searched: Dictionary = _search_action_4p(game, level, player)
		if not searched.is_empty():
			return searched
	var own_pos: Vector2i = game.quo_pawns[player]
	var own_distance: int = _distance(game, player, own_pos)
	var moves: Array[Dictionary] = []
	for target in game._quo_legal_moves(player):
		var target_distance: int = _distance(game, player, target)
		var score: float = float(own_distance - target_distance) * 105.0
		# Prefer the centre when progress is equivalent, but do not overvalue it.
		score -= absf(float(target.x) - 4.0) * 0.45 + absf(float(target.y) - 4.0) * 0.20
		var history: Array = game.quo_cpu_position_history_by_player.get(str(player), [])
		if history.size() >= 2 and target == history[history.size() - 2]:
			score -= 150.0
		elif target in history.slice(maxi(0, history.size() - 5), history.size()):
			score -= 32.0
		var noise: Array[float] = [0.0, 24.0, 14.0]
		score += randf_range(-noise[mini(level, 2)], noise[mini(level, 2)])
		moves.append({"type": "move", "to": target, "score": score})
	moves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.score) > float(b.score))
	if not moves.is_empty():
		return moves[0]
	var forced_wall: Dictionary = _first_legal_wall(game, player)
	return forced_wall if not forced_wall.is_empty() else {"type": "pass"}

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

func _move_repetition_penalty(game, target: Vector2i) -> float:
	var history: Array[Vector2i] = game.quo_cpu_position_history
	if history.is_empty():
		return 0.0
	var penalty: float = 0.0
	# A -> B -> A is the exact oscillation seen in the report. Do not forbid it absolutely (a
	# newly placed wall can make it tactically necessary), but make another legal route
	# preferable whenever scores are close.
	if history.size() >= 2 and target == history[history.size() - 2]:
		penalty += IMMEDIATE_REVERSAL_PENALTY
	var first_recent: int = maxi(0, history.size() - HISTORY_LOOKBACK)
	for index in range(first_recent, history.size() - 1):
		if history[index] == target:
			var age: int = (history.size() - 2) - index
			penalty += RECENT_REVISIT_PENALTY + maxf(0.0, 4.0 - float(age)) * 6.0
	return penalty

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
	# Cheap adjacent-cell BFS used only to derive relevant wall anchors. It mirrors the route
	# legality rule (a pawn always has at least one open path to its goal).
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
		# Break equal-distance choices toward the board centre.
		var target: Vector2i = move.to
		var centrality: float = -absf(float(target.x) - 4.0)
		var quality: float = float(progress) * 100.0 + (centrality * float(level) * 0.25)
		# Remember recent CPU squares; this stabilizes play without making it deterministic.
		quality -= _move_repetition_penalty(game, target) * (float(level - 1) / 5.0)
		if quality > best_quality + 0.01:
			best_quality = quality
			best.clear()
			best.append(move)
		elif absf(quality - best_quality) < 0.01:
			best.append(move)
	if best.is_empty():
		return moves[0]
	best.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ax: Vector2i = a.to
		var bx: Vector2i = b.to
		if ax.x != bx.x:
			return abs(ax.x - 4) < abs(bx.x - 4)
		return ax.y < bx.y
	)
	return best[0]

## Level 2 wall choice: only walls on the human's route are examined, which keeps the beginner
## levels instant even in web exports.
func _best_wall(game, current_cpu_distance: int, current_human_distance: int) -> Dictionary:
	var best: Dictionary = {}
	var best_score: float = -INF
	var cpu_walls_spent: int = 10 - int(game.quo_walls_left[1])
	var urgency: float = clampf((5.0 - float(current_human_distance)) / 5.0, 0.0, 1.0)
	# Once the CPU has a clear route advantage, advancing is usually better than spending more
	# walls merely to widen an already comfortable lead.
	var lead_penalty: float = maxf(0.0, float(current_human_distance - current_cpu_distance)) * 65.0
	var enemy_weight: float = 112.0
	var self_penalty: float = 100.0
	var turn_cost: float = 25.0
	var wall_cost: float = 4.0 + float(cpu_walls_spent) * 4.0
	for info in _route_wall_candidates(game, 0, 12):
		var candidate: Dictionary = _evaluate_wall(game, str(info.key), int(info.x), int(info.y), bool(info.vertical), current_cpu_distance, current_human_distance)
		if not candidate.is_empty():
			var score: float = _wall_score(candidate, enemy_weight, self_penalty, turn_cost, wall_cost, lead_penalty)
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

func _wall_score(candidate: Dictionary, enemy_weight: float, self_penalty: float, turn_cost: float, wall_cost: float, lead_penalty: float) -> float:
	var score: float = float(candidate.enemy_delta) * enemy_weight
	score -= maxf(0.0, float(candidate.self_delta)) * self_penalty
	score -= turn_cost + wall_cost + lead_penalty
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
