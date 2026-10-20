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
var hokm_difficulty: int = 3 # 1 random .. 6 tactical trick play, suit planning, and void tracking
var hokm_voids: Array = [[], []] # suits each player has shown void in
var hokm_seen_cards: Array = []

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
	hokm_voids = [[], []]
	hokm_seen_cards = []
	hokm_last = []
	hokm_last_winner = -1
	hokm_last_t = -10.0

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
	if p < 0 or p >= hokm_hands.size() or idx < 0 or idx >= hokm_hands[p].size():
		return
	var card: Dictionary = hokm_hands[p][idx]
	if not _hokm_legal(p, card):
		return
	if hokm_trick.size() == 1:
		var led_card: Dictionary = hokm_trick[0].c
		if int(card.s) != int(led_card.s) and not hokm_voids[p].has(int(led_card.s)):
			hokm_voids[p].append(int(led_card.s))
	hokm_hands[p].remove_at(idx)
	hokm_seen_cards.append(card.duplicate())
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

func _hokm_rank_value(card: Dictionary) -> int:
	return _hk_rank(int(card.r))

func _hokm_suit_count(cards: Array, suit: int) -> int:
	var count: int = 0
	for c in cards:
		if int(c.s) == suit:
			count += 1
	return count

func _hokm_high_cards_in_suit(cards: Array, suit: int) -> int:
	var count: int = 0
	for c in cards:
		if int(c.s) == suit and _hokm_rank_value(c) >= 11:
			count += 1
	return count

func _hokm_lead_score(card: Dictionary, level: int) -> float:
	var suit: int = int(card.s)
	var rank: int = _hokm_rank_value(card)
	var own_hand: Array = hokm_hands[1]
	var length: int = _hokm_suit_count(own_hand, suit)
	var strong_count: int = _hokm_high_cards_in_suit(own_hand, suit)
	var higher_in_hand: int = 0
	for other in own_hand:
		if int(other.s) == suit and _hokm_rank_value(other) > rank:
			higher_in_hand += 1
	var score: float = 0.0
	match level:
		2:
			score = -float(rank) + (2.0 if suit != hokm_trump else -5.0)
		3:
			score = float(length) * 5.0 - float(rank) * 0.65 + (3.0 if suit != hokm_trump else -5.0)
		4:
			score = float(length) * 4.5 + float(strong_count) * 2.5 - float(higher_in_hand) * 3.0
			score += 7.0 if higher_in_hand == 0 else 0.0
			score += -10.0 if suit == hokm_trump and length <= 2 else 0.0
		5, 6:
			# سطح‌های بالا کارت‌های برتر و طول خال را نگه می‌دارند و از خالِ بدون‌کارت حریف آگاه‌اند.
			score = float(length) * (4.0 + float(level) * 0.35) + float(strong_count) * 3.5
			score -= float(higher_in_hand) * (2.0 + float(level) * 0.35)
			if higher_in_hand == 0:
				score += 11.0 + float(level)
			if suit == hokm_trump:
				score -= 9.0 if length < 3 else 2.0
			if hokm_voids[0].has(suit) and suit != hokm_trump:
				score -= 10.0 + float(level) * 1.5 # حریف ممکن است حکم ببُرد
			if level >= 6 and suit != hokm_trump and length >= 4 and strong_count >= 2:
				score += 8.0 # ادامه‌ی خال قوی برای بیرون کشیدن حکم
		_:
			score = float(length) - float(rank) * 0.1
	return score

func _hokm_response_score(card: Dictionary, led_card: Dictionary, level: int) -> float:
	var wins: bool = _hokm_card_beats(card, led_card, hokm_led_suit, hokm_trump)
	var rank: int = _hokm_rank_value(card)
	var is_trump: bool = int(card.s) == hokm_trump
	var score: float = 0.0
	if wins:
		# بردن دست را ترجیح بده، ولی در صورت امکان حکم و کارت‌های بزرگ را حفظ کن.
		score = 120.0 - float(rank) * 2.0
		if is_trump:
			score -= 9.0 + float(level) * 2.0
		if int(card.s) == int(led_card.s):
			score += 5.0
	else:
		# اگر دست را نمی‌توان برد، ارزان‌ترین کارت را دور بریز؛ حکم را بی‌دلیل خرج نکن.
		score = -float(rank) * 1.8
		if is_trump:
			score -= 12.0 + float(level) * 2.5
		if int(card.s) == int(led_card.s):
			score += 3.0
	if level >= 5 and hokm_voids[0].has(int(card.s)) and is_trump:
		score -= 3.0 # حکم را برای خال‌بُری‌های مهم‌تر حفظ کن
	if level >= 6 and wins and int(card.s) == int(led_card.s) and rank >= 12:
		score -= 2.0 # در صورت امکان با کارت برنده‌ی ارزان‌تر، آس/شاه را نسوزان
	return score

