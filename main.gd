extends Node2D
# Mind Bastion - مجموعه بازی‌های فکری بزرگسال
# سبک: procedural drawing مثل Last Bastion، موبایل عمودی 540×960

const S := 1.0
const VIEW_W := 540.0
const VIEW_H := 960.0

const GameCatalogScript = preload("res://core/game_catalog.gd")
const ScoringServiceScript = preload("res://services/scoring_service.gd")
const RankingServiceScript = preload("res://services/ranking_service.gd")
const GAME_MODULE_SCRIPTS := {
	"othello": preload("res://games/othello/rules.gd"),
	"pentago": preload("res://games/pentago/rules.gd"),
	"quoridor": preload("res://games/quoridor/rules.gd"),
	"domino": preload("res://games/domino/rules.gd"),
	"chess": preload("res://games/chess/rules.gd"),
	"pasoor": preload("res://games/pasoor/rules.gd"),
	"mastermind": preload("res://games/mastermind/rules.gd"),
	"gobblet": preload("res://games/gobblet/rules.gd"),
	"hokm": preload("res://games/hokm/rules.gd"),
	"backgammon": preload("res://games/backgammon/rules.gd"),
	"abalone": preload("res://games/abalone/rules.gd"),
	"blockace": preload("res://games/blockace/rules.gd"),
}
var scoring_service = ScoringServiceScript.new()
var _game_modules: Dictionary = {}


# ---------- States ----------
enum State { MENU, MODE, LOBBY, IP_ENTRY, PLAYING, RESULT, DASHBOARD, RANKINGS, ONLINE }
var state: State = State.MENU:
	set = _set_state
var menu_scroll: float = 0.0
var dash_tab: int = 0
var rank_game_filter: String = "all"
var online_room_code: String = ""
var online_searching: bool = false

# ---------- Games ----------
var GAMES: Array = []

# ---------- Score / Ranking (local + structure for online) ----------

var selected_game: String = ""
var vs_cpu: bool = true
var is_host: bool = false
var my_name: String = "بازیکن"
var opponent_name: String = "حریف"

# ---------- Multiplayer ----------
const PORT := 7777
var peer: ENetMultiplayerPeer
var connected_players: int = 1
var local_player_id: int = 1          # multiplayer unique id
var local_seat: int = 0               # 0 = host/first, 1 = second player
var peer_to_seat: Dictionary = {}     # peer_id -> seat (0,1,...)
var host_ips: Array = []              # local IPs shown to host
var join_ip: String = ""              # IP typed by client
var max_players_for_game: int = 2

# Extra game state vars (new games)


# ---------- Shared UI ----------
var font: Font
var buttons: Array = []          # {rect, text, cb, enabled, accent}
var scroll_y: float = 0.0
var toast_msg: String = ""
var toast_timer: float = 0.0

# ---------- Othello ----------
const OTH_DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)
]

# ---------- Pentago ----------

# ---------- Quoridor (simplified) ----------

# ---------- Domino ----------
# tiles: Vector2i(a,b) with a <= b

# ---------- Chess ----------
# board[y][x]: 0 empty, 1-6 white (P N B R Q K), 7-12 black
const CHESS_NAMES := ["", "P", "N", "B", "R", "Q", "K", "p", "n", "b", "r", "q", "k"]
const CHESS_VAL := [0, 1, 3, 3, 5, 9, 100, 1, 3, 3, 5, 9, 100]

# ---------- Pasoor (پاسور / چهاربرگ) — قوانین دقیق ----------
# عدد A-10: جمع دقیقاً ۱۱ | شاه↔شاه | بی‌بی↔بی‌بی | سرباز=جارو (غیرشاه/بی‌بی)
# سور: خالی‌کردن میز با غیرسرباز = ۵ | هفت‌خاج=۷ | ۱۰♦=۳ | ۲♣=۲ | آس/سرباز=۱ | هدف ۶۲
const PAS_SUITS := ["♠", "♥", "♦", "♣"]
const PAS_RANKS := ["", "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
const PAS_TARGET := 62

# ---------- Game state compatibility bridge ----------
# Rules and state are owned by each game module; these properties let the shared renderer migrate safely.
var oth_size: int:
	get:
		return _game_modules["othello"].oth_size
	set(value):
		_game_modules["othello"].oth_size = value
var oth_difficulty: int:
	get:
		return _game_modules["othello"].oth_difficulty
	set(value):
		_game_modules["othello"].oth_difficulty = value
var mm_secret: Array:
	get:
		return _game_modules["mastermind"].mm_secret
	set(value):
		_game_modules["mastermind"].mm_secret = value
var mm_guesses: Array:
	get:
		return _game_modules["mastermind"].mm_guesses
	set(value):
		_game_modules["mastermind"].mm_guesses = value
var mm_cur: Array:
	get:
		return _game_modules["mastermind"].mm_cur
	set(value):
		_game_modules["mastermind"].mm_cur = value
var mm_slot: int:
	get:
		return _game_modules["mastermind"].mm_slot
	set(value):
		_game_modules["mastermind"].mm_slot = value
var mm_turn_role: int:
	get:
		return _game_modules["mastermind"].mm_turn_role
	set(value):
		_game_modules["mastermind"].mm_turn_role = value
var mm_game_over: bool:
	get:
		return _game_modules["mastermind"].mm_game_over
	set(value):
		_game_modules["mastermind"].mm_game_over = value
var mm_won: bool:
	get:
		return _game_modules["mastermind"].mm_won
	set(value):
		_game_modules["mastermind"].mm_won = value
var gob_board: Array:
	get:
		return _game_modules["gobblet"].gob_board
	set(value):
		_game_modules["gobblet"].gob_board = value
var gob_turn: int:
	get:
		return _game_modules["gobblet"].gob_turn
	set(value):
		_game_modules["gobblet"].gob_turn = value
var gob_hand: Array:
	get:
		return _game_modules["gobblet"].gob_hand
	set(value):
		_game_modules["gobblet"].gob_hand = value
var gob_sel_size: int:
	get:
		return _game_modules["gobblet"].gob_sel_size
	set(value):
		_game_modules["gobblet"].gob_sel_size = value
var gob_game_over: bool:
	get:
		return _game_modules["gobblet"].gob_game_over
	set(value):
		_game_modules["gobblet"].gob_game_over = value
var gob_winner: int:
	get:
		return _game_modules["gobblet"].gob_winner
	set(value):
		_game_modules["gobblet"].gob_winner = value
var bg_difficulty: int:
	get:
		return _game_modules["backgammon"].bg_difficulty
	set(value):
		_game_modules["backgammon"].bg_difficulty = value
var bg_points: Array:
	get:
		return _game_modules["backgammon"].bg_points
	set(value):
		_game_modules["backgammon"].bg_points = value
var bg_bar: Array:
	get:
		return _game_modules["backgammon"].bg_bar
	set(value):
		_game_modules["backgammon"].bg_bar = value
var bg_off: Array:
	get:
		return _game_modules["backgammon"].bg_off
	set(value):
		_game_modules["backgammon"].bg_off = value
var bg_dice: Array:
	get:
		return _game_modules["backgammon"].bg_dice
	set(value):
		_game_modules["backgammon"].bg_dice = value
var bg_turn: int:
	get:
		return _game_modules["backgammon"].bg_turn
	set(value):
		_game_modules["backgammon"].bg_turn = value
var bg_moves_left: Array:
	get:
		return _game_modules["backgammon"].bg_moves_left
	set(value):
		_game_modules["backgammon"].bg_moves_left = value
var bg_sel: int:
	get:
		return _game_modules["backgammon"].bg_sel
	set(value):
		_game_modules["backgammon"].bg_sel = value
var bg_game_over: bool:
	get:
		return _game_modules["backgammon"].bg_game_over
	set(value):
		_game_modules["backgammon"].bg_game_over = value
var bg_winner: int:
	get:
		return _game_modules["backgammon"].bg_winner
	set(value):
		_game_modules["backgammon"].bg_winner = value
var aba_board: Array:
	get:
		return _game_modules["abalone"].aba_board
	set(value):
		_game_modules["abalone"].aba_board = value
var aba_turn: int:
	get:
		return _game_modules["abalone"].aba_turn
	set(value):
		_game_modules["abalone"].aba_turn = value
var aba_sel: Vector2i:
	get:
		return _game_modules["abalone"].aba_sel
	set(value):
		_game_modules["abalone"].aba_sel = value
var aba_out: Array:
	get:
		return _game_modules["abalone"].aba_out
	set(value):
		_game_modules["abalone"].aba_out = value
var aba_game_over: bool:
	get:
		return _game_modules["abalone"].aba_game_over
	set(value):
		_game_modules["abalone"].aba_game_over = value
var aba_winner: int:
	get:
		return _game_modules["abalone"].aba_winner
	set(value):
		_game_modules["abalone"].aba_winner = value
var blk_grid: Array:
	get:
		return _game_modules["blockace"].blk_grid
	set(value):
		_game_modules["blockace"].blk_grid = value
var blk_turn: int:
	get:
		return _game_modules["blockace"].blk_turn
	set(value):
		_game_modules["blockace"].blk_turn = value
var blk_pieces: Array:
	get:
		return _game_modules["blockace"].blk_pieces
	set(value):
		_game_modules["blockace"].blk_pieces = value
var blk_sel: int:
	get:
		return _game_modules["blockace"].blk_sel
	set(value):
		_game_modules["blockace"].blk_sel = value
var blk_game_over: bool:
	get:
		return _game_modules["blockace"].blk_game_over
	set(value):
		_game_modules["blockace"].blk_game_over = value
var blk_winner: int:
	get:
		return _game_modules["blockace"].blk_winner
	set(value):
		_game_modules["blockace"].blk_winner = value
var hokm_hands: Array:
	get:
		return _game_modules["hokm"].hokm_hands
	set(value):
		_game_modules["hokm"].hokm_hands = value
var hokm_trick: Array:
	get:
		return _game_modules["hokm"].hokm_trick
	set(value):
		_game_modules["hokm"].hokm_trick = value
var hokm_trump: int:
	get:
		return _game_modules["hokm"].hokm_trump
	set(value):
		_game_modules["hokm"].hokm_trump = value
var hokm_turn: int:
	get:
		return _game_modules["hokm"].hokm_turn
	set(value):
		_game_modules["hokm"].hokm_turn = value
var hokm_scores: Array:
	get:
		return _game_modules["hokm"].hokm_scores
	set(value):
		_game_modules["hokm"].hokm_scores = value
var hokm_led_suit: int:
	get:
		return _game_modules["hokm"].hokm_led_suit
	set(value):
		_game_modules["hokm"].hokm_led_suit = value
var hokm_game_over: bool:
	get:
		return _game_modules["hokm"].hokm_game_over
	set(value):
		_game_modules["hokm"].hokm_game_over = value
var hokm_winner: int:
	get:
		return _game_modules["hokm"].hokm_winner
	set(value):
		_game_modules["hokm"].hokm_winner = value
var hokm_dealer: int:
	get:
		return _game_modules["hokm"].hokm_dealer
	set(value):
		_game_modules["hokm"].hokm_dealer = value
var othello_board: Array:
	get:
		return _game_modules["othello"].othello_board
	set(value):
		_game_modules["othello"].othello_board = value
var othello_turn: int:
	get:
		return _game_modules["othello"].othello_turn
	set(value):
		_game_modules["othello"].othello_turn = value
var othello_last_move: Vector2i:
	get:
		return _game_modules["othello"].othello_last_move
	set(value):
		_game_modules["othello"].othello_last_move = value
var othello_valid: Array:
	get:
		return _game_modules["othello"].othello_valid
	set(value):
		_game_modules["othello"].othello_valid = value
var othello_scores: Array:
	get:
		return _game_modules["othello"].othello_scores
	set(value):
		_game_modules["othello"].othello_scores = value
var othello_game_over: bool:
	get:
		return _game_modules["othello"].othello_game_over
	set(value):
		_game_modules["othello"].othello_game_over = value
var othello_winner: int:
	get:
		return _game_modules["othello"].othello_winner
	set(value):
		_game_modules["othello"].othello_winner = value
var pent_board: Array:
	get:
		return _game_modules["pentago"].pent_board
	set(value):
		_game_modules["pentago"].pent_board = value
var pent_turn: int:
	get:
		return _game_modules["pentago"].pent_turn
	set(value):
		_game_modules["pentago"].pent_turn = value
var pent_phase: int:
	get:
		return _game_modules["pentago"].pent_phase
	set(value):
		_game_modules["pentago"].pent_phase = value
var pent_last: Vector2i:
	get:
		return _game_modules["pentago"].pent_last
	set(value):
		_game_modules["pentago"].pent_last = value
var pent_game_over: bool:
	get:
		return _game_modules["pentago"].pent_game_over
	set(value):
		_game_modules["pentago"].pent_game_over = value
var pent_winner: int:
	get:
		return _game_modules["pentago"].pent_winner
	set(value):
		_game_modules["pentago"].pent_winner = value
var pent_selected_quad: int:
	get:
		return _game_modules["pentago"].pent_selected_quad
	set(value):
		_game_modules["pentago"].pent_selected_quad = value
var quo_pawns: Array:
	get:
		return _game_modules["quoridor"].quo_pawns
	set(value):
		_game_modules["quoridor"].quo_pawns = value
var quo_walls_left: Array:
	get:
		return _game_modules["quoridor"].quo_walls_left
	set(value):
		_game_modules["quoridor"].quo_walls_left = value
var quo_turn: int:
	get:
		return _game_modules["quoridor"].quo_turn
	set(value):
		_game_modules["quoridor"].quo_turn = value
var quo_mode: int:
	get:
		return _game_modules["quoridor"].quo_mode
	set(value):
		_game_modules["quoridor"].quo_mode = value
var quo_game_over: bool:
	get:
		return _game_modules["quoridor"].quo_game_over
	set(value):
		_game_modules["quoridor"].quo_game_over = value
var quo_winner: int:
	get:
		return _game_modules["quoridor"].quo_winner
	set(value):
		_game_modules["quoridor"].quo_winner = value
var quo_walls: Dictionary:
	get:
		return _game_modules["quoridor"].quo_walls
	set(value):
		_game_modules["quoridor"].quo_walls = value
var quo_difficulty: int:
	get:
		return _game_modules["quoridor"].quo_difficulty
	set(value):
		_game_modules["quoridor"].quo_difficulty = value
var quo_player_count: int:
	get:
		return _game_modules["quoridor"].quo_player_count
	set(value):
		_game_modules["quoridor"].quo_player_count = value
var quo_local_multiplayer: bool:
	get:
		return _game_modules["quoridor"].quo_local_multiplayer
	set(value):
		_game_modules["quoridor"].quo_local_multiplayer = value
var dom_hands: Array:
	get:
		return _game_modules["domino"].dom_hands
	set(value):
		_game_modules["domino"].dom_hands = value
var dom_boneyard: Array:
	get:
		return _game_modules["domino"].dom_boneyard
	set(value):
		_game_modules["domino"].dom_boneyard = value
var dom_chain: Array:
	get:
		return _game_modules["domino"].dom_chain
	set(value):
		_game_modules["domino"].dom_chain = value
var dom_left: int:
	get:
		return _game_modules["domino"].dom_left
	set(value):
		_game_modules["domino"].dom_left = value
var dom_right: int:
	get:
		return _game_modules["domino"].dom_right
	set(value):
		_game_modules["domino"].dom_right = value
var dom_turn: int:
	get:
		return _game_modules["domino"].dom_turn
	set(value):
		_game_modules["domino"].dom_turn = value
var dom_game_over: bool:
	get:
		return _game_modules["domino"].dom_game_over
	set(value):
		_game_modules["domino"].dom_game_over = value
var dom_winner: int:
	get:
		return _game_modules["domino"].dom_winner
	set(value):
		_game_modules["domino"].dom_winner = value
var dom_selected: int:
	get:
		return _game_modules["domino"].dom_selected
	set(value):
		_game_modules["domino"].dom_selected = value
var dom_scores: Array:
	get:
		return _game_modules["domino"].dom_scores
	set(value):
		_game_modules["domino"].dom_scores = value
var chess_difficulty: int:
	get:
		return _game_modules["chess"].chess_difficulty
	set(value):
		_game_modules["chess"].chess_difficulty = value
var chess_board: Array:
	get:
		return _game_modules["chess"].chess_board
	set(value):
		_game_modules["chess"].chess_board = value
var chess_turn: int:
	get:
		return _game_modules["chess"].chess_turn
	set(value):
		_game_modules["chess"].chess_turn = value
var chess_selected: Vector2i:
	get:
		return _game_modules["chess"].chess_selected
	set(value):
		_game_modules["chess"].chess_selected = value
var chess_valid: Array:
	get:
		return _game_modules["chess"].chess_valid
	set(value):
		_game_modules["chess"].chess_valid = value
var chess_game_over: bool:
	get:
		return _game_modules["chess"].chess_game_over
	set(value):
		_game_modules["chess"].chess_game_over = value
var chess_winner: int:
	get:
		return _game_modules["chess"].chess_winner
	set(value):
		_game_modules["chess"].chess_winner = value
var chess_last: Array:
	get:
		return _game_modules["chess"].chess_last
	set(value):
		_game_modules["chess"].chess_last = value
var pas_deck: Array:
	get:
		return _game_modules["pasoor"].pas_deck
	set(value):
		_game_modules["pasoor"].pas_deck = value
var pas_hands: Array:
	get:
		return _game_modules["pasoor"].pas_hands
	set(value):
		_game_modules["pasoor"].pas_hands = value
var pas_table: Array:
	get:
		return _game_modules["pasoor"].pas_table
	set(value):
		_game_modules["pasoor"].pas_table = value
var pas_captured: Array:
	get:
		return _game_modules["pasoor"].pas_captured
	set(value):
		_game_modules["pasoor"].pas_captured = value
var pas_turn: int:
	get:
		return _game_modules["pasoor"].pas_turn
	set(value):
		_game_modules["pasoor"].pas_turn = value
var pas_game_over: bool:
	get:
		return _game_modules["pasoor"].pas_game_over
	set(value):
		_game_modules["pasoor"].pas_game_over = value
var pas_winner: int:
	get:
		return _game_modules["pasoor"].pas_winner
	set(value):
		_game_modules["pasoor"].pas_winner = value
var pas_selected: int:
	get:
		return _game_modules["pasoor"].pas_selected
	set(value):
		_game_modules["pasoor"].pas_selected = value
var pas_scores: Array:
	get:
		return _game_modules["pasoor"].pas_scores
	set(value):
		_game_modules["pasoor"].pas_scores = value
var pas_match_scores: Array:
	get:
		return _game_modules["pasoor"].pas_match_scores
	set(value):
		_game_modules["pasoor"].pas_match_scores = value
var pas_surs: Array:
	get:
		return _game_modules["pasoor"].pas_surs
	set(value):
		_game_modules["pasoor"].pas_surs = value
var pas_last_capturer: int:
	get:
		return _game_modules["pasoor"].pas_last_capturer
	set(value):
		_game_modules["pasoor"].pas_last_capturer = value
var pas_deals_done: int:
	get:
		return _game_modules["pasoor"].pas_deals_done
	set(value):
		_game_modules["pasoor"].pas_deals_done = value
var pas_is_last_deal: bool:
	get:
		return _game_modules["pasoor"].pas_is_last_deal
	set(value):
		_game_modules["pasoor"].pas_is_last_deal = value
var mm_filled: Array:
	get:
		return _game_modules["mastermind"].mm_filled
	set(value):
		_game_modules["mastermind"].mm_filled = value
var hokm_last: Array:
	get:
		return _game_modules["hokm"].hokm_last
	set(value):
		_game_modules["hokm"].hokm_last = value
var hokm_last_winner: int:
	get:
		return _game_modules["hokm"].hokm_last_winner
	set(value):
		_game_modules["hokm"].hokm_last_winner = value
var hokm_last_t: float:
	get:
		return _game_modules["hokm"].hokm_last_t
	set(value):
		_game_modules["hokm"].hokm_last_t = value
var blk_rot: int:
	get:
		return _game_modules["blockace"].blk_rot
	set(value):
		_game_modules["blockace"].blk_rot = value
var blk_prev: Vector2i:
	get:
		return _game_modules["blockace"].blk_prev
	set(value):
		_game_modules["blockace"].blk_prev = value

# ---------- Colors (modern dark) ----------
const BG := Color(0.043, 0.063, 0.125)
const BG_TOP := Color(0.039, 0.055, 0.118)
const BG_BOT := Color(0.086, 0.106, 0.220)
const BAR := Color(0.071, 0.090, 0.184)
const CARD := Color(0.102, 0.125, 0.247)
const CARD_H := Color(0.153, 0.184, 0.349)
const DISABLED := Color(0.10, 0.12, 0.20)
const LINE := Color(1, 1, 1, 0.08)
const LINE_STRONG := Color(1, 1, 1, 0.16)
const ACCENT := Color(1.0, 0.79, 0.30)
const TEXT := Color(0.96, 0.97, 1.0)
const TEXT_DIM := Color(0.68, 0.72, 0.84)
const TEXT_FAINT := Color(0.45, 0.49, 0.62)
const GREEN := Color(0.24, 0.86, 0.60)
const RED := Color(1.0, 0.36, 0.42)
const BLUE := Color(0.38, 0.62, 1.0)
const PINK := Color(1.0, 0.45, 0.72)

func _ensure_game_stats() -> void:
	scoring_service.ensure_game_stats(_game_ids())

func _record_match_result(won: bool) -> void:
	scoring_service.record_match_result(selected_game, won, "CPU" if vs_cpu else "Online", _game_ids())

func _points_in_period(game_id: String, days: int) -> int:
	return scoring_service.points_in_period(game_id, days)

func _total_wins_losses() -> Array:
	return scoring_service.total_wins_losses()

func _handle_tap(p: Vector2) -> void:
	# check buttons first
	for b in buttons:
		if b.enabled and b.rect.has_point(p):
			b.cb.call()
			return

	if state == State.PLAYING:
		if selected_game in ["othello", "othello12"]:
			_othello_tap(p)
		elif selected_game == "pentago":
			_pent_tap(p)
		elif selected_game == "quoridor":
			_quo_tap(p)
		elif selected_game == "domino":
			_dom_tap(p)
		elif selected_game == "chess":
			_chess_tap(p)
		elif selected_game == "pasoor":
			_pas_tap(p)
		elif selected_game == "mastermind":
			_mm_tap(p)
		elif selected_game == "gobblet":
			_gob_tap(p)
		elif selected_game == "hokm":
			_hokm_tap(p)
		elif selected_game == "backgammon":
			_bg_tap(p)
		elif selected_game == "abalone":
			_aba_tap(p)
		elif selected_game == "blockace":
			_blk_tap(p)

# ==================== BUTTON HELPERS ====================

func _rebuild_dash_btns() -> void:
	_clear_buttons()
	_add_btn(Rect2(20, 150, 120, 40), "منو", func(): _back_to_menu(), true, TEXT_DIM)
	_add_btn(Rect2(20, VIEW_H - 70, 160, 50), "کلی", func(): dash_tab = 0, true, ACCENT)
	_add_btn(Rect2(190, VIEW_H - 70, 160, 50), "هفتگی", func(): dash_tab = 1, true, GREEN)
	_add_btn(Rect2(360, VIEW_H - 70, 160, 50), "ماهانه", func(): dash_tab = 2, true, BLUE)

func _start_vs_cpu() -> void:
	vs_cpu = true
	is_host = true
	local_seat = 0
	local_player_id = 1
	if selected_game == "quoridor":
		_game_modules["quoridor"].quo_player_count = 2
		_game_modules["quoridor"].quo_local_multiplayer = false
	_start_game()

func _start_quoridor_local_four_player() -> void:
	# Hot-seat mode: four people share one device; no network session is started.
	vs_cpu = false
	is_host = true
	local_seat = 0
	local_player_id = 1
	_game_modules["quoridor"].quo_player_count = 4
	_game_modules["quoridor"].quo_local_multiplayer = true
	_start_game()

func _get_local_ips() -> Array:
	var ips: Array = []
	for a in IP.get_local_addresses():
		var s := str(a)
		# فقط IPv4 خصوصی رایج
		if s.begins_with("192.168.") or s.begins_with("10.") or s.begins_with("172."):
			if s not in ips:
				ips.append(s)
	return ips

func _start_host() -> void:
	if OS.has_feature("web"):
		_show_toast("نسخه وب از اتصال شبکه‌ای ENet پشتیبانی نمی‌کند؛ بازی محلی را انتخاب کنید.")
		return
	vs_cpu = false
	is_host = true
	_cleanup_network()
	if selected_game == "quoridor":
		max_players_for_game = 2
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, max_players_for_game)
	if err != OK:
		_show_toast("خطا در ایجاد سرور (پورت اشغال؟)")
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	local_player_id = multiplayer.get_unique_id()  # معمولاً 1
	local_seat = 0
	peer_to_seat[local_player_id] = 0
	connected_players = 1
	host_ips = _get_local_ips()
	state = State.LOBBY
	_build_lobby_buttons()
	if host_ips.size() > 0:
		_show_toast("میزبان آماده — IP: " + host_ips[0])
	else:
		_show_toast("میزبان آماده — پورت " + str(PORT))

