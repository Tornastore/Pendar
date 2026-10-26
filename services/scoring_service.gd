extends RefCounted
## Pendar League scoring (schema v3).
##
## Four separate numbers, each with its own job:
##   1. League points (LP) per game  -> that game's league, title and mastery badge.
##   2. League points (LP) overall   -> the main league, title, season rewards and quests (resets softly every Jalali month).
##   3. Skill rating (MMR) per game + overall -> matchmaking only; changed by real human matches (online queue) only.
##   4. XP / level / mastery          -> lifetime progression that never goes down, so every match gives something.
## CPU / LAN practice earns reduced LP by difficulty, but only up to the top of Gold; higher leagues need real opponents
## and a minimum skill rating. See docs/SCORING_AND_LEAGUES_FA.md for the full design and tuning table.
const LeagueScript = preload("res://services/league_service.gd")
const QuestScript = preload("res://services/quest_service.gd")

const SCORE_PATH := "user://pendar_scores.cfg"
const LEGACY_SCORE_PATH := "user://mind_bastion_scores.cfg" # One-time migration for existing players.
const SCHEMA_VERSION := 3

# ----- base results (before multipliers) -----
const WIN_PTS := 30
const DRAW_PTS := 6
const LOSS_PTS := -18

# ----- skill rating -----
const INITIAL_RATING := 1000
const MIN_RATING := 100
const MAX_RATING := 3000
const CALIBRATION_MATCHES := 10

# ----- modes -----
const HUMAN_ONLINE_MULTIPLIER := 1.0
const HUMAN_LAN_MULTIPLIER := 0.45 # direct Wi-Fi/IP games are friendly: no MMR, reduced LP (anti win-trading)
const CPU_DIFFICULTY_MULTIPLIERS: Array[float] = [0.10, 0.18, 0.30, 0.45, 0.62, 0.80]
const CPU_XP_MULTIPLIERS: Array[float] = [0.35, 0.45, 0.60, 0.75, 0.90, 1.00]

## weight = depth/length of the game; k = how fast MMR moves (less for luck-heavy games).
const GAME_PROFILES := {
	"chess": {"weight": 1.30, "k": 1.00},
	"quoridor": {"weight": 1.20, "k": 1.00},
	"abalone": {"weight": 1.20, "k": 1.00},
	"blockace": {"weight": 1.15, "k": 1.00},
	"othello12": {"weight": 1.15, "k": 1.00},
	"quarto": {"weight": 1.10, "k": 1.00},
	"pentago": {"weight": 1.05, "k": 1.00},
	"gobblet": {"weight": 1.05, "k": 1.00},
	"othello": {"weight": 1.00, "k": 1.00},
	"mastermind": {"weight": 1.00, "k": 0.90},
	"hokm": {"weight": 0.95, "k": 0.85},
	"backgammon": {"weight": 0.95, "k": 0.85},
	"domino": {"weight": 0.90, "k": 0.80},
	"pasoor": {"weight": 0.90, "k": 0.80},
	"uno": {"weight": 0.85, "k": 0.70},
}

# ----- reward shaping -----
const SHORT_MATCH_SECONDS := 90.0       # human wins/draws faster than this are scaled down (resign-trading guard)
const SHORT_MATCH_FLOOR := 0.25
const LONG_MATCH_SECONDS := 1800.0      # +25% for deep games, capped
const STREAK_STEP := 0.10
const STREAK_MAX_STEPS := 4             # up to x1.40
const FIRST_WIN_OF_DAY_MULTIPLIER := 1.5
const COMEBACK_LOSS_STREAK := 2         # third straight loss onward costs half
const COMEBACK_MULTIPLIER := 0.5
const FORFEIT_WIN_MULTIPLIER := 0.6
const STREAK_MIN_CPU_LEVEL := 3         # wins vs CPU level 1-2 neither extend nor break a win streak
const PRACTICE_HINT_MIN_WINS := 3       # wins at one CPU level needed before it says something about your skill
## Beating the CPU in a game nudges the *first* online matches of that game toward stronger opponents (it never changes MMR).
const PRACTICE_RATING_HINT := {3: 1040, 4: 1100, 5: 1180, 6: 1250}
const PRACTICE_HINT_FADE_MATCHES := 8
const ONBOARDING_MATCHES := 12          # first matches ever earn double positive LP so the first promotion happens in session one
const ONBOARDING_MULTIPLIER := 2.0
const REPEAT_OPPONENT_FACTORS: Array[float] = [1.0, 1.0, 1.0, 0.6, 0.4, 0.2]
const TEMPO_XP_MIN_SECONDS := 30.0
const MAX_HISTORY := 300
const MAX_RIVALS := 40
const MAX_SEASON_HISTORY := 12

var player_name: String = "بازیکن"
var global_rating: int = INITIAL_RATING
var global_rated_matches: int = 0
var global_lifetime_points: int = 0
var global_season_points: int = 0
var current_season_id: String = ""
var xp: int = 0
var win_streak: int = 0
var loss_streak: int = 0
var best_streak: int = 0
var season_peak_points: int = 0
var season_counts: Dictionary = {"matches": 0, "wins": 0, "draws": 0, "losses": 0, "human": 0}
var badges: Array = []
var season_history: Array = []
var last_report: Dictionary = {}
var report_unseen: bool = false
var rivals: Dictionary = {}
var pending_match: Dictionary = {}
var daily: Dictionary = {"day": "", "first_win": false, "opp": {}}
var quests_daily: Array = []
var quests_weekly: Array = []
var quest_week_id: String = ""
var game_stats: Dictionary = {}
var seen_rules: Dictionary = {}
var music_on: bool = true

## Test hooks: a fixed clock and a switch to keep unit tests from touching user:// files.
var clock_override: float = -1.0
var persist: bool = true
var score_path: String = SCORE_PATH
var _season_dirty: bool = false

func now() -> float:
	return clock_override if clock_override >= 0.0 else Time.get_unix_time_from_system()

