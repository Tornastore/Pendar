extends "res://core/game_module.gd"
## Rule engine and authoritative state for blockace.

# ---------- Game-owned state ----------
var blk_grid: Array = []
var blk_turn: int = 0
var blk_pieces: Array = []
var blk_sel: int = 0
var blk_game_over: bool = false
var blk_winner: int = -1
var blk_rot: int = 0
var blk_prev: Vector2i = Vector2i(-1, -1)

func reset_game() -> void:
	_reset_blockace()

func _reset_blockace() -> void:
	blk_grid = []
	for y in 10:
		var row: Array = []
		for x in 10:
			row.append(0)
		blk_grid.append(row)
	blk_turn = 0
	# simple pieces as list of offsets
	blk_pieces = [
		[Vector2i(0,0)],
		[Vector2i(0,0), Vector2i(1,0)],
		[Vector2i(0,0), Vector2i(1,0), Vector2i(2,0)],
		[Vector2i(0,0), Vector2i(0,1), Vector2i(1,0)],
		[Vector2i(0,0), Vector2i(1,0), Vector2i(0,1), Vector2i(1,1)],
	]
	blk_sel = 0
	blk_game_over = false
	blk_winner = -1

func _blk_can_place(px: int, py: int, piece: Array, player: int) -> bool:
	for o in piece:
		var x: int = px + o.x
		var y: int = py + o.y
		if x < 0 or x >= 10 or y < 0 or y >= 10:
			return false
		if blk_grid[y][x] != 0:
			return false
	return true

func _blk_cells(idx: int, rot: int) -> Array:
	var base: Array = blk_pieces[idx]
	var cells: Array = []
	for o in base:
		var v: Vector2i = o
		for k in rot:
			v = Vector2i(-v.y, v.x)
		cells.append(v)
	var mx: int = 999
	var my: int = 999
	for v in cells:
		mx = mini(mx, v.x)
		my = mini(my, v.y)
	var res: Array = []
	for v in cells:
		res.append(Vector2i(v.x - mx, v.y - my))
	return res

func _blk_has_move(player: int) -> bool:
	for i in blk_pieces.size():
		for r in 4:
			var cells: Array = _blk_cells(i, r)
			for y in 10:
				for x in 10:
					if _blk_can_place(x, y, cells, player):
						return true
	return false

func _blk_place(px: int, py: int, piece: Array, player: int) -> void:
	for o in piece:
		blk_grid[py + o.y][px + o.x] = player + 1
	blk_turn = 1 - blk_turn
	if not _blk_has_move(blk_turn):
		if _blk_has_move(1 - blk_turn):
			blk_turn = 1 - blk_turn
			if blk_turn == 1:
				app._show_toast("نوبت یک بازیکن رد شد.")
			else:
				app._show_toast("نوبت یک بازیکن رد شد.")
		else:
			var c0: int = 0
			var c1: int = 0
			for row in blk_grid:
				for v in row:
					if v == 1:
						c0 += 1
					elif v == 2:
						c1 += 1
			blk_game_over = true
			blk_winner = 0 if c0 > c1 else (1 if c1 > c0 else -1)
			app.state = State.RESULT
			app._build_result_buttons()

func _blk_cpu() -> void:
	if blk_game_over or blk_turn != 1:
		return
	var order: Array = [4, 3, 2, 1, 0]
	for i in order:
		var rots: Array = [0, 1, 2, 3]
		rots.shuffle()
		for r in rots:
			var cells: Array = _blk_cells(i, r)
			var sx: int = randi() % 10
			var sy: int = randi() % 10
			for k in 100:
				var x: int = (sx + k) % 10
				var y: int = (sy + int((sx + k) / 10)) % 10
				if _blk_can_place(x, y, cells, 1):
					_blk_place(x, y, cells, 1)
					return
	blk_turn = 0

func _blk_me() -> int:
	return app._my_seat()

func _blk_apply_net(px: int, py: int, sel: int, rot: int, player: int) -> void:
	if blk_game_over or blk_turn != player:
		return
	var cells: Array = _blk_cells(sel, rot)
	if _blk_can_place(px, py, cells, player):
		_blk_place(px, py, cells, player)
	blk_prev = Vector2i(-1, -1)

func _blk_confirm() -> void:
	var me: int = _blk_me()
	if blk_game_over or blk_turn != me or blk_prev.x < 0:
		return
	var cells: Array = _blk_cells(blk_sel, blk_rot)
	if _blk_can_place(blk_prev.x, blk_prev.y, cells, me):
		if app._net_on():
			app.rpc("_rpc_blk_place", blk_prev.x, blk_prev.y, blk_sel, blk_rot, me)
		else:
			_blk_place(blk_prev.x, blk_prev.y, cells, me)
			blk_prev = Vector2i(-1, -1)

func _blk_tap(p: Vector2) -> void:
	if blk_game_over or blk_turn != _blk_me():
		return
	var gx: int = int(floor((p.x - app.BLK_ORIGIN.x) / app.BLK_CELL))
	var gy: int = int(floor((p.y - app.BLK_ORIGIN.y) / app.BLK_CELL))
	if gx < 0 or gx > 9 or gy < 0 or gy > 9:
		return
	var tgt := Vector2i(gx, gy)
	if blk_prev == tgt:
		_blk_confirm()
	else:
		blk_prev = tgt