func _go_ip_entry() -> void:
	vs_cpu = false
	is_host = false
	join_ip = ""
	state = State.IP_ENTRY
	_build_ip_buttons()

func _ip_key(k: String) -> void:
	if k == "⌫":
		if join_ip.length() > 0:
			join_ip = join_ip.substr(0, join_ip.length() - 1)
	else:
		if join_ip.length() < 15:
			join_ip += k
	_build_ip_buttons()

func _do_join() -> void:
	if OS.has_feature("web"):
		_show_toast("اتصال با IP در نسخه وب پشتیبانی نمی‌شود؛ بازی محلی را انتخاب کنید.")
		return
	if join_ip.length() < 7:
		_show_toast("IP معتبر وارد کنید")
		return
	var target_ip: String = join_ip.strip_edges()
	_cleanup_network()  # این تابع join_ip را خالی می‌کند
	join_ip = target_ip
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(target_ip, PORT)
	if err != OK:
		_show_toast("خطا در اتصال (کد %d)" % err)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	state = State.LOBBY
	_build_lobby_buttons()
	_show_toast("در حال اتصال به " + join_ip + " ...")

func _on_peer_connected(id: int) -> void:
	# فقط روی Host اجرا می‌شود
	if not is_host:
		return
	if connected_players >= max_players_for_game:
		# رد کردن اتصال اضافی
		peer.disconnect_peer(id)
		_show_toast("ظرفیت پر است")
		return
	var seat := connected_players  # 1, 2, ...
	peer_to_seat[id] = seat
	connected_players += 1
	# به کلاینت بگو seat او چیست
	rpc_id(id, "_rpc_assign_seat", seat, selected_game)
	_show_toast("بازیکن " + str(seat + 1) + " متصل شد")
	_build_lobby_buttons()

func _on_peer_disconnected(id: int) -> void:
	if peer_to_seat.has(id):
		peer_to_seat.erase(id)
	connected_players = max(1, connected_players - 1)
	_show_toast("بازیکن قطع شد")
	if state == State.PLAYING:
		_show_toast("حریف قطع شد — بازگشت به منو")
		_back_to_menu()
	else:
		_build_lobby_buttons()

@rpc("authority", "reliable")
func _rpc_assign_seat(seat: int, game_id: String) -> void:
	local_seat = seat
	selected_game = game_id
	_show_toast("شما بازیکن " + str(seat + 1) + " هستید")

func _on_server_disconnected() -> void:
	_show_toast("اتصال با Host قطع شد")
	_back_to_menu()

func _start_network_game() -> void:
	if not is_host:
		return
	if connected_players < 2:
		_show_toast("حداقل ۲ بازیکن لازم است")
		return
	var rng_seed: int = randi()
	rpc("_rpc_start_game", selected_game, rng_seed)
	# call_local will also run on host

@rpc("authority", "call_local", "reliable")
func _rpc_start_game(game_id: String, rng_seed: int = 0) -> void:
	selected_game = game_id
	vs_cpu = false
	if game_id == "quoridor":
		_game_modules["quoridor"].quo_player_count = 2
		_game_modules["quoridor"].quo_local_multiplayer = false
	if rng_seed != 0:
		seed(rng_seed)  # یکسان‌سازی تصادفی برای پخش کارت/مهره
	_start_game()

func _my_seat() -> int:
	return 0 if vs_cpu else local_seat

func _net_on() -> bool:
	return not vs_cpu and multiplayer.multiplayer_peer != null

func _is_my_turn() -> bool:
	if vs_cpu:
		# در vs CPU همیشه seat 0 هستیم و نوبت‌های فرد/زوج را چک می‌کنیم
		return true  # منطق جدا در هر بازی (CPU وقتی نوبت ۲ است بازی می‌کند)
	match selected_game:
		"othello", "othello12":
			return (local_seat == 0 and othello_turn == 1) or (local_seat == 1 and othello_turn == 2)
		"pentago":
			return (local_seat == 0 and pent_turn == 1) or (local_seat == 1 and pent_turn == 2)
		"chess":
			return (local_seat == 0 and chess_turn == 1) or (local_seat == 1 and chess_turn == 2)
		"domino":
			return dom_turn == local_seat
		"pasoor":
			return pas_turn == local_seat
		"quoridor":
			return quo_turn == local_seat
	return false

func _reset_othello() -> void:
	_game_modules["othello"]._reset_othello()

func _othello_update_scores() -> void:
	_game_modules["othello"]._othello_update_scores()

func _othello_in_bounds(c: Vector2i) -> bool:
	return _game_modules["othello"]._othello_in_bounds(c)

func _othello_would_flip(c: Vector2i, color: int) -> Array:
	return _game_modules["othello"]._othello_would_flip(c, color)

func _othello_update_valid() -> void:
	_game_modules["othello"]._othello_update_valid()

func _othello_place(c: Vector2i) -> bool:
	return _game_modules["othello"]._othello_place(c)

func _othello_apply_place(c: Vector2i) -> void:
	_game_modules["othello"]._othello_apply_place(c)

@rpc("any_peer", "call_local", "reliable")
func _rpc_othello_place(x: int, y: int) -> void:
	_othello_apply_place(Vector2i(x, y))

func _reset_pentago() -> void:
	_game_modules["pentago"]._reset_pentago()

func _pent_check_win(color: int) -> bool:
	return _game_modules["pentago"]._pent_check_win(color)

func _pent_rotate(quad: int, clockwise: bool) -> void:
	_game_modules["pentago"]._pent_rotate(quad, clockwise)

func _pent_place(c: Vector2i) -> bool:
	return _game_modules["pentago"]._pent_place(c)

func _pent_do_rotate(quad: int, clockwise: bool) -> void:
	_game_modules["pentago"]._pent_do_rotate(quad, clockwise)

func _pent_cpu_move() -> void:
	_game_modules["pentago"]._pent_cpu_move()

func _reset_quoridor() -> void:
	_game_modules["quoridor"]._reset_quoridor()

func _quo_can_move(from: Vector2i, to: Vector2i) -> bool:
	return _game_modules["quoridor"]._quo_can_move(from, to)

func _quo_path_exists(player: int) -> bool:
	return _game_modules["quoridor"]._quo_path_exists(player)

func _quo_place_wall(hx: int, hy: int, vertical: bool) -> bool:
	return _game_modules["quoridor"]._quo_place_wall(hx, hy, vertical)

func _quo_in_bounds(pos: Vector2i) -> bool:
	return _game_modules["quoridor"]._quo_in_bounds(pos)

func _quo_goal_reached(player: int, pos: Vector2i) -> bool:
	return _game_modules["quoridor"]._quo_goal_reached(player, pos)

func _quo_legal_moves(player: int) -> Array[Vector2i]:
	return _game_modules["quoridor"]._quo_legal_moves(player)

func _quo_legal_moves_from(player: int, pos: Vector2i) -> Array[Vector2i]:
	return _game_modules["quoridor"]._quo_legal_moves_from(player, pos)

func _quo_wall_geometry_clear(x: int, y: int, vertical: bool) -> bool:
	return _game_modules["quoridor"]._quo_wall_geometry_clear(x, y, vertical)

func _quo_wall_placement_legal(x: int, y: int, vertical: bool) -> bool:
	return _game_modules["quoridor"]._quo_wall_placement_legal(x, y, vertical)

func _quo_has_legal_wall() -> bool:
	return _game_modules["quoridor"]._quo_has_legal_wall()

func _reset_domino() -> void:
	_game_modules["domino"]._reset_domino()

func _dom_can_play(tile: Vector2i, end: String) -> bool:
	return _game_modules["domino"]._dom_can_play(tile, end)

func _dom_playable(p: int) -> Array:
	return _game_modules["domino"]._dom_playable(p)

func _dom_play(p: int, idx: int, end: String) -> bool:
	return _game_modules["domino"]._dom_play(p, idx, end)

func _dom_draw(p: int) -> void:
	_game_modules["domino"]._dom_draw(p)

func _dom_calc_scores() -> void:
	_game_modules["domino"]._dom_calc_scores()

func _dom_cpu_move() -> void:
	_game_modules["domino"]._dom_cpu_move()

func _reset_chess() -> void:
	_game_modules["chess"]._reset_chess()

func _chess_color(piece: int) -> int:
	return _game_modules["chess"]._chess_color(piece)

func _chess_in(c: Vector2i) -> bool:
	return _game_modules["chess"]._chess_in(c)

func _chess_gen_moves(from: Vector2i) -> Array:
	return _game_modules["chess"]._chess_gen_moves(from)

func _chess_all_moves(col: int) -> Array:
	return _game_modules["chess"]._chess_all_moves(col)

func _chess_make_move(from: Vector2i, to: Vector2i) -> void:
	_game_modules["chess"]._chess_make_move(from, to)

func _chess_cpu_move() -> void:
	_game_modules["chess"]._chess_cpu_move()

func _pas_pip(c: Dictionary) -> int:
	return _game_modules["pasoor"]._pas_pip(c)

func _pas_is_jack(c: Dictionary) -> bool:
	return _game_modules["pasoor"]._pas_is_jack(c)

func _pas_is_queen(c: Dictionary) -> bool:
	return _game_modules["pasoor"]._pas_is_queen(c)

func _pas_is_king(c: Dictionary) -> bool:
	return _game_modules["pasoor"]._pas_is_king(c)

func _pas_card_str(c: Dictionary) -> String:
	return _game_modules["pasoor"]._pas_card_str(c)

func _reset_pasoor() -> void:
	_game_modules["pasoor"]._reset_pasoor()

func _pas_deal_table() -> void:
	_game_modules["pasoor"]._pas_deal_table()

func _pas_find_captures(card: Dictionary) -> Array:
	return _game_modules["pasoor"]._pas_find_captures(card)

func _pas_best_capture(card: Dictionary) -> Array:
	return _game_modules["pasoor"]._pas_best_capture(card)

func _pas_must_capture(card: Dictionary) -> bool:
	return _game_modules["pasoor"]._pas_must_capture(card)

func _pas_play(p: int, hand_idx: int, capture_indices: Array) -> void:
	_game_modules["pasoor"]._pas_play(p, hand_idx, capture_indices)

func _pas_after_hands_empty() -> void:
	_game_modules["pasoor"]._pas_after_hands_empty()

func _pas_end_hand() -> void:
	_game_modules["pasoor"]._pas_end_hand()

func _pas_cpu_move() -> void:
	_game_modules["pasoor"]._pas_cpu_move()

@rpc("any_peer", "call_local", "reliable")
func _rpc_pas_play(p: int, hand_idx: int, capture_indices: Array) -> void:
	_pas_play(p, hand_idx, capture_indices)

@rpc("any_peer", "call_local", "reliable")
func _rpc_pent_place(x: int, y: int) -> void:
	if selected_game == "pentago" and pent_phase == 0:
		_pent_place(Vector2i(x, y))

@rpc("any_peer", "call_local", "reliable")
func _rpc_pent_rotate(quad: int, clockwise: bool) -> void:
	if selected_game == "pentago" and pent_phase == 1:
		_pent_do_rotate(quad, clockwise)

@rpc("any_peer", "call_local", "reliable")
func _rpc_dom_play(p: int, idx: int, end: String) -> void:
	if selected_game == "domino":
		_dom_play(p, idx, end)

@rpc("any_peer", "call_local", "reliable")
func _rpc_chess_move(fx: int, fy: int, tx: int, ty: int) -> void:
	if selected_game == "chess":
		_chess_make_move(Vector2i(fx, fy), Vector2i(tx, ty))

@rpc("any_peer", "call_local", "reliable")
func _rpc_quo_move(x: int, y: int, mode: int) -> void:
	if selected_game == "quoridor":
		quo_mode = mode
		_quo_tap(Vector2(45 + x * 50 + 25, 180 + y * 50 + 25))

# ==================== DASHBOARD / RANKINGS / ONLINE UI ====================

func _mm_evaluate(guess: Array) -> Array:
	return _game_modules["mastermind"]._mm_evaluate(guess)

func _reset_gobblet() -> void:
	_game_modules["gobblet"]._reset_gobblet()

func _gob_top(x: int, y: int) -> Dictionary:
	return _game_modules["gobblet"]._gob_top(x, y)

func _gob_check_win(p: int) -> bool:
	return _game_modules["gobblet"]._gob_check_win(p)

func _gob_place(x: int, y: int, size: int, player: int) -> bool:
	return _game_modules["gobblet"]._gob_place(x, y, size, player)

func _reset_hokm() -> void:
	_game_modules["hokm"]._reset_hokm()

func _reset_backgammon() -> void:
	_game_modules["backgammon"]._reset_backgammon()

func _bg_roll() -> void:
	_game_modules["backgammon"]._bg_roll()

func _bg_cpu() -> void:
	_game_modules["backgammon"]._bg_cpu()

func _reset_abalone() -> void:
	_game_modules["abalone"]._reset_abalone()

func _aba_cpu() -> void:
	_game_modules["abalone"]._aba_cpu()

func _reset_blockace() -> void:
	_game_modules["blockace"]._reset_blockace()

func _blk_can_place(px: int, py: int, piece: Array, player: int) -> bool:
	return _game_modules["blockace"]._blk_can_place(px, py, piece, player)

# ======================================================================
#  UI CORE — Theme · helpers · buttons · input · navigation · overlays
# ======================================================================
const RULES := {
	"othello": [
		"هر نوبت یک مهره روی خانه‌ای بگذارید که حداقل یک مهره حریف را بین دو مهره شما محصور کند.",
		"مهره‌های محصورشده به رنگ شما درمی‌آیند.",
		"اگر حرکتی نداشته باشید، نوبت خودکار به حریف می‌رسد.",
		"وقتی هیچ‌کس حرکتی نداشت، مهره بیشتر = برنده.",
		"نقطه‌های روشن روی صفحه، حرکت‌های مجاز را نشان می‌دهند.",
	],
	"pentago": [
		"ابتدا یک مهره روی خانه خالی بگذارید.",
		"سپس یکی از چهار بخش ۳×۳ را ۹۰ درجه (ساعتگرد یا پادساعتگرد) بچرخانید.",
		"اولین نفری که ۵ مهره هم‌رنگ پشت‌سرهم (افقی، عمودی یا مورب) بسازد برنده است.",
	],
	"quoridor": [
		"هدف: زودتر از بقیه به ضلع مقابلِ محل شروع خود برسید.",
		"در هر نوبت یا مهره را حرکت دهید، یا یک دیوار بگذارید. در صورت قرارگرفتن مهره حریف کنار شما، پرش مستقیم و در صورت بسته‌بودن آن، حرکت مورب مجاز است.",
		"هر دیوار دقیقاً به اندازه دو مسیر خانه‌ای طول دارد و دو گذر را مسدود می‌کند. دیوارها نباید روی هم بیفتند، همدیگر را قطع کنند یا مسیر رسیدن هیچ بازیکنی به هدف را ببندند.",
		"در بازی دونفره هر بازیکن ۱۰ دیوار دارد؛ در بازی چهارنفره هر بازیکن ۵ دیوار دارد.",
		"برای چهار نفر، گزینه «بازی ۴ نفره روی یک دستگاه» را انتخاب کنید؛ نوبت‌ها بین چهار بازیکن می‌چرخد.",
	],
	"chess": [
		"حرکت مهره‌ها مطابق شطرنج کلاسیک است؛ مهره را بزنید تا خانه‌های مجاز نمایش داده شود.",
		"پیاده در رسیدن به خانه آخر وزیر می‌شود.",
		"نسخه ساده: قلعه، آن‌پاسان و کیش‌ومات وجود ندارد؛ بازی با گرفتن شاه تمام می‌شود.",
	],
	"domino": [
		"هر بازیکن ۷ مهره دارد. مهره را انتخاب کنید و در ابتدا یا انتهای زنجیر بگذارید؛ عدد باید با سر زنجیر برابر باشد.",
		"اگر مهره مناسب ندارید از انبار بردارید؛ اگر انبار خالی بود پاس بدهید.",
		"اولین نفری که مهره‌هایش تمام شود برنده است. در بن‌بست، مجموع نقطه‌های کمتر برنده است.",
	],
	"pasoor": [
		"کارت بازی‌شده یا روی میز می‌ماند یا کارت‌هایی را می‌گیرد؛ اگر گرفتن ممکن باشد اجباری است.",
		"عدد: جمع کارت‌های عددی (آس تا ۱۰) باید دقیقاً ۱۱ شود. شاه با شاه، بی‌بی با بی‌بی.",
		"سرباز همه کارت‌های میز را جارو می‌کند (به‌جز شاه و بی‌بی).",
		"امتیاز: سور ۵ | هفت‌خاج ۷ | ده خشت ۳ | دو گشنیز ۲ | آس و سرباز هرکدام ۱.",
		"هدف مسابقه: رسیدن به ۶۲ امتیاز. برای بازی کارت، دو بار ضربه بزنید یا دکمه پایین را بزنید.",
	],
	"hokm": [
		"هر بازیکن ۱۳ کارت دارد و خال حکم بالای صفحه نمایش داده می‌شود.",
		"اگر کارت هم‌خالِ زمین دارید باید همان را بازی کنید (کارت‌های غیرمجاز کم‌رنگ می‌شوند).",
		"حکم بر بقیه خال‌ها برتری دارد. برنده هر دست یک امتیاز می‌گیرد.",
		"بعد از ۱۳ دست، امتیاز بیشتر برنده است. (نسخه ساده دو نفره)",
	],
	"backgammon": [
		"تاس‌ها خودکار ریخته می‌شوند. با دکمه «حرکت» یا ضربه روی صفحه، حرکت بعدی انجام می‌شود.",
		"هدف: خارج‌کردن هر ۱۵ مهره از صفحه.",
		"نسخه ساده: انتخاب دستی مهره هنوز پیاده‌سازی نشده است.",
	],
	"gobblet": [
		"هر بازیکن از هر اندازه (کوچک، متوسط، بزرگ) سه مهره دارد.",
		"مهره بزرگ‌تر می‌تواند روی مهره کوچک‌تر (حتی مهره حریف) بنشیند.",
		"۴ مهره هم‌رنگ در یک ردیف، ستون یا قطر = برد.",
	],
	"mastermind": [
		"یک کد مخفی ۴ رنگی ساخته شده است؛ رنگ‌ها می‌توانند تکراری باشند.",
		"هر حدس را ثبت کنید: مهره سیاه = رنگ و جای درست، سفید = رنگ درست در جای نادرست.",
		"حداکثر ۱۰ تلاش دارید.",
	],
	"abalone": [
		"نسخه آزمایشی: مهره خود را انتخاب کنید و به خانه خالیِ کناری ببرید.",
		"قوانین هل‌دادن و برد کامل هنوز اضافه نشده است.",
	],
	"blockace": [
		"قطعه را از پایین انتخاب کنید (با دکمه چرخش می‌توانید بچرخانید).",
		"یک بار روی صفحه ضربه بزنید تا پیش‌نمایش ببینید، دوباره ضربه بزنید یا «قراردادن» را بزنید.",
		"اگر کسی نتواند قطعه‌ای بگذارد نوبتش رد می‌شود؛ وقتی هیچ‌کس نتواند، صاحب خانه‌های بیشتر برنده است.",
	],
}

const CAT_LABELS := {"all": "همه", "strategy": "استراتژی", "cards": "کارتی", "classic": "کلاسیک"}
const MM_COLORS := [Color(1.0, 0.36, 0.42), Color(0.24, 0.86, 0.60), Color(0.30, 0.55, 1.0), Color(1.0, 0.82, 0.30), Color(0.71, 0.48, 1.0), Color(1.0, 0.62, 0.26)]

# ---------- UI state ----------
var _result_logged: bool = false
var _time: float = 0.0
var _state_t: float = 0.0
var font_bold: Font
var _bg_tex: GradientTexture2D
var _glow_tex: GradientTexture2D
var _sb_cache: Dictionary = {}
var _ptr: Vector2 = Vector2(-999, -999)
var ov_buttons: Array = []
var dialog: Dictionary = {}
var pause_open: bool = false
var rules_open: bool = false
var _ov_t: float = 0.0
var _press_active: bool = false
var _press_id: String = ""
var _press_pos: Vector2 = Vector2.ZERO
var _press_moved: bool = false
var _scroll_vel: float = 0.0
var _scroll_top: float = 176.0
var _scroll_bottom: float = 868.0
var _content_h: float = 0.0
var menu_filter: String = "all"
var online_game: String = "othello"
var _origin_online: bool = false
var _cpu_pending: bool = false
var _game_epoch: int = 0
var _last_sig: String = ""
var _prev_boards: Dictionary = {}
var _cell_anim: Dictionary = {}
var _result_t0: float = 0.0
var _result_delta: int = 0
var _result_draw: bool = false
var seen_rules: Dictionary:
	get:
		return scoring_service.seen_rules
	set(value):
		scoring_service.seen_rules = value

func _set_state(v: State) -> void:
	if state != v:
		_state_t = 0.0
		scroll_y = 0.0
		_scroll_vel = 0.0
		pause_open = false
		rules_open = false
		dialog = {}
	state = v

# ---------- setup ----------
func _setup_fonts() -> void:
	var reg_path := "res://fonts/Vazirmatn-Regular.ttf"
	var bold_path := "res://fonts/Vazirmatn-Bold.ttf"
	if ResourceLoader.exists(reg_path):
		font = load(reg_path)
		font_bold = load(bold_path) if ResourceLoader.exists(bold_path) else font
		return
	var names := PackedStringArray(["Vazirmatn", "Vazir", "IRANSansX", "IRANSans", "Samim", "Noto Sans Arabic UI", "Noto Sans Arabic", "Tahoma", "Segoe UI", "Arial", "DejaVu Sans"])
	var sf := SystemFont.new()
	sf.font_names = names
	sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	sf.fallbacks = [ThemeDB.fallback_font]
	font = sf
	var sb := SystemFont.new()
	sb.font_names = names
	sb.font_weight = 700
	sb.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	sb.fallbacks = [ThemeDB.fallback_font]
	font_bold = sb

func _setup_textures() -> void:
	var g := Gradient.new()
	g.set_color(0, BG_TOP)
	g.set_color(1, BG_BOT)
	_bg_tex = GradientTexture2D.new()
	_bg_tex.gradient = g
	_bg_tex.fill_from = Vector2(0.5, 0.0)
	_bg_tex.fill_to = Vector2(0.5, 1.0)
	_bg_tex.width = 8
	_bg_tex.height = 256
	var g2 := Gradient.new()
	g2.set_color(0, Color(1, 1, 1, 1))
	g2.set_color(1, Color(1, 1, 1, 0))
	_glow_tex = GradientTexture2D.new()
	_glow_tex.gradient = g2
	_glow_tex.fill = GradientTexture2D.FILL_RADIAL
	_glow_tex.fill_from = Vector2(0.5, 0.5)
	_glow_tex.fill_to = Vector2(1.0, 0.5)
	_glow_tex.width = 128
	_glow_tex.height = 128

# ---------- text helpers ----------
func _fa(v) -> String:
	var s := str(v)
	var out := ""
	for i in s.length():
		var c: int = s.unicode_at(i)
		if c >= 48 and c <= 57:
			out += String.chr(0x06F0 + c - 48)
		else:
			out += s[i]
	return out

func _txt(s: String, x: float, y: float, size: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, w: float = -1.0, bold: bool = false) -> void:
	draw_string(font_bold if bold else font, Vector2(x, y), s, align, w, size, col)

func _txt_c(s: String, r: Rect2, size: int, col: Color, bold: bool = false) -> void:
	var f: Font = font_bold if bold else font
	var asc: float = f.get_ascent(size)
	var desc: float = f.get_descent(size)
	var y: float = r.position.y + (r.size.y + asc - desc) * 0.5
	draw_string(f, Vector2(r.position.x, y), s, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, size, col)

func _txt_r(s: String, right_x: float, y: float, size: int, col: Color, bold: bool = false, w: float = 420.0) -> void:
	draw_string(font_bold if bold else font, Vector2(right_x - w, y), s, HORIZONTAL_ALIGNMENT_RIGHT, w, size, col)

func _txt_w(s: String, size: int, bold: bool = false) -> float:
	var f: Font = font_bold if bold else font
	return f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

func _fit_size(s: String, max_w: float, size: int, bold: bool = false) -> int:
	var sz := size
	while sz > 10 and _txt_w(s, sz, bold) > max_w:
		sz -= 1
	return sz

func _wrap(s: String, x: float, y: float, w: float, size: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_CENTER, bold: bool = false) -> float:
	var f: Font = font_bold if bold else font
	var sz: Vector2 = f.get_multiline_string_size(s, align, w, size)
	draw_multiline_string(f, Vector2(x, y), s, align, w, size, -1, col)
	return sz.y

