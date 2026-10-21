extends RefCounted
## Single source of truth for the public game catalogue.
static func all_games() -> Array:
	return [
		{"id": "othello", "name": "اتلو ۸×۸", "desc": "فتح خانه‌ها — نسخه کلاسیک", "short": "محاصره و تسخیر", "players": "2 نفر", "max_p": 2, "icon_col": Color(0.2, 0.7, 0.4), "cat": "strategy", "net": true, "beta": false},
		{"id": "othello12", "name": "اتلو ۱۲×۱۲", "desc": "اتلو روی صفحه بزرگ‌تر", "short": "صفحه بزرگ‌تر", "players": "2 نفر", "max_p": 2, "icon_col": Color(0.15, 0.62, 0.45), "cat": "strategy", "net": true, "beta": false},
		{"id": "pentago", "name": "پنتاگو", "desc": "۵ در یک ردیف + چرخش بخش‌ها", "short": "بچرخان و ببر", "players": "2 نفر", "max_p": 2, "icon_col": Color(0.85, 0.45, 0.2), "cat": "strategy", "net": true, "beta": false},
		{"id": "quoridor", "name": "کوریدور", "desc": "مسیر بساز و حریف را مسدود کن", "short": "دیوار بکش و برس", "players": "۲ یا ۴ نفر", "max_p": 4, "icon_col": Color(0.6, 0.4, 0.95), "cat": "strategy", "net": true, "beta": false},
		{"id": "chess", "name": "شطرنج", "desc": "کلاسیک‌ترین بازی فکری جهان", "short": "شاه را بگیر", "players": "2 نفر", "max_p": 2, "icon_col": Color(0.9, 0.75, 0.3), "cat": "strategy", "net": true, "beta": false},
		{"id": "domino", "name": "دومینو", "desc": "چینش مهره‌های سنگی", "short": "زنجیر بساز", "players": "2 نفر", "max_p": 2, "icon_col": Color(0.55, 0.65, 0.85), "cat": "classic", "net": true, "beta": false},
		{"id": "pasoor", "name": "چهاربرگ (پاسور)", "desc": "جمع ۱۱ — سور و هفت‌خاج", "short": "جمع ۱۱ و سور", "players": "2 نفر", "max_p": 2, "icon_col": Color(0.95, 0.35, 0.4), "cat": "cards", "net": true, "beta": false},
		{"id": "hokm", "name": "حکم", "desc": "ورق‌بازی ایرانی با حکم", "short": "حکم بزن", "players": "2 نفر", "max_p": 2, "icon_col": Color(0.9, 0.3, 0.55), "cat": "cards", "net": true, "beta": true},
		{"id": "backgammon", "name": "تخته نرد", "desc": "تاس و مهره — کلاسیک ایرانی", "short": "تاس بینداز", "players": "2 نفر", "max_p": 2, "icon_col": Color(0.8, 0.58, 0.28), "cat": "classic", "net": true, "beta": true},
		{"id": "gobblet", "name": "گابلت", "desc": "مهره‌های تو در تو", "short": "بخور و بچین", "players": "2 نفر", "max_p": 2, "icon_col": Color(0.98, 0.58, 0.18), "cat": "strategy", "net": true, "beta": false},
		{"id": "mastermind", "name": "فکر بکر", "desc": "حدس کد رنگی مخفی و رقابت سرعتی", "short": "کد را بشکن", "players": "۲ تا ۴ نفر", "max_p": 4, "icon_col": Color(0.45, 0.7, 0.95), "cat": "classic", "net": true, "beta": false},
		{"id": "abalone", "name": "ابلون", "desc": "قواعد استاندارد هل‌دادن مهره‌ها", "short": "هل بده بیرون", "players": "2 نفر", "max_p": 2, "icon_col": Color(0.55, 0.5, 0.95), "cat": "strategy", "net": true, "beta": false},
		{"id": "blockace", "name": "بلاک‌آس", "desc": "Blokus Duo · صفحه ۱۴×۱۴ و ۲۱ قطعه‌ی استاندارد", "short": "گسترش از گوشه‌ها", "players": "2 نفر", "max_p": 2, "icon_col": Color(0.3, 0.78, 0.72), "cat": "strategy", "net": true, "beta": false},
	]
