extends SceneTree
## Boots the real main scene and draws every league-related screen so runtime errors in presenters surface in CI.

var main: Node
var draws := 0
var failures := 0
var checks := 0

func _frames(n: int = 3) -> void:
	for i in n:
		main.queue_redraw()
		await process_frame

func _check(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)

func _init() -> void:
	var packed: PackedScene = load("res://main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	main.draw.connect(func(): draws += 1)
	await _frames(3)
	main.scoring_service.persist = false
	main.scoring_service.pending_match = {}
	_check(draws > 0, "main scene draws in headless mode (draw signal fired %d times)" % draws)
	var base_draws := draws

	# Menu
	await _frames()
	# Record a few matches across games/modes to populate every section
	var ids: Array = main._game_ids()
	var seq := [["chess", "win", "cpu"], ["chess", "win", "cpu"], ["othello", "loss", "cpu"], ["uno", "draw", "cpu"], ["chess", "win", "human_online"]]
	for item in seq:
		main.selected_game = item[0]
		main.vs_cpu = item[2] == "cpu"
		main.ws_match_active = item[2] == "human_online"
		main._game_started_msec = Time.get_ticks_msec() - 300000
		var r: Dictionary = main._record_match_result(item[1], 1040, 1040, {"opponent_name": "علی"})
		_check(bool(r.get("recorded", false)), "recorded %s %s" % [item[0], item[1]])
	main.ws_match_active = false

	# Opponent kind detection: offline / same-device games must never score (Godot always has an offline peer object).
	main.vs_cpu = false
	main.ws_match_active = false
	main.selected_game = "chess"
	_check(main._opponent_kind() == "local_friendly", "offline game is unranked")
	main.selected_game = "mastermind"
	main.mm_local_two_player = true
	_check(main._opponent_kind() == "local_friendly", "same-device Mastermind is unranked")
	main.mm_local_two_player = false
	main.selected_game = "quoridor"
	main._game_modules["quoridor"].quo_local_multiplayer = true
	_check(main._opponent_kind() == "local_friendly", "same-device Quoridor is unranked")
	main._game_modules["quoridor"].quo_local_multiplayer = false
	var lan_peer := ENetMultiplayerPeer.new()
	if lan_peer.create_server(47123, 1) == OK:
		main.multiplayer.multiplayer_peer = lan_peer
		main.selected_game = "chess"
		_check(main._opponent_kind() == "human_lan", "a real LAN/IP peer is a friendly network game")
		var lan_res: Dictionary = main._record_match_result("win", -1, -1, {"opponent_name": "دوست"})
		_check(bool(lan_res.get("recorded", false)) and int(lan_res.get("rating_delta", 0)) == 0, "LAN result scores LP but never MMR")
		main.multiplayer.multiplayer_peer = null
	main.ws_match_active = true
	_check(main._opponent_kind() == "human_online", "matchmaker games are ranked")
	main.ws_match_active = false
	main.vs_cpu = true
	_check(main._opponent_kind() == "cpu", "CPU games are CPU kind")
	main.vs_cpu = false

	# Mode screen for each game (reward preview, star, recommended level)
	for gid in ids:
		main._select_game(gid)
		await _frames(2)
	_check(main.state == main.State.MODE, "mode screen reached for every game")

	# Rankings, three tabs
	main._open_rankings()
	for tab in [0, 1, 2]:
		main._set_rank_tab(tab)
		await _frames(2)
		main.scroll_y = 120.0
		await _frames(2)
		main.scroll_y = 0.0
	_check(main.state == main.State.RANKINGS, "rankings tabs rendered")

	# Dashboard & online
	main._open_dashboard()
	await _frames(3)
	main._open_online()
	await _frames(3)

	# Result popup with a full score result (promotion, quests, badges)
	main.selected_game = "chess"
	main.vs_cpu = true
	main.state = main.State.PLAYING
	main._result_logged = true
	main._result_popup_open = true
	main._result_draw = false
	main._result_t0 = main._time
	for i in range(30):
		main._game_started_msec = Time.get_ticks_msec() - 600000
		main._last_score_result = main._record_match_result("win")
	main._rebuild_buttons()
	await _frames(4)
	var res: Dictionary = main._last_score_result
	_check(res.has("chips") and res.has("tier_after"), "result carries chips and tier data")
	# Unranked result
	main._last_score_result = {"recorded": false}
	await _frames(3)
	# Force a league-up presentation
	main.scoring_service.global_season_points = 295
	main._game_started_msec = Time.get_ticks_msec() - 600000
	main._last_score_result = main._record_match_result("win")
	await _frames(4)

	# Menu again
	main.state = main.State.MENU
	main._rebuild_buttons()
	await _frames(3)
	_check(draws > base_draws + 20, "all screens drew without stopping the draw loop (%d draws)" % draws)
	print("LEAGUE_UI_TESTS: checks=%d, failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