func _wrap_h(s: String, w: float, size: int, bold: bool = false) -> float:
	var f: Font = font_bold if bold else font
	return f.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_CENTER, w, size).y

# ---------- shape helpers ----------
func _panel(r: Rect2, fill: Color, rad: float = 16.0, bc: Color = Color(0, 0, 0, 0), bw: float = 0.0, shadow: float = 0.0, sy: float = 0.0) -> void:
	var key := "%s|%s|%s|%s|%s|%s" % [fill.to_html(true), rad, bc.to_html(true), bw, shadow, sy]
	var sb: StyleBoxFlat = _sb_cache.get(key)
	if sb == null:
		if _sb_cache.size() > 700:
			_sb_cache.clear()
		sb = StyleBoxFlat.new()
		sb.bg_color = fill
		sb.set_corner_radius_all(int(rad))
		sb.anti_aliasing = true
		if bw > 0.0:
			sb.set_border_width_all(int(ceil(bw)))
			sb.border_color = bc
		if shadow > 0.0:
			sb.shadow_color = Color(0, 0, 0, 0.40)
			sb.shadow_size = int(shadow)
			sb.shadow_offset = Vector2(0, sy)
		_sb_cache[key] = sb
	draw_style_box(sb, r)

func _gloss(r: Rect2, rad: float, a: float = 0.07) -> void:
	var key := "gloss|%s|%s" % [rad, a]
	var sb: StyleBoxFlat = _sb_cache.get(key)
	if sb == null:
		sb = StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, a)
		sb.corner_radius_top_left = int(rad)
		sb.corner_radius_top_right = int(rad)
		sb.corner_radius_bottom_left = 0
		sb.corner_radius_bottom_right = 0
		sb.anti_aliasing = true
		_sb_cache[key] = sb
	draw_style_box(sb, Rect2(r.position, Vector2(r.size.x, r.size.y * 0.5)))

func _ring(c: Vector2, r: float, col: Color, w: float = 2.0) -> void:
	draw_arc(c, r, 0.0, TAU, 40, col, w, true)

func _vgrad(r: Rect2, top: Color, bot: Color) -> void:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	draw_polygon(pts, PackedColorArray([top, top, bot, bot]))

func _glow(c: Vector2, rad: float, col: Color) -> void:
	draw_texture_rect(_glow_tex, Rect2(c - Vector2(rad, rad), Vector2(rad, rad) * 2.0), false, col)

func _ease_out(t: float) -> float:
	var x: float = clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)

func _ease_back(t: float) -> float:
	var x: float = clampf(t, 0.0, 1.0)
	var c1: float = 1.70158
	var c3: float = c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)

func _lum_text(col: Color) -> Color:
	return Color(0.05, 0.07, 0.14) if col.get_luminance() > 0.45 else Color(1, 1, 1)

# ---------- music ----------
const MUSIC_MENU := "res://audio/music_menu.wav"
const MUSIC_GAME := "res://audio/music_game.wav"
const MUSIC_MAX := 0.7
var _music_player: AudioStreamPlayer
var _music_cur: String = ""
var _music_vol: float = 0.0

func _setup_music() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.volume_db = -80.0
	add_child(_music_player)
	_music_player.finished.connect(_on_music_finished)

func _on_music_finished() -> void:
	if _music_cur != "" and _music_player.stream != null:
		_music_player.play()

func _music_want() -> String:
	if not scoring_service.music_on:
		return ""
	return MUSIC_GAME if state == State.PLAYING else MUSIC_MENU

func _music_update(delta: float) -> void:
	if _music_player == null:
		return
	var want: String = _music_want()
	if want != _music_cur:
		_music_vol = move_toward(_music_vol, 0.0, delta / 0.5)
		if _music_vol <= 0.001:
			_music_cur = want
			_music_player.stop()
			_music_player.stream = null
			if want != "":
				var st = load(want)
				if st != null:
					if st is AudioStreamWAV:
						st.loop_mode = AudioStreamWAV.LOOP_FORWARD
						st.loop_begin = 0
						st.loop_end = int(st.data.size() / 2)
					_music_player.stream = st
					_music_player.play()
	elif _music_cur != "":
		_music_vol = move_toward(_music_vol, MUSIC_MAX, delta / 0.8)
	_music_player.volume_db = linear_to_db(maxf(_music_vol, 0.0001))

func _toggle_music() -> void:
	scoring_service.music_on = not scoring_service.music_on
	_save_scores()
	_show_toast("موسیقی روشن شد" if scoring_service.music_on else "موسیقی خاموش شد")
	_rebuild_buttons()

func _music_icon() -> String:
	return "music" if scoring_service.music_on else "music_off"

func _music_label() -> String:
	return "موسیقی: روشن" if scoring_service.music_on else "موسیقی: خاموش"

# ---------- icons ----------
func _draw_icon(n: String, c: Vector2, s: float, col: Color, w: float = 2.4) -> void:
	var h: float = s * 0.5
	match n:
		"back":
			draw_polyline(PackedVector2Array([c + Vector2(-h * 0.35, -h * 0.75), c + Vector2(h * 0.4, 0), c + Vector2(-h * 0.35, h * 0.75)]), col, w, true)
		"forward":
			draw_polyline(PackedVector2Array([c + Vector2(h * 0.35, -h * 0.75), c + Vector2(-h * 0.4, 0), c + Vector2(h * 0.35, h * 0.75)]), col, w, true)
		"close":
			draw_line(c + Vector2(-h * 0.6, -h * 0.6), c + Vector2(h * 0.6, h * 0.6), col, w, true)
			draw_line(c + Vector2(h * 0.6, -h * 0.6), c + Vector2(-h * 0.6, h * 0.6), col, w, true)
		"music", "music_off":
			draw_line(c + Vector2(h * 0.35, -h * 0.75), c + Vector2(h * 0.35, h * 0.4), col, w, true)
			draw_line(c + Vector2(h * 0.35, -h * 0.75), c + Vector2(-h * 0.45, -h * 0.5), col, w, true)
			draw_line(c + Vector2(-h * 0.45, -h * 0.5), c + Vector2(-h * 0.45, h * 0.6), col, w, true)
			draw_circle(c + Vector2(h * 0.1, h * 0.45), h * 0.3, col)
			draw_circle(c + Vector2(-h * 0.7, h * 0.65), h * 0.3, col)
			if n == "music_off":
				draw_line(c + Vector2(-h * 0.9, -h * 0.9), c + Vector2(h * 0.9, h * 0.9), Color(1.0, 0.45, 0.5), w * 1.2, true)
		"help":
			_ring(c, h * 0.9, col, w * 0.8)
			_txt_c("؟", Rect2(c - Vector2(h, h), Vector2(s, s)), int(s * 0.7), col, true)
		"pause":
			_panel(Rect2(c + Vector2(-h * 0.55, -h * 0.65), Vector2(h * 0.42, h * 1.3)), col, 2)
			_panel(Rect2(c + Vector2(h * 0.13, -h * 0.65), Vector2(h * 0.42, h * 1.3)), col, 2)
		"play":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.45, -h * 0.7), c + Vector2(h * 0.7, 0), c + Vector2(-h * 0.45, h * 0.7)]), col)
		"door":
			draw_polyline(PackedVector2Array([c + Vector2(-h * 0.1, -h * 0.8), c + Vector2(-h * 0.7, -h * 0.8), c + Vector2(-h * 0.7, h * 0.8), c + Vector2(-h * 0.1, h * 0.8)]), col, w, true)
			draw_line(c + Vector2(-h * 0.1, 0), c + Vector2(h * 0.8, 0), col, w, true)
			draw_polyline(PackedVector2Array([c + Vector2(h * 0.45, -h * 0.35), c + Vector2(h * 0.8, 0), c + Vector2(h * 0.45, h * 0.35)]), col, w, true)
		"flag":
			draw_line(c + Vector2(-h * 0.5, -h * 0.8), c + Vector2(-h * 0.5, h * 0.8), col, w, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.5, -h * 0.75), c + Vector2(h * 0.7, -h * 0.4), c + Vector2(-h * 0.5, h * 0.1)]), col)
		"cpu":
			_panel(Rect2(c - Vector2(h * 0.55, h * 0.55), Vector2(h * 1.1, h * 1.1)), Color(0, 0, 0, 0), 3, col, w * 0.8)
			for i in 3:
				var o: float = (i - 1) * h * 0.45
				draw_line(c + Vector2(o, -h * 0.55), c + Vector2(o, -h * 0.95), col, w * 0.7)
				draw_line(c + Vector2(o, h * 0.55), c + Vector2(o, h * 0.95), col, w * 0.7)
				draw_line(c + Vector2(-h * 0.55, o), c + Vector2(-h * 0.95, o), col, w * 0.7)
				draw_line(c + Vector2(h * 0.55, o), c + Vector2(h * 0.95, o), col, w * 0.7)
			draw_circle(c, h * 0.18, col)
		"wifi":
			for i in 3:
				var rr: float = h * (0.45 + i * 0.42)
				draw_arc(c + Vector2(0, h * 0.6), rr, deg_to_rad(-135), deg_to_rad(-45), 14, col, w * 0.85, true)
			draw_circle(c + Vector2(0, h * 0.6), h * 0.12, col)
		"globe":
			_ring(c, h * 0.9, col, w * 0.8)
			draw_arc(c, h * 0.9, deg_to_rad(-90), deg_to_rad(90), 12, col, 1.2, true)
			draw_line(c + Vector2(-h * 0.9, 0), c + Vector2(h * 0.9, 0), col, 1.4, true)
			draw_line(c + Vector2(0, -h * 0.9), c + Vector2(0, h * 0.9), col, 1.4, true)
			var pts := PackedVector2Array()
			for i in 17:
				var a: float = -PI * 0.5 + PI * i / 16.0
				pts.append(c + Vector2(cos(a) * h * 0.42, sin(a) * h * 0.9))
			draw_polyline(pts, col, 1.4, true)
			var pts2 := PackedVector2Array()
			for i in 17:
				var a2: float = PI * 0.5 + PI * i / 16.0
				pts2.append(c + Vector2(cos(a2) * h * 0.42, sin(a2) * h * 0.9))
			draw_polyline(pts2, col, 1.4, true)
		"keypad":
			for i in 9:
				draw_circle(c + Vector2((i % 3 - 1) * h * 0.62, (i / 3 - 1) * h * 0.62), h * 0.17, col)
		"trophy":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.55, -h * 0.75), c + Vector2(h * 0.55, -h * 0.75), c + Vector2(h * 0.4, h * 0.05), c + Vector2(h * 0.12, h * 0.3), c + Vector2(-h * 0.12, h * 0.3), c + Vector2(-h * 0.4, h * 0.05)]), col)
			draw_arc(c + Vector2(-h * 0.55, -h * 0.4), h * 0.3, deg_to_rad(90), deg_to_rad(270), 10, col, w * 0.7, true)
			draw_arc(c + Vector2(h * 0.55, -h * 0.4), h * 0.3, deg_to_rad(-90), deg_to_rad(90), 10, col, w * 0.7, true)
			draw_rect(Rect2(c + Vector2(-h * 0.1, h * 0.3), Vector2(h * 0.2, h * 0.3)), col)
			_panel(Rect2(c + Vector2(-h * 0.5, h * 0.58), Vector2(h, h * 0.22)), col, 2)
		"chart":
			_panel(Rect2(c + Vector2(-h * 0.75, h * 0.0), Vector2(h * 0.4, h * 0.8)), col, 2)
			_panel(Rect2(c + Vector2(-h * 0.2, -h * 0.8), Vector2(h * 0.4, h * 1.6)), col, 2)
			_panel(Rect2(c + Vector2(h * 0.35, -h * 0.35), Vector2(h * 0.4, h * 1.15)), col, 2)
		"gamepad":
			_panel(Rect2(c + Vector2(-h * 0.95, -h * 0.5), Vector2(h * 1.9, h * 1.05)), Color(0, 0, 0, 0), h * 0.5, col, w * 0.8)
			draw_line(c + Vector2(-h * 0.5, -h * 0.2), c + Vector2(-h * 0.5, h * 0.25), col, w * 0.8)
			draw_line(c + Vector2(-h * 0.72, h * 0.02), c + Vector2(-h * 0.28, h * 0.02), col, w * 0.8)
			draw_circle(c + Vector2(h * 0.4, -h * 0.05), h * 0.1, col)
			draw_circle(c + Vector2(h * 0.65, h * 0.2), h * 0.1, col)
		"home":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h * 0.9), c + Vector2(h * 0.95, -h * 0.05), c + Vector2(-h * 0.95, -h * 0.05)]), col)
			draw_rect(Rect2(c + Vector2(-h * 0.6, -h * 0.05), Vector2(h * 1.2, h * 0.85)), col)
		"power":
			draw_arc(c, h * 0.75, deg_to_rad(-60), deg_to_rad(240), 20, col, w, true)
			draw_line(c + Vector2(0, -h * 0.95), c + Vector2(0, -h * 0.1), col, w, true)
		"restart":
			draw_arc(c, h * 0.7, deg_to_rad(-40), deg_to_rad(270), 20, col, w, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(h * 0.55, -h * 0.9), c + Vector2(h * 0.95, -h * 0.25), c + Vector2(h * 0.2, -h * 0.35)]), col)
		"check":
			draw_polyline(PackedVector2Array([c + Vector2(-h * 0.7, 0), c + Vector2(-h * 0.2, h * 0.5), c + Vector2(h * 0.7, -h * 0.5)]), col, w * 1.15, true)
		"copy":
			_panel(Rect2(c + Vector2(-h * 0.2, -h * 0.75), Vector2(h * 0.95, h * 1.1)), Color(0, 0, 0, 0), 3, col, w * 0.7)
			_panel(Rect2(c + Vector2(-h * 0.75, -h * 0.35), Vector2(h * 0.95, h * 1.1)), Color(0, 0, 0, 0), 3, col, w * 0.7)
		"backspace":
			draw_polyline(PackedVector2Array([c + Vector2(-h * 0.2, -h * 0.6), c + Vector2(h * 0.8, -h * 0.6), c + Vector2(h * 0.8, h * 0.6), c + Vector2(-h * 0.2, h * 0.6), c + Vector2(-h * 0.85, 0), c + Vector2(-h * 0.2, -h * 0.6)]), col, w * 0.8, true)
			draw_line(c + Vector2(0, -h * 0.25), c + Vector2(h * 0.5, h * 0.25), col, w * 0.7, true)
			draw_line(c + Vector2(h * 0.5, -h * 0.25), c + Vector2(0, h * 0.25), col, w * 0.7, true)
		"rot_cw":
			draw_arc(c, h * 0.7, deg_to_rad(-60), deg_to_rad(210), 18, col, w, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.95, h * 0.3), c + Vector2(-h * 0.35, h * 0.2), c + Vector2(-h * 0.7, h * 0.9)]), col)
		"rot_ccw":
			draw_arc(c, h * 0.7, deg_to_rad(-30), deg_to_rad(240), 18, col, w, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(h * 0.95, h * 0.3), c + Vector2(h * 0.35, h * 0.2), c + Vector2(h * 0.7, h * 0.9)]), col)
		"user":
			draw_circle(c + Vector2(0, -h * 0.35), h * 0.38, col)
			draw_arc(c + Vector2(0, h * 0.95), h * 0.8, deg_to_rad(200), deg_to_rad(340), 12, col, w * 1.6, true)
		"warning":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h * 0.9), c + Vector2(h * 0.95, h * 0.75), c + Vector2(-h * 0.95, h * 0.75)]), col)
			draw_line(c + Vector2(0, -h * 0.3), c + Vector2(0, h * 0.25), BG_TOP, w * 0.9, true)
			draw_circle(c + Vector2(0, h * 0.5), w * 0.5, BG_TOP)
		"crown":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.8, h * 0.55), c + Vector2(-h * 0.85, -h * 0.5), c + Vector2(-h * 0.35, -h * 0.05), c + Vector2(0, -h * 0.75), c + Vector2(h * 0.35, -h * 0.05), c + Vector2(h * 0.85, -h * 0.5), c + Vector2(h * 0.8, h * 0.55)]), col)
		"star":
			var sp := PackedVector2Array()
			for i in 10:
				var rr2: float = h * (0.95 if i % 2 == 0 else 0.42)
				var a3: float = -PI * 0.5 + i * PI / 5.0
				sp.append(c + Vector2(cos(a3), sin(a3)) * rr2)
			draw_colored_polygon(sp, col)
		"lock":
			_panel(Rect2(c + Vector2(-h * 0.6, -h * 0.1), Vector2(h * 1.2, h * 0.9)), col, 3)
			draw_arc(c + Vector2(0, -h * 0.1), h * 0.4, PI, TAU, 12, col, w, true)
		"info":
			_ring(c, h * 0.9, col, w * 0.8)
			draw_circle(c + Vector2(0, -h * 0.4), 1.8, col)
			draw_line(c + Vector2(0, -h * 0.1), c + Vector2(0, h * 0.5), col, w * 0.9, true)
		"plus":
			draw_line(c + Vector2(-h * 0.6, 0), c + Vector2(h * 0.6, 0), col, w, true)
			draw_line(c + Vector2(0, -h * 0.6), c + Vector2(0, h * 0.6), col, w, true)
		"undo":
			draw_arc(c + Vector2(0, h * 0.1), h * 0.65, deg_to_rad(180), deg_to_rad(400), 18, col, w, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.95, -h * 0.1), c + Vector2(-h * 0.25, -h * 0.2), c + Vector2(-h * 0.6, h * 0.5)]), col)
		"swap":
			draw_line(c + Vector2(-h * 0.7, -h * 0.35), c + Vector2(h * 0.7, -h * 0.35), col, w, true)
			draw_line(c + Vector2(h * 0.7, h * 0.35), c + Vector2(-h * 0.7, h * 0.35), col, w, true)

# ---------- background & chrome ----------
func _draw_bg(accent: Color = ACCENT) -> void:
	draw_texture_rect(_bg_tex, Rect2(0, 0, VIEW_W, VIEW_H), false)
	var k: float = 0.5 + 0.5 * sin(_time * 0.7)
	_glow(Vector2(60, 60), 360, Color(accent.r, accent.g, accent.b, 0.17 + 0.04 * k))
	_glow(Vector2(500, 880), 380, Color(0.35, 0.45, 1.0, 0.13 + 0.03 * (1.0 - k)))

func _draw_bar_top(h: float) -> void:
	draw_rect(Rect2(0, 0, VIEW_W, h), BAR)
	draw_rect(Rect2(0, h - 1, VIEW_W, 1), LINE)
	_vgrad(Rect2(0, h, VIEW_W, 22), Color(BAR.r, BAR.g, BAR.b, 0.95), Color(BAR.r, BAR.g, BAR.b, 0.0))

func _draw_bar_bottom(y: float) -> void:
	_vgrad(Rect2(0, y - 22, VIEW_W, 22), Color(BAR.r, BAR.g, BAR.b, 0.0), Color(BAR.r, BAR.g, BAR.b, 0.95))
	draw_rect(Rect2(0, y, VIEW_W, VIEW_H - y), BAR)
	draw_rect(Rect2(0, y, VIEW_W, 1), LINE)

func _nav_index() -> int:
	match state:
		State.MENU: return 0
		State.ONLINE: return 1
		State.RANKINGS: return 2
		State.DASHBOARD: return 3
	return -1

func _draw_bottom_nav() -> void:
	_draw_bar_bottom(868.0)
	var idx: int = _nav_index()
	var labels := ["بازی‌ها", "آنلاین", "رتبه‌بندی", "آمار"]
	var icons := ["gamepad", "globe", "trophy", "chart"]
	for i in 4:
		var cx: float = VIEW_W - (VIEW_W / 4.0) * (i + 0.5)
		var on: bool = (i == idx)
		var col: Color = ACCENT if on else TEXT_DIM
		if on:
			_panel(Rect2(cx - 38, 876, 76, 30), Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.16), 15)
		_draw_icon(icons[i], Vector2(cx, 891), 22, col, 2.2)
		_txt_c(labels[i], Rect2(cx - 50, 912, 100, 26), 13, col, on)

func _draw_topbar(title: String, subtitle: String = "", with_back: bool = true) -> void:
	_draw_bar_top(76.0)
	_txt_c(title, Rect2(70, 10, VIEW_W - 140, 40), 24, TEXT, true)
	if subtitle != "":
		_txt_c(subtitle, Rect2(40, 46, VIEW_W - 80, 24), 13, TEXT_DIM)

# ---------- toast ----------
func _show_toast(msg: String) -> void:
	toast_msg = msg
	toast_timer = 3.0

func _draw_toast() -> void:
	if toast_timer <= 0.0:
		return
	var a: float = clampf(toast_timer * 3.0, 0.0, 1.0)
	var enter: float = _ease_out((3.0 - toast_timer) / 0.25)
	var w: float = VIEW_W - 56.0
	var hh: float = _wrap_h(toast_msg, w - 56.0, 16) + 24.0
	var y: float = 800.0 - hh + (1.0 - enter) * 24.0
	var r := Rect2(28, y, w, hh)
	_panel(r, Color(0.13, 0.16, 0.30, 0.96 * a), 16, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.55 * a), 1.5, 14, 6)
	_draw_icon("info", Vector2(r.end.x - 24, r.position.y + hh * 0.5), 18, Color(ACCENT.r, ACCENT.g, ACCENT.b, a), 2.0)
	_wrap(toast_msg, r.position.x + 14, r.position.y + 12 + 16.0, w - 64.0, 16, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_RIGHT)

# ---------- buttons ----------
func _clear_buttons() -> void:
	buttons.clear()

func _add_btn(rect: Rect2, text: String, cb: Callable, enabled: bool = true, accent: Color = ACCENT, kind: String = "solid", icon: String = "", id: String = "", sub: String = "") -> void:
	var bid: String = id if id != "" else (text + "#" + str(buttons.size()))
	buttons.append({"rect": rect, "text": text, "cb": cb, "enabled": enabled, "accent": accent, "kind": kind, "icon": icon, "id": bid, "sub": sub, "scroll": false, "sel": false, "hint": ""})

func _add_ov_btn(rect: Rect2, text: String, cb: Callable, accent: Color = ACCENT, kind: String = "solid", icon: String = "", id: String = "", enabled: bool = true) -> void:
	var bid: String = id if id != "" else ("ov_" + text + "#" + str(ov_buttons.size()))
	ov_buttons.append({"rect": rect, "text": text, "cb": cb, "enabled": enabled, "accent": accent, "kind": kind, "icon": icon, "id": bid, "sub": "", "scroll": false, "sel": false, "hint": ""})

func _last_btn() -> Dictionary:
	return buttons[buttons.size() - 1]

func _add_hit(rect: Rect2, cb: Callable, id: String, scroll: bool = false, enabled: bool = true) -> void:
	buttons.append({"rect": rect, "text": "", "cb": cb, "enabled": enabled, "accent": ACCENT, "kind": "hit", "icon": "", "id": id, "sub": "", "scroll": scroll, "sel": false, "hint": ""})

func _active_buttons() -> Array:
	if _ov_active():
		return ov_buttons
	return buttons

func _btn_at(p: Vector2) -> Dictionary:
	var list: Array = _active_buttons()
	for i in range(list.size() - 1, -1, -1):
		var b: Dictionary = list[i]
		var r: Rect2 = b.rect
		var q: Vector2 = p
		if b.scroll:
			if p.y < _scroll_top or p.y > _scroll_bottom:
				continue
			q.y += scroll_y
		var gx: float = maxf(0.0, 46.0 - r.size.x) * 0.5
		var gy: float = maxf(0.0, 46.0 - r.size.y) * 0.5
		if r.grow_individual(gx, gy, gx, gy).has_point(q):
			return b
	return {}

func _fire(b: Dictionary) -> void:
	if not b.enabled:
		if str(b.hint) != "":
			_show_toast(str(b.hint))
		return
	Input.vibrate_handheld(12)
	var cb: Callable = b.cb
	cb.call()

