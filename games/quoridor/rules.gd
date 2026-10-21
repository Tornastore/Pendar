extends "res://core/game_module.gd"
## Quoridor rules: two-edge walls, legal jumping/diagonal pawn moves and 2/4-player modes.

const QuoridorAIScript = preload("res://games/quoridor/ai.gd")
const QUO_DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)]
var quo_ai = QuoridorAIScript.new()
var quo_difficulty: int = 3 # 1 very easy .. 5 expert .. 6 master grandmaster
var quo_player_count: int = 2
var quo_local_multiplayer: bool = false

# ---------- Game-owned state ----------
var quo_pawns: Array = [Vector2i(4, 0), Vector2i(4, 8)]
var quo_walls_left: Array = [10, 10]
var quo_turn: int = 0
var quo_mode: int = 0           # 0 move pawn, 1 place wall
var quo_game_over: bool = false
var quo_winner: int = -1
var quo_walls: Dictionary = {}  # key "h3,4" or "v2,5"; each wall covers two edges
var quo_cpu_position_history: Array[Vector2i] = [] # Two-player CPU history.
var quo_cpu_position_history_by_player: Dictionary = {} # Per-CPU history in four-player vs CPU mode.

func reset_game() -> void:
	_reset_quoridor()

func _reset_quoridor() -> void:
	quo_player_count = 4 if quo_player_count == 4 else 2
	quo_pawns = [Vector2i(4, 0), Vector2i(4, 8)]
	if quo_player_count == 4:
		quo_pawns = [Vector2i(4, 0), Vector2i(8, 4), Vector2i(4, 8), Vector2i(0, 4)]
		quo_walls_left = [5, 5, 5, 5]
	else:
		quo_walls_left = [10, 10]
	quo_turn = 0
	quo_mode = 0
	quo_game_over = false
	quo_winner = -1
	quo_walls.clear()
	quo_cpu_position_history.clear()
	quo_cpu_position_history_by_player.clear()
	if quo_player_count == 2:
		quo_cpu_position_history.append(quo_pawns[1])
	else:
		for player in range(1, 4):
			quo_cpu_position_history_by_player[str(player)] = [quo_pawns[player]]

func _quo_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x <= 8 and pos.y >= 0 and pos.y <= 8

func _quo_goal_reached(player: int, pos: Vector2i) -> bool:
	if quo_player_count == 2:
		if player == 0:
			return pos.y == 8
		return pos.y == 0
	match player:
		0: return pos.y == 8
		1: return pos.x == 0
		2: return pos.y == 0
		3: return pos.x == 8
	return false

func _quo_can_move(from: Vector2i, to: Vector2i) -> bool:
	if abs(to.x - from.x) + abs(to.y - from.y) != 1 or not _quo_in_bounds(to):
		return false
	# A vertical wall covers two horizontal edges on adjacent rows.
	if to.x != from.x:
		var boundary_x: int = mini(from.x, to.x)
		if quo_walls.has("v%d,%d" % [boundary_x, from.y]) or quo_walls.has("v%d,%d" % [boundary_x, from.y - 1]):
			return false
	else:
		# A horizontal wall covers two vertical edges in adjacent columns.
		var boundary_y: int = mini(from.y, to.y)
		if quo_walls.has("h%d,%d" % [from.x, boundary_y]) or quo_walls.has("h%d,%d" % [from.x - 1, boundary_y]):
			return false
	return true

func _quo_legal_moves(player: int) -> Array[Vector2i]:
	if player < 0 or player >= quo_pawns.size():
		var no_moves: Array[Vector2i] = []
		return no_moves
	return _quo_legal_moves_from(player, quo_pawns[player])

