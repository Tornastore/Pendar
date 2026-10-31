extends RefCounted
## Four-player Quoridor CPU core. Same flat-array board model as engine.gd, extended to four
## goal sides: seat 0 -> row 8, seat 1 -> column 0, seat 2 -> row 0, seat 3 -> column 8,
## turn order 0, 1, 2, 3. Cell index c = y * 9 + x; wall anchors a = y * 8 + x.
##
## Every pawn gets an "arrival time" in plies: after my action my k-th future move happens
## 4k plies from now, while a rival that is p seats after me arrives after p + 4 * (steps - 1)
## plies. Only the earliest rival can beat me, so a wall that delays that leader is worth far
## more than one that delays a straggler, and a wall that costs me a tempo must buy more than it
## spends. Higher levels additionally look at the next player's best reply.
##
## Action codes: 0..80 pawn destination, 100..163 horizontal wall anchor, 164..227 vertical.

const CELLS: int = 81
const FAR: int = 99
const WALL_BASE: int = 100
const VWALL_BASE: int = 164
const MOVE_CAP: int = 160

var mvU: PackedByteArray = PackedByteArray()
var mvD: PackedByteArray = PackedByteArray()
var mvL: PackedByteArray = PackedByteArray()
var mvR: PackedByteArray = PackedByteArray()
var hw: PackedByteArray = PackedByteArray()
var vw: PackedByteArray = PackedByteArray()
var pawn: PackedInt32Array = PackedInt32Array()
var wleft: PackedInt32Array = PackedInt32Array()

var _fld: Array = []      # per seat: distance to that seat's goal side (pawns ignored)
var _cnt: Array = []      # per seat: number of distinct shortest routes
var _nf: Array = []       # scratch fields while a candidate wall is being judged
var _nc: Array = []
var _goal: Array = []     # per seat: its nine goal cells
var _acc: Array = []      # per seat: shortest routes crossing each candidate wall
var _list: Array = []
var _q: PackedInt32Array = PackedInt32Array()
var _q2: PackedInt32Array = PackedInt32Array()
var _fwd: PackedInt32Array = PackedInt32Array()
var _cell_x: PackedInt32Array = PackedInt32Array()
var _cell_y: PackedInt32Array = PackedInt32Array()
var _dist: PackedInt32Array = PackedInt32Array()
var _dist2: PackedInt32Array = PackedInt32Array()
var _totals: PackedInt32Array = PackedInt32Array()
var _touched: PackedInt32Array = PackedInt32Array()
var _seen: PackedInt32Array = PackedInt32Array()
var _stamp: int = 0
var _pm: PackedInt32Array = PackedInt32Array()
var _cc: Array = []       # candidate codes per lookahead level
var _cs: Array = []       # candidate scores per lookahead level
var last_score: float = 0.0

func _init() -> void:
	mvU.resize(CELLS)
	mvD.resize(CELLS)
	mvL.resize(CELLS)
	mvR.resize(CELLS)
	hw.resize(64)
	vw.resize(64)
	pawn.resize(4)
	wleft.resize(4)
	_q.resize(96)
	_q2.resize(96)
	_fwd.resize(CELLS)
	_cell_x.resize(CELLS)
	_cell_y.resize(CELLS)
	_dist.resize(4)
	_dist2.resize(4)
	_totals.resize(4)
	_touched.resize(4)
	_seen.resize(128)
	_pm.resize(12)
	for y in range(9):
		for x in range(9):
			_cell_x[y * 9 + x] = x
			_cell_y[y * 9 + x] = y
	for seat in range(4):
		var f: PackedInt32Array = PackedInt32Array()
		f.resize(CELLS)
		var c: PackedInt32Array = PackedInt32Array()
		c.resize(CELLS)
		var nf: PackedInt32Array = PackedInt32Array()
		nf.resize(CELLS)
		var nc: PackedInt32Array = PackedInt32Array()
		nc.resize(CELLS)
		var acc: PackedInt32Array = PackedInt32Array()
		acc.resize(128)
		var lst: PackedInt32Array = PackedInt32Array()
		lst.resize(128)
		_fld.append(f)
		_cnt.append(c)
		_nf.append(nf)
		_nc.append(nc)
		_acc.append(acc)
		_list.append(lst)
		var goal: PackedInt32Array = PackedInt32Array()
		goal.resize(9)
		for i in range(9):
			match seat:
				0:
					goal[i] = 72 + i
				1:
					goal[i] = i * 9
				2:
					goal[i] = i
				_:
					goal[i] = i * 9 + 8
		_goal.append(goal)
	for level in range(2):
		var codes: PackedInt32Array = PackedInt32Array()
		codes.resize(MOVE_CAP)
		var scores: PackedFloat64Array = PackedFloat64Array()
		scores.resize(MOVE_CAP)
		_cc.append(codes)
		_cs.append(scores)
	_reset_board()

