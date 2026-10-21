extends RefCounted
## Fair, transparent scoring: monthly league points are separate from persistent skill rating.
## CPU games earn smaller season points by difficulty; only human online matches change MMR.
const SCORE_PATH := "user://mind_bastion_scores.cfg"
const WIN_PTS := 24
const DRAW_PTS := 4
const LOSS_PTS := -12
const INITIAL_RATING := 1000
const MIN_RATING := 100
const MAX_RATING := 3000
const HUMAN_SEASON_MULTIPLIER := 1.25
const CPU_DIFFICULTY_MULTIPLIERS: Array[float] = [0.15, 0.25, 0.38, 0.52, 0.68, 0.82]
const GAME_WEIGHTS := {
	"chess": 1.25,
	"quoridor": 1.20,
	"abalone": 1.20,
	"blockace": 1.15,
	"quarto": 1.05,
	"backgammon": 1.10,
	"othello12": 1.10,
	"pentago": 1.05,
	"gobblet": 1.05,
	"othello": 1.00,
	"mastermind": 1.00,
	"hokm": 1.00,
	"domino": 0.95,
	"pasoor": 0.95,
}

var player_name: String = "بازیکن"
var global_rating: int = INITIAL_RATING
var global_rated_matches: int = 0
var global_lifetime_points: int = 0
var global_season_points: int = 0
var current_season_id: String = ""
var _season_dirty: bool = false
var game_stats: Dictionary = {}
var seen_rules: Dictionary = {}
var music_on: bool = true

func _month_key() -> String:
	var d: Dictionary = Time.get_datetime_dict_from_system(true)
	return "%04d-%02d" % [int(d.get("year", 2026)), int(d.get("month", 1))]

func _empty_game_stats() -> Dictionary:
	return {
		"wins": 0, "draws": 0, "losses": 0,
		"points": 0, "season_points": 0,
		"rating": INITIAL_RATING, "rated_matches": 0,
		"cpu_wins": 0, "cpu_draws": 0, "cpu_losses": 0,
		"human_wins": 0, "human_draws": 0, "human_losses": 0,
		"history": []
	}

func _normalize_stats(raw: Variant) -> Dictionary:
	var stats: Dictionary = raw.duplicate(true) if typeof(raw) == TYPE_DICTIONARY else _empty_game_stats()
	for key in _empty_game_stats().keys():
		if not stats.has(key):
			stats[key] = [] if key == "history" else (INITIAL_RATING if key == "rating" else 0)
	if typeof(stats.get("history", [])) != TYPE_ARRAY:
		stats["history"] = []
	return stats

func ensure_game_stats(game_ids: Array) -> void:
	for game_id in game_ids:
		var id := str(game_id)
		game_stats[id] = _normalize_stats(game_stats.get(id, {}))
	if not current_season_id.is_empty():
		_roll_season_if_needed()

func _reset_season_counters() -> void:
	global_season_points = 0
	for key in game_stats.keys():
		var stats: Dictionary = _normalize_stats(game_stats[key])
		stats["season_points"] = 0
		game_stats[key] = stats

func _roll_season_if_needed() -> void:
	var now := _month_key()
	var changed := false
	if current_season_id.is_empty():
		# Existing installations may have lifetime stats only; never mislabel them as this month's score.
		current_season_id = now
		_reset_season_counters()
		changed = true
	elif current_season_id != now:
		current_season_id = now
		_reset_season_counters()
		changed = true
	if changed:
		_season_dirty = true

func _result_base(outcome: String) -> int:
	match outcome:
		"win": return WIN_PTS
		"draw": return DRAW_PTS
		_: return LOSS_PTS

func _actual_result(outcome: String) -> float:
	match outcome:
		"win": return 1.0
		"draw": return 0.5
		_: return 0.0

func _elo_delta(rating: int, opponent_rating: int, outcome: String, rated_matches: int) -> int:
	# Until online profiles provide the opponent's true MMR, compare against the 1000-point baseline.
	var opponent := clampi(opponent_rating if opponent_rating > 0 else INITIAL_RATING, MIN_RATING, MAX_RATING)
	var expected := 1.0 / (1.0 + pow(10.0, float(opponent - rating) / 400.0))
	var k := 32 if rated_matches < 10 else 24
	return roundi(float(k) * (_actual_result(outcome) - expected))

