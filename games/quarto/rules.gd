extends "res://core/game_module.gd"
## Standard Quarto rules. Pieces have four binary attributes encoded in bits 0..3.
## A player wins by placing a piece that completes a four-piece line sharing any attribute.

const QuartoAIScript = preload("res://games/quarto/ai.gd")

var qto_board: Array = []                 # 4x4, -1 empty, otherwise piece id 0..15
var qto_remaining: Array[int] = []        # Pieces not yet offered or placed
var qto_turn: int = 1                     # Player whose action is next (1 or 2)
var qto_phase: int = 0                    # 0 choose piece for opponent, 1 place offered piece
var qto_piece_to_place: int = -1
var qto_last_cell: Vector2i = Vector2i(-1, -1)
var qto_game_over: bool = false
var qto_winner: int = -1                  # -1 ongoing, 0 draw, 1/2 winner
var qto_difficulty: int = 3
var _qto_ai = QuartoAIScript.new()

func reset_game() -> void:
	_qto_reset()

func _qto_reset() -> void:
	qto_board = []
	for y in range(4):
		var row: Array[int] = []
		for x in range(4):
			row.append(-1)
		qto_board.append(row)
	qto_remaining.clear()
	for piece in range(16):
		qto_remaining.append(piece)
	qto_turn = 1
	qto_phase = 0
	qto_piece_to_place = -1
	qto_last_cell = Vector2i(-1, -1)
	qto_game_over = false
	qto_winner = -1

func _qto_lines() -> Array:
	var lines: Array = []
	for y in range(4):
		var row: Array[Vector2i] = []
		for x in range(4):
			row.append(Vector2i(x, y))
		lines.append(row)
	for x in range(4):
		var col: Array[Vector2i] = []
		for y in range(4):
			col.append(Vector2i(x, y))
		lines.append(col)
	var diag_a: Array[Vector2i] = []
	var diag_b: Array[Vector2i] = []
	for i in range(4):
		diag_a.append(Vector2i(i, i))
		diag_b.append(Vector2i(3 - i, i))
	lines.append(diag_a)
	lines.append(diag_b)
	return lines

func _qto_line_has_shared_attribute(line: Array, board: Array) -> bool:
	if line.size() != 4:
		return false
	var all_true: int = 15
	var all_false: int = 15
	for cell in line:
		var piece: int = int(board[cell.y][cell.x])
		if piece < 0:
			return false
		all_true = all_true & piece
		all_false = all_false & ((~piece) & 15)
	return all_true != 0 or all_false != 0

func _qto_has_quarto() -> bool:
	for line in _qto_lines():
		if _qto_line_has_shared_attribute(line, qto_board):
			return true
	return false

func _qto_empty_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(4):
		for x in range(4):
			if int(qto_board[y][x]) < 0:
				cells.append(Vector2i(x, y))
	return cells

func _qto_winning_cells_for_piece(piece: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if piece < 0 or piece > 15:
		return cells
	for cell in _qto_empty_cells():
		qto_board[cell.y][cell.x] = piece
		var wins: bool = _qto_has_quarto()
		qto_board[cell.y][cell.x] = -1
		if wins:
			cells.append(cell)
	return cells

func _qto_count_placed() -> int:
	var count: int = 0
	for y in range(4):
		for x in range(4):
			if int(qto_board[y][x]) >= 0:
				count += 1
	return count

func _qto_finish(winner: int) -> void:
	if qto_game_over:
		return
	qto_game_over = true
	qto_winner = winner
	qto_phase = 0
	qto_piece_to_place = -1
	app._go_result()

func _qto_choose_piece(piece: int, actor: int) -> bool:
	if qto_game_over or qto_phase != 0 or actor != qto_turn or piece not in qto_remaining:
		return false
	qto_remaining.erase(piece)
	qto_piece_to_place = piece
	qto_phase = 1
	qto_turn = 3 - actor
	app._rebuild_buttons()
	return true

func _qto_place(x: int, y: int, actor: int) -> bool:
	if qto_game_over or qto_phase != 1 or actor != qto_turn or qto_piece_to_place < 0:
		return false
	if x < 0 or x >= 4 or y < 0 or y >= 4 or int(qto_board[y][x]) >= 0:
		return false
	qto_board[y][x] = qto_piece_to_place
	qto_last_cell = Vector2i(x, y)
	qto_piece_to_place = -1
	if _qto_has_quarto():
		_qto_finish(actor)
		return true
	if _qto_empty_cells().is_empty():
		_qto_finish(0)
		return true
	# The player who placed the piece now chooses a piece for the opponent.
	qto_phase = 0
	qto_turn = actor
	app._rebuild_buttons()
	return true

func _qto_pick_piece(piece: int) -> void:
	if not _qto_is_local_actor() or qto_phase != 0:
		return
	if app._net_on():
		app._send_game_action("_rpc_quarto_choose_piece", [app.local_seat, piece])
	else:
		if not _qto_choose_piece(piece, qto_turn):
			app._show_toast("این مهره در دسترس نیست.")

func _qto_is_local_actor() -> bool:
	if qto_game_over:
		return false
	if app.vs_cpu:
		return qto_turn == 1
	return app._is_my_turn()

func _qto_tap(p: Vector2) -> void:
	if qto_game_over or not _qto_is_local_actor() or qto_phase != 1:
		return
	var origin: Vector2 = _qto_board_origin()
	var cell_size: float = app.QUARTO_CELL
	var gap: float = app.QUARTO_GAP
	for y in range(4):
		for x in range(4):
			var rect := Rect2(origin.x + x * (cell_size + gap), origin.y + y * (cell_size + gap), cell_size, cell_size)
			if not rect.has_point(p):
				continue
			if app._net_on():
				app._send_game_action("_rpc_quarto_place", [app.local_seat, x, y])
			elif not _qto_place(x, y, qto_turn):
				app._show_toast("این خانه در دسترس نیست.")
			return
	app._show_toast("یک خانه‌ی داخل صفحه را انتخاب کنید.")

func _qto_board_origin() -> Vector2:
	return Vector2((app.VIEW_W - (app.QUARTO_CELL * 4.0 + app.QUARTO_GAP * 3.0)) * 0.5, app.QUARTO_ORIGIN_Y)

func _qto_me() -> int:
	return 1 if app.vs_cpu else app.local_seat + 1

func _btns_quarto() -> void:
	if qto_game_over or qto_phase != 0 or not _qto_is_local_actor():
		return
	for piece in qto_remaining:
		var rect: Rect2 = app._quarto_piece_rect(int(piece))
		app._add_hit(rect, _qto_pick_piece.bind(int(piece)), "quarto_piece_%d" % int(piece), false, true)

func _qto_cpu_step() -> void:
	if qto_game_over or qto_turn != 2 or not app.vs_cpu:
		return
	if qto_phase == 0:
		var piece: int = _qto_ai.choose_piece(self, qto_difficulty)
		if piece >= 0:
			_qto_choose_piece(piece, 2)
	else:
		var cell: Vector2i = _qto_ai.choose_cell(self, qto_difficulty, qto_piece_to_place)
		if cell.x >= 0 and cell.y >= 0:
			_qto_place(cell.x, cell.y, 2)

func _qto_difficulty_name() -> String:
	var labels: Array[String] = ["خیلی آسان", "آسان", "متوسط", "سخت", "استاد", "استادتمام"]
	return labels[clampi(qto_difficulty, 1, 6) - 1]