func _draw_button(b: Dictionary) -> void:
	var kind: String = b.kind
	if kind == "hit":
		return
	var r: Rect2 = b.rect
	var en: bool = b.enabled
	var col: Color = b.accent
	var pressed: bool = _press_active and _press_id == str(b.id)
	if pressed:
		r = r.grow(-1.5)
	var radius: float = minf(r.size.y * 0.5, 16.0) if kind != "icon" and kind != "key" and kind != "disc" else r.size.y * 0.5
	if kind == "key":
		radius = 18.0
	var txt_col: Color = TEXT
	var icon_col: Color = TEXT
	match kind:
		"solid", "seg_on":
			if en:
				_panel(Rect2(r.position + Vector2(0, 3), r.size), Color(col.r * 0.45, col.g * 0.45, col.b * 0.45, 0.85), radius, Color(0, 0, 0, 0), 0.0, 8, 4)
				_panel(r, col.lightened(0.08) if pressed else col, radius)
				_gloss(r, radius, 0.14)
				txt_col = _lum_text(col)
				icon_col = txt_col
			else:
				_panel(r, DISABLED, radius, LINE, 1.0)
				txt_col = TEXT_FAINT
				icon_col = TEXT_FAINT
		"soft", "seg_off":
			var base: Color = Color(col.r * 0.20 + CARD.r * 0.8, col.g * 0.20 + CARD.g * 0.8, col.b * 0.20 + CARD.b * 0.8, 1.0)
			if pressed:
				base = base.lightened(0.12)
			if en:
				_panel(r, base, radius, Color(col.r, col.g, col.b, 0.55), 1.5, 6, 3)
				txt_col = TEXT
				icon_col = col.lightened(0.25)
			else:
				_panel(r, DISABLED, radius, LINE, 1.0)
				txt_col = TEXT_FAINT
				icon_col = TEXT_FAINT
		"ghost":
			_panel(r, Color(1, 1, 1, 0.10 if pressed else 0.04), radius, LINE_STRONG, 1.0)
			txt_col = TEXT_DIM if en else TEXT_FAINT
			icon_col = txt_col
		"icon", "disc":
			var bg: Color = Color(1, 1, 1, 0.16) if pressed else Color(1, 1, 1, 0.07)
			if kind == "disc" and en:
				bg = Color(col.r * 0.3, col.g * 0.3, col.b * 0.3, 0.9)
			_panel(r, bg, radius, LINE_STRONG if kind == "icon" else Color(col.r, col.g, col.b, 0.7), 1.0)
			icon_col = col if en else TEXT_FAINT
			if kind == "icon" and col == ACCENT:
				icon_col = TEXT
		"key":
			var kb: Color = Color(1, 1, 1, 0.16) if pressed else Color(1, 1, 1, 0.07)
			_panel(r, kb, radius, LINE_STRONG, 1.0, 6, 3)
			txt_col = col if en else TEXT_FAINT
			icon_col = txt_col
		"option":
			_draw_option_card(b, r, pressed)
			return
		"nav":
			return
	var ico: String = b.icon
	var tx: String = b.text
	if ico != "" and tx == "":
		_draw_icon(ico, r.get_center(), minf(r.size.x, r.size.y) * 0.46, icon_col)
	elif ico != "" and tx != "":
		var fs: int = _fit_size(tx, r.size.x - 70.0, 18, true)
		var tw: float = _txt_w(tx, fs, true)
		var total: float = tw + 30.0
		var sx: float = r.get_center().x - total * 0.5
		_draw_icon(ico, Vector2(sx + total - 11.0, r.get_center().y), 20, icon_col, 2.2)
		_txt_c(tx, Rect2(sx - 4, r.position.y, tw + 8, r.size.y), fs, txt_col, true)
	elif tx != "":
		var size: int = 22 if kind == "key" else 18
		var fs2: int = _fit_size(tx, r.size.x - 16.0, size, true)
		_txt_c(tx, r, fs2, txt_col, true)

func _draw_option_card(b: Dictionary, r: Rect2, pressed: bool) -> void:
	var col: Color = b.accent
	var en: bool = b.enabled
	var fill: Color = CARD_H if pressed else CARD
	_panel(r, fill, 20, Color(col.r, col.g, col.b, 0.45 if en else 0.12), 1.5, 12, 5)
	var disc_c := Vector2(r.end.x - 46, r.get_center().y)
	var dc: Color = col if en else TEXT_FAINT
	draw_circle(disc_c, 28, Color(dc.r, dc.g, dc.b, 0.20))
	_ring(disc_c, 28, Color(dc.r, dc.g, dc.b, 0.6), 1.5)
	_draw_icon(b.icon, disc_c, 28, dc.lightened(0.15), 2.4)
	_txt_r(b.text, r.end.x - 92, r.position.y + r.size.y * 0.5 - 4, 19, TEXT if en else TEXT_FAINT, true, r.size.x - 150)
	if str(b.sub) != "":
		_txt_r(b.sub, r.end.x - 92, r.position.y + r.size.y * 0.5 + 18, 13, TEXT_DIM if en else TEXT_FAINT, false, r.size.x - 150)
	_draw_icon("forward", Vector2(r.position.x + 26, r.get_center().y), 18, TEXT_DIM if en else TEXT_FAINT, 2.0)

# ---------- input ----------
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var e: InputEventMouseButton = event
		if e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_on_press(e.position)
			else:
				_on_release(e.position)
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll_by(-70.0)
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll_by(70.0)
	elif event is InputEventMouseMotion:
		var m: InputEventMouseMotion = event
		_ptr = m.position
		if _press_active:
			if m.position.distance_to(_press_pos) > 14.0:
				_press_moved = true
			if _press_moved and _scroll_enabled():
				_scroll_by(-m.relative.y)
				_scroll_vel = lerpf(_scroll_vel, -m.relative.y * 60.0, 0.5)
	elif event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and not k.echo:
			if k.keycode == KEY_ESCAPE:
				_go_back()
			elif state == State.IP_ENTRY and not _ov_active():
				if k.keycode == KEY_BACKSPACE:
					_ip_key("⌫")
				elif k.unicode >= 48 and k.unicode <= 57:
					_ip_key(String.chr(k.unicode))
				elif k.unicode == 46:
					_ip_key(".")
				elif k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
					if _valid_ip(join_ip):
						_do_join()

func _on_press(p: Vector2) -> void:
	_press_active = true
	_press_pos = p
	_press_moved = false
	_ptr = p
	_scroll_vel = 0.0
	var b: Dictionary = _btn_at(p)
	_press_id = str(b.id) if not b.is_empty() else ""

func _on_release(p: Vector2) -> void:
	if not _press_active:
		return
	_press_active = false
	var pid: String = _press_id
	_press_id = ""
	var moved: bool = _press_moved
	if moved and _scroll_enabled():
		return
	var b: Dictionary = _btn_at(p)
	if not b.is_empty():
		if pid != "" and str(b.id) == pid:
			_fire(b)
		return
	if pid == "" and not _ov_active() and state == State.PLAYING:
		if _press_pos.distance_to(p) < 28.0:
			_board_tap(p)

func _scroll_enabled() -> bool:
	if _ov_active():
		return false
	return state == State.MENU or state == State.DASHBOARD or state == State.RANKINGS or state == State.ONLINE

func _scroll_max() -> float:
	return maxf(0.0, _content_h - (_scroll_bottom - _scroll_top))

func _scroll_by(d: float) -> void:
	if not _scroll_enabled():
		return
	scroll_y = clampf(scroll_y + d, 0.0, _scroll_max())

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		if _music_player != null:
			_music_player.stream_paused = true
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		if _music_player != null:
			_music_player.stream_paused = false
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		if dialog.get("kind", "") == "exit":
			_quit_app()
		else:
			_go_back_to_exit_dialog()

func _go_back_to_exit_dialog() -> void:
	pause_open = false
	rules_open = false
	_confirm_exit_app()

func _quit_app() -> void:
	_cleanup_network()
	get_tree().quit()

func _board_tap(p: Vector2) -> void:
	match selected_game:
		"othello", "othello12": _othello_tap(p)
		"pentago": _pent_tap(p)
		"quoridor": _quo_tap(p)
		"domino": _dom_tap(p)
		"chess": _chess_tap(p)
		"pasoor": _pas_tap(p)
		"mastermind": _mm_tap(p)
		"gobblet": _gob_tap(p)
		"hokm": _hokm_tap(p)
		"backgammon": _bg_tap(p)
		"abalone": _aba_tap(p)
		"blockace": _blk_tap(p)

# ---------- central back / navigation ----------
func _ov_active() -> bool:
	return not dialog.is_empty() or pause_open or rules_open

func _go_back() -> void:
	if not dialog.is_empty():
		dialog = {}
		_rebuild_buttons()
		return
	if rules_open:
		rules_open = false
		_rebuild_buttons()
		return
	if pause_open:
		pause_open = false
		_rebuild_buttons()
		return
	match state:
		State.MENU:
			_confirm_exit_app()
		State.MODE, State.RESULT, State.DASHBOARD, State.RANKINGS, State.ONLINE:
			_back_to_menu()
		State.IP_ENTRY:
			_leave_lobby()
		State.LOBBY:
			_request_leave_lobby()
		State.PLAYING:
			_open_pause()

func _open_pause() -> void:
	pause_open = true
	_ov_t = 0.0
	_rebuild_buttons()

func _show_confirm(kind: String, title: String, body: String, confirm_text: String, on_confirm: Callable, danger: bool = true, cancel_text: String = "انصراف", icon: String = "warning") -> void:
	dialog = {"kind": kind, "title": title, "body": body, "confirm": confirm_text, "cancel": cancel_text, "cb": on_confirm, "danger": danger, "icon": icon}
	_ov_t = 0.0
	_rebuild_buttons()

func _dialog_confirm() -> void:
	var cb: Callable = dialog.get("cb", Callable())
	dialog = {}
	pause_open = false
	rules_open = false
	if cb.is_valid():
		cb.call()
	_rebuild_buttons()

func _confirm_exit_app() -> void:
	_show_confirm("exit", "خروج از برنامه؟", "آیا می‌خواهید از Mind Bastion خارج شوید؟", "خروج", _quit_app, true, "ماندن", "power")

func _confirm_exit_game() -> void:
	var body := "بازی جاری ناتمام می‌ماند و نتیجه‌ای ثبت نمی‌شود."
	if not vs_cpu and multiplayer.multiplayer_peer != null:
		body += "\nارتباط شما با حریف قطع خواهد شد."
	_show_confirm("exit_game", "خروج از بازی؟", body, "خروج به منو", _back_to_menu, true, "ادامه بازی", "door")

func _confirm_resign() -> void:
	_show_confirm("resign", "تسلیم می‌شوید؟", "این بازی به‌عنوان باخت ثبت می‌شود (%s امتیاز)." % _fa(scoring_service.LOSS_PTS), "تسلیم", _resign, true, "ادامه بازی", "flag")

func _confirm_restart() -> void:
	_show_confirm("restart", "شروع بازی جدید؟", "پیشرفت بازی فعلی از بین می‌رود و نتیجه‌ای ثبت نمی‌شود.", "بازی جدید", _restart_current, true, "انصراف", "restart")

func _request_leave_lobby() -> void:
	if multiplayer.multiplayer_peer != null:
		_show_confirm("leave", "ترک لابی؟", "اتصال شما بسته می‌شود و باید دوباره وصل شوید.", "ترک لابی", _leave_lobby, true, "ماندن", "door")
	else:
		_leave_lobby()

func _game_info(id: String) -> Dictionary:
	for g in GAMES:
		if g.id == id:
			return g
	return {}

func _set_game(id: String) -> void:
	if id != selected_game:
		pas_match_scores = [0, 0]
	selected_game = id
	max_players_for_game = int(_game_info(id).get("max_p", 2))

func _select_game(id: String) -> void:
	_set_game(id)
	_origin_online = false
	state = State.MODE
	_rebuild_buttons()

func _back_to_menu() -> void:
	_cleanup_network()
	dialog = {}
	state = State.MENU
	selected_game = ""
	online_searching = false
	online_room_code = ""
	_origin_online = false
	_rebuild_buttons()

func _open_dashboard() -> void:
	state = State.DASHBOARD
	_rebuild_buttons()

func _open_rankings() -> void:
	state = State.RANKINGS
	_rebuild_buttons()

func _open_online() -> void:
	if state != State.ONLINE:
		online_searching = false
		online_room_code = ""
	state = State.ONLINE
	_rebuild_buttons()

func _leave_lobby() -> void:
	_cleanup_network()
	online_room_code = ""
	state = State.ONLINE if _origin_online else State.MODE
	_rebuild_buttons()

func _go_result(_won: bool = false) -> void:
	state = State.RESULT
	_build_result_buttons()

# wrappers kept for the game-logic code that triggers a UI refresh
func _build_menu_buttons() -> void:
	_rebuild_buttons()
func _build_mode_buttons() -> void:
	_rebuild_buttons()
func _build_lobby_buttons() -> void:
	_rebuild_buttons()
func _build_ip_buttons() -> void:
	_rebuild_buttons()
func _build_playing_buttons() -> void:
	_rebuild_buttons()
func _build_pent_rotate_buttons() -> void:
	_rebuild_buttons()
func _build_online_buttons() -> void:
	_rebuild_buttons()

func _build_result_buttons() -> void:
	if not _result_logged:
		_result_logged = true
		_result_draw = _result_is_draw()
		var won: bool = _player_won_current()
		_result_delta = 0
		var shared_device_four_player: bool = selected_game == "quoridor" and bool(_game_modules["quoridor"].quo_local_multiplayer)
		# Do not award a single account a win/loss for a shared-device match between four people.
		if not shared_device_four_player and not _result_draw and _result_counts():
			_result_delta = scoring_service.WIN_PTS if won else scoring_service.LOSS_PTS
			_record_match_result(won)
		_result_t0 = _time
	_rebuild_buttons()

func _result_counts() -> bool:
	if selected_game == "pasoor":
		return _pas_match_over()
	return true

func _pas_match_over() -> bool:
	return pas_match_scores[0] >= PAS_TARGET or pas_match_scores[1] >= PAS_TARGET

func _result_is_draw() -> bool:
	match selected_game:
		"othello", "othello12": return othello_winner == 0
		"pentago": return pent_winner == 0
		"chess": return chess_winner == 0
		"domino": return dom_winner < 0
		"pasoor": return pas_winner < 0
		"blockace": return blk_winner < 0
		"quoridor": return quo_winner < 0
		"mastermind": return not vs_cpu and int(_game_modules["mastermind"].mm_winner) < 0
	return false

func _player_won_current() -> bool:
	var seat: int = 0 if vs_cpu else local_seat
	match selected_game:
		"othello", "othello12": return othello_winner == seat + 1
		"pentago": return pent_winner == seat + 1
		"chess": return chess_winner == seat + 1
		"quoridor": return quo_winner == seat
		"domino": return dom_winner == seat
		"pasoor": return pas_winner == seat
		"mastermind": return mm_won
		"gobblet": return gob_winner == seat + 1
		"hokm": return hokm_winner == seat
		"backgammon": return bg_winner == seat
		"abalone": return aba_winner == seat + 1
		"blockace": return blk_winner == seat
	return false

# ---------- resign ----------
func _resign() -> void:
	if state != State.PLAYING:
		return
	if not vs_cpu and multiplayer.multiplayer_peer != null:
		rpc("_rpc_resign", local_seat)
	else:
		_apply_resign(0)

@rpc("any_peer", "call_local", "reliable")
func _rpc_resign(seat: int) -> void:
	_apply_resign(seat)

func _apply_resign(seat: int) -> void:
	match selected_game:
		"othello", "othello12":
			othello_game_over = true
			othello_winner = 2 - seat
		"pentago":
			pent_game_over = true
			pent_winner = 2 - seat
		"quoridor":
			quo_game_over = true
			quo_winner = 1 - seat
		"domino":
			dom_game_over = true
			dom_winner = 1 - seat
		"chess":
			chess_game_over = true
			chess_winner = 2 - seat
		"pasoor":
			pas_game_over = true
			pas_winner = 1 - seat
			if seat == 0:
				pas_match_scores[1] = maxi(pas_match_scores[1], PAS_TARGET)
			else:
				pas_match_scores[0] = maxi(pas_match_scores[0], PAS_TARGET)
		"mastermind":
			mm_game_over = true
			mm_won = (not vs_cpu) and (1 - seat) == local_seat
			_game_modules["mastermind"].mm_winner = 1 - seat
		"gobblet":
			gob_game_over = true
			gob_winner = 2 - seat
		"hokm":
			hokm_game_over = true
			hokm_winner = 1 - seat
		"backgammon":
			bg_game_over = true
			bg_winner = 1 - seat
		"abalone":
			aba_game_over = true
			aba_winner = 2 - seat
		"blockace":
			blk_game_over = true
			blk_winner = 1 - seat
	_go_result(false)

# ---------- game start / restart ----------
func _start_game() -> void:
	_result_logged = false
	_game_epoch += 1
	_prev_boards.clear()
	_cell_anim.clear()
	_cpu_pending = false
	hokm_last = []
	hokm_last_t = -10.0
	blk_rot = 0
	blk_prev = Vector2i(-1, -1)
	dialog = {}
	state = State.PLAYING
	match selected_game:
		"othello":
			oth_size = 8
			_reset_othello()
		"othello12":
			oth_size = 12
			_reset_othello()
		"pentago":
			_reset_pentago()
		"quoridor":
			_reset_quoridor()
		"domino":
			_reset_domino()
		"chess":
			_reset_chess()
		"pasoor":
			if _pas_match_over():
				pas_match_scores = [0, 0]
			_reset_pasoor()
		"hokm":
			_reset_hokm()
		"backgammon":
			_reset_backgammon()
		"gobblet":
			_reset_gobblet()
		"mastermind":
			_reset_mastermind()
		"abalone":
			_reset_abalone()
		"blockace":
			_reset_blockace()
		_:
			_show_toast("این بازی هنوز کامل نشده")
			state = State.MODE
			_rebuild_buttons()
			return
	if not seen_rules.has(selected_game):
		seen_rules[selected_game] = true
		rules_open = true
		_ov_t = 0.0
		_save_scores()
	_rebuild_buttons()

func _restart_current() -> void:
	if not vs_cpu and multiplayer.multiplayer_peer != null:
		if is_host:
			var rng_seed: int = randi()
			rpc("_rpc_start_game", selected_game, rng_seed)
	else:
		_start_game()

# ---------- cpu scheduling ----------
func _schedule_cpu(delay: float, cb: Callable) -> void:
	if _cpu_pending:
		return
	_cpu_pending = true
	var epoch: int = _game_epoch
	await get_tree().create_timer(delay).timeout
	_cpu_pending = false
	if epoch != _game_epoch or state != State.PLAYING or not vs_cpu or _ov_active():
		return
	cb.call()

func _cpu_tick() -> void:
	if state != State.PLAYING or not vs_cpu or _cpu_pending or _ov_active():
		return
	match selected_game:
		"othello", "othello12":
			if not othello_game_over and othello_turn == 2:
				_schedule_cpu(0.7, _othello_cpu_move)
		"pentago":
			if not pent_game_over and pent_turn == 2:
				_schedule_cpu(0.7, _pent_cpu_move)
		"quoridor":
			if not quo_game_over and quo_turn == 1:
				_schedule_cpu(0.7, _quo_cpu)
		"domino":
			if not dom_game_over and dom_turn == 1:
				_schedule_cpu(0.85, _dom_cpu_move)
		"chess":
			if not chess_game_over and chess_turn == 2:
				_schedule_cpu(0.7, _chess_cpu_move)
		"pasoor":
			if not pas_game_over and pas_turn == 1:
				_schedule_cpu(0.85, _pas_cpu_move)
		"hokm":
			if not hokm_game_over and hokm_turn == 1:
				_schedule_cpu(0.9, _hokm_cpu)
		"gobblet":
			if not gob_game_over and gob_turn == 2:
				_schedule_cpu(0.6, _gob_cpu)
		"abalone":
			if not aba_game_over and aba_turn == 2:
				_schedule_cpu(0.6, _aba_cpu)
		"blockace":
			if not blk_game_over and blk_turn == 1:
				_schedule_cpu(0.6, _blk_cpu)

func _ui_sig() -> String:
	var s: String = "%d|%d|%d|%s|%s|%d|%d|%d|%s|%s|%d" % [state, int(pause_open), int(rules_open), str(dialog.get("title", "")), menu_filter, dash_tab, connected_players, int(online_searching), online_game, join_ip, int(is_host)]
	s += "|%d|%d" % [int(multiplayer.multiplayer_peer != null), int(_result_logged)]
	if state == State.PLAYING:
		match selected_game:
			"pentago": s += "|%d|%d" % [pent_phase, pent_turn]
			"quoridor": s += "|%d|%d" % [quo_mode, quo_turn]
			"domino": s += "|%d|%d|%d|%d|%d|%d" % [dom_turn, dom_selected, dom_boneyard.size(), dom_hands[0].size(), dom_hands[1].size(), dom_chain.size()]
			"pasoor": s += "|%d|%d|%d|%d" % [pas_turn, pas_selected, pas_table.size(), pas_hands[0].size() + pas_hands[1].size()]
			"mastermind": s += "|%d|%s|%d|%d" % [mm_slot, str(mm_filled), int(_game_modules["mastermind"].mm_turn), mm_guesses.size()]
			"gobblet": s += "|%d|%d" % [gob_sel_size, gob_turn]
			"backgammon": s += "|%d|%d" % [bg_turn, bg_moves_left.size()]
			"blockace": s += "|%d|%d|%d|%d|%d" % [blk_sel, blk_rot, blk_turn, blk_prev.x, blk_prev.y]
			"hokm": s += "|%d|%d" % [hokm_turn, hokm_hands[0].size()]
			"abalone": s += "|%d" % aba_turn
			"chess": s += "|%d" % chess_turn
			"othello", "othello12": s += "|%d" % othello_turn
	return s

# ---------- board change tracking (animations) ----------
func _track_board(key: String, flat: Array) -> void:
	var prev: Array = _prev_boards.get(key, [])
	if prev.size() == flat.size():
		for i in flat.size():
			if prev[i] != flat[i]:
				_cell_anim[key + ":" + str(i)] = [_time, prev[i]]
	_prev_boards[key] = flat.duplicate()

# returns [progress 0..1, old_value]
func _cell_t(key: String, idx: int, dur: float = 0.4) -> Array:
	var k: String = key + ":" + str(idx)
	if not _cell_anim.has(k):
		return [1.0, 0]
	var a: Array = _cell_anim[k]
	var t: float = (_time - float(a[0])) / dur
	if t >= 1.0:
		_cell_anim.erase(k)
		return [1.0, 0]
	return [t, a[1]]


# ======================================================================
#  SCREENS — buttons builder + drawing for every non-game screen
# ======================================================================
const NET_GAMES := ["othello", "othello12", "pentago", "chess", "domino", "pasoor", "quoridor", "hokm", "backgammon", "gobblet", "mastermind", "abalone", "blockace"]
const TILE_W := 248.0
const TILE_H := 176.0
const TILE_GAP := 12.0

func _rebuild_buttons() -> void:
	buttons.clear()
	ov_buttons.clear()
	match state:
		State.MENU: _btns_menu()
		State.MODE: _btns_mode()
		State.LOBBY: _btns_lobby()
		State.IP_ENTRY: _btns_ip()
		State.PLAYING: _btns_playing()
		State.RESULT: _btns_result()
		State.DASHBOARD: _btns_dashboard()
		State.RANKINGS: _btns_rankings()
		State.ONLINE: _btns_online()
	if _ov_active():
		if not dialog.is_empty():
			_btns_dialog()
		elif rules_open:
			_btns_rules()
		else:
			_btns_pause()

func _back_btn() -> void:
	_add_btn(Rect2(VIEW_W - 60, 16, 44, 44), "", _go_back, true, TEXT, "icon", "back", "back")

func _btns_nav() -> void:
	var fns: Array = [_back_to_menu, _open_online, _open_rankings, _open_dashboard]
	for i in 4:
		var w: float = VIEW_W / 4.0
		_add_hit(Rect2(VIEW_W - w * (i + 1), 868, w, 92), fns[i], "nav_%d" % i)

# ---------------- MENU ----------------
func _menu_games() -> Array:
	var res: Array = []
	for g in GAMES:
		if menu_filter == "all" or g.cat == menu_filter:
			res.append(g)
	return res

func _tile_rect(i: int) -> Rect2:
	var col: int = i % 2
	var row: int = int(i / 2)
	var x: float = VIEW_W - 16.0 - TILE_W - col * (TILE_W + TILE_GAP)
	var y: float = _scroll_top + 14.0 + row * (TILE_H + TILE_GAP)
	return Rect2(x, y, TILE_W, TILE_H)

func _set_filter(key: String) -> void:
	menu_filter = key
	scroll_y = 0.0
	_rebuild_buttons()

func _btns_menu() -> void:
	_scroll_top = 176.0
	_scroll_bottom = 868.0
	var games: Array = _menu_games()
	var rows: int = int((games.size() + 1) / 2)
	_content_h = 14.0 + rows * (TILE_H + TILE_GAP) + 16.0
	for i in games.size():
		var id: String = games[i].id
		_add_hit(_tile_rect(i), _select_game.bind(id), "game_" + id, true)
	_add_btn(Rect2(16, 22, 44, 44), "", _confirm_exit_app, true, TEXT_DIM, "icon", "power", "exit")
	_add_btn(Rect2(214, 22, 44, 44), "", _toggle_music, true, ACCENT if scoring_service.music_on else TEXT_DIM, "icon", _music_icon(), "music")
	var x: float = VIEW_W - 16.0
	for key in ["all", "strategy", "cards", "classic"]:
		var label: String = CAT_LABELS[key]
		var w: float = _txt_w(label, 16, true) + 32.0
		x -= w
		_add_btn(Rect2(x, 124, w, 38), label, _set_filter.bind(key), true, ACCENT, "seg_on" if key == menu_filter else "ghost", "", "chip_" + key)
		x -= 8.0
	_btns_nav()

