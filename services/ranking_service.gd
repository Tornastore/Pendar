extends RefCounted
## Ranking presentation and tier rules are separate from score recording and game rules.
const LeagueScript = preload("res://services/league_service.gd")

## One row per game: that game's own league (independent ladder), skill rating, record and mastery.
static func build_game_rows(games: Array, game_stats: Dictionary) -> Array:
	var rows: Array = []
	for game in games:
		var id := str(game.get("id", ""))
		var stats: Dictionary = game_stats.get(id, {})
		var pts: int = int(stats.get("season_points", 0))
		rows.append({
			"id": id,
			"name": str(game.get("name", id)),
			"pts": pts,
			"rating": int(stats.get("rating", 1000)),
			"col": game.get("icon_col", Color.WHITE),
			"w": int(stats.get("wins", 0)),
			"d": int(stats.get("draws", 0)),
			"l": int(stats.get("losses", 0)),
			"tier": LeagueScript.tier_for_points(pts, LeagueScript.GAME_LADDER_SCALE),
			"mastery": LeagueScript.mastery_info(int(stats.get("xp", 0))),
			"played": int(stats.get("wins", 0)) + int(stats.get("draws", 0)) + int(stats.get("losses", 0)),
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

# Permanent skill rank: only human online matches change this MMR.
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

## Monthly league as the legacy [label, color, lower, upper] array (label includes the division, e.g. "طلا ۲").
static func season_tier_info(points: int) -> Array:
	var t: Dictionary = LeagueScript.tier_for_points(points)
	return [str(t["label"]), t["col"], int(t["floor"]), int(t["next_threshold"]) if int(t["next_threshold"]) >= 0 else int(t["floor"])]

## One-line, human wording for "how close am I to the next step", e.g. "۴۲ امتیاز تا طلا ۱ · حدود ۲ برد".
static func progress_hint(tier: Dictionary, points_per_win: int) -> String:
	if bool(tier.get("is_top", false)):
		return "در بالاترین لیگ هستی؛ امتیازت را بالاتر ببر"
	var need: int = int(tier.get("to_next", 0))
	var wins: int = int(ceil(float(need) / float(maxi(1, points_per_win))))
	return "%s امتیاز تا %s · حدود %s برد" % [_fa(need), str(tier.get("next_label", "")), _fa(wins)]

## Signed number that keeps its sign on the left of the digits inside right-to-left text (e.g. "+۵۷", "−۱۲").
static func signed(v: int) -> String:
	var sign := "+" if v > 0 else ("−" if v < 0 else "")
	return "\u2066" + sign + _fa(absi(v)) + "\u2069"

static func _fa(v: Variant) -> String:
	var s := str(v)
	var out := ""
	for i in s.length():
		var c: int = s.unicode_at(i)
		out += String.chr(0x06F0 + c - 48) if c >= 48 and c <= 57 else s[i]
	return out
