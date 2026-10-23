extends "res://core/game_module.gd"
## FIDE-style chess rules and authoritative game state.

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
var chess_last: Array = [Vector2i(-1, -1), Vector2i(-1, -1)]  # from, to

const CASTLE_WHITE_KING: int = 1
const CASTLE_WHITE_QUEEN: int = 2
const CASTLE_BLACK_KING: int = 4
const CASTLE_BLACK_QUEEN: int = 8
var chess_castling_rights: int = 15
var chess_en_passant: Vector2i = Vector2i(-1, -1)
var chess_halfmove_clock: int = 0
var chess_fullmove_number: int = 1
var chess_history: Array[Dictionary] = []
var chess_position_history: Array[String] = []
var chess_move_log: Array[String] = []
var chess_promotion_pending: Dictionary = {}
var chess_terminal_reason: String = ""
var chess_last_notation: String = ""

func reset_game() -> void:
	_reset_chess()

func _reset_chess() -> void:
	chess_board = []
	# Piece IDs: white P/N/B/R/Q/K = 1..6; black P/N/B/R/Q/K = 7..12.
	var back := [4, 2, 3, 5, 6, 3, 2, 4]
	for y in range(8):
		var row: Array = []
		for x in range(8):
			row.append(0)
		chess_board.append(row)
	for x in range(8):
		chess_board[0][x] = back[x] + 6
		chess_board[1][x] = 7
		chess_board[6][x] = 1
		chess_board[7][x] = back[x]
	chess_turn = 1
	chess_selected = Vector2i(-1, -1)
	chess_valid = []
	chess_game_over = false
	chess_winner = 0
	chess_last = [Vector2i(-1, -1), Vector2i(-1, -1)]
	chess_castling_rights = CASTLE_WHITE_KING | CASTLE_WHITE_QUEEN | CASTLE_BLACK_KING | CASTLE_BLACK_QUEEN
	chess_en_passant = Vector2i(-1, -1)
	chess_halfmove_clock = 0
	chess_fullmove_number = 1
	chess_history.clear()
	chess_position_history.clear()
	chess_move_log.clear()
	chess_promotion_pending = {}
	chess_terminal_reason = ""
	chess_last_notation = ""
	chess_position_history.append(_chess_position_key())

func _chess_color(piece: int) -> int:
	if piece == 0:
		return 0
	return 1 if piece <= 6 else 2

func _chess_type(piece: int) -> int:
	if piece <= 0:
		return 0
	return piece if piece <= 6 else piece - 6

func _chess_in(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < 8 and c.y >= 0 and c.y < 8

func _chess_is_square_attacked(target: Vector2i, by_color: int) -> bool:
	if not _chess_in(target):
		return false
	# Pawn attacks are checked geometrically; they do not depend on occupancy
	# of the target square (unlike ordinary pawn move generation).
	var pawn_source_y: int = target.y + (1 if by_color == 1 else -1)
	var pawn_piece: int = 1 if by_color == 1 else 7
	for dx in [-1, 1]:
		var source := Vector2i(target.x + dx, pawn_source_y)
		if _chess_in(source) and int(chess_board[source.y][source.x]) == pawn_piece:
			return true
	# Knight attacks.
	for d in [Vector2i(1, 2), Vector2i(2, 1), Vector2i(-1, 2), Vector2i(-2, 1), Vector2i(1, -2), Vector2i(2, -1), Vector2i(-1, -2), Vector2i(-2, -1)]:
		var source: Vector2i = target + d
		if _chess_in(source):
			var piece: int = int(chess_board[source.y][source.x])
			if piece != 0 and _chess_color(piece) == by_color and _chess_type(piece) == 2:
				return true
	# Adjacent king attacks. Pinned pieces still attack squares for king legality.
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var source := target + Vector2i(dx, dy)
			if _chess_in(source):
				var piece: int = int(chess_board[source.y][source.x])
				if piece != 0 and _chess_color(piece) == by_color and _chess_type(piece) == 6:
					return true
	# Rook/queen rays and bishop/queen diagonals, stopping at first blocker.
	var ray_sets: Array = [
		{"dirs": [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)], "types": [4, 5]},
		{"dirs": [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)], "types": [3, 5]}
	]
	for ray_set in ray_sets:
		for direction in ray_set["dirs"]:
			var cursor: Vector2i = target + direction
			while _chess_in(cursor):
				var piece: int = int(chess_board[cursor.y][cursor.x])
				if piece != 0:
					if _chess_color(piece) == by_color and _chess_type(piece) in ray_set["types"]:
						return true
					break
				cursor += direction
	return false

