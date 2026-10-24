extends "res://core/game_module.gd"
## Mastermind with CPU play and real two-device LAN play.
## In LAN mode the host owns the secret; it is never sent to the guessing client.

const MastermindPresentationScript = preload("res://games/mastermind/presentation.gd")
var _mm_presentation = MastermindPresentationScript.new()

var mm_difficulty: int = 1
var mm_code_len: int = 4
var mm_color_count: int = 4
# Retained as a compatibility field; multiplayer is network-only, never hot-seat.
var mm_local_two_player: bool = false
# 0 = LAN host composing secret, 1 = guesser may submit, 2 = LAN client waiting for host,
# 3 = LAN host watching guesses, 4 = guess sent and awaiting authoritative response.
var mm_phase: int = 1
var mm_secret: Array = []
var mm_guesses: Array = []
var mm_cur: Array = []
var mm_slot: int = 0
var mm_turn_role: int = 0
var mm_game_over: bool = false
var mm_won: bool = false
var mm_filled: Array = []
var mm_turn: int = 0
var mm_winner: int = -1
var mm_online_race: bool = false
var mm_lan_race: bool = false
var mm_cpu_race: bool = false
var mm_cpu_racers: Array = []
var mm_cpu_race_started_msec: int = 0
var mm_online_progress: Array = []
var mm_race_finished: bool = false
var mm_race_status: String = ""

func reset_game() -> void:
	_reset_mastermind()

func _mm_blank_code() -> Array:
	var result: Array = []
	for i in range(mm_code_len):
		result.append(0)
	return result

func _mm_blank_filled() -> Array:
	var result: Array = []
	for i in range(mm_code_len):
		result.append(false)
	return result

# Feedback is position-mapped: 2 = exact match, 1 = correct colour in another
# position, 0 = no unmatched secret peg of that colour. Exact matches are claimed first.
func _mm_feedback(guess: Array) -> Array:
	var feedback: Array = []
	var secret_used: Array = []
	for i in range(mm_code_len):
		feedback.append(0)
		secret_used.append(false)
	for i in range(mm_code_len):
		if i < guess.size() and i < mm_secret.size() and guess[i] == mm_secret[i]:
			feedback[i] = 2
			secret_used[i] = true
	for i in range(mm_code_len):
		if feedback[i] == 2 or i >= guess.size():
			continue
		for j in range(mm_code_len):
			if secret_used[j] or j >= mm_secret.size():
				continue
			if guess[i] == mm_secret[j]:
				feedback[i] = 1
				secret_used[j] = true
				break
	return feedback

func _mm_evaluate(guess: Array) -> Array:
	var feedback: Array = _mm_feedback(guess)
	var black: int = 0
	var white: int = 0
	for value in feedback:
		if int(value) == 2:
			black += 1
		elif int(value) == 1:
			white += 1
	return [black, white]

func _reset_mastermind() -> void:
	var requested_cpu_race: bool = mm_cpu_race and app.vs_cpu and app.selected_game == "mastermind"
	mm_difficulty = clampi(mm_difficulty, 1, 6)
	# Higher difficulty increases both code length and available colours.
	mm_code_len = clampi(3 + mm_difficulty, 4, 9)
	mm_color_count = clampi(3 + mm_difficulty, 4, 9)
	mm_secret = []
	mm_guesses = []
	mm_cur = _mm_blank_code()
	mm_filled = _mm_blank_filled()
	mm_slot = 0
	mm_phase = 1
	mm_online_race = app.ws_match_active and app.selected_game == "mastermind"
	mm_lan_race = (not app.ws_match_active and app.multiplayer.multiplayer_peer != null and app.connected_players >= 2 and app.selected_game == "mastermind")
	mm_cpu_race = requested_cpu_race and not mm_online_race and not mm_lan_race
	if mm_online_race:
		# The online matchmaker stores the secret on the server only.
		mm_secret = []
		mm_phase = 1
	elif mm_lan_race:
		# In IP/LAN races, the host evaluates guesses. Other clients never receive the secret.
		if app.is_host:
			for i in range(mm_code_len):
				mm_secret.append(randi() % mm_color_count)
		mm_phase = 1
	elif app._net_on():
		mm_local_two_player = false
		mm_phase = 0 if app.is_host else 2
	else:
		for i in range(mm_code_len):
			mm_secret.append(randi() % mm_color_count)
	mm_game_over = false
	mm_won = false
	mm_turn = 0
	mm_winner = -1
	mm_online_progress = []
	mm_cpu_racers = []
	mm_cpu_race_started_msec = Time.get_ticks_msec()
	mm_race_finished = false
	mm_race_status = ""
	if mm_cpu_race:
		for seat in range(4):
			mm_cpu_racers.append({
				"seat": seat,
				"username": "شما" if seat == 0 else "CPU %s" % app._fa(seat),
				"attempts_used": 0,
				"latest_black": 0,
				"status": "active",
				"solve_ms": 0,
				"history": [],
				"tried": {},
				"next_guess_msec": mm_cpu_race_started_msec + (900 if seat == 0 else randi_range(1600, 2400))
			})
		_mm_cpu_race_refresh_progress()

