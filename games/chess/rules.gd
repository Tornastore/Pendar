extends "res://core/game_module.gd"
## Rule engine and authoritative state for chess.

const ChessAIScript = preload("res://games/chess/ai.gd")
const ChessPresentationScript = preload("res://games/chess/presentation.gd")

# ---------- Game-owned state ----------
var _presentation = ChessPresentationScript.new()

var chess_difficulty: int = 3
var chess_board: Array = []
var chess_turn: int = 1           # 1 white, 2 black
var chess_selected: Vector2i = Vector2i(-1, -1)
var chess_valid: Array = []
var chess_game_over: bool = false
var chess_winner: int = 0
var chess_last: Array = [Vector2i(-1,-1), Vector2i(-1,-1)]  # from, to

func reset_game() -> void:
	_reset_chess()

func _reset_chess() -> void:
	chess_board = []
	# standard start
	var back := [4, 2, 3, 5, 6, 3, 2, 4]  # R N B Q K B N R
	for y in 8:
		var row: Array = []
		for x in 8:
			row.append(0)
		chess_board.append(row)
	for x in 8:
		chess_board[0][x] = back[x] + 6   # black
		chess_board[1][x] = 7            # black pawn
		chess_board[6][x] = 1            # white pawn
		chess_board[7][x] = back[x]      # white
	chess_turn = 1
	chess_selected = Vector2i(-1, -1)
	chess_valid = []
	chess_game_over = false
	chess_winner = 0
	chess_last = [Vector2i(-1,-1), Vector2i(-1,-1)]

func _chess_color(piece: int) -> int:
	if piece == 0:
		return 0
	return 1 if piece <= 6 else 2

func _chess_in(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < 8 and c.y >= 0 and c.y < 8

func _chess_gen_moves(from: Vector2i) -> Array:
	var piece: int = chess_board[from.y][from.x]
	if piece == 0:
		return []
	var col := _chess_color(piece)
	var typ := piece if col == 1 else piece - 6
	var moves: Array = []
	var enemy := 3 - col

	match typ:
		1:  # pawn
			var dir := -1 if col == 1 else 1
			var one := from + Vector2i(0, dir)
			if _chess_in(one) and chess_board[one.y][one.x] == 0:
				moves.append(one)
				var start_row := 6 if col == 1 else 1
				var two := from + Vector2i(0, dir * 2)
				if from.y == start_row and chess_board[two.y][two.x] == 0:
					moves.append(two)
			for dx in [-1, 1]:
				var cap: Vector2i = from + Vector2i(dx, dir)
				if _chess_in(cap) and _chess_color(chess_board[cap.y][cap.x]) == enemy:
					moves.append(cap)
		2:  # knight
			for d in [Vector2i(1,2), Vector2i(2,1), Vector2i(-1,2), Vector2i(-2,1), Vector2i(1,-2), Vector2i(2,-1), Vector2i(-1,-2), Vector2i(-2,-1)]:
				var dir: Vector2i = d
				var n: Vector2i = from + dir
				if _chess_in(n) and _chess_color(chess_board[n.y][n.x]) != col:
					moves.append(n)
		3, 4, 5:  # bishop, rook, queen
			var dirs: Array = []
			if typ == 3 or typ == 5:
				dirs.append_array([Vector2i(1,1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(-1,-1)])
			if typ == 4 or typ == 5:
				dirs.append_array([Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)])
			for d in dirs:
				var dir: Vector2i = d
				var n: Vector2i = from + dir
				while _chess_in(n):
					var pc: int = chess_board[n.y][n.x]
					if pc == 0:
						moves.append(n)
					elif _chess_color(pc) == enemy:
						moves.append(n)
						break
					else:
						break
					n += dir
		6:  # king
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var n := from + Vector2i(dx, dy)
					if _chess_in(n) and _chess_color(chess_board[n.y][n.x]) != col:
						moves.append(n)
	return moves

func _chess_all_moves(col: int) -> Array:
	var res: Array = []
	for y in 8:
		for x in 8:
			if _chess_color(chess_board[y][x]) == col:
				var from := Vector2i(x, y)
				for to in _chess_gen_moves(from):
					res.append([from, to])
	return res

func _chess_make_move(from: Vector2i, to: Vector2i) -> void:
	var piece: int = chess_board[from.y][from.x]
	# promotion
	if (piece == 1 and to.y == 0) or (piece == 7 and to.y == 7):
		piece = 5 if piece == 1 else 11  # queen
	chess_board[to.y][to.x] = piece
	chess_board[from.y][from.x] = 0
	chess_last = [from, to]
	chess_selected = Vector2i(-1, -1)
	chess_valid = []
	# check king captured (simple win condition for prototype)
	var has_king := [false, false, false]
	for y in 8:
		for x in 8:
			var p: int = chess_board[y][x]
			if p == 6:
				has_king[1] = true
			elif p == 12:
				has_king[2] = true
	if not has_king[1]:
		chess_game_over = true
		chess_winner = 2
		app._go_result()
		return
	if not has_king[2]:
		chess_game_over = true
		chess_winner = 1
		app._go_result()
		return
	chess_turn = 3 - chess_turn

func _chess_cpu_move() -> void:
	if chess_game_over or chess_turn != 2:
		return
	var ai = ChessAIScript.new()
	var best: Array = ai.choose_move(self, chess_difficulty)
	if best.is_empty():
		chess_game_over = true
		chess_winner = 1
		app._go_result()
		return
	_chess_make_move(best[0], best[1])

func _chess_king_in_check(col: int) -> Vector2i:
	var kp := Vector2i(-1, -1)
	var kv: int = 6 if col == 1 else 12
	for y in 8:
		for x in 8:
			if chess_board[y][x] == kv:
				kp = Vector2i(x, y)
	if kp.x < 0:
		return kp
	for y in 8:
		for x in 8:
			if _chess_color(chess_board[y][x]) == 3 - col:
				if kp in _chess_gen_moves(Vector2i(x, y)):
					return kp
	return Vector2i(-1, -1)

func _chess_flip() -> bool:
	return _presentation.is_flipped(app)

func _chess_scr(c: Vector2i) -> Vector2i:
	return _presentation.orient_cell(app, c)

func _chess_center(c: Vector2i) -> Vector2:
	return _presentation.cell_center(app, c)

func _chess_my_turn() -> bool:
	if app.vs_cpu:
		return chess_turn == 1
	return app._is_my_turn()

func _chess_tap(p: Vector2) -> void:
	if chess_game_over or not _chess_my_turn():
		return
	var c: Vector2i = _presentation.screen_to_board_cell(app, p)
	if c.x < 0:
		return
	if chess_selected.x >= 0:
		if c in chess_valid:
			if app._net_on():
				app._send_game_action("_rpc_chess_move", [chess_selected.x, chess_selected.y, c.x, c.y])
			else:
				_chess_make_move(chess_selected, c)
			return
		chess_selected = Vector2i(-1, -1)
		chess_valid = []
	if _chess_color(chess_board[c.y][c.x]) == chess_turn:
		chess_selected = c
		chess_valid = _chess_gen_moves(c)

func _draw_chess() -> void:
	_presentation.render(app, self)
