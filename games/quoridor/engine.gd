extends RefCounted
## Quoridor search core for the two-player CPU.
##
## The old CPU walked the live rules object (Dictionary walls keyed by formatted strings,
## Vector2i queues) which made one shortest-path query cost hundreds of microseconds and
## starved the search. This engine keeps its own flat packed-array board, so a full
## goal-distance field costs ~40 microseconds, and it layers the following on top:
##   * make/unmake with Zobrist hashing and a transposition table
##   * principal-variation alpha-beta with iterative deepening and a hard time/node budget
##   * exact "does this wall cut every shortest path?" tests from shortest-path counts, so
##     only walls that really lengthen the opponent's route are ever searched
##   * a threat extension so a pawn one step from the goal is never mis-evaluated
##
## Cell index c = y * 9 + x. Player 0 starts on row 0 and wins on row 8; player 1 starts on
## row 8 and wins on row 0. Move codes: 0..80 pawn destination, 100..163 horizontal wall
## at anchor (y * 8 + x), 164..227 vertical wall at that anchor. Wall geometry is identical
## to rules.gd (a wall covers two edges; "h" blocks vertical travel, "v" horizontal).

const CELLS: int = 81
const FAR: int = 99
const WIN: int = 100000
const WIN_BOUND: int = 99000
const NEG_INF: int = -1000000
const MAX_PLY: int = 40
const TT_SIZE: int = 131072
const TT_MASK: int = 131071
const SCORE_OFFSET: int = 1048576
const WALL_BASE: int = 100
const VWALL_BASE: int = 164
const NO_MOVE: int = -1
const MOVE_CAP: int = 200

# ---- evaluation weights (100 points = one pawn step) ----
var w_tempo: int = 50      # side to move wins an exact race, so it is worth half a step
var w_wall: int = 30       # value of one spare wall compared with the opponent's spares
var w_flex: int = 5        # more distinct shortest routes = harder to trap (capped at 4)
var w_threat: int = 0      # bonus per step of distance when the opponent has a single lane

# ---- per-search configuration (set through think()) ----
var wall_limit_by_depth: PackedInt32Array = PackedInt32Array([0, 3, 5, 6, 7, 8, 8, 8, 8, 8, 8, 8, 8])
var exact_order_depth: int = 3

# ---- board ----
var mvU: PackedByteArray = PackedByteArray()
var mvD: PackedByteArray = PackedByteArray()
var mvL: PackedByteArray = PackedByteArray()
var mvR: PackedByteArray = PackedByteArray()
var hw: PackedByteArray = PackedByteArray()
var vw: PackedByteArray = PackedByteArray()
var pawn: PackedInt32Array = PackedInt32Array()
var wleft: PackedInt32Array = PackedInt32Array()
var stm: int = 0
var hash: int = 0

# ---- scratch / pools ----
var _q: PackedInt32Array = PackedInt32Array()
var _q2: PackedInt32Array = PackedInt32Array()
var _fwd: PackedInt32Array = PackedInt32Array()
var _fwd2: PackedInt32Array = PackedInt32Array()
var _tf: PackedInt32Array = PackedInt32Array()
var _tc: PackedInt32Array = PackedInt32Array()
var _acc_o: PackedInt32Array = PackedInt32Array()
var _acc_m: PackedInt32Array = PackedInt32Array()
var _list_o: PackedInt32Array = PackedInt32Array()
var _list_m: PackedInt32Array = PackedInt32Array()
var _cell_x: PackedInt32Array = PackedInt32Array()
var _cell_y: PackedInt32Array = PackedInt32Array()
var _pf0: Array = []
var _pf1: Array = []
var _pc0: Array = []
var _pc1: Array = []
var _mv_code: Array = []
var _mv_ord: Array = []
var _u_from: PackedInt32Array = PackedInt32Array()
var _u_hash: PackedInt64Array = PackedInt64Array()

# ---- hashing / transposition table ----
var z_pawn: PackedInt64Array = PackedInt64Array()
var z_hw: PackedInt64Array = PackedInt64Array()
var z_vw: PackedInt64Array = PackedInt64Array()
var z_wl: PackedInt64Array = PackedInt64Array()
var z_stm: int = 0
var tt_key: PackedInt64Array = PackedInt64Array()
var tt_dat: PackedInt64Array = PackedInt64Array()

# ---- search state ----
var _nodes: int = 0
var _node_limit: int = 0
var _deadline: int = 0
var _aborted: bool = false
var _win_cell: int = -1
var _iter_code: int = -1
var _iter_score: int = 0
var _root_n: int = 0
var _root_code: PackedInt32Array = PackedInt32Array()
var _root_score: PackedInt32Array = PackedInt32Array()
var _root_bias: PackedInt32Array = PackedInt32Array()
var last_depth: int = 0
var last_nodes: int = 0
var last_score: int = 0