func _mm_is_race_mode() -> bool:
	return mm_online_race or mm_lan_race or mm_cpu_race

func _mm_my_turn() -> bool:
	if mm_game_over:
		return false
	if _mm_is_race_mode():
		if mm_cpu_race and not mm_cpu_racers.is_empty() and str(mm_cpu_racers[0].get("status", "active")) != "active":
			return false
		return mm_phase == 1
	if app._net_on():
		return (app.is_host and mm_phase == 0) or (not app.is_host and mm_phase == 1)
	return mm_phase == 1

func _mm_slot_pos(i: int) -> Vector2:
	return _mm_presentation.slot_pos(app, self, i)

func _mm_color_pos(i: int) -> Vector2:
	return _mm_presentation.color_pos(app, self, i)

func _mm_pick(c: int) -> void:
	if mm_game_over or not _mm_my_turn() or c < 0 or c >= mm_color_count:
		return
	if mm_slot < 0 or mm_slot >= mm_code_len:
		mm_slot = 0
	mm_cur[mm_slot] = c
	mm_filled[mm_slot] = true
	for k in range(1, mm_code_len + 1):
		var idx: int = (mm_slot + k) % mm_code_len
		if not mm_filled[idx]:
			mm_slot = idx
			break

func _mm_pick_slot(i: int) -> void:
	if i >= 0 and i < mm_code_len and _mm_my_turn():
		mm_slot = i

func _mm_clear() -> void:
	if mm_game_over or not _mm_my_turn():
		return
	mm_cur = _mm_blank_code()
	mm_filled = _mm_blank_filled()
	mm_slot = 0

func _mm_all_filled() -> bool:
	if mm_filled.size() != mm_code_len:
		return false
	for f in mm_filled:
		if not f:
			return false
	return true

func _btns_mastermind() -> void:
	_mm_presentation.build_buttons(app, self)

func _draw_mastermind() -> void:
	_mm_presentation.render(app, self)

