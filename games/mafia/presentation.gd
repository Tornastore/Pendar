extends RefCounted

const TextWrapScript = preload("res://ui/text_wrap.gd")
## Mafia's role-sensitive controls; never renders other living players' hidden roles.

func handle_tap(_app, _game, _point: Vector2) -> void:
	pass

func build_buttons(app, game) -> void:
	if game.mafia_game_over or not game._mafia_local_needs_action():
		return
	var kind: String = "vote"
	var action_label: String = "رأی برای حذف"
	if game.mafia_phase == "night":
		match game._mafia_local_role():
			"mafia":
				kind = "kill"
				action_label = "هدف شب مافیا"
			"doctor":
				kind = "protect"
				action_label = "محافظت دکتر"
			"detective":
				kind = "inspect"
				action_label = "بررسی کارآگاه"
			_: return
	game.mafia_action_label = action_label
	var candidates: Array[int] = []
	for seat in range(game.mafia_player_count):
		if not game._mafia_is_alive(seat):
			continue
		if kind != "protect" and seat == game._mafia_my_seat():
			continue
		if kind == "kill" and game.mafia_roles[seat] == game.ROLE_MAFIA:
			continue
		candidates.append(seat)
	var columns: int = 2
	var button_w: float = 240.0
	var button_h: float = 38.0
	var start_y: float = 298.0
	for index in range(candidates.size()):
		var target: int = candidates[index]
		var col: int = index % columns
		var row: int = int(index / columns)
		var rect := Rect2(20 + col * 250, start_y + row * 43, button_w, button_h)
		var color: Color = app.RED if game.mafia_roles[game._mafia_my_seat()] == game.ROLE_MAFIA else app.BLUE
		if kind == "protect":
			color = app.GREEN
		app._add_btn(rect, game._mafia_player_name(target), game._mafia_submit_action.bind(kind, target), true, color, "soft", "user", "mafia_target_%s" % target)

func render(app, game) -> void:
	var seat: int = game._mafia_my_seat()
	var role: String = game._mafia_local_role()
	var role_title: String = game._mafia_role_label(role)
	var role_color: Color = app.RED if role == game.ROLE_MAFIA else (app.GREEN if role == game.ROLE_DOCTOR else (app.BLUE if role == game.ROLE_DETECTIVE else app.TEXT_DIM))
	var alive_label: String = "زنده" if game._mafia_is_alive(seat) else "حذف شده"
	var active: bool = game._mafia_local_needs_action()
	var player: Dictionary = app._pl("شما", role_color, role_title, active, true, alive_label)
	app._draw_hud("مافیا کلاسیک", player)
	app._draw_ai_difficulty_chip_at(game.mafia_difficulty, 151)
	var phase_color: Color = Color("#6a75c5") if game.mafia_phase == "night" else Color("#d58d42")
	app._panel(Rect2(20, 194, 500, 76), Color(phase_color.r, phase_color.g, phase_color.b, 0.16), 18, Color(phase_color.r, phase_color.g, phase_color.b, 0.60), 1.2)
	var phase_label: String = "شب %s" % app._fa(game.mafia_round) if game.mafia_phase == "night" else "روز %s · رأی‌گیری" % app._fa(game.mafia_round)
	app._txt_c(phase_label, Rect2(28, 202, 484, 30), 19, phase_color.lightened(0.25), true)
	app._txt_c(game.mafia_status, Rect2(30, 235, 480, 28), app._fit_size(game.mafia_status, 462, 11, false), app.TEXT_DIM)
	if game.mafia_action_label != "":
		app._txt_c(game.mafia_action_label, Rect2(28, 269, 484, 24), 12, app.ACCENT, true)
	var alive_y: float = 562.0
	app._txt_r("وضعیت بازیکنان", 514, alive_y, 14, app.TEXT, true, 250)
	for index in range(game.mafia_player_count):
		var col: int = index % 3
		var row: int = int(index / 3)
		var rect := Rect2(20 + col * 168, alive_y + 22 + row * 37, 160, 34)
		var alive: bool = game._mafia_is_alive(index)
		var is_me: bool = index == seat
		var revealed: bool = game.mafia_revealed[index] or game.mafia_game_over
		var color: Color = app.GREEN if alive else app.TEXT_FAINT
		if revealed and game.mafia_roles[index] == game.ROLE_MAFIA:
			color = app.RED
		app._panel(rect, app.CARD if alive else Color("#111629"), 12, Color(color.r, color.g, color.b, 0.55 if alive else 0.2), 1.0)
		var name: String = "شما" if is_me else "بازیکن %s" % app._fa(index + 1)
		app._txt_c(name, Rect2(rect.position.x + 2, rect.position.y + 1, rect.size.x - 4, 16), app._fit_size(name, rect.size.x - 10, 11, true), app.TEXT if alive else app.TEXT_FAINT, true)
		var state_label: String = "زنده" if alive else "حذف شد"
		if revealed:
			state_label += " · " + game._mafia_role_label(game.mafia_roles[index])
		elif is_me:
			state_label += " · نقش شما: " + role_title
		app._txt_c(state_label, Rect2(rect.position.x + 2, rect.position.y + 17, rect.size.x - 4, 15), app._fit_size(state_label, rect.size.x - 10, 9, false), color)
	if game.mafia_private_note != "":
		app._panel(Rect2(24, 735, 492, 40), Color("#1b5b4c", 0.72), 14, Color("#63d9a9", 0.7), 1)
		var private_size: int = app._fit_size(game.mafia_private_note, 466, 12, true)
		app._wrap(game.mafia_private_note, 30, 741, 480, private_size, Color("#a6ffdc"), HORIZONTAL_ALIGNMENT_RIGHT, true)
	var event_height: float = 0.0
	if game.mafia_last_event != "":
		var compact_event: String = TextWrapScript.wrap(app, game.mafia_last_event, 492, 13, false, 2)
		event_height = app._wrap(compact_event, 24, 779, 492, 13, app.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	var hint_y: float = minf(849.0, maxf(826.0, 779.0 + event_height + 12.0))
	if not game.mafia_game_over:
		var hint: String = "با بازیکنان گفت‌وگو کنید، سپس رأی بدهید." if game.mafia_phase == "day" else "شب است؛ فقط نقش‌های ویژه اقدام می‌کنند."
		if not game._mafia_is_alive(seat):
			hint = "شما حذف شده‌اید؛ می‌توانید ادامهٔ بازی را تماشا کنید."
		elif game.mafia_phase == "night" and role == game.ROLE_CITIZEN:
			hint = "شهروند عادی هستید؛ منتظر پایان اقدامات شب بمانید."
		elif game.mafia_phase == "night" and not active:
			hint = "اقدام شما ثبت شده؛ منتظر بقیه بمانید."
		app._hint(hint, hint_y, app.TEXT_DIM)
	else:
		app._hint("بازی تمام شد؛ نقش همه بازیکنان آشکار است.", hint_y, app.GREEN)