func _init() -> void:
	mvU.resize(CELLS)
	mvD.resize(CELLS)
	mvL.resize(CELLS)
	mvR.resize(CELLS)
	hw.resize(64)
	vw.resize(64)
	pawn.resize(2)
	wleft.resize(2)
	_q.resize(96)
	_q2.resize(96)
	_fwd.resize(CELLS)
	_fwd2.resize(CELLS)
	_tf.resize(CELLS)
	_tc.resize(CELLS)
	_acc_o.resize(128)
	_acc_m.resize(128)
	_list_o.resize(128)
	_list_m.resize(128)
	_cell_x.resize(CELLS)
	_cell_y.resize(CELLS)
	for y in range(9):
		for x in range(9):
			_cell_x[y * 9 + x] = x
			_cell_y[y * 9 + x] = y
	for ply in range(MAX_PLY + 3):
		var a0: PackedInt32Array = PackedInt32Array()
		a0.resize(CELLS)
		var a1: PackedInt32Array = PackedInt32Array()
		a1.resize(CELLS)
		var b0: PackedInt32Array = PackedInt32Array()
		b0.resize(CELLS)
		var b1: PackedInt32Array = PackedInt32Array()
		b1.resize(CELLS)
		_pf0.append(a0)
		_pf1.append(a1)
		_pc0.append(b0)
		_pc1.append(b1)
		var codes: PackedInt32Array = PackedInt32Array()
		codes.resize(MOVE_CAP)
		var ords: PackedInt32Array = PackedInt32Array()
		ords.resize(MOVE_CAP)
		_mv_code.append(codes)
		_mv_ord.append(ords)
	_u_from.resize(MAX_PLY + 3)
	_u_hash.resize(MAX_PLY + 3)
	_root_code.resize(MOVE_CAP)
	_root_score.resize(MOVE_CAP)
	_root_bias.resize(MOVE_CAP)
	tt_key.resize(TT_SIZE)
	tt_dat.resize(TT_SIZE)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7919331
	z_pawn.resize(2 * CELLS)
	for i in range(2 * CELLS):
		z_pawn[i] = _rand64(rng)
	z_hw.resize(64)
	z_vw.resize(64)
	for i in range(64):
		z_hw[i] = _rand64(rng)
		z_vw[i] = _rand64(rng)
	z_wl.resize(2 * 12)
	for i in range(2 * 12):
		z_wl[i] = _rand64(rng)
	z_stm = _rand64(rng)
	_reset_board()

func _rand64(rng: RandomNumberGenerator) -> int:
	return (int(rng.randi()) << 32) ^ int(rng.randi())

# ------------------------------------------------------------------------------------
# Board set-up
# ------------------------------------------------------------------------------------

func _reset_board() -> void:
	for y in range(9):
		for x in range(9):
			var c: int = y * 9 + x
			mvU[c] = 1 if y > 0 else 0
			mvD[c] = 1 if y < 8 else 0
			mvL[c] = 1 if x > 0 else 0
			mvR[c] = 1 if x < 8 else 0
	hw.fill(0)
	vw.fill(0)

func _set_wall(vert: bool, a: int, on: bool) -> void:
	var c1: int = (a >> 3) * 9 + (a & 7)
	var v: int = 0 if on else 1
	if vert:
		vw[a] = 1 if on else 0
		var c2: int = c1 + 9
		mvR[c1] = v
		mvL[c1 + 1] = v
		mvR[c2] = v
		mvL[c2 + 1] = v
	else:
		hw[a] = 1 if on else 0
		mvD[c1] = v
		mvU[c1 + 9] = v
		mvD[c1 + 1] = v
		mvU[c1 + 10] = v

func _wall_geometry_ok(vert: bool, a: int) -> bool:
	var x: int = a & 7
	var y: int = a >> 3
	if vert:
		if vw[a] == 1 or hw[a] == 1:
			return false
		if y > 0 and vw[a - 8] == 1:
			return false
		if y < 7 and vw[a + 8] == 1:
			return false
	else:
		if hw[a] == 1 or vw[a] == 1:
			return false
		if x > 0 and hw[a - 1] == 1:
			return false
		if x < 7 and hw[a + 1] == 1:
			return false
	return true

## Copies the live game into the engine. `to_move` is the seat that will act.
func load_position(game, to_move: int) -> void:
	_reset_board()
	var p0: Vector2i = game.quo_pawns[0]
	var p1: Vector2i = game.quo_pawns[1]
	pawn[0] = p0.y * 9 + p0.x
	pawn[1] = p1.y * 9 + p1.x
	wleft[0] = int(game.quo_walls_left[0])
	wleft[1] = int(game.quo_walls_left[1])
	for key in game.quo_walls.keys():
		var s: String = str(key)
		var parts: PackedStringArray = s.substr(1).split(",")
		if parts.size() != 2:
			continue
		var a: int = int(parts[1]) * 8 + int(parts[0])
		_set_wall(s.begins_with("v"), a, true)
	stm = to_move
	_recompute_hash()