# ------------------------------------------------------------------------------------
# Board
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

func _geometry_ok(vert: bool, a: int) -> bool:
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

func load_position(game) -> void:
	_reset_board()
	for seat in range(4):
		var p: Vector2i = game.quo_pawns[seat]
		pawn[seat] = p.y * 9 + p.x
		wleft[seat] = int(game.quo_walls_left[seat])
	for key in game.quo_walls.keys():
		var s: String = str(key)
		var parts: PackedStringArray = s.substr(1).split(",")
		if parts.size() == 2:
			_set_wall(s.begins_with("v"), int(parts[1]) * 8 + int(parts[0]), true)

## Distance (and route count) from every cell to `seat`'s goal side; pawns are ignored.
func _bfs(seat: int, fld: PackedInt32Array, cnt: PackedInt32Array) -> void:
	fld.fill(FAR)
	var goal: PackedInt32Array = _goal[seat]
	var tail: int = 0
	for i in range(9):
		fld[goal[i]] = 0
		cnt[goal[i]] = 1
		_q[tail] = goal[i]
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

func _refresh_all() -> void:
	for seat in range(4):
		_bfs(seat, _fld[seat], _cnt[seat])
		_dist[seat] = _fld[seat][pawn[seat]]

## Accumulates, per candidate wall, how many of `seat`'s shortest routes cross the edges the
## wall would block (same technique as engine.gd). A wall lengthens the route iff it reaches
## the total route count. Returns the number of touched candidates.
func _accumulate(seat: int) -> int:
	var f: PackedInt32Array = _fld[seat]
	var cnt: PackedInt32Array = _cnt[seat]
	var acc: PackedInt32Array = _acc[seat]
	var list: PackedInt32Array = _list[seat]
	var start: int = pawn[seat]
	_fwd.fill(0)
	_fwd[start] = 1
	_q2[0] = start
	var head: int = 0
	var tail: int = 1
	acc.fill(0)
	var touched: int = 0
	while head < tail:
		var c: int = _q2[head]
		head += 1
		var d: int = f[c] - 1
		if d < 0:
			continue
		var w: int = _fwd[c]
		var x: int = _cell_x[c]
		var y: int = _cell_y[c]
		if mvU[c] == 1 and f[c - 9] == d:
			var n: int = c - 9
			if _fwd[n] == 0:
				_q2[tail] = n
				tail += 1
			_fwd[n] += w
			var through: int = w * cnt[n]
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
			var n2: int = c + 9
			if _fwd[n2] == 0:
				_q2[tail] = n2
				tail += 1
			_fwd[n2] += w
			var through2: int = w * cnt[n2]
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
			var n3: int = c - 1
			if _fwd[n3] == 0:
				_q2[tail] = n3
				tail += 1
			_fwd[n3] += w
			var through3: int = w * cnt[n3]
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
			var n4: int = c + 1
			if _fwd[n4] == 0:
				_q2[tail] = n4
				tail += 1
			_fwd[n4] += w
			var through4: int = w * cnt[n4]
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

# ------------------------------------------------------------------------------------
# Moves
# ------------------------------------------------------------------------------------

func _occupied(cell: int, seat: int) -> bool:
	for other in range(4):
		if other != seat and pawn[other] == cell:
			return true
	return false

