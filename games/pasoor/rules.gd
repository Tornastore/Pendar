extends "res://core/game_module.gd"
const PasoorPresentationScript = preload("res://games/pasoor/presentation.gd")
var _pas_presentation = PasoorPresentationScript.new()
## Rule engine and authoritative state for pasoor.

# ---------- Game-owned state ----------
var pas_deck: Array = []
var pas_hands: Array = [[], []]
var pas_table: Array = []
var pas_captured: Array = [[], []]
var pas_turn: int = 0
var pas_game_over: bool = false
var pas_winner: int = -1
var pas_selected: int = -1
var pas_scores: Array = [0, 0]
var pas_match_scores: Array = [0, 0]
var pas_surs: Array = [0, 0]
var pas_last_capturer: int = -1
var pas_deals_done: int = 0
var pas_is_last_deal: bool = false
var pas_difficulty: int = 3 # 1 random .. 6 tactical capture and exposure evaluation

func reset_game() -> void:
	_reset_pasoor()

func _pas_pip(c: Dictionary) -> int:
	# فقط برای جمع ۱۱: A=1 ... 10=10  (شاه و بی‌بی و سرباز در جمع شرکت نمی‌کنند)
	if c.r >= 1 and c.r <= 10:
		return c.r
	return -1

func _pas_is_jack(c: Dictionary) -> bool:
	return c.r == 11

func _pas_is_queen(c: Dictionary) -> bool:
	return c.r == 12

func _pas_is_king(c: Dictionary) -> bool:
	return c.r == 13

func _pas_card_str(c: Dictionary) -> String:
	return app.PAS_RANKS[c.r] + app.PAS_SUITS[c.s]

func _reset_pasoor() -> void:
	pas_deck = []
	for s in 4:
		for r in range(1, 14):
			pas_deck.append({"r": r, "s": s})
	pas_deck.shuffle()
	pas_hands = [[], []]
	pas_table = []
	pas_captured = [[], []]
	pas_turn = 0
	pas_game_over = false
	pas_winner = -1
	pas_selected = -1
	pas_scores = [0, 0]
	pas_surs = [0, 0]
	pas_last_capturer = -1
	pas_deals_done = 0
	pas_is_last_deal = false
	# پخش اولیه: ۴ به هر نفر + ۴ میز (اگر سرباز روی میز بود عوض می‌شود)
	for i in 4:
		pas_hands[0].append(pas_deck.pop_back())
		pas_hands[1].append(pas_deck.pop_back())
	_pas_deal_table()

func _pas_deal_table() -> void:
	pas_table.clear()
	var tries := 0
	while pas_table.size() < 4 and pas_deck.size() > 0 and tries < 20:
		var c: Dictionary = pas_deck.pop_back()
		if _pas_is_jack(c):
			pas_deck.push_front(c)  # برگردان و دوباره
			pas_deck.shuffle()
			tries += 1
			continue
		pas_table.append(c)
	# اگر هنوز سرباز ماند، نادیده بگیر (نادر)

func _pas_find_captures(card: Dictionary) -> Array:
	# برمی‌گرداند لیست بهترین/ممکن ایندکس‌های میز برای گرفتن
	var results: Array = []
	var n: int = pas_table.size()
	if n == 0:
		return results

	# ۱) شاه فقط شاه
	if _pas_is_king(card):
		for i in n:
			if _pas_is_king(pas_table[i]):
				results.append([i])
		return results
	# ۲) بی‌بی فقط بی‌بی
	if _pas_is_queen(card):
		for i in n:
			if _pas_is_queen(pas_table[i]):
				results.append([i])
		return results
	# ۳) سرباز: همه غیر از شاه و بی‌بی
	if _pas_is_jack(card):
		var all_non: Array = []
		for i in n:
			if not _pas_is_king(pas_table[i]) and not _pas_is_queen(pas_table[i]):
				all_non.append(i)
		if all_non.size() > 0:
			results.append(all_non)
		return results

	# ۴) عدد A–۱۰: زیرمجموعه‌هایی که جمع pip + pip کارت = ۱۱
	var my_pip: int = _pas_pip(card)
	if my_pip < 0:
		return results
	# فقط کارت‌های عددی میز را در نظر بگیر
	var num_indices: Array = []
	for i in n:
		if _pas_pip(pas_table[i]) > 0:
			num_indices.append(i)
	var m: int = num_indices.size()
	if m == 0 or m > 10:
		return results
	for mask in range(1, 1 << m):
		var subset: Array = []
		var sm := 0
		for j in m:
			if mask & (1 << j):
				var idx: int = num_indices[j]
				subset.append(idx)
				sm += _pas_pip(pas_table[idx])
		if sm + my_pip == 11:
			results.append(subset)
	return results

