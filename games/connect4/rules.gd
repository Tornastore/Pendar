extends "res://core/game_module.gd"
## Standard Connect Four rules. Board values: -1 empty, 0 first seat, 1 second seat.
const PresentationScript = preload("res://games/connect4/presentation.gd")
var _presentation = PresentationScript.new()
const C4_COLUMN_ORDER: Array[int] = [3, 2, 4, 1, 5, 0, 6]
var _c4_nodes: int = 0
var _c4_node_limit: int = 2400
var _c4_deadline_usec: int = 0
var _c4_search_aborted: bool = false
var _c4_transposition: Dictionary = {}

var c4_board: Array = []
var c4_turn: int = 0
var c4_difficulty: int = 3
var c4_game_over: bool = false
var c4_winner: int = -1
var c4_moves: int = 0
var c4_last_column: int = -1

func reset_game() -> void:
	_reset_connect4()

func _reset_connect4() -> void:
	c4_board = []
	for _y in range(6):
		var row: Array[int] = []
		for _x in range(7):
			row.append(-1)
		c4_board.append(row)
	c4_turn = 0
	c4_game_over = false
	c4_winner = -1
	c4_moves = 0
	c4_last_column = -1
	if app != null:
		app._rebuild_buttons()

func _c4_my_turn() -> bool:
	if c4_game_over:
		return false
	return c4_turn == (0 if app.vs_cpu else app.local_seat)

func _c4_landing_row(column: int) -> int:
	if column < 0 or column >= 7:
		return -1
	for y in range(5, -1, -1):
		if int(c4_board[y][column]) < 0:
			return y
	return -1

func _c4_legal_columns(board: Array = []) -> Array[int]:
	var source: Array = c4_board if board.is_empty() else board
	var result: Array[int] = []
	for x in range(7):
		if int(source[0][x]) < 0:
			result.append(x)
	return result

func _c4_has_four(board: Array, player: int) -> bool:
	for y in range(6):
		for x in range(7):
			if int(board[y][x]) != player:
				continue
			for direction in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
				var ex: int = x + direction.x * 3
				var ey: int = y + direction.y * 3
				if ex < 0 or ex >= 7 or ey < 0 or ey >= 6:
					continue
				var matches: bool = true
				for step in range(1, 4):
					if int(board[y + direction.y * step][x + direction.x * step]) != player:
						matches = false
						break
				if matches:
					return true
	return false

func _c4_apply_drop(seat: int, column: int) -> bool:
	if c4_game_over or seat != c4_turn or column < 0 or column >= 7:
		return false
	var y: int = _c4_landing_row(column)
	if y < 0:
		return false
	c4_board[y][column] = seat
	c4_last_column = column
	c4_moves += 1
	if _c4_has_four(c4_board, seat):
		c4_game_over = true
		c4_winner = seat
	elif c4_moves >= 42:
		c4_game_over = true
		c4_winner = -1
	else:
		c4_turn = 1 - seat
	if c4_game_over and app != null:
		app._go_result(c4_winner == (0 if app.vs_cpu else app.local_seat))
	if app != null:
		app._rebuild_buttons()
	return true

func _c4_submit_column(column: int) -> void:
	if not _c4_my_turn() or _c4_landing_row(column) < 0:
		return
	var seat: int = 0 if app.vs_cpu else app.local_seat
	if app._net_on():
		app._send_game_action("_rpc_connect4_drop", [seat, column])
	else:
		if _c4_apply_drop(seat, column) and app.vs_cpu and not c4_game_over:
			app._schedule_cpu(0.42, _c4_cpu_move)

