extends "res://core/game_module.gd"
const HokmPresentationScript = preload("res://games/hokm/presentation.gd")
var _hokm_presentation = HokmPresentationScript.new()
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
			app._go_result()
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
	var sampled_opponent_hands: Array = []
	if level >= 5 and hokm_trick.is_empty():
		sampled_opponent_hands = _hokm_sample_opponent_hands(24 if level == 5 else 48)
	for i in legal_indices:
		var card: Dictionary = hokm_hands[1][i]
		var score: float
		if hokm_trick.size() == 1:
			score = _hokm_response_score(card, led_card, level)
		else:
			score = _hokm_lead_score(card, level)
			if level >= 5 and not sampled_opponent_hands.is_empty():
				var risk: float = _hokm_lead_beaten_probability(card, sampled_opponent_hands)
				score -= risk * (26.0 if level == 5 else 38.0)
		var noise: float = [0.0, 7.0, 4.5, 2.5, 0.7, 0.0][level - 1]
		score += randf_range(-noise, noise)
		if score > best_score:
			best_score = score
			best_idx = i
	_hokm_play(1, best_idx)


func _hokm_card_key(card: Dictionary) -> String:
	return "%d:%d" % [int(card.s), int(card.r)]

func _hokm_sample_opponent_hands(sample_count: int) -> Array:
	# Determinized samples improve lead selection without peeking at the real
	# opponent hand. Played cards and our current hand are removed from the pool.
	var known: Dictionary = {}
	for card in hokm_hands[1]:
		known[_hokm_card_key(card)] = true
	for card in hokm_seen_cards:
		known[_hokm_card_key(card)] = true
	var pool_template: Array = []
	for suit in range(4):
		if hokm_voids[0].has(suit):
			continue
		for rank in range(1, 14):
			var candidate: Dictionary = {"s": suit, "r": rank}
			if not known.has(_hokm_card_key(candidate)):
				pool_template.append(candidate)
	var hand_size: int = hokm_hands[0].size()
	if pool_template.size() < hand_size or hand_size <= 0:
		return []
	var samples: Array = []
	for sample_index in range(sample_count):
		var pool: Array = pool_template.duplicate(true)
		pool.shuffle()
		var sampled_hand: Array = []
		for index in range(hand_size):
			sampled_hand.append(pool[index])
		samples.append(sampled_hand)
	return samples

func _hokm_lead_beaten_probability(card: Dictionary, sampled_hands: Array) -> float:
	if sampled_hands.is_empty():
		return 0.0
	var beaten_count: int = 0
	for sampled_hand_value in sampled_hands:
		var sampled_hand: Array = sampled_hand_value
		var has_led_suit: bool = false
		for hidden_card in sampled_hand:
			if int(hidden_card.s) == int(card.s):
				has_led_suit = true
				break
		var can_beat: bool = false
		for hidden_card in sampled_hand:
			if has_led_suit and int(hidden_card.s) != int(card.s):
				continue
			if _hokm_card_beats(hidden_card, card, int(card.s), hokm_trump):
				can_beat = true
				break
		if can_beat:
			beaten_count += 1
	return float(beaten_count) / float(sampled_hands.size())

func _hokm_me() -> int:
	return app._my_seat()

func _hokm_rects() -> Array:
	return _hokm_presentation.hand_rects(app, self)

func _hokm_tap(p: Vector2) -> void:
	_hokm_presentation.handle_tap(app, self, p)

func _hokm_handle_card_index(index: int) -> void:
	var me: int = _hokm_me()
	if hokm_game_over or hokm_turn != me or app._time - hokm_last_t < 0.9:
		return
	if index < 0 or index >= hokm_hands[me].size():
		return
	if not _hokm_legal(me, hokm_hands[me][index]):
		app._show_toast("باید هم‌خالِ زمین بازی کنید.")
		return
	if app._net_on():
		app._send_game_action("_rpc_hokm_play", [me, index])
	else:
		_hokm_play(me, index)

func _draw_hokm() -> void:
	_hokm_presentation.render(app, self)