func _hokm_cpu() -> void:
	if hokm_hands[1].is_empty() or hokm_game_over or hokm_turn != 1:
		return
	var level: int = clampi(hokm_difficulty, 1, 6)
	var legal_indices: Array[int] = []
	for i in hokm_hands[1].size():
		if _hokm_legal(1, hokm_hands[1][i]):
			legal_indices.append(i)
	if legal_indices.is_empty():
		return
	if level <= 1:
		_hokm_play(1, legal_indices[randi_range(0, legal_indices.size() - 1)])
		return
	var best_idx: int = legal_indices[0]
	var best_score: float = -INF
	var led_card: Dictionary = {}
	if hokm_trick.size() == 1:
		led_card = hokm_trick[0].c
	for i in legal_indices:
		var card: Dictionary = hokm_hands[1][i]
		var score: float
		if hokm_trick.size() == 1:
			score = _hokm_response_score(card, led_card, level)
		else:
			score = _hokm_lead_score(card, level)
		var noise: float = [0.0, 7.0, 4.5, 2.5, 1.1, 0.35][level - 1]
		score += randf_range(-noise, noise)
		if score > best_score:
			best_score = score
			best_idx = i
	_hokm_play(1, best_idx)

func _hokm_me() -> int:
	return app._my_seat()

func _hokm_rects() -> Array:
	return app._fan_rects(hokm_hands[_hokm_me()].size(), 58.0, 86.0, 762.0, 500.0, 6.0)

func _hokm_tap(p: Vector2) -> void:
	var me: int = _hokm_me()
	if hokm_game_over or hokm_turn != me or app._time - hokm_last_t < 0.9:
		return
	var i: int = app._fan_hit(_hokm_rects(), p)
	if i < 0:
		return
	if not _hokm_legal(me, hokm_hands[me][i]):
		app._show_toast("باید هم‌خالِ زمین بازی کنید.")
		return
	if app._net_on():
		app.rpc("_rpc_hokm_play", me, i)
	else:
		_hokm_play(me, i)

func _draw_hokm() -> void:
	var suit_cols := [app.TEXT, app.RED, app.RED, app.TEXT]
	var me: int = _hokm_me()
	var pa: Dictionary = app._pl("شما", app.BLUE, app._fa(hokm_scores[me]), hokm_turn == me and not hokm_game_over, true, "دست برده")
	var pb: Dictionary = app._pl("حریف", app.PINK, app._fa(hokm_scores[1 - me]), hokm_turn == 1 - me and not hokm_game_over, false, "دست برده")
	if pa.active:
		pa.sub = "نوبت شما"
	app._draw_hud("حکم", pa, pb)
	app._draw_ai_difficulty_chip(hokm_difficulty)
	var orr: Array = app._fan_rects(hokm_hands[1 - me].size(), 36.0, 52.0, 150.0, 240.0, 4.0)
	for r in orr:
		app._draw_card_back(r)
	var badge := Rect2(16, 150, 118, 40)
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
		var rr: Rect2 = slot_me if int(it.p) == me else slot_opp
		var won: bool = showing_last and int(it.p) == hokm_last_winner
		app._draw_card(rr, it.c, false, false, won)
	if showing_last:
		app._txt_c("برنده این دست: " + ("شما" if hokm_last_winner == me else "حریف"), Rect2(table.position.x, table.position.y + 4, table.size.x, 26), 13, app.ACCENT, true)
	app._txt_c("هنوز ۱۳ دست: " + app._fa(13 - hokm_hands[me].size()) + " / " + app._fa(13), Rect2(table.position.x, table.end.y - 30, table.size.x, 24), 12, Color(1, 1, 1, 0.4))
	var rects: Array = _hokm_rects()
	for i in rects.size():
		var c: Dictionary = hokm_hands[me][i]
		var ok: bool = hokm_turn == me and _hokm_legal(me, c)
		app._draw_card(rects[i], c, false, hokm_turn == me and not ok, false)
	if not hokm_game_over:
		app._hint("کارت بزنید تا بازی شود" if hokm_turn == me else "حریف در حال بازی…", 706, app.TEXT_DIM)