func record_result(game_id: String, outcome: String, opponent_kind: String, difficulty: int, game_ids: Array, opponent_rating: int = -1, opponent_global_rating: int = -1) -> Dictionary:
	if game_id.is_empty():
		return {"recorded": false, "delta": 0, "reason": "empty_game"}
	if opponent_kind == "local_friendly":
		return {"recorded": false, "delta": 0, "reason": "unranked_local_match"}
	if outcome not in ["win", "draw", "loss"]:
		return {"recorded": false, "delta": 0, "reason": "invalid_outcome"}
	ensure_game_stats(game_ids)
	_roll_season_if_needed()
	if not game_stats.has(game_id):
		game_stats[game_id] = _empty_game_stats()

	var stats: Dictionary = _normalize_stats(game_stats[game_id])
	var ranked_human := opponent_kind == "human_online"
	var against_cpu := opponent_kind == "cpu"
	var mode_multiplier := 0.0
	if ranked_human:
		mode_multiplier = HUMAN_SEASON_MULTIPLIER
	elif against_cpu:
		mode_multiplier = CPU_DIFFICULTY_MULTIPLIERS[clampi(difficulty, 1, 6) - 1]
	else:
		return {"recorded": false, "delta": 0, "reason": "unsupported_mode"}

	var game_weight: float = float(GAME_WEIGHTS.get(game_id, 1.0))
	var opponent_strength_multiplier := 1.0
	if ranked_human and opponent_rating > 0:
		var before_rating := int(stats.get("rating", INITIAL_RATING))
		opponent_strength_multiplier = clampf(1.0 + float(opponent_rating - before_rating) / 1200.0, 0.75, 1.25)
	var raw_delta := roundi(float(_result_base(outcome)) * mode_multiplier * game_weight * opponent_strength_multiplier)
	# Every completed draw is a small positive league result, including easier CPU levels.
	if outcome == "draw":
		raw_delta = maxi(1, raw_delta)
	var delta := raw_delta

	match outcome:
		"win": stats["wins"] = int(stats["wins"]) + 1
		"draw": stats["draws"] = int(stats["draws"]) + 1
		"loss": stats["losses"] = int(stats["losses"]) + 1
	if against_cpu:
		match outcome:
			"win": stats["cpu_wins"] = int(stats["cpu_wins"]) + 1
			"draw": stats["cpu_draws"] = int(stats["cpu_draws"]) + 1
			"loss": stats["cpu_losses"] = int(stats["cpu_losses"]) + 1
	else:
		match outcome:
			"win": stats["human_wins"] = int(stats["human_wins"]) + 1
			"draw": stats["human_draws"] = int(stats["human_draws"]) + 1
			"loss": stats["human_losses"] = int(stats["human_losses"]) + 1

	stats["points"] = int(stats.get("points", 0)) + delta
	stats["season_points"] = int(stats.get("season_points", 0)) + delta
	var game_rating_delta := 0
	var global_rating_delta := 0
	if ranked_human:
		var before_game_rating := int(stats.get("rating", INITIAL_RATING))
		game_rating_delta = _elo_delta(before_game_rating, opponent_rating, outcome, int(stats.get("rated_matches", 0)))
		stats["rating"] = clampi(before_game_rating + game_rating_delta, MIN_RATING, MAX_RATING)
		stats["rated_matches"] = int(stats.get("rated_matches", 0)) + 1
		global_rating_delta = _elo_delta(global_rating, opponent_global_rating, outcome, global_rated_matches)
		global_rating = clampi(global_rating + global_rating_delta, MIN_RATING, MAX_RATING)
		global_rated_matches += 1

	global_lifetime_points += delta
	global_season_points += delta
	var history: Array = stats.get("history", [])
	history.append({
		"t": Time.get_unix_time_from_system(), "outcome": outcome,
		"win": outcome == "win", "draw": outcome == "draw", "delta": delta,
		"vs": opponent_kind, "difficulty": clampi(difficulty, 1, 6),
		"game_weight": game_weight, "season": current_season_id,
		"game_rating_delta": game_rating_delta, "global_rating_delta": global_rating_delta
	})
	if history.size() > 400:
		history = history.slice(history.size() - 400)
	stats["history"] = history
	game_stats[game_id] = stats
	save_scores()
	return {
		"recorded": true, "delta": delta, "rating": global_rating,
		"rating_delta": global_rating_delta, "game_rating": int(stats["rating"]),
		"game_rating_delta": game_rating_delta, "season_points": global_season_points,
		"game_season_points": int(stats["season_points"]), "season": current_season_id,
		"game_id": game_id, "outcome": outcome, "mode": opponent_kind
	}

