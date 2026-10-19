extends "res://core/game_module.gd"
## Rule engine and authoritative state for hokm.

# ---------- Game-owned state ----------
var hokm_hands: Array = [[], []]
var hokm_trick: Array = []
var hokm_trump: int = 0
var hokm_turn: int = 0
var hokm_scores: Array = [0, 0]
var hokm_led_suit: int = -1
var hokm_game_over: bool = false
var hokm_winner: int = -1
var hokm_dealer: int = 0
var hokm_last: Array = []
var hokm_last_winner: int = -1
var hokm_last_t: float = -10.0

func reset_game() -> void:
	_reset_hokm()

func _reset_hokm() -> void:
	var deck: Array = []
	for s in 4:
		for r in range(1, 14):
			deck.append({"r": r, "s": s})
	deck.shuffle()
	hokm_hands = [[], []]
	for i in 13:
		hokm_hands[0].append(deck.pop_back())
		hokm_hands[1].append(deck.pop_back())
	hokm_trump = randi() % 4
	hokm_trick = []
	hokm_turn = 0
	hokm_scores = [0, 0]
	hokm_led_suit = -1
	hokm_game_over = false
	hokm_winner = -1

func _hk_rank(r: int) -> int:
	return 14 if r == 1 else r

func _hokm_card_beats(a: Dictionary, b: Dictionary, led: int, trump: int) -> bool:
	if a.s == trump and b.s != trump:
		return true
	if a.s != trump and b.s == trump:
		return false
	if a.s == b.s:
		return _hk_rank(int(a.r)) > _hk_rank(int(b.r))
	if a.s == led and b.s != led and b.s != trump:
		return true
	return false

func _hokm_legal(p: int, card: Dictionary) -> bool:
	if hokm_led_suit < 0:
		return true
	for c in hokm_hands[p]:
		if c.s == hokm_led_suit:
			return card.s == hokm_led_suit
	return true

func _hokm_play(p: int, idx: int) -> void:
	var card: Dictionary = hokm_hands[p][idx]
	if not _hokm_legal(p, card):
		return
	hokm_hands[p].remove_at(idx)
	if hokm_trick.size() == 0:
		hokm_led_suit = card.s
	hokm_trick.append({"p": p, "c": card})
	if hokm_trick.size() == 2:
		var a: Dictionary = hokm_trick[0]
		var b: Dictionary = hokm_trick[1]
		var winner: int = a.p
		if _hokm_card_beats(b.c, a.c, hokm_led_suit, hokm_trump):
			winner = b.p
		hokm_scores[winner] += 1
		hokm_last = [a.duplicate(), b.duplicate()]
		hokm_last_winner = winner
		hokm_last_t = app._time
		hokm_trick.clear()
		hokm_led_suit = -1
		hokm_turn = winner
		if hokm_hands[0].size() == 0:
			hokm_game_over = true
			hokm_winner = 0 if hokm_scores[0] > hokm_scores[1] else 1
			app.state = State.RESULT
			app._build_result_buttons()
	else:
		hokm_turn = 1 - p

func _hokm_cpu() -> void:
	if hokm_hands[1].size() == 0 or hokm_game_over or hokm_turn != 1:
		return
	var idx: int = 0
	for i in hokm_hands[1].size():
		if _hokm_legal(1, hokm_hands[1][i]):
			idx = i
			break
	_hokm_play(1, idx)

func _hokm_rects() -> Array:
	return app._fan_rects(hokm_hands[0].size(), 58.0, 86.0, 762.0, 500.0, 6.0)

func _hokm_tap(p: Vector2) -> void:
	if hokm_game_over or hokm_turn != 0 or app._time - hokm_last_t < 0.9:
		return
	var i: int = app._fan_hit(_hokm_rects(), p)
	if i < 0:
		return
	if not _hokm_legal(0, hokm_hands[0][i]):
		app._show_toast("باید هم‌خالِ زمین بازی کنید.")
		return
	_hokm_play(0, i)

func _draw_hokm() -> void:
	var suit_cols := [app.TEXT, app.RED, app.RED, app.TEXT]
	var pa: Dictionary = app._pl("شما", app.BLUE, app._fa(hokm_scores[0]), hokm_turn == 0 and not hokm_game_over, true, "دست برده")
	var pb: Dictionary = app._pl("حریف", app.PINK, app._fa(hokm_scores[1]), hokm_turn == 1 and not hokm_game_over, false, "دست برده")
	if pa.active:
		pa.sub = "نوبت شما"
	app._draw_hud("حکم", pa, pb)
	var orr: Array = app._fan_rects(hokm_hands[1].size(), 36.0, 52.0, 150.0, 240.0, 4.0)
	for r in orr:
		app._draw_card_back(r)
	var badge := Rect2(app.VIEW_W - 16 - 118, 150, 118, 40)
	app._panel(badge, Color(1, 1, 1, 0.07), 20, app.ACCENT, 1.2)
	app._txt_r("حکم", badge.end.x - 14, badge.position.y + 26, 15, app.TEXT, true, 60)
	var sc: Color = Color(0.9, 0.25, 0.3) if (hokm_trump == 1 or hokm_trump == 2) else Color(0.95, 0.96, 1.0)
	app._draw_suit(hokm_trump, Vector2(badge.position.x + 34, badge.get_center().y), 22, sc)
	var table := Rect2(16, 210, app.VIEW_W - 32, 380)
	app._panel(table, Color(0.07, 0.24, 0.20), 26, Color(0.25, 0.65, 0.5, 0.4), 1.5, 18, 6)
	var slot_opp := Rect2(app.VIEW_W * 0.5 - 45, 236, 90, 126)
	var slot_me := Rect2(app.VIEW_W * 0.5 - 45, 424, 90, 126)
	for s in [slot_opp, slot_me]:
		app._panel(s, Color(1, 1, 1, 0.05), 12, Color(1, 1, 1, 0.15), 1.0)
	var showing_last: bool = hokm_trick.size() == 0 and hokm_last.size() == 2 and app._time - hokm_last_t < 1.4
	var plays: Array = hokm_last if showing_last else hokm_trick
	for it in plays:
		var rr: Rect2 = slot_me if int(it.p) == 0 else slot_opp
		var won: bool = showing_last and int(it.p) == hokm_last_winner
		app._draw_card(rr, it.c, false, false, won)
	if showing_last:
		app._txt_c("برنده این دست: " + ("شما" if hokm_last_winner == 0 else "حریف"), Rect2(table.position.x, table.position.y + 4, table.size.x, 26), 13, app.ACCENT, true)
	app._txt_c("هنوز ۱۳ دست: " + app._fa(13 - hokm_hands[0].size()) + " / " + app._fa(13), Rect2(table.position.x, table.end.y - 30, table.size.x, 24), 12, Color(1, 1, 1, 0.4))
	var rects: Array = _hokm_rects()
	for i in rects.size():
		var c: Dictionary = hokm_hands[0][i]
		var ok: bool = hokm_turn == 0 and _hokm_legal(0, c)
		app._draw_card(rects[i], c, false, hokm_turn == 0 and not ok, false)
	if not hokm_game_over:
		app._hint("کارت بزنید تا بازی شود" if hokm_turn == 0 else "حریف در حال بازی…", 706, app.TEXT_DIM)
