extends RefCounted

# Shared card, dice, domino, disc, marble and chess-piece drawing primitives.
var _canvas: CanvasItem
var _accent: Color = Color(1.0, 0.79, 0.30)
var _pas_ranks: Array = []

func _prepare(canvas: CanvasItem, accent: Color, pas_ranks: Array) -> void:
	_canvas = canvas
	_accent = accent
	_pas_ranks = pas_ranks

func draw_disc(canvas: CanvasItem, c: Vector2, r: float, light: bool, accent: Color, pas_ranks: Array) -> void:
	_prepare(canvas, accent, pas_ranks)
	_draw_disc(c, r, light)

func draw_marble(canvas: CanvasItem, c: Vector2, r: float, col: Color, accent: Color, pas_ranks: Array) -> void:
	_prepare(canvas, accent, pas_ranks)
	_draw_marble(c, r, col)

func pip_positions(n: int, rect: Rect2) -> Array:
	return _pip_positions(n, rect)

func draw_pips(canvas: CanvasItem, rect: Rect2, n: int, col: Color, accent: Color, pas_ranks: Array) -> void:
	_prepare(canvas, accent, pas_ranks)
	_draw_pips(rect, n, col)

func draw_dice_face(canvas: CanvasItem, r: Rect2, n: int, dim: bool, accent: Color, pas_ranks: Array) -> void:
	_prepare(canvas, accent, pas_ranks)
	_draw_dice_face(r, n, dim)

func draw_dom_tile(canvas: CanvasItem, r: Rect2, a: int, b: int, selected: bool, dim: bool, horizontal: bool, glow: Color, accent: Color, pas_ranks: Array) -> void:
	_prepare(canvas, accent, pas_ranks)
	_draw_dom_tile(r, a, b, selected, dim, horizontal, glow)

func draw_dom_back(canvas: CanvasItem, r: Rect2, accent: Color, pas_ranks: Array) -> void:
	_prepare(canvas, accent, pas_ranks)
	_draw_dom_back(r)

func draw_suit(canvas: CanvasItem, s: int, c: Vector2, sz: float, col: Color, accent: Color, pas_ranks: Array) -> void:
	_prepare(canvas, accent, pas_ranks)
	_draw_suit(s, c, sz, col)

func draw_card(canvas: CanvasItem, r: Rect2, c: Dictionary, selected: bool, dim: bool, hl: bool, accent: Color, pas_ranks: Array) -> void:
	_prepare(canvas, accent, pas_ranks)
	_draw_card(r, c, selected, dim, hl)

func draw_card_back(canvas: CanvasItem, r: Rect2, accent: Color, pas_ranks: Array) -> void:
	_prepare(canvas, accent, pas_ranks)
	_draw_card_back(r)

func draw_chess_piece(canvas: CanvasItem, typ: int, white: bool, c: Vector2, size: float, accent: Color, pas_ranks: Array) -> void:
	_prepare(canvas, accent, pas_ranks)
	_draw_chess_piece(typ, white, c, size)

func _panel(r: Rect2, fill: Color, rad: float = 16.0, bc: Color = Color(0, 0, 0, 0), bw: float = 0.0, shadow: float = 0.0, sy: float = 0.0) -> void:
	_canvas.call("_panel", r, fill, rad, bc, bw, shadow, sy)

func _txt(s: String, x: float, y: float, size: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, w: float = -1.0, bold: bool = false) -> void:
	_canvas.call("_txt", s, x, y, size, col, align, w, bold)

func _txt_c(s: String, r: Rect2, size: int, col: Color, bold: bool = false) -> void:
	_canvas.call("_txt_c", s, r, size, col, bold)

func _draw_disc(c: Vector2, r: float, light: bool) -> void:
	_canvas.draw_circle(c + Vector2(0, r * 0.16), r, Color(0, 0, 0, 0.35))
	if light:
		_canvas.draw_circle(c, r, Color(0.74, 0.77, 0.84))
		_canvas.draw_circle(c + Vector2(0, -r * 0.05), r * 0.92, Color(0.95, 0.96, 0.99))
		_canvas.draw_circle(c + Vector2(-r * 0.30, -r * 0.34), r * 0.26, Color(1, 1, 1, 0.75))
	else:
		_canvas.draw_circle(c, r, Color(0.02, 0.03, 0.05))
		_canvas.draw_circle(c + Vector2(0, -r * 0.05), r * 0.92, Color(0.15, 0.17, 0.24))
		_canvas.draw_circle(c + Vector2(-r * 0.30, -r * 0.34), r * 0.24, Color(1, 1, 1, 0.22))

