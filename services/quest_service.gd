extends RefCounted
## Daily / weekly quests and permanent badges.
## Quests are shared by every player on the same Jalali day/week (deterministic pick), reward XP + a small amount of
## league points, and never punish absence: an unfinished quest simply expires.

const DAILY_POOL: Array = [
	{"id": "d_play3", "title": "۳ مسابقه کامل کن", "type": "matches", "target": 3, "xp": 40, "lp": 2, "online": false},
	{"id": "d_play5", "title": "۵ مسابقه کامل کن", "type": "matches", "target": 5, "xp": 80, "lp": 3, "online": false},
	{"id": "d_win2", "title": "۲ برد بگیر", "type": "wins", "target": 2, "xp": 50, "lp": 2, "online": false},
	{"id": "d_games2", "title": "در ۲ بازی مختلف مسابقه بده", "type": "distinct_games", "target": 2, "xp": 50, "lp": 2, "online": false},
	{"id": "d_hardcpu", "title": "یک برد مقابل CPU سطح ۴ یا بالاتر", "type": "hard_cpu_wins", "target": 1, "xp": 55, "lp": 3, "online": false},
	{"id": "d_streak2", "title": "۲ برد پشت‌سرهم", "type": "streak", "target": 2, "xp": 60, "lp": 3, "online": false},
	{"id": "d_human1", "title": "یک مسابقه‌ی آنلاین با انسان انجام بده", "type": "human_matches", "target": 1, "xp": 55, "lp": 2, "online": true},
	{"id": "d_humanwin", "title": "یک برد مقابل انسان آنلاین بگیر", "type": "human_wins", "target": 1, "xp": 70, "lp": 3, "online": true},
]
const WEEKLY_POOL: Array = [
	{"id": "w_win10", "title": "۱۰ برد در این هفته", "type": "wins", "target": 10, "xp": 250, "lp": 8, "online": false},
	{"id": "w_wingames4", "title": "در ۴ بازی مختلف برد بگیر", "type": "distinct_win_games", "target": 4, "xp": 300, "lp": 10, "online": false},
	{"id": "w_play25", "title": "۲۵ مسابقه کامل کن", "type": "matches", "target": 25, "xp": 260, "lp": 8, "online": false},
	{"id": "w_streak3", "title": "یک رشته‌ی ۳ بردی بساز", "type": "streak", "target": 3, "xp": 220, "lp": 6, "online": false},
	{"id": "w_human6", "title": "۶ مسابقه‌ی آنلاین با انسان", "type": "human_matches", "target": 6, "xp": 300, "lp": 10, "online": true},
]
const DAILY_COUNT := 3
const WEEKLY_COUNT := 2

# Mutually exclusive daily quests (never offer both "3 matches" and "5 matches").
const _EXCLUSIVE_TYPE_PAIRS: Array = [["d_play3", "d_play5"]]

static func fnv1a(text: String) -> int:
	var h: int = 2166136261
	for b in text.to_utf8_buffer():
		h = h ^ int(b)
		h = (h * 16777619) & 0xFFFFFFFF
	return h

## Deterministic shuffle (Fisher-Yates driven by an LCG seeded from the key).
static func _shuffled_indices(count: int, key: String) -> Array:
	var order: Array = range(count)
	var state: int = fnv1a(key)
	for i in range(count - 1, 0, -1):
		state = (state * 1103515245 + 12345) & 0x7FFFFFFF
		var j: int = state % (i + 1)
		var tmp: Variant = order[i]
		order[i] = order[j]
		order[j] = tmp
	return order

static func _make_instance(def: Dictionary) -> Dictionary:
	return {
		"id": str(def["id"]), "title": str(def["title"]), "type": str(def["type"]),
		"target": int(def["target"]), "progress": 0, "done": false,
		"xp": int(def["xp"]), "lp": int(def["lp"]), "online": bool(def["online"]), "seen": [],
	}

static func _pick(pool: Array, count: int, key: String) -> Array:
	var chosen: Array = []
	var online_count := 0
	for idx in _shuffled_indices(pool.size(), key):
		var def: Dictionary = pool[int(idx)]
		var clash := false
		for existing in chosen:
			for pair in _EXCLUSIVE_TYPE_PAIRS:
				if (str(existing["id"]) == pair[0] and str(def["id"]) == pair[1]) or (str(existing["id"]) == pair[1] and str(def["id"]) == pair[0]):
					clash = true
		# At most one quest that needs an online opponent, so offline players can always finish a full board.
		if bool(def["online"]) and online_count >= 1:
			clash = true
		if clash:
			continue
		chosen.append(_make_instance(def))
		if bool(def["online"]):
			online_count += 1
		if chosen.size() >= count:
			break
	return chosen

static func daily_for(day_id: String) -> Array:
	return _pick(DAILY_POOL, DAILY_COUNT, "daily:" + day_id)

static func weekly_for(week_id: String) -> Array:
	return _pick(WEEKLY_POOL, WEEKLY_COUNT, "weekly:" + week_id)

