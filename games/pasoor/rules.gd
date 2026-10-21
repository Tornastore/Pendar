extends "res://core/game_module.gd"
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
	app.state = State.RESULT
	app._build_result_buttons()

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
	# برای کارت دورریختنی، تخمین می‌زند چند رتبه‌ی احتمالی می‌توانند از میز بگیرند.
	# این محاسبه از کارت‌های مخفی حریف استفاده نمی‌کند.
	pas_table.append(card)
	var risk: float = 0.0
	for rank in range(1, 14):
		var candidate: Dictionary = {"r": rank, "s": 1}
		var captures: Array = _pas_find_captures(candidate)
		if captures.size() > 0:
			var max_taken: int = 0
			for cap in captures:
				max_taken = maxi(max_taken, cap.size())
			risk += 1.0 + minf(float(max_taken), 5.0) * 0.15
	pas_table.pop_back()
	return risk

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
		# سطوح آسان خطای بیشتری دارند؛ سطح استادتمام تقریباً بدون نویز انتخاب می‌کند.
		var noise: float = [0.0, 16.0, 9.0, 5.0, 2.5, 1.0][level - 1]
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
	return app._fan_rects(pas_hands[_pas_me()].size(), 66.0, 96.0, 776.0, 500.0, 8.0)

func _pas_table_rects() -> Array:
	var n: int = pas_table.size()
	var res: Array = []
	if n <= 14:
		var r1: int = mini(7, n)
		var a: Array = app._fan_rects(r1, 56.0, 80.0, 244.0, 480.0, 6.0)
		res.append_array(a)
		if n > 7:
			res.append_array(app._fan_rects(n - 7, 56.0, 80.0, 334.0, 480.0, 6.0))
	else:
		res = app._fan_rects(n, 56.0, 80.0, 286.0, 480.0, 6.0)
	return res

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
	if not _pas_my_turn():
		return
	var i: int = app._fan_hit(_pas_hand_rects(), p)
	if i < 0:
		pas_selected = -1
		return
	if pas_selected == i:
		_pas_confirm()
	else:
		pas_selected = i

func _btns_pasoor() -> void:
	if not _pas_my_turn() or pas_selected < 0:
		return
	var me: int = _pas_me()
	if pas_selected >= pas_hands[me].size():
		return
	var card: Dictionary = pas_hands[me][pas_selected]
	var cap: Array = _pas_find_captures(card)
	if cap.size() > 0:
		var best: Array = _pas_best_capture(card)
		app._add_btn(Rect2(60, 710, app.VIEW_W - 120, 54), "گرفتن %s کارت" % app._fa(best.size() + 1), _pas_confirm, true, app.GREEN, "solid", "check", "pas_go")
	else:
		app._add_btn(Rect2(60, 710, app.VIEW_W - 120, 54), "گذاشتن روی میز", _pas_confirm, true, app.ACCENT, "solid", "play", "pas_go")

func _draw_pasoor() -> void:
	var me: int = _pas_me()
	var opp: int = 1 - me
	var pa: Dictionary = app._pl("شما", app.BLUE, app._fa(pas_match_scores[me]), pas_turn == me and not pas_game_over, true, "سور: " + app._fa(pas_surs[me]))
	var pb: Dictionary = app._pl("حریف", app.PINK, app._fa(pas_match_scores[opp]), pas_turn == opp and not pas_game_over, false, "سور: " + app._fa(pas_surs[opp]))
	if pas_turn == me and not pas_game_over:
		pa.sub = "نوبت شما"
	if pas_turn == opp and not pas_game_over:
		pb.sub = "نوبت حریف"
	app._draw_hud("پاسور (چهاربرگ)", pa, pb)
	app._draw_ai_difficulty_chip(pas_difficulty)
	var orr: Array = app._fan_rects(pas_hands[opp].size(), 40.0, 58.0, 150.0, 300.0, 6.0)
	for r in orr:
		app._draw_card_back(r)
	var info := Rect2(16, 150, 100, 34)
	app._panel(info, Color(0, 0, 0, 0.3), 17)
	app._txt_c("دسته: " + app._fa(pas_deck.size()), info, 13, app.TEXT_DIM, true)
	var felt := Rect2(16, 204, app.VIEW_W - 32, 232)
	app._panel(felt, Color(0.07, 0.24, 0.20), 26, Color(0.25, 0.65, 0.5, 0.4), 1.5, 18, 6)
	app._txt_c("میز (" + app._fa(pas_table.size()) + ")", Rect2(felt.position.x, felt.position.y + 4, felt.size.x, 30), 13, Color(1, 1, 1, 0.45), true)
	var hl: Array = []
	var me_hand: Array = pas_hands[me]
	if pas_selected >= 0 and pas_selected < me_hand.size() and _pas_my_turn():
		hl = _pas_best_capture(me_hand[pas_selected])
	var trs: Array = _pas_table_rects()
	for i in trs.size():
		var r: Rect2 = trs[i]
		app._draw_card(r, pas_table[i], false, false, i in hl)
	if pas_table.size() == 0:
		app._txt_c("میز خالی است", Rect2(felt.position.x, felt.position.y + 80, felt.size.x, 60), 16, Color(1, 1, 1, 0.3))
	var cap_me := Rect2(16, 446, 240, 30)
	app._panel(cap_me, Color(app.GREEN.r, app.GREEN.g, app.GREEN.b, 0.12), 15)
	app._txt_c("کارت‌های گرفته‌شده شما: " + app._fa(pas_captured[me].size()), cap_me, 12, app.GREEN, true)
	var cap_op := Rect2(app.VIEW_W - 16 - 240, 446, 240, 30)
	app._panel(cap_op, Color(app.RED.r, app.RED.g, app.RED.b, 0.12), 15)
	app._txt_c("حریف: " + app._fa(pas_captured[opp].size()), cap_op, 12, app.RED, true)
	var rects: Array = _pas_hand_rects()
	var dimmed: bool = false
	for i in rects.size():
		var r: Rect2 = rects[i]
		var sel: bool = (i == pas_selected)
		if sel:
			r.position.y -= 20.0
		app._draw_card(r, me_hand[i], sel, false, false)
	if not pas_game_over:
		if _pas_my_turn():
			if pas_selected < 0:
				app._hint("یک کارت انتخاب کنید", 740, app.ACCENT)
		else:
			app._hint("حریف در حال بازی…", 740, app.TEXT_DIM)
