extends RefCounted

# Renders decorative icons and the small illustrations on game-selection cards.
# Drawing is delegated to the active CanvasItem so the original draw order is retained.
var _canvas: CanvasItem
var _bg_top: Color = Color(0.039, 0.055, 0.118)
var _mm_colors: Array = []

func draw_icon(canvas: CanvasItem, n: String, c: Vector2, s: float, col: Color, w: float, bg_top: Color) -> void:
	_canvas = canvas
	_bg_top = bg_top
	_draw_icon(n, c, s, col, w)

func draw_game_art(canvas: CanvasItem, id: String, rect: Rect2, col: Color, bg_top: Color, mm_colors: Array) -> void:
	_canvas = canvas
	_bg_top = bg_top
	_mm_colors = mm_colors
	_draw_game_art(id, rect, col)

func _panel(r: Rect2, fill: Color, rad: float = 16.0, bc: Color = Color(0, 0, 0, 0), bw: float = 0.0, shadow: float = 0.0, sy: float = 0.0) -> void:
	_canvas.call("_panel", r, fill, rad, bc, bw, shadow, sy)

func _ring(c: Vector2, r: float, col: Color, w: float = 2.0) -> void:
	_canvas.call("_ring", c, r, col, w)

func _txt_c(s: String, r: Rect2, size: int, col: Color, bold: bool = false) -> void:
	_canvas.call("_txt_c", s, r, size, col, bold)

func _gloss(r: Rect2, rad: float, a: float = 0.07) -> void:
	_canvas.call("_gloss", r, rad, a)

func _draw_disc(c: Vector2, r: float, light: bool) -> void:
	_canvas.call("_draw_disc", c, r, light)

func _draw_chess_piece(typ: int, white: bool, c: Vector2, size: float) -> void:
	_canvas.call("_draw_chess_piece", typ, white, c, size)

func _draw_dom_tile(r: Rect2, a: int, b: int, selected: bool, dim: bool, horizontal: bool, glow: Color = Color(0, 0, 0, 0)) -> void:
	_canvas.call("_draw_dom_tile", r, a, b, selected, dim, horizontal, glow)

func _draw_card(r: Rect2, c: Dictionary, selected: bool = false, dim: bool = false, hl: bool = false) -> void:
	_canvas.call("_draw_card", r, c, selected, dim, hl)

func _draw_dice_face(r: Rect2, n: int, dim: bool = false) -> void:
	_canvas.call("_draw_dice_face", r, n, dim)