func _mm_code_key(code: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for value in code:
		parts.append(str(int(value)))
	return ",".join(parts)

func _mm_score_guess_for_secret(guess: Array, candidate_secret: Array) -> Array[int]:
	var black: int = 0
	var guess_counts: Dictionary = {}
	var secret_counts: Dictionary = {}
	for index in range(mm_code_len):
		var g: int = int(guess[index])
		var secret_value: int = int(candidate_secret[index])
		if g == secret_value:
			black += 1
		else:
			guess_counts[g] = int(guess_counts.get(g, 0)) + 1
			secret_counts[secret_value] = int(secret_counts.get(secret_value, 0)) + 1
	var white: int = 0
	for key in guess_counts.keys():
		white += mini(int(guess_counts[key]), int(secret_counts.get(key, 0)))
	return [black, white]

func _mm_cpu_candidate_consistent(candidate: Array, history: Array) -> bool:
	for old in history:
		var score: Array[int] = _mm_score_guess_for_secret(old.get("g", []), candidate)
		if score[0] != int(old.get("b", 0)) or score[1] != int(old.get("w", 0)):
			return false
	return true

func _mm_cpu_guess_partition_cost(guess: Array, candidates: Array) -> int:
	var buckets: Dictionary = {}
	var largest: int = 0
	for possible_secret in candidates:
		var score: Array[int] = _mm_score_guess_for_secret(guess, possible_secret)
		var key: String = "%d:%d" % [score[0], score[1]]
		buckets[key] = int(buckets.get(key, 0)) + 1
		largest = maxi(largest, int(buckets[key]))
	var squares: int = 0
	for value in buckets.values():
		squares += int(value) * int(value)
	return largest * 100000 + squares

func _mm_cpu_make_guess(racer: Dictionary) -> Array:
	var history: Array = racer.get("history", [])
	var tried: Dictionary = racer.get("tried", {})
	var level: int = clampi(mm_difficulty, 1, 6)
	var sample_budgets: Array[int] = [0, 80, 180, 350, 600, 950, 1300]
	var pool_limits: Array[int] = [0, 1, 1, 22, 36, 55, 75]
	var pool: Array = []
	var pool_keys: Dictionary = {}
	var require_consistency: bool = level >= 2
	for attempt in range(sample_budgets[level]):
		var candidate: Array = []
		for slot in range(mm_code_len):
			candidate.append(randi() % mm_color_count)
		var key: String = _mm_code_key(candidate)
		if tried.has(key) or pool_keys.has(key):
			continue
		if require_consistency and not _mm_cpu_candidate_consistent(candidate, history):
			continue
		pool_keys[key] = true
		pool.append(candidate)
		if pool.size() >= pool_limits[level]:
			break
	if pool.is_empty():
		for attempt in range(300):
			var fallback: Array = []
			for slot in range(mm_code_len):
				fallback.append(randi() % mm_color_count)
			var fallback_key: String = _mm_code_key(fallback)
			if not tried.has(fallback_key):
				return fallback
		return _mm_blank_code()
	if level >= 5 and pool.size() > 1:
		var best_guess: Array = pool[0]
		var best_cost: int = 2147483647
		for candidate_guess in pool:
			var cost: int = _mm_cpu_guess_partition_cost(candidate_guess, pool)
			if cost < best_cost:
				best_cost = cost
				best_guess = candidate_guess
		return best_guess.duplicate()
	return pool[randi() % pool.size()].duplicate()

func _mm_cpu_race_before(a: Dictionary, b: Dictionary) -> bool:
	var sa: String = str(a.get("status", "active"))
	var sb: String = str(b.get("status", "active"))
	var rank_order: Dictionary = {"solved": 0, "active": 1, "failed": 2}
	var ra: int = int(rank_order.get(sa, 3))
	var rb: int = int(rank_order.get(sb, 3))
	if ra != rb:
		return ra < rb
	if sa == "solved" and int(a.get("solve_ms", 0)) != int(b.get("solve_ms", 0)):
		return int(a.get("solve_ms", 0)) < int(b.get("solve_ms", 0))
	if int(a.get("latest_black", 0)) != int(b.get("latest_black", 0)):
		return int(a.get("latest_black", 0)) > int(b.get("latest_black", 0))
	if int(a.get("attempts_used", 0)) != int(b.get("attempts_used", 0)):
		return int(a.get("attempts_used", 0)) < int(b.get("attempts_used", 0))
	return int(a.get("seat", 0)) < int(b.get("seat", 0))

func _mm_cpu_race_refresh_progress() -> void:
	var progress: Array = mm_cpu_racers.duplicate(true)
	progress.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _mm_cpu_race_before(a, b))
	for index in range(progress.size()):
		var entry: Dictionary = progress[index]
		entry["rank"] = index + 1
		progress[index] = entry
	mm_online_progress = progress

func _mm_cpu_race_finish_if_complete() -> void:
	if not mm_cpu_race or mm_game_over or mm_cpu_racers.size() != 4:
		return
	for racer in mm_cpu_racers:
		if str(racer.get("status", "active")) == "active":
			return
	_mm_cpu_race_refresh_progress()
	mm_game_over = true
	mm_race_finished = true
	var top: Dictionary = mm_online_progress[0] if not mm_online_progress.is_empty() else {}
	mm_winner = int(top.get("seat", -1)) if str(top.get("status", "")) == "solved" else -1
	mm_won = mm_winner == 0
	mm_race_status = "نفر اول شدی!" if mm_won else ("مساوی" if mm_winner < 0 else "CPU %s زودتر کد را پیدا کرد" % app._fa(mm_winner))
	app._go_result(false)