## Returns quests (new array) with progress applied. `completed` receives the quests that finished on this event.
## event: {"outcome","kind","difficulty","game_id","win_streak"}
static func apply_event(quests: Array, event: Dictionary, completed: Array) -> Array:
	var out: Array = []
	var outcome: String = str(event.get("outcome", ""))
	var kind: String = str(event.get("kind", ""))
	var difficulty: int = int(event.get("difficulty", 0))
	var game_id: String = str(event.get("game_id", ""))
	var streak: int = int(event.get("win_streak", 0))
	for raw in quests:
		var q: Dictionary = (raw as Dictionary).duplicate(true)
		if not bool(q.get("done", false)):
			var before: int = int(q.get("progress", 0))
			var progress: int = before
			var seen: Array = q.get("seen", [])
			match str(q.get("type", "")):
				"matches":
					progress += 1
				"wins":
					if outcome == "win":
						progress += 1
				"human_matches":
					if kind == "human_online":
						progress += 1
				"human_wins":
					if kind == "human_online" and outcome == "win":
						progress += 1
				"hard_cpu_wins":
					if kind == "cpu" and outcome == "win" and difficulty >= 4:
						progress += 1
				"distinct_games":
					if game_id != "" and not seen.has(game_id):
						seen.append(game_id)
					progress = seen.size()
				"distinct_win_games":
					if outcome == "win" and game_id != "" and not seen.has(game_id):
						seen.append(game_id)
					progress = seen.size()
				"streak":
					progress = maxi(progress, streak)
			q["seen"] = seen
			q["progress"] = mini(int(q["target"]), progress)
			if int(q["progress"]) >= int(q["target"]):
				q["done"] = true
				completed.append(q.duplicate(true))
		out.append(q)
	return out

# ---------------------------------------------------------------------------
# Badges (permanent, collectible)
# ---------------------------------------------------------------------------
const BADGES: Array = [
	{"id": "first_win", "name": "اولین برد", "desc": "اولین برد خودت را ثبت کن."},
	{"id": "wins_10", "name": "ده‌تایی", "desc": "۱۰ برد جمع کن."},
	{"id": "wins_50", "name": "پنجاه‌تایی", "desc": "۵۰ برد جمع کن."},
	{"id": "wins_250", "name": "غول مسابقات", "desc": "۲۵۰ برد جمع کن."},
	{"id": "streak_5", "name": "آتشین", "desc": "۵ برد پشت‌سرهم."},
	{"id": "giant_slayer", "name": "غول‌کش", "desc": "حریف انسانی را ببر که رتبه‌اش ۱۵۰ امتیاز بالاتر است."},
	{"id": "comeback", "name": "بازگشت", "desc": "بعد از ۳ باخت پشت‌سرهم یک برد بگیر."},
	{"id": "all_rounder", "name": "همه‌فن‌حریف", "desc": "در ۵ بازی مختلف برد بگیر."},
	{"id": "collector", "name": "کلکسیونر", "desc": "در همه‌ی بازی‌های پندار حداقل یک برد داشته باش."},
	{"id": "human_25", "name": "رقیب واقعی", "desc": "۲۵ مسابقه‌ی آنلاین با انسان انجام بده."},
	{"id": "marathon", "name": "ماراتن", "desc": "۱۰۰ مسابقه کامل کن."},
	{"id": "level_10", "name": "سطح ۱۰", "desc": "به سطح حساب ۱۰ برس."},
	{"id": "league_gold", "name": "لیگ طلا", "desc": "به لیگ طلا برس."},
	{"id": "league_platinum", "name": "لیگ پلاتین", "desc": "به لیگ پلاتین برس."},
	{"id": "league_diamond", "name": "لیگ الماس", "desc": "به لیگ الماس برس."},
	{"id": "league_master", "name": "لیگ مستر", "desc": "به لیگ مستر برس."},
	{"id": "league_legend", "name": "لیگ لجند", "desc": "به لیگ لجند برس."},
]

static func badge_def(id: String) -> Dictionary:
	for b in BADGES:
		if str(b["id"]) == id:
			return b
	return {}

## ctx: wins, matches, human_matches, best_streak, win_streak, win_games(int), game_count(int), upset(bool), comeback(bool),
## level(int), league(int). Returns the badge definitions that became unlocked.
static func evaluate_badges(owned: Array, ctx: Dictionary) -> Array:
	var gained: Array = []
	var checks: Dictionary = {
		"first_win": int(ctx.get("wins", 0)) >= 1,
		"wins_10": int(ctx.get("wins", 0)) >= 10,
		"wins_50": int(ctx.get("wins", 0)) >= 50,
		"wins_250": int(ctx.get("wins", 0)) >= 250,
		"streak_5": int(ctx.get("best_streak", 0)) >= 5,
		"giant_slayer": bool(ctx.get("upset", false)),
		"comeback": bool(ctx.get("comeback", false)),
		"all_rounder": int(ctx.get("win_games", 0)) >= 5,
		"collector": int(ctx.get("game_count", 99)) > 0 and int(ctx.get("win_games", 0)) >= int(ctx.get("game_count", 99)),
		"human_25": int(ctx.get("human_matches", 0)) >= 25,
		"marathon": int(ctx.get("matches", 0)) >= 100,
		"level_10": int(ctx.get("level", 1)) >= 10,
		"league_gold": int(ctx.get("league", 0)) >= 2,
		"league_platinum": int(ctx.get("league", 0)) >= 3,
		"league_diamond": int(ctx.get("league", 0)) >= 4,
		"league_master": int(ctx.get("league", 0)) >= 5,
		"league_legend": int(ctx.get("league", 0)) >= 7,
	}
	for id in checks.keys():
		if bool(checks[id]) and not owned.has(id):
			gained.append(badge_def(str(id)))
	return gained