func _pas_best_capture(card: Dictionary) -> Array:
	var caps: Array = _pas_find_captures(card)
	if caps.size() == 0:
		return []
	# ترجیح: بیشترین کارت، بعد پاسور/آس/سرباز
	var best: Array = caps[0]
	var best_sc: int = -1
	for sub in caps:
		var sc: int = sub.size() * 3
		for idx in sub:
			var c: Dictionary = pas_table[idx]
			if c.r == 10 and c.s == 2:
				sc += 6
			if c.r == 1:
				sc += 2
			if c.r == 11:
				sc += 2
			if c.s == 0:
				sc += 1
		if sc > best_sc:
			best_sc = sc
			best = sub
	return best

func _pas_must_capture(card: Dictionary) -> bool:
	return _pas_find_captures(card).size() > 0

func _pas_play(p: int, hand_idx: int, capture_indices: Array) -> void:
	if hand_idx < 0 or hand_idx >= pas_hands[p].size():
		return
	var card: Dictionary = pas_hands[p][hand_idx]
	# اگر می‌تواند بگیرد ولی indices خالی است → اجبار به گرفتن بهترین
	if capture_indices.size() == 0 and _pas_must_capture(card):
		capture_indices = _pas_best_capture(card)
	pas_hands[p].remove_at(hand_idx)
	pas_selected = -1

	var did_capture := capture_indices.size() > 0
	var was_jack := _pas_is_jack(card)

	if did_capture:
		pas_captured[p].append(card)
		var sorted_idx: Array = capture_indices.duplicate()
		sorted_idx.sort()
		sorted_idx.reverse()
		for idx in sorted_idx:
			if idx >= 0 and idx < pas_table.size():
				pas_captured[p].append(pas_table[idx])
				pas_table.remove_at(idx)
		pas_last_capturer = p
		# سور؟
		if pas_table.size() == 0 and not was_jack and not pas_is_last_deal:
			pas_surs[p] += 1
			app._show_toast("سور! +۵")
	else:
		pas_table.append(card)

	pas_turn = 1 - p

	# پایان دست؟
	if pas_hands[0].size() == 0 and pas_hands[1].size() == 0:
		_pas_after_hands_empty()

func _pas_after_hands_empty() -> void:
	pas_deals_done += 1
	if pas_deck.size() >= 8:
		# پخش دوباره ۴تایی (میز باقی می‌ماند)
		for i in 4:
			pas_hands[0].append(pas_deck.pop_back())
			pas_hands[1].append(pas_deck.pop_back())
		if pas_deck.size() < 8:
			pas_is_last_deal = true
	elif pas_deck.size() > 0:
		while pas_deck.size() > 0:
			pas_hands[0].append(pas_deck.pop_back())
			if pas_deck.size() > 0:
				pas_hands[1].append(pas_deck.pop_back())
		pas_is_last_deal = true
	else:
		# پایان کامل دست — کارت‌های باقی‌مانده میز به آخرین گیرنده
		if pas_last_capturer >= 0:
			for c in pas_table:
				pas_captured[pas_last_capturer].append(c)
		pas_table.clear()
		_pas_end_hand()

func _pas_end_hand() -> void:
	pas_scores = [0, 0]
	for p in 2:
		var clubs := 0
		for c in pas_captured[p]:
			if c.s == 0:
				clubs += 1
			if c.r == 1:
				pas_scores[p] += 1          # آس
			if c.r == 11:
				pas_scores[p] += 1          # سرباز
			if c.r == 10 and c.s == 2:
				pas_scores[p] += 3          # ۱۰ خشت
			if c.r == 2 and c.s == 0:
				pas_scores[p] += 2          # ۲ گشنیز
		# هفت خاج
		if clubs >= 7:
			pas_scores[p] += 7
		# سور
		pas_scores[p] += pas_surs[p] * 5

	pas_match_scores[0] += pas_scores[0]
	pas_match_scores[1] += pas_scores[1]

	if pas_scores[0] > pas_scores[1]:
		pas_winner = 0
	elif pas_scores[1] > pas_scores[0]:
		pas_winner = 1
	else:
		pas_winner = -1

	# بررسی رسیدن به ۶۲
	if pas_match_scores[0] >= app.PAS_TARGET or pas_match_scores[1] >= app.PAS_TARGET:
		if pas_match_scores[0] > pas_match_scores[1]:
			pas_winner = 0
		elif pas_match_scores[1] > pas_match_scores[0]:
			pas_winner = 1

	pas_game_over = true
	app._go_result()

func _pas_card_point_value(card: Dictionary) -> float:
	# ارزش تقریبی امتیازی کارت در چهاربرگ.
	var value: float = 0.0
	if int(card.r) == 1 or int(card.r) == 11:
		value += 1.0
	if int(card.r) == 10 and int(card.s) == 2:
		value += 3.0
	if int(card.r) == 2 and int(card.s) == 0:
		value += 2.0
	if int(card.s) == 0:
		value += 0.25
	return value

func _pas_exposure_cost(card: Dictionary) -> float:
	# Evaluate the table after a discard; don't consult the hidden opponent hand.
	pas_table.append(card)
	var risk: float = _pas_table_capture_risk()
	pas_table.pop_back()
	return risk