func _mm_cpu_race_record_human_guess(guess: Array) -> void:
	if mm_game_over or mm_cpu_racers.size() != 4 or str(mm_cpu_racers[0].get("status", "active")) != "active":
		return
	if guess.size() != mm_code_len or mm_secret.size() != mm_code_len:
		return
	for colour in guess:
		if int(colour) < 0 or int(colour) >= mm_color_count:
			return
	var score: Array[int] = _mm_score_guess_for_secret(guess, mm_secret)
	var black: int = score[0]
	var white: int = score[1]
	var row: Dictionary = {"g": guess.duplicate(), "b": black, "w": white, "f": _mm_feedback(guess), "p": 0}
	mm_guesses.append(row)
	var racer: Dictionary = mm_cpu_racers[0]
	racer["attempts_used"] = int(racer.get("attempts_used", 0)) + 1
	racer["latest_black"] = black
	var history: Array = racer.get("history", [])
	history.append({"g": guess.duplicate(), "b": black, "w": white})
	racer["history"] = history
	if black == mm_code_len:
		racer["status"] = "solved"
		racer["solve_ms"] = maxi(1, Time.get_ticks_msec() - mm_cpu_race_started_msec)
	elif int(racer["attempts_used"]) >= 10:
		racer["status"] = "failed"
	mm_cpu_racers[0] = racer
	if str(racer.get("status", "active")) == "active":
		mm_cur = _mm_blank_code()
		mm_filled = _mm_blank_filled()
		mm_slot = 0
	else:
		mm_phase = 4
	_mm_cpu_race_refresh_progress()
	_mm_cpu_race_finish_if_complete()
	if not mm_game_over:
		app._build_playing_buttons()

func _mm_cpu_race_tick() -> void:
	if not mm_cpu_race or mm_game_over or mm_secret.size() != mm_code_len or mm_cpu_racers.size() != 4:
		return
	var now: int = Time.get_ticks_msec()
	for seat in range(1, 4):
		var racer: Dictionary = mm_cpu_racers[seat]
		if str(racer.get("status", "active")) != "active" or now < int(racer.get("next_guess_msec", now + 1000)):
			continue
		var guess: Array = _mm_cpu_make_guess(racer)
		var score: Array[int] = _mm_score_guess_for_secret(guess, mm_secret)
		var history: Array = racer.get("history", [])
		history.append({"g": guess.duplicate(), "b": score[0], "w": score[1]})
		racer["history"] = history
		var attempts: int = int(racer.get("attempts_used", 0)) + 1
		racer["attempts_used"] = attempts
		racer["latest_black"] = score[0]
		var tried: Dictionary = racer.get("tried", {})
		tried[_mm_code_key(guess)] = true
		racer["tried"] = tried
		if score[0] == mm_code_len:
			racer["status"] = "solved"
			racer["solve_ms"] = maxi(1, now - mm_cpu_race_started_msec)
		elif attempts >= 10:
			racer["status"] = "failed"
		else:
			var delay: int = 2700 - (mm_difficulty - 1) * 250
			racer["next_guess_msec"] = now + maxi(850, delay) + randi_range(0, 400)
		mm_cpu_racers[seat] = racer
		_mm_cpu_race_refresh_progress()
		_mm_cpu_race_finish_if_complete()
		app._rebuild_buttons()
		return


func _mm_submit() -> void:
	if mm_game_over or not _mm_all_filled() or not _mm_my_turn():
		return
	if mm_online_race:
		var guess_to_send: Array = mm_cur.duplicate()
		if app._ws_send_json({"type": "mastermind_guess", "guess": guess_to_send}):
			mm_phase = 4
			app._show_toast("حدس ثبت شد؛ منتظر نتیجه‌ی سرور…")
		else:
			app._show_toast("اتصال مسابقه قطع است؛ حدس ارسال نشد.")
		app._rebuild_buttons()
		return
	if mm_lan_race:
		var lan_guess: Array = mm_cur.duplicate()
		if app.is_host:
			app._mm_lan_process_guess(lan_guess, app.local_seat)
		else:
			mm_phase = 4
			app.rpc_id(1, "_rpc_mm_lan_submit", lan_guess, app.local_seat)
			app._show_toast("حدس ارسال شد؛ منتظر بازخورد هستید…")
			app._rebuild_buttons()
		return
	if app._net_on() and app.is_host and mm_phase == 0:
		# Never send the secret itself over the network.
		mm_secret = mm_cur.duplicate()
		mm_phase = 3
		mm_cur = _mm_blank_code()
		mm_filled = _mm_blank_filled()
		mm_slot = 0
		if app.ws_match_active:
			if not app._ws_send_json({"type": "mastermind_secret_ready", "code_length": mm_code_len, "color_count": mm_color_count}):
				app._show_toast("کد ثبت شد اما ارسال به حریف ناموفق بود؛ اتصال را بررسی کنید.")
		else:
			var client_id: int = -1
			for pid in app.peer_to_seat.keys():
				if int(app.peer_to_seat[pid]) == 1:
					client_id = int(pid)
					break
			if client_id >= 0:
				app.rpc_id(client_id, "_rpc_mm_secret_ready", mm_code_len, mm_color_count)
			else:
				app._show_toast("بازیکن مهمان پیدا نشد؛ اتصال را بررسی کنید.")
		app._rebuild_buttons()
		return
	if app._net_on() and not app.is_host and mm_phase == 1:
		mm_phase = 4
		if app.ws_match_active:
			if not app._ws_send_json({"type": "mastermind_guess", "guess": mm_cur.duplicate()}):
				mm_phase = 1
				app._show_toast("حدس ارسال نشد؛ اتصال را بررسی کنید.")
		else:
			app.rpc_id(1, "_rpc_mm_submit", mm_cur.duplicate(), 1)
		app._rebuild_buttons()
		return
	_mm_apply(mm_cur.duplicate(), 0)