func _tier_info() -> Array:
	return RankingServiceScript.tier_info(scoring_service.global_rating)

func _draw_emblem(c: Vector2, s: float) -> void:
	var r := Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s))
	_panel(r, ACCENT, s * 0.28, Color(0, 0, 0, 0), 0.0, 10, 4)
	_gloss(r, s * 0.28, 0.2)
	var dk := Color(0.10, 0.12, 0.24)
	var u: float = s / 56.0
	draw_rect(Rect2(c + Vector2(-14, -4) * u, Vector2(28, 26) * u), dk)
	for i in 3:
		draw_rect(Rect2(c + Vector2(-14 + i * 11.5, -13) * u, Vector2(5, 10) * u), dk)
	draw_arc(c + Vector2(0, 22) * u, 6 * u, PI, TAU, 10, ACCENT, 3 * u, true)
	draw_rect(Rect2(c + Vector2(-6, 14) * u, Vector2(12, 8) * u), ACCENT)

func _draw_menu() -> void:
	var games: Array = _menu_games()
	for i in games.size():
		var r: Rect2 = _tile_rect(i)
		r.position.y -= scroll_y
		if r.end.y < _scroll_top - 10 or r.position.y > _scroll_bottom + 10:
			continue
		_draw_game_tile(games[i], r, _press_active and _press_id == "game_" + str(games[i].id))
	_draw_bar_top(170.0)
	_draw_emblem(Vector2(VIEW_W - 16 - 28, 56), 56.0)
	_txt_r("MIND BASTION", VIEW_W - 16 - 56 - 14, 56, 27, TEXT, true, 300)
	_txt_r("مجموعه بازی‌های فکری", VIEW_W - 16 - 56 - 14, 80, 14, TEXT_DIM, false, 300)
	var tier: Array = _tier_info()
	var tc: Color = tier[1]
	var pill := Rect2(68, 26, 138, 36)
	_panel(pill, Color(1, 1, 1, 0.06), 18, Color(tc.r, tc.g, tc.b, 0.5), 1.0)
	draw_circle(Vector2(pill.end.x - 18, pill.get_center().y), 7, tc)
	_txt_c("%s · %s" % [tier[0], _fa(scoring_service.global_rating)], Rect2(pill.position.x + 4, pill.position.y, pill.size.x - 36, pill.size.y), 14, TEXT, true)
	if games.size() == 0:
		_txt_c("بازی‌ای پیدا نشد", Rect2(0, 400, VIEW_W, 40), 18, TEXT_DIM)
	if _scroll_max() > 4.0 and scroll_y < _scroll_max() - 4.0:
		var a: float = 0.55 + 0.25 * sin(_time * 3.0)
		_draw_icon("back", Vector2(VIEW_W * 0.5, 858), 14, Color(1, 1, 1, a * 0.7), 2.0)
	_draw_bottom_nav()

func _draw_game_tile(g: Dictionary, r: Rect2, pressed: bool) -> void:
	var col: Color = g.icon_col
	if pressed:
		r = r.grow(-3)
	_panel(r, CARD_H if pressed else CARD, 20, Color(col.r, col.g, col.b, 0.38), 1.5, 14, 6)
	var art := Rect2(r.position + Vector2(10, 10), Vector2(r.size.x - 20, 98))
	_panel(art, Color(col.r * 0.30 + 0.035, col.g * 0.30 + 0.045, col.b * 0.30 + 0.09, 1.0), 14)
	_draw_game_art(str(g.id), art, col)
	_gloss(art, 14, 0.05)
	var chip := Rect2(art.position + Vector2(8, 8), Vector2(54, 22))
	_panel(chip, Color(0, 0, 0, 0.38), 11)
	_txt_c(_fa("2") + " نفره", chip, 12, TEXT, true)
	if g.net:
		_draw_icon("wifi", chip.position + Vector2(70, 11), 14, Color(1, 1, 1, 0.75), 1.6)
	if g.beta:
		var bc := Rect2(art.end.x - 70, art.position.y + 8, 62, 22)
		_panel(bc, Color(1.0, 0.72, 0.25, 0.22), 11, Color(1.0, 0.72, 0.25, 0.7), 1.0)
		_txt_c("آزمایشی", bc, 12, Color(1.0, 0.82, 0.45), true)
	var w: float = r.size.x - 28.0
	var nm: String = g.name
	_txt_r(nm, r.end.x - 14, art.end.y + 30, _fit_size(nm, w, 19, true), TEXT, true, w)
	_txt_r(str(g.short), r.end.x - 14, art.end.y + 52, 13, TEXT_DIM, false, w)

# ---------------- GAME ART (mini illustrations) ----------------
func _art_xf(c: Vector2, o: Vector2, s: float, ang: float = 0.0) -> void:
	draw_set_transform(c + o * s, ang, Vector2(s, s))

func _art_end() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_game_art(id: String, rect: Rect2, col: Color) -> void:
	var c: Vector2 = rect.get_center()
	var s: float = minf(rect.size.x / 228.0, rect.size.y / 98.0)
	match id:
		"othello", "othello12":
			var n: int = 5 if id == "othello" else 8
			var rows: int = 3 if id == "othello" else 4
			var cs: float = 24.0 if id == "othello" else 15.0
			_art_xf(c, Vector2.ZERO, s)
			var ox: float = -cs * n * 0.5
			var oy: float = -cs * rows * 0.5
			for yy in rows:
				for xx in n:
					var rr := Rect2(ox + xx * cs, oy + yy * cs, cs - 1.5, cs - 1.5)
					draw_rect(rr, Color(0.14, 0.50, 0.32))
					var v: int = (xx * 3 + yy * 5 + xx * yy) % 4
					if v == 0 or v == 1:
						var cc: Vector2 = rr.get_center()
						_draw_disc(cc, cs * 0.38, v == 1)
			_art_end()
		"pentago":
			_art_xf(c, Vector2.ZERO, s)
			for q in 4:
				var qx: float = -40.0 + (q % 2) * 42.0
				var qy: float = -40.0 + int(q / 2) * 42.0
				_panel(Rect2(qx, qy, 38, 38), Color(0.40, 0.28, 0.16), 6, Color(0.7, 0.5, 0.25, 0.6), 1.0)
				_draw_disc(Vector2(qx + 11, qy + 11), 6.5, false)
				_draw_disc(Vector2(qx + 27, qy + 27), 6.5, true)
			draw_arc(Vector2.ZERO, 54, deg_to_rad(-60), deg_to_rad(40), 14, col.lightened(0.3), 3.0, true)
			draw_colored_polygon(PackedVector2Array([Vector2(54 * cos(deg_to_rad(40)) + 5, 54 * sin(deg_to_rad(40)) - 6), Vector2(54 * cos(deg_to_rad(40)) + 5, 54 * sin(deg_to_rad(40)) + 9), Vector2(54 * cos(deg_to_rad(40)) - 9, 54 * sin(deg_to_rad(40)) + 2)]), col.lightened(0.3))
			_art_end()
		"quoridor":
			_art_xf(c, Vector2.ZERO, s)
			for yy in 3:
				for xx in 5:
					_panel(Rect2(-60 + xx * 25, -36 + yy * 25, 21, 21), Color(1, 1, 1, 0.12), 5)
			_panel(Rect2(-37, -17, 46, 6), Color(1.0, 0.78, 0.35), 3)
			_panel(Rect2(15, 8, 6, 22), Color(1.0, 0.78, 0.35), 3)
			_draw_disc(Vector2(-47.5, 36 - 14), 8, true)
			draw_circle(Vector2(27.5, -25.5), 8.5, Color(1.0, 0.45, 0.5))
			_art_end()
		"chess":
			_art_xf(c, Vector2.ZERO, s)
			for yy in 4:
				for xx in 8:
					var lt: bool = (xx + yy) % 2 == 0
					draw_rect(Rect2(-96 + xx * 24, -48 + yy * 24, 24, 24), Color(1, 1, 1, 0.10) if lt else Color(1, 1, 1, 0.03))
			_draw_chess_piece(2, true, Vector2(-26, 3), 78)
			_draw_chess_piece(6, false, Vector2(34, 3), 78)
			_art_end()
		"domino":
			_art_xf(c, Vector2(-30, 4), s, deg_to_rad(-14))
			_draw_dom_tile(Rect2(-22, -34, 44, 68), 6, 4, false, false, false)
			_art_xf(c, Vector2(32, 0), s, deg_to_rad(12))
			_draw_dom_tile(Rect2(-22, -34, 44, 68), 3, 5, false, false, false)
			_art_end()
		"pasoor":
			var ang := [-0.30, 0.0, 0.30]
			var cards := [{"r": 11, "s": 3}, {"r": 7, "s": 0}, {"r": 1, "s": 1}]
			for i in 3:
				_art_xf(c, Vector2((i - 1) * 40, 8 - abs(i - 1) * 4), s, ang[i])
				_draw_card(Rect2(-24, -38, 48, 70), cards[i], false, false, false)
			_art_end()
		"hokm":
			var cs2 := [{"r": 13, "s": 0}, {"r": 12, "s": 1}]
			for i in 2:
				_art_xf(c, Vector2(-26 + i * 52, 10), s, -0.2 + i * 0.4)
				_draw_card(Rect2(-24, -38, 48, 70), cs2[i], false, false, false)
			_art_xf(c, Vector2(0, -30), s)
			_draw_icon("crown", Vector2.ZERO, 26, Color(1.0, 0.82, 0.3))
			_art_end()
		"backgammon":
			_art_xf(c, Vector2.ZERO, s)
			for i in 8:
				var x0: float = -92.0 + i * 23.0
				var tcol := Color(0.85, 0.62, 0.35) if i % 2 == 0 else Color(0.35, 0.22, 0.14)
				draw_colored_polygon(PackedVector2Array([Vector2(x0, 44), Vector2(x0 + 21, 44), Vector2(x0 + 10.5, -20)]), tcol)
			_draw_disc(Vector2(-81.5, 34), 9, true)
			_draw_disc(Vector2(-81.5, 15), 9, true)
			_draw_disc(Vector2(57, 34), 9, false)
			_draw_dice_face(Rect2(-14, -42, 30, 30), 5)
			_draw_dice_face(Rect2(24, -34, 30, 30), 2)
			_art_end()
		"gobblet":
			_art_xf(c, Vector2.ZERO, s)
			var cols := [Color(1.0, 0.45, 0.35), Color(0.35, 0.58, 1.0), Color(1.0, 0.78, 0.30)]
			for i in 3:
				var cx: float = (i - 1) * 62.0
				for j in 3:
					var rad: float = 34.0 - j * 11.0
					draw_circle(Vector2(cx, 4), rad, cols[(i + j) % 3].darkened(0.1 + j * 0.0))
					draw_circle(Vector2(cx, 4), rad - 3.5, cols[(i + j) % 3].lightened(0.1 * j))
			_art_end()
		"mastermind":
			_art_xf(c, Vector2.ZERO, s)
			for i in 4:
				var mc: Color = MM_COLORS[(i * 2 + 1) % 6]
				draw_circle(Vector2(-60 + i * 36, -10), 14, mc.darkened(0.25))
				draw_circle(Vector2(-60 + i * 36, -11), 12, mc)
			for i in 4:
				draw_circle(Vector2(-32 + (i % 2) * 14 + 40, 22 + int(i / 2) * 14 - 4), 5, Color(1, 1, 1) if i < 2 else Color(0.1, 0.1, 0.14))
			_art_end()
		"abalone":
			_art_xf(c, Vector2.ZERO, s)
			var pts: Array = [Vector2.ZERO]
			for i in 6:
				pts.append(Vector2(cos(i * PI / 3.0), sin(i * PI / 3.0)) * 30.0)
			for i in pts.size():
				_draw_disc(pts[i], 13, i % 2 == 0)
			_art_end()
		"blockace":
			_art_xf(c, Vector2.ZERO, s)
			var shapes: Array = [
				[[0, 0], [1, 0], [2, 0], [2, 1]],
				[[0, 0], [1, 0], [0, 1], [1, 1]],
				[[0, 0], [1, 0], [2, 0], [1, 1]],
			]
			var scol := [Color(0.30, 0.82, 0.76), Color(1.0, 0.62, 0.35), Color(0.62, 0.50, 1.0)]
			var offs := [Vector2(-82, -26), Vector2(-14, -26), Vector2(30, 6)]
			for si in 3:
				for cell in shapes[si]:
					var cp := Rect2(offs[si] + Vector2(cell[0], cell[1]) * 21.0, Vector2(19, 19))
					_panel(cp, scol[si], 4)
					_gloss(cp, 4, 0.18)
			_art_end()
		_:
			_draw_icon("gamepad", c, 40, col)
	_art_end()

# ---------------- MODE ----------------
func _open_rules() -> void:
	rules_open = true
	_ov_t = 0.0
	_rebuild_buttons()

func _btns_mode() -> void:
	var info: Dictionary = _game_info(selected_game)
	var web_build: bool = OS.has_feature("web")
	# Godot Web does not support low-level ENet/UDP networking in browsers.
	var net: bool = info.get("net", false) and not web_build
	var option_y: float = 346.0
	var difficulty_labels: Array[String] = ["خیلی آسان", "آسان", "متوسط", "سخت", "استاد", "استادتمام"]
	_back_btn()
	_add_btn(Rect2(16, 16, 44, 44), "", _open_rules, true, TEXT, "icon", "help", "help")
	if selected_game == "quoridor":
		var qmod = _game_modules["quoridor"]
		for i in range(6):
			var active: bool = int(qmod.quo_difficulty) == i + 1
			var color: Color = GREEN if active else ACCENT
			_add_btn(Rect2(8 + i * 84, 345, 80, 40), difficulty_labels[i], _set_quoridor_difficulty.bind(i + 1), true, color, "seg_on" if active else "ghost", "", "quo_difficulty_%d" % (i + 1))
		option_y = 398.0
	elif selected_game in ["othello", "othello12"]:
		for i in range(6):
			var active: bool = oth_difficulty == i + 1
			var color: Color = GREEN if active else ACCENT
			_add_btn(Rect2(8 + i * 84, 345, 80, 40), difficulty_labels[i], _set_othello_difficulty.bind(i + 1), true, color, "seg_on" if active else "ghost", "", "oth_difficulty_%d" % (i + 1))
		option_y = 398.0
	elif selected_game == "chess":
		for i in range(6):
			var active: bool = chess_difficulty == i + 1
			var color: Color = GREEN if active else ACCENT
			_add_btn(Rect2(8 + i * 84, 345, 80, 40), difficulty_labels[i], _set_chess_difficulty.bind(i + 1), true, color, "seg_on" if active else "ghost", "", "chess_difficulty_%d" % (i + 1))
		option_y = 398.0
	elif selected_game == "backgammon":
		for i in range(6):
			var active: bool = bg_difficulty == i + 1
			var color: Color = GREEN if active else ACCENT
			_add_btn(Rect2(8 + i * 84, 345, 80, 40), difficulty_labels[i], _set_backgammon_difficulty.bind(i + 1), true, color, "seg_on" if active else "ghost", "", "backgammon_difficulty_%d" % (i + 1))
		option_y = 398.0
	_add_btn(Rect2(24, option_y, 492, 84), "بازی با کامپیوتر", _start_vs_cpu, true, GREEN, "option", "cpu", "m_cpu", "تک‌نفره · بدون نیاز به اینترنت")
	_add_btn(Rect2(24, option_y + 98, 492, 84), "میزبانی روی وای‌فای", _start_host, net, BLUE, "option", "wifi", "m_host", "شما میزبان باشید، دوستتان با IP وصل می‌شود")
	_add_btn(Rect2(24, option_y + 196, 492, 84), "اتصال با IP", _go_ip_entry, net, ACCENT, "option", "keypad", "m_join", "به بازی میزبانِ دیگر بپیوندید")
	_add_btn(Rect2(24, option_y + 294, 492, 84), "بازی آنلاین", _open_online_for_game, net, PINK, "option", "globe", "m_online", "ساخت اتاق و دعوت دوست")
	if web_build:
		for i in range(buttons.size() - 3, buttons.size()):
			buttons[i].hint = "اتصال شبکه‌ای ENet در نسخه وب پشتیبانی نمی‌شود؛ بازی با کامپیوتر قابل اجراست."
	elif not net:
		for i in range(buttons.size() - 3, buttons.size()):
			buttons[i].hint = "این بازی فعلاً فقط با کامپیوتر قابل بازی است."
	if selected_game == "quoridor":
		_add_btn(Rect2(24, option_y + 392, 492, 76), "بازی ۴ نفره روی یک دستگاه", _start_quoridor_local_four_player, true, ACCENT, "option", "users", "m_quoridor_local4", "چهار بازیکن · نوبتی روی یک صفحه")

func _set_quoridor_difficulty(level: int) -> void:
	_game_modules["quoridor"].quo_difficulty = clampi(level, 1, 6)
	_rebuild_buttons()

func _set_othello_difficulty(level: int) -> void:
	_game_modules["othello"].oth_difficulty = clampi(level, 1, 6)
	_rebuild_buttons()

func _set_chess_difficulty(level: int) -> void:
	_game_modules["chess"].chess_difficulty = clampi(level, 1, 6)
	_rebuild_buttons()

func _set_backgammon_difficulty(level: int) -> void:
	_game_modules["backgammon"].bg_difficulty = clampi(level, 1, 6)
	_rebuild_buttons()

