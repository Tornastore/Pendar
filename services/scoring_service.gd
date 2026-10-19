extends RefCounted
## Persistence and scoring only. It knows game IDs, not game rules or UI.
const SCORE_PATH := "user://mind_bastion_scores.cfg"
const WIN_PTS := 15
const LOSS_PTS := -8

var player_name: String = "بازیکن"
var global_rating: int = 1000
var game_stats: Dictionary = {}
var seen_rules: Dictionary = {}
var music_on: bool = true

func ensure_game_stats(game_ids: Array) -> void:
	for game_id in game_ids:
		var id := str(game_id)
		if not game_stats.has(id):
			game_stats[id] = {"wins": 0, "losses": 0, "points": 0, "history": []}

func record_match_result(game_id: String, won: bool, opponent_kind: String, game_ids: Array) -> Dictionary:
	if game_id.is_empty():
		return {"recorded": false, "delta": 0}
	ensure_game_stats(game_ids)
	if not game_stats.has(game_id):
		game_stats[game_id] = {"wins": 0, "losses": 0, "points": 0, "history": []}
	var stats: Dictionary = game_stats[game_id]
	var delta: int = WIN_PTS if won else LOSS_PTS
	if won:
		stats.wins = int(stats.get("wins", 0)) + 1
	else:
		stats.losses = int(stats.get("losses", 0)) + 1
	stats.points = int(stats.get("points", 0)) + delta
	global_rating = maxi(100, global_rating + delta)
	var history: Array = stats.get("history", [])
	history.append({"t": Time.get_unix_time_from_system(), "win": won, "delta": delta, "vs": opponent_kind})
	if history.size() > 200:
		history = history.slice(history.size() - 200)
	stats.history = history
	game_stats[game_id] = stats
	save_scores()
	return {"recorded": true, "delta": delta, "rating": global_rating, "game_id": game_id}

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
	var losses := 0
	for stats in game_stats.values():
		wins += int(stats.get("wins", 0))
		losses += int(stats.get("losses", 0))
	return [wins, losses]

func load_scores(game_ids: Array) -> void:
	var config := ConfigFile.new()
	if config.load(SCORE_PATH) == OK:
		global_rating = int(config.get_value("player", "rating", 1000))
		player_name = str(config.get_value("player", "name", "بازیکن"))
		music_on = bool(config.get_value("settings", "music", true))
		if config.has_section("stats"):
			for key in config.get_section_keys("stats"):
				var raw = config.get_value("stats", key, {})
				if typeof(raw) == TYPE_DICTIONARY:
					game_stats[str(key)] = raw
		if config.has_section("seen"):
			for key in config.get_section_keys("seen"):
				seen_rules[str(key)] = true
	ensure_game_stats(game_ids)

func save_scores() -> void:
	var config := ConfigFile.new()
	config.set_value("player", "rating", global_rating)
	config.set_value("player", "name", player_name)
	config.set_value("settings", "music", music_on)
	for id in game_stats.keys():
		config.set_value("stats", id, game_stats[id])
	for id in seen_rules.keys():
		config.set_value("seen", id, true)
	config.save(SCORE_PATH)