func _quo_legal_moves_from(player: int, from: Vector2i) -> Array[Vector2i]:
	# Standard Quoridor jumping: move over an adjacent pawn when possible; if
	# the straight jump is blocked by a wall/edge/another pawn, diagonals are allowed.
	var result: Array[Vector2i] = []
	var occupied: Dictionary = {}
	for i in range(quo_pawns.size()):
		if i != player:
			occupied[quo_pawns[i]] = true
	for direction in QUO_DIRS:
		var adjacent: Vector2i = from + direction
		if not _quo_can_move(from, adjacent):
			continue
		if not occupied.has(adjacent):
			if adjacent not in result:
				result.append(adjacent)
			continue
		var jump: Vector2i = adjacent + direction
		if _quo_in_bounds(jump) and _quo_can_move(adjacent, jump) and not occupied.has(jump):
			if jump not in result:
				result.append(jump)
			continue
		# The straight jump is impossible: try the two cells beside the adjacent pawn.
		var sides: Array[Vector2i] = []
		if direction.x == 0:
			sides = [Vector2i(-1, 0), Vector2i(1, 0)]
		else:
			sides = [Vector2i(0, -1), Vector2i(0, 1)]
		for side in sides:
			var diagonal: Vector2i = adjacent + side
			if _quo_in_bounds(diagonal) and _quo_can_move(adjacent, diagonal) and not occupied.has(diagonal) and diagonal not in result:
				result.append(diagonal)
	return result

func _quo_path_exists(player: int) -> bool:
	# Wall legality is checked against a path for every active player. Pawn
	# occupancy is intentionally ignored here: walls must never seal a goal off.
	if player < 0 or player >= quo_player_count:
		return false
	var start: Vector2i = quo_pawns[player]
	var visited: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		if _quo_goal_reached(player, current):
			return true
		for direction in QUO_DIRS:
			var next: Vector2i = current + direction
			if _quo_can_move(current, next) and not visited.has(next):
				visited[next] = true
				queue.append(next)
	return false

func _quo_wall_geometry_clear(hx: int, hy: int, vertical: bool) -> bool:
	# Legal wall anchors are the 8x8 inter-cell intersections. Neighboring
	# parallel walls at offset 1 overlap one edge; offset 2 only touch endpoints.
	if hx < 0 or hx > 7 or hy < 0 or hy > 7:
		return false
	var key: String = ("v%d,%d" % [hx, hy]) if vertical else ("h%d,%d" % [hx, hy])
	if quo_walls.has(key):
		return false
	if vertical:
		if quo_walls.has("v%d,%d" % [hx, hy - 1]) or quo_walls.has("v%d,%d" % [hx, hy + 1]):
			return false
		# Perpendicular walls at the same anchor would cross.
		if quo_walls.has("h%d,%d" % [hx, hy]):
			return false
	else:
		if quo_walls.has("h%d,%d" % [hx - 1, hy]) or quo_walls.has("h%d,%d" % [hx + 1, hy]):
			return false
		if quo_walls.has("v%d,%d" % [hx, hy]):
			return false
	return true

func _quo_wall_placement_legal(hx: int, hy: int, vertical: bool) -> bool:
	if not _quo_wall_geometry_clear(hx, hy, vertical):
		return false
	var key: String = ("v%d,%d" % [hx, hy]) if vertical else ("h%d,%d" % [hx, hy])
	quo_walls[key] = true
	var paths_ok: bool = true
	for player in range(quo_player_count):
		if not _quo_path_exists(player):
			paths_ok = false
			break
	quo_walls.erase(key)
	return paths_ok

func _quo_has_legal_wall() -> bool:
	for y in range(8):
		for x in range(8):
			if _quo_wall_placement_legal(x, y, false) or _quo_wall_placement_legal(x, y, true):
				return true
	return false

func _quo_place_wall(hx: int, hy: int, vertical: bool) -> bool:
	if quo_turn < 0 or quo_turn >= quo_walls_left.size() or int(quo_walls_left[quo_turn]) <= 0:
		return false
	if not _quo_wall_placement_legal(hx, hy, vertical):
		return false
	var key: String = ("v%d,%d" % [hx, hy]) if vertical else ("h%d,%d" % [hx, hy])
	quo_walls[key] = true
	return true

