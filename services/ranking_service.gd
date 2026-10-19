extends RefCounted
## Ranking presentation and tier rules are separate from score recording and game rules.
static func build_game_rows(games: Array, game_stats: Dictionary) -> Array:
	var rows: Array = []
	for game in games:
		var id := str(game.get("id", ""))
		var stats: Dictionary = game_stats.get(id, {})
		rows.append({
			"id": id,
			"name": str(game.get("name", id)),
			"pts": int(stats.get("points", 0)),
			"col": game.get("icon_col", Color.WHITE),
			"w": int(stats.get("wins", 0)),
			"l": int(stats.get("losses", 0)),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.pts != b.pts:
			return int(a.pts) > int(b.pts)
		if a.w != b.w:
			return int(a.w) > int(b.w)
		if a.l != b.l:
			return int(a.l) < int(b.l)
		return str(a.id) < str(b.id)
	)
	return rows

static func tier_info(rating: int) -> Array:
	if rating < 900:
		return ["آهنی", Color(0.62, 0.66, 0.74), 0, 900]
	if rating < 1050:
		return ["برنزی", Color(0.85, 0.55, 0.30), 900, 1050]
	if rating < 1200:
		return ["نقره‌ای", Color(0.78, 0.84, 0.92), 1050, 1200]
	if rating < 1400:
		return ["طلایی", Color(1.0, 0.80, 0.30), 1200, 1400]
	return ["الماسی", Color(0.45, 0.88, 1.0), 1400, 1400]