func _draw_icon(n: String, c: Vector2, s: float, col: Color, w: float = 2.4) -> void:
	var h: float = s * 0.5
	match n:
		"back":
			_canvas.draw_polyline(PackedVector2Array([c + Vector2(-h * 0.35, -h * 0.75), c + Vector2(h * 0.4, 0), c + Vector2(-h * 0.35, h * 0.75)]), col, w, true)
		"forward":
			_canvas.draw_polyline(PackedVector2Array([c + Vector2(h * 0.35, -h * 0.75), c + Vector2(-h * 0.4, 0), c + Vector2(h * 0.35, h * 0.75)]), col, w, true)
		"close":
			_canvas.draw_line(c + Vector2(-h * 0.6, -h * 0.6), c + Vector2(h * 0.6, h * 0.6), col, w, true)
			_canvas.draw_line(c + Vector2(h * 0.6, -h * 0.6), c + Vector2(-h * 0.6, h * 0.6), col, w, true)
		"music", "music_off":
			_canvas.draw_line(c + Vector2(h * 0.35, -h * 0.75), c + Vector2(h * 0.35, h * 0.4), col, w, true)
			_canvas.draw_line(c + Vector2(h * 0.35, -h * 0.75), c + Vector2(-h * 0.45, -h * 0.5), col, w, true)
			_canvas.draw_line(c + Vector2(-h * 0.45, -h * 0.5), c + Vector2(-h * 0.45, h * 0.6), col, w, true)
			_canvas.draw_circle(c + Vector2(h * 0.1, h * 0.45), h * 0.3, col)
			_canvas.draw_circle(c + Vector2(-h * 0.7, h * 0.65), h * 0.3, col)
			if n == "music_off":
				_canvas.draw_line(c + Vector2(-h * 0.9, -h * 0.9), c + Vector2(h * 0.9, h * 0.9), Color(1.0, 0.45, 0.5), w * 1.2, true)
		"help":
			_ring(c, h * 0.9, col, w * 0.8)
			_txt_c("؟", Rect2(c - Vector2(h, h), Vector2(s, s)), int(s * 0.7), col, true)
		"pause":
			_panel(Rect2(c + Vector2(-h * 0.55, -h * 0.65), Vector2(h * 0.42, h * 1.3)), col, 2)
			_panel(Rect2(c + Vector2(h * 0.13, -h * 0.65), Vector2(h * 0.42, h * 1.3)), col, 2)
		"play":
			_canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.45, -h * 0.7), c + Vector2(h * 0.7, 0), c + Vector2(-h * 0.45, h * 0.7)]), col)
		"door":
			_canvas.draw_polyline(PackedVector2Array([c + Vector2(-h * 0.1, -h * 0.8), c + Vector2(-h * 0.7, -h * 0.8), c + Vector2(-h * 0.7, h * 0.8), c + Vector2(-h * 0.1, h * 0.8)]), col, w, true)
			_canvas.draw_line(c + Vector2(-h * 0.1, 0), c + Vector2(h * 0.8, 0), col, w, true)
			_canvas.draw_polyline(PackedVector2Array([c + Vector2(h * 0.45, -h * 0.35), c + Vector2(h * 0.8, 0), c + Vector2(h * 0.45, h * 0.35)]), col, w, true)
		"flag":
			_canvas.draw_line(c + Vector2(-h * 0.5, -h * 0.8), c + Vector2(-h * 0.5, h * 0.8), col, w, true)
			_canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.5, -h * 0.75), c + Vector2(h * 0.7, -h * 0.4), c + Vector2(-h * 0.5, h * 0.1)]), col)
		"cpu":
			_panel(Rect2(c - Vector2(h * 0.55, h * 0.55), Vector2(h * 1.1, h * 1.1)), Color(0, 0, 0, 0), 3, col, w * 0.8)
			for i in 3:
				var o: float = (i - 1) * h * 0.45
				_canvas.draw_line(c + Vector2(o, -h * 0.55), c + Vector2(o, -h * 0.95), col, w * 0.7)
				_canvas.draw_line(c + Vector2(o, h * 0.55), c + Vector2(o, h * 0.95), col, w * 0.7)
				_canvas.draw_line(c + Vector2(-h * 0.55, o), c + Vector2(-h * 0.95, o), col, w * 0.7)
				_canvas.draw_line(c + Vector2(h * 0.55, o), c + Vector2(h * 0.95, o), col, w * 0.7)
			_canvas.draw_circle(c, h * 0.18, col)
		"wifi":
			for i in 3:
				var rr: float = h * (0.45 + i * 0.42)
				_canvas.draw_arc(c + Vector2(0, h * 0.6), rr, deg_to_rad(-135), deg_to_rad(-45), 14, col, w * 0.85, true)
			_canvas.draw_circle(c + Vector2(0, h * 0.6), h * 0.12, col)
		"globe":
			_ring(c, h * 0.9, col, w * 0.8)
			_canvas.draw_arc(c, h * 0.9, deg_to_rad(-90), deg_to_rad(90), 12, col, 1.2, true)
			_canvas.draw_line(c + Vector2(-h * 0.9, 0), c + Vector2(h * 0.9, 0), col, 1.4, true)
			_canvas.draw_line(c + Vector2(0, -h * 0.9), c + Vector2(0, h * 0.9), col, 1.4, true)
			var pts := PackedVector2Array()
			for i in 17:
				var a: float = -PI * 0.5 + PI * i / 16.0
				pts.append(c + Vector2(cos(a) * h * 0.42, sin(a) * h * 0.9))
			_canvas.draw_polyline(pts, col, 1.4, true)
			var pts2 := PackedVector2Array()
			for i in 17:
				var a2: float = PI * 0.5 + PI * i / 16.0
				pts2.append(c + Vector2(cos(a2) * h * 0.42, sin(a2) * h * 0.9))
			_canvas.draw_polyline(pts2, col, 1.4, true)
		"keypad":
			for i in 9:
				_canvas.draw_circle(c + Vector2((i % 3 - 1) * h * 0.62, (i / 3 - 1) * h * 0.62), h * 0.17, col)
		"trophy":
			_canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.55, -h * 0.75), c + Vector2(h * 0.55, -h * 0.75), c + Vector2(h * 0.4, h * 0.05), c + Vector2(h * 0.12, h * 0.3), c + Vector2(-h * 0.12, h * 0.3), c + Vector2(-h * 0.4, h * 0.05)]), col)
			_canvas.draw_arc(c + Vector2(-h * 0.55, -h * 0.4), h * 0.3, deg_to_rad(90), deg_to_rad(270), 10, col, w * 0.7, true)
			_canvas.draw_arc(c + Vector2(h * 0.55, -h * 0.4), h * 0.3, deg_to_rad(-90), deg_to_rad(90), 10, col, w * 0.7, true)
			_canvas.draw_rect(Rect2(c + Vector2(-h * 0.1, h * 0.3), Vector2(h * 0.2, h * 0.3)), col)
			_panel(Rect2(c + Vector2(-h * 0.5, h * 0.58), Vector2(h, h * 0.22)), col, 2)
		"chart":
			_panel(Rect2(c + Vector2(-h * 0.75, h * 0.0), Vector2(h * 0.4, h * 0.8)), col, 2)
			_panel(Rect2(c + Vector2(-h * 0.2, -h * 0.8), Vector2(h * 0.4, h * 1.6)), col, 2)
			_panel(Rect2(c + Vector2(h * 0.35, -h * 0.35), Vector2(h * 0.4, h * 1.15)), col, 2)
		"gamepad":
			_panel(Rect2(c + Vector2(-h * 0.95, -h * 0.5), Vector2(h * 1.9, h * 1.05)), Color(0, 0, 0, 0), h * 0.5, col, w * 0.8)
			_canvas.draw_line(c + Vector2(-h * 0.5, -h * 0.2), c + Vector2(-h * 0.5, h * 0.25), col, w * 0.8)
			_canvas.draw_line(c + Vector2(-h * 0.72, h * 0.02), c + Vector2(-h * 0.28, h * 0.02), col, w * 0.8)
			_canvas.draw_circle(c + Vector2(h * 0.4, -h * 0.05), h * 0.1, col)
			_canvas.draw_circle(c + Vector2(h * 0.65, h * 0.2), h * 0.1, col)
		"home":
			_canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h * 0.9), c + Vector2(h * 0.95, -h * 0.05), c + Vector2(-h * 0.95, -h * 0.05)]), col)
			_canvas.draw_rect(Rect2(c + Vector2(-h * 0.6, -h * 0.05), Vector2(h * 1.2, h * 0.85)), col)
		"power":
			_canvas.draw_arc(c, h * 0.75, deg_to_rad(-60), deg_to_rad(240), 20, col, w, true)
			_canvas.draw_line(c + Vector2(0, -h * 0.95), c + Vector2(0, -h * 0.1), col, w, true)
		"restart":
			_canvas.draw_arc(c, h * 0.7, deg_to_rad(-40), deg_to_rad(270), 20, col, w, true)
			_canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(h * 0.55, -h * 0.9), c + Vector2(h * 0.95, -h * 0.25), c + Vector2(h * 0.2, -h * 0.35)]), col)
		"check":
			_canvas.draw_polyline(PackedVector2Array([c + Vector2(-h * 0.7, 0), c + Vector2(-h * 0.2, h * 0.5), c + Vector2(h * 0.7, -h * 0.5)]), col, w * 1.15, true)
		"copy":
			_panel(Rect2(c + Vector2(-h * 0.2, -h * 0.75), Vector2(h * 0.95, h * 1.1)), Color(0, 0, 0, 0), 3, col, w * 0.7)
			_panel(Rect2(c + Vector2(-h * 0.75, -h * 0.35), Vector2(h * 0.95, h * 1.1)), Color(0, 0, 0, 0), 3, col, w * 0.7)
		"backspace":
			_canvas.draw_polyline(PackedVector2Array([c + Vector2(-h * 0.2, -h * 0.6), c + Vector2(h * 0.8, -h * 0.6), c + Vector2(h * 0.8, h * 0.6), c + Vector2(-h * 0.2, h * 0.6), c + Vector2(-h * 0.85, 0), c + Vector2(-h * 0.2, -h * 0.6)]), col, w * 0.8, true)
			_canvas.draw_line(c + Vector2(0, -h * 0.25), c + Vector2(h * 0.5, h * 0.25), col, w * 0.7, true)
			_canvas.draw_line(c + Vector2(h * 0.5, -h * 0.25), c + Vector2(0, h * 0.25), col, w * 0.7, true)
		"rot_cw":
			_canvas.draw_arc(c, h * 0.7, deg_to_rad(-60), deg_to_rad(210), 18, col, w, true)
			_canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.95, h * 0.3), c + Vector2(-h * 0.35, h * 0.2), c + Vector2(-h * 0.7, h * 0.9)]), col)
		"rot_ccw":
			_canvas.draw_arc(c, h * 0.7, deg_to_rad(-30), deg_to_rad(240), 18, col, w, true)
			_canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(h * 0.95, h * 0.3), c + Vector2(h * 0.35, h * 0.2), c + Vector2(h * 0.7, h * 0.9)]), col)
		"user":
			_canvas.draw_circle(c + Vector2(0, -h * 0.35), h * 0.38, col)
			_canvas.draw_arc(c + Vector2(0, h * 0.95), h * 0.8, deg_to_rad(200), deg_to_rad(340), 12, col, w * 1.6, true)
		"warning":
			_canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h * 0.9), c + Vector2(h * 0.95, h * 0.75), c + Vector2(-h * 0.95, h * 0.75)]), col)
			_canvas.draw_line(c + Vector2(0, -h * 0.3), c + Vector2(0, h * 0.25), _bg_top, w * 0.9, true)
			_canvas.draw_circle(c + Vector2(0, h * 0.5), w * 0.5, _bg_top)
		"crown":
			_canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.8, h * 0.55), c + Vector2(-h * 0.85, -h * 0.5), c + Vector2(-h * 0.35, -h * 0.05), c + Vector2(0, -h * 0.75), c + Vector2(h * 0.35, -h * 0.05), c + Vector2(h * 0.85, -h * 0.5), c + Vector2(h * 0.8, h * 0.55)]), col)
		"star":
			var sp := PackedVector2Array()
			for i in 10:
				var rr2: float = h * (0.95 if i % 2 == 0 else 0.42)
				var a3: float = -PI * 0.5 + i * PI / 5.0
				sp.append(c + Vector2(cos(a3), sin(a3)) * rr2)
			_canvas.draw_colored_polygon(sp, col)
		"lock":
			_panel(Rect2(c + Vector2(-h * 0.6, -h * 0.1), Vector2(h * 1.2, h * 0.9)), col, 3)
			_canvas.draw_arc(c + Vector2(0, -h * 0.1), h * 0.4, PI, TAU, 12, col, w, true)
		"info":
			_ring(c, h * 0.9, col, w * 0.8)
			_canvas.draw_circle(c + Vector2(0, -h * 0.4), 1.8, col)
			_canvas.draw_line(c + Vector2(0, -h * 0.1), c + Vector2(0, h * 0.5), col, w * 0.9, true)
		"plus":
			_canvas.draw_line(c + Vector2(-h * 0.6, 0), c + Vector2(h * 0.6, 0), col, w, true)
			_canvas.draw_line(c + Vector2(0, -h * 0.6), c + Vector2(0, h * 0.6), col, w, true)
		"undo":
			_canvas.draw_arc(c + Vector2(0, h * 0.1), h * 0.65, deg_to_rad(180), deg_to_rad(400), 18, col, w, true)
			_canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.95, -h * 0.1), c + Vector2(-h * 0.25, -h * 0.2), c + Vector2(-h * 0.6, h * 0.5)]), col)
		"swap":
			_canvas.draw_line(c + Vector2(-h * 0.7, -h * 0.35), c + Vector2(h * 0.7, -h * 0.35), col, w, true)
			_canvas.draw_line(c + Vector2(h * 0.7, h * 0.35), c + Vector2(-h * 0.7, h * 0.35), col, w, true)