func _quo_apply_move(player: int, target: Vector2i) -> void:
	quo_pawns[player] = target
	if _quo_goal_reached(player, target):
		quo_game_over = true
		quo_winner = player
		app._go_result()
		return
	_quo_advance_turn(player)

func _quo_advance_turn(completed_player: int) -> void:
	# If a pawn has no legal move, its turn becomes wall-only when it still
	# has walls; otherwise it is skipped. This matters in four-player positions.
	var first_candidate: int = (completed_player + 1) % quo_player_count
	for offset in range(quo_player_count):
		var candidate: int = (first_candidate + offset) % quo_player_count
		var can_move: bool = not _quo_legal_moves(candidate).is_empty()
		var can_wall: bool = int(quo_walls_left[candidate]) > 0
		if not can_move and can_wall:
			can_wall = _quo_has_legal_wall()
		if can_move or can_wall:
			quo_turn = candidate
			quo_mode = 0 if can_move else 1
			if offset > 0:
				app._show_toast("نوبت بازیکنی که حرکت و دیوار نداشت رد شد.")
			return
	# Extremely rare deadlock: nobody can move or place a wall.
	quo_game_over = true
	quo_winner = -1
	app._go_result()

func _quo_next_step(player: int) -> Vector2i:
	var start: Vector2i = quo_pawns[player]
	var previous: Dictionary = {start: start}
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	var goal := Vector2i(-1, -1)
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		if _quo_goal_reached(player, current):
			goal = current
			break
		for next in _quo_legal_moves_from(player, current):
			if not previous.has(next):
				previous[next] = current
				queue.append(next)
	if goal.x < 0:
		return start
	var step: Vector2i = goal
	while previous[step] != start:
		step = previous[step]
	return step

func _quo_cpu() -> void:
	if quo_game_over or quo_turn <= 0 or quo_turn >= quo_player_count:
		return
	var player: int = quo_turn
	var action: Dictionary = quo_ai.choose_action(self, quo_difficulty) if quo_player_count == 2 else quo_ai.choose_action_for_player(self, quo_difficulty, player)
	match str(action.get("type", "move")):
		"wall":
			if _quo_place_wall(int(action.get("x", -1)), int(action.get("y", -1)), bool(action.get("vertical", false))):
				quo_walls_left[player] -= 1
				quo_mode = 0
				_quo_advance_turn(player)
				return
		"pass":
			_quo_advance_turn(player)
			return
	var step: Vector2i = action.get("to", _quo_next_step(player))
	if step == quo_pawns[player] or step not in _quo_legal_moves(player):
		step = _quo_next_step(player)
	if step == quo_pawns[player]:
		_quo_advance_turn(player)
		return
	# Store only actual CPU moves, never temporary positions explored by search.
	if quo_player_count == 2:
		quo_cpu_position_history.append(step)
		while quo_cpu_position_history.size() > 12:
			quo_cpu_position_history.pop_front()
	else:
		var history_key: String = str(player)
		var history: Array = quo_cpu_position_history_by_player.get(history_key, [])
		history.append(step)
		while history.size() > 12:
			history.pop_front()
		quo_cpu_position_history_by_player[history_key] = history
	_quo_apply_move(player, step)

func _quo_my_turn() -> bool:
	if quo_local_multiplayer:
		return true
	return true if app.vs_cpu and quo_turn == 0 else (not app.vs_cpu and quo_turn == app.local_seat)