func _pas_table_capture_risk() -> float:
	var risk: float = 0.0
	for rank in range(1, 14):
		var candidate: Dictionary = {"r": rank, "s": 1}
		var captures: Array = _pas_find_captures(candidate)
		if captures.size() > 0:
			var max_taken: int = 0
			for cap in captures:
				max_taken = maxi(max_taken, cap.size())
			# More cards available to sweep, especially a large set, raise exposure risk.
			risk += 1.0 + minf(float(max_taken), 5.0) * 0.15
	return risk

func _pas_future_table_risk(card: Dictionary, captures: Array) -> float:
	var original_table: Array = pas_table
	var future_table: Array = pas_table.duplicate(true)
	if captures.is_empty():
		future_table.append(card)
	else:
		var descending: Array = captures.duplicate()
		descending.sort()
		descending.reverse()
		for raw_index in descending:
			var table_index: int = int(raw_index)
			if table_index >= 0 and table_index < future_table.size():
				future_table.remove_at(table_index)
	pas_table = future_table
	var result: float = _pas_table_capture_risk()
	pas_table = original_table
	return result

func _pas_cpu_move() -> void:
	if pas_hands[1].is_empty() or pas_game_over:
		return
	var level: int = clampi(pas_difficulty, 1, 6)
	var best_idx: int = randi_range(0, pas_hands[1].size() - 1)
	var best_cap: Array = _pas_best_capture(pas_hands[1][best_idx])
	if level <= 1:
		# سطح خیلی آسان، حرکت را عمداً تصادفی انتخاب می‌کند.
		_pas_play(1, best_idx, best_cap)
		return

	var best_score: float = -INF
	for i in pas_hands[1].size():
		var card: Dictionary = pas_hands[1][i]
		var cap: Array = _pas_best_capture(card)
		var score: float = 0.0
		if cap.size() > 0:
			# گرفتن کارت‌ها، گرفتن کارت‌های امتیازی و ساختن سور ارزشمند است.
			score += float(cap.size()) * (2.5 + float(level) * 0.65)
			for idx in cap:
				if idx >= 0 and idx < pas_table.size():
					score += _pas_card_point_value(pas_table[idx]) * (1.0 + float(level) * 0.3)
			score += _pas_card_point_value(card) * (1.0 + float(level) * 0.35)
			if cap.size() == pas_table.size() and not _pas_is_jack(card) and not pas_is_last_deal:
				score += 7.0 + float(level) * 2.0 # سور
			# در سطوح بالاتر، کارت‌های ارزشمند را فقط وقتی خرج کن که بازدهی داشته باشند.
			if level >= 5 and card.r == 11 and cap.size() < 2:
				score -= 1.5
		else:
			# دورریختن کارتِ امتیازی یا کارتِ آسان‌گرفتنی برای حریف بد است.
			score = -0.5 - _pas_card_point_value(card) * (0.6 + float(level) * 0.25)
			if level >= 4:
				score -= _pas_exposure_cost(card) * (0.45 + float(level) * 0.42)
			if level >= 6 and card.s == 0:
				score -= 0.8 # حفظ کنترل خاج برای امتیاز هفت خاج
		if level >= 5:
			# Compare the resulting table, not only the immediate capture. A move is
			# penalized if it leaves a high-probability capture/sweep for the next turn.
			var future_risk: float = _pas_future_table_risk(card, cap)
			score -= future_risk * (1.1 if level == 5 else 1.9)
		# Lower levels stay varied; Master/Grandmaster should be reproducible.
		var noise: float = [0.0, 16.0, 9.0, 5.0, 0.45, 0.0][level - 1]
		score += randf_range(-noise, noise)
		if score > best_score:
			best_score = score
			best_idx = i
			best_cap = cap
	_pas_play(1, best_idx, best_cap)

func _pas_me() -> int:
	return 0 if app.vs_cpu else app.local_seat

func _pas_my_turn() -> bool:
	return pas_turn == _pas_me() and not pas_game_over

func _pas_hand_rects() -> Array:
	return _pas_presentation.hand_rects(app, self)

func _pas_table_rects() -> Array:
	return _pas_presentation.table_rects(app, self)

func _pas_confirm() -> void:
	var me: int = _pas_me()
	if pas_selected < 0 or pas_selected >= pas_hands[me].size() or not _pas_my_turn():
		return
	var i: int = pas_selected
	var cap: Array = _pas_best_capture(pas_hands[me][i])
	if app._net_on():
		app._send_game_action("_rpc_pas_play", [me, i, cap])
	else:
		_pas_play(me, i, cap)

func _pas_tap(p: Vector2) -> void:
	_pas_presentation.handle_tap(app, self, p)

func _pas_handle_hand_index(index: int) -> void:
	if not _pas_my_turn():
		return
	if index < 0:
		pas_selected = -1
		return
	if pas_selected == index:
		_pas_confirm()
	else:
		pas_selected = index

func _btns_pasoor() -> void:
	_pas_presentation.build_buttons(app, self)

func _draw_pasoor() -> void:
	_pas_presentation.render(app, self)