func _c4_cpu_move() -> void:
	if not app.vs_cpu or c4_game_over or c4_turn == 0:
		return
	var legal: Array[int] = _c4_legal_columns()
	if legal.is_empty():
		return
	var ordered: Array[int] = _c4_ordered_columns(legal)
	# Win now or block the opponent's immediate win before considering heuristics.
	for col in ordered:
		var row: int = _c4_landing_row(col)
		c4_board[row][col] = 1
		var wins: bool = _c4_has_four(c4_board, 1)
		c4_board[row][col] = -1
		if wins:
			_c4_apply_drop(1, col)
			return
	for col in ordered:
		var row: int = _c4_landing_row(col)
		c4_board[row][col] = 0
		var opponent_wins: bool = _c4_has_four(c4_board, 0)
		c4_board[row][col] = -1
		if opponent_wins:
			_c4_apply_drop(1, col)
			return

	var level: int = clampi(c4_difficulty, 1, 6)
	var depth_by_level: Array[int] = [2, 3, 4, 5, 6, 7]
	var node_limit_by_level: Array[int] = [180, 340, 700, 1250, 2300, 3900]
	var time_limit_usec_by_level: Array[int] = [3500, 5000, 7000, 10000, 14000, 20000]
	_c4_nodes = 0
	_c4_node_limit = node_limit_by_level[level - 1]
	_c4_deadline_usec = Time.get_ticks_usec() + time_limit_usec_by_level[level - 1]
	_c4_search_aborted = false
	_c4_transposition.clear()
	var best_col: int = ordered[0]
	# Iterative deepening makes the search interruption-safe: a move is promoted
	# only when every legal root move has completed at that depth. If the browser
	# hits a time/node budget, retain the best move from the last completed depth.
	for search_depth in range(1, depth_by_level[level - 1] + 1):
		var iteration_col: int = best_col
		var iteration_score: int = -1000000
		var root_alpha: int = -1000000
		var iteration_complete: bool = true
		for col in ordered:
			if _c4_search_aborted or _c4_nodes >= _c4_node_limit or Time.get_ticks_usec() >= _c4_deadline_usec:
				_c4_search_aborted = true
				iteration_complete = false
				break
			var landing_row: int = _c4_landing_row(col)
			if landing_row < 0:
				continue
			c4_board[landing_row][col] = 1
			var score: int = _c4_minimax(c4_board, search_depth - 1, false, root_alpha, 1000000, 1)
			c4_board[landing_row][col] = -1
			if _c4_search_aborted:
				iteration_complete = false
				break
			if score > iteration_score:
				iteration_score = score
				iteration_col = col
				root_alpha = score
		if iteration_complete:
			best_col = iteration_col
		else:
			break
	# Lower levels are allowed to make occasional non-tactical mistakes; levels
	# 3–6 use the best fully completed search result and are reproducible on ties.
	if level == 1 and randf() < 0.45:
		best_col = int(ordered[randi_range(0, ordered.size() - 1)])
	elif level == 2 and randf() < 0.20:
		best_col = int(ordered[randi_range(0, ordered.size() - 1)])
	_c4_apply_drop(1, best_col)


func _c4_landing_row_on(board: Array, column: int) -> int:
	if column < 0 or column >= 7:
		return -1
	for y in range(5, -1, -1):
		if int(board[y][column]) < 0:
			return y
	return -1


func _c4_ordered_columns(legal: Array[int]) -> Array[int]:
	var ordered: Array[int] = []
	for col in C4_COLUMN_ORDER:
		if col in legal:
			ordered.append(col)
	return ordered


func _c4_board_key(board: Array, maximizing: bool) -> String:
	var key: String = "1|" if maximizing else "0|"
	for y in range(6):
		for x in range(7):
			key += str(int(board[y][x]) + 1)
	return key


