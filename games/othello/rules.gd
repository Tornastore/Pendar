extends "res://core/game_module.gd"
## Rule engine and authoritative state for othello.

const OthelloAIScript = preload("res://games/othello/ai.gd")
const OthelloPresentationScript = preload("res://games/othello/presentation.gd")

# ---------- Game-owned state ----------
var oth_size: int = 8
var oth_difficulty: int = 3
var othello_board: Array = []    # 8x8, 0 empty, 1 black, 2 white
var othello_turn: int = 1       # 1 black, 2 white
var othello_last_move: Vector2i = Vector2i(-1, -1)
var othello_valid: Array = []
var othello_scores: Array = [0, 0, 0]
var othello_game_over: bool = false
var othello_winner: int = 0
var _presentation = OthelloPresentationScript.new()

func reset_game() -> void:
	_reset_othello()

func _reset_othello() -> void:
	if oth_size < 8:
		oth_size = 8
	othello_board = []
	for y in oth_size:
		var row: Array = []
		for x in oth_size:
			row.append(0)
		othello_board.append(row)
	var m: int = int(oth_size / 2)
	othello_board[m - 1][m - 1] = 2
	othello_board[m - 1][m] = 1
	othello_board[m][m - 1] = 1
	othello_board[m][m] = 2
	othello_turn = 1
	othello_last_move = Vector2i(-1, -1)
	othello_game_over = false
	othello_winner = 0
	_othello_update_valid()
	_othello_update_scores()

func _othello_update_scores() -> void:
	othello_scores = [0, 0, 0]
	for y in oth_size:
		for x in oth_size:
			othello_scores[othello_board[y][x]] += 1

func _othello_in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < oth_size and c.y >= 0 and c.y < oth_size

func _othello_would_flip(c: Vector2i, color: int) -> Array:
	var flips: Array = []
	if othello_board[c.y][c.x] != 0:
		return flips
	for d in app.OTH_DIRS:
		var dir: Vector2i = d
		var line: Array = []
		var p: Vector2i = c + dir
		while _othello_in_bounds(p) and othello_board[p.y][p.x] == 3 - color:
			line.append(p)
			p += dir
		if line.size() > 0 and _othello_in_bounds(p) and othello_board[p.y][p.x] == color:
			flips.append_array(line)
	return flips

func _othello_update_valid() -> void:
	othello_valid.clear()
	for y in oth_size:
		for x in oth_size:
			var c := Vector2i(x, y)
			if _othello_would_flip(c, othello_turn).size() > 0:
				othello_valid.append(c)

func _othello_place(c: Vector2i) -> bool:
	var flips: Array = _othello_would_flip(c, othello_turn)
	if flips.size() == 0:
		return false
	if app._net_on():
		app._send_game_action("_rpc_othello_place", [c.x, c.y])
	else:
		_othello_apply_place(c)
	return true

func _othello_apply_place(c: Vector2i) -> void:
	var flips: Array = _othello_would_flip(c, othello_turn)
	if flips.size() == 0 and othello_board[c.y][c.x] != 0:
		return
	othello_board[c.y][c.x] = othello_turn
	for f in flips:
		othello_board[f.y][f.x] = othello_turn
	othello_last_move = c
	othello_turn = 3 - othello_turn
	_othello_update_valid()
	_othello_update_scores()
	if othello_valid.size() == 0:
		othello_turn = 3 - othello_turn
		_othello_update_valid()
		if othello_valid.size() == 0:
			othello_game_over = true
			if othello_scores[1] > othello_scores[2]:
				othello_winner = 1
			elif othello_scores[2] > othello_scores[1]:
				othello_winner = 2
			else:
				othello_winner = 0
			app._go_result()

func _othello_cpu_move() -> void:
	if othello_valid.size() == 0 or othello_game_over or othello_turn != 2:
		return
	var ai = OthelloAIScript.new()
	var best: Vector2i = ai.choose_move(othello_board, oth_size, othello_turn, oth_difficulty)
	if best.x < 0 or best.y < 0 or best not in othello_valid:
		best = othello_valid[0]
	_othello_place(best)

func _oth_cell() -> float:
	return _presentation.cell_size(self)

func _oth_origin() -> Vector2:
	return _presentation.board_origin(app, self)

func _oth_my_turn() -> bool:
	return _presentation.is_my_turn(app, self)

func _othello_tap(p: Vector2) -> void:
	_presentation.handle_tap(app, self, p)

func _draw_othello() -> void:
	_presentation.render(app, self)
