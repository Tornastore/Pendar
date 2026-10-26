extends SceneTree
## Feeds real server messages into the client and checks ranked-match bookkeeping (pending match, forfeits, ratings).

var main: Node
var checks := 0
var failures := 0

func ck(c: bool, l: String) -> void:
	checks += 1
	if c:
		print("PASS: ", l)
	else:
		failures += 1
		print("FAIL: ", l)

func match_found(game: String = "chess", opp_rating: int = 1180, opp_name: String = "علی") -> Dictionary:
	return {
		"type": "match_found", "game": game, "room_id": "room1", "seat": 0, "player_count": 2, "seed": 7,
		"opponent_username": opp_name, "opponent_rating": opp_rating, "opponent_global_rating": opp_rating - 20, "opponent_league": 3,
		"players": [{"seat": 0, "username": "من", "rating": 1000, "league": 1}, {"seat": 1, "username": opp_name, "rating": opp_rating, "league": 3}],
	}

func fresh_main() -> Node:
	if main != null:
		main.queue_free()
		await process_frame
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.scoring_service.persist = false
	main.scoring_service.pending_match = {}
	main.scoring_service.global_season_points = 400
	main.scoring_service.game_stats["chess"]["season_points"] = 200
	return main

func _init() -> void:
	# ---- 1. match found: opponent data, pending match, ranked kind ----
	await fresh_main()
	main._ws_handle_server_message(match_found())
	await process_frame
	ck(main.ws_match_active and main.state == main.State.PLAYING, "match_found starts a ranked game")
	ck(main._opp_match_rating == 1180 and main._opp_league == 3, "opponent rating and league are stored")
	ck(main._opponent_kind() == "human_online", "online matchmaker game is ranked human")
	ck(main.scoring_service.has_pending_match() and int(main.scoring_service.pending_match["opp_rating"]) == 1180, "pending match saved with opponent rating")
	ck(main._match_player_count() == 2, "two-player count")

	# ---- 2. opponent leaves mid-game: forfeit win, pending cleared ----
	var pts_before: int = main.scoring_service.global_season_points
	var mmr_before: int = main.scoring_service.game_rating("chess")
	main._ws_handle_server_message({"type": "opponent_left", "reason": "leave"})
	await process_frame
	var res: Dictionary = main._last_score_result
	ck(bool(res.get("recorded", false)) and res.get("outcome") == "win", "opponent leaving records a win")
	ck(main.scoring_service.global_season_points > pts_before, "the forfeit win gives league points")
	ck(main.scoring_service.game_rating("chess") > mmr_before, "the forfeit win raises MMR")
	var has_forfeit := false
	for c in res.get("chips", []):
		if c["key"] == "forfeit": has_forfeit = true
	ck(has_forfeit, "forfeit win is discounted and labelled")
	ck(not main.scoring_service.has_pending_match() and not main.ws_match_active, "pending cleared and match closed")
	ck(main.state == main.State.ONLINE, "player returns to the online screen")

	# ---- 3. leaving the match yourself is a loss ----
	await fresh_main()
	main._ws_handle_server_message(match_found("othello", 1000, "رضا"))
	await process_frame
	var pts2: int = main.scoring_service.global_season_points
	main._back_to_menu()
	await process_frame
	ck(main._last_score_result.get("outcome") == "loss" and bool(main._last_score_result.get("recorded", false)), "leaving a ranked match records a loss")
	ck(main.scoring_service.global_season_points < pts2, "the loss costs league points")
	ck(not main.scoring_service.has_pending_match(), "pending cleared after leaving")
	ck(main._opp_match_rating == -1, "opponent info is cleared on returning to the menu")

	# ---- 4. a finished match must not be punished when the player leaves afterwards ----
	await fresh_main()
	main._ws_handle_server_message(match_found("chess", 1000, "سارا"))
	await process_frame
	main._game_started_msec = Time.get_ticks_msec() - 300000
	main._result_logged = true
	main._record_match_result("win")
	var pts3: int = main.scoring_service.global_season_points
	var games_before: int = main.scoring_service.total_matches()
	main._back_to_menu()
	await process_frame
	ck(main.scoring_service.total_matches() == games_before and main.scoring_service.global_season_points == pts3, "leaving after the result adds nothing")

	# ---- 5. app closed mid-match -> settled as a loss on next launch ----
	await fresh_main()
	main._ws_handle_server_message(match_found("quoridor", 1100, "نگار"))
	await process_frame
	ck(main.scoring_service.has_pending_match(), "pending exists while the match runs")
	var sv = main.scoring_service
	sv.clock_override = sv.now() + 120.0
	var settled: Dictionary = sv.settle_pending_match(main._game_ids())
	ck(bool(settled.get("recorded", false)) and settled["outcome"] == "loss", "next launch settles the abandoned match as a loss")

	# ---- 6. multi-player room: opponent leaving gives no result but clears pending ----
	await fresh_main()
	var multi: Dictionary = match_found("mastermind", 1000, "الف، ب، ج")
	multi["player_count"] = 4
	multi["players"] = [{"seat": 0, "username": "من"}, {"seat": 1, "username": "الف"}, {"seat": 2, "username": "ب"}, {"seat": 3, "username": "ج"}]
	# No frames are drawn here: this checks bookkeeping only, not the game's own board rendering.
	main._ws_handle_server_message(multi)
	ck(main._match_player_count() == 4, "a 4-player online room is counted as 4 players")
	var total_before: int = main.scoring_service.total_matches()
	main._ws_handle_server_message({"type": "opponent_left", "reason": "leave"})
	ck(main.scoring_service.total_matches() == total_before and not main.scoring_service.has_pending_match(), "multi-player room closing records nothing and clears pending")

	# ---- 7. queue messages: search range and the CPU hint after a long wait ----
	await fresh_main()
	main._ws_handle_server_message({"type": "queued", "game": "chess", "position": 1, "players_needed": 1, "search_range": 250, "waited_ms": 31000})
	ck(main.online_status.find("±") >= 0, "queue status shows the widening search range")
	ck(main._queue_hint_shown, "a long wait suggests practising against the CPU")

	print("ONLINE_LEAGUE_TESTS: checks=%d, failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