# ---------------------------------------------------------------------------
# Small pure helpers
# ---------------------------------------------------------------------------
static func expected_score(my_rating: int, opponent_rating: int, players: int = 2) -> float:
	var n: int = maxi(2, players)
	return 1.0 / (1.0 + float(n - 1) * pow(10.0, float(opponent_rating - my_rating) / 400.0))

static func game_weight(game_id: String) -> float:
	return float(GAME_PROFILES.get(game_id, {"weight": 1.0})["weight"])

static func game_k_scale(game_id: String) -> float:
	return float(GAME_PROFILES.get(game_id, {"k": 1.0})["k"])

static func _fa(s: String) -> String:
	var out := ""
	for i in s.length():
		var c: int = s.unicode_at(i)
		out += String.chr(0x06F0 + c - 48) if c >= 48 and c <= 57 else (("٫") if s[i] == "." else s[i])
	return out

static func factor_text(f: float) -> String:
	var r: float = snappedf(f, 0.01)
	if absf(r - roundf(r)) < 0.001:
		return "×" + _fa(str(int(roundf(r))))
	return "×" + _fa(str(r))

static func _result_base(outcome: String) -> int:
	match outcome:
		"win": return WIN_PTS
		"draw": return DRAW_PTS
		_: return LOSS_PTS

static func _actual_result(outcome: String) -> float:
	match outcome:
		"win": return 1.0
		"draw": return 0.5
		_: return 0.0

static func _is_human(kind: String) -> bool:
	return kind == "human_online" or kind == "human_lan"

func _mode_multiplier(kind: String, difficulty: int) -> float:
	match kind:
		"human_online": return HUMAN_ONLINE_MULTIPLIER
		"human_lan": return HUMAN_LAN_MULTIPLIER
		"cpu": return CPU_DIFFICULTY_MULTIPLIERS[clampi(difficulty, 1, 6) - 1]
	return 0.0

func _mode_label(kind: String, difficulty: int) -> String:
	match kind:
		"human_online": return "حریف انسان آنلاین"
		"human_lan": return "بازی شبکه‌ی محلی"
		"cpu": return "CPU سطح " + _fa(str(clampi(difficulty, 1, 6)))
	return "حالت"

static func duration_multiplier(duration_seconds: float, kind: String = "cpu") -> float:
	if duration_seconds <= 0.0:
		return 1.0 # unknown duration: neutral
	if _is_human(kind) and duration_seconds < SHORT_MATCH_SECONDS:
		return clampf(duration_seconds / SHORT_MATCH_SECONDS, SHORT_MATCH_FLOOR, 1.0)
	return 1.0 + 0.25 * (clampf(duration_seconds, 0.0, LONG_MATCH_SECONDS) / LONG_MATCH_SECONDS)

static func elo_delta(rating: int, opponent_rating: int, outcome: String, rated_matches: int, k_scale: float = 1.0, players: int = 2) -> int:
	var opp: int = clampi(opponent_rating if opponent_rating > 0 else rating, MIN_RATING, MAX_RATING)
	var expected: float = expected_score(rating, opp, players)
	var k: float = (32.0 if rated_matches < CALIBRATION_MATCHES else 24.0) * k_scale
	return roundi(k * (_actual_result(outcome) - expected))

# ---------------------------------------------------------------------------
# Stats containers
# ---------------------------------------------------------------------------
func _empty_game_stats() -> Dictionary:
	return {
		"wins": 0, "draws": 0, "losses": 0,
		"points": 0, "season_points": 0,
		"rating": INITIAL_RATING, "rated_matches": 0,
		"cpu_wins": 0, "cpu_draws": 0, "cpu_losses": 0,
		"human_wins": 0, "human_draws": 0, "human_losses": 0,
		"xp": 0, "best_streak": 0,
		"cpu_wins_by_level": [0, 0, 0, 0, 0, 0],
		"history": [],
	}

func _normalize_stats(raw: Variant) -> Dictionary:
	var stats: Dictionary = (raw as Dictionary).duplicate(true) if typeof(raw) == TYPE_DICTIONARY else _empty_game_stats()
	var template: Dictionary = _empty_game_stats()
	for key in template.keys():
		if not stats.has(key):
			stats[key] = template[key]
	if typeof(stats.get("history", [])) != TYPE_ARRAY:
		stats["history"] = []
	stats["season_points"] = maxi(0, int(stats.get("season_points", 0)))
	if typeof(stats.get("cpu_wins_by_level", [])) != TYPE_ARRAY or (stats["cpu_wins_by_level"] as Array).size() != 6:
		stats["cpu_wins_by_level"] = [0, 0, 0, 0, 0, 0]
	return stats

func ensure_game_stats(game_ids: Array) -> void:
	for game_id in game_ids:
		var id := str(game_id)
		game_stats[id] = _normalize_stats(game_stats.get(id, {}))
	_roll_clock_if_needed()

func _game(game_id: String) -> Dictionary:
	if not game_stats.has(game_id):
		game_stats[game_id] = _empty_game_stats()
	return _normalize_stats(game_stats[game_id])

# ---------------------------------------------------------------------------
# Ladder views
# ---------------------------------------------------------------------------
func global_tier() -> Dictionary:
	return LeagueScript.tier_for_points(global_season_points)

func game_tier(game_id: String) -> Dictionary:
	var stats: Dictionary = game_stats.get(game_id, {})
	return LeagueScript.tier_for_points(int(stats.get("season_points", 0)), LeagueScript.GAME_LADDER_SCALE)

func skill_tier() -> Dictionary:
	return skill_tier_for(global_rating)

## Permanent skill title (MMR). Kept separate from the monthly league so veterans keep a visible "true skill" badge.
static func skill_tier_for(rating: int) -> Dictionary:
	var steps: Array = [[850, "تازه‌وارد"], [1050, "آماتور"], [1200, "نیمه‌حرفه‌ای"], [1350, "حرفه‌ای"], [1500, "نخبه"], [1650, "استاد"], [1850, "استادبزرگ"]]
	for s in steps:
		if rating < int(s[0]):
			return {"name": str(s[1]), "rating": rating}
	return {"name": "افسانه", "rating": rating}