func _draw_mode() -> void:
	var info: Dictionary = _game_info(selected_game)
	var col: Color = info.get("icon_col", ACCENT)
	_draw_bar_top(76.0)
	var hero := Rect2(24, 92, 492, 226)
	_panel(hero, CARD, 24, Color(col.r, col.g, col.b, 0.4), 1.5, 16, 6)
	var art := Rect2(hero.position + Vector2(14, 14), Vector2(200, 198))
	_panel(art, Color(col.r * 0.30 + 0.035, col.g * 0.30 + 0.045, col.b * 0.30 + 0.09, 1.0), 18)
	_draw_game_art(selected_game, Rect2(art.position + Vector2(0, 40), Vector2(art.size.x, 118)), col)
	_gloss(art, 18, 0.05)
	var rx: float = hero.end.x - 20
	var nm: String = str(info.get("name", ""))
	_txt_r(nm, rx, hero.position.y + 56, _fit_size(nm, 250, 30, true), TEXT, true, 260)
	_wrap(str(info.get("desc", "")), hero.position.x + 230, hero.position.y + 88, 240, 15, TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	var chip_y: float = hero.position.y + 150
	var cx: float = rx
	var chips: Array = [str(info.get("players", "2 نفره"))]
	if OS.has_feature("web"):
		chips.append("نسخه وب · بازی محلی")
	elif info.get("net", false):
		chips.append("چندنفره شبکه‌ای")
	else:
		chips.append("فقط آفلاین")
	if info.get("beta", false):
		chips.append("آزمایشی")
	for t in chips:
		var w: float = _txt_w(t, 13, true) + 26.0
		cx -= w
		var cc: Color = Color(1.0, 0.72, 0.25) if t == "آزمایشی" else col
		_panel(Rect2(cx, chip_y, w, 28), Color(cc.r, cc.g, cc.b, 0.16), 14, Color(cc.r, cc.g, cc.b, 0.6), 1.0)
		_txt_c(t, Rect2(cx, chip_y, w, 28), 13, cc.lightened(0.3), true)
		cx -= 8.0
	if selected_game == "quoridor":
		_txt_r("سطح هوش کامپیوتر را انتخاب کنید", VIEW_W - 28, 333, 13, TEXT_DIM, true, 310)
		_txt_r("روش بازی", VIEW_W - 28, 389, 13, TEXT_DIM, true, 180)
	elif selected_game in ["othello", "othello12"]:
		_txt_r("سطح هوش کامپیوتر را انتخاب کنید", VIEW_W - 28, 333, 13, TEXT_DIM, true, 310)
		_txt_r("روش بازی", VIEW_W - 28, 389, 13, TEXT_DIM, true, 180)
	else:
		_txt_r("روش بازی را انتخاب کنید", VIEW_W - 28, 336, 15, TEXT_DIM, true, 300)
	_txt_c(nm, Rect2(70, 10, VIEW_W - 140, 40), 22, TEXT, true)
	_txt_c("حالت بازی را انتخاب کنید", Rect2(40, 46, VIEW_W - 80, 24), 13, TEXT_DIM)

# ---------------- ONLINE ----------------
func _open_online_for_game() -> void:
	if NET_GAMES.has(selected_game):
		online_game = selected_game
	_open_online()

func _create_online_room() -> void:
	_set_game(online_game)
	_origin_online = true
	online_room_code = str(100000 + randi() % 900000)
	_start_host()
	if state == State.LOBBY:
		_show_toast("اتاق ساخته شد. IP یا کد اتاق را به دوستتان بدهید.")

func _join_online_room_ui() -> void:
	_set_game(online_game)
	_origin_online = true
	_go_ip_entry()

func _quick_match_search() -> void:
	_show_toast("جستجوی سریع به سرور آنلاین نیاز دارد و هنوز فعال نیست.")

func _pick_online_game(id: String) -> void:
	online_game = id
	_rebuild_buttons()

func _online_extra() -> float:
	var rows: int = int(ceil(float(NET_GAMES.size()) / 3.0))
	var end_y: float = 156.0 + (rows - 1) * 44.0 + 38.0
	return maxf(0.0, end_y - 254.0)

func _btns_online() -> void:
	var web_build: bool = OS.has_feature("web")
	_scroll_top = 76.0
	_scroll_bottom = 868.0
	_content_h = 0.0
	var i: int = 0
	for id in NET_GAMES:
		var col: int = i % 3
		var row: int = int(i / 3)
		var w: float = 156.0
		var x: float = VIEW_W - 16.0 - w - col * (w + 10.0)
		var y: float = 156.0 + row * 44.0
		var nm: String = str(_game_info(id).name)
		_add_btn(Rect2(x, y, w, 38), nm, _pick_online_game.bind(id), true, _game_info(id).icon_col, "seg_on" if id == online_game else "ghost", "", "og_" + id)
		i += 1
	var ex: float = _online_extra()
	_add_btn(Rect2(24, 292 + ex, 492, 84), "ساخت اتاق", _create_online_room, not web_build, GREEN, "option", "plus", "o_create", "کد اتاق ۶ رقمی می‌گیرید و میزبان می‌شوید")
	if web_build:
		_last_btn().hint = "نسخه وب هنوز از ENet/UDP پشتیبانی نمی‌کند."
	_add_btn(Rect2(24, 390 + ex, 492, 84), "ورود با IP میزبان", _join_online_room_ui, not web_build, BLUE, "option", "keypad", "o_join", "IP را با صفحه‌کلید وارد کنید")
	if web_build:
		_last_btn().hint = "برای بازی شبکه‌ای نسخه وب باید به WebSocket یا WebRTC منتقل شود."
	_add_btn(Rect2(24, 488 + ex, 492, 84), "جستجوی سریع هم‌بازی", _quick_match_search, false, PINK, "option", "globe", "o_quick", "به‌زودی · نیازمند سرور آنلاین")
	_last_btn().hint = "جستجوی سریع به سرور آنلاین نیاز دارد و هنوز فعال نیست."
	_btns_nav()

func _draw_online() -> void:
	_draw_topbar("بازی آنلاین", "اتاق بسازید یا به دوستتان بپیوندید")
	_txt_r("۱. بازی را انتخاب کنید", VIEW_W - 24, 138, 15, TEXT_DIM, true, 300)
	var ex: float = _online_extra()
	_txt_r("۲. روش اتصال", VIEW_W - 24, 280 + ex, 15, TEXT_DIM, true, 300)
	var note := Rect2(24, 592 + ex, 492, 120)
	_panel(note, Color(0.38, 0.62, 1.0, 0.10), 18, Color(0.38, 0.62, 1.0, 0.35), 1.0)
	_draw_icon("info", Vector2(note.end.x - 28, note.position.y + 30), 22, BLUE, 2.0)
	if OS.has_feature("web"):
		_wrap("مرورگرها از اتصال سطح پایین ENet/UDP پشتیبانی نمی‌کنند؛ ساخت اتاق و اتصال با IP در نسخه وب غیرفعال است.", note.position.x + 18, note.position.y + 34, note.size.x - 76, 14, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		_wrap("بازی با کامپیوتر و بازی محلی تک‌دستگاه در دسترس است. برای چندنفره وب باید WebSocket/WebRTC و سرور سازگار پیاده‌سازی شود.", note.position.x + 18, note.position.y + 80, note.size.x - 36, 13, TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	else:
		_wrap("اتصال فعلی روی همان وای‌فای (یا با IP عمومی و پورت‌فوروارد) کار می‌کند.", note.position.x + 18, note.position.y + 34, note.size.x - 76, 14, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		_wrap("بازی با هم‌بازی تصادفی در اینترنت به یک سرور میانی نیاز دارد که هنوز اضافه نشده است.", note.position.x + 18, note.position.y + 80, note.size.x - 36, 13, TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	_draw_bottom_nav()

# ---------------- LOBBY ----------------
func _btns_lobby() -> void:
	_back_btn()
	_add_btn(Rect2(16, 16, 44, 44), "", _open_rules, true, TEXT, "icon", "help", "help")
	if is_host:
		var can_start: bool = connected_players >= 2
		_add_btn(Rect2(40, 706, VIEW_W - 80, 62), "شروع بازی", _start_network_game, can_start, GREEN, "solid", "play", "start")
		_last_btn().hint = "برای شروع، باید بازیکن دوم وصل شود."
		var ips: Array = host_ips
		for j in ips.size():
			var y: float = 250.0 + 82.0 + j * 42.0
			_add_btn(Rect2(30, y - 2, 40, 36), "", _copy_ip.bind(str(ips[j])), true, ACCENT, "icon", "copy", "copy_%d" % j)
	_add_btn(Rect2(40, 782, VIEW_W - 80, 54), "ترک لابی", _request_leave_lobby, true, RED, "soft", "door", "leave")

func _copy_ip(ip: String) -> void:
	DisplayServer.clipboard_set(ip)
	_show_toast("IP کپی شد: " + ip)

func _draw_seat(r: Rect2, seat: int, present: bool, me: bool, col: Color) -> void:
	var live: bool = present
	_panel(r, CARD, 20, Color(col.r, col.g, col.b, 0.7 if live else 0.2), 1.5 if live else 1.0, 12, 5)
	var ac := Vector2(r.end.x - 42, r.position.y + 46)
	if live:
		draw_circle(ac, 28, Color(col.r, col.g, col.b, 0.25))
		draw_circle(ac, 22, col)
		_draw_icon("user", ac, 22, _lum_text(col), 2.0)
	else:
		draw_circle(ac, 26, Color(1, 1, 1, 0.05))
		for k in 3:
			var ph: float = fmod(_time * 1.6 + k * 0.33, 1.0)
			draw_circle(ac + Vector2((k - 1) * 12, 0), 3.0 + 2.0 * sin(ph * PI), Color(1, 1, 1, 0.25 + 0.35 * sin(ph * PI)))
	var title: String = "بازیکن " + _fa(seat + 1)
	_txt_r(title, r.end.x - 82, r.position.y + 40, 17, TEXT if live else TEXT_DIM, true, 140)
	var sub: String = "متصل" if live else "در انتظار…"
	_txt_r(sub, r.end.x - 82, r.position.y + 64, 13, GREEN if live else TEXT_FAINT, false, 140)
	if me:
		var tag := Rect2(r.position.x + 12, r.position.y + 12, 46, 22)
		_panel(tag, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.2), 11, ACCENT, 1.0)
		_txt_c("شما", tag, 12, ACCENT, true)
	var role: String = "میزبان" if seat == 0 else "مهمان"
	_txt_c(role, Rect2(r.position.x, r.end.y - 30, r.size.x, 24), 12, TEXT_DIM)

func _draw_lobby() -> void:
	var info: Dictionary = _game_info(selected_game)
	var col: Color = info.get("icon_col", ACCENT)
	_draw_topbar("لابی بازی", str(info.get("name", "")))
	var seat0_present: bool = true
	var seat1_present: bool = connected_players >= 2 if is_host else _client_connected
	_draw_seat(Rect2(VIEW_W - 16 - 238, 100, 238, 124), 0, seat0_present if is_host else _client_connected, local_seat == 0, BLUE)
	_draw_seat(Rect2(16, 100, 238, 124), 1, seat1_present, local_seat == 1, ACCENT)
	if is_host:
		var ips: Array = host_ips
		var card := Rect2(16, 250, VIEW_W - 32, 112 + maxi(ips.size(), 1) * 42)
		_panel(card, CARD, 20, LINE_STRONG, 1.0, 12, 5)
		_txt_r("آدرس شما برای دوست", card.end.x - 18, card.position.y + 34, 15, TEXT_DIM, true, 300)
		if online_room_code != "":
			var cr := Rect2(card.position.x + 16, card.position.y + 14, 130, 32)
			_panel(cr, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.14), 16, ACCENT, 1.0)
			_txt_c("کد " + _fa(online_room_code), cr, 14, ACCENT, true)
		if ips.size() > 0:
			for j in ips.size():
				var y: float = card.position.y + 82.0 + j * 42.0
				_txt_r(str(ips[j]), card.end.x - 18, y + 24, 26, ACCENT, true, 300)
		else:
			_txt_r("IP پیدا نشد — از تنظیمات وای‌فای ببینید", card.end.x - 18, card.position.y + 92, 14, TEXT_DIM, false, 400)
		_txt_r("پورت: " + _fa(PORT), card.end.x - 18, card.end.y - 16, 13, TEXT_DIM, false, 200)
		var need: int = max_players_for_game - connected_players
		var msg: String = "منتظر بازیکن دوم…" if need > 0 else "همه آماده‌اند — بازی را شروع کنید"
		_txt_c(msg, Rect2(0, 650, VIEW_W, 36), 17, TEXT_DIM if need > 0 else GREEN, true)
	else:
		var card2 := Rect2(16, 250, VIEW_W - 32, 190)
		_panel(card2, CARD, 20, LINE_STRONG, 1.0, 12, 5)
		var cc := Vector2(VIEW_W * 0.5, card2.position.y + 66)
		if not _client_connected:
			draw_arc(cc, 26, _time * 4.0, _time * 4.0 + PI * 1.4, 24, ACCENT, 4.0, true)
			_txt_c("در حال اتصال به " + join_ip + " …", Rect2(card2.position.x, card2.position.y + 108, card2.size.x, 28), 17, TEXT, true)
			_txt_c("هر دو گوشی باید روی یک وای‌فای باشند", Rect2(card2.position.x, card2.position.y + 140, card2.size.x, 24), 13, TEXT_DIM)
		else:
			draw_circle(cc, 28, Color(GREEN.r, GREEN.g, GREEN.b, 0.2))
			_draw_icon("check", cc, 30, GREEN, 3.4)
			_txt_c("متصل شدید", Rect2(card2.position.x, card2.position.y + 108, card2.size.x, 28), 18, GREEN, true)
			_txt_c("منتظر شروع بازی توسط میزبان" + ".".repeat(1 + int(_time * 2.0) % 3), Rect2(card2.position.x, card2.position.y + 140, card2.size.x, 24), 14, TEXT_DIM)

# ---------------- IP ENTRY ----------------
func _valid_ip(s: String) -> bool:
	var parts: PackedStringArray = s.strip_edges().split(".")
	if parts.size() != 4:
		return false
	for p in parts:
		if p.length() == 0 or p.length() > 3 or not p.is_valid_int():
			return false
		if int(p) > 255:
			return false
	return true

func _ip_paste() -> void:
	var t: String = DisplayServer.clipboard_get().strip_edges()
	if _valid_ip(t):
		join_ip = t
		_rebuild_buttons()
	else:
		_show_toast("در کلیپ‌بورد IP معتبر پیدا نشد.")

func _ip_clear() -> void:
	join_ip = ""
	_rebuild_buttons()

func _btns_ip() -> void:
	_back_btn()
	_add_btn(Rect2(16, 16, 44, 44), "", _open_rules, true, TEXT, "icon", "help", "help")
	var keys: Array = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"]
	for i in keys.size():
		var cx: int = i % 3
		var ry: int = int(i / 3)
		var r := Rect2(48 + cx * 152, 236 + ry * 76, 140, 64)
		var k: String = keys[i]
		if k == "⌫":
			_add_btn(r, "", _ip_key.bind(k), true, RED.lightened(0.2), "key", "backspace", "k_back")
		else:
			_add_btn(r, k, _ip_key.bind(k), true, TEXT, "key", "", "k_" + k)
	var ok: bool = _valid_ip(join_ip)
	_add_btn(Rect2(40, 556, VIEW_W - 80, 62), "اتصال", _do_join, ok, GREEN, "solid", "check", "join")
	_last_btn().hint = "IP کامل را وارد کنید (مثل 192.168.1.5)"
	_add_btn(Rect2(40, 634, 232, 50), "چسباندن", _ip_paste, true, TEXT_DIM, "ghost", "copy", "paste")
	_add_btn(Rect2(VIEW_W - 40 - 232, 634, 232, 50), "پاک کردن", _ip_clear, join_ip.length() > 0, TEXT_DIM, "ghost", "close", "clear")

func _draw_ip_entry() -> void:
	_draw_topbar("اتصال به دوست", "IP میزبان را وارد کنید")
	var f := Rect2(40, 96, VIEW_W - 80, 84)
	var ok: bool = _valid_ip(join_ip)
	_panel(f, CARD, 20, GREEN if ok else (ACCENT if join_ip != "" else LINE_STRONG), 1.5, 12, 5)
	var shown: String = join_ip if join_ip != "" else "192.168.1.5"
	var caret: String = "|" if (int(_time * 2.0) % 2 == 0 and join_ip.length() < 15) else " "
	var tc: Color = TEXT if join_ip != "" else TEXT_FAINT
	draw_string(font_bold, Vector2(f.position.x, f.position.y + 56), shown + (caret if join_ip != "" else ""), HORIZONTAL_ALIGNMENT_CENTER, f.size.x, 34, tc)
	if ok:
		_draw_icon("check", Vector2(f.position.x + 30, f.get_center().y), 22, GREEN, 3.0)
	_txt_c("هر دو گوشی باید به یک وای‌فای وصل باشند", Rect2(0, 190, VIEW_W, 28), 14, TEXT_DIM)

# ---------------- PLAYING (frame + buttons) ----------------
func _btns_playing() -> void:
	_back_btn()
	_add_btn(Rect2(16, 16, 44, 44), "", _open_rules, true, TEXT, "icon", "help", "help")
	_add_btn(Rect2(20, 892, 150, 52), "خروج", _confirm_exit_game, true, TEXT_DIM, "ghost", "door", "dock_exit")
	_add_btn(Rect2(VIEW_W - 170, 892, 150, 52), "تسلیم", _confirm_resign, true, RED, "soft", "flag", "dock_resign")
	_btns_game()

func _btns_game() -> void:
	match selected_game:
		"pentago": _btns_pentago()
		"quoridor": _btns_quoridor()
		"domino": _btns_domino()
		"pasoor": _btns_pasoor()
		"mastermind": _btns_mastermind()
		"gobblet": _btns_gobblet()
		"backgammon": _btns_backgammon()
		"blockace": _btns_blockace()

func _seat_me(seat: int) -> bool:
	if vs_cpu:
		return seat == 0
	return seat == local_seat

func _pl(name: String, col: Color, score: String, active: bool, me: bool, sub: String = "", light: int = -1) -> Dictionary:
	return {"name": name, "col": col, "score": score, "active": active, "me": me, "sub": sub, "light": light}

func _draw_pill(r: Rect2, p: Dictionary) -> void:
	var active: bool = p.active
	var col: Color = p.col
	var edge: Color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.95) if active else LINE
	if active:
		var k: float = 0.5 + 0.5 * sin(_time * 4.0)
		_panel(r.grow(2.0 + k * 1.5), Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.07 + 0.05 * k), 24)
	_panel(r, Color(0.14, 0.17, 0.32) if active else CARD, 20, edge, 1.5 if active else 1.0, 8, 3)
	var ac := Vector2(r.end.x - 30, r.get_center().y)
	if int(p.light) >= 0:
		_draw_disc(ac, 15, int(p.light) == 1)
	else:
		draw_circle(ac, 15, Color(col.r * 0.4, col.g * 0.4, col.b * 0.4))
		draw_circle(ac, 12, col)
	var nm: String = str(p.name)
	_txt_r(nm, r.end.x - 54, r.position.y + 25, _fit_size(nm, 96, 15, true), TEXT, true, 100)
	var sub: String = str(p.sub)
	if sub == "" and active:
		sub = "نوبت شما" if p.me else "نوبت حریف"
	var sc: Color = ACCENT if active else TEXT_DIM
	if sub != "":
		_txt_r(sub, r.end.x - 54, r.position.y + 46, 12, sc, false, 110)
	_txt_c(str(p.score), Rect2(r.position.x + 4, r.position.y, 62, r.size.y), 24, TEXT if active else TEXT_DIM, true)

func _draw_hud(title: String, a: Dictionary, b: Dictionary = {}) -> void:
	_draw_bar_top(72.0)
	_txt_c(title, Rect2(70, 12, VIEW_W - 140, 48), 23, TEXT, true)
	var ry: float = 84.0
	if b.is_empty():
		_draw_pill(Rect2(16, ry, VIEW_W - 32, 58), a)
		return
	_draw_pill(Rect2(VIEW_W - 16 - 224, ry, 224, 58), a)
	_draw_pill(Rect2(16, ry, 224, 58), b)
	var mid := Vector2(VIEW_W * 0.5, ry + 29)
	_txt_c("VS", Rect2(mid.x - 24, mid.y - 12, 48, 24), 13, TEXT_FAINT, true)
	var pulse: float = 0.6 + 0.4 * sin(_time * 5.0)
	if a.active:
		draw_colored_polygon(PackedVector2Array([mid + Vector2(10, 22), mid + Vector2(10, 34), mid + Vector2(24, 28)]), Color(ACCENT.r, ACCENT.g, ACCENT.b, pulse))
	elif b.active:
		draw_colored_polygon(PackedVector2Array([mid + Vector2(-10, 22), mid + Vector2(-10, 34), mid + Vector2(-24, 28)]), Color(ACCENT.r, ACCENT.g, ACCENT.b, pulse))

func _hint(text: String, y: float, col: Color = TEXT_DIM) -> void:
	var w: float = minf(_txt_w(text, 14) + 36.0, VIEW_W - 32.0)
	var r := Rect2((VIEW_W - w) * 0.5, y, w, 32)
	_panel(r, Color(0, 0, 0, 0.30), 16)
	_txt_c(text, r, 14, col)

func _draw_playing() -> void:
	match selected_game:
		"othello", "othello12": _draw_othello()
		"pentago": _draw_pentago()
		"quoridor": _draw_quoridor()
		"domino": _draw_domino()
		"chess": _draw_chess()
		"pasoor": _draw_pasoor()
		"mastermind": _draw_mastermind()
		"gobblet": _draw_gobblet()
		"hokm": _draw_hokm()
		"backgammon": _draw_backgammon()
		"abalone": _draw_abalone()
		"blockace": _draw_blockace()
		_:
			_draw_topbar("به زودی", "این بازی در نسخه‌های بعدی اضافه می‌شود")

# ---------------- RESULT ----------------
func _result_info() -> Dictionary:
	var won: bool = _player_won_current()
	var rows: Array = []
	var title: String = "مساوی شد!" if _result_draw else ("شما برنده شدید!" if won else "حریف برنده شد")
	if selected_game == "quoridor" and bool(_game_modules["quoridor"].quo_local_multiplayer) and quo_winner >= 0:
		title = "بازیکن %s برنده شد!" % _fa(quo_winner + 1)
	var sub: String = ""
	match selected_game:
		"othello", "othello12":
			rows.append(["سیاه", _fa(othello_scores[1])])
			rows.append(["سفید", _fa(othello_scores[2])])
		"pentago":
			sub = "بازیکن سیاه برنده شد" if pent_winner == 1 else "بازیکن سفید برنده شد"
		"quoridor":
			sub = "بازیکن %s به ضلع مقابل رسید" % _fa(quo_winner + 1) if quo_winner >= 0 else "هیچ بازیکنی حرکت یا دیوار مجاز ندارد."
		"domino":
			rows.append(["مجموع نقطه‌های شما", _fa(dom_scores[0 if vs_cpu else local_seat])])
			rows.append(["مجموع نقطه‌های حریف", _fa(dom_scores[1 if vs_cpu else 1 - local_seat])])
		"chess":
			sub = "سفید برنده شد" if chess_winner == 1 else ("سیاه برنده شد" if chess_winner == 2 else "")
		"pasoor":
			var me: int = 0 if vs_cpu else local_seat
			rows.append(["امتیاز این دست", "%s - %s" % [_fa(pas_scores[me]), _fa(pas_scores[1 - me])]])
			rows.append(["امتیاز کل (هدف %s)" % _fa(PAS_TARGET), "%s - %s" % [_fa(pas_match_scores[me]), _fa(pas_match_scores[1 - me])]])
			rows.append(["سورها", "%s - %s" % [_fa(pas_surs[me]), _fa(pas_surs[1 - me])]])
			if not _pas_match_over():
				title = "این دست را بردید" if won else ("این دست مساوی شد" if _result_draw else "این دست را باختید")
				sub = "مسابقه تا رسیدن به %s امتیاز ادامه دارد" % _fa(PAS_TARGET)
		"hokm":
			rows.append(["دست‌های شما", _fa(hokm_scores[_my_seat()])])
			rows.append(["دست‌های حریف", _fa(hokm_scores[1 - _my_seat()])])
		"mastermind":
			if vs_cpu:
				title = "کد را شکستید!" if mm_won else "کد شکسته نشد"
			elif _result_draw:
				title = "کد شکسته نشد"
			sub = "تعداد تلاش: " + _fa(mm_guesses.size())
		"gobblet":
			sub = "۴ مهره هم‌رنگ در یک خط"
		"backgammon":
			rows.append(["خارج‌شده شما", _fa(bg_off[_my_seat()])])
			rows.append(["خارج‌شده حریف", _fa(bg_off[1 - _my_seat()])])
		"blockace":
			var c0: int = 0
			var c1: int = 0
			for row in blk_grid:
				for v in row:
					if v == 1:
						c0 += 1
					elif v == 2:
						c1 += 1
			rows.append(["خانه‌های شما", _fa(c1 if _my_seat() == 1 else c0)])
			rows.append(["خانه‌های حریف", _fa(c0 if _my_seat() == 1 else c1)])
	return {"title": title, "sub": sub, "rows": rows}

func _btns_result() -> void:
	var can_restart: bool = vs_cpu or is_host
	var label: String = "بازی دوباره"
	if selected_game == "pasoor" and not _pas_match_over():
		label = "دست بعدی"
	_add_btn(Rect2(40, 668, VIEW_W - 80, 62), label if can_restart else "منتظر میزبان…", _restart_current, can_restart, GREEN, "solid", "restart", "again")
	_last_btn().hint = "فقط میزبان می‌تواند بازی جدید را شروع کند."
	_add_btn(Rect2(VIEW_W - 40 - 242, 746, 242, 54), "تغییر حالت", _change_mode, true, BLUE, "soft", "swap", "mode")
	_add_btn(Rect2(40, 746, 242, 54), "منوی اصلی", _back_to_menu, true, ACCENT, "soft", "home", "home")
	_add_btn(Rect2(40, 816, VIEW_W - 80, 48), "مشاهده آمار", _open_dashboard, true, TEXT_DIM, "ghost", "chart", "stats")

func _change_mode() -> void:
	_cleanup_network()
	state = State.MODE
	_rebuild_buttons()

func _draw_result() -> void:
	var info: Dictionary = _result_info()
	var won: bool = _player_won_current()
	var tcol: Color = TEXT_DIM if _result_draw else (GREEN if won else RED)
	var t: float = _time - _result_t0
	# glow behind emblem
	_glow(Vector2(VIEW_W * 0.5, 190), 230, Color(tcol.r, tcol.g, tcol.b, 0.30))
	var pop: float = _ease_back(t / 0.5)
	var c := Vector2(VIEW_W * 0.5, 190)
	draw_circle(c, 78 * pop, Color(tcol.r * 0.28, tcol.g * 0.28, tcol.b * 0.28, 1.0))
	_ring(c, 78 * pop, tcol, 3.0)
	_ring(c, 92 * pop + 3.0 * sin(t * 3.0), Color(tcol.r, tcol.g, tcol.b, 0.30), 2.0)
	var icon: String = "swap" if _result_draw else ("trophy" if won else "flag")
	_draw_icon(icon, c, 76 * pop, tcol.lightened(0.2), 4.0)
	if won and not _result_draw:
		for i in 28:
			var seed_v: float = float(i) * 12.9898
			var px: float = fposmod(sin(seed_v) * 43758.5453, 1.0)
			var spd: float = 70.0 + fposmod(sin(seed_v * 1.7) * 9231.13, 1.0) * 110.0
			var py: float = fposmod(-40.0 + t * spd + fposmod(sin(seed_v * 2.3) * 1111.1, 1.0) * 300.0, 560.0) + 40.0
			if t * spd > 600.0:
				py = 2000.0
			var cc: Color = MM_COLORS[i % 6]
			var rot: float = t * (2.0 + px * 3.0) + i
			var cp := Vector2(24.0 + px * (VIEW_W - 48.0), py)
			draw_set_transform(cp, rot, Vector2.ONE)
			draw_rect(Rect2(-4, -2.5, 8, 5), Color(cc.r, cc.g, cc.b, clampf(1.0 - t / 4.0, 0.0, 1.0)))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_txt_c(str(info.title), Rect2(0, 296, VIEW_W, 52), 34, tcol.lightened(0.15), true)
	if str(info.sub) != "":
		_txt_c(str(info.sub), Rect2(24, 346, VIEW_W - 48, 30), 16, TEXT_DIM)
	var rows: Array = info.rows
	var y: float = 392.0
	if rows.size() > 0:
		var card := Rect2(40, y, VIEW_W - 80, 20 + rows.size() * 40)
		_panel(card, CARD, 20, LINE_STRONG, 1.0, 10, 4)
		for i in rows.size():
			var ry: float = card.position.y + 10 + i * 40
			_txt_r(str(rows[i][0]), card.end.x - 18, ry + 27, 16, TEXT_DIM, false, 260)
			_txt_c(str(rows[i][1]), Rect2(card.position.x + 12, ry, 180, 40), 20, TEXT, true)
			if i < rows.size() - 1:
				draw_rect(Rect2(card.position.x + 16, ry + 40, card.size.x - 32, 1), LINE)
		y = card.end.y + 14.0
	if selected_game == "mastermind":
		var sy: float = maxf(y, 440.0)
		_txt_c("کد مخفی", Rect2(0, sy, VIEW_W, 24), 14, TEXT_DIM)
		for i in 4:
			var mc: Color = MM_COLORS[mm_secret[i]]
			var sc := Vector2(VIEW_W * 0.5 + (1.5 - i) * 56.0, sy + 54)
			draw_circle(sc, 22, mc.darkened(0.3))
			draw_circle(sc + Vector2(0, -1), 19, mc)
			draw_circle(sc + Vector2(-6, -8), 5, Color(1, 1, 1, 0.35))
		y = sy + 96.0
	# delta chip
	var dtxt: String
	var dcol: Color
	if _result_draw or _result_delta == 0:
		dtxt = "بدون تغییر امتیاز"
		dcol = TEXT_DIM
	else:
		dtxt = (_fa(absi(_result_delta)) + " امتیاز اضافه شد") if _result_delta > 0 else (_fa(absi(_result_delta)) + " امتیاز کسر شد")
		dcol = GREEN if _result_delta > 0 else RED
	var cw: float = _txt_w(dtxt, 17, true) + 44.0
	var dy: float = minf(y + 6.0, 604.0)
	var cr := Rect2((VIEW_W - cw) * 0.5, dy, cw, 40)
	var dp: float = _ease_back((t - 0.4) / 0.4)
	if dp > 0.0:
		_panel(cr.grow_individual(-(1.0 - dp) * cw * 0.25, 0, -(1.0 - dp) * cw * 0.25, 0), Color(dcol.r, dcol.g, dcol.b, 0.16), 20, dcol, 1.5)
		_txt_c(dtxt, cr, 17, dcol, true)
		if _result_delta != 0:
			_txt_c("رتبه: " + _fa(scoring_service.global_rating), Rect2(0, cr.end.y + 4, VIEW_W, 22), 12, TEXT_DIM)

# ---------------- DASHBOARD ----------------
func _set_tab(i: int) -> void:
	dash_tab = i
	scroll_y = 0.0
	_rebuild_buttons()

func _btns_dashboard() -> void:
	_scroll_top = 312.0
	_scroll_bottom = 868.0
	_content_h = GAMES.size() * 66.0 + 16.0
	var tabs: Array = ["کلی", "هفتگی", "ماهانه"]
	for i in 3:
		var w: float = 156.0
		var x: float = VIEW_W - 16.0 - w - i * (w + 10.0)
		_add_btn(Rect2(x, 256, w, 42), tabs[i], _set_tab.bind(i), true, ACCENT, "seg_on" if i == dash_tab else "ghost", "", "tab_%d" % i)
	_btns_nav()

func _stat_pts(id: String) -> int:
	var st: Dictionary = scoring_service.game_stats.get(id, {})
	if dash_tab == 0:
		return int(st.get("points", 0))
	return _points_in_period(id, 7 if dash_tab == 1 else 30)

func _draw_dashboard() -> void:
	var maxabs: int = 1
	for g in GAMES:
		maxabs = maxi(maxabs, absi(_stat_pts(str(g.id))))
	for i in GAMES.size():
		var g: Dictionary = GAMES[i]
		var id: String = g.id
		var st: Dictionary = scoring_service.game_stats.get(id, {})
		var pts: int = _stat_pts(id)
		var r := Rect2(16, _scroll_top + 8.0 + i * 66.0 - scroll_y, VIEW_W - 32, 58)
		if r.end.y < _scroll_top - 4 or r.position.y > _scroll_bottom + 4:
			continue
		var col: Color = g.icon_col
		_panel(r, CARD, 16, LINE, 1.0)
		_panel(Rect2(r.end.x - 8, r.position.y + 12, 4, r.size.y - 24), col, 2)
		_txt_r(str(g.name), r.end.x - 20, r.position.y + 25, 16, TEXT, true, 190)
		var w: int = int(st.get("wins", 0))
		var l: int = int(st.get("losses", 0))
		_txt_r("%s برد · %s باخت" % [_fa(w), _fa(l)], r.end.x - 20, r.position.y + 46, 12, TEXT_DIM, false, 190)
		var bar := Rect2(r.position.x + 90, r.position.y + 36, 130, 8)
		_panel(bar, Color(1, 1, 1, 0.07), 4)
		var frac: float = clampf(float(absi(pts)) / float(maxabs), 0.0, 1.0)
		if frac > 0.0:
			_panel(Rect2(bar.position, Vector2(maxf(8.0, bar.size.x * frac), 8)), GREEN if pts >= 0 else RED, 4)
		var ps: String = ("+" if pts > 0 else ("−" if pts < 0 else "")) + _fa(absi(pts))
		_txt_c(ps, Rect2(r.position.x + 8, r.position.y + 6, 90, 26), 18, GREEN if pts > 0 else (RED if pts < 0 else TEXT_DIM), true)
	# header block
	draw_rect(Rect2(0, 0, VIEW_W, _scroll_top - 4), BAR)
	draw_rect(Rect2(0, _scroll_top - 5, VIEW_W, 1), LINE)
	_vgrad(Rect2(0, _scroll_top - 4, VIEW_W, 16), Color(BAR.r, BAR.g, BAR.b, 0.95), Color(BAR.r, BAR.g, BAR.b, 0.0))
	_txt_c("آمار و امتیازات", Rect2(70, 10, VIEW_W - 140, 40), 24, TEXT, true)
	var wl: Array = _total_wins_losses()
	var total: int = int(wl[0]) + int(wl[1])
	var rate: int = int(round(100.0 * float(wl[0]) / float(maxi(1, total)))) if total > 0 else 0
	var card := Rect2(16, 58, VIEW_W - 32, 184)
	var tier: Array = _tier_info()
	var tc: Color = tier[1]
	_panel(card, Color(0.15, 0.18, 0.34), 24, Color(tc.r, tc.g, tc.b, 0.5), 1.5, 12, 5)
	_glow(Vector2(card.end.x - 90, card.position.y + 60), 120, Color(tc.r, tc.g, tc.b, 0.25))
	_txt_r("رتبه کلی", card.end.x - 22, card.position.y + 34, 14, TEXT_DIM, true, 200)
	_txt_r(_fa(scoring_service.global_rating), card.end.x - 22, card.position.y + 90, 52, TEXT, true, 300)
	var tcw: float = _txt_w(tier[0], 14, true) + 30.0
	var tchip := Rect2(card.end.x - 22 - tcw, card.position.y + 102, tcw, 28)
	_panel(tchip, Color(tc.r, tc.g, tc.b, 0.18), 14, tc, 1.0)
	_txt_c(str(tier[0]), tchip, 14, tc.lightened(0.2), true)
	var cols3: Array = [["برد", _fa(wl[0]), GREEN], ["باخت", _fa(wl[1]), RED], ["درصد برد", _fa(rate) + "٪", ACCENT]]
	for i in 3:
		var cx: float = card.position.x + 20 + i * 100.0
		_panel(Rect2(cx, card.position.y + 134, 92, 40), Color(1, 1, 1, 0.05), 12)
		_txt_c(str(cols3[i][1]), Rect2(cx, card.position.y + 134, 92, 24), 17, cols3[i][2], true)
		_txt_c(str(cols3[i][0]), Rect2(cx, card.position.y + 154, 92, 18), 11, TEXT_DIM)
	_draw_bottom_nav()

# ---------------- RANKINGS ----------------
func _btns_rankings() -> void:
	_scroll_top = 262.0
	_scroll_bottom = 868.0
	_content_h = GAMES.size() * 66.0 + 16.0
	_btns_nav()

func _draw_rankings() -> void:
	var rows: Array = RankingServiceScript.build_game_rows(GAMES, scoring_service.game_stats)
	var medal: Array = [Color(1.0, 0.80, 0.30), Color(0.80, 0.86, 0.94), Color(0.85, 0.55, 0.30)]
	for i in rows.size():
		var row: Dictionary = rows[i]
		var r := Rect2(16, _scroll_top + 8.0 + i * 66.0 - scroll_y, VIEW_W - 32, 58)
		if r.end.y < _scroll_top - 4 or r.position.y > _scroll_bottom + 4:
			continue
		_panel(r, CARD, 16, medal[i] if (i < 3 and row.pts > 0) else LINE, 1.5 if (i < 3 and row.pts > 0) else 1.0)
		var bc := Vector2(r.end.x - 32, r.get_center().y)
		if i < 3 and row.pts > 0:
			draw_circle(bc, 18, medal[i])
			_txt_c(_fa(i + 1), Rect2(bc.x - 18, bc.y - 18, 36, 36), 17, Color(0.1, 0.1, 0.16), true)
		else:
			draw_circle(bc, 18, Color(1, 1, 1, 0.06))
			_txt_c(_fa(i + 1), Rect2(bc.x - 18, bc.y - 18, 36, 36), 15, TEXT_DIM, true)
		draw_circle(Vector2(r.end.x - 66, r.get_center().y), 5, row.col)
		_txt_r(str(row.name), r.end.x - 80, r.position.y + 26, 16, TEXT, true, 190)
		_txt_r("%s برد · %s باخت" % [_fa(row.w), _fa(row.l)], r.end.x - 80, r.position.y + 47, 12, TEXT_DIM, false, 190)
		var pv: int = row.pts
		_txt_c(("+" if pv > 0 else ("−" if pv < 0 else "")) + _fa(absi(pv)), Rect2(r.position.x + 8, r.position.y, 100, r.size.y), 20, GREEN if pv > 0 else (RED if pv < 0 else TEXT_DIM), true)
	draw_rect(Rect2(0, 0, VIEW_W, _scroll_top - 4), BAR)
	draw_rect(Rect2(0, _scroll_top - 5, VIEW_W, 1), LINE)
	_vgrad(Rect2(0, _scroll_top - 4, VIEW_W, 16), Color(BAR.r, BAR.g, BAR.b, 0.95), Color(BAR.r, BAR.g, BAR.b, 0.0))
	_txt_c("رتبه‌بندی", Rect2(70, 10, VIEW_W - 140, 40), 24, TEXT, true)
	var tier: Array = _tier_info()
	var tc: Color = tier[1]
	var card := Rect2(16, 62, VIEW_W - 32, 180)
	_panel(card, Color(0.15, 0.18, 0.34), 24, Color(tc.r, tc.g, tc.b, 0.55), 1.5, 12, 5)
	_glow(Vector2(card.end.x - 80, card.position.y + 70), 130, Color(tc.r, tc.g, tc.b, 0.28))
	var bc2 := Vector2(card.end.x - 74, card.position.y + 78)
	draw_circle(bc2, 44, Color(tc.r * 0.3, tc.g * 0.3, tc.b * 0.3))
	_ring(bc2, 44, tc, 3.0)
	_draw_icon("crown", bc2, 44, tc, 2.0)
	_txt_r(str(tier[0]), card.end.x - 140, card.position.y + 70, 30, TEXT, true, 240)
	_txt_r("امتیاز: " + _fa(scoring_service.global_rating), card.end.x - 140, card.position.y + 98, 15, TEXT_DIM, false, 240)
	var lo: int = tier[2]
	var hi: int = tier[3]
	var frac: float = 1.0 if hi <= lo else clampf(float(scoring_service.global_rating - lo) / float(hi - lo), 0.0, 1.0)
	var pb := Rect2(card.position.x + 20, card.end.y - 46, card.size.x - 40, 12)
	_panel(pb, Color(1, 1, 1, 0.08), 6)
	_panel(Rect2(pb.position, Vector2(maxf(12.0, pb.size.x * frac), 12)), tc, 6)
	var note: String = "به بالاترین رتبه رسیده‌اید" if hi <= lo else "تا رتبه بعد: " + _fa(hi - scoring_service.global_rating) + " امتیاز"
	_txt_c(note, Rect2(card.position.x, card.end.y - 28, card.size.x, 22), 12, TEXT_DIM)
	_draw_bottom_nav()

# ---------------- OVERLAYS ----------------
func _scrim(a: float = 0.62) -> void:
	var k: float = _ease_out(_ov_t / 0.18)
	draw_rect(Rect2(0, 0, VIEW_W, VIEW_H), Color(0.02, 0.03, 0.08, a * k))

func _pause_layout() -> Rect2:
	var rows: int = 6 if vs_cpu else 5
	var h: float = 104.0 + rows * 62.0 + 24.0 + (28.0 if not vs_cpu else 0.0)
	return Rect2(36, (VIEW_H - h) * 0.5, VIEW_W - 72, h)

func _btns_pause() -> void:
	var p: Rect2 = _pause_layout()
	var y: float = p.position.y + 92
	var x: float = p.position.x + 20
	var w: float = p.size.x - 40
	_add_ov_btn(Rect2(x, y, w, 54), "ادامه بازی", _close_pause, GREEN, "solid", "play", "p_resume")
	y += 62
	_add_ov_btn(Rect2(x, y, w, 54), "راهنمای بازی", _open_rules, BLUE, "soft", "help", "p_rules")
	y += 62
	_add_ov_btn(Rect2(x, y, w, 54), _music_label(), _toggle_music, ACCENT, "soft", _music_icon(), "p_music")
	y += 62
	if vs_cpu:
		_add_ov_btn(Rect2(x, y, w, 54), "بازی جدید", _confirm_restart, ACCENT, "soft", "restart", "p_new")
		y += 62
	_add_ov_btn(Rect2(x, y, w, 54), "تسلیم", _confirm_resign, RED, "soft", "flag", "p_resign")
	y += 62
	_add_ov_btn(Rect2(x, y, w, 54), "خروج به منوی اصلی", _confirm_exit_game, TEXT_DIM, "ghost", "door", "p_exit")

func _close_pause() -> void:
	pause_open = false
	_rebuild_buttons()

func _draw_pause() -> void:
	_scrim()
	var p: Rect2 = _pause_layout()
	var k: float = _ease_out(_ov_t / 0.22)
	var r := Rect2(p.position + Vector2(0, (1.0 - k) * 30.0), p.size)
	_panel(r, Color(0.11, 0.14, 0.28), 28, LINE_STRONG, 1.0, 24, 10)
	_gloss(r, 28, 0.04)
	_txt_c("توقف بازی", Rect2(r.position.x, r.position.y + 18, r.size.x, 36), 24, TEXT, true)
	_txt_c(str(_game_info(selected_game).get("name", "")), Rect2(r.position.x, r.position.y + 54, r.size.x, 24), 14, TEXT_DIM)
	if not vs_cpu:
		_txt_c("بازی برای حریف متوقف نمی‌شود", Rect2(r.position.x, r.end.y - 38, r.size.x, 24), 12, ACCENT)

const CONN_HELP := [
	"بدون مودم: روی یک گوشی هات‌اسپات را روشن کنید و گوشی دوم را به وای‌فای همان هات‌اسپات وصل کنید. اینترنت لازم نیست.",
	"گوشی میزبان: وارد لابی شود و IP نمایش‌داده‌شده را به دوستش بدهد. (دکمه‌ی کپی کنار IP است.) IP هات‌اسپات معمولاً 192.168.43.1 است.",
	"گوشی مهمان: گزینه‌ی پیوستن را بزند و IP میزبان را کامل وارد کند. مثل 192.168.43.1",
	"اگر وای‌فای معمولی دارید، هر دو گوشی باید به همان وای‌فای وصل باشند. VPN را هم خاموش کنید.",
	"اگر IP کار نکرد، آن را از تنظیمات وای‌فای گوشی میزبان بخوانید. IP باید با 192.168 یا 10 یا 172 شروع شود.",
	"اگر «اتصال ناموفق بود» آمد، یعنی دو گوشی همدیگر را نمی‌بینند. از هات‌اسپات استفاده کنید یا گزینه‌ی AP/Client Isolation روتر را خاموش کنید.",
	"اگر «خطا در اتصال» همراه با یک کد آمد، آن کد را برای سازنده بفرستید.",
]

func _conn_help_active() -> bool:
	return rules_open and (state == State.LOBBY or state == State.IP_ENTRY)

func _rules_lines() -> Array:
	if _conn_help_active():
		return CONN_HELP
	return RULES.get(selected_game, [])

func _rules_layout() -> Dictionary:
	var lines: Array = _rules_lines()
	var tw: float = 392.0
	var total: float = 0.0
	var hs: Array = []
	for t in lines:
		var h: float = _wrap_h(str(t), tw, 15)
		hs.append(h)
		total += h + 16.0
	var ph: float = 96.0 + total + 84.0
	var py: float = maxf(40.0, (VIEW_H - ph) * 0.5)
	return {"rect": Rect2(24, py, VIEW_W - 48, ph), "hs": hs, "tw": tw}

func _btns_rules() -> void:
	var l: Dictionary = _rules_layout()
	var r: Rect2 = l.rect
	_add_ov_btn(Rect2(r.position.x + 24, r.end.y - 72, r.size.x - 48, 54), "متوجه شدم", _close_rules, GREEN, "solid", "check", "r_ok")

func _close_rules() -> void:
	rules_open = false
	_rebuild_buttons()

func _draw_rules() -> void:
	_scrim(0.70)
	var l: Dictionary = _rules_layout()
	var r: Rect2 = l.rect
	var col: Color = _game_info(selected_game).get("icon_col", ACCENT)
	_panel(r, Color(0.11, 0.14, 0.28), 28, Color(col.r, col.g, col.b, 0.5), 1.5, 24, 10)
	_gloss(r, 28, 0.04)
	var help_title: String = "راهنمای اتصال" if _conn_help_active() else "راهنمای " + str(_game_info(selected_game).get("name", ""))
	_txt_c(help_title, Rect2(r.position.x, r.position.y + 18, r.size.x, 40), 22, TEXT, true)
	draw_rect(Rect2(r.position.x + 28, r.position.y + 68, r.size.x - 56, 1), LINE)
	var lines: Array = _rules_lines()
	var hs: Array = l.hs
	var y: float = r.position.y + 90.0
	for i in lines.size():
		var h: float = hs[i]
		var dc := Vector2(r.end.x - 40, y + 12)
		draw_circle(dc, 13, Color(col.r, col.g, col.b, 0.25))
		_txt_c(_fa(i + 1), Rect2(dc.x - 13, dc.y - 13, 26, 26), 13, col.lightened(0.35), true)
		_wrap(str(lines[i]), r.position.x + 24, y + 16, float(l.tw), 15, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		y += h + 16.0

func _dialog_layout() -> Dictionary:
	var body: String = str(dialog.get("body", ""))
	var bh: float = _wrap_h(body, 360.0, 15)
	var h: float = 150.0 + bh + 24.0 + 54.0 + 12.0 + 50.0 + 24.0
	return {"rect": Rect2(40, (VIEW_H - h) * 0.5, VIEW_W - 80, h), "bh": bh}

func _btns_dialog() -> void:
	var l: Dictionary = _dialog_layout()
	var r: Rect2 = l.rect
	var danger: bool = dialog.get("danger", true)
	var y: float = r.end.y - 24 - 50 - 12 - 54
	_add_ov_btn(Rect2(r.position.x + 24, y, r.size.x - 48, 54), str(dialog.confirm), _dialog_confirm, RED if danger else GREEN, "solid", "", "d_confirm")
	_add_ov_btn(Rect2(r.position.x + 24, y + 66, r.size.x - 48, 50), str(dialog.cancel), _go_back, TEXT_DIM, "ghost", "", "d_cancel")

func _draw_dialog() -> void:
	_scrim(0.74)
	var l: Dictionary = _dialog_layout()
	var r0: Rect2 = l.rect
	var k: float = _ease_back(_ov_t / 0.28)
	var r: Rect2 = Rect2(r0.get_center() - r0.size * 0.5 * (0.88 + 0.12 * k), r0.size * (0.88 + 0.12 * k))
	var danger: bool = dialog.get("danger", true)
	var col: Color = RED if danger else GREEN
	_panel(r, Color(0.11, 0.14, 0.28), 28, Color(col.r, col.g, col.b, 0.5), 1.5, 26, 10)
	var ic := Vector2(VIEW_W * 0.5, r.position.y + 54)
	draw_circle(ic, 34, Color(col.r, col.g, col.b, 0.18))
	_ring(ic, 34, Color(col.r, col.g, col.b, 0.6), 1.5)
	_draw_icon(str(dialog.get("icon", "warning")), ic, 32, col.lightened(0.15), 2.6)
	_txt_c(str(dialog.get("title", "")), Rect2(r.position.x, r.position.y + 96, r.size.x, 40), 23, TEXT, true)
	_wrap(str(dialog.get("body", "")), r.position.x + 40, r.position.y + 150, r.size.x - 80, 15, TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)

# ---------------- MASTER DRAW ----------------
func _draw() -> void:
	var accent: Color = ACCENT
	if selected_game != "" and state != State.MENU and state != State.DASHBOARD and state != State.RANKINGS:
		accent = _game_info(selected_game).get("icon_col", ACCENT)
	_draw_bg(accent)
	match state:
		State.MENU: _draw_menu()
		State.MODE: _draw_mode()
		State.LOBBY: _draw_lobby()
		State.IP_ENTRY: _draw_ip_entry()
		State.PLAYING: _draw_playing()
		State.RESULT: _draw_result()
		State.DASHBOARD: _draw_dashboard()
		State.RANKINGS: _draw_rankings()
		State.ONLINE: _draw_online()
	for b in buttons:
		_draw_button(b)
	if _ov_active():
		if pause_open:
			_draw_pause()
		if rules_open:
			_draw_rules()
		if not dialog.is_empty():
			_draw_dialog()
		for b in ov_buttons:
			_draw_button(b)
	_draw_toast()
	var f: float = clampf(_state_t / 0.20, 0.0, 1.0)
	if f < 1.0:
		draw_rect(Rect2(0, 0, VIEW_W, VIEW_H), Color(BG_TOP.r, BG_TOP.g, BG_TOP.b, 1.0 - f))


# ======================================================================
#  GAME VISUALS — shared pieces
# ======================================================================
func _draw_disc(c: Vector2, r: float, light: bool) -> void:
	draw_circle(c + Vector2(0, r * 0.16), r, Color(0, 0, 0, 0.35))
	if light:
		draw_circle(c, r, Color(0.74, 0.77, 0.84))
		draw_circle(c + Vector2(0, -r * 0.05), r * 0.92, Color(0.95, 0.96, 0.99))
		draw_circle(c + Vector2(-r * 0.30, -r * 0.34), r * 0.26, Color(1, 1, 1, 0.75))
	else:
		draw_circle(c, r, Color(0.02, 0.03, 0.05))
		draw_circle(c + Vector2(0, -r * 0.05), r * 0.92, Color(0.15, 0.17, 0.24))
		draw_circle(c + Vector2(-r * 0.30, -r * 0.34), r * 0.24, Color(1, 1, 1, 0.22))

func _draw_marble(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c + Vector2(0, r * 0.16), r, Color(0, 0, 0, 0.35))
	draw_circle(c, r, col.darkened(0.35))
	draw_circle(c + Vector2(0, -r * 0.05), r * 0.92, col)
	draw_circle(c + Vector2(-r * 0.28, -r * 0.34), r * 0.26, Color(1, 1, 1, 0.55))

func _hint_dot(c: Vector2, r: float, col: Color) -> void:
	var k: float = 0.5 + 0.5 * sin(_time * 4.0)
	draw_circle(c, r + 3.0 * k, Color(col.r, col.g, col.b, 0.14))
	draw_circle(c, r, Color(col.r, col.g, col.b, 0.55))

func _pip_positions(n: int, rect: Rect2) -> Array:
	var c: Vector2 = rect.get_center()
	var dx: float = rect.size.x * 0.27
	var dy: float = rect.size.y * 0.27
	match n:
		1: return [c]
		2: return [c + Vector2(-dx, -dy), c + Vector2(dx, dy)]
		3: return [c + Vector2(-dx, -dy), c, c + Vector2(dx, dy)]
		4: return [c + Vector2(-dx, -dy), c + Vector2(dx, -dy), c + Vector2(-dx, dy), c + Vector2(dx, dy)]
		5: return [c + Vector2(-dx, -dy), c + Vector2(dx, -dy), c, c + Vector2(-dx, dy), c + Vector2(dx, dy)]
		6: return [c + Vector2(-dx, -dy), c + Vector2(dx, -dy), c + Vector2(-dx, 0), c + Vector2(dx, 0), c + Vector2(-dx, dy), c + Vector2(dx, dy)]
	return []

func _draw_pips(rect: Rect2, n: int, col: Color) -> void:
	var rad: float = maxf(2.0, minf(rect.size.x, rect.size.y) * 0.085)
	for p in _pip_positions(n, rect):
		draw_circle(p, rad, col)

func _draw_dice_face(r: Rect2, n: int, dim: bool = false) -> void:
	_panel(Rect2(r.position + Vector2(0, 2.5), r.size), Color(0, 0, 0, 0.35), r.size.x * 0.22)
	_panel(r, Color(0.95, 0.95, 0.97) if not dim else Color(0.55, 0.57, 0.65), r.size.x * 0.22)
	_draw_pips(r.grow(-r.size.x * 0.06), n, Color(0.12, 0.13, 0.20))

func _draw_dom_tile(r: Rect2, a: int, b: int, selected: bool, dim: bool, horizontal: bool, glow: Color = Color(0, 0, 0, 0)) -> void:
	var rad: float = minf(r.size.x, r.size.y) * 0.18
	_panel(Rect2(r.position + Vector2(0, 2.5), r.size), Color(0, 0, 0, 0.38), rad)
	var bg := Color(0.96, 0.94, 0.88)
	if dim:
		bg = bg.darkened(0.42)
	var bc: Color = ACCENT if selected else Color(0.25, 0.20, 0.14, 0.55)
	if glow.a > 0.0:
		bc = glow
	_panel(r, bg, rad, bc, 2.5 if (selected or glow.a > 0.0) else 1.0)
	var h1: Rect2
	var h2: Rect2
	var pc := Color(0.13, 0.12, 0.17) if not dim else Color(0.30, 0.28, 0.30)
	if horizontal:
		h1 = Rect2(r.position, Vector2(r.size.x * 0.5, r.size.y))
		h2 = Rect2(r.position + Vector2(r.size.x * 0.5, 0), Vector2(r.size.x * 0.5, r.size.y))
		draw_line(r.position + Vector2(r.size.x * 0.5, r.size.y * 0.16), r.position + Vector2(r.size.x * 0.5, r.size.y * 0.84), Color(0.3, 0.25, 0.2, 0.6), 1.5)
	else:
		h1 = Rect2(r.position, Vector2(r.size.x, r.size.y * 0.5))
		h2 = Rect2(r.position + Vector2(0, r.size.y * 0.5), Vector2(r.size.x, r.size.y * 0.5))
		draw_line(r.position + Vector2(r.size.x * 0.16, r.size.y * 0.5), r.position + Vector2(r.size.x * 0.84, r.size.y * 0.5), Color(0.3, 0.25, 0.2, 0.6), 1.5)
	_draw_pips(h1.grow(-2), a, pc)
	_draw_pips(h2.grow(-2), b, pc)

func _draw_dom_back(r: Rect2) -> void:
	var rad: float = minf(r.size.x, r.size.y) * 0.18
	_panel(r, Color(0.16, 0.19, 0.36), rad, Color(0.38, 0.45, 0.80, 0.6), 1.0, 4, 2)
	draw_circle(r.get_center(), minf(r.size.x, r.size.y) * 0.12, Color(0.45, 0.55, 0.95, 0.7))

# ---------- cards ----------
func _draw_suit(s: int, c: Vector2, sz: float, col: Color) -> void:
	var u: float = sz * 0.5
	match s:
		0:
			draw_circle(c + Vector2(-u * 0.44, u * 0.14), u * 0.48, col)
			draw_circle(c + Vector2(u * 0.44, u * 0.14), u * 0.48, col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -u), c + Vector2(-u * 0.92, u * 0.2), c + Vector2(u * 0.92, u * 0.2)]), col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 0.12, u * 0.1), c + Vector2(-u * 0.34, u * 0.98), c + Vector2(u * 0.34, u * 0.98), c + Vector2(u * 0.12, u * 0.1)]), col)
		1:
			draw_circle(c + Vector2(-u * 0.46, -u * 0.3), u * 0.5, col)
			draw_circle(c + Vector2(u * 0.46, -u * 0.3), u * 0.5, col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 0.96, -u * 0.1), c + Vector2(u * 0.96, -u * 0.1), c + Vector2(0, u * 0.98)]), col)
		2:
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -u), c + Vector2(u * 0.72, 0), c + Vector2(0, u), c + Vector2(-u * 0.72, 0)]), col)
		3:
			draw_circle(c + Vector2(0, -u * 0.46), u * 0.44, col)
			draw_circle(c + Vector2(-u * 0.52, u * 0.2), u * 0.44, col)
			draw_circle(c + Vector2(u * 0.52, u * 0.2), u * 0.44, col)
			draw_circle(c + Vector2(0, u * 0.06), u * 0.3, col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 0.12, u * 0.1), c + Vector2(-u * 0.34, u * 0.98), c + Vector2(u * 0.34, u * 0.98), c + Vector2(u * 0.12, u * 0.1)]), col)