func _recompute_hash() -> void:
	var h: int = 0
	h ^= z_pawn[pawn[0]]
	h ^= z_pawn[CELLS + pawn[1]]
	for a in range(64):
		if hw[a] == 1:
			h ^= z_hw[a]
		if vw[a] == 1:
			h ^= z_vw[a]
	h ^= z_wl[mini(wleft[0], 11)]
	h ^= z_wl[12 + mini(wleft[1], 11)]
	if stm == 1:
		h ^= z_stm
	hash = h

# ------------------------------------------------------------------------------------
# Distance fields
# ------------------------------------------------------------------------------------

## Fills fld[c] with the wall-aware distance from c to `player`'s goal row (FAR if sealed
## off) and cnt[c] with the number of distinct shortest routes. Pawns are ignored.
func _bfs(player: int, fld: PackedInt32Array, cnt: PackedInt32Array) -> void:
	fld.fill(FAR)
	var tail: int = 0
	var base: int = 72 if player == 0 else 0
	for i in range(9):
		fld[base + i] = 0
		cnt[base + i] = 1
		_q[tail] = base + i
		tail += 1
	var head: int = 0
	while head < tail:
		var c: int = _q[head]
		head += 1
		var d: int = fld[c] + 1
		var w: int = cnt[c]
		if mvU[c] == 1:
			var n: int = c - 9
			var fn: int = fld[n]
			if fn == FAR:
				fld[n] = d
				cnt[n] = w
				_q[tail] = n
				tail += 1
			elif fn == d:
				cnt[n] += w
		if mvD[c] == 1:
			var n: int = c + 9
			var fn: int = fld[n]
			if fn == FAR:
				fld[n] = d
				cnt[n] = w
				_q[tail] = n
				tail += 1
			elif fn == d:
				cnt[n] += w
		if mvL[c] == 1:
			var n: int = c - 1
			var fn: int = fld[n]
			if fn == FAR:
				fld[n] = d
				cnt[n] = w
				_q[tail] = n
				tail += 1
			elif fn == d:
				cnt[n] += w
		if mvR[c] == 1:
			var n: int = c + 1
			var fn: int = fld[n]
			if fn == FAR:
				fld[n] = d
				cnt[n] = w
				_q[tail] = n
				tail += 1
			elif fn == d:
				cnt[n] += w

## fwd[c] = number of shortest routes from `start` that pass through cell c (0 elsewhere).
func _dag_forward(start: int, f: PackedInt32Array, fwd: PackedInt32Array) -> int:
	fwd.fill(0)
	fwd[start] = 1
	_q2[0] = start
	var head: int = 0
	var tail: int = 1
	while head < tail:
		var c: int = _q2[head]
		head += 1
		var d: int = f[c] - 1
		if d < 0:
			continue
		var w: int = fwd[c]
		if mvU[c] == 1 and f[c - 9] == d:
			var n: int = c - 9
			if fwd[n] == 0:
				_q2[tail] = n
				tail += 1
			fwd[n] += w
		if mvD[c] == 1 and f[c + 9] == d:
			var n: int = c + 9
			if fwd[n] == 0:
				_q2[tail] = n
				tail += 1
			fwd[n] += w
		if mvL[c] == 1 and f[c - 1] == d:
			var n: int = c - 1
			if fwd[n] == 0:
				_q2[tail] = n
				tail += 1
			fwd[n] += w
		if mvR[c] == 1 and f[c + 1] == d:
			var n: int = c + 1
			if fwd[n] == 0:
				_q2[tail] = n
				tail += 1
			fwd[n] += w
	return tail

# ------------------------------------------------------------------------------------
# Move generation
# ------------------------------------------------------------------------------------

