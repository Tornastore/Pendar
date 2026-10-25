extends SceneTree
## Economy simulation for the Pendar League: plays one 28-day season for several player archetypes and prints where each
## ends up. Run: godot --headless --path . --script res://tools/simulate_league_economy.gd
## Use it after changing any constant in scoring_service.gd / league_service.gd to check pacing before shipping.
const S = preload("res://services/scoring_service.gd")
const L = preload("res://services/league_service.gd")
const GAMES := ["chess","othello","uno","domino","quoridor","mastermind","pentago","gobblet","hokm","backgammon"]

func sim(name: String, per_day: int, human_share: float, true_skill: int, cpu_level: int, cpu_win: float, n_games: int, days: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var s = S.new()
	s.persist = false
	var base: float = Time.get_unix_time_from_datetime_dict({"year":2026,"month":10,"day":24,"hour":12,"minute":0,"second":0})
	s.clock_override = base
	s.ensure_game_stats(GAMES)
	var milestones := {}
	var total := 0
	for d in range(days):
		s.clock_override = base + d * 86400.0
		s.ensure_game_stats(GAMES)
		for m in range(per_day):
			var g: String = GAMES[rng.randi() % n_games]
			var dur: float = rng.randf_range(240, 1200)
			var human: bool = rng.randf() < human_share
			var res: Dictionary
			if human:
				var opp: int = s.match_rating(g) + int(rng.randfn(0, 60))
				var e: float = S.expected_score(true_skill, opp, 2)
				var u: float = rng.randf()
				var out: String = "win" if u < e * 0.97 else ("draw" if u < e * 0.97 + 0.03 else "loss")
				res = s.record_result(g, out, "human_online", 3, GAMES, opp, opp, dur, {"opponent_name": "p%d" % (rng.randi() % 30)})
			else:
				var u2: float = rng.randf()
				var out2: String = "win" if u2 < cpu_win else ("draw" if u2 < cpu_win + 0.04 else "loss")
				res = s.record_result(g, out2, "cpu", cpu_level, GAMES, -1, -1, dur)
			total += 1
		for key in [7, 14, 28]:
			if d + 1 == key:
				milestones[key] = "%s(%d)" % [s.global_tier()["label"], s.global_season_points]
	var bests := []
	for g in GAMES.slice(0, n_games):
		bests.append("%s:%s" % [g, s.game_tier(g)["label"]])
	print("%-22s matches=%d | d7 %s | d14 %s | d28 %s | MMR=%d lvl=%d xp=%d badges=%d | %s" % [name, total, milestones[7], milestones[14], milestones[28], s.global_rating, s.level()["level"], s.xp, s.badges.size(), ", ".join(bests.slice(0,3))])

func _init() -> void:
	sim("casual CPU L3 (4/day)", 4, 0.0, 1000, 3, 0.55, 4, 28)
	sim("casual CPU L2 (3/day)", 3, 0.0, 1000, 2, 0.60, 3, 28)
	sim("grinder CPU L6 (30/day)", 30, 0.0, 1000, 6, 0.55, 10, 28)
	sim("regular mixed (8/day)", 8, 0.5, 1000, 4, 0.65, 6, 28)
	sim("regular human (8/day)", 8, 1.0, 1000, 3, 0.5, 6, 28)
	sim("strong 1300 (12/day)", 12, 0.8, 1300, 5, 0.85, 8, 28)
	sim("expert 1500 (20/day)", 20, 0.9, 1500, 6, 0.9, 10, 28)
	sim("weak 850 (8/day)", 8, 0.6, 850, 2, 0.45, 5, 28)
	sim("hardcore 1250 (40/day)", 40, 0.9, 1250, 6, 0.8, 10, 28)
	quit()