func _draw_card(r: Rect2, c: Dictionary, selected: bool = false, dim: bool = false, hl: bool = false) -> void:
	var rad: float = minf(r.size.x * 0.14, 11.0)
	_panel(Rect2(r.position + Vector2(0, 3), r.size), Color(0, 0, 0, 0.38), rad)
	var bg := Color(0.98, 0.97, 0.94)
	if dim:
		bg = bg.darkened(0.36)
	var bcol: Color = Color(0.2, 0.18, 0.16, 0.45)
	var bw: float = 1.0
	if selected or hl:
		bcol = ACCENT
		bw = 3.0
	_panel(r, bg, rad, bcol, bw)
	var red: bool = (int(c.s) == 1 or int(c.s) == 2)
	var col: Color = Color(0.82, 0.13, 0.20) if red else Color(0.09, 0.10, 0.16)
	if dim:
		col = col.lerp(bg, 0.40)
	var label: String = PAS_RANKS[int(c.r)]
	var fs: int = int(r.size.x * 0.30)
	_txt(label, r.position.x + r.size.x * 0.10, r.position.y + fs + 3, fs, col, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	_draw_suit(int(c.s), Vector2(r.position.x + r.size.x * 0.10 + fs * 0.34, r.position.y + fs + 3 + fs * 0.55), fs * 0.55, col)
	if int(c.r) >= 11:
		_txt_c(label, Rect2(r.position.x, r.position.y + r.size.y * 0.30, r.size.x, r.size.y * 0.5), int(r.size.x * 0.62), col, true)
	else:
		_draw_suit(int(c.s), r.get_center() + Vector2(0, r.size.y * 0.1), r.size.x * 0.46, col)

func _draw_card_back(r: Rect2) -> void:
	var rad: float = minf(r.size.x * 0.14, 11.0)
	_panel(Rect2(r.position + Vector2(0, 2), r.size), Color(0, 0, 0, 0.35), rad)
	_panel(r, Color(0.20, 0.16, 0.42), rad, Color(0.96, 0.96, 1.0, 0.85), 2.0)
	var inner: Rect2 = r.grow(-r.size.x * 0.14)
	_panel(inner, Color(0.30, 0.24, 0.62), rad * 0.6, Color(0.7, 0.65, 1.0, 0.5), 1.0)
	var c: Vector2 = r.get_center()
	var h: float = minf(inner.size.x, inner.size.y) * 0.28
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h), c + Vector2(h * 0.7, 0), c + Vector2(0, h), c + Vector2(-h * 0.7, 0)]), Color(0.75, 0.70, 1.0, 0.55))

