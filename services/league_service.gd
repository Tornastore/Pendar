extends RefCounted
## Pendar League ladder: leagues, divisions, titles, XP levels and the Jalali season calendar.
## Pure static helpers only (no storage, no UI) so every rule here is unit-testable in headless Godot.

# ---------------------------------------------------------------------------
# Season calendar (Jalali / Persian). A season is one Jalali month, switching at 00:00 Tehran time.
# ---------------------------------------------------------------------------
const TEHRAN_UTC_OFFSET_SECONDS := 12600 # UTC+03:30 (Iran has no DST since 2022)
const JALALI_MONTHS: Array[String] = [
	"فروردین", "اردیبهشت", "خرداد", "تیر", "مرداد", "شهریور",
	"مهر", "آبان", "آذر", "دی", "بهمن", "اسفند",
]
const _JALALI_BREAKS: Array[int] = [-61, 9, 38, 199, 426, 686, 756, 818, 1111, 1181, 1210, 1635, 2060, 2097, 2192, 2262, 2324, 2394, 2456, 3178]

# The jalaali algorithm relies on integer division that truncates toward zero (GDScript int / int does).
static func _div(a: int, b: int) -> int:
	return a / b

static func _mod(a: int, b: int) -> int:
	return a - (a / b) * b

static func _floor_div(a: int, b: int) -> int:
	return int(floor(float(a) / float(b)))

# Port of the public-domain jalaali algorithm: returns {"leap": 0..4, "gy": int, "march": int}.
static func _jal_cal(jy: int) -> Dictionary:
	var bl: int = _JALALI_BREAKS.size()
	var gy: int = jy + 621
	var leap_j: int = -14
	var jp: int = _JALALI_BREAKS[0]
	var jm: int = 0
	var jump: int = 0
	for i in range(1, bl):
		jm = _JALALI_BREAKS[i]
		jump = jm - jp
		if jy < jm:
			break
		leap_j += _div(jump, 33) * 8 + _div(_mod(jump, 33), 4)
		jp = jm
	var n: int = jy - jp
	leap_j += _div(n, 33) * 8 + _div(_mod(n, 33) + 3, 4)
	if _mod(jump, 33) == 4 and jump - n == 4:
		leap_j += 1
	var leap_g: int = _div(gy, 4) - _div((_div(gy, 100) + 1) * 3, 4) - 150
	var march: int = 20 + leap_j - leap_g
	if jump - n < 6:
		n = n - jump + _div(jump + 4, 33) * 33
	var leap: int = _mod(_mod(n + 1, 33) - 1, 4)
	if leap == -1:
		leap = 4
	return {"leap": leap, "gy": gy, "march": march}

static func _g2d(gy: int, gm: int, gd: int) -> int:
	var d: int = _div((gy + _div(gm - 8, 6) + 100100) * 1461, 4) + _div(153 * _mod(gm + 9, 12) + 2, 5) + gd - 34840408
	d = d - _div(_div(gy + 100100 + _div(gm - 8, 6), 100) * 3, 4) + 752
	return d

static func _d2g(jdn: int) -> Dictionary:
	var j: int = 4 * jdn + 139361631
	j = j + _div(_div(4 * jdn + 183187720, 146097) * 3, 4) * 4 - 3908
	var i: int = _div(_mod(j, 1461), 4) * 5 + 308
	var gd: int = _div(_mod(i, 153), 5) + 1
	var gm: int = _mod(_div(i, 153), 12) + 1
	var gy: int = _div(j, 1461) - 100100 + _div(8 - gm, 6)
	return {"gy": gy, "gm": gm, "gd": gd}

static func _j2d(jy: int, jm: int, jd: int) -> int:
	var r: Dictionary = _jal_cal(jy)
	return _g2d(int(r["gy"]), 3, int(r["march"])) + (jm - 1) * 31 - _div(jm, 7) * (jm - 7) + jd - 1