## Fills codes/ords with legal pawn destinations (standard jump / diagonal rules).
## Returns -1 when one of them reaches the goal (an immediate win).
func _gen_pawn(me: int, from: int, fm: PackedInt32Array, codes: PackedInt32Array, ords: PackedInt32Array) -> int:
	var opp: int = pawn[1 - me]
	var n: int = 0
	var here: int = fm[from]
	for dir in range(4):
		var ok: bool = false
		var step: int = 0
		match dir:
			0:
				ok = mvU[from] == 1
				step = -9
			1:
				ok = mvD[from] == 1
				step = 9
			2:
				ok = mvL[from] == 1
				step = -1
			_:
				ok = mvR[from] == 1
				step = 1
		if not ok:
			continue
		var adj: int = from + step
		if adj != opp:
			if fm[adj] == 0:
				_win_cell = adj
				return -1
			codes[n] = adj
			ords[n] = (here - fm[adj]) * 100 - absi(_cell_x[adj] - 4)
			n += 1
			continue
		# Opponent adjacent: straight jump when possible, otherwise the two diagonals.
		var straight: bool = false
		match dir:
			0:
				straight = mvU[adj] == 1
			1:
				straight = mvD[adj] == 1
			2:
				straight = mvL[adj] == 1
			_:
				straight = mvR[adj] == 1
		if straight:
			var jump: int = adj + step
			if fm[jump] == 0:
				_win_cell = jump
				return -1
			codes[n] = jump
			ords[n] = (here - fm[jump]) * 100 - absi(_cell_x[jump] - 4)
			n += 1
			continue
		if dir < 2:
			if mvL[adj] == 1:
				var t1: int = adj - 1
				if fm[t1] == 0:
					_win_cell = t1
					return -1
				codes[n] = t1
				ords[n] = (here - fm[t1]) * 100 - absi(_cell_x[t1] - 4)
				n += 1
			if mvR[adj] == 1:
				var t2: int = adj + 1
				if fm[t2] == 0:
					_win_cell = t2
					return -1
				codes[n] = t2
				ords[n] = (here - fm[t2]) * 100 - absi(_cell_x[t2] - 4)
				n += 1
		else:
			if mvU[adj] == 1:
				var t3: int = adj - 9
				if fm[t3] == 0:
					_win_cell = t3
					return -1
				codes[n] = t3
				ords[n] = (here - fm[t3]) * 100 - absi(_cell_x[t3] - 4)
				n += 1
			if mvD[adj] == 1:
				var t4: int = adj + 9
				if fm[t4] == 0:
					_win_cell = t4
					return -1
				codes[n] = t4
				ords[n] = (here - fm[t4]) * 100 - absi(_cell_x[t4] - 4)
				n += 1
	return n

## For the shortest-route DAG of the pawn on `start`, accumulates in acc[] (index = vertical *
## 64 + anchor) how many shortest routes cross the edges each candidate wall would block.
## A wall lengthens that pawn's route exactly when acc >= cnt[start]. Returns the number of
## touched candidates, listed in `list`.
func _accumulate(start: int, f: PackedInt32Array, cnt: PackedInt32Array, fwd: PackedInt32Array, acc: PackedInt32Array, list: PackedInt32Array) -> int:
	var dag_n: int = _dag_forward(start, f, fwd)
	acc.fill(0)
	var touched: int = 0
	for i in range(dag_n):
		var c: int = _q2[i]
		var d: int = f[c] - 1
		if d < 0:
			continue
		var w: int = fwd[c]
		var x: int = _cell_x[c]
		var y: int = _cell_y[c]
		if mvU[c] == 1 and f[c - 9] == d:
			var through: int = w * cnt[c - 9]
			var base: int = (y - 1) * 8
			if x <= 7:
				if acc[base + x] == 0:
					list[touched] = base + x
					touched += 1
				acc[base + x] += through
			if x >= 1:
				if acc[base + x - 1] == 0:
					list[touched] = base + x - 1
					touched += 1
				acc[base + x - 1] += through
		if mvD[c] == 1 and f[c + 9] == d:
			var through2: int = w * cnt[c + 9]
			var base2: int = y * 8
			if x <= 7:
				if acc[base2 + x] == 0:
					list[touched] = base2 + x
					touched += 1
				acc[base2 + x] += through2
			if x >= 1:
				if acc[base2 + x - 1] == 0:
					list[touched] = base2 + x - 1
					touched += 1
				acc[base2 + x - 1] += through2
		if mvL[c] == 1 and f[c - 1] == d:
			var through3: int = w * cnt[c - 1]
			if y <= 7:
				var i3: int = 64 + y * 8 + x - 1
				if acc[i3] == 0:
					list[touched] = i3
					touched += 1
				acc[i3] += through3
			if y >= 1:
				var i4: int = 64 + (y - 1) * 8 + x - 1
				if acc[i4] == 0:
					list[touched] = i4
					touched += 1
				acc[i4] += through3
		if mvR[c] == 1 and f[c + 1] == d:
			var through4: int = w * cnt[c + 1]
			if y <= 7:
				var i5: int = 64 + y * 8 + x
				if acc[i5] == 0:
					list[touched] = i5
					touched += 1
				acc[i5] += through4
			if y >= 1:
				var i6: int = 64 + (y - 1) * 8 + x
				if acc[i6] == 0:
					list[touched] = i6
					touched += 1
				acc[i6] += through4
	return touched

