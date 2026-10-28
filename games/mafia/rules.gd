extends "res://core/game_module.gd"
## Classic Mafia. UI reveals only the local player's role and their own detective feedback.
const PresentationScript = preload("res://games/mafia/presentation.gd")
var _presentation = PresentationScript.new()

const ROLE_MAFIA := "mafia"
const ROLE_DETECTIVE := "detective"
const ROLE_DOCTOR := "doctor"
const ROLE_CITIZEN := "citizen"

var mafia_player_count: int = 8
var mafia_difficulty: int = 3
var mafia_roles: Array[String] = []
var mafia_alive: Array[bool] = []
var mafia_revealed: Array[bool] = []
var mafia_phase: String = "night"
var mafia_round: int = 1
var mafia_game_over: bool = false
var mafia_winner_team: int = -1 # 0 Mafia, 1 town
var mafia_day_votes: Dictionary = {}
var mafia_night_actions: Dictionary = {}
var mafia_vote_history: Array = []
var mafia_suspicion: Array[float] = []
var mafia_ai_intel: Dictionary = {}
var mafia_private_note: String = ""
var mafia_last_event: String = ""
var mafia_last_eliminated: int = -1
var mafia_status: String = ""
var mafia_action_label: String = ""
var mafia_role_names: Dictionary = {
	"mafia": "مافیا",
	"detective": "کارآگاه",
	"doctor": "دکتر",
	"citizen": "شهروند",
}

func reset_game() -> void:
	_reset_mafia()

func _reset_mafia() -> void:
	mafia_player_count = clampi(mafia_player_count, 6, 12)
	mafia_roles.clear()
	mafia_alive.clear()
	mafia_revealed.clear()
	mafia_day_votes.clear()
	mafia_night_actions.clear()
	mafia_vote_history.clear()
	mafia_suspicion.clear()
	mafia_ai_intel.clear()
	mafia_private_note = ""
	mafia_last_event = ""
	mafia_last_eliminated = -1
	mafia_phase = "night"
	mafia_round = 1
	mafia_game_over = false
	mafia_winner_team = -1
	var mafia_count: int = 1 if mafia_player_count == 6 else (2 if mafia_player_count <= 9 else 3)
	var roles: Array[String] = []
	for _i in range(mafia_count):
		roles.append(ROLE_MAFIA)
	roles.append(ROLE_DETECTIVE)
	roles.append(ROLE_DOCTOR)
	while roles.size() < mafia_player_count:
		roles.append(ROLE_CITIZEN)
	roles.shuffle()
	mafia_roles = roles
	for _i in range(mafia_player_count):
		mafia_alive.append(true)
		mafia_revealed.append(false)
		mafia_suspicion.append(0.0)
	mafia_status = "شب اول؛ نقش و اقدام مخصوص خود را بررسی کنید."
	mafia_action_label = ""
	if app != null:
		app._rebuild_buttons()

func _mafia_my_seat() -> int:
	return 0 if app.vs_cpu else app.local_seat

func _mafia_is_alive(seat: int) -> bool:
	return seat >= 0 and seat < mafia_alive.size() and bool(mafia_alive[seat])

func _mafia_alive_count() -> int:
	var count: int = 0
	for alive in mafia_alive:
		if alive:
			count += 1
	return count

func _mafia_count_role(role: String) -> int:
	var count: int = 0
	for seat in range(mafia_roles.size()):
		if _mafia_is_alive(seat) and mafia_roles[seat] == role:
			count += 1
	return count

func _mafia_local_role() -> String:
	var seat: int = _mafia_my_seat()
	return str(mafia_roles[seat]) if seat >= 0 and seat < mafia_roles.size() else ROLE_CITIZEN

func _mafia_local_needs_action() -> bool:
	var seat: int = _mafia_my_seat()
	if not _mafia_is_alive(seat) or mafia_game_over:
		return false
	if mafia_phase == "day":
		return not mafia_day_votes.has(seat)
	if mafia_phase == "night":
		if mafia_roles[seat] not in [ROLE_MAFIA, ROLE_DOCTOR, ROLE_DETECTIVE]:
			return false
		return not mafia_night_actions.has(seat)
	return false