func level() -> Dictionary:
	return LeagueScript.level_info(xp)

func game_mastery(game_id: String) -> Dictionary:
	return LeagueScript.mastery_info(int(game_stats.get(game_id, {}).get("xp", 0)))

func game_rating(game_id: String) -> int:
	return int(game_stats.get(game_id, {}).get("rating", INITIAL_RATING))

## Rating used to find opponents. A brand-new game leans on your overall rating; after ~8 ranked matches the game's own
## rating fully takes over. This is how the overall score affects games you have barely played.
func match_rating(game_id: String) -> int:
	var stats: Dictionary = game_stats.get(game_id, {})
	var n: int = int(stats.get("rated_matches", 0))
	var w: float = clampf(float(n) / 8.0, 0.35, 1.0)
	var base: int = roundi(w * float(int(stats.get("rating", INITIAL_RATING))) + (1.0 - w) * float(global_rating))
	var hint: int = practice_hint(game_id)
	if hint > base and n < PRACTICE_HINT_FADE_MATCHES:
		base += roundi(float(hint - base) * 0.6 * (1.0 - float(n) / float(PRACTICE_HINT_FADE_MATCHES)))
	return base

## Skill hint from CPU practice in this game: the strongest CPU level you have beaten at least 3 times (0 = none yet).
func practice_hint(game_id: String) -> int:
	var by_level: Array = game_stats.get(game_id, {}).get("cpu_wins_by_level", [])
	var best := 0
	for i in range(mini(by_level.size(), 6)):
		if int(by_level[i]) >= PRACTICE_HINT_MIN_WINS:
			best = i + 1
	return int(PRACTICE_RATING_HINT.get(best, 0))

## Suggested CPU level for the player's current strength in this game (1..6).
func recommended_cpu_level(game_id: String) -> int:
	var r: int = match_rating(game_id)
	var edges: Array[int] = [920, 990, 1060, 1140, 1260]
	for i in range(edges.size()):
		if r < edges[i]:
			return i + 1
	return 6

func total_matches() -> int:
	var total := 0
	for stats in game_stats.values():
		total += int(stats.get("wins", 0)) + int(stats.get("draws", 0)) + int(stats.get("losses", 0))
	return total

func total_wins_losses() -> Array:
	var wins := 0
	var draws := 0
	var losses := 0
	for stats in game_stats.values():
		wins += int(stats.get("wins", 0))
		draws += int(stats.get("draws", 0))
		losses += int(stats.get("losses", 0))
	return [wins, losses, draws]

func current_month_points(game_id: String = "") -> int:
	_roll_clock_if_needed()
	if _season_dirty:
		save_scores()
	if game_id.is_empty():
		return global_season_points
	return int(game_stats.get(game_id, {}).get("season_points", 0))

func points_in_period(game_id: String, days: int) -> int:
	if not game_stats.has(game_id):
		return 0
	var cutoff: float = now() - days * 86400.0
	var total := 0
	for entry in game_stats[game_id].get("history", []):
		if float(entry.get("t", 0)) >= cutoff:
			total += int(entry.get("game_delta", entry.get("delta", 0)))
	return total

func season_label() -> String:
	return LeagueScript.season_label(current_season_id)

func season_days_left() -> int:
	return LeagueScript.days_left_in_season(now())

# ---------------------------------------------------------------------------
# Clock: season / day / week rollover
# ---------------------------------------------------------------------------
func _roll_clock_if_needed() -> void:
	var t: float = now()
	var season_now: String = LeagueScript.season_id_at(t)
	if current_season_id.is_empty() or not LeagueScript.is_valid_season_id(current_season_id):
		# Fresh install or legacy (Gregorian) season id: adopt the Jalali season without wiping anyone's points.
		current_season_id = season_now
		global_season_points = maxi(0, global_season_points)
		season_peak_points = maxi(season_peak_points, global_season_points)
		_season_dirty = true
	elif current_season_id != season_now:
		_rollover_season(season_now)
	var day_now: String = LeagueScript.day_id_at(t)
	if str(daily.get("day", "")) != day_now:
		daily = {"day": day_now, "first_win": false, "opp": {}, "quests": QuestScript.daily_for(day_now)}
		_season_dirty = true
	elif not daily.has("quests"):
		daily["quests"] = QuestScript.daily_for(day_now)
	quests_daily = daily["quests"]
	var week_now: String = LeagueScript.week_id_at(t)
	if quest_week_id != week_now or quests_weekly.is_empty():
		quest_week_id = week_now
		quests_weekly = QuestScript.weekly_for(week_now)
		_season_dirty = true

## Call regularly while the app stays open (web tabs live for days). Returns true when the day, week or season changed.
func refresh_clock() -> bool:
	var before: String = "%s|%s|%s" % [current_season_id, str(daily.get("day", "")), quest_week_id]
	_roll_clock_if_needed()
	var after: String = "%s|%s|%s" % [current_season_id, str(daily.get("day", "")), quest_week_id]
	if before != after:
		save_scores()
	return before != after

