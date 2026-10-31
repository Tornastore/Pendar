extends SceneTree
## Production-path checks for the Quoridor CPU: every difficulty level returns only legal
## actions within its time budget, the four-player engine agrees with rules.gd, and complete
## games (two and four players) finish with a winner.

const RulesScript = preload("res://games/quoridor/rules.gd")
const Engine4Script = preload("res://games/quoridor/engine4.gd")

class MockApp extends Node2D:
	var vs_cpu: bool = true
	var local_seat: int = 0
	func _net_on() -> bool:
		return false
	func _go_result(_won: bool = false) -> void:
		pass
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

func _new_game(players: int):
	var game = RulesScript.new()
	game.bind(_host, "quoridor")
	game.quo_player_count = players
	game.reset_game()
	return game

func _apply(game, seat: int, action: Dictionary) -> bool:
	var kind: String = str(action.get("type", ""))
	if kind == "wall":
		if int(game.quo_walls_left[seat]) <= 0 or not game._quo_wall_placement_legal(int(action.x), int(action.y), bool(action.vertical)):
			return false
		game._quo_place_wall(int(action.x), int(action.y), bool(action.vertical))
		game.quo_walls_left[seat] -= 1
		game._quo_advance_turn(seat)
		return true
	if kind == "move":
		if action.to not in game._quo_legal_moves(seat):
			return false
		game._quo_apply_move(seat, action.to)
		return true
	if kind == "pass":
		game._quo_advance_turn(seat)
		return true
	return false

func _scatter_walls(game, count: int) -> void:
	var placed: int = 0
	var tries: int = 0
	while placed < count and tries < 400:
		tries += 1
		var x: int = _rng.randi_range(0, 7)
		var y: int = _rng.randi_range(0, 7)
		var vertical: bool = _rng.randf() < 0.5
		if game._quo_wall_placement_legal(x, y, vertical):
			game.quo_walls[("v%d,%d" if vertical else "h%d,%d") % [x, y]] = true
			placed += 1

func _run() -> void:
	_host = MockApp.new()
	root.add_child(_host)
	_rng.seed = 20260531
	_test_every_level_is_legal_and_bounded()
	_test_levels_two_and_three_keep_beginner_behaviour()
	_test_four_player_engine_matches_rules()
	_test_full_games()
	print("QUORIDOR_AI_LEVEL_TESTS: checks=%d, failures=%d" % [_checks, _failures])
	_host.free()
	quit(1 if _failures > 0 else 0)

func _test_every_level_is_legal_and_bounded() -> void:
	var worst_ms: Dictionary = {}
	for trial in range(6):
		var game = _new_game(2)
		_scatter_walls(game, 4 + trial * 2)
		game.quo_pawns = [Vector2i(_rng.randi_range(0, 8), _rng.randi_range(1, 5)), Vector2i(_rng.randi_range(0, 8), _rng.randi_range(3, 7))]
		if game.quo_pawns[0] == game.quo_pawns[1]:
			game.quo_pawns[1] = Vector2i(4, 8)
		game.quo_walls_left = [10 - trial, 9 - trial / 2]
		game.quo_turn = 1
		for level in range(1, 7):
			var t0: int = Time.get_ticks_usec()
			var action: Dictionary = game.quo_ai.choose_action(game, level)
			var ms: int = (Time.get_ticks_usec() - t0) / 1000
			worst_ms[level] = maxi(int(worst_ms.get(level, 0)), ms)
			var legal: bool = false
			match str(action.get("type", "")):
				"move":
					legal = action.to in game._quo_legal_moves(1)
				"wall":
					legal = int(game.quo_walls_left[1]) > 0 and game._quo_wall_placement_legal(int(action.x), int(action.y), bool(action.vertical))
				"pass":
					legal = game._quo_legal_moves(1).is_empty()
			_expect(legal, "level %d returns a legal action (trial %d): %s" % [level, trial, str(action)])
	# Hard bound: the longest level is capped at 900 ms (630 ms on the web); allow slack for slow CI.
	for level in range(1, 7):
		_expect(int(worst_ms[level]) < 2500, "level %d stays within its time budget (worst %d ms)" % [level, int(worst_ms[level])])
	print("worst move time per level (ms): ", worst_ms)

func _test_levels_two_and_three_keep_beginner_behaviour() -> void:
	# The human is one step from the goal: every level must spend a wall to stop it.
	for level in range(1, 7):
		var game = _new_game(2)
		game.quo_pawns = [Vector2i(4, 7), Vector2i(1, 4)]
		game.quo_turn = 1
		var action: Dictionary = game.quo_ai.choose_action(game, level)
		_expect(str(action.get("type", "")) == "wall", "level %d blocks an immediate human win" % level)
	# And every level takes its own immediate win.
	for level in range(1, 7):
		var game = _new_game(2)
		game.quo_pawns = [Vector2i(1, 3), Vector2i(6, 1)]
		game.quo_turn = 1
		var action: Dictionary = game.quo_ai.choose_action(game, level)
		_expect(str(action.get("type", "")) == "move" and action.to == Vector2i(6, 0), "level %d takes an immediate win" % level)

