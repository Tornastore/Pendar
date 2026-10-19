extends RefCounted
## Shared contract for game rule modules.
## Board-specific state and rule implementation live in each game's own folder.
enum State { MENU, MODE, LOBBY, IP_ENTRY, PLAYING, RESULT, DASHBOARD, RANKINGS, ONLINE }

var app
var game_id: String = ""

func bind(host, module_id: String) -> void:
	app = host
	game_id = module_id

func reset_game() -> void:
	pass

func get_game_id() -> String:
	return game_id