func _draw_marble(c: Vector2, r: float, col: Color) -> void:
	_canvas.draw_circle(c + Vector2(0, r * 0.16), r, Color(0, 0, 0, 0.35))
	_canvas.draw_circle(c, r, col.darkened(0.35))
	_canvas.draw_circle(c + Vector2(0, -r * 0.05), r * 0.92, col)
	_canvas.draw_circle(c + Vector2(-r * 0.28, -r * 0.34), r * 0.26, Color(1, 1, 1, 0.55))

func _pip_positions(n: int, rect: Rect2) -> Array:
	var c: Vector2 = rect.get_center()
	var dx: float = rect.size.x * 0.27
	var dy: float = rect.size.y * 0.27
	match n:
		1: return [c]
		2: return [c + Vector2(-dx, -dy), c + Vector2(dx, dy)]
		3: return [c + Vector2(-dx, -dy), c, c + Vector2(dx, dy)]
		4: return [c + Vector2(-dx, -dy), c + Vector2(dx, -dy), c + Vector2(-dx, dy), c + Vector2(dx, dy)]
		5: return [c + Vector2(-dx, -dy), c + Vector2(dx, -dy), c, c + Vector2(-dx, dy), c + Vector2(dx, dy)]
		6: return [c + Vector2(-dx, -dy), c + Vector2(dx, -dy), c + Vector2(-dx, 0), c + Vector2(dx, 0), c + Vector2(-dx, dy), c + Vector2(dx, dy)]
	return []

func _draw_pips(rect: Rect2, n: int, col: Color) -> void:
	var rad: float = maxf(2.0, minf(rect.size.x, rect.size.y) * 0.085)
	for p in _pip_positions(n, rect):
		_canvas.draw_circle(p, rad, col)

func _draw_dice_face(r: Rect2, n: int, dim: bool = false) -> void:
	_panel(Rect2(r.position + Vector2(0, 2.5), r.size), Color(0, 0, 0, 0.35), r.size.x * 0.22)
	_panel(r, Color(0.95, 0.95, 0.97) if not dim else Color(0.55, 0.57, 0.65), r.size.x * 0.22)
	_draw_pips(r.grow(-r.size.x * 0.06), n, Color(0.12, 0.13, 0.20))

func _draw_dom_tile(r: Rect2, a: int, b: int, selected: bool, dim: bool, horizontal: bool, glow: Color = Color(0, 0, 0, 0)) -> void:
	var rad: float = minf(r.size.x, r.size.y) * 0.18
	_panel(Rect2(r.position + Vector2(0, 2.5), r.size), Color(0, 0, 0, 0.38), rad)
	var bg := Color(0.96, 0.94, 0.88)
	if dim:
		bg = bg.darkened(0.42)
	var bc: Color = _accent if selected else Color(0.25, 0.20, 0.14, 0.55)
	if glow.a > 0.0:
		bc = glow
	_panel(r, bg, rad, bc, 2.5 if (selected or glow.a > 0.0) else 1.0)
	var h1: Rect2
	var h2: Rect2
	var pc := Color(0.13, 0.12, 0.17) if not dim else Color(0.30, 0.28, 0.30)
	if horizontal:
		h1 = Rect2(r.position, Vector2(r.size.x * 0.5, r.size.y))
		h2 = Rect2(r.position + Vector2(r.size.x * 0.5, 0), Vector2(r.size.x * 0.5, r.size.y))
		_canvas.draw_line(r.position + Vector2(r.size.x * 0.5, r.size.y * 0.16), r.position + Vector2(r.size.x * 0.5, r.size.y * 0.84), Color(0.3, 0.25, 0.2, 0.6), 1.5)
	else:
		h1 = Rect2(r.position, Vector2(r.size.x, r.size.y * 0.5))
		h2 = Rect2(r.position + Vector2(0, r.size.y * 0.5), Vector2(r.size.x, r.size.y * 0.5))
		_canvas.draw_line(r.position + Vector2(r.size.x * 0.16, r.size.y * 0.5), r.position + Vector2(r.size.x * 0.84, r.size.y * 0.5), Color(0.3, 0.25, 0.2, 0.6), 1.5)
	_draw_pips(h1.grow(-2), a, pc)
	_draw_pips(h2.grow(-2), b, pc)

func _draw_dom_back(r: Rect2) -> void:
	var rad: float = minf(r.size.x, r.size.y) * 0.18
	_panel(r, Color(0.16, 0.19, 0.36), rad, Color(0.38, 0.45, 0.80, 0.6), 1.0, 4, 2)
	_canvas.draw_circle(r.get_center(), minf(r.size.x, r.size.y) * 0.12, Color(0.45, 0.55, 0.95, 0.7))