## Legal pawn destinations for `seat`, using the exact jump / diagonal rules of rules.gd.
func _gen_pawn(seat: int, out: PackedInt32Array) -> int:
	var from: int = pawn[seat]
	var n: int = 0
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
		if not _occupied(adj, seat):
			out[n] = adj
			n += 1
			continue
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
		if straight and not _occupied(adj + step, seat):
			out[n] = adj + step
			n += 1
			continue
		if dir < 2:
			if mvL[adj] == 1 and not _occupied(adj - 1, seat):
				out[n] = adj - 1
				n += 1
			if mvR[adj] == 1 and not _occupied(adj + 1, seat):
				out[n] = adj + 1
				n += 1
		else:
			if mvU[adj] == 1 and not _occupied(adj - 9, seat):
				out[n] = adj - 9
				n += 1
			if mvD[adj] == 1 and not _occupied(adj + 9, seat):
				out[n] = adj + 9
				n += 1
	return n

# ------------------------------------------------------------------------------------
# Scoring
# ------------------------------------------------------------------------------------

## Score from `seat`'s point of view for the distances in `d` (one entry per seat), assuming it
## is the next seat's turn. 100 points = one step of lead over the closest rival.
func _arrival_score(seat: int, d: PackedInt32Array, my_walls: int) -> float:
	var t_me: float = 4.0 * float(d[seat])
	var m1: float = 1.0e9
	var m2: float = 1.0e9
	var wall_sum: int = 0
	for off in range(1, 4):
		var q: int = (seat + off) % 4
		var tq: float = float(off) + 4.0 * float(d[q] - 1)
		wall_sum += wleft[q]
		if tq < m1:
			m2 = m1
			m1 = tq
		elif tq < m2:
			m2 = tq
	var lead1: float = clampf((m1 - t_me) / 4.0, -12.0, 12.0)
	var lead2: float = clampf((m2 - t_me) / 4.0, -12.0, 12.0)
	var score: float = lead1 * 100.0 + lead2 * 30.0 + float(my_walls) * 9.0 - float(wall_sum) * 2.0
	if m1 < t_me - 3.0:
		# Someone arrives before I can even move again: treat it as a emergency.
		score -= 120.0
	return score

## Builds the candidate list for `seat` into level `lv`, best first. Walls are only considered
## when they lengthen the route of one of the `targets` most dangerous rivals.
func _candidates(seat: int, lv: int, targets: int, avoid: Array, noise: float) -> int:
	var codes: PackedInt32Array = _cc[lv]
	var scores: PackedFloat64Array = _cs[lv]
	var n: int = 0
	var base: PackedInt32Array = _dist.duplicate()
	var fm: PackedInt32Array = _fld[seat]
	var moves: int = _gen_pawn(seat, _pm)
	for i in range(moves):
		var t: int = _pm[i]
		var d2: PackedInt32Array = base.duplicate()
		d2[seat] = fm[t]
		var score: float = _arrival_score(seat, d2, wleft[seat])
		if fm[t] == 0:
			score += 1.0e6
		var cell: Vector2i = Vector2i(_cell_x[t], _cell_y[t])
		var idx: int = avoid.find(cell)
		if idx >= 0:
			score -= 90.0 if idx >= avoid.size() - 2 else 35.0
		if noise > 0.0:
			score += randf_range(-noise, noise)
		codes[n] = t
		scores[n] = score
		n += 1
	if wleft[seat] > 0 and targets > 0:
		# Rank rivals by arrival time and keep the most dangerous ones as wall targets.
		var order: Array = []
		for off in range(1, 4):
			var q: int = (seat + off) % 4
			order.append({"seat": q, "t": float(off) + 4.0 * float(base[q] - 1)})
		order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.t) < float(b.t))
		for q in range(4):
			_totals[q] = _cnt[q][pawn[q]]
			_touched[q] = _accumulate(q)
		_stamp += 1
		for oi in range(mini(targets, order.size())):
			var target_seat: int = int(order[oi].seat)
			var acc: PackedInt32Array = _acc[target_seat]
			var list: PackedInt32Array = _list[target_seat]
			for ti in range(_touched[target_seat]):
				var widx: int = list[ti]
				if acc[widx] < _totals[target_seat] or _seen[widx] == _stamp:
					continue
				_seen[widx] = _stamp
				var vert: bool = widx >= 64
				var a: int = widx - 64 if vert else widx
				if not _geometry_ok(vert, a):
					continue
				var d3: PackedInt32Array = base.duplicate()
				var legal: bool = true
				_set_wall(vert, a, true)
				for r in range(4):
					if _acc[r][widx] >= _totals[r]:
						_bfs(r, _nf[r], _nc[r])
						var nd: int = _nf[r][pawn[r]]
						if nd >= FAR:
							legal = false
							break
						d3[r] = nd
				_set_wall(vert, a, false)
				if not legal or n >= MOVE_CAP - 1:
					continue
				var wscore: float = _arrival_score(seat, d3, wleft[seat] - 1)
				if noise > 0.0:
					wscore += randf_range(-noise, noise)
				codes[n] = (VWALL_BASE + a) if vert else (WALL_BASE + a)
				scores[n] = wscore
				n += 1
	# Insertion sort, best first.
	for i in range(1, n):
		var kc: int = codes[i]
		var ks: float = scores[i]
		var j: int = i - 1
		while j >= 0 and scores[j] < ks:
			codes[j + 1] = codes[j]
			scores[j + 1] = scores[j]
			j -= 1
		codes[j + 1] = kc
		scores[j + 1] = ks
	return n