func _rollover_season(new_id: String) -> void:
	var final_tier: Dictionary = LeagueScript.tier_for_points(global_season_points)
	var best_game := ""
	var best_pts := -1
	for id in game_stats.keys():
		var sp: int = int(game_stats[id].get("season_points", 0))
		if sp > best_pts:
			best_pts = sp
			best_game = str(id)
	var peak_tier: Dictionary = LeagueScript.tier_for_points(maxi(season_peak_points, global_season_points))
	var carry: int = LeagueScript.carry_over_points(global_season_points)
	last_report = {
		"season": current_season_id, "label": LeagueScript.season_label(current_season_id),
		"points": global_season_points, "tier_label": str(final_tier["label"]), "tier_name": str(final_tier["name"]),
		"title": str(final_tier["title"]), "peak_label": str(peak_tier["label"]), "peak_league": int(peak_tier["league"]),
		"matches": int(season_counts.get("matches", 0)), "wins": int(season_counts.get("wins", 0)),
		"draws": int(season_counts.get("draws", 0)), "losses": int(season_counts.get("losses", 0)),
		"human": int(season_counts.get("human", 0)), "best_game": best_game, "best_game_points": maxi(0, best_pts),
		"carry": carry, "new_season": new_id,
	}
	season_history.push_front(last_report.duplicate(true))
	if season_history.size() > MAX_SEASON_HISTORY:
		season_history = season_history.slice(0, MAX_SEASON_HISTORY)
	report_unseen = int(season_counts.get("matches", 0)) > 0
	global_season_points = carry
	season_peak_points = carry
	season_counts = {"matches": 0, "wins": 0, "draws": 0, "losses": 0, "human": 0}
	for key in game_stats.keys():
		var stats: Dictionary = _normalize_stats(game_stats[key])
		stats["season_points"] = LeagueScript.carry_over_points(int(stats["season_points"]))
		game_stats[key] = stats
	current_season_id = new_id
	_season_dirty = true

func acknowledge_season_report() -> void:
	report_unseen = false
	_season_dirty = true
	save_scores()

# ---------------------------------------------------------------------------
# League-point maths (pure given state)
# ---------------------------------------------------------------------------
## Computes LP for one result. `p` keys: outcome, kind, difficulty, game_id, my_rating, opp_rating, duration, players,
## win_streak, loss_streak, first_win_today, repeat_count, forfeit, abandoned.
## Returns {"lp": int, "chips": Array[{key,label,factor,text}], "duration_factor": float}.
func compute_lp(p: Dictionary) -> Dictionary:
	var outcome: String = str(p.get("outcome", "loss"))
	var kind: String = str(p.get("kind", "cpu"))
	var difficulty: int = int(p.get("difficulty", 3))
	var game_id: String = str(p.get("game_id", ""))
	var players: int = maxi(2, int(p.get("players", 2)))
	var total: float = float(_result_base(outcome))
	var chips: Array = []
	var mode_factor: float = _mode_multiplier(kind, difficulty)
	total *= mode_factor
	chips.append(_chip("mode", _mode_label(kind, difficulty), mode_factor))
	var gw: float = game_weight(game_id)
	total *= gw
	if absf(gw - 1.0) > 0.001:
		chips.append(_chip("game", "ضریب بازی", gw))
	# Opponent strength: only meaningful in 1v1 against a human whose rating we know.
	var opp_rating: int = int(p.get("opp_rating", -1))
	if kind == "human_online" and players == 2 and opp_rating > 0:
		var e: float = expected_score(int(p.get("my_rating", INITIAL_RATING)), opp_rating, 2)
		var f: float = clampf(0.6 + 0.8 * ((1.0 - e) if outcome != "loss" else e), 0.6, 1.4)
		total *= f
		if absf(f - 1.0) >= 0.05:
			var label := ""
			if outcome == "loss":
				label = "باخت به حریف ضعیف‌تر" if f > 1.0 else "باخت به حریف قوی‌تر"
			else:
				label = "حریف قوی‌تر" if f > 1.0 else "حریف ضعیف‌تر"
			chips.append(_chip("opponent", label, f))
	# Multiplayer field size: winning a bigger table is rarer, losing it is less informative.
	if players > 2 and outcome != "draw":
		var ff: float = minf(2.2, 1.0 + 0.15 * float(players - 2)) if outcome == "win" else 1.0 / (1.0 + 0.3 * float(players - 2))
		total *= ff
		chips.append(_chip("field", "میز %s نفره" % _fa(str(players)), ff))
	var dur: float = 1.0
	if outcome != "loss":
		dur = duration_multiplier(float(p.get("duration", 0.0)), kind)
		total *= dur
		if absf(dur - 1.0) >= 0.02:
			chips.append(_chip("duration", "مسابقه‌ی کوتاه" if dur < 1.0 else "مسابقه‌ی طولانی", dur))
	if outcome != "loss" and bool(p.get("onboarding", false)):
		total *= ONBOARDING_MULTIPLIER
		chips.append(_chip("onboarding", "شروع پرقدرت", ONBOARDING_MULTIPLIER))
	if outcome == "win":
		var steps: int = mini(int(p.get("win_streak", 0)), STREAK_MAX_STEPS)
		if steps > 0:
			var sf: float = 1.0 + STREAK_STEP * float(steps)
			total *= sf
			chips.append(_chip("streak", "رشته‌ی برد", sf))
		if not bool(p.get("first_win_today", false)):
			total *= FIRST_WIN_OF_DAY_MULTIPLIER
			chips.append(_chip("first_win", "اولین برد امروز", FIRST_WIN_OF_DAY_MULTIPLIER))
		if bool(p.get("forfeit", false)):
			total *= FORFEIT_WIN_MULTIPLIER
			chips.append(_chip("forfeit", "ترک حریف", FORFEIT_WIN_MULTIPLIER))
	if outcome != "loss" and _is_human(kind):
		var rep: int = int(p.get("repeat_count", 0))
		var rf: float = REPEAT_OPPONENT_FACTORS[mini(rep, REPEAT_OPPONENT_FACTORS.size() - 1)]
		if rf < 1.0:
			total *= rf
			chips.append(_chip("repeat", "حریف تکراری امروز", rf))
	if outcome == "loss" and int(p.get("loss_streak", 0)) >= COMEBACK_LOSS_STREAK and not bool(p.get("abandoned", false)):
		total *= COMEBACK_MULTIPLIER
		chips.append(_chip("comeback", "حمایت بازگشت", COMEBACK_MULTIPLIER))
	var lp: int = roundi(total)
	if outcome == "loss":
		lp = mini(-1, lp) if mode_factor > 0.0 else 0
	elif mode_factor > 0.0:
		lp = maxi(1, lp)
	return {"lp": lp, "chips": chips, "duration_factor": dur}