func _art_xf(c: Vector2, o: Vector2, s: float, ang: float = 0.0) -> void:
	_canvas.draw_set_transform(c + o * s, ang, Vector2(s, s))

func _art_end() -> void:
	_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_game_art(id: String, rect: Rect2, col: Color) -> void:
	var c: Vector2 = rect.get_center()
	var s: float = minf(rect.size.x / 228.0, rect.size.y / 98.0)
	match id:
		"othello", "othello12":
			var n: int = 5 if id == "othello" else 8
			var rows: int = 3 if id == "othello" else 4
			var cs: float = 24.0 if id == "othello" else 15.0
			_art_xf(c, Vector2.ZERO, s)
			var ox: float = -cs * n * 0.5
			var oy: float = -cs * rows * 0.5
			for yy in rows:
				for xx in n:
					var rr := Rect2(ox + xx * cs, oy + yy * cs, cs - 1.5, cs - 1.5)
					_canvas.draw_rect(rr, Color(0.14, 0.50, 0.32))
					var v: int = (xx * 3 + yy * 5 + xx * yy) % 4
					if v == 0 or v == 1:
						var cc: Vector2 = rr.get_center()
						_draw_disc(cc, cs * 0.38, v == 1)
			_art_end()
		"pentago":
			_art_xf(c, Vector2.ZERO, s)
			for q in 4:
				var qx: float = -40.0 + (q % 2) * 42.0
				var qy: float = -40.0 + int(q / 2) * 42.0
				_panel(Rect2(qx, qy, 38, 38), Color(0.40, 0.28, 0.16), 6, Color(0.7, 0.5, 0.25, 0.6), 1.0)
				_draw_disc(Vector2(qx + 11, qy + 11), 6.5, false)
				_draw_disc(Vector2(qx + 27, qy + 27), 6.5, true)
			_canvas.draw_arc(Vector2.ZERO, 54, deg_to_rad(-60), deg_to_rad(40), 14, col.lightened(0.3), 3.0, true)
			_canvas.draw_colored_polygon(PackedVector2Array([Vector2(54 * cos(deg_to_rad(40)) + 5, 54 * sin(deg_to_rad(40)) - 6), Vector2(54 * cos(deg_to_rad(40)) + 5, 54 * sin(deg_to_rad(40)) + 9), Vector2(54 * cos(deg_to_rad(40)) - 9, 54 * sin(deg_to_rad(40)) + 2)]), col.lightened(0.3))
			_art_end()
		"quoridor":
			_art_xf(c, Vector2.ZERO, s)
			for yy in 3:
				for xx in 5:
					_panel(Rect2(-60 + xx * 25, -36 + yy * 25, 21, 21), Color(1, 1, 1, 0.12), 5)
			_panel(Rect2(-37, -17, 46, 6), Color(1.0, 0.78, 0.35), 3)
			_panel(Rect2(15, 8, 6, 22), Color(1.0, 0.78, 0.35), 3)
			_draw_disc(Vector2(-47.5, 36 - 14), 8, true)
			_canvas.draw_circle(Vector2(27.5, -25.5), 8.5, Color(1.0, 0.45, 0.5))
			_art_end()
		"chess":
			_art_xf(c, Vector2.ZERO, s)
			for yy in 4:
				for xx in 8:
					var lt: bool = (xx + yy) % 2 == 0
					_canvas.draw_rect(Rect2(-96 + xx * 24, -48 + yy * 24, 24, 24), Color(1, 1, 1, 0.10) if lt else Color(1, 1, 1, 0.03))
			_draw_chess_piece(2, true, Vector2(-26, 3), 78)
			_draw_chess_piece(6, false, Vector2(34, 3), 78)
			_art_end()
		"domino":
			_art_xf(c, Vector2(-30, 4), s, deg_to_rad(-14))
			_draw_dom_tile(Rect2(-22, -34, 44, 68), 6, 4, false, false, false)
			_art_xf(c, Vector2(32, 0), s, deg_to_rad(12))
			_draw_dom_tile(Rect2(-22, -34, 44, 68), 3, 5, false, false, false)
			_art_end()
		"pasoor":
			var ang := [-0.30, 0.0, 0.30]
			var cards := [{"r": 11, "s": 3}, {"r": 7, "s": 0}, {"r": 1, "s": 1}]
			for i in 3:
				_art_xf(c, Vector2((i - 1) * 40, 8 - abs(i - 1) * 4), s, ang[i])
				_draw_card(Rect2(-24, -38, 48, 70), cards[i], false, false, false)
			_art_end()
		"hokm":
			var cs2 := [{"r": 13, "s": 0}, {"r": 12, "s": 1}]
			for i in 2:
				_art_xf(c, Vector2(-26 + i * 52, 10), s, -0.2 + i * 0.4)
				_draw_card(Rect2(-24, -38, 48, 70), cs2[i], false, false, false)
			_art_xf(c, Vector2(0, -30), s)
			_draw_icon("crown", Vector2.ZERO, 26, Color(1.0, 0.82, 0.3))
			_art_end()
		"backgammon":
			_art_xf(c, Vector2.ZERO, s)
			for i in 8:
				var x0: float = -92.0 + i * 23.0
				var tcol := Color(0.85, 0.62, 0.35) if i % 2 == 0 else Color(0.35, 0.22, 0.14)
				_canvas.draw_colored_polygon(PackedVector2Array([Vector2(x0, 44), Vector2(x0 + 21, 44), Vector2(x0 + 10.5, -20)]), tcol)
			_draw_disc(Vector2(-81.5, 34), 9, true)
			_draw_disc(Vector2(-81.5, 15), 9, true)
			_draw_disc(Vector2(57, 34), 9, false)
			_draw_dice_face(Rect2(-14, -42, 30, 30), 5)
			_draw_dice_face(Rect2(24, -34, 30, 30), 2)
			_art_end()
		"gobblet":
			_art_xf(c, Vector2.ZERO, s)
			var cols := [Color(1.0, 0.45, 0.35), Color(0.35, 0.58, 1.0), Color(1.0, 0.78, 0.30)]
			for i in 3:
				var cx: float = (i - 1) * 62.0
				for j in 3:
					var rad: float = 34.0 - j * 11.0
					_canvas.draw_circle(Vector2(cx, 4), rad, cols[(i + j) % 3].darkened(0.1 + j * 0.0))
					_canvas.draw_circle(Vector2(cx, 4), rad - 3.5, cols[(i + j) % 3].lightened(0.1 * j))
			_art_end()
		"mastermind":
			_art_xf(c, Vector2.ZERO, s)
			for i in 4:
				var mc: Color = _mm_colors[(i * 2 + 1) % 6]
				_canvas.draw_circle(Vector2(-60 + i * 36, -10), 14, mc.darkened(0.25))
				_canvas.draw_circle(Vector2(-60 + i * 36, -11), 12, mc)
			for i in 4:
				_canvas.draw_circle(Vector2(-32 + (i % 2) * 14 + 40, 22 + int(i / 2) * 14 - 4), 5, Color(1, 1, 1) if i < 2 else Color(0.1, 0.1, 0.14))
			_art_end()
		"abalone":
			_art_xf(c, Vector2.ZERO, s)
			var pts: Array = [Vector2.ZERO]
			for i in 6:
				pts.append(Vector2(cos(i * PI / 3.0), sin(i * PI / 3.0)) * 30.0)
			for i in pts.size():
				_draw_disc(pts[i], 13, i % 2 == 0)
			_art_end()
		"uno":
			var uno_cols: Array[Color] = [Color("#e9434f"), Color("#2289e8"), Color("#32a765"), Color("#f3c735")]
			for i in 4:
				_art_xf(c, Vector2((-1.5 + i) * 31.0, 5 - absf(1.5 - i) * 3.0), s, (i - 1.5) * 0.09)
				_panel(Rect2(-23, -37, 46, 74), uno_cols[i], 9, Color.WHITE, 1.4)
				_panel(Rect2(-17, -30, 34, 60), Color(0.06, 0.07, 0.12), 18, Color(1,1,1,0.65), 0.8)
				_txt_c(["1", "+۲", "↻", "۷"][i], Rect2(-17, -22, 34, 45), 18, uno_cols[i], true)
			_art_end()
		"quarto":
			_art_xf(c, Vector2.ZERO, s)
			for yy in range(4):
				for xx in range(4):
					var qr := Rect2(-42 + xx * 22, -42 + yy * 22, 19, 19)
					_panel(qr, Color(0.20, 0.22, 0.36), 4, Color(0.75, 0.62, 0.92, 0.45), 0.7)
					if (xx + yy) % 3 == 0:
						_canvas.draw_circle(qr.get_center(), 5.0 if (xx + yy) % 2 == 0 else 4.0, col.lightened(0.12))
						if (xx + yy) % 2 == 1:
							_canvas.draw_circle(qr.get_center(), 2.2, Color(0.10, 0.11, 0.18))
			_art_end()
		"blockace":
			_art_xf(c, Vector2.ZERO, s)
			var shapes: Array = [
				[[0, 0], [1, 0], [2, 0], [2, 1]],
				[[0, 0], [1, 0], [0, 1], [1, 1]],
				[[0, 0], [1, 0], [2, 0], [1, 1]],
			]
			var scol := [Color(0.30, 0.82, 0.76), Color(1.0, 0.62, 0.35), Color(0.62, 0.50, 1.0)]
			var offs := [Vector2(-82, -26), Vector2(-14, -26), Vector2(30, 6)]
			for si in 3:
				for cell in shapes[si]:
					var cp := Rect2(offs[si] + Vector2(cell[0], cell[1]) * 21.0, Vector2(19, 19))
					_panel(cp, scol[si], 4)
					_gloss(cp, 4, 0.18)
			_art_end()
		_:
			_draw_icon("gamepad", c, 40, col)
	_art_end()