func _blk_select(i: int) -> void:
	blk_sel = i

func _blk_rotate() -> void:
	blk_rot = (blk_rot + 1) % 4

func _btns_blockace() -> void:
	for i in blk_pieces.size():
		app._add_hit(Rect2(app.VIEW_W - 16 - 88 - i * 96, 650, 88, 76), _blk_select.bind(i), "blk_p%d" % i)
	var valid: bool = false
	if blk_prev.x >= 0 and blk_turn == _blk_me() and not blk_game_over:
		valid = _blk_can_place(blk_prev.x, blk_prev.y, _blk_cells(blk_sel, blk_rot), _blk_me())
	app._add_btn(Rect2(app.VIEW_W - 16 - 150, 740, 150, 52), "چرخش", _blk_rotate, true, app.BLUE, "soft", "rot_cw", "blk_rot")
	app._add_btn(Rect2(16, 740, 340, 52), "قراردادن", _blk_confirm, valid, app.GREEN, "solid", "check", "blk_ok")
	app._last_btn().hint = "ابتدا روی صفحه ضربه بزنید تا پیش‌نمایش ببینید."

func _draw_blk_cell(r: Rect2, col: Color) -> void:
	app._panel(r, col, 6)
	app._gloss(r, 6, 0.16)

func _draw_blockace() -> void:
	var flat: Array = []
	var c0: int = 0
	var c1: int = 0
	for y in 10:
		for x in 10:
			flat.append(blk_grid[y][x])
			if blk_grid[y][x] == 1:
				c0 += 1
			elif blk_grid[y][x] == 2:
				c1 += 1
	app._track_board("blk", flat)
	var ca := Color(0.30, 0.82, 0.76)
	var cb := Color(1.0, 0.62, 0.35)
	var me: int = _blk_me()
	var pa: Dictionary = app._pl("شما", ca if me == 0 else cb, app._fa(c0 if me == 0 else c1), blk_turn == me and not blk_game_over, true, "خانه")
	var pb: Dictionary = app._pl("حریف", cb if me == 0 else ca, app._fa(c1 if me == 0 else c0), blk_turn == 1 - me and not blk_game_over, false, "خانه")
	if pa.active:
		pa.sub = "نوبت شما"
	app._draw_hud("بلاک‌آس", pa, pb)
	var o: Vector2 = app.BLK_ORIGIN
	var cs: float = app.BLK_CELL
	app._panel(Rect2(o - Vector2(10, 10), Vector2(cs * 10 + 20, cs * 10 + 20)), Color(0.10, 0.14, 0.22), 22, Color(0.3, 0.8, 0.75, 0.35), 1.5, 20, 8)
	for y in 10:
		for x in 10:
			var r := Rect2(o.x + x * cs + 1.5, o.y + y * cs + 1.5, cs - 3, cs - 3)
			var v: int = blk_grid[y][x]
			if v == 0:
				app._panel(r, Color(1, 1, 1, 0.05), 6)
			else:
				var t: float = app._cell_t("blk", y * 10 + x)[0]
				var rr: Rect2 = r if t >= 1.0 else r.grow(-(1.0 - app._ease_out(t)) * 10.0)
				_draw_blk_cell(rr, ca if v == 1 else cb)
	if blk_prev.x >= 0 and blk_turn == me and not blk_game_over:
		var cells: Array = _blk_cells(blk_sel, blk_rot)
		var ok: bool = _blk_can_place(blk_prev.x, blk_prev.y, cells, me)
		for oc in cells:
			var px: int = blk_prev.x + oc.x
			var py: int = blk_prev.y + oc.y
			if px >= 0 and px < 10 and py >= 0 and py < 10:
				var rr2 := Rect2(o.x + px * cs + 1.5, o.y + py * cs + 1.5, cs - 3, cs - 3)
				app._panel(rr2, Color(0.3, 0.9, 0.5, 0.55) if ok else Color(1.0, 0.3, 0.35, 0.55), 6, Color(1, 1, 1, 0.6), 1.5)
	for i in blk_pieces.size():
		var r2 := Rect2(app.VIEW_W - 16 - 88 - i * 96, 650, 88, 76)
		var sel: bool = (i == blk_sel)
		app._panel(r2, app.CARD_H if sel else app.CARD, 16, app.ACCENT if sel else app.LINE_STRONG, 2.5 if sel else 1.0)
		var cells2: Array = _blk_cells(i, blk_rot if sel else 0)
		var mxx: int = 0
		var myy: int = 0
		for oc in cells2:
			mxx = maxi(mxx, oc.x)
			myy = maxi(myy, oc.y)
		var us: float = 16.0
		var org := Vector2(r2.get_center().x - (mxx + 1) * us * 0.5, r2.get_center().y - (myy + 1) * us * 0.5)
		for oc in cells2:
			_draw_blk_cell(Rect2(org + Vector2(oc.x, oc.y) * us, Vector2(us - 2, us - 2)), ca if me == 0 else cb)
	if not blk_game_over:
		if blk_turn == me:
			app._hint("روی صفحه ضربه بزنید تا پیش‌نمایش ببینید" if blk_prev.x < 0 else "دوباره همان‌جا ضربه بزنید یا «قراردادن»", 620, app.TEXT_DIM)
		else:
			app._hint("حریف در حال بازی…", 620, app.TEXT_DIM)