# Compatibility wrapper for older callers. New ranked callers should use record_result().
func record_match_result(game_id: String, won: bool, opponent_kind: String, game_ids: Array, draw: bool = false, difficulty: int = 3, opponent_rating: int = -1) -> Dictionary:
	var outcome := "draw" if draw else ("win" if won else "loss")
	var mode := "cpu" if opponent_kind.to_lower() == "cpu" else ("human_online" if opponent_kind.to_lower() in ["online", "human", "human_online"] else "local_friendly")
	return record_result(game_id, outcome, mode, difficulty, game_ids, opponent_rating)

func current_month_points(game_id: String = "") -> int:
	_roll_season_if_needed()
	if _season_dirty:
		save_scores()
	if game_id.is_empty():
		return global_season_points
	var stats: Dictionary = game_stats.get(game_id, {})
	return int(stats.get("season_points", 0))

func points_in_period(game_id: String, days: int) -> int:
	if not game_stats.has(game_id):
		return 0
	var cutoff: float = Time.get_unix_time_from_system() - days * 86400.0
	var total := 0
	for entry in game_stats[game_id].get("history", []):
		if float(entry.get("t", 0)) >= cutoff:
			total += int(entry.get("delta", 0))
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

func load_scores(game_ids: Array) -> void:
	var config := ConfigFile.new()
	var loaded_ok: bool = config.load(SCORE_PATH) == OK
	var rating_schema_version := int(config.get_value("player", "rating_schema_version", 0)) if loaded_ok else 0
	if loaded_ok:
		global_rating = int(config.get_value("player", "rating", INITIAL_RATING))
		global_rated_matches = int(config.get_value("player", "rated_matches", 0))
		global_lifetime_points = int(config.get_value("player", "lifetime_points", 0))
		global_season_points = int(config.get_value("player", "season_points", 0))
		current_season_id = str(config.get_value("player", "season_id", ""))
		player_name = str(config.get_value("player", "name", "بازیکن"))
		music_on = bool(config.get_value("settings", "music", true))
		if config.has_section("stats"):
			for key in config.get_section_keys("stats"):
				game_stats[str(key)] = _normalize_stats(config.get_value("stats", key, {}))
		if rating_schema_version < 2:
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
	var had_lifetime_total := config_has_saved_lifetime_total()
	ensure_game_stats(game_ids)
	if not had_lifetime_total:
		global_lifetime_points = 0
		for raw_stats in game_stats.values():
			global_lifetime_points += int(raw_stats.get("points", 0))
	_roll_season_if_needed()
	save_scores()

func config_has_saved_lifetime_total() -> bool:
	var config := ConfigFile.new()
	return config.load(SCORE_PATH) == OK and config.has_section_key("player", "lifetime_points")

func save_scores() -> void:
	var config := ConfigFile.new()
	config.set_value("player", "rating", global_rating)
	config.set_value("player", "rating_schema_version", 2)
	config.set_value("player", "rated_matches", global_rated_matches)
	config.set_value("player", "lifetime_points", global_lifetime_points)
	config.set_value("player", "season_points", global_season_points)
	config.set_value("player", "season_id", current_season_id if not current_season_id.is_empty() else _month_key())
	config.set_value("player", "name", player_name)
	config.set_value("settings", "music", music_on)
	for id in game_stats.keys():
		config.set_value("stats", id, game_stats[id])
	for id in seen_rules.keys():
		config.set_value("seen", id, true)
	config.save(SCORE_PATH)
	_season_dirty = false