static func _d2j(jdn: int) -> Dictionary:
	var gy: int = int(_d2g(jdn)["gy"])
	var jy: int = gy - 621
	var r: Dictionary = _jal_cal(jy)
	var jdn1f: int = _g2d(gy, 3, int(r["march"]))
	var k: int = jdn - jdn1f
	if k >= 0:
		if k <= 185:
			return {"y": jy, "m": 1 + _div(k, 31), "d": _mod(k, 31) + 1}
		k -= 186
	else:
		jy -= 1
		k += 179
		if int(r["leap"]) == 1:
			k += 1
	return {"y": jy, "m": 7 + _div(k, 30), "d": _mod(k, 30) + 1}

static func is_jalali_leap(jy: int) -> bool:
	return int(_jal_cal(jy)["leap"]) == 0

static func jalali_month_length(jy: int, jm: int) -> int:
	if jm <= 6:
		return 31
	if jm <= 11:
		return 30
	return 30 if is_jalali_leap(jy) else 29

static func jalali_from_gregorian(gy: int, gm: int, gd: int) -> Dictionary:
	return _d2j(_g2d(gy, gm, gd))

static func gregorian_from_jalali(jy: int, jm: int, jd: int) -> Dictionary:
	return _d2g(_j2d(jy, jm, jd))

## Jalali date at a unix timestamp in Tehran local time: {"y","m","d","weekday"} (weekday 0 = Saturday).
static func jalali_from_unix(unix_time: float) -> Dictionary:
	var local: int = int(floor(unix_time)) + TEHRAN_UTC_OFFSET_SECONDS
	var days: int = _floor_div(local, 86400)
	# 1970-01-01 (day 0) was a Thursday; Saturday-based index: Thu = 5.
	var weekday: int = days + 5 - _floor_div(days + 5, 7) * 7
	var jdn: int = _g2d(1970, 1, 1) + days
	var j: Dictionary = _d2j(jdn)
	j["weekday"] = weekday
	j["jdn"] = jdn
	return j

static func season_id_at(unix_time: float) -> String:
	var j: Dictionary = jalali_from_unix(unix_time)
	return "%04d-%02d" % [int(j["y"]), int(j["m"])]

static func day_id_at(unix_time: float) -> String:
	var j: Dictionary = jalali_from_unix(unix_time)
	return "%04d-%02d-%02d" % [int(j["y"]), int(j["m"]), int(j["d"])]

## Saturday-based week id: the Jalali date of the Saturday that started the current week.
static func week_id_at(unix_time: float) -> String:
	var j: Dictionary = jalali_from_unix(unix_time)
	var start_jdn: int = int(j["jdn"]) - int(j["weekday"])
	var s: Dictionary = _d2j(start_jdn)
	return "%04d-%02d-%02d" % [int(s["y"]), int(s["m"]), int(s["d"])]

static func is_valid_season_id(id: String) -> bool:
	if id.length() != 7 or id[4] != "-":
		return false
	var y: int = int(id.substr(0, 4))
	var m: int = int(id.substr(5, 2))
	return y >= 1300 and y <= 1700 and m >= 1 and m <= 12

static func season_label(season_id: String) -> String:
	if not is_valid_season_id(season_id):
		return "فصل جاری"
	var m: int = int(season_id.substr(5, 2))
	return "فصل %s %s" % [JALALI_MONTHS[m - 1], _fa_digits(season_id.substr(0, 4))]

## Whole days left after today before the season (Jalali month) ends.
static func days_left_in_season(unix_time: float) -> int:
	var j: Dictionary = jalali_from_unix(unix_time)
	return jalali_month_length(int(j["y"]), int(j["m"])) - int(j["d"])

static func _fa_digits(s: String) -> String:
	var out := ""
	for i in s.length():
		var c: int = s.unicode_at(i)
		out += String.chr(0x06F0 + c - 48) if c >= 48 and c <= 57 else s[i]
	return out