func _ref_distance(game, seat: int) -> int:
	var start: Vector2i = game.quo_pawns[seat]
	var seen: Dictionary = {start: 0}
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		if game._quo_goal_reached(seat, cur):
			return int(seen[cur])
		for d in game.QUO_DIRS:
			var nxt: Vector2i = cur + d
			if game._quo_can_move(cur, nxt) and not seen.has(nxt):
				seen[nxt] = int(seen[cur]) + 1
				queue.append(nxt)
	return 99

func _test_four_player_engine_matches_rules() -> void:
	var engine = Engine4Script.new()
	var positions: int = 0
	for g in range(7):
		var game = _new_game(4)
		var plies: int = 0
		while not game.quo_game_over and plies < 90:
			if plies % 4 == 1:
				positions += 1
				engine.load_position(game)
				engine._refresh_all()
				for seat in range(4):
					_expect(engine._dist[seat] == _ref_distance(game, seat), "4p game %d ply %d: seat %d distance matches the rules" % [g, plies, seat])
				var seat_now: int = game.quo_turn
				var n: int = engine._gen_pawn(seat_now, engine._pm)
				var mine: Array = []
				for i in range(n):
					mine.append(Vector2i(engine._pm[i] % 9, engine._pm[i] / 9))
				var real: Array[Vector2i] = game._quo_legal_moves(seat_now)
				var same: bool = mine.size() == real.size()
				for m in real:
					if m not in mine:
						same = false
				_expect(same, "4p game %d ply %d: pawn moves match the rules (%s vs %s)" % [g, plies, str(mine), str(real)])
				var mismatch: int = 0
				for vert_i in range(2):
					for a in range(64):
						var vert: bool = vert_i == 1
						var legal: bool = engine._geometry_ok(vert, a)
						if legal:
							engine._set_wall(vert, a, true)
							for s in range(4):
								engine._bfs(s, engine._nf[s], engine._nc[s])
								if engine._nf[s][engine.pawn[s]] >= 99:
									legal = false
							engine._set_wall(vert, a, false)
						if legal != game._quo_wall_placement_legal(a & 7, a >> 3, vert):
							mismatch += 1
				_expect(mismatch == 0, "4p game %d ply %d: wall legality matches the rules (%d mismatches)" % [g, plies, mismatch])
			# advance the game with random legal play
			var seat: int = game.quo_turn
			var acted: bool = false
			if _rng.randf() < 0.3 and int(game.quo_walls_left[seat]) > 0:
				for _try in range(10):
					var x: int = _rng.randi_range(0, 7)
					var y: int = _rng.randi_range(0, 7)
					var vertical: bool = _rng.randf() < 0.5
					if game._quo_wall_placement_legal(x, y, vertical):
						acted = _apply(game, seat, {"type": "wall", "x": x, "y": y, "vertical": vertical})
						break
			if not acted:
				var moves: Array[Vector2i] = game._quo_legal_moves(seat)
				if moves.is_empty():
					game._quo_advance_turn(seat)
				else:
					game._quo_apply_move(seat, moves[_rng.randi_range(0, moves.size() - 1)])
			plies += 1
	print("compared %d random four-player positions against rules.gd" % positions)

func _test_full_games() -> void:
	# Two players: levels 3..6 against a simple walker finish and never act illegally.
	for level in range(3, 7):
		var game = _new_game(2)
		var plies: int = 0
		var legal_all: bool = true
		while not game.quo_game_over and plies < 220:
			var seat: int = game.quo_turn
			var action: Dictionary
			if seat == 1:
				action = game.quo_ai.choose_action(game, level)
				if str(action.get("type", "")) == "move":
					game.quo_cpu_position_history.append(action.to)
			else:
				action = {"type": "move", "to": game._quo_next_step(0)}
			if not _apply(game, seat, action):
				legal_all = false
				break
			plies += 1
		_expect(legal_all, "two-player level %d played a whole game legally" % level)
		_expect(game.quo_game_over, "two-player level %d game finished (plies=%d)" % [level, plies])
		_expect(game.quo_winner == 1, "two-player level %d beats a plain shortest-path walker" % level)
	# Four players: three CPU seats (levels 3..6) against a walker in seat 0.
	for level in range(3, 7):
		var game = _new_game(4)
		var plies: int = 0
		var legal_all: bool = true
		while not game.quo_game_over and plies < 500:
			var seat: int = game.quo_turn
			var action: Dictionary
			if seat == 0:
				action = {"type": "move", "to": game._quo_next_step(0)}
			else:
				action = game.quo_ai.choose_action_for_player(game, level, seat)
				if str(action.get("type", "")) == "move":
					var key: String = str(seat)
					if not game.quo_cpu_position_history_by_player.has(key):
						game.quo_cpu_position_history_by_player[key] = []
					game.quo_cpu_position_history_by_player[key].append(action.to)
			if not _apply(game, seat, action):
				legal_all = false
				break
			plies += 1
		_expect(legal_all, "four-player level %d played a whole game legally" % level)
		_expect(game.quo_game_over, "four-player level %d game finished (plies=%d)" % [level, plies])