func _quo_edge_at(p: Vector2) -> Dictionary:
	var gx: int = int(floor((p.x - app.QUO_ORIGIN.x) / app.QUO_CELL))
	var gy: int = int(floor((p.y - app.QUO_ORIGIN.y) / app.QUO_CELL))
	if gx < 0 or gx > 8 or gy < 0 or gy > 8:
		return {}
	var fx: float = p.x - app.QUO_ORIGIN.x - gx * app.QUO_CELL
	var fy: float = p.y - app.QUO_ORIGIN.y - gy * app.QUO_CELL
	var cands: Array = [
		{"d": app.QUO_CELL - fy, "x": gx, "y": gy, "v": false, "ok": gx <= 7 and gy <= 7},
		{"d": fy, "x": gx, "y": gy - 1, "v": false, "ok": gx <= 7 and gy - 1 >= 0 and gy - 1 <= 7},
		{"d": app.QUO_CELL - fx, "x": gx, "y": gy, "v": true, "ok": gx <= 7 and gy <= 7},
		{"d": fx, "x": gx - 1, "y": gy, "v": true, "ok": gx - 1 >= 0 and gx - 1 <= 7 and gy <= 7},
	]
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.d) < float(b.d))
	for candidate in cands:
		if bool(candidate.ok):
			return candidate
	return {}

func _quo_net_apply(kind: int, x: int, y: int, vertical: bool) -> void:
	if quo_game_over:
		return
	if kind == 0:
		var target := Vector2i(x, y)
		if target in _quo_legal_moves(quo_turn):
			quo_mode = 0
			_quo_apply_move(quo_turn, target)
	else:
		if quo_walls_left[quo_turn] <= 0:
			return
		if _quo_place_wall(x, y, vertical):
			var completed_player: int = quo_turn
			quo_walls_left[completed_player] -= 1
			quo_mode = 0
			_quo_advance_turn(completed_player)

func _quo_tap(p: Vector2) -> void:
	if quo_game_over or not _quo_my_turn():
		return
	if quo_mode == 0:
		var target := Vector2i(
			int(floor((p.x - app.QUO_ORIGIN.x) / app.QUO_CELL)),
			int(floor((p.y - app.QUO_ORIGIN.y) / app.QUO_CELL))
		)
		if target in _quo_legal_moves(quo_turn):
			if app._net_on():
				app._send_game_action("_rpc_quo_action", [0, target.x, target.y, false, quo_turn])
			else:
				_quo_apply_move(quo_turn, target)
	else:
		if quo_walls_left[quo_turn] <= 0:
			app._show_toast("دیوار باقی نمانده است.")
			return
		var edge: Dictionary = _quo_edge_at(p)
		if edge.is_empty():
			return
		if app._net_on():
			if _quo_wall_placement_legal(int(edge.x), int(edge.y), bool(edge.v)):
				app._send_game_action("_rpc_quo_action", [1, int(edge.x), int(edge.y), bool(edge.v), quo_turn])
			else:
				app._show_toast("دیوار غیرمجاز است: هم‌پوشانی، تقاطع یا بستن مسیر بازیکن.")
		elif _quo_place_wall(int(edge.x), int(edge.y), bool(edge.v)):
			var completed_player: int = quo_turn
			quo_walls_left[completed_player] -= 1
			_quo_advance_turn(completed_player)
		else:
			app._show_toast("دیوار غیرمجاز است: هم‌پوشانی، تقاطع یا بستن مسیر بازیکن.")

func _btns_quoridor() -> void:
	if quo_game_over:
		return
	var mine: bool = _quo_my_turn()
	var walls: int = int(quo_walls_left[quo_turn]) if mine else 0
	app._add_btn(Rect2(app.VIEW_W - 16 - 240, 826, 240, 50), "حرکت مهره", _set_quo_mode.bind(0), mine, app.BLUE, "seg_on" if quo_mode == 0 else "ghost", "", "qm_move")
	app._add_btn(Rect2(16, 826, 240, 50), "دیوار (%s)" % app._fa(walls) if mine else "دیوار", _set_quo_mode.bind(1), mine and walls > 0, app.ACCENT, "seg_on" if quo_mode == 1 else "ghost", "", "qm_wall")

