extends SceneTree
## Cross-checks the fast Quoridor search engine against the authoritative rules module on
## thousands of random positions, then runs tactical and strength sanity checks.

const RulesScript = preload("res://games/quoridor/rules.gd")
const EngineScript = preload("res://games/quoridor/engine.gd")

class MockApp extends Node2D:
	var vs_cpu: bool = true
	var local_seat: int = 0
	var result_calls: int = 0
	func _net_on() -> bool:
		return false
	func _go_result(_won: bool = false) -> void:
		result_calls += 1
	func _show_toast(_message: String) -> void:
		pass

var _checks: int = 0
var _failures: int = 0
var _host: MockApp
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + label)

func _new_game():
	var game = RulesScript.new()
	game.bind(_host, "quoridor")
	game.quo_player_count = 2
	game.reset_game()
	return game

# Reference distance: plain BFS over the authoritative edge rule, pawns ignored.
func _ref_distance(game, player: int) -> int:
	var start: Vector2i = game.quo_pawns[player]
	var seen: Dictionary = {start: 0}
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		if game._quo_goal_reached(player, cur):
			return int(seen[cur])
		for d in game.QUO_DIRS:
			var nxt: Vector2i = cur + d
			if game._quo_can_move(cur, nxt) and not seen.has(nxt):
				seen[nxt] = int(seen[cur]) + 1
				queue.append(nxt)
	return 99

func _cell(v: Vector2i) -> int:
	return v.y * 9 + v.x

func _random_step(game) -> bool:
	var seat: int = game.quo_turn
	var roll: float = _rng.randf()
	if roll < 0.35 and int(game.quo_walls_left[seat]) > 0:
		for _try in range(12):
			var x: int = _rng.randi_range(0, 7)
			var y: int = _rng.randi_range(0, 7)
			var vertical: bool = _rng.randf() < 0.5
			if game._quo_wall_placement_legal(x, y, vertical):
				game._quo_place_wall(x, y, vertical)
				game.quo_walls_left[seat] -= 1
				game._quo_advance_turn(seat)
				return true
	var moves: Array[Vector2i] = game._quo_legal_moves(seat)
	if moves.is_empty():
		return false
	var pick: Vector2i = moves[_rng.randi_range(0, moves.size() - 1)]
	if _rng.randf() < 0.55:
		# Bias towards progress so games reach the end-game tactics too.
		var best_dist: int = 999
		for m in moves:
			var saved: Vector2i = game.quo_pawns[seat]
			game.quo_pawns[seat] = m
			var dd: int = _ref_distance(game, seat)
			game.quo_pawns[seat] = saved
			if dd < best_dist:
				best_dist = dd
				pick = m
	game._quo_apply_move(seat, pick)
	return true