static func _chip(key: String, label: String, factor: float) -> Dictionary:
	return {"key": key, "label": label, "factor": factor, "text": factor_text(factor)}

## Applies a delta to a ladder total, honouring league floors, the practice ceiling and the skill gate.
## Returns {"new": int, "applied": int, "reason": "" | "practice" | "gate" | "practice_safe"}.
static func ladder_apply(current: int, delta: int, scale: float, practice_ceiling: int, mmr: int, practice: bool) -> Dictionary:
	var cur: int = maxi(0, current)
	var target: int = cur + delta
	var reason := ""
	if delta > 0:
		if practice and target > practice_ceiling:
			target = maxi(cur, practice_ceiling)
			reason = "practice"
		var gate_cap: int = LeagueScript.gate_cap_points(mmr, scale)
		if target > gate_cap:
			target = maxi(cur, gate_cap)
			reason = "gate"
	elif delta < 0:
		if practice and cur >= practice_ceiling:
			target = cur # practice never costs points once you are at the top of what practice can give
			reason = "practice_safe"
		else:
			var floor_pts: int = LeagueScript.scaled_start(LeagueScript.league_index_for_points(cur, scale), scale)
			target = maxi(target, floor_pts)
	return {"new": target, "applied": target - cur, "reason": reason}

## What a result would be worth right now (no streak or daily bonuses). Used by the mode screen and resign dialog.
func preview_points(game_id: String, kind: String, difficulty: int, opp_rating: int = -1, players: int = 2) -> Dictionary:
	_roll_clock_if_needed()
	var out: Dictionary = {}
	var practice: bool = kind != "human_online"
	var stats: Dictionary = _game(game_id)
	for outcome in ["win", "draw", "loss"]:
		var calc: Dictionary = compute_lp({
			"outcome": outcome, "kind": kind, "difficulty": difficulty, "game_id": game_id, "players": players,
			"my_rating": match_rating(game_id), "opp_rating": opp_rating, "duration": 0.0,
			"win_streak": 0, "loss_streak": 0, "first_win_today": true, "repeat_count": 0,
		})
		var lp: int = int(calc["lp"])
		var g: Dictionary = ladder_apply(global_season_points, lp, 1.0, LeagueScript.PRACTICE_CEILING_GLOBAL, global_rating, practice)
		out[outcome] = lp
		out[outcome + "_applied"] = int(g["applied"])
		out[outcome + "_reason"] = str(g["reason"])
	return out

