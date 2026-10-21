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
			"pts": int(stats.get("season_points", stats.get("points", 0))),
			"rating": int(stats.get("rating", 1000)),
			"col": game.get("icon_col", Color.WHITE),
			"w": int(stats.get("wins", 0)),
			"d": int(stats.get("draws", 0)),
			"l": int(stats.get("losses", 0)),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.pts != b.pts:
			return int(a.pts) > int(b.pts)
		if a.rating != b.rating:
			return int(a.rating) > int(b.rating)
		if a.w != b.w:
			return int(a.w) > int(b.w)
		return str(a.id) < str(b.id)
	)
	return rows

# Permanent skill rank: only human online matches should change this MMR.
static func tier_info(rating: int) -> Array:
	if rating < 850:
		return ["تازه‌وارد", Color(0.62, 0.66, 0.74), 100, 850]
	if rating < 1050:
		return ["آماتور", Color(0.70, 0.73, 0.80), 850, 1050]
	if rating < 1200:
		return ["نیمه‌حرفه‌ای", Color(0.78, 0.84, 0.92), 1050, 1200]
	if rating < 1350:
		return ["حرفه‌ای", Color(1.0, 0.80, 0.30), 1200, 1350]
	if rating < 1500:
		return ["نخبه", Color(0.45, 0.88, 1.0), 1350, 1500]
	if rating < 1650:
		return ["استاد", Color(0.48, 0.76, 1.0), 1500, 1650]
	if rating < 1850:
		return ["استادبزرگ", Color(0.83, 0.53, 1.0), 1650, 1850]
	return ["افسانه", Color(1.0, 0.61, 0.78), 1850, 1850]

# Monthly competitive league: resets at month boundary, unlike skill MMR.
static func season_tier_info(points: int) -> Array:
	if points < 0:
		return ["در حال بازگشت", Color(0.62, 0.66, 0.74), -100, 0]
	if points < 100:
		return ["تازه‌وارد", Color(0.62, 0.66, 0.74), 0, 100]
	if points < 250:
		return ["آماتور", Color(0.70, 0.73, 0.80), 100, 250]
	if points < 500:
		return ["نیمه‌حرفه‌ای", Color(0.78, 0.84, 0.92), 250, 500]
	if points < 900:
		return ["حرفه‌ای", Color(1.0, 0.80, 0.30), 500, 900]
	if points < 1400:
		return ["نخبه", Color(0.45, 0.88, 1.0), 900, 1400]
	if points < 2000:
		return ["استاد", Color(0.48, 0.76, 1.0), 1400, 2000]
	if points < 3000:
		return ["استادبزرگ", Color(0.83, 0.53, 1.0), 2000, 3000]
	return ["افسانه", Color(1.0, 0.61, 0.78), 3000, 3000]