func _draw_mm_online_sidebar() -> void:
	_mm_presentation.render_online_sidebar(app, self)

func _mm_online_feedback(message: Dictionary) -> void:
	if not mm_online_race:
		return
	_mm_accept_race_feedback(message)

func _mm_lan_feedback(message: Dictionary) -> void:
	if not mm_lan_race:
		return
	_mm_accept_race_feedback(message)

func _mm_accept_race_feedback(message: Dictionary) -> void:
	if mm_game_over:
		return
	var guess_value: Variant = message.get("guess", [])
	var feedback_value: Variant = message.get("feedback", [])
	if not (guess_value is Array) or not (feedback_value is Array):
		return
	if guess_value.size() != mm_code_len or feedback_value.size() != mm_code_len:
		return
	mm_guesses.append({
		"g": guess_value.duplicate(),
		"f": feedback_value.duplicate(),
		"b": int(message.get("black", 0)),
		"w": int(message.get("white", 0)),
		"p": app.local_seat
	})
	var solved: bool = bool(message.get("solved", false))
	var failed: bool = bool(message.get("failed", false))
	mm_cur = _mm_blank_code()
	mm_filled = _mm_blank_filled()
	mm_slot = 0
	mm_phase = 1
	if solved or failed:
		mm_game_over = true
		mm_won = solved
		mm_winner = app.local_seat if solved else -1
		mm_race_status = "کد را پیدا کردی!" if solved else "فرصت حدس تمام شد"
		# Keep the live leaderboard visible until every racer has finished.
		app._show_toast(mm_race_status)
		app._build_playing_buttons()
	else:
		app._show_toast("بازخورد دریافت شد؛ حدس بعدی را ثبت کن.")
		app._build_playing_buttons()

func _mm_apply(g: Array, player: int) -> void:
	if mm_cpu_race:
		_mm_cpu_race_record_human_guess(g)
		return
	if mm_game_over or g.size() != mm_code_len or mm_secret.size() != mm_code_len:
		return
	for colour in g:
		if int(colour) < 0 or int(colour) >= mm_color_count:
			return
	var feedback: Array = _mm_feedback(g)
	var black: int = 0
	var white: int = 0
	for val in feedback:
		if int(val) == 2:
			black += 1
		elif int(val) == 1:
			white += 1
	mm_guesses.append({"g": g.duplicate(), "b": black, "w": white, "f": feedback, "p": player})
	if black == mm_code_len:
		mm_game_over = true
		mm_winner = player
	elif mm_guesses.size() >= 10:
		mm_game_over = true
		mm_winner = 0 if app._net_on() else (1 if app.vs_cpu else -1)
	else:
		mm_cur = _mm_blank_code()
		mm_filled = _mm_blank_filled()
		mm_slot = 0
	mm_won = mm_winner == app._my_seat() if mm_game_over else false
	if mm_game_over:
		app._go_result(false)
	else:
		app._build_playing_buttons()
	if app._net_on() and app.is_host:
		if app.ws_match_active:
			app._ws_send_json({"type": "mastermind_sync", "guesses": mm_guesses, "is_over": mm_game_over, "winner": mm_winner})
		else:
			for pid in app.peer_to_seat.keys():
				if int(app.peer_to_seat[pid]) == 1:
					app.rpc_id(int(pid), "_rpc_mm_sync_state", mm_guesses, mm_game_over, mm_winner)
					break