func _chess_king_in_check(col: int) -> Vector2i:
	var king_piece: int = 6 if col == 1 else 12
	for y in range(8):
		for x in range(8):
			if int(chess_board[y][x]) == king_piece:
				var king := Vector2i(x, y)
				if _chess_is_square_attacked(king, 3 - col):
					return king
				return Vector2i(-1, -1)
	return Vector2i(-1, -1)

func _chess_pseudo_moves(from: Vector2i) -> Array:
	if not _chess_in(from):
		return []
	var piece: int = int(chess_board[from.y][from.x])
	if piece == 0:
		return []
	var col: int = _chess_color(piece)
	var enemy: int = 3 - col
	var typ: int = _chess_type(piece)
	var moves: Array = []
	match typ:
		1:
			var dir: int = -1 if col == 1 else 1
			var one := from + Vector2i(0, dir)
			if _chess_in(one) and int(chess_board[one.y][one.x]) == 0:
				moves.append(one)
				var start_row: int = 6 if col == 1 else 1
				var two := from + Vector2i(0, dir * 2)
				if from.y == start_row and _chess_in(two) and int(chess_board[two.y][two.x]) == 0:
					moves.append(two)
			for dx in [-1, 1]:
				var cap := from + Vector2i(dx, dir)
				if not _chess_in(cap):
					continue
				var target_piece: int = int(chess_board[cap.y][cap.x])
				if target_piece != 0 and _chess_color(target_piece) == enemy and _chess_type(target_piece) != 6:
					moves.append(cap)
				elif cap == chess_en_passant and target_piece == 0:
					var pawn_behind := Vector2i(cap.x, from.y)
					var expected_pawn: int = 7 if col == 1 else 1
					if int(chess_board[pawn_behind.y][pawn_behind.x]) == expected_pawn:
						moves.append(cap)
		2:
			for d in [Vector2i(1, 2), Vector2i(2, 1), Vector2i(-1, 2), Vector2i(-2, 1), Vector2i(1, -2), Vector2i(2, -1), Vector2i(-1, -2), Vector2i(-2, -1)]:
				var target: Vector2i = from + d
				if not _chess_in(target):
					continue
				var target_piece: int = int(chess_board[target.y][target.x])
				if _chess_color(target_piece) != col and _chess_type(target_piece) != 6:
					moves.append(target)
		3, 4, 5:
			var dirs: Array = []
			if typ == 3 or typ == 5:
				dirs.append_array([Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)])
			if typ == 4 or typ == 5:
				dirs.append_array([Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)])
			for d in dirs:
				var target: Vector2i = from + d
				while _chess_in(target):
					var target_piece: int = int(chess_board[target.y][target.x])
					if target_piece == 0:
						moves.append(target)
					else:
						if _chess_color(target_piece) == enemy and _chess_type(target_piece) != 6:
							moves.append(target)
						break
					target += d
		6:
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var target := from + Vector2i(dx, dy)
					if not _chess_in(target):
						continue
					var target_piece: int = int(chess_board[target.y][target.x])
					if _chess_color(target_piece) != col and _chess_type(target_piece) != 6:
						moves.append(target)
			# Castling: king/rook unmoved, path clear, king not in or through check.
			var home_y: int = 7 if col == 1 else 0
			var home := Vector2i(4, home_y)
			var rook_piece: int = 4 if col == 1 else 10
			var king_right: int = CASTLE_WHITE_KING if col == 1 else CASTLE_BLACK_KING
			var queen_right: int = CASTLE_WHITE_QUEEN if col == 1 else CASTLE_BLACK_QUEEN
			if from == home and _chess_king_in_check(col).x < 0:
				if (chess_castling_rights & king_right) != 0 and int(chess_board[home_y][7]) == rook_piece and int(chess_board[home_y][5]) == 0 and int(chess_board[home_y][6]) == 0:
					if _chess_castle_transit_safe(home, Vector2i(5, home_y), col):
						moves.append(Vector2i(6, home_y))
				if (chess_castling_rights & queen_right) != 0 and int(chess_board[home_y][0]) == rook_piece and int(chess_board[home_y][1]) == 0 and int(chess_board[home_y][2]) == 0 and int(chess_board[home_y][3]) == 0:
					if _chess_castle_transit_safe(home, Vector2i(3, home_y), col):
						moves.append(Vector2i(2, home_y))
	return moves