func _mafia_action_allowed(seat: int, kind: String, target: int) -> bool:
	if mafia_game_over or not _mafia_is_alive(seat) or target < 0 or target >= mafia_player_count or not _mafia_is_alive(target):
		return false
	if mafia_phase == "day":
		return kind == "vote" and not mafia_day_votes.has(seat) and target != seat
	if mafia_phase == "night":
		if mafia_night_actions.has(seat):
			return false
		match mafia_roles[seat]:
			ROLE_MAFIA: return kind == "kill" and target != seat and mafia_roles[target] != ROLE_MAFIA
			ROLE_DOCTOR: return kind == "protect"
			ROLE_DETECTIVE: return kind == "inspect" and target != seat
	return false

func _mafia_submit_action(kind: String, target: int, seat_override: int = -1) -> void:
	var seat: int = _mafia_my_seat() if seat_override < 0 else seat_override
	if not _mafia_action_allowed(seat, kind, target):
		return
	if app._net_on():
		app._send_game_action("_rpc_mafia_action", [seat, kind, target])
	else:
		_mafia_apply_action(seat, kind, target)

func _mafia_apply_action(seat: int, kind: String, target: int) -> void:
	if not _mafia_action_allowed(seat, kind, target):
		return
	if mafia_phase == "day" and kind == "vote":
		mafia_day_votes[seat] = target
		mafia_vote_history.append({"round": mafia_round, "voter": seat, "target": target})
		mafia_status = "رأی ثبت شد؛ منتظر رأی بقیه هستیم (%s/%s)" % [app._fa(mafia_day_votes.size()), app._fa(_mafia_alive_count())]
		_mafia_resolve_day_if_ready()
	elif mafia_phase == "night":
		mafia_night_actions[seat] = {"kind": kind, "target": target}
		if kind == "inspect" and seat == _mafia_my_seat():
			mafia_private_note = "نتیجهٔ بررسی: %s %s است." % [str(_mafia_player_name(target)), "عضو مافیاست" if mafia_roles[target] == ROLE_MAFIA else "مافیا نیست"]
		if kind == "inspect" and app.vs_cpu:
			if not mafia_ai_intel.has(seat):
				mafia_ai_intel[seat] = {}
			mafia_ai_intel[seat][target] = mafia_roles[target] == ROLE_MAFIA
		mafia_status = "اقدام شب ثبت شد؛ منتظر نقش‌های دیگر هستیم."
		_mafia_resolve_night_if_ready()
	if app != null:
		app._rebuild_buttons()

func _mafia_resolve_day_if_ready() -> void:
	if mafia_phase != "day" or mafia_day_votes.size() < _mafia_alive_count():
		return
	var counts: Dictionary = {}
	for value in mafia_day_votes.values():
		counts[int(value)] = int(counts.get(int(value), 0)) + 1
	var highest: int = 0
	var leaders: Array[int] = []
	for target in counts.keys():
		var count: int = int(counts[target])
		if count > highest:
			highest = count
			leaders = [int(target)]
		elif count == highest:
			leaders.append(int(target))
	var eliminated: int = leaders[0] if leaders.size() == 1 else -1
	if eliminated >= 0:
		mafia_alive[eliminated] = false
		mafia_revealed[eliminated] = true
		mafia_last_eliminated = eliminated
		mafia_last_event = "%s از رأی روز حذف شد؛ نقش او %s بود." % [_mafia_player_name(eliminated), _mafia_role_label(mafia_roles[eliminated])]
		var votes_for_eliminated: Array[int] = []
		for voter in mafia_day_votes.keys():
			if int(mafia_day_votes[voter]) == eliminated:
				votes_for_eliminated.append(int(voter))
		for voter in votes_for_eliminated:
			if mafia_roles[eliminated] == ROLE_MAFIA:
				mafia_suspicion[voter] = maxf(0.0, mafia_suspicion[voter] - 0.55)
			else:
				mafia_suspicion[voter] += 0.65
	else:
		mafia_last_event = "رأی برابر شد؛ کسی از شهر حذف نشد."
	if _mafia_check_winner():
		return
	mafia_phase = "night"
	mafia_round += 1
	mafia_day_votes.clear()
	mafia_night_actions.clear()
	mafia_status = "شب %s؛ نقش‌های ویژه اقدام کنند." % app._fa(mafia_round)
	if app != null:
		app._rebuild_buttons()