func _compare_position(game, engine, label: String) -> void:
	var seat: int = game.quo_turn
	engine.load_position(game, seat)
	var f0: PackedInt32Array = engine._pf0[0]
	var f1: PackedInt32Array = engine._pf1[0]
	var c0: PackedInt32Array = engine._pc0[0]
	var c1: PackedInt32Array = engine._pc1[0]
	engine._bfs(0, f0, c0)
	engine._bfs(1, f1, c1)
	_expect(f0[engine.pawn[0]] == _ref_distance(game, 0), "%s: player 0 distance matches reference" % label)
	_expect(f1[engine.pawn[1]] == _ref_distance(game, 1), "%s: player 1 distance matches reference" % label)

	# Pawn moves.
	var fm: PackedInt32Array = f0 if seat == 0 else f1
	var codes: PackedInt32Array = engine._mv_code[0]
	var ords: PackedInt32Array = engine._mv_ord[0]
	var n: int = engine._gen_pawn(seat, engine.pawn[seat], fm, codes, ords)
	var real: Array[Vector2i] = game._quo_legal_moves(seat)
	if n < 0:
		var win_cell: Vector2i = Vector2i(engine._win_cell % 9, engine._win_cell / 9)
		_expect(win_cell in real and game._quo_goal_reached(seat, win_cell), "%s: engine win move is a real winning move" % label)
		var any_real_win: bool = false
		for m in real:
			if game._quo_goal_reached(seat, m):
				any_real_win = true
		_expect(any_real_win, "%s: a real winning move exists when the engine reports one" % label)
	else:
		var mine: Array = []
		for i in range(n):
			mine.append(Vector2i(codes[i] % 9, codes[i] / 9))
		var same: bool = mine.size() == real.size()
		for m in real:
			if m not in mine:
				same = false
		_expect(same, "%s: pawn moves match rules (%s vs %s)" % [label, str(mine), str(real)])

	# Wall legality for all 128 anchors.
	var wall_mismatch: int = 0
	for vert_i in range(2):
		for a in range(64):
			var vert: bool = vert_i == 1
			var engine_legal: bool = engine._wall_geometry_ok(vert, a)
			if engine_legal:
				engine._set_wall(vert, a, true)
				engine._bfs(0, engine._tf, engine._tc)
				var ok0: bool = engine._tf[engine.pawn[0]] < 99
				engine._bfs(1, engine._tf, engine._tc)
				var ok1: bool = engine._tf[engine.pawn[1]] < 99
				engine._set_wall(vert, a, false)
				engine_legal = ok0 and ok1
			var real_legal: bool = game._quo_wall_placement_legal(a & 7, a >> 3, vert)
			if engine_legal != real_legal:
				wall_mismatch += 1
	_expect(wall_mismatch == 0, "%s: wall legality matches rules for all anchors (mismatches=%d)" % [label, wall_mismatch])

	# Cut test: a wall lengthens the opponent's route iff the engine lists it as a candidate.
	var op: int = 1 - seat
	var fo: PackedInt32Array = f1 if seat == 0 else f0
	var co: PackedInt32Array = c1 if seat == 0 else c0
	var cm: PackedInt32Array = c0 if seat == 0 else c1
	var cand_codes: PackedInt32Array = engine._mv_code[1]
	var cand_ords: PackedInt32Array = engine._mv_ord[1]
	var cn: int = engine._gen_walls(seat, fo, co, fm, cm, cand_codes, cand_ords, 0, false, 500)
	var listed: Dictionary = {}
	for i in range(cn):
		listed[int(cand_codes[i])] = true
	var false_negative: int = 0
	var false_positive: int = 0
	var base_op: int = _ref_distance(game, op)
	for vert_i in range(2):
		for a in range(64):
			var vert: bool = vert_i == 1
			if not game._quo_wall_placement_legal(a & 7, a >> 3, vert):
				continue
			var key: String = ("v%d,%d" if vert else "h%d,%d") % [a & 7, a >> 3]
			game.quo_walls[key] = true
			var new_op: int = _ref_distance(game, op)
			game.quo_walls.erase(key)
			var code: int = (engine.VWALL_BASE if vert else engine.WALL_BASE) + a
			var lengthens: bool = new_op > base_op
			if lengthens and not listed.has(code):
				false_negative += 1
			if not lengthens and listed.has(code):
				false_positive += 1
	_expect(false_negative == 0, "%s: no wall that lengthens the opponent route is missed (missed=%d)" % [label, false_negative])
	_expect(false_positive == 0, "%s: no listed wall fails to lengthen the route (extra=%d)" % [label, false_positive])

func _run() -> void:
	_host = MockApp.new()
	root.add_child(_host)
	_rng.seed = 424242
	var engine = EngineScript.new()
	var positions: int = 0
	for g in range(10):
		var game = _new_game()
		var plies: int = 0
		while not game.quo_game_over and plies < 80:
			if plies % 3 == 0:
				_compare_position(game, engine, "game %d ply %d" % [g, plies])
				positions += 1
			if not _random_step(game):
				break
			plies += 1
	print("compared %d random positions against rules.gd" % positions)
	_test_tactics(engine)
	_test_hash_and_make_unmake(engine)
	print("QUORIDOR_ENGINE_TESTS: checks=%d, failures=%d" % [_checks, _failures])
	_host.free()
	quit(1 if _failures > 0 else 0)