func _chess_castle_transit_safe(home: Vector2i, transit: Vector2i, col: int) -> bool:
	# Move the king temporarily so it cannot accidentally block an attack ray.
	var king_piece: int = 6 if col == 1 else 12
	var prior_transit: int = int(chess_board[transit.y][transit.x])
	chess_board[home.y][home.x] = 0
	chess_board[transit.y][transit.x] = king_piece
	var safe: bool = not _chess_is_square_attacked(transit, 3 - col)
	chess_board[transit.y][transit.x] = prior_transit
	chess_board[home.y][home.x] = king_piece
	return safe

func _chess_gen_moves(from: Vector2i) -> Array:
	if not _chess_in(from):
		return []
	var piece: int = int(chess_board[from.y][from.x])
	if piece == 0:
		return []
	var col: int = _chess_color(piece)
	var legal_moves: Array = []
	for to_value in _chess_pseudo_moves(from):
		var to: Vector2i = to_value
		if _chess_move_keeps_king_safe(from, to, col):
			legal_moves.append(to)
	return legal_moves

func _chess_move_keeps_king_safe(from: Vector2i, to: Vector2i, col: int) -> bool:
	var snapshot: Dictionary = _chess_apply_move_core(from, to, 5, false)
	if snapshot.is_empty():
		return false
	var safe: bool = _chess_king_in_check(col).x < 0
	_chess_restore_simulation(snapshot)
	return safe

func _chess_all_moves(col: int) -> Array:
	var result: Array = []
	for y in range(8):
		for x in range(8):
			var from := Vector2i(x, y)
			if _chess_color(int(chess_board[y][x])) != col:
				continue
			for to_value in _chess_gen_moves(from):
				var to: Vector2i = to_value
				if _chess_is_promotion_move(from, to):
					# Search all legal promotion choices separately. The UI also offers
					# underpromotions, so the AI must evaluate the same move space.
					for promotion_type in [5, 4, 3, 2]:
						result.append([from, to, promotion_type])
				else:
					result.append([from, to])
	return result