func _mafia_resolve_night_if_ready() -> void:
	if mafia_phase != "night":
		return
	var required: Array[int] = []
	for seat in range(mafia_player_count):
		if _mafia_is_alive(seat) and mafia_roles[seat] in [ROLE_MAFIA, ROLE_DOCTOR, ROLE_DETECTIVE]:
			required.append(seat)
	for seat in required:
		if not mafia_night_actions.has(seat):
			return
	var kill_votes: Dictionary = {}
	var protected_target: int = -1
	for seat in mafia_night_actions.keys():
		var action: Dictionary = mafia_night_actions[seat]
		var kind: String = str(action.get("kind", ""))
		var target: int = int(action.get("target", -1))
		if kind == "kill":
			kill_votes[target] = int(kill_votes.get(target, 0)) + 1
		elif kind == "protect":
			protected_target = target
	var victim: int = -1
	var highest: int = 0
	var tied: bool = false
	for target in kill_votes.keys():
		var votes: int = int(kill_votes[target])
		if votes > highest:
			highest = votes
			victim = int(target)
			tied = false
		elif votes == highest:
			tied = true
	if tied:
		victim = -1
	if victim >= 0 and victim != protected_target and _mafia_is_alive(victim):
		mafia_alive[victim] = false
		mafia_revealed[victim] = true
		mafia_last_eliminated = victim
		mafia_last_event = "%s در شب کشته شد؛ نقش او %s بود." % [_mafia_player_name(victim), _mafia_role_label(mafia_roles[victim])]
	else:
		mafia_last_eliminated = -1
		mafia_last_event = "شب بدون حذف گذشت؛ دکتر هدف مافیا را نجات داد یا مافیا به توافق نرسید."
	if _mafia_check_winner():
		return
	mafia_phase = "day"
	mafia_day_votes.clear()
	mafia_night_actions.clear()
	mafia_status = "روز %s؛ پس از بحث، به یک مظنون رأی دهید." % app._fa(mafia_round)
	if app != null:
		app._rebuild_buttons()

func _mafia_check_winner() -> bool:
	var mafia_count: int = _mafia_count_role(ROLE_MAFIA)
	var town_count: int = _mafia_alive_count() - mafia_count
	if mafia_count <= 0:
		mafia_game_over = true
		mafia_winner_team = 1
		mafia_status = "همهٔ اعضای مافیا حذف شدند؛ شهروندان پیروز شدند."
	elif mafia_count >= town_count:
		mafia_game_over = true
		mafia_winner_team = 0
		mafia_status = "تعداد مافیا به شهروندان باقی‌مانده رسید؛ مافیا پیروز شد."
	else:
		return false
	if app != null:
		app._go_result(_mafia_local_team_won())
		app._rebuild_buttons()
	return true

func _mafia_local_team_won() -> bool:
	var role: String = _mafia_local_role()
	return (role == ROLE_MAFIA and mafia_winner_team == 0) or (role != ROLE_MAFIA and mafia_winner_team == 1)