## Appends the walls that cut every shortest route of the opponent (the only walls that can
## lengthen it right now), best first and capped at `limit`. A cheap proxy orders them; with
## `exact` the most promising ones are re-ranked by their real distance gain (one BFS each).
func _gen_walls(me: int, fo: PackedInt32Array, co: PackedInt32Array, fm: PackedInt32Array, cm: PackedInt32Array, codes: PackedInt32Array, ords: PackedInt32Array, n0: int, exact: bool, limit: int) -> int:
	var op: int = 1 - me
	var op_pawn: int = pawn[op]
	var me_pawn: int = pawn[me]
	var total_o: int = co[op_pawn]
	var total_m: int = cm[me_pawn]
	var base_o: int = fo[op_pawn]
	var base_m: int = fm[me_pawn]
	var touched_o: int = _accumulate(op_pawn, fo, co, _fwd, _acc_o, _list_o)
	_accumulate(me_pawn, fm, cm, _fwd2, _acc_m, _list_m)
	var n: int = n0
	for t in range(touched_o):
		var idx: int = _list_o[t]
		if _acc_o[idx] < total_o:
			continue
		var vert: bool = idx >= 64
		var a: int = idx - 64 if vert else idx
		if not _wall_geometry_ok(vert, a):
			continue
		var ord: int = 100
		if _acc_m[idx] >= total_m:
			ord -= 150
		var x: int = a & 7
		var y: int = a >> 3
		if vert:
			if y == 0 or y == 7:
				ord += 40
			if y >= 2 and vw[a - 16] == 1:
				ord += 40
			if y <= 5 and vw[a + 16] == 1:
				ord += 40
		else:
			if x == 0 or x == 7:
				ord += 40
			if x >= 2 and hw[a - 2] == 1:
				ord += 40
			if x <= 5 and hw[a + 2] == 1:
				ord += 40
		codes[n] = (VWALL_BASE + a) if vert else (WALL_BASE + a)
		ords[n] = ord
		n += 1
	# Sort the wall segment by the proxy score, best first.
	for i in range(n0 + 1, n):
		var kc: int = codes[i]
		var ko: int = ords[i]
		var j: int = i - 1
		while j >= n0 and ords[j] < ko:
			codes[j + 1] = codes[j]
			ords[j + 1] = ords[j]
			j -= 1
		codes[j + 1] = kc
		ords[j + 1] = ko
	if exact and n > n0:
		# Re-rank the best proxy candidates by true distance gain. Illegal walls (that would
		# seal a pawn in) are dropped here for free.
		var m: int = mini(n - n0, limit * 2 + 2)
		var out: int = n0
		for i in range(n0, n0 + m):
			var code: int = codes[i]
			var vert2: bool = code >= VWALL_BASE
			var a2: int = code - (VWALL_BASE if vert2 else WALL_BASE)
			_set_wall(vert2, a2, true)
			_bfs(op, _tf, _tc)
			var new_o: int = _tf[op_pawn]
			var self_cost: int = 0
			var legal: bool = new_o < FAR
			if legal and _acc_m[(64 if vert2 else 0) + a2] >= total_m:
				_bfs(me, _tf, _tc)
				self_cost = _tf[me_pawn] - base_m
				legal = _tf[me_pawn] < FAR
			_set_wall(vert2, a2, false)
			if legal:
				codes[out] = code
				ords[out] = (new_o - base_o - self_cost) * 100 + (ords[i] if ords[i] > 0 else 0) % 100
				out += 1
		n = out
		for i in range(n0 + 1, n):
			var kc2: int = codes[i]
			var ko2: int = ords[i]
			var j2: int = i - 1
			while j2 >= n0 and ords[j2] < ko2:
				codes[j2 + 1] = codes[j2]
				ords[j2 + 1] = ords[j2]
				j2 -= 1
			codes[j2 + 1] = kc2
			ords[j2 + 1] = ko2
	if n - n0 > limit:
		n = n0 + limit
	return n

# ------------------------------------------------------------------------------------
# Make / unmake
# ------------------------------------------------------------------------------------

## Applies `code` for the side to move. A wall also refreshes both distance fields into the
## ply+1 pool. Returns false (state untouched) when the wall would seal a pawn in.
func _make(code: int, ply: int) -> bool:
	var me: int = stm
	_u_hash[ply] = hash
	if code < WALL_BASE:
		var from: int = pawn[me]
		_u_from[ply] = from
		hash ^= z_pawn[me * CELLS + from] ^ z_pawn[me * CELLS + code] ^ z_stm
		pawn[me] = code
	else:
		var vert: bool = code >= VWALL_BASE
		var a: int = code - (VWALL_BASE if vert else WALL_BASE)
		_set_wall(vert, a, true)
		var nf0: PackedInt32Array = _pf0[ply + 1]
		var nf1: PackedInt32Array = _pf1[ply + 1]
		_bfs(0, nf0, _pc0[ply + 1])
		_bfs(1, nf1, _pc1[ply + 1])
		if nf0[pawn[0]] >= FAR or nf1[pawn[1]] >= FAR:
			_set_wall(vert, a, false)
			return false
		var wl: int = wleft[me]
		hash ^= (z_vw[a] if vert else z_hw[a]) ^ z_wl[me * 12 + mini(wl, 11)] ^ z_wl[me * 12 + mini(wl - 1, 11)] ^ z_stm
		wleft[me] = wl - 1
	stm = 1 - me
	return true