func _chess_apply_move_core(from: Vector2i, to: Vector2i, promotion_type: int = 5, full_snapshot: bool = true) -> Dictionary:
	if not _chess_in(from) or not _chess_in(to):
		return {}
	var moving: int = int(chess_board[from.y][from.x])
	if moving == 0:
		return {}
	var target: int = int(chess_board[to.y][to.x])
	if _chess_type(target) == 6:
		return {} # Kings are checked/mated, never captured.
	var is_ep: bool = _chess_type(moving) == 1 and to == chess_en_passant and target == 0 and from.x != to.x
	var ep_capture_square := Vector2i(-1, -1)
	var ep_captured_piece: int = 0
	if is_ep:
		ep_capture_square = Vector2i(to.x, from.y)
		ep_captured_piece = int(chess_board[ep_capture_square.y][ep_capture_square.x])
	var rook_from := Vector2i(-1, -1)
	var rook_to := Vector2i(-1, -1)
	var rook_piece: int = 0
	if _chess_type(moving) == 6 and absi(to.x - from.x) == 2:
		var home_y: int = from.y
		if to.x == 6:
			rook_from = Vector2i(7, home_y)
			rook_to = Vector2i(5, home_y)
		else:
			rook_from = Vector2i(0, home_y)
			rook_to = Vector2i(3, home_y)
		rook_piece = int(chess_board[rook_from.y][rook_from.x])
	var snapshot: Dictionary = {
		"from": from, "to": to, "moving": moving, "captured": target,
		"ep_capture_square": ep_capture_square, "ep_captured_piece": ep_captured_piece,
		"rook_from": rook_from, "rook_to": rook_to, "rook_piece": rook_piece,
		"prior_turn": chess_turn, "prior_castling": chess_castling_rights,
		"prior_ep": chess_en_passant, "prior_halfmove": chess_halfmove_clock,
		"prior_fullmove": chess_fullmove_number, "prior_last": chess_last.duplicate(true)
	}
	if full_snapshot:
		snapshot["prior_game_over"] = chess_game_over
		snapshot["prior_winner"] = chess_winner
		snapshot["prior_terminal_reason"] = chess_terminal_reason
		snapshot["prior_last_notation"] = chess_last_notation
		snapshot["prior_position_history_size"] = chess_position_history.size()
		snapshot["prior_move_log_size"] = chess_move_log.size()
	var mover_color: int = _chess_color(moving)
	chess_board[from.y][from.x] = 0
	if is_ep:
		chess_board[ep_capture_square.y][ep_capture_square.x] = 0
	var placed: int = moving
	if _chess_type(moving) == 1 and (to.y == 0 or to.y == 7):
		var safe_promotion: int = promotion_type if promotion_type in [2, 3, 4, 5] else 5
		placed = safe_promotion if mover_color == 1 else safe_promotion + 6
	chess_board[to.y][to.x] = placed
	if rook_from.x >= 0:
		chess_board[rook_to.y][rook_to.x] = rook_piece
		chess_board[rook_from.y][rook_from.x] = 0
	# Once the king or a home rook moves, its castling right is permanently lost.
	var rights: int = chess_castling_rights
	if moving == 6:
		rights = rights & ~(CASTLE_WHITE_KING | CASTLE_WHITE_QUEEN)
	elif moving == 12:
		rights = rights & ~(CASTLE_BLACK_KING | CASTLE_BLACK_QUEEN)
	if moving == 4 and from == Vector2i(7, 7): rights = rights & ~CASTLE_WHITE_KING
	if moving == 4 and from == Vector2i(0, 7): rights = rights & ~CASTLE_WHITE_QUEEN
	if moving == 10 and from == Vector2i(7, 0): rights = rights & ~CASTLE_BLACK_KING
	if moving == 10 and from == Vector2i(0, 0): rights = rights & ~CASTLE_BLACK_QUEEN
	if target == 4 and to == Vector2i(7, 7): rights = rights & ~CASTLE_WHITE_KING
	if target == 4 and to == Vector2i(0, 7): rights = rights & ~CASTLE_WHITE_QUEEN
	if target == 10 and to == Vector2i(7, 0): rights = rights & ~CASTLE_BLACK_KING
	if target == 10 and to == Vector2i(0, 0): rights = rights & ~CASTLE_BLACK_QUEEN
	chess_castling_rights = rights
	chess_en_passant = Vector2i(-1, -1)
	if _chess_type(moving) == 1 and absi(to.y - from.y) == 2:
		chess_en_passant = Vector2i(from.x, int((from.y + to.y) / 2))
	if _chess_type(moving) == 1 or target != 0 or is_ep:
		chess_halfmove_clock = 0
	else:
		chess_halfmove_clock += 1
	if mover_color == 2:
		chess_fullmove_number += 1
	chess_last = [from, to]
	chess_turn = 3 - mover_color
	return snapshot