# ------------------------------------------------------------------------------------
# Applying actions (used by the one-reply lookahead)
# ------------------------------------------------------------------------------------

func _apply(seat: int, code: int) -> int:
	if code < WALL_BASE:
		var old: int = pawn[seat]
		pawn[seat] = code
		_dist[seat] = _fld[seat][code]
		return old
	var vert: bool = code >= VWALL_BASE
	_set_wall(vert, code - (VWALL_BASE if vert else WALL_BASE), true)
	wleft[seat] -= 1
	_refresh_all()
	return -1

func _undo(seat: int, code: int, old: int) -> void:
	if code < WALL_BASE:
		pawn[seat] = old
		_dist[seat] = _fld[seat][old]
		return
	var vert: bool = code >= VWALL_BASE
	_set_wall(vert, code - (VWALL_BASE if vert else WALL_BASE), false)
	wleft[seat] += 1
	_refresh_all()

func _to_action(code: int) -> Dictionary:
	if code < WALL_BASE:
		return {"type": "move", "to": Vector2i(_cell_x[code], _cell_y[code])}
	var vert: bool = code >= VWALL_BASE
	var a: int = code - (VWALL_BASE if vert else WALL_BASE)
	return {"type": "wall", "x": a & 7, "y": a >> 3, "vertical": vert}

## params: targets (rivals considered for walls), noise (points), reply_n (how many of the best
## candidates are re-scored after the next player's best reply), avoid (recent own cells).
func think(game, seat: int, params: Dictionary) -> Dictionary:
	load_position(game)
	var targets: int = int(params.get("targets", 2))
	var noise: float = float(params.get("noise", 0.0))
	var reply_n: int = int(params.get("reply_n", 0))
	var avoid: Array = params.get("avoid", [])
	_refresh_all()
	var n: int = _candidates(seat, 0, targets, avoid, noise)
	if n == 0:
		return {"type": "pass"}
	var codes: PackedInt32Array = _cc[0]
	var scores: PackedFloat64Array = _cs[0]
	var best: int = codes[0]
	var best_score: float = scores[0]
	if best_score >= 1.0e5:
		return _to_action(best)   # a pawn move that reaches the goal
	if reply_n > 0:
		var nxt: int = (seat + 1) % 4
		best_score = -1.0e12
		for i in range(mini(reply_n, n)):
			var code: int = codes[i]
			var first_score: float = scores[i]
			var saved: Array = [pawn.duplicate(), wleft.duplicate(), _dist.duplicate()]
			var old: int = _apply(seat, code)
			var after: float = first_score
			var replies: int = _candidates(nxt, 1, targets, [], 0.0)
			if replies > 0:
				var reply_code: int = _cc[1][0]
				var reply_old: int = _apply(nxt, reply_code)
				for q in range(4):
					_dist[q] = _fld[q][pawn[q]]
				if _dist[nxt] == 0:
					after = -1.0e5   # the reply wins the game
				else:
					after = _arrival_score(seat, _dist, wleft[seat])
				_undo(nxt, reply_code, reply_old)
			_undo(seat, code, old)
			pawn = saved[0]
			wleft = saved[1]
			_dist = saved[2]
			# Blend: the lookahead matters most, the direct score keeps the plan coherent.
			var combined: float = after * 0.7 + first_score * 0.3
			if noise > 0.0:
				combined += randf_range(-noise, noise) * 0.25
			if combined > best_score:
				best_score = combined
				best = code
	last_score = best_score
	return _to_action(best)