func _unmake(code: int, ply: int) -> void:
	var me: int = 1 - stm
	stm = me
	if code < WALL_BASE:
		pawn[me] = _u_from[ply]
	else:
		var vert: bool = code >= VWALL_BASE
		var a: int = code - (VWALL_BASE if vert else WALL_BASE)
		_set_wall(vert, a, false)
		wleft[me] += 1
	hash = _u_hash[ply]

# ------------------------------------------------------------------------------------
# Evaluation
# ------------------------------------------------------------------------------------

func _eval(dm: int, d_o: int, cmp: int, cop: int, me: int, op: int) -> int:
	var wm: int = wleft[me]
	var wo: int = wleft[op]
	if wm == 0 and wo == 0:
		# Nobody can place another wall: the pure race is decided by distance and tempo.
		if dm <= d_o:
			return 20000 - dm * 10
		return -20000 + d_o * 10
	var s: int = (d_o - dm) * 100 + w_tempo
	s += (wm - wo) * w_wall
	s += w_flex * (mini(cmp, 4) - mini(cop, 4))
	return s

# ------------------------------------------------------------------------------------
# Search
# ------------------------------------------------------------------------------------

func _pvs(depth: int, alpha: int, beta: int, ply: int, first: bool, f0: PackedInt32Array, f1: PackedInt32Array, c0: PackedInt32Array, c1: PackedInt32Array) -> int:
	if first:
		return -_search(depth - 1, -beta, -alpha, ply + 1, f0, f1, c0, c1)
	var s: int = -_search(depth - 1, -alpha - 1, -alpha, ply + 1, f0, f1, c0, c1)
	if s > alpha and s < beta and not _aborted:
		s = -_search(depth - 1, -beta, -alpha, ply + 1, f0, f1, c0, c1)
	return s

func _search(depth: int, alpha: int, beta: int, ply: int, f0: PackedInt32Array, f1: PackedInt32Array, c0: PackedInt32Array, c1: PackedInt32Array) -> int:
	_nodes += 1
	if (_nodes & 127) == 0:
		if _nodes >= _node_limit or Time.get_ticks_usec() >= _deadline:
			_aborted = true
	if _aborted:
		return 0
	var me: int = stm
	var op: int = 1 - me
	var fm: PackedInt32Array = f0 if me == 0 else f1
	var fo: PackedInt32Array = f1 if me == 0 else f0
	var cm: PackedInt32Array = c0 if me == 0 else c1
	var co: PackedInt32Array = c1 if me == 0 else c0
	var codes: PackedInt32Array = _mv_code[ply]
	var ords: PackedInt32Array = _mv_ord[ply]
	var from: int = pawn[me]
	var n: int = _gen_pawn(me, from, fm, codes, ords)
	if n < 0:
		return WIN - ply
	var d_o: int = fo[pawn[op]]
	if depth <= 0:
		# Threat extension: if the opponent is one step from winning, the static score is
		# meaningless until we know whether a wall can parry it.
		if d_o <= 1 and wleft[me] > 0 and ply < MAX_PLY - 6:
			depth = 1
		else:
			return _eval(fm[from], d_o, cm[from], co[pawn[op]], me, op)
	if ply >= MAX_PLY - 2:
		return _eval(fm[from], d_o, cm[from], co[pawn[op]], me, op)

	var tt_move: int = NO_MOVE
	var h: int = hash
	var ti: int = h & TT_MASK
	if tt_key[ti] == h:
		var dat: int = tt_dat[ti]
		tt_move = (dat & 1023) - 1
		if ((dat >> 12) & 63) >= depth and ply > 0:
			var tflag: int = (dat >> 10) & 3
			var tscore: int = (dat >> 18) - SCORE_OFFSET
			if tscore > WIN_BOUND:
				tscore -= ply
			elif tscore < -WIN_BOUND:
				tscore += ply
			if tflag == 0:
				return tscore
			if tflag == 1 and tscore >= beta:
				return tscore
			if tflag == 2 and tscore <= alpha:
				return tscore

	if wleft[me] > 0:
		var limit: int = wall_limit_by_depth[mini(depth, wall_limit_by_depth.size() - 1)]
		if limit > 0:
			n = _gen_walls(me, fo, co, fm, cm, codes, ords, n, depth >= exact_order_depth, limit)
	if n == 0:
		return 0
	if tt_move != NO_MOVE:
		for i in range(n):
			if codes[i] == tt_move:
				ords[i] = 1000000
				break

	var best: int = NEG_INF
	var best_move: int = NO_MOVE
	var alpha0: int = alpha
	var first: bool = true
	for i in range(n):
		var bi: int = i
		var bo: int = ords[i]
		for j in range(i + 1, n):
			if ords[j] > bo:
				bo = ords[j]
				bi = j
		var code: int = codes[bi]
		if bi != i:
			codes[bi] = codes[i]
			ords[bi] = ords[i]
			codes[i] = code
			ords[i] = bo
		if not _make(code, ply):
			continue
		var score: int
		if code < WALL_BASE:
			score = _pvs(depth, alpha, beta, ply, first, f0, f1, c0, c1)
		else:
			score = _pvs(depth, alpha, beta, ply, first, _pf0[ply + 1], _pf1[ply + 1], _pc0[ply + 1], _pc1[ply + 1])
		_unmake(code, ply)
		if _aborted:
			return 0
		first = false
		if score > best:
			best = score
			best_move = code
			if score > alpha:
				alpha = score
				if alpha >= beta:
					break
	if best == NEG_INF:
		return 0
	var flag: int = 0
	if best <= alpha0:
		flag = 2
	elif best >= beta:
		flag = 1
	var stored: int = best
	if stored > WIN_BOUND:
		stored += ply
	elif stored < -WIN_BOUND:
		stored -= ply
	tt_key[ti] = h
	tt_dat[ti] = ((stored + SCORE_OFFSET) << 18) | (depth << 12) | (flag << 10) | (best_move + 1)
	return best