func _chess_restore_simulation(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	var from: Vector2i = snapshot["from"]
	var to: Vector2i = snapshot["to"]
	chess_board[from.y][from.x] = int(snapshot["moving"])
	chess_board[to.y][to.x] = int(snapshot["captured"])
	var ep_square: Vector2i = snapshot["ep_capture_square"]
	if ep_square.x >= 0:
		chess_board[ep_square.y][ep_square.x] = int(snapshot["ep_captured_piece"])
	var rook_from: Vector2i = snapshot["rook_from"]
	var rook_to: Vector2i = snapshot["rook_to"]
	if rook_from.x >= 0:
		chess_board[rook_from.y][rook_from.x] = int(snapshot["rook_piece"])
		chess_board[rook_to.y][rook_to.x] = 0
	chess_turn = int(snapshot["prior_turn"])
	chess_castling_rights = int(snapshot["prior_castling"])
	chess_en_passant = snapshot["prior_ep"]
	chess_halfmove_clock = int(snapshot["prior_halfmove"])
	chess_fullmove_number = int(snapshot["prior_fullmove"])
	chess_last = snapshot["prior_last"].duplicate(true)
	if snapshot.has("prior_game_over"):
		chess_game_over = bool(snapshot["prior_game_over"])
		chess_winner = int(snapshot["prior_winner"])
		chess_terminal_reason = str(snapshot["prior_terminal_reason"])
		chess_last_notation = str(snapshot["prior_last_notation"])
		chess_position_history.resize(int(snapshot["prior_position_history_size"]))
		chess_move_log.resize(int(snapshot["prior_move_log_size"]))

func _chess_simulate_move(from: Vector2i, to: Vector2i, promotion_type: int = 5) -> Dictionary:
	return _chess_apply_move_core(from, to, promotion_type, false)

func _chess_make_move(from: Vector2i, to: Vector2i, promotion_type: int = 5) -> void:
	if chess_game_over or not _chess_in(from) or not _chess_in(to):
		return
	var moving: int = int(chess_board[from.y][from.x])
	if moving == 0 or _chess_color(moving) != chess_turn:
		return
	if not _chess_gen_moves(from).has(to):
		return
	if _chess_type(moving) == 1 and (to.y == 0 or to.y == 7):
		if promotion_type not in [2, 3, 4, 5]:
			promotion_type = 5
	else:
		promotion_type = 5
	var notation: String = _chess_move_notation(from, to, promotion_type)
	var snapshot: Dictionary = _chess_apply_move_core(from, to, promotion_type)
	if snapshot.is_empty():
		return
	chess_history.append(snapshot)
	chess_selected = Vector2i(-1, -1)
	chess_valid = []
	chess_move_log.append(notation)
	chess_last_notation = notation
	chess_position_history.append(_chess_position_key())
	chess_promotion_pending = {}
	chess_terminal_reason = ""
	_chess_update_terminal_state()
	if chess_game_over:
		app._go_result(false)
	if app != null:
		app._rebuild_buttons()
		app.queue_redraw()

func _chess_move_notation(from: Vector2i, to: Vector2i, promotion_type: int) -> String:
	if int(chess_board[from.y][from.x]) in [6, 12] and absi(to.x - from.x) == 2:
		return "O-O" if to.x == 6 else "O-O-O"
	var source_piece: int = int(chess_board[from.y][from.x])
	var target_piece: int = int(chess_board[to.y][to.x])
	var capture: bool = target_piece != 0 or ( _chess_type(source_piece) == 1 and to == chess_en_passant and from.x != to.x )
	var text: String = _chess_square_name(from) + ("x" if capture else "-") + _chess_square_name(to)
	if _chess_type(source_piece) == 1 and (to.y == 0 or to.y == 7):
		text += "=" + ["", "", "N", "B", "R", "Q"][promotion_type]
	var move_snapshot: Dictionary = _chess_simulate_move(from, to, promotion_type)
	if not move_snapshot.is_empty():
		var defending_side: int = chess_turn
		var opponent_moves: Array = _chess_all_moves(defending_side)
		if _chess_king_in_check(defending_side).x >= 0:
			text += "#" if opponent_moves.is_empty() else "+"
		_chess_restore_simulation(move_snapshot)
	return text

func _chess_square_name(square: Vector2i) -> String:
	return "abcdefgh"[square.x] + str(8 - square.y)

func _chess_update_terminal_state() -> void:
	chess_game_over = false
	chess_winner = 0
	chess_terminal_reason = ""
	var legal_moves: Array = _chess_all_moves(chess_turn)
	if legal_moves.is_empty():
		if _chess_king_in_check(chess_turn).x >= 0:
			chess_game_over = true
			chess_winner = 3 - chess_turn
			chess_terminal_reason = "کیش‌ومات؛ " + ("سفید" if chess_winner == 1 else "سیاه") + " برنده شد."
		else:
			chess_game_over = true
			chess_winner = 0
			chess_terminal_reason = "پات؛ بازی مساوی شد."
	elif _chess_insufficient_material():
		chess_game_over = true
		chess_winner = 0
		chess_terminal_reason = "مساوی؛ مهره کافی برای مات وجود ندارد."
	elif chess_halfmove_clock >= 150:
		chess_game_over = true
		chess_winner = 0
		chess_terminal_reason = "مساوی؛ قانون ۷۵ حرکت."
	elif _chess_repetition_count(_chess_position_key()) >= 5:
		chess_game_over = true
		chess_winner = 0
		chess_terminal_reason = "مساوی؛ تکرار پنج‌باره موقعیت."

func _chess_insufficient_material() -> bool:
	var material: Array = []
	var bishop_colors: Array[int] = []
	for y in range(8):
		for x in range(8):
			var piece: int = int(chess_board[y][x])
			var typ: int = _chess_type(piece)
			if piece == 0 or typ == 6:
				continue
			material.append(typ)
			if typ == 3:
				bishop_colors.append((x + y) % 2)
	if material.is_empty():
		return true
	if material.size() == 1 and int(material[0]) in [2, 3]:
		return true
	if material.size() == bishop_colors.size():
		var first_color: int = int(bishop_colors[0])
		for square_color in bishop_colors:
			if int(square_color) != first_color:
				return false
		return true
	return false

func _chess_position_key() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for y in range(8):
		for x in range(8):
			parts.append(str(int(chess_board[y][x])))
	var ep_text: String = "-"
	if _chess_in(chess_en_passant):
		# En-passant matters for repetition only when a legal en-passant capture exists.
		for dx in [-1, 1]:
			var from := Vector2i(chess_en_passant.x + dx, chess_en_passant.y + (1 if chess_turn == 1 else -1))
			if _chess_in(from) and _chess_type(int(chess_board[from.y][from.x])) == 1 and _chess_color(int(chess_board[from.y][from.x])) == chess_turn:
				if chess_en_passant in _chess_gen_moves(from):
					ep_text = _chess_square_name(chess_en_passant)
					break
	return ",".join(parts) + "|" + str(chess_turn) + "|" + str(chess_castling_rights) + "|" + ep_text

func _chess_repetition_count(key: String = "") -> int:
	var target_key: String = key if key != "" else _chess_position_key()
	var count: int = 0
	for previous in chess_position_history:
		if previous == target_key:
			count += 1
	return count

func _chess_draw_claim_available() -> bool:
	if chess_game_over:
		return false
	return chess_halfmove_clock >= 100 or _chess_repetition_count(_chess_position_key()) >= 3

func _chess_can_claim_draw() -> bool:
	# A human may only claim on their own turn. Do not expose the control while
	# the CPU is thinking or when an online match has no synchronized claim RPC.
	if app == null or app._net_on() or not _chess_my_turn():
		return false
	return _chess_draw_claim_available()

func _chess_claim_draw(cpu_claim: bool = false) -> void:
	if cpu_claim:
		if app == null or not app.vs_cpu or chess_turn != 2 or not _chess_draw_claim_available():
			return
	elif not _chess_can_claim_draw():
		return
	chess_game_over = true
	chess_winner = 0
	chess_terminal_reason = "مساوی اعلام شد؛ قانون ۵۰ حرکت یا تکرار سه‌باره."
	app._go_result(false)

func _btns_chess() -> void:
	if not chess_promotion_pending.is_empty():
		var labels: Array[String] = ["ملکه", "رخ", "فیل", "اسب"]
		var piece_types: Array[int] = [5, 4, 3, 2]
		for i in range(piece_types.size()):
			var rect := Rect2(15.0 + float(i) * 128.0, 812.0, 120.0, 48.0)
			app._add_btn(rect, labels[i], _chess_choose_promotion.bind(piece_types[i]), true, app.ACCENT, "soft", "", "chess_promote_%d" % piece_types[i])
		return
	app._add_btn(Rect2(32.0, 812.0, 154.0, 48.0), "برگشت حرکت", _chess_undo, _chess_can_undo(), app.TEXT_DIM, "ghost", "undo", "chess_undo")
	if _chess_can_claim_draw():
		app._add_btn(Rect2(198.0, 812.0, 170.0, 48.0), "ادعای مساوی", _chess_claim_draw, true, app.ACCENT, "soft", "scale", "chess_claim_draw")

func _chess_can_undo() -> bool:
	if app == null or chess_game_over or chess_history.is_empty() or not chess_promotion_pending.is_empty():
		return false
	return not app._net_on()

func _chess_undo_one() -> bool:
	if chess_history.is_empty():
		return false
	var snapshot: Dictionary = chess_history.pop_back()
	_chess_restore_simulation(snapshot)
	chess_promotion_pending = {}
	return true

func _chess_undo() -> void:
	if not _chess_can_undo():
		return
	# Against CPU, rewind to the human's previous turn; local two-player rewinds one ply.
	while not chess_history.is_empty():
		if not _chess_undo_one():
			break
		if not app.vs_cpu or chess_turn == 1:
			break
	chess_selected = Vector2i(-1, -1)
	chess_valid = []
	app._rebuild_buttons()
	app.queue_redraw()

func _chess_is_promotion_move(from: Vector2i, to: Vector2i) -> bool:
	if not _chess_in(from) or not _chess_in(to):
		return false
	var piece: int = int(chess_board[from.y][from.x])
	return (piece == 1 and to.y == 0) or (piece == 7 and to.y == 7)

func _chess_choose_promotion(promotion_type: int) -> void:
	if chess_promotion_pending.is_empty() or chess_game_over:
		return
	if promotion_type not in [2, 3, 4, 5]:
		promotion_type = 5
	var from: Vector2i = chess_promotion_pending["from"]
	var to: Vector2i = chess_promotion_pending["to"]
	chess_promotion_pending = {}
	if app._net_on():
		app._send_game_action("_rpc_chess_move", [from.x, from.y, to.x, to.y, promotion_type])
	else:
		_chess_make_move(from, to, promotion_type)
	app._rebuild_buttons()
	app.queue_redraw()

func _chess_cpu_move() -> void:
	if chess_game_over or chess_turn != 2:
		return
	var ai = ChessAIScript.new()
	var best: Array = ai.choose_move(self, chess_difficulty)
	if ai.should_claim_draw:
		_chess_claim_draw(true)
		return
	if best.is_empty():
		_chess_update_terminal_state()
		if chess_game_over:
			app._go_result(false)
		return
	var promotion_type: int = int(best[2]) if best.size() >= 3 else 5
	_chess_make_move(best[0], best[1], promotion_type)

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
	if chess_game_over or not _chess_my_turn() or not chess_promotion_pending.is_empty():
		return
	var c: Vector2i = _presentation.screen_to_board_cell(app, p)
	if not _chess_in(c):
		return
	if chess_selected.x >= 0:
		if c in chess_valid:
			if _chess_is_promotion_move(chess_selected, c):
				chess_promotion_pending = {"from": chess_selected, "to": c}
				chess_selected = Vector2i(-1, -1)
				chess_valid = []
				app._rebuild_buttons()
				app.queue_redraw()
				return
			if app._net_on():
				app._send_game_action("_rpc_chess_move", [chess_selected.x, chess_selected.y, c.x, c.y])
			else:
				_chess_make_move(chess_selected, c)
			return
		chess_selected = Vector2i(-1, -1)
		chess_valid = []
	if _chess_color(int(chess_board[c.y][c.x])) == chess_turn:
		chess_selected = c
		chess_valid = _chess_gen_moves(c)
		app.queue_redraw()

func _draw_chess() -> void:
	_presentation.render(app, self)