# ---------------------------------------------------------------------------
# Recording a finished match
# ---------------------------------------------------------------------------
## context keys: players(int), opponent_name(String), forfeit(bool), abandoned(bool).
func record_result(game_id: String, outcome: String, opponent_kind: String, difficulty: int, game_ids: Array, opponent_rating: int = -1, opponent_global_rating: int = -1, duration_seconds: float = 0.0, context: Dictionary = {}) -> Dictionary:
	if game_id.is_empty():
		return {"recorded": false, "delta": 0, "reason": "empty_game"}
	if opponent_kind == "local_friendly":
		return {"recorded": false, "delta": 0, "reason": "unranked_local_match"}
	if outcome not in ["win", "draw", "loss"]:
		return {"recorded": false, "delta": 0, "reason": "invalid_outcome"}
	if opponent_kind not in ["cpu", "human_online", "human_lan"]:
		return {"recorded": false, "delta": 0, "reason": "unsupported_mode"}
	ensure_game_stats(game_ids)
	_roll_clock_if_needed()
	var stats: Dictionary = _game(game_id)
	var kind: String = opponent_kind
	var human: bool = _is_human(kind)
	var ranked_human: bool = kind == "human_online"
	var practice: bool = kind != "human_online"
	var players: int = maxi(2, int(context.get("players", 2)))
	var opponent_name: String = str(context.get("opponent_name", "")).strip_edges()
	var diff: int = clampi(difficulty, 1, 6)

	# ----- snapshots for "before / after" presentation -----
	var tier_before: Dictionary = global_tier()
	var game_tier_before: Dictionary = game_tier(game_id)
	var level_before: Dictionary = level()
	var mastery_before: Dictionary = game_mastery(game_id)
	var my_match_rating: int = match_rating(game_id)
	var game_rating_before: int = int(stats["rating"])
	var global_rating_before: int = global_rating

	# ----- league points -----
	var repeat_count := 0
	var opp_counts: Dictionary = daily.get("opp", {})
	if human and opponent_name != "":
		repeat_count = int(opp_counts.get(opponent_name, 0))
	var calc: Dictionary = compute_lp({
		"outcome": outcome, "kind": kind, "difficulty": diff, "game_id": game_id, "players": players,
		"my_rating": my_match_rating, "opp_rating": opponent_rating, "duration": duration_seconds,
		"win_streak": win_streak, "loss_streak": loss_streak, "first_win_today": bool(daily.get("first_win", false)),
		"repeat_count": repeat_count, "forfeit": bool(context.get("forfeit", false)), "abandoned": bool(context.get("abandoned", false)),
		"onboarding": total_matches() < ONBOARDING_MATCHES,
	})
	var raw_lp: int = int(calc["lp"])

	# ----- skill rating (real human matches from the matchmaking queue only) -----
	var game_rating_delta := 0
	var global_rating_delta := 0
	if ranked_human:
		var kscale: float = game_k_scale(game_id)
		game_rating_delta = elo_delta(game_rating_before, opponent_rating, outcome, int(stats["rated_matches"]), kscale, players)
		stats["rating"] = clampi(game_rating_before + game_rating_delta, MIN_RATING, MAX_RATING)
		stats["rated_matches"] = int(stats["rated_matches"]) + 1
		global_rating_delta = elo_delta(global_rating_before, opponent_global_rating, outcome, global_rated_matches, kscale, players)
		global_rating = clampi(global_rating_before + global_rating_delta, MIN_RATING, MAX_RATING)
		global_rated_matches += 1

	# ----- apply to the two ladders independently -----
	var g_res: Dictionary = ladder_apply(global_season_points, raw_lp, 1.0, LeagueScript.PRACTICE_CEILING_GLOBAL, global_rating, practice)
	var s_res: Dictionary = ladder_apply(int(stats["season_points"]), raw_lp, LeagueScript.GAME_LADDER_SCALE, LeagueScript.PRACTICE_CEILING_GAME, int(stats["rating"]), practice)
	global_season_points = int(g_res["new"])
	stats["season_points"] = int(s_res["new"])
	var delta: int = int(g_res["applied"])
	var game_delta: int = int(s_res["applied"])
	global_lifetime_points += delta
	stats["points"] = int(stats["points"]) + game_delta
	season_peak_points = maxi(season_peak_points, global_season_points)

	# ----- counters, streaks -----
	var first_win_of_game: bool = outcome == "win" and int(stats["wins"]) == 0
	var comeback: bool = outcome == "win" and loss_streak >= 3
	var counts_for_streak: bool = human or diff >= STREAK_MIN_CPU_LEVEL
	match outcome:
		"win":
			stats["wins"] = int(stats["wins"]) + 1
			if counts_for_streak:
				win_streak += 1
			loss_streak = 0
			if kind == "cpu":
				var by_level: Array = (stats["cpu_wins_by_level"] as Array).duplicate()
				by_level[diff - 1] = int(by_level[diff - 1]) + 1
				stats["cpu_wins_by_level"] = by_level
		"draw":
			stats["draws"] = int(stats["draws"]) + 1
			loss_streak = 0
		"loss":
			stats["losses"] = int(stats["losses"]) + 1
			loss_streak += 1
			win_streak = 0
	best_streak = maxi(best_streak, win_streak)
	stats["best_streak"] = maxi(int(stats["best_streak"]), win_streak)
	var bucket: String = "cpu" if kind == "cpu" else "human"
	var outcome_key: String = outcome + "s" if outcome != "loss" else "losses"
	if outcome == "draw":
		outcome_key = "draws"
	stats["%s_%s" % [bucket, outcome_key]] = int(stats["%s_%s" % [bucket, outcome_key]]) + 1
	season_counts["matches"] = int(season_counts["matches"]) + 1
	season_counts[outcome_key] = int(season_counts[outcome_key]) + 1
	if ranked_human:
		season_counts["human"] = int(season_counts["human"]) + 1
	if outcome == "win":
		daily["first_win"] = true
	if human and opponent_name != "":
		opp_counts[opponent_name] = repeat_count + 1
		daily["opp"] = opp_counts

	# ----- XP (never negative; every result earns something) -----
	var xp_base: int = 40 if outcome == "win" else (26 if outcome == "draw" else 16)
	var xp_mode: float = 1.0 if ranked_human else (0.7 if kind == "human_lan" else CPU_XP_MULTIPLIERS[diff - 1])
	var xp_gain: float = float(xp_base) * xp_mode
	if duration_seconds > 0.0 and duration_seconds < TEMPO_XP_MIN_SECONDS:
		xp_gain *= 0.25
	var xp_bonus_lines: Array = []
	var xp_total: int = maxi(1, roundi(xp_gain))
	if first_win_of_game:
		xp_total += 40
		xp_bonus_lines.append("اولین برد در این بازی")
	stats["xp"] = int(stats["xp"]) + xp_total
	xp += xp_total

	# ----- rivals -----
	var rival_info: Dictionary = {}
	if ranked_human and opponent_name != "":
		var rec: Dictionary = rivals.get(opponent_name, {"w": 0, "d": 0, "l": 0, "t": 0.0})
		match outcome:
			"win": rec["w"] = int(rec["w"]) + 1
			"draw": rec["d"] = int(rec["d"]) + 1
			"loss": rec["l"] = int(rec["l"]) + 1
		rec["t"] = now()
		rivals[opponent_name] = rec
		_trim_rivals()
		rival_info = {"name": opponent_name, "w": int(rec["w"]), "d": int(rec["d"]), "l": int(rec["l"])}

	# ----- history -----
	var history: Array = stats["history"]
	history.append({
		"t": now(), "outcome": outcome, "delta": delta, "game_delta": game_delta, "vs": kind, "difficulty": diff,
		"season": current_season_id, "duration_seconds": maxf(0.0, duration_seconds),
		"game_rating_delta": game_rating_delta, "global_rating_delta": global_rating_delta,
	})
	if history.size() > MAX_HISTORY:
		history = history.slice(history.size() - MAX_HISTORY)
	stats["history"] = history
	game_stats[game_id] = stats

	# ----- quests -----
	var event: Dictionary = {"outcome": outcome, "kind": kind, "difficulty": diff, "game_id": game_id, "win_streak": win_streak}
	var finished_quests: Array = []
	daily["quests"] = QuestScript.apply_event(daily.get("quests", []), event, finished_quests)
	quests_daily = daily["quests"]
	quests_weekly = QuestScript.apply_event(quests_weekly, event, finished_quests)
	var quest_report: Array = []
	for q in finished_quests:
		xp += int(q["xp"])
		var bonus: Dictionary = ladder_apply(global_season_points, int(q["lp"]), 1.0, LeagueScript.PRACTICE_CEILING_GLOBAL, global_rating, true)
		global_season_points = int(bonus["new"])
		global_lifetime_points += int(bonus["applied"])
		season_peak_points = maxi(season_peak_points, global_season_points)
		quest_report.append({"title": str(q["title"]), "xp": int(q["xp"]), "lp": int(bonus["applied"])})

	# ----- badges -----
	var win_games := 0
	for gid in game_stats.keys():
		if int(game_stats[gid].get("wins", 0)) > 0:
			win_games += 1
	var wl: Array = total_wins_losses()
	var human_total := 0
	for gid in game_stats.keys():
		human_total += int(game_stats[gid].get("human_wins", 0)) + int(game_stats[gid].get("human_draws", 0)) + int(game_stats[gid].get("human_losses", 0))
	var tier_after: Dictionary = global_tier()
	var upset: bool = outcome == "win" and ranked_human and opponent_rating > 0 and opponent_rating - my_match_rating >= 150
	var new_badges: Array = QuestScript.evaluate_badges(badges, {
		"wins": int(wl[0]), "matches": total_matches(), "human_matches": human_total, "best_streak": best_streak,
		"win_games": win_games, "game_count": maxi(game_ids.size(), 1), "upset": upset, "comeback": comeback,
		"level": int(level()["level"]), "league": int(tier_after["league"]),
	})
	var badge_report: Array = []
	for b in new_badges:
		badges.append(str(b["id"]))
		badge_report.append({"id": str(b["id"]), "name": str(b["name"])})

	# ----- pending ranked match is now settled -----
	if not pending_match.is_empty() and str(pending_match.get("game", "")) == game_id:
		pending_match = {}

	tier_after = global_tier()
	var game_tier_after: Dictionary = game_tier(game_id)
	var level_after: Dictionary = level()
	var mastery_after: Dictionary = game_mastery(game_id)
	var cap_reason: String = str(g_res["reason"])
	if cap_reason == "" or cap_reason == "practice_safe":
		cap_reason = str(s_res["reason"]) if str(s_res["reason"]) in ["practice", "gate"] else cap_reason
	save_scores()
	return {
		"recorded": true, "delta": delta, "game_delta": game_delta, "raw_delta": raw_lp,
		"rating": global_rating, "rating_delta": global_rating_delta,
		"game_rating": int(stats["rating"]), "game_rating_delta": game_rating_delta,
		"season_points": global_season_points, "game_season_points": int(stats["season_points"]), "season": current_season_id,
		"game_id": game_id, "outcome": outcome, "mode": kind, "difficulty": diff,
		"duration_seconds": maxf(0.0, duration_seconds), "duration_multiplier": float(calc["duration_factor"]),
		"chips": calc["chips"],
		"tier_before": tier_before, "tier_after": tier_after,
		"game_tier_before": game_tier_before, "game_tier_after": game_tier_after,
		"league_up": int(tier_after["league"]) > int(tier_before["league"]),
		"division_up": int(tier_after["league"]) == int(tier_before["league"]) and int(tier_after["division"]) != int(tier_before["division"]) and int(tier_after["points"]) > int(tier_before["points"]),
		"game_league_up": int(game_tier_after["league"]) > int(game_tier_before["league"]),
		"cap_reason": cap_reason,
		"xp_gain": xp_total, "xp_bonus_lines": xp_bonus_lines,
		"level_before": int(level_before["level"]), "level_after": int(level_after["level"]),
		"level_up": int(level_after["level"]) > int(level_before["level"]), "level_info": level_after,
		"mastery_before": int(mastery_before["stars"]), "mastery_after": int(mastery_after["stars"]),
		"mastery_up": int(mastery_after["stars"]) > int(mastery_before["stars"]),
		"win_streak": win_streak, "loss_streak": loss_streak, "comeback": comeback,
		"quests_completed": quest_report, "badges_unlocked": badge_report, "rival": rival_info,
		"first_win_of_game": first_win_of_game,
	}