func _fan_rects(n: int, cw: float, ch: float, y: float, max_w: float = 508.0, gap: float = 8.0) -> Array:
	var rects: Array = []
	if n <= 0:
		return rects
	var step: float = cw + gap
	if n > 1 and step * (n - 1) + cw > max_w:
		step = (max_w - cw) / float(n - 1)
	var total: float = step * (n - 1) + cw
	var sx: float = (VIEW_W - total) * 0.5
	for i in n:
		rects.append(Rect2(sx + i * step, y, cw, ch))
	return rects

func _fan_hit(rects: Array, p: Vector2, lift: float = 26.0) -> int:
	for i in range(rects.size() - 1, -1, -1):
		var r: Rect2 = rects[i]
		if Rect2(r.position.x, r.position.y - lift, r.size.x, r.size.y + lift).has_point(p):
			return i
	return -1

# ---------- chess pieces (vector) ----------
func _cpoly(pts: Array, c: Vector2, u: float, fill: Color, edge: Color) -> void:
	var arr := PackedVector2Array()
	for p in pts:
		arr.append(c + (p as Vector2) * u)
	draw_colored_polygon(arr, fill)
	arr.append(arr[0])
	draw_polyline(arr, edge, 1.6, true)

func _ccirc(p: Vector2, r: float, c: Vector2, u: float, fill: Color, edge: Color) -> void:
	draw_circle(c + p * u, r * u + 1.4, edge)
	draw_circle(c + p * u, r * u, fill)

func _draw_chess_piece(typ: int, white: bool, c: Vector2, size: float) -> void:
	var fill: Color = Color(0.97, 0.95, 0.90) if white else Color(0.17, 0.18, 0.24)
	var edge: Color = Color(0.10, 0.09, 0.10) if white else Color(0.88, 0.90, 0.96)
	var u: float = size / 100.0
	_panel(Rect2(c + Vector2(-34, 30) * u, Vector2(68, 12) * u), Color(0, 0, 0, 0.28), 6.0 * u)
	_panel(Rect2(c + Vector2(-30, 26) * u, Vector2(60, 14) * u), fill, 6.0 * u, edge, 1.5)
	match typ:
		1:
			_cpoly([Vector2(-10, -8), Vector2(10, -8), Vector2(18, 26), Vector2(-18, 26)], c, u, fill, edge)
			_panel(Rect2(c + Vector2(-16, -12) * u, Vector2(32, 8) * u), fill, 3.0 * u, edge, 1.5)
			_ccirc(Vector2(0, -24), 13, c, u, fill, edge)
		2:
			_cpoly([Vector2(-22, 28), Vector2(-18, 6), Vector2(-8, -4), Vector2(-16, -10), Vector2(-8, -26), Vector2(0, -38), Vector2(5, -30), Vector2(13, -37), Vector2(15, -24), Vector2(24, -2), Vector2(22, 28)], c, u, fill, edge)
			draw_circle(c + Vector2(3, -22) * u, 2.8 * u, edge)
			draw_line(c + Vector2(-14, -12) * u, c + Vector2(-8, -10) * u, edge, 1.8, true)
		3:
			_cpoly([Vector2(-18, 26), Vector2(-8, -4), Vector2(8, -4), Vector2(18, 26)], c, u, fill, edge)
			var hp: Array = []
			for i in 16:
				var a: float = TAU * i / 16.0
				hp.append(Vector2(cos(a) * 12.0, -22.0 + sin(a) * 18.0))
			_cpoly(hp, c, u, fill, edge)
			_ccirc(Vector2(0, -44), 5, c, u, fill, edge)
			draw_line(c + Vector2(-3, -30) * u, c + Vector2(6, -16) * u, edge, 2.0, true)
		4:
			_cpoly([Vector2(-18, 26), Vector2(-14, -8), Vector2(14, -8), Vector2(18, 26)], c, u, fill, edge)
			_cpoly([Vector2(-21, -8), Vector2(-21, -34), Vector2(-12, -34), Vector2(-12, -26), Vector2(-4, -26), Vector2(-4, -34), Vector2(4, -34), Vector2(4, -26), Vector2(12, -26), Vector2(12, -34), Vector2(21, -34), Vector2(21, -8)], c, u, fill, edge)
		5:
			_cpoly([Vector2(-18, 26), Vector2(-12, -6), Vector2(12, -6), Vector2(18, 26)], c, u, fill, edge)
			_cpoly([Vector2(-22, -8), Vector2(-26, -32), Vector2(-12, -20), Vector2(-7, -38), Vector2(0, -22), Vector2(7, -38), Vector2(12, -20), Vector2(26, -32), Vector2(22, -8)], c, u, fill, edge)
			for px in [-26.0, -7.0, 7.0, 26.0]:
				_ccirc(Vector2(px, -36 if abs(px) < 10 else -33), 4, c, u, fill, edge)
		6:
			_cpoly([Vector2(-20, 26), Vector2(-14, -4), Vector2(14, -4), Vector2(20, 26)], c, u, fill, edge)
			_panel(Rect2(c + Vector2(-17, -22) * u, Vector2(34, 18) * u), fill, 6.0 * u, edge, 1.5)
			_panel(Rect2(c + Vector2(-3.5, -46) * u, Vector2(7, 26) * u), fill, 2.0 * u, edge, 1.5)
			_panel(Rect2(c + Vector2(-11, -39) * u, Vector2(22, 7) * u), fill, 2.0 * u, edge, 1.5)

# ======================================================================
#  OTHELLO
# ======================================================================
func _oth_cell() -> float:
	return _game_modules["othello"]._oth_cell()

func _oth_origin() -> Vector2:
	return _game_modules["othello"]._oth_origin()

func _oth_my_turn() -> bool:
	return _game_modules["othello"]._oth_my_turn()

func _othello_tap(p: Vector2) -> void:
	_game_modules["othello"]._othello_tap(p)

func _othello_cpu_move() -> void:
	_game_modules["othello"]._othello_cpu_move()

func _draw_othello() -> void:
	_game_modules["othello"]._draw_othello()

# ======================================================================
#  PENTAGO
# ======================================================================
const PENT_CELL := 72.0
const PENT_GAP := 14.0
func _pent_origin() -> Vector2:
	return _game_modules["pentago"]._pent_origin()

func _pent_cell_pos(x: int, y: int) -> Vector2:
	return _game_modules["pentago"]._pent_cell_pos(x, y)

func _pent_my_turn() -> bool:
	return _game_modules["pentago"]._pent_my_turn()

func _pent_tap(p: Vector2) -> void:
	_game_modules["pentago"]._pent_tap(p)

func _pent_rot(q: int, cw: bool) -> void:
	_game_modules["pentago"]._pent_rot(q, cw)

func _pent_quad_rect(q: int) -> Rect2:
	return _game_modules["pentago"]._pent_quad_rect(q)

func _btns_pentago() -> void:
	_game_modules["pentago"]._btns_pentago()

func _draw_pentago() -> void:
	_game_modules["pentago"]._draw_pentago()

# ======================================================================
#  QUORIDOR
# ======================================================================
const QUO_CELL := 50.0
const QUO_ORIGIN := Vector2(45, 196)

func _quo_apply_move(player: int, target: Vector2i) -> void:
	_game_modules["quoridor"]._quo_apply_move(player, target)

func _quo_advance_turn(completed_player: int) -> void:
	_game_modules["quoridor"]._quo_advance_turn(completed_player)

func _quo_my_turn() -> bool:
	return _game_modules["quoridor"]._quo_my_turn()

func _quo_edge_at(p: Vector2) -> Dictionary:
	return _game_modules["quoridor"]._quo_edge_at(p)

func _quo_tap(p: Vector2) -> void:
	_game_modules["quoridor"]._quo_tap(p)

func _quo_next_step(player: int) -> Vector2i:
	return _game_modules["quoridor"]._quo_next_step(player)

func _quo_cpu() -> void:
	_game_modules["quoridor"]._quo_cpu()

func _btns_quoridor() -> void:
	_game_modules["quoridor"]._btns_quoridor()

func _set_quo_mode(m: int) -> void:
	_game_modules["quoridor"]._set_quo_mode(m)

func _quo_color(player: int) -> Color:
	return _game_modules["quoridor"]._quo_color(player)

func _draw_four_player_hud() -> void:
	_game_modules["quoridor"]._draw_four_player_hud()

func _draw_quoridor() -> void:
	_game_modules["quoridor"]._draw_quoridor()

# ======================================================================
#  DOMINO
# ======================================================================
const DOM_L := 46.0
const DOM_W := 26.0
const DOM_PER_ROW := 9
const DOM_END_A := Color(0.38, 0.62, 1.0)
const DOM_END_B := Color(1.0, 0.62, 0.30)

func _dom_me() -> int:
	return _game_modules["domino"]._dom_me()

func _dom_my_turn() -> bool:
	return _game_modules["domino"]._dom_my_turn()

func _dom_hand_rects() -> Array:
	return _game_modules["domino"]._dom_hand_rects()

func _dom_tap(p: Vector2) -> void:
	_game_modules["domino"]._dom_tap(p)

func _dom_do_play(end: String) -> void:
	_game_modules["domino"]._dom_do_play(end)

func _dom_do_draw() -> void:
	_game_modules["domino"]._dom_do_draw()

func _dom_do_pass() -> void:
	_game_modules["domino"]._dom_do_pass()

func _dom_pass(p: int) -> void:
	_game_modules["domino"]._dom_pass(p)

@rpc("any_peer", "call_local", "reliable")
func _rpc_dom_draw(p: int) -> void:
	if selected_game == "domino":
		_dom_draw(p)

@rpc("any_peer", "call_local", "reliable")
func _rpc_dom_pass(p: int) -> void:
	if selected_game == "domino":
		_dom_pass(p)

func _btns_domino() -> void:
	_game_modules["domino"]._btns_domino()

# ---------- network moves for the newer 2-player games ----------
@rpc("any_peer", "call_local", "reliable")
func _rpc_gob_place(x: int, y: int, size: int, player: int) -> void:
	if selected_game == "gobblet" and state == State.PLAYING:
		_game_modules["gobblet"]._gob_place(x, y, size, player)

@rpc("any_peer", "call_local", "reliable")
func _rpc_aba_move(fx: int, fy: int, tx: int, ty: int) -> void:
	if selected_game == "abalone" and state == State.PLAYING:
		_game_modules["abalone"]._aba_apply_move(Vector2i(fx, fy), Vector2i(tx, ty))

@rpc("any_peer", "call_local", "reliable")
func _rpc_blk_place(px: int, py: int, sel: int, rot: int, player: int) -> void:
	if selected_game == "blockace" and state == State.PLAYING:
		_game_modules["blockace"]._blk_apply_net(px, py, sel, rot, player)

@rpc("any_peer", "call_local", "reliable")
func _rpc_bg_step(d1: int, d2: int) -> void:
	if selected_game == "backgammon" and state == State.PLAYING:
		_game_modules["backgammon"]._bg_step_apply(d1, d2)

@rpc("any_peer", "call_local", "reliable")
func _rpc_hokm_play(p: int, idx: int) -> void:
	if selected_game == "hokm" and state == State.PLAYING:
		_game_modules["hokm"]._hokm_play(p, idx)

@rpc("any_peer", "call_local", "reliable")
func _rpc_mm_submit(g: Array, player: int) -> void:
	if selected_game == "mastermind" and state == State.PLAYING:
		_game_modules["mastermind"]._mm_apply(g, player)

@rpc("any_peer", "call_local", "reliable")
func _rpc_quo_action(kind: int, x: int, y: int, vertical: bool) -> void:
	if selected_game == "quoridor" and state == State.PLAYING:
		_game_modules["quoridor"]._quo_net_apply(kind, x, y, vertical)

func _draw_domino() -> void:
	_game_modules["domino"]._draw_domino()

# ======================================================================
#  CHESS
# ======================================================================
const CHESS_ORIGIN := Vector2(30, 196)
const CHESS_CELL := 60.0

func _chess_flip() -> bool:
	return _game_modules["chess"]._chess_flip()

func _chess_scr(c: Vector2i) -> Vector2i:
	return _game_modules["chess"]._chess_scr(c)

func _chess_center(c: Vector2i) -> Vector2:
	return _game_modules["chess"]._chess_center(c)

func _chess_my_turn() -> bool:
	return _game_modules["chess"]._chess_my_turn()

func _chess_tap(p: Vector2) -> void:
	_game_modules["chess"]._chess_tap(p)

func _chess_king_in_check(col: int) -> Vector2i:
	return _game_modules["chess"]._chess_king_in_check(col)

func _draw_chess() -> void:
	_game_modules["chess"]._draw_chess()

# ======================================================================
#  PASOOR
# ======================================================================
func _pas_me() -> int:
	return _game_modules["pasoor"]._pas_me()

func _pas_my_turn() -> bool:
	return _game_modules["pasoor"]._pas_my_turn()

func _pas_hand_rects() -> Array:
	return _game_modules["pasoor"]._pas_hand_rects()

func _pas_table_rects() -> Array:
	return _game_modules["pasoor"]._pas_table_rects()

func _pas_confirm() -> void:
	_game_modules["pasoor"]._pas_confirm()

func _pas_tap(p: Vector2) -> void:
	_game_modules["pasoor"]._pas_tap(p)

func _btns_pasoor() -> void:
	_game_modules["pasoor"]._btns_pasoor()

func _draw_pasoor() -> void:
	_game_modules["pasoor"]._draw_pasoor()

# ======================================================================
#  MASTERMIND
# ======================================================================
func _mm_slot_pos(i: int) -> Vector2:
	return _game_modules["mastermind"]._mm_slot_pos(i)

func _mm_pick(c: int) -> void:
	_game_modules["mastermind"]._mm_pick(c)

func _mm_pick_slot(i: int) -> void:
	_game_modules["mastermind"]._mm_pick_slot(i)

func _mm_clear() -> void:
	_game_modules["mastermind"]._mm_clear()

func _mm_all_filled() -> bool:
	return _game_modules["mastermind"]._mm_all_filled()

func _mm_tap(_p: Vector2) -> void:
	_game_modules["mastermind"]._mm_tap(_p)

func _btns_mastermind() -> void:
	_game_modules["mastermind"]._btns_mastermind()

func _draw_mastermind() -> void:
	_game_modules["mastermind"]._draw_mastermind()

# ======================================================================
#  GOBBLET
# ======================================================================
const GOB_CELL := 100.0
const GOB_ORIGIN := Vector2(70, 176)

func _gob_my_turn() -> bool:
	return _game_modules["gobblet"]._gob_my_turn()

func _gob_tap(p: Vector2) -> void:
	_game_modules["gobblet"]._gob_tap(p)

func _gob_pick(s: int) -> void:
	_game_modules["gobblet"]._gob_pick(s)

func _btns_gobblet() -> void:
	_game_modules["gobblet"]._btns_gobblet()

func _draw_gobblet() -> void:
	_game_modules["gobblet"]._draw_gobblet()

# ======================================================================
#  HOKM
# ======================================================================
func _hk_rank(r: int) -> int:
	return _game_modules["hokm"]._hk_rank(r)

func _hokm_card_beats(a: Dictionary, b: Dictionary, led: int, trump: int) -> bool:
	return _game_modules["hokm"]._hokm_card_beats(a, b, led, trump)

func _hokm_legal(p: int, card: Dictionary) -> bool:
	return _game_modules["hokm"]._hokm_legal(p, card)

func _hokm_play(p: int, idx: int) -> void:
	_game_modules["hokm"]._hokm_play(p, idx)

func _hokm_cpu() -> void:
	_game_modules["hokm"]._hokm_cpu()

func _hokm_rects() -> Array:
	return _game_modules["hokm"]._hokm_rects()

func _hokm_tap(p: Vector2) -> void:
	_game_modules["hokm"]._hokm_tap(p)

func _draw_hokm() -> void:
	_game_modules["hokm"]._draw_hokm()

# ======================================================================
#  BACKGAMMON
# ======================================================================
func _bg_pt_x(col: int) -> float:
	return _game_modules["backgammon"]._bg_pt_x(col)

func _bg_step() -> void:
	_game_modules["backgammon"]._bg_step()

func _bg_tap(p: Vector2) -> void:
	_game_modules["backgammon"]._bg_tap(p)

func _btns_backgammon() -> void:
	_game_modules["backgammon"]._btns_backgammon()

func _draw_backgammon() -> void:
	_game_modules["backgammon"]._draw_backgammon()

# ======================================================================
#  ABALONE (simplified)
# ======================================================================
const ABA_CELL := 48.0
const ABA_ORIGIN := Vector2(54, 196)

func _aba_tap(p: Vector2) -> void:
	_game_modules["abalone"]._aba_tap(p)

func _draw_abalone() -> void:
	_game_modules["abalone"]._draw_abalone()

# ======================================================================
#  BLOCKACE
# ======================================================================
const BLK_CELL := 44.0
const BLK_ORIGIN := Vector2(50, 168)

func _blk_cells(idx: int, rot: int) -> Array:
	return _game_modules["blockace"]._blk_cells(idx, rot)

func _blk_has_move(player: int) -> bool:
	return _game_modules["blockace"]._blk_has_move(player)

func _blk_place(px: int, py: int, piece: Array, player: int) -> void:
	_game_modules["blockace"]._blk_place(px, py, piece, player)

func _blk_cpu() -> void:
	_game_modules["blockace"]._blk_cpu()

func _blk_confirm() -> void:
	_game_modules["blockace"]._blk_confirm()

func _blk_tap(p: Vector2) -> void:
	_game_modules["blockace"]._blk_tap(p)

func _blk_select(i: int) -> void:
	_game_modules["blockace"]._blk_select(i)

func _blk_rotate() -> void:
	_game_modules["blockace"]._blk_rotate()

func _btns_blockace() -> void:
	_game_modules["blockace"]._btns_blockace()

func _draw_blk_cell(r: Rect2, col: Color) -> void:
	_game_modules["blockace"]._draw_blk_cell(r, col)

func _draw_blockace() -> void:
	_game_modules["blockace"]._draw_blockace()

# ======================================================================
#  LOGIC REPLACEMENTS
# ======================================================================
var _client_connected: bool = false

func _init_game_modules() -> void:
	for id in GAME_MODULE_SCRIPTS.keys():
		var module = GAME_MODULE_SCRIPTS[id].new()
		module.bind(self, str(id))
		_game_modules[str(id)] = module

func _game_ids() -> Array:
	var ids: Array = []
	for game in GAMES:
		ids.append(str(game.id))
	return ids

func _ready() -> void:
	GAMES = GameCatalogScript.all_games()
	_init_game_modules()
	_setup_fonts()
	_setup_textures()
	get_tree().set_auto_accept_quit(false)
	randomize()
	_load_scores()
	_setup_music()
	_ensure_game_stats()
	_reset_othello()
	_reset_pentago()
	_reset_quoridor()
	_reset_domino()
	_reset_chess()
	_reset_pasoor()
	_rebuild_buttons()

func _process(delta: float) -> void:
	_time += delta
	_music_update(delta)
	_state_t += delta
	if _ov_active():
		_ov_t += delta
	if toast_timer > 0.0:
		toast_timer -= delta
	if not _press_active and absf(_scroll_vel) > 4.0:
		var before: float = scroll_y
		_scroll_by(_scroll_vel * delta)
		_scroll_vel *= pow(0.04, delta)
		if is_equal_approx(before, scroll_y):
			_scroll_vel = 0.0
	elif not _press_active:
		_scroll_vel = 0.0
	var sig: String = _ui_sig()
	if sig != _last_sig:
		_last_sig = sig
		_rebuild_buttons()
	_cpu_tick()
	queue_redraw()

func _load_scores() -> void:
	scoring_service.load_scores(_game_ids())

func _save_scores() -> void:
	scoring_service.seen_rules = seen_rules
	scoring_service.save_scores()

func _cleanup_network() -> void:
	if peer:
		peer.close()
		peer = null
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer = null
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)
	if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)
	connected_players = 1
	local_seat = 0
	peer_to_seat.clear()
	host_ips.clear()
	join_ip = ""
	_client_connected = false

func _on_connected_to_server() -> void:
	local_player_id = multiplayer.get_unique_id()
	_client_connected = true
	_show_toast("متصل شدید! منتظر شروع بازی توسط میزبان…")

func _on_connection_failed() -> void:
	_show_toast("اتصال ناموفق بود؛ IP و یکسان بودن وای‌فای را بررسی کنید.")
	var keep: String = join_ip
	_cleanup_network()
	join_ip = keep
	state = State.IP_ENTRY
	_rebuild_buttons()

func _reset_mastermind() -> void:
	_game_modules["mastermind"]._reset_mastermind()

func _mm_submit() -> void:
	_game_modules["mastermind"]._mm_submit()

func _gob_cpu() -> void:
	_game_modules["gobblet"]._gob_cpu()