# ------------------------------------------------------------------------------------
# Root
# ------------------------------------------------------------------------------------

func _build_root(me: int, f0: PackedInt32Array, f1: PackedInt32Array, c0: PackedInt32Array, c1: PackedInt32Array, avoid: Array) -> bool:
	var fm: PackedInt32Array = f0 if me == 0 else f1
	var fo: PackedInt32Array = f1 if me == 0 else f0
	var cm: PackedInt32Array = c0 if me == 0 else c1
	var co: PackedInt32Array = c1 if me == 0 else c0
	var codes: PackedInt32Array = _mv_code[0]
	var ords: PackedInt32Array = _mv_ord[0]
	var n: int = _gen_pawn(me, pawn[me], fm, codes, ords)
	if n < 0:
		# A winning pawn move exists: make it the only root move.
		_root_n = 1
		_root_code[0] = _win_cell
		_root_score[0] = WIN
		_root_bias[0] = 0
		return true
	if wleft[me] > 0:
		n = _gen_walls(me, fo, co, fm, cm, codes, ords, n, true, 64)
	_root_n = n
	for i in range(n):
		_root_code[i] = codes[i]
		_root_score[i] = ords[i]
		_root_bias[i] = 0
		if codes[i] < WALL_BASE:
			var idx: int = avoid.find(Vector2i(_cell_x[codes[i]], _cell_y[codes[i]]))
			if idx >= 0:
				# The most recent revisit is penalised hardest to break A-B-A-B shuffles.
				_root_bias[i] = -40 if idx >= avoid.size() - 2 else -18
	return n > 0

## One iteration at the root. Returns false when the budget ran out mid-iteration; even then
## _iter_code/_iter_score hold the best move that was fully (or fail-high) proven so far.
func _root_iteration(depth: int, full_window: bool, f0: PackedInt32Array, f1: PackedInt32Array, c0: PackedInt32Array, c1: PackedInt32Array) -> bool:
	var alpha: int = NEG_INF
	var beta: int = -NEG_INF
	var first: bool = true
	var me: int = stm
	var saved_hash: int = hash
	_iter_code = NO_MOVE
	_iter_score = NEG_INF
	for i in range(_root_n):
		var code: int = _root_code[i]
		var bias: int = _root_bias[i]
		if not _make(code, 0):
			_root_score[i] = NEG_INF
			continue
		var nf0: PackedInt32Array = f0
		var nf1: PackedInt32Array = f1
		var nc0: PackedInt32Array = c0
		var nc1: PackedInt32Array = c1
		if code >= WALL_BASE:
			nf0 = _pf0[1]
			nf1 = _pf1[1]
			nc0 = _pc0[1]
			nc1 = _pc1[1]
		var a: int = NEG_INF if full_window else alpha - bias
		var b: int = -NEG_INF if full_window else beta - bias
		var score: int
		if first or full_window:
			score = -_search(depth - 1, -b, -a, 1, nf0, nf1, nc0, nc1)
		else:
			score = -_search(depth - 1, -a - 1, -a, 1, nf0, nf1, nc0, nc1)
			if score > a and not _aborted:
				# Fail-high: this move beats the best so far. Keep it as a provisional pick
				# so a budget cut during the confirming re-search still uses the finding.
				_iter_code = code
				_iter_score = alpha + 1
				score = -_search(depth - 1, -b, -a, 1, nf0, nf1, nc0, nc1)
		_unmake(code, 0)
		if _aborted:
			hash = saved_hash
			stm = me
			return false
		score += bias
		_root_score[i] = score
		first = false
		if score > alpha:
			alpha = score
			_iter_code = code
			_iter_score = score
	hash = saved_hash
	stm = me
	# Order for the next iteration: best score first.
	for i in range(1, _root_n):
		var kc: int = _root_code[i]
		var ks: int = _root_score[i]
		var kb: int = _root_bias[i]
		var j: int = i - 1
		while j >= 0 and _root_score[j] < ks:
			_root_code[j + 1] = _root_code[j]
			_root_score[j + 1] = _root_score[j]
			_root_bias[j + 1] = _root_bias[j]
			j -= 1
		_root_code[j + 1] = kc
		_root_score[j + 1] = ks
		_root_bias[j + 1] = kb
	return true