func _draw_suit(s: int, c: Vector2, sz: float, col: Color) -> void:
	var u: float = sz * 0.5
	match s:
		0:
			_canvas.draw_circle(c + Vector2(-u * 0.44, u * 0.14), u * 0.48, col)
			_canvas.draw_circle(c + Vector2(u * 0.44, u * 0.14), u * 0.48, col)
			_canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -u), c + Vector2(-u * 0.92, u * 0.2), c + Vector2(u * 0.92, u * 0.2)]), col)
			_canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 0.12, u * 0.1), c + Vector2(-u * 0.34, u * 0.98), c + Vector2(u * 0.34, u * 0.98), c + Vector2(u * 0.12, u * 0.1)]), col)
		1:
			_canvas.draw_circle(c + Vector2(-u * 0.46, -u * 0.3), u * 0.5, col)
			_canvas.draw_circle(c + Vector2(u * 0.46, -u * 0.3), u * 0.5, col)
			_canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 0.96, -u * 0.1), c + Vector2(u * 0.96, -u * 0.1), c + Vector2(0, u * 0.98)]), col)
		2:
			_canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -u), c + Vector2(u * 0.72, 0), c + Vector2(0, u), c + Vector2(-u * 0.72, 0)]), col)
		3:
			_canvas.draw_circle(c + Vector2(0, -u * 0.46), u * 0.44, col)
			_canvas.draw_circle(c + Vector2(-u * 0.52, u * 0.2), u * 0.44, col)
			_canvas.draw_circle(c + Vector2(u * 0.52, u * 0.2), u * 0.44, col)
			_canvas.draw_circle(c + Vector2(0, u * 0.06), u * 0.3, col)
			_canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 0.12, u * 0.1), c + Vector2(-u * 0.34, u * 0.98), c + Vector2(u * 0.34, u * 0.98), c + Vector2(u * 0.12, u * 0.1)]), col)

func _draw_card(r: Rect2, c: Dictionary, selected: bool = false, dim: bool = false, hl: bool = false) -> void:
	var rad: float = minf(r.size.x * 0.14, 11.0)
	_panel(Rect2(r.position + Vector2(0, 3), r.size), Color(0, 0, 0, 0.38), rad)
	var bg := Color(0.98, 0.97, 0.94)
	if dim:
		bg = bg.darkened(0.36)
	var bcol: Color = Color(0.2, 0.18, 0.16, 0.45)
	var bw: float = 1.0
	if selected or hl:
		bcol = _accent
		bw = 3.0
	_panel(r, bg, rad, bcol, bw)
	var red: bool = (int(c.s) == 1 or int(c.s) == 2)
	var col: Color = Color(0.82, 0.13, 0.20) if red else Color(0.09, 0.10, 0.16)
	if dim:
		col = col.lerp(bg, 0.40)
	var label: String = _pas_ranks[int(c.r)]
	var fs: int = int(r.size.x * 0.30)
	_txt(label, r.position.x + r.size.x * 0.10, r.position.y + fs + 3, fs, col, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	_draw_suit(int(c.s), Vector2(r.position.x + r.size.x * 0.10 + fs * 0.34, r.position.y + fs + 3 + fs * 0.55), fs * 0.55, col)
	if int(c.r) >= 11:
		_txt_c(label, Rect2(r.position.x, r.position.y + r.size.y * 0.30, r.size.x, r.size.y * 0.5), int(r.size.x * 0.62), col, true)
	else:
		_draw_suit(int(c.s), r.get_center() + Vector2(0, r.size.y * 0.1), r.size.x * 0.46, col)

func _draw_card_back(r: Rect2) -> void:
	var rad: float = minf(r.size.x * 0.14, 11.0)
	_panel(Rect2(r.position + Vector2(0, 2), r.size), Color(0, 0, 0, 0.35), rad)
	_panel(r, Color(0.20, 0.16, 0.42), rad, Color(0.96, 0.96, 1.0, 0.85), 2.0)
	var inner: Rect2 = r.grow(-r.size.x * 0.14)
	_panel(inner, Color(0.30, 0.24, 0.62), rad * 0.6, Color(0.7, 0.65, 1.0, 0.5), 1.0)
	var c: Vector2 = r.get_center()
	var h: float = minf(inner.size.x, inner.size.y) * 0.28
	_canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h), c + Vector2(h * 0.7, 0), c + Vector2(0, h), c + Vector2(-h * 0.7, 0)]), Color(0.75, 0.70, 1.0, 0.55))