func _set_quo_mode(mode: int) -> void:
	quo_mode = mode

func _quo_color(player: int) -> Color:
	match player:
		0: return Color(0.35, 0.60, 1.0)
		1: return Color(1.0, 0.45, 0.50)
		2: return Color(0.34, 0.82, 0.58)
		3: return Color(1.0, 0.78, 0.30)
	return Color.WHITE

func _draw_four_player_hud() -> void:
	app._draw_bar_top(72.0)
	app._txt_c("کوریدور · چهار نفره", Rect2(70, 10, app.VIEW_W - 140, 48), 22, app.TEXT, true)
	for player in range(4):
		var rect := Rect2(16.0 + float(player % 2) * 254.0, 76.0 + floor(float(player) / 2.0) * 42.0, 246.0, 36.0)
		var color: Color = _quo_color(player)
		var active: bool = player == quo_turn and not quo_game_over
		app._panel(rect, Color(0.14, 0.17, 0.32) if active else app.CARD, 11.0, Color(color.r, color.g, color.b, 0.95 if active else 0.35), 1.5 if active else 1.0)
		app.draw_circle(Vector2(rect.position.x + 16.0, rect.get_center().y), 7.0, color)
		var player_label: String = "شما" if app.vs_cpu and player == 0 else ("CPU %s" % app._fa(player) if app.vs_cpu else "بازیکن %s" % app._fa(player + 1))
		app._txt_r(player_label, rect.end.x - 9.0, rect.position.y + 15.0, 13, app.TEXT, true, 100.0)
		app._txt_r("دیوار: %s" % app._fa(quo_walls_left[player]), rect.end.x - 112.0, rect.position.y + 29.0, 10, app.ACCENT if active else app.TEXT_DIM, false, 100.0)
		if active:
			app._txt("نوبت", rect.position.x + 28.0, rect.position.y + 23.0, 10, app.ACCENT, HORIZONTAL_ALIGNMENT_LEFT, 48.0, true)