func _c4_minimax(board: Array, depth: int, maximizing: bool, alpha_in: int, beta_in: int, last_player: int) -> int:
	if _c4_search_aborted:
		return _c4_evaluate(board)
	if _c4_nodes >= _c4_node_limit or Time.get_ticks_usec() >= _c4_deadline_usec:
		_c4_search_aborted = true
		return _c4_evaluate(board)
	_c4_nodes += 1
	if _c4_has_four(board, 1):
		return 100000 + depth * 100
	if _c4_has_four(board, 0):
		return -100000 - depth * 100
	var legal: Array[int] = _c4_legal_columns(board)
	if depth <= 0 or legal.is_empty():
		return _c4_evaluate(board)

	var alpha_original: int = alpha_in
	var beta_original: int = beta_in
	var alpha: int = alpha_in
	var beta: int = beta_in
	var key: String = _c4_board_key(board, maximizing)
	if _c4_transposition.has(key):
		var cached: Dictionary = _c4_transposition[key]
		if int(cached.get("depth", -1)) >= depth:
			var cached_score: int = int(cached.get("score", 0))
			match int(cached.get("bound", 0)):
				0:
					return cached_score
				1:
					alpha = maxi(alpha, cached_score)
				2:
					beta = mini(beta, cached_score)
			if alpha >= beta:
				return cached_score

	var best_value: int = -1000000 if maximizing else 1000000
	for col in _c4_ordered_columns(legal):
		if _c4_search_aborted:
			break
		var row: int = _c4_landing_row_on(board, col)
		if row < 0:
			continue
		board[row][col] = 1 if maximizing else 0
		var value: int = _c4_minimax(board, depth - 1, not maximizing, alpha, beta, 1 if maximizing else 0)
		board[row][col] = -1
		if maximizing:
			best_value = maxi(best_value, value)
			alpha = maxi(alpha, best_value)
		else:
			best_value = mini(best_value, value)
			beta = mini(beta, best_value)
		if alpha >= beta:
			break
	if _c4_search_aborted:
		return _c4_evaluate(board)
	var bound: int = 0 # exact, lower bound, upper bound
	if best_value <= alpha_original:
		bound = 2
	elif best_value >= beta_original:
		bound = 1
	_c4_transposition[key] = {"depth": depth, "score": best_value, "bound": bound}
	return best_value


func _c4_evaluate(board: Array) -> int:
	var score: int = 0
	# Center columns create more overlapping four-in-a-row windows.
	for y in range(6):
		for x in range(7):
			var piece: int = int(board[y][x])
			var center_weight: int = 4 - absi(x - 3)
			if piece == 1:
				score += center_weight * 2
			elif piece == 0:
				score -= center_weight * 2
	var directions: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
	for y in range(6):
		for x in range(7):
			for direction in directions:
				var ex: int = x + direction.x * 3
				var ey: int = y + direction.y * 3
				if ex < 0 or ex >= 7 or ey < 0 or ey >= 6:
					continue
				var cpu: int = 0
				var human: int = 0
				var empty: int = 0
				var empty_cell: Vector2i = Vector2i(-1, -1)
				for step in range(4):
					var cell_x: int = x + direction.x * step
					var cell_y: int = y + direction.y * step
					var value: int = int(board[cell_y][cell_x])
					if value == 1:
						cpu += 1
					elif value == 0:
						human += 1
					else:
						empty += 1
						empty_cell = Vector2i(cell_x, cell_y)
				if human == 0:
					if cpu == 3 and empty == 1:
						score += 90
						if _c4_landing_row_on(board, empty_cell.x) == empty_cell.y:
							score += 420
					elif cpu == 2 and empty == 2:
						score += 14
					elif cpu == 1 and empty == 3:
						score += 2
				if cpu == 0:
					if human == 3 and empty == 1:
						score -= 110
						if _c4_landing_row_on(board, empty_cell.x) == empty_cell.y:
							score -= 600
					elif human == 2 and empty == 2:
						score -= 16
					elif human == 1 and empty == 3:
						score -= 2
	return score

func _connect4_tap(point: Vector2) -> void:
	_presentation.handle_tap(app, self, point)

func _draw_connect4() -> void:
	_presentation.render(app, self)

func _btns_connect4() -> void:
	_presentation.build_buttons(app, self)