func _test_tactics(engine) -> void:
	# 1) Immediate win is always taken.
	var game = _new_game()
	game.quo_pawns = [Vector2i(0, 0), Vector2i(4, 1)]
	game.quo_turn = 1
	var act: Dictionary = engine.think(game, 1, {"depth": 3, "budget_usec": 200000, "nodes": 2000})
	_expect(str(act.get("type", "")) == "move" and act.to == Vector2i(4, 0), "engine takes the immediate win")

	# 2) Opponent one step from the goal: the engine must block with a wall (it cannot win itself).
	game = _new_game()
	game.quo_pawns = [Vector2i(4, 7), Vector2i(4, 5)]
	game.quo_turn = 1
	act = engine.think(game, 1, {"depth": 4, "budget_usec": 300000, "nodes": 5000})
	_expect(str(act.get("type", "")) == "wall", "engine blocks a one-step opponent threat with a wall")
	if str(act.get("type", "")) == "wall":
		game.quo_walls_left[1] -= 1
		_expect(game._quo_wall_placement_legal(int(act.x), int(act.y), bool(act.vertical)), "the blocking wall is legal under the real rules")
		game._quo_place_wall(int(act.x), int(act.y), bool(act.vertical))
		var left: bool = false
		for m in game._quo_legal_moves(0):
			if game._quo_goal_reached(0, m):
				left = true
		_expect(not left, "after the engine's wall the opponent can no longer win immediately")

	# 3) With no walls left for anyone it simply races along a shortest path.
	game = _new_game()
	game.quo_walls_left = [0, 0]
	game.quo_pawns = [Vector2i(4, 3), Vector2i(2, 6)]
	game.quo_turn = 1
	act = engine.think(game, 1, {"depth": 4, "budget_usec": 200000, "nodes": 3000})
	_expect(str(act.get("type", "")) == "move" and act.to == Vector2i(2, 5), "engine races straight when walls are gone")

	# 4) Returned actions are always legal in real play across a seeded self-play game.
	game = _new_game()
	var legal_all: bool = true
	var plies: int = 0
	while not game.quo_game_over and plies < 160:
		var seat: int = game.quo_turn
		var a: Dictionary = engine.think(game, seat, {"depth": 3, "budget_usec": 80000, "nodes": 1200})
		if str(a.get("type", "")) == "wall":
			if int(game.quo_walls_left[seat]) <= 0 or not game._quo_wall_placement_legal(int(a.x), int(a.y), bool(a.vertical)):
				legal_all = false
				break
			game._quo_place_wall(int(a.x), int(a.y), bool(a.vertical))
			game.quo_walls_left[seat] -= 1
			game._quo_advance_turn(seat)
		elif str(a.get("type", "")) == "move":
			if a.to not in game._quo_legal_moves(seat):
				legal_all = false
				break
			game._quo_apply_move(seat, a.to)
		else:
			break
		plies += 1
	_expect(legal_all, "every engine action in a full self-play game is legal under rules.gd")
	_expect(game.quo_game_over, "an engine self-play game finishes with a winner (plies=%d)" % plies)

func _test_hash_and_make_unmake(engine) -> void:
	var game = _new_game()
	engine.load_position(game, 0)
	var before: int = engine.hash
	var f0: PackedInt32Array = engine._pf0[0]
	var f1: PackedInt32Array = engine._pf1[0]
	engine._bfs(0, f0, engine._pc0[0])
	engine._bfs(1, f1, engine._pc1[0])
	var ok: bool = true
	for code in [engine.pawn[0] + 9, engine.WALL_BASE + 27, engine.VWALL_BASE + 36]:
		var h0: int = engine.hash
		var made: bool = engine._make(code, 0)
		ok = ok and made
		engine._unmake(code, 0)
		ok = ok and engine.hash == h0 and engine.stm == 0
	_expect(ok and engine.hash == before, "make/unmake restores hash, side to move and board")
	# Hash recomputed from scratch must equal the incrementally updated one.
	engine.load_position(game, 0)
	engine._make(engine.WALL_BASE + 27, 0)
	var incremental: int = engine.hash
	var game2 = _new_game()
	game2.quo_walls["h3,3"] = true
	game2.quo_walls_left = [9, 10]
	engine.load_position(game2, 1)
	_expect(incremental == engine.hash, "incremental Zobrist hash equals a fresh recomputation")
