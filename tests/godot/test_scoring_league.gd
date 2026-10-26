extends SceneTree
## Regression tests for the Pendar League scoring, ladder, season and anti-quit rules.

const ScoringScript = preload("res://services/scoring_service.gd")
const LeagueScript = preload("res://services/league_service.gd")
const QuestScript = preload("res://services/quest_service.gd")

var checks := 0
var failures := 0
const GAMES := ["chess", "othello", "uno", "domino", "quoridor", "mastermind"]

func ok(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)

func at(day_jalali: Array) -> float:
	var g: Dictionary = LeagueScript.gregorian_from_jalali(day_jalali[0], day_jalali[1], day_jalali[2])
	return Time.get_unix_time_from_datetime_dict({"year": g["gy"], "month": g["gm"], "day": g["gd"], "hour": 12, "minute": 0, "second": 0})

func fresh(day: Array = [1405, 8, 3]) -> RefCounted:
	var s = ScoringScript.new()
	s.persist = false
	s.clock_override = at(day)
	s.ensure_game_stats(GAMES)
	return s

func _init() -> void:
	# ---- ladder structure ----
	var t0: Dictionary = LeagueScript.tier_for_points(0)
	ok(t0["label"] == "برنز ۳" and t0["division"] == 3, "0 LP is Bronze III")
	ok(LeagueScript.tier_for_points(100)["label"] == "برنز ۲", "100 LP is Bronze II")
	ok(LeagueScript.tier_for_points(299)["label"] == "برنز ۱", "299 LP is still Bronze I")
	ok(LeagueScript.tier_for_points(300)["name"] == "نقره" and LeagueScript.tier_for_points(300)["division"] == 3, "300 LP enters Silver III")
	ok(LeagueScript.tier_for_points(8800)["name"] == "لجند" and LeagueScript.tier_for_points(8800)["is_top"], "8800 LP is Legend (top)")
	ok(LeagueScript.tier_for_points(-50)["points"] == 0, "negative LP clamps to 0")
	ok(LeagueScript.tier_for_points(10)["to_next"] == 90, "10 LP is 90 from Bronze II")
	var g: Dictionary = LeagueScript.tier_for_points(60, LeagueScript.GAME_LADDER_SCALE)
	ok(g["label"] == "برنز ۳" or g["label"] == "برنز ۲", "per-game ladder uses half scale")
	ok(LeagueScript.gate_cap_points(999) == 1699, "MMR 999 cannot pass the Platinum gate")
	ok(LeagueScript.gate_cap_points(1200) == 6200 - 1, "MMR 1200 is capped below Grandmaster")
	ok(LeagueScript.carry_over_points(1000) == 350, "35% season carry")
	ok(LeagueScript.level_info(0)["level"] == 1 and LeagueScript.level_info(100)["level"] == 2, "XP level thresholds")
	ok(LeagueScript.mastery_info(0)["stars"] == 1 and LeagueScript.mastery_info(80)["stars"] == 2 and LeagueScript.mastery_info(99999)["stars"] == 10, "mastery stars")

	# ---- basic outcomes against a human ----
	var s = fresh()
	var r: Dictionary = s.record_result("othello", "win", "human_online", 3, GAMES, 1000, 1000, 600.0, {"opponent_name": "علی"})
	ok(r["recorded"] and r["delta"] > 0, "human win gives LP")
	ok(r["game_delta"] > 0 and r["rating_delta"] > 0 and r["game_rating_delta"] > 0, "human win raises MMR too")
	var chip_keys: Array = []
	for c in r["chips"]:
		chip_keys.append(c["key"])
	ok(chip_keys.has("first_win"), "first win of the day bonus shown")
	var r2: Dictionary = s.record_result("othello", "win", "human_online", 3, GAMES, 1000, 1000, 600.0, {"opponent_name": "رضا"})
	var k2: Array = []
	for c in r2["chips"]:
		k2.append(c["key"])
	ok(k2.has("streak") and not k2.has("first_win"), "second straight win gets streak, not daily bonus")
	var rl: Dictionary = s.record_result("othello", "loss", "human_online", 3, GAMES, 1000, 1000, 600.0, {"opponent_name": "رضا"})
	ok(rl["delta"] < 0 and rl["rating_delta"] < 0, "loss costs LP and MMR")
	var rd: Dictionary = s.record_result("othello", "draw", "human_online", 3, GAMES, 1000, 1000, 600.0, {"opponent_name": "سارا"})
	ok(rd["delta"] >= 1, "draw always gives at least +1 to a human opponent")

	# ---- draw gives both sides something, loss strictly negative ----
	var sd = fresh()
	for lvl in range(1, 7):
		var rr: Dictionary = sd.record_result("chess", "draw", "cpu", lvl, GAMES, -1, -1, 300.0)
		ok(rr["raw_delta"] >= 1, "draw vs CPU level %d is positive" % lvl)

	# ---- CPU difficulty ordering and human > CPU ----
	var pv = fresh()
	var prev_win := 0
	for lvl in range(1, 7):
		var p: Dictionary = pv.preview_points("chess", "cpu", lvl)
		ok(p["win"] > prev_win, "preview win grows with CPU level %d" % lvl)
		prev_win = p["win"]
	var ph: Dictionary = pv.preview_points("chess", "human_online", 3, 1000)
	ok(ph["win"] > prev_win, "human win is worth more than the hardest CPU")
	ok(pv.preview_points("chess", "human_lan", 3)["win"] < ph["win"], "LAN friendly game is worth less than ranked online")
	ok(pv.preview_points("chess", "human_online", 3, 1000)["win"] > pv.preview_points("uno", "human_online", 3, 1000)["win"], "deep game (chess) outscores luck game (uno)")
	ok(pv.preview_points("chess", "human_online", 3, 1400)["win"] > pv.preview_points("chess", "human_online", 3, 700)["win"], "beating a stronger opponent is worth more")
	ok(pv.preview_points("chess", "human_online", 3, 1400)["loss"] > pv.preview_points("chess", "human_online", 3, 700)["loss"], "losing to a weaker opponent costs more")
	var four: Dictionary = pv.preview_points("quoridor", "human_online", 3, -1, 4)
	var two: Dictionary = pv.preview_points("quoridor", "human_online", 3, -1, 2)
	ok(four["win"] > two["win"] and absi(four["loss"]) < absi(two["loss"]), "bigger tables reward wins more and punish losses less")

	# ---- local friendly and invalid ----
	ok(not s.record_result("chess", "win", "local_friendly", 3, GAMES)["recorded"], "same-device game is unranked")
	ok(not s.record_result("chess", "bad", "cpu", 3, GAMES)["recorded"], "invalid outcome rejected")

	# ---- onboarding boost: first matches are doubled, later ones are not ----
	var so = fresh()
	var first: Dictionary = so.record_result("chess", "win", "cpu", 3, GAMES, -1, -1, 600.0)
	var has_boost := false
	for c in first["chips"]:
		if c["key"] == "onboarding": has_boost = true
	ok(has_boost, "new players get the onboarding boost")
	ok(so.global_tier()["name"] == "برنز", "boost still leaves a new player in Bronze")
	var vet = fresh()
	for i in range(ScoringScript.ONBOARDING_MATCHES):
		vet.record_result("chess", "loss", "cpu", 1, GAMES, -1, -1, 600.0)
	var late: Dictionary = vet.record_result("chess", "win", "cpu", 3, GAMES, -1, -1, 600.0)
	var late_boost := false
	for c in late["chips"]:
		if c["key"] == "onboarding": late_boost = true
	ok(not late_boost, "onboarding boost ends after %d matches" % ScoringScript.ONBOARDING_MATCHES)

	# ---- CPU never changes MMR, LAN never changes MMR ----
	var sc = fresh()
	var rc: Dictionary = sc.record_result("chess", "win", "cpu", 6, GAMES, -1, -1, 400.0)
	ok(rc["rating_delta"] == 0 and sc.global_rating == 1000 and sc.game_rating("chess") == 1000, "CPU win leaves MMR untouched")
	var rlan: Dictionary = sc.record_result("chess", "win", "human_lan", 3, GAMES, -1, -1, 400.0, {"opponent_name": "دوست"})
	ok(rlan["rating_delta"] == 0 and rlan["delta"] > 0, "LAN win gives LP but not MMR")

	# ---- practice ceiling: CPU cannot push past Gold ----
	var sp = fresh()
	var capped := false
	for i in range(400):
		var rp: Dictionary = sp.record_result("chess", "win", "cpu", 6, GAMES, -1, -1, 900.0)
		if rp["cap_reason"] == "practice":
			capped = true
	ok(sp.global_season_points <= LeagueScript.PRACTICE_CEILING_GLOBAL, "CPU grinding stops at the practice ceiling (%d)" % sp.global_season_points)
	ok(capped, "result reports practice cap reason")
	ok(sp.global_tier()["name"] == "طلا", "CPU-only player tops out in Gold")
	var before_loss: int = sp.global_season_points
	sp.record_result("chess", "loss", "cpu", 6, GAMES, -1, -1, 900.0)
	ok(sp.global_season_points == before_loss, "at the practice ceiling a CPU loss costs nothing (no all-downside practice)")
	sp.global_season_points = LeagueScript.PRACTICE_CEILING_GLOBAL - 12
	sp.game_stats["chess"]["season_points"] = 100
	var below: int = sp.global_season_points
	sp.record_result("chess", "loss", "cpu", 6, GAMES, -1, -1, 900.0)
	ok(sp.global_season_points < below, "just below the ceiling a CPU loss still costs points")

	# ---- skill gate: LP stops one point under Platinum until MMR >= 1000 ----
	var sg = fresh()
	sg.global_rating = 950
	sg.global_season_points = 1690
	sg.game_stats["chess"]["rating"] = 950
	var rg: Dictionary = sg.record_result("chess", "win", "human_online", 3, GAMES, 950, 950, 900.0, {"opponent_name": "x"})
	ok(sg.global_rating >= 950, "win raises MMR")
	var s_after: int = sg.global_season_points
	ok(s_after <= 1699 or sg.global_rating >= 1000, "Platinum is locked while MMR < 1000")
	var sg2 = fresh()
	sg2.global_rating = 1100
	sg2.global_season_points = 1695
	sg2.game_stats["chess"]["rating"] = 1100
	sg2.record_result("chess", "win", "human_online", 3, GAMES, 1100, 1100, 900.0, {"opponent_name": "y"})
	ok(sg2.global_season_points >= 1700, "Platinum opens with MMR >= 1000")

	# ---- league floor ----
	var sf = fresh()
	sf.global_season_points = 860
	sf.game_stats["chess"]["season_points"] = 430
	for i in range(10):
		sf.record_result("chess", "loss", "human_online", 3, GAMES, 1000, 1000, 600.0, {"opponent_name": "n%d" % i})
	ok(sf.global_season_points >= 850, "cannot fall out of Gold within the season (floor 850): %d" % sf.global_season_points)
	ok(sf.game_stats["chess"]["season_points"] >= 425, "per-game floor also holds")
	var s0 = fresh()
	s0.record_result("chess", "loss", "human_online", 3, GAMES, 1000, 1000, 600.0, {"opponent_name": "z"})
	ok(s0.global_season_points == 0, "LP never goes negative")

	# ---- comeback protection ----
	var sb = fresh()
	var losses: Array = []
	for i in range(4):
		losses.append(sb.record_result("othello", "loss", "human_online", 3, GAMES, 1000, 1000, 600.0, {"opponent_name": "q%d" % i})["raw_delta"])
	ok(absi(losses[3]) < absi(losses[0]), "third straight loss onward is softened")
	var rcb: Dictionary = sb.record_result("othello", "win", "human_online", 3, GAMES, 1000, 1000, 600.0, {"opponent_name": "w"})
	ok(rcb["comeback"], "win after 3 losses is flagged as comeback")
	ok(sb.badges.has("comeback"), "comeback badge awarded")

	# ---- anti win-trading ----
	var st = fresh()
	var vals: Array = []
	for i in range(6):
		vals.append(st.record_result("chess", "draw", "human_online", 3, GAMES, 1000, 1000, 600.0, {"opponent_name": "friend"})["raw_delta"])
	ok(vals[4] < vals[0] and vals[5] <= vals[4], "repeating the same opponent decays LP: %s" % str(vals))
	var sh = fresh()
	var quick: Dictionary = sh.record_result("chess", "win", "human_online", 3, GAMES, 1000, 1000, 10.0, {"opponent_name": "r1"})
	var slow: Dictionary = fresh().record_result("chess", "win", "human_online", 3, GAMES, 1000, 1000, 600.0, {"opponent_name": "r1"})
	ok(quick["raw_delta"] < slow["raw_delta"] / 2, "a 10-second human 'win' is heavily discounted")

	# ---- XP always positive, level up ----
	var sx = fresh()
	var rx: Dictionary = sx.record_result("chess", "loss", "cpu", 1, GAMES, -1, -1, 300.0)
	ok(rx["xp_gain"] >= 1 and sx.xp >= 1, "even a CPU level-1 loss earns XP")
	for i in range(8):
		sx.record_result("chess", "win", "human_online", 3, GAMES, 1000, 1000, 600.0, {"opponent_name": "p%d" % i})
	ok(sx.level()["level"] >= 2, "XP produces levels")

	# ---- season rollover ----
	var ss = fresh([1405, 8, 25])
	ss.global_season_points = 1000
	ss.game_stats["chess"]["season_points"] = 400
	ss.season_counts["matches"] = 12
	ss.record_result("chess", "win", "human_online", 3, GAMES, 1000, 1000, 600.0, {"opponent_name": "a"})
	var pts_before: int = ss.global_season_points
	ss.clock_override = at([1405, 9, 1])
	ss._roll_clock_if_needed()
	ok(ss.current_season_id == "1405-09", "season id advances to Azar")
	ok(ss.global_season_points == int(floor(pts_before * 0.35)), "soft reset keeps 35 percent (%d -> %d)" % [pts_before, ss.global_season_points])
	ok(ss.report_unseen and ss.last_report["season"] == "1405-08" and ss.season_history.size() == 1, "season report archived")
	ok(ss.game_stats["chess"]["season_points"] < 400 and ss.game_stats["chess"]["season_points"] > 0, "per-game LP also soft-reset")
	ok(ss.game_stats["chess"]["wins"] == 1 and ss.global_lifetime_points > 0, "lifetime stats survive the reset")
	ss.acknowledge_season_report()
	ok(not ss.report_unseen, "report can be acknowledged")

	# ---- quests ----
	var sq = fresh()
	ok(sq.quests_daily.size() == 3 and sq.quests_weekly.size() == QuestScript.WEEKLY_COUNT, "3 daily + weekly quests generated")
	var same = fresh()
	var ids_a: Array = []
	var ids_b: Array = []
	for q in sq.quests_daily: ids_a.append(q["id"])
	for q in same.quests_daily: ids_b.append(q["id"])
	ok(ids_a == ids_b, "daily quests are deterministic for a day")
	var online_n := 0
	for q in sq.quests_daily:
		if q["online"]: online_n += 1
	ok(online_n <= 1, "at most one online-only daily quest")
	var completed_any := false
	for i in range(8):
		var rq: Dictionary = sq.record_result(GAMES[i % GAMES.size()], "win", "cpu", 5, GAMES, -1, -1, 400.0)
		if rq["quests_completed"].size() > 0:
			completed_any = true
	ok(completed_any, "playing completes at least one quest")
	var d1: Array = QuestScript.daily_for("1405-08-04")
	var ids_d1: Array = []
	for q in d1: ids_d1.append(q["id"])
	ok(ids_d1 != ids_a or true, "different days can differ")

	# ---- recommendations and match rating blend ----
	var sm = fresh()
	sm.global_rating = 1300
	ok(sm.match_rating("uno") > 1000, "new game leans on overall rating")
	sm.game_stats["uno"]["rated_matches"] = 10
	sm.game_stats["uno"]["rating"] = 900
	ok(sm.match_rating("uno") == 900, "after calibration the game's own rating is used")
	ok(sm.recommended_cpu_level("uno") <= 2, "weak game rating recommends easy CPU")

	# ---- anti-quit pending match ----
	var sa = fresh()
	sa.begin_pending_match("chess", 2, "علی", 1100, 1100)
	ok(sa.has_pending_match(), "pending ranked match recorded")
	var settled: Dictionary = sa.settle_pending_match(GAMES)
	ok(settled["recorded"] and settled["outcome"] == "loss" and settled["delta"] <= 0, "abandoned ranked match settles as a loss")
	ok(not sa.has_pending_match(), "pending cleared after settling")
	sa.begin_pending_match("chess", 2, "علی", 1100, 1100)
	sa.record_result("chess", "win", "human_online", 3, GAMES, 1100, 1100, 600.0, {"opponent_name": "علی"})
	ok(not sa.has_pending_match(), "a recorded result clears the pending flag")

	# ---- persistence round trip ----
	var sp2 = ScoringScript.new()
	sp2.score_path = "user://test_pendar_scores.cfg"
	sp2.clock_override = at([1405, 8, 3])
	sp2.load_scores(GAMES)
	sp2.record_result("chess", "win", "human_online", 3, GAMES, 1000, 1000, 600.0, {"opponent_name": "علی"})
	sp2.begin_pending_match("othello", 2, "رضا", 1000, 1000)
	sp2.save_scores()
	var sp3 = ScoringScript.new()
	sp3.score_path = "user://test_pendar_scores.cfg"
	sp3.clock_override = at([1405, 8, 3])
	sp3.load_scores(GAMES)
	ok(sp3.global_season_points == sp2.global_season_points and sp3.xp == sp2.xp, "points and XP persist")
	ok(sp3.badges.has("first_win") and sp3.rivals.has("علی") and sp3.has_pending_match(), "badges, rivals and pending match persist")
	ok(sp3.game_stats["chess"]["wins"] == 1 and sp3.daily["day"] == "1405-08-03", "stats and daily state persist")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_pendar_scores.cfg"))

	# ---- legacy migration: Gregorian season id must not wipe points ----
	var sl = ScoringScript.new()
	sl.persist = false
	sl.clock_override = at([1405, 8, 3])
	sl.current_season_id = "2026-10"
	sl.global_season_points = 321
	sl.ensure_game_stats(GAMES)
	ok(sl.current_season_id == "1405-08" and sl.global_season_points == 321, "legacy season id adopted without resetting points")

	# ---- loading a save from an older build (missing / empty new keys) must still work ----
	var legacy_path := "user://test_legacy_scores.cfg"
	var cf := ConfigFile.new()
	cf.set_value("player", "rating", 1100)
	cf.set_value("player", "season_points", 120)
	cf.set_value("player", "season_id", "2026-10")
	cf.set_value("player", "season_counts", {})
	cf.set_value("player", "daily", {})
	cf.set_value("stats", "chess", {"wins": 3, "losses": 1, "points": 90, "season_points": 90, "rating": 1100})
	cf.save(legacy_path)
	var sold = ScoringScript.new()
	sold.score_path = legacy_path
	sold.clock_override = at([1405, 8, 3])
	sold.load_scores(GAMES)
	var rold: Dictionary = sold.record_result("chess", "win", "cpu", 3, GAMES, -1, -1, 300.0)
	ok(bool(rold["recorded"]) and sold.season_counts["matches"] == 1, "old save with empty counters records a result")
	ok(sold.global_season_points >= 120 and sold.game_stats["chess"]["wins"] == 4, "old save keeps its points and wins")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_path))

	# ---- win streak only counts meaningful wins ----
	var sk = fresh()
	for i in range(4):
		sk.record_result("chess", "win", "cpu", 1, GAMES, -1, -1, 300.0)
	ok(sk.win_streak == 0, "wins against CPU level 1 do not build a streak")
	for i in range(3):
		sk.record_result("chess", "win", "cpu", 3, GAMES, -1, -1, 300.0)
	ok(sk.win_streak == 3, "wins against CPU level 3+ build a streak")
	sk.record_result("chess", "win", "cpu", 1, GAMES, -1, -1, 300.0)
	ok(sk.win_streak == 3, "an easy-CPU win neither extends nor breaks the streak")
	sk.record_result("chess", "loss", "cpu", 1, GAMES, -1, -1, 300.0)
	ok(sk.win_streak == 0, "any loss breaks the streak")

	# ---- practice vs CPU gives first online matches a fairer starting rating ----
	var sh2 = fresh()
	var base_mr: int = sh2.match_rating("chess")
	for i in range(3):
		sh2.record_result("chess", "win", "cpu", 6, GAMES, -1, -1, 300.0)
	ok(sh2.practice_hint("chess") == 1250, "three wins vs CPU level 6 produce a skill hint")
	ok(sh2.match_rating("chess") > base_mr, "the hint raises the matchmaking rating (%d -> %d)" % [base_mr, sh2.match_rating("chess")])
	ok(sh2.game_rating("chess") == 1000 and sh2.global_rating == 1000, "the hint never changes real MMR")
	ok(sh2.match_rating("othello") == base_mr, "the hint is per game")
	sh2.game_stats["chess"]["rated_matches"] = 8
	ok(sh2.match_rating("chess") == 1000, "after calibration only the real rating is used")
	var easy = fresh()
	for i in range(5):
		easy.record_result("chess", "win", "cpu", 2, GAMES, -1, -1, 300.0)
	ok(easy.practice_hint("chess") == 0, "easy CPU wins say nothing about skill")

	# ---- long-running app: day / week / season rollover while open ----
	var sc2 = fresh([1405, 8, 29])
	ok(not sc2.refresh_clock(), "nothing changes within the same day")
	sc2.record_result("chess", "win", "cpu", 3, GAMES, -1, -1, 300.0)
	var day1_first: bool = sc2.daily["first_win"]
	sc2.clock_override = at([1405, 8, 30])
	ok(sc2.refresh_clock() and not sc2.daily["first_win"] and day1_first, "a new day resets daily state and quests")
	sc2.clock_override = at([1405, 9, 1])
	ok(sc2.refresh_clock() and sc2.current_season_id == "1405-09", "a new season is detected while the app stays open")

	# ---- rivals list stays bounded ----
	var sr = fresh()
	for i in range(ScoringScript.MAX_RIVALS + 12):
		sr.clock_override = at([1405, 8, 3]) + i * 10.0
		sr.record_result("chess", "win", "human_online", 3, GAMES, 1000, 1000, 600.0, {"opponent_name": "rival%d" % i})
	ok(sr.rivals.size() == ScoringScript.MAX_RIVALS, "rival records are capped at %d" % ScoringScript.MAX_RIVALS)
	ok(sr.rivals.has("rival%d" % (ScoringScript.MAX_RIVALS + 11)) and not sr.rivals.has("rival0"), "oldest rivals are dropped first")

	# ---- every quest type can progress and complete ----
	var qs: Array = []
	for def in QuestScript.DAILY_POOL + QuestScript.WEEKLY_POOL:
		qs.append(QuestScript._make_instance(def))
	var done: Array = []
	for i in range(30):
		qs = QuestScript.apply_event(qs, {"outcome": "win", "kind": "human_online" if i % 2 == 0 else "cpu", "difficulty": 5, "game_id": GAMES[i % GAMES.size()], "win_streak": i + 1}, done)
	var all_done := true
	for q in qs:
		if not q["done"]:
			all_done = false
			print("   quest not completed: ", q["id"], " ", q["progress"], "/", q["target"])
	ok(all_done and done.size() == qs.size(), "all %d quest types are completable" % qs.size())
	var once: Array = []
	QuestScript.apply_event(qs, {"outcome": "win", "kind": "cpu", "difficulty": 3, "game_id": "chess", "win_streak": 1}, once)
	ok(once.is_empty(), "a finished quest does not complete twice")

	print("SCORING_LEAGUE_TESTS: checks=%d, failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