# Compatibility wrapper for older callers. New ranked callers should use record_result().
func record_match_result(game_id: String, won: bool, opponent_kind: String, game_ids: Array, draw: bool = false, difficulty: int = 3, opponent_rating: int = -1) -> Dictionary:
	var outcome := "draw" if draw else ("win" if won else "loss")
	var lowered: String = opponent_kind.to_lower()
	var mode := "cpu" if lowered == "cpu" else ("human_online" if lowered in ["online", "human", "human_online"] else ("human_lan" if lowered == "human_lan" else "local_friendly"))
	return record_result(game_id, outcome, mode, difficulty, game_ids, opponent_rating)

func _trim_rivals() -> void:
	if rivals.size() <= MAX_RIVALS:
		return
	var names: Array = rivals.keys()
	names.sort_custom(func(a, b): return float(rivals[a].get("t", 0.0)) > float(rivals[b].get("t", 0.0)))
	var kept: Dictionary = {}
	for i in range(MAX_RIVALS):
		kept[names[i]] = rivals[names[i]]
	rivals = kept

# ---------------------------------------------------------------------------
# Anti-quit: a ranked online match is written down when it starts. If the app is closed / the page is reloaded before a
# result exists, the next launch settles it as a loss. Opponent-left events and clean exits resolve it explicitly.
# ---------------------------------------------------------------------------
func begin_pending_match(game_id: String, players: int, opponent_name: String, opponent_rating: int, opponent_global_rating: int) -> void:
	pending_match = {
		"game": game_id, "players": players, "opponent": opponent_name,
		"opp_rating": opponent_rating, "opp_global": opponent_global_rating, "t": now(),
	}
	save_scores()

func clear_pending_match() -> void:
	if pending_match.is_empty():
		return
	pending_match = {}
	save_scores()

func has_pending_match() -> bool:
	return not pending_match.is_empty()

## Returns the recorded result when an unfinished ranked match is found, otherwise an empty dictionary.
func settle_pending_match(game_ids: Array) -> Dictionary:
	if pending_match.is_empty():
		return {}
	var pm: Dictionary = pending_match
	pending_match = {}
	var age: float = maxf(0.0, now() - float(pm.get("t", now())))
	var res: Dictionary = record_result(str(pm.get("game", "")), "loss", "human_online", 3, game_ids, int(pm.get("opp_rating", -1)), int(pm.get("opp_global", -1)), age, {"players": int(pm.get("players", 2)), "opponent_name": str(pm.get("opponent", "")), "abandoned": true})
	return res

# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------
func load_scores(game_ids: Array) -> void:
	var config := ConfigFile.new()
	var load_path := score_path
	var loaded_ok: bool = config.load(load_path) == OK
	if not loaded_ok and score_path == SCORE_PATH:
		load_path = LEGACY_SCORE_PATH
		loaded_ok = config.load(load_path) == OK
	var has_saved_lifetime_total := loaded_ok and config.has_section_key("player", "lifetime_points")
	var schema: int = int(config.get_value("player", "schema_version", int(config.get_value("player", "rating_schema_version", 0)))) if loaded_ok else SCHEMA_VERSION
	if loaded_ok:
		global_rating = int(config.get_value("player", "rating", INITIAL_RATING))
		global_rated_matches = int(config.get_value("player", "rated_matches", 0))
		global_lifetime_points = int(config.get_value("player", "lifetime_points", 0))
		global_season_points = maxi(0, int(config.get_value("player", "season_points", 0)))
		current_season_id = str(config.get_value("player", "season_id", ""))
		player_name = str(config.get_value("player", "name", "بازیکن"))
		music_on = bool(config.get_value("settings", "music", true))
		xp = int(config.get_value("player", "xp", 0))
		win_streak = int(config.get_value("player", "win_streak", 0))
		loss_streak = int(config.get_value("player", "loss_streak", 0))
		best_streak = int(config.get_value("player", "best_streak", 0))
		season_peak_points = int(config.get_value("player", "season_peak_points", global_season_points))
		season_counts = _merge_defaults(config.get_value("player", "season_counts", {}), {"matches": 0, "wins": 0, "draws": 0, "losses": 0, "human": 0})
		badges = _array_or(config.get_value("player", "badges", []))
		season_history = _array_or(config.get_value("player", "season_history", []))
		last_report = _dict_or(config.get_value("player", "last_report", {}), {})
		report_unseen = bool(config.get_value("player", "report_unseen", false))
		rivals = _dict_or(config.get_value("player", "rivals", {}), {})
		pending_match = _dict_or(config.get_value("player", "pending_match", {}), {})
		daily = _merge_defaults(config.get_value("player", "daily", {}), {"day": "", "first_win": false, "opp": {}})
		quests_weekly = _array_or(config.get_value("player", "quests_weekly", []))
		quest_week_id = str(config.get_value("player", "quest_week_id", ""))
		if config.has_section("stats"):
			for key in config.get_section_keys("stats"):
				game_stats[str(key)] = _normalize_stats(config.get_value("stats", key, {}))
		if schema < 2:
			# Old global_rating was a simple win/loss counter, not MMR. Keep history/points but recalibrate skill.
			global_rating = INITIAL_RATING
			global_rated_matches = 0
			for key in game_stats.keys():
				var migrated: Dictionary = _normalize_stats(game_stats[key])
				migrated["rating"] = INITIAL_RATING
				migrated["rated_matches"] = 0
				game_stats[key] = migrated
		if config.has_section("seen"):
			for key in config.get_section_keys("seen"):
				seen_rules[str(key)] = true
	var had_lifetime_total := has_saved_lifetime_total
	ensure_game_stats(game_ids)
	if not had_lifetime_total:
		global_lifetime_points = 0
		for raw_stats in game_stats.values():
			global_lifetime_points += int(raw_stats.get("points", 0))
	_roll_clock_if_needed()
	save_scores()

## Stored dictionaries from older builds may be empty or partial: always fill in every default key.
static func _merge_defaults(value: Variant, defaults: Dictionary) -> Dictionary:
	var out: Dictionary = defaults.duplicate(true)
	if typeof(value) == TYPE_DICTIONARY:
		for key in (value as Dictionary).keys():
			out[key] = (value as Dictionary)[key]
	return out

static func _dict_or(value: Variant, fallback: Dictionary) -> Dictionary:
	return (value as Dictionary).duplicate(true) if typeof(value) == TYPE_DICTIONARY else fallback.duplicate(true)

static func _array_or(value: Variant) -> Array:
	return (value as Array).duplicate(true) if typeof(value) == TYPE_ARRAY else []

func config_has_saved_lifetime_total() -> bool:
	var config := ConfigFile.new()
	if config.load(score_path) == OK:
		return config.has_section_key("player", "lifetime_points")
	var legacy := ConfigFile.new()
	return legacy.load(LEGACY_SCORE_PATH) == OK and legacy.has_section_key("player", "lifetime_points")

func save_scores() -> void:
	_season_dirty = false
	if not persist:
		return
	var config := ConfigFile.new()
	config.set_value("player", "rating", global_rating)
	config.set_value("player", "schema_version", SCHEMA_VERSION)
	config.set_value("player", "rating_schema_version", 2) # kept so older builds do not recalibrate on downgrade
	config.set_value("player", "rated_matches", global_rated_matches)
	config.set_value("player", "lifetime_points", global_lifetime_points)
	config.set_value("player", "season_points", global_season_points)
	config.set_value("player", "season_id", current_season_id if not current_season_id.is_empty() else LeagueScript.season_id_at(now()))
	config.set_value("player", "name", player_name)
	config.set_value("player", "xp", xp)
	config.set_value("player", "win_streak", win_streak)
	config.set_value("player", "loss_streak", loss_streak)
	config.set_value("player", "best_streak", best_streak)
	config.set_value("player", "season_peak_points", season_peak_points)
	config.set_value("player", "season_counts", season_counts)
	config.set_value("player", "badges", badges)
	config.set_value("player", "season_history", season_history)
	config.set_value("player", "last_report", last_report)
	config.set_value("player", "report_unseen", report_unseen)
	config.set_value("player", "rivals", rivals)
	config.set_value("player", "pending_match", pending_match)
	config.set_value("player", "daily", daily)
	config.set_value("player", "quests_weekly", quests_weekly)
	config.set_value("player", "quest_week_id", quest_week_id)
	config.set_value("settings", "music", music_on)
	for id in game_stats.keys():
		config.set_value("stats", id, game_stats[id])
	for id in seen_rules.keys():
		config.set_value("seen", id, true)
	config.save(score_path)