func _mafia_ai_target(seat: int, action_kind: String) -> int:
	var candidates: Array[int] = []
	for target in range(mafia_player_count):
		if not _mafia_is_alive(target):
			continue
		if action_kind != "protect" and target == seat:
			continue
		if action_kind == "kill" and mafia_roles[target] == ROLE_MAFIA:
			continue
		if action_kind == "vote" and mafia_roles[seat] == ROLE_MAFIA and mafia_roles[target] == ROLE_MAFIA:
			continue
		if action_kind == "inspect" and mafia_ai_intel.has(seat) and (mafia_ai_intel[seat] as Dictionary).has(target):
			continue
		candidates.append(target)
	if candidates.is_empty():
		return -1
	var level: int = clampi(mafia_difficulty, 1, 6)
	# The doctor should protect the most likely target of the previous day's vote.
	# Day resolution increments mafia_round before the following night, so use round-1.
	if action_kind == "protect" and level >= 3:
		var previous_round: int = mafia_round - 1
		var vote_counts: Dictionary = {}
		for history_entry in mafia_vote_history:
			if int(history_entry.get("round", -1)) != previous_round:
				continue
			var voted_target: int = int(history_entry.get("target", -1))
			if _mafia_is_alive(voted_target):
				vote_counts[voted_target] = int(vote_counts.get(voted_target, 0)) + 1
		var recent_target: int = -1
		var recent_count: int = 0
		for target_key in vote_counts.keys():
			var count: int = int(vote_counts[target_key])
			if count > recent_count:
				recent_count = count
				recent_target = int(target_key)
		if recent_target >= 0 and candidates.has(recent_target):
			return recent_target
	# Levels change evidence use and uncertainty, not just a cosmetic random range.
	var noise_by_level: Array[float] = [4.2, 3.0, 2.1, 1.15, 0.35, 0.0]
	var best: int = int(candidates[0])
	var best_score: float = -INF
	for target in candidates:
		var suspicion: float = float(mafia_suspicion[target])
		var score: float = 0.0
		match action_kind:
			"vote":
				if mafia_roles[seat] == ROLE_MAFIA:
					# Mafia try to keep suspicion off themselves and their teammates.
					score = -suspicion
				else:
					# A detective's confirmed result is evidence, not a guess. Every
					# difficulty follows it; stronger levels also use accumulated votes.
					var confirmed: bool = false
					if mafia_ai_intel.has(seat):
						var intel: Dictionary = mafia_ai_intel[seat]
						if intel.has(target):
							confirmed = true
							score = 10000.0 if bool(intel[target]) else -10000.0
					if not confirmed:
						score = suspicion
			"inspect":
				# Investigate the strongest unresolved public suspicion first.
				score = suspicion + (float(mafia_vote_history.size()) * 0.001 if level >= 5 else 0.0)
			"kill":
				# Kill a relatively trusted town member rather than conveniently
				# removing the person already likely to be voted out.
				score = -suspicion
			"protect":
				# If there is no useful public vote pattern, favor a confirmed safe
				# defensive choice with some uncertainty at low levels.
				score = suspicion
		if level < 6:
			score += randf_range(-noise_by_level[level - 1], noise_by_level[level - 1])
		if score > best_score:
			best_score = score
			best = target
	return best

func _mafia_cpu_tick() -> void:
	if not app.vs_cpu or mafia_game_over:
		return
	if mafia_phase == "day":
		for seat in range(1, mafia_player_count):
			if not _mafia_is_alive(seat) or mafia_day_votes.has(seat):
				continue
			var target: int = _mafia_ai_target(seat, "vote")
			if target >= 0:
				_mafia_apply_action(seat, "vote", target)
	elif mafia_phase == "night":
		for seat in range(1, mafia_player_count):
			if not _mafia_is_alive(seat) or mafia_night_actions.has(seat):
				continue
			var kind: String = ""
			match mafia_roles[seat]:
				ROLE_MAFIA: kind = "kill"
				ROLE_DOCTOR: kind = "protect"
				ROLE_DETECTIVE: kind = "inspect"
				_: continue
			var target: int = _mafia_ai_target(seat, kind)
			if target >= 0:
				_mafia_apply_action(seat, kind, target)

func _mafia_player_name(seat: int) -> String:
	if seat == _mafia_my_seat():
		return "شما"
	if seat >= 0 and seat < mafia_player_count:
		return "بازیکن %s" % app._fa(seat + 1)
	return "بازیکن ناشناس"

func _mafia_role_label(role: String) -> String:
	return str(mafia_role_names.get(role, "شهروند"))

func _mafia_tap(point: Vector2) -> void:
	_presentation.handle_tap(app, self, point)

func _draw_mafia() -> void:
	_presentation.render(app, self)

func _btns_mafia() -> void:
	_presentation.build_buttons(app, self)