func _draw_quoridor() -> void:
	if quo_player_count == 4:
		_draw_four_player_hud()
	else:
		var pa: Dictionary = app._pl("شما" if app.vs_cpu else "بازیکن ۱", _quo_color(0), "", quo_turn == 0 and not quo_game_over, app._seat_me(0), "دیوار: " + app._fa(quo_walls_left[0]))
		var pb: Dictionary = app._pl("CPU" if app.vs_cpu else "بازیکن ۲", _quo_color(1), "", quo_turn == 1 and not quo_game_over, app._seat_me(1), "دیوار: " + app._fa(quo_walls_left[1]))
		if quo_turn == 0 and not quo_game_over:
			pa.sub = "نوبت شما" if app._seat_me(0) else "نوبت حریف"
		if quo_turn == 1 and not quo_game_over:
			pb.sub = "نوبت شما" if app._seat_me(1) else "نوبت حریف"
		pa.score = app._fa(quo_walls_left[0])
		pb.score = app._fa(quo_walls_left[1])
		app._draw_hud("کوریدور", pa, pb)
	var origin: Vector2 = app.QUO_ORIGIN
	var cell: float = app.QUO_CELL
	app._panel(Rect2(origin - Vector2(10, 10), Vector2(cell * 9 + 20, cell * 9 + 20)), Color(0.12, 0.10, 0.24), 22, Color(0.55, 0.40, 0.95, 0.4), 1.5, 22, 8)
	for y in range(9):
		for x in range(9):
			var rect := Rect2(origin.x + x * cell + 3, origin.y + y * cell + 3, cell - 6, cell - 6)
			var base := Color(0.22, 0.20, 0.40)
			if quo_player_count == 2:
				if y == 8:
					base = base.lerp(_quo_color(0), 0.22)
				elif y == 0:
					base = base.lerp(_quo_color(1), 0.22)
			else:
				if y == 8: base = base.lerp(_quo_color(0), 0.18)
				if x == 0: base = base.lerp(_quo_color(1), 0.18)
				if y == 0: base = base.lerp(_quo_color(2), 0.18)
				if x == 8: base = base.lerp(_quo_color(3), 0.18)
			app._panel(rect, base, 8)
	# Show every legal move, including jumps and diagonals.
	var mine: bool = _quo_my_turn() and not quo_game_over
	if mine and quo_mode == 0:
		var moves: Array[Vector2i] = _quo_legal_moves(quo_turn)
		for target in moves:
			app._hint_dot(origin + Vector2(target.x * cell + cell * 0.5, target.y * cell + cell * 0.5), 6, app.ACCENT)
	# Every wall spans two cell spaces, matching the rules engine.
	for wall_key in quo_walls:
		var parts: PackedStringArray = str(wall_key).split(",")
		var orientation: String = parts[0]
		var wx: int = int(orientation.substr(1))
		var wy: int = int(parts[1])
		var wall_rect: Rect2
		if orientation.begins_with("h"):
			wall_rect = Rect2(origin.x + wx * cell + 3, origin.y + (wy + 1) * cell - 4, cell * 2 - 6, 8)
		else:
			wall_rect = Rect2(origin.x + (wx + 1) * cell - 4, origin.y + wy * cell + 3, 8, cell * 2 - 6)
		app._panel(wall_rect, Color(1.0, 0.78, 0.35), 4, Color(0.6, 0.4, 0.1, 0.8), 1.0, 5, 2)
	# Placement preview also uses the full two-space wall length.
	if mine and quo_mode == 1 and quo_walls_left[quo_turn] > 0:
		var edge: Dictionary = _quo_edge_at(app._ptr)
		if not edge.is_empty():
			var ghost: Rect2
			if not bool(edge.v):
				ghost = Rect2(origin.x + int(edge.x) * cell + 3, origin.y + (int(edge.y) + 1) * cell - 4, cell * 2 - 6, 8)
			else:
				ghost = Rect2(origin.x + (int(edge.x) + 1) * cell - 4, origin.y + int(edge.y) * cell + 3, 8, cell * 2 - 6)
			var key: String = ("v%d,%d" % [int(edge.x), int(edge.y)]) if bool(edge.v) else ("h%d,%d" % [int(edge.x), int(edge.y)])
			var allowed: bool = _quo_wall_placement_legal(int(edge.x), int(edge.y), bool(edge.v)) and not quo_walls.has(key)
			app._panel(ghost, Color(0.35, 0.95, 0.70, 0.58) if allowed else Color(1.0, 0.30, 0.35, 0.5), 4)
	# Pawns
	for player in range(quo_player_count):
		var pawn_center: Vector2 = origin + Vector2(quo_pawns[player].x * cell + cell * 0.5, quo_pawns[player].y * cell + cell * 0.5)
		var pawn_color: Color = _quo_color(player)
		app._draw_marble(pawn_center, 16.5, pawn_color)
		app._txt_c(app._fa(player + 1), Rect2(pawn_center.x - 16, pawn_center.y - 16, 32, 32), 15, app._lum_text(pawn_color), true)
	if not quo_game_over:
		if quo_mode == 1 and mine:
			app._hint("دیوار را روی شکاف بگذارید؛ هر دیوار دو خانه طول دارد", 668, app.ACCENT)
		elif mine and _quo_legal_moves(quo_turn).is_empty():
			app._hint("حرکت مهره بسته است؛ یک دیوار قرار دهید", 668, app.ACCENT)
		elif mine:
			app._hint("مهره را به یکی از خانه‌های نقطه‌دار ببرید؛ پرش و حرکت مورب مجاز است", 668, app.TEXT_DIM)
		else:
			app._hint("حریف در حال حرکت…", 668, app.TEXT_DIM)