# ---------------------------------------------------------------------------
# League ladder
# ---------------------------------------------------------------------------
## "start" = league-points where the league begins; "gate" = minimum skill rating (MMR) required to enter.
## Players who are one league below a gate keep earning points up to (start - 1) but cannot pass until MMR allows.
const LEAGUES: Array = [
	{"id": "bronze", "name": "برنز", "title": "نوب", "start": 0, "divs": 3, "gate": 0, "col": Color(0.82, 0.53, 0.32)},
	{"id": "silver", "name": "نقره", "title": "رُکی", "start": 300, "divs": 3, "gate": 0, "col": Color(0.78, 0.83, 0.91)},
	{"id": "gold", "name": "طلا", "title": "گرایندر", "start": 850, "divs": 3, "gate": 0, "col": Color(1.0, 0.80, 0.30)},
	{"id": "platinum", "name": "پلاتین", "title": "تری‌هارد", "start": 1700, "divs": 3, "gate": 1000, "col": Color(0.42, 0.90, 0.88)},
	{"id": "diamond", "name": "الماس", "title": "پرو", "start": 2800, "divs": 3, "gate": 1100, "col": Color(0.48, 0.76, 1.0)},
	{"id": "master", "name": "مستر", "title": "الیت", "start": 4300, "divs": 3, "gate": 1200, "col": Color(0.83, 0.53, 1.0)},
	{"id": "grandmaster", "name": "گرندمستر", "title": "چمپیون", "start": 6200, "divs": 3, "gate": 1300, "col": Color(1.0, 0.45, 0.55)},
	{"id": "legend", "name": "لجند", "title": "لجند", "start": 8800, "divs": 1, "gate": 1400, "col": Color(1.0, 0.66, 0.86)},
]
const ROMAN_DIVISION_FA: Array[String] = ["", "۱", "۲", "۳"]

## Per-game ladders use the same leagues on a compressed scale (a game sees fewer matches than the whole app).
const GAME_LADDER_SCALE := 0.5
## Practice (CPU / bonus) points can lift a player only up to the top of Gold; higher leagues need real opponents.
const PRACTICE_CEILING_GLOBAL := 1699
const PRACTICE_CEILING_GAME := 849
## Fraction of last season's points kept when a new season starts (soft reset).
const SEASON_CARRY := 0.35

static func league_count() -> int:
	return LEAGUES.size()

static func scaled_start(league_index: int, scale: float = 1.0) -> int:
	var i: int = clampi(league_index, 0, LEAGUES.size() - 1)
	return int(round(float(LEAGUES[i]["start"]) * scale))

static func league_index_for_points(points: int, scale: float = 1.0) -> int:
	var idx := 0
	for i in range(LEAGUES.size()):
		if points >= scaled_start(i, scale):
			idx = i
	return idx

## Full description of where a point total sits on the ladder.
## Keys: league(int), id, name, title, col, division(1..3, 0 for the top league), label, floor, next_threshold(-1 at top),
## to_next (points to the next division/league, 0 at the top), progress (0..1 inside current division), is_top.
static func tier_for_points(points: int, scale: float = 1.0) -> Dictionary:
	var p: int = maxi(0, points)
	var li: int = league_index_for_points(p, scale)
	var lg: Dictionary = LEAGUES[li]
	var lstart: int = scaled_start(li, scale)
	var is_top: bool = li == LEAGUES.size() - 1
	var divs: int = int(lg["divs"])
	var info: Dictionary = {
		"league": li, "id": lg["id"], "name": lg["name"], "title": lg["title"], "col": lg["col"],
		"floor": lstart, "is_top": is_top, "points": p,
	}
	if is_top:
		info["division"] = 0
		info["label"] = str(lg["name"])
		info["next_threshold"] = -1
		info["to_next"] = 0
		info["progress"] = 1.0
		info["next_label"] = ""
		return info
	var lend: int = scaled_start(li + 1, scale)
	var width: float = float(lend - lstart)
	var d_index: int = mini(divs - 1, int(floor(float(p - lstart) / (width / float(divs)))))
	var d_start: int = lstart + int(round(width * float(d_index) / float(divs)))
	var d_end: int = lstart + int(round(width * float(d_index + 1) / float(divs)))
	var division: int = divs - d_index # III -> II -> I (3 is the lowest division)
	info["division"] = division
	info["label"] = "%s %s" % [lg["name"], ROMAN_DIVISION_FA[division]]
	info["next_threshold"] = d_end
	info["to_next"] = maxi(0, d_end - p)
	info["progress"] = clampf(float(p - d_start) / maxf(1.0, float(d_end - d_start)), 0.0, 1.0)
	if d_index == divs - 1:
		info["next_label"] = str(LEAGUES[li + 1]["name"]) + (" " + ROMAN_DIVISION_FA[int(LEAGUES[li + 1]["divs"])] if int(LEAGUES[li + 1]["divs"]) > 1 else "")
	else:
		info["next_label"] = "%s %s" % [lg["name"], ROMAN_DIVISION_FA[division - 1]]
	return info