func _cpoly(pts: Array, c: Vector2, u: float, fill: Color, edge: Color) -> void:
	var arr := PackedVector2Array()
	for p in pts:
		arr.append(c + (p as Vector2) * u)
	_canvas.draw_colored_polygon(arr, fill)
	arr.append(arr[0])
	_canvas.draw_polyline(arr, edge, 1.6, true)

func _ccirc(p: Vector2, r: float, c: Vector2, u: float, fill: Color, edge: Color) -> void:
	_canvas.draw_circle(c + p * u, r * u + 1.4, edge)
	_canvas.draw_circle(c + p * u, r * u, fill)

func _draw_chess_piece(typ: int, white: bool, c: Vector2, size: float) -> void:
	var fill: Color = Color(0.97, 0.95, 0.90) if white else Color(0.17, 0.18, 0.24)
	var edge: Color = Color(0.10, 0.09, 0.10) if white else Color(0.88, 0.90, 0.96)
	var u: float = size / 100.0
	_panel(Rect2(c + Vector2(-34, 30) * u, Vector2(68, 12) * u), Color(0, 0, 0, 0.28), 6.0 * u)
	_panel(Rect2(c + Vector2(-30, 26) * u, Vector2(60, 14) * u), fill, 6.0 * u, edge, 1.5)
	match typ:
		1:
			_cpoly([Vector2(-10, -8), Vector2(10, -8), Vector2(18, 26), Vector2(-18, 26)], c, u, fill, edge)
			_panel(Rect2(c + Vector2(-16, -12) * u, Vector2(32, 8) * u), fill, 3.0 * u, edge, 1.5)
			_ccirc(Vector2(0, -24), 13, c, u, fill, edge)
		2:
			_cpoly([Vector2(-22, 28), Vector2(-18, 6), Vector2(-8, -4), Vector2(-16, -10), Vector2(-8, -26), Vector2(0, -38), Vector2(5, -30), Vector2(13, -37), Vector2(15, -24), Vector2(24, -2), Vector2(22, 28)], c, u, fill, edge)
			_canvas.draw_circle(c + Vector2(3, -22) * u, 2.8 * u, edge)
			_canvas.draw_line(c + Vector2(-14, -12) * u, c + Vector2(-8, -10) * u, edge, 1.8, true)
		3:
			_cpoly([Vector2(-18, 26), Vector2(-8, -4), Vector2(8, -4), Vector2(18, 26)], c, u, fill, edge)
			var hp: Array = []
			for i in 16:
				var a: float = TAU * i / 16.0
				hp.append(Vector2(cos(a) * 12.0, -22.0 + sin(a) * 18.0))
			_cpoly(hp, c, u, fill, edge)
			_ccirc(Vector2(0, -44), 5, c, u, fill, edge)
			_canvas.draw_line(c + Vector2(-3, -30) * u, c + Vector2(6, -16) * u, edge, 2.0, true)
		4:
			_cpoly([Vector2(-18, 26), Vector2(-14, -8), Vector2(14, -8), Vector2(18, 26)], c, u, fill, edge)
			_cpoly([Vector2(-21, -8), Vector2(-21, -34), Vector2(-12, -34), Vector2(-12, -26), Vector2(-4, -26), Vector2(-4, -34), Vector2(4, -34), Vector2(4, -26), Vector2(12, -26), Vector2(12, -34), Vector2(21, -34), Vector2(21, -8)], c, u, fill, edge)
		5:
			_cpoly([Vector2(-18, 26), Vector2(-12, -6), Vector2(12, -6), Vector2(18, 26)], c, u, fill, edge)
			_cpoly([Vector2(-22, -8), Vector2(-26, -32), Vector2(-12, -20), Vector2(-7, -38), Vector2(0, -22), Vector2(7, -38), Vector2(12, -20), Vector2(26, -32), Vector2(22, -8)], c, u, fill, edge)
			for px in [-26.0, -7.0, 7.0, 26.0]:
				_ccirc(Vector2(px, -36 if abs(px) < 10 else -33), 4, c, u, fill, edge)
		6:
			_cpoly([Vector2(-20, 26), Vector2(-14, -4), Vector2(14, -4), Vector2(20, 26)], c, u, fill, edge)
			_panel(Rect2(c + Vector2(-17, -22) * u, Vector2(34, 18) * u), fill, 6.0 * u, edge, 1.5)
			_panel(Rect2(c + Vector2(-3.5, -46) * u, Vector2(7, 26) * u), fill, 2.0 * u, edge, 1.5)
			_panel(Rect2(c + Vector2(-11, -39) * u, Vector2(22, 7) * u), fill, 2.0 * u, edge, 1.5)