func clear_tt() -> void:
	tt_key.fill(0)

## Searches the live game for `me` and returns {"type": "move"/"wall", ...}.
## params: depth (max iterations), budget_usec, nodes, noise (points, 0 = deterministic),
##         avoid (recent own cells, oldest first), k (wall candidates per remaining depth),
##         root_n (root moves weighed when noisy), keep_tt (reuse the previous search's table).
func think(game, me: int, params: Dictionary) -> Dictionary:
	load_position(game, me)
	var max_depth: int = int(params.get("depth", 4))
	_deadline = Time.get_ticks_usec() + int(params.get("budget_usec", 300000))
	_node_limit = int(params.get("nodes", 4000))
	var noise: int = int(params.get("noise", 0))
	var root_keep: int = int(params.get("root_n", 0))
	var avoid: Array = params.get("avoid", [])
	if params.has("k"):
		wall_limit_by_depth = PackedInt32Array(params["k"])
	exact_order_depth = int(params.get("exact_depth", 3))
	_nodes = 0
	_aborted = false
	if not bool(params.get("keep_tt", false)):
		# Entries are exact for their position (the hash covers pawns, walls, wall counts and
		# side to move), so consecutive searches of one game may reuse them; only a different
		# profile or a new game needs a clean table.
		tt_key.fill(0)
	var f0: PackedInt32Array = _pf0[0]
	var f1: PackedInt32Array = _pf1[0]
	var c0: PackedInt32Array = _pc0[0]
	var c1: PackedInt32Array = _pc1[0]
	_bfs(0, f0, c0)
	_bfs(1, f1, c1)
	last_depth = 0
	if not _build_root(me, f0, f1, c0, c1, avoid):
		return {"type": "pass"}
	var best_code: int = _root_code[0]
	var best_score: int = _root_score[0]
	if _root_n > 1 or best_score != WIN:
		for depth in range(1, max_depth + 1):
			var started: int = Time.get_ticks_usec()
			var finished: bool = _root_iteration(depth, noise > 0, f0, f1, c0, c1)
			if finished:
				last_depth = depth
				if noise > 0 and depth == 1 and root_keep > 0:
					# Weaker profiles only weigh the most promising root moves at greater depth.
					_root_n = mini(_root_n, root_keep)
				if noise > 0:
					# Exact scores for every root move: add noise, then take the maximum.
					var pick: int = 0
					var pick_score: int = NEG_INF
					for i in range(_root_n):
						var sc: int = _root_score[i] + int(randf_range(-float(noise), float(noise)))
						if sc > pick_score:
							pick_score = sc
							pick = i
					best_code = _root_code[pick]
					best_score = _root_score[pick]
				else:
					best_code = _root_code[0]
					best_score = _root_score[0]
			else:
				# Budget exhausted mid-iteration: trust a move that already beat the previous
				# best at this depth (never in noisy mode, where scores are not comparable).
				if noise == 0 and _iter_code != NO_MOVE and depth > 1:
					best_code = _iter_code
					best_score = _iter_score
				break
			if absi(best_score) >= WIN_BOUND:
				break
			var spent: int = Time.get_ticks_usec() - started
			if Time.get_ticks_usec() + int(float(spent) * 1.3) > _deadline:
				break
	last_nodes = _nodes
	last_score = best_score
	if best_code < WALL_BASE:
		return {"type": "move", "to": Vector2i(_cell_x[best_code], _cell_y[best_code])}
	var vert: bool = best_code >= VWALL_BASE
	var a: int = best_code - (VWALL_BASE if vert else WALL_BASE)
	return {"type": "wall", "x": a & 7, "y": a >> 3, "vertical": vert}