## MMR required to enter the league that starts at or above `points`, or 0 when no gate applies.
static func gate_rating_for_league(league_index: int) -> int:
	return int(LEAGUES[clampi(league_index, 0, LEAGUES.size() - 1)]["gate"])

## Highest point total reachable with `mmr` on a ladder with this scale: one point below the first closed gate.
static func gate_cap_points(mmr: int, scale: float = 1.0) -> int:
	for i in range(LEAGUES.size()):
		if int(LEAGUES[i]["gate"]) > mmr:
			return scaled_start(i, scale) - 1
	return 1 << 30

## Points kept for the next season.
static func carry_over_points(final_points: int) -> int:
	return maxi(0, int(floor(float(maxi(0, final_points)) * SEASON_CARRY)))

# ---------------------------------------------------------------------------
# Account level (XP is lifetime and never decreases) and per-game mastery
# ---------------------------------------------------------------------------
const MAX_LEVEL := 100
const MASTERY_THRESHOLDS: Array[int] = [0, 80, 200, 400, 700, 1100, 1700, 2500, 3600, 5000]
const MASTERY_NAMES: Array[String] = ["آشنا", "تازه‌کار", "شاگرد", "ماهر", "کاربلد", "خبره", "استاد", "استادِ ارشد", "افسانه‌ای", "اسطوره"]

static func xp_to_reach_level(level: int) -> int:
	var l: int = clampi(level, 1, MAX_LEVEL)
	return 80 * (l - 1) + 10 * l * (l - 1)

## {"level", "xp", "into", "need", "progress"} for an XP total.
static func level_info(xp: int) -> Dictionary:
	var total: int = maxi(0, xp)
	var level := 1
	while level < MAX_LEVEL and total >= xp_to_reach_level(level + 1):
		level += 1
	var base: int = xp_to_reach_level(level)
	if level >= MAX_LEVEL:
		return {"level": level, "xp": total, "into": 0, "need": 0, "progress": 1.0}
	var need: int = xp_to_reach_level(level + 1) - base
	var into: int = total - base
	return {"level": level, "xp": total, "into": into, "need": need, "progress": clampf(float(into) / float(maxi(1, need)), 0.0, 1.0)}

## {"stars" 1..10, "name", "into", "need", "progress"} for per-game mastery XP.
static func mastery_info(xp: int) -> Dictionary:
	var total: int = maxi(0, xp)
	var stars := 1
	for i in range(MASTERY_THRESHOLDS.size()):
		if total >= MASTERY_THRESHOLDS[i]:
			stars = i + 1
	var top: bool = stars >= MASTERY_THRESHOLDS.size()
	var base: int = MASTERY_THRESHOLDS[stars - 1]
	var need: int = 0 if top else MASTERY_THRESHOLDS[stars] - base
	return {"stars": stars, "name": MASTERY_NAMES[stars - 1], "into": total - base, "need": need, "progress": 1.0 if top else clampf(float(total - base) / float(maxi(1, need)), 0.0, 1.0)}
