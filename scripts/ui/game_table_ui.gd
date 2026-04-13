extends Control

@onready var bottom_hand: HBoxContainer = $BottomHand
@onready var top_hand: HBoxContainer = $TopHand
@onready var left_hand: VBoxContainer = $MidRow/LeftHand
@onready var right_hand: VBoxContainer = $MidRow/RightHand
@onready var trick_area: Control = $MidRow/TrickArea
@onready var mid_row: HBoxContainer = $MidRow
@onready var north_avatar = $NorthAvatar
@onready var west_avatar = $WestAvatar
@onready var east_avatar = $EastAvatar
@onready var south_avatar = $SouthAvatar
@onready var top_hand_node: HBoxContainer = $TopHand
@onready var trump_label: Label = $HUD/HUDRow1/TrumpLabel
@onready var books_label: Label = $HUD/HUDRow1/BooksLabel
@onready var session_label: Label = $HUD/HUDRow2/SessionLabel
@onready var turn_label: Label = $HUD/HUDRow2/TurnLabel
@onready var timer_label: Label = $HUD/HUDRow2/TimerLabel
@onready var settings_button: Button = $HUD/HUDRow1/SettingsButton
@onready var history_button: Button = $HUD/HUDRow1/HistoryButton
@onready var trump_watermark: Label = $TrumpWatermark
@onready var toast_label: Label = $Toast

const CardScene := preload("res://scenes/card.tscn")
const TrumpSelectorScene := preload("res://scenes/ui/trump_selector.tscn")
const WinScreenScene := preload("res://scenes/ui/win_screen.tscn")
const SettingsOverlayScene := preload("res://scenes/ui/settings_overlay.tscn")
const HistoryOverlayScene := preload("res://scenes/ui/history_overlay.tscn")

# Watermark colors per suit.
const WATERMARK_RED := Color(0.75, 0.22, 0.17, 0.25)
const WATERMARK_BLACK := Color(0.08, 0.08, 0.08, 0.26)

# Sort button colors — gold when on, dim grey when off.

# Auto-play timing for the human's final card.
const AUTO_PLAY_DELAY := 0.5
const AUTO_PLAY_TOAST := "Auto playing last card"
const AUTO_PLAY_TOAST_DURATION := 1.0

# Card sizing — computed from viewport so cards scale with window width.
# Baseline: at viewport width 390 the bottom hand uses a 68x102 card with -42
# separation (13 cards fit in ~380 px). Opponent hands use 50% of the full size.
const CARD_ASPECT := 1.5                  # height / width
const CARD_WIDTH_RATIO := 0.174           # of viewport width (68/390)
const CARD_HEIGHT_CAP_RATIO := 0.12       # max card width as fraction of viewport height
const CARD_MAX_WIDTH := 110.0             # hard cap on tablet/desktop
const CARD_MIN_WIDTH := 40.0              # floor on very small viewports
const CARD_SEP_RATIO := 0.62              # -separation as fraction of card width
const SMALL_CARD_RATIO := 0.5             # opponents' cards: half-size
const SMALL_H_SEP_RATIO := 0.54           # top-hand horizontal separation
const SMALL_V_SEP_RATIO := 0.88           # side-hand vertical separation

var _card_size: Vector2 = Vector2(52, 78)
var _small_card_size: Vector2 = Vector2(26, 39)

var _selected_card: Card = null
var _current_valid_cards: Array[Card] = []
var _trump_selector_overlay: Control = null
var _win_screen_overlay: Control = null
var _settings_overlay: Control = null
var _history_overlay: Control = null

# Deal animation
var _deal_queue: Array = []        # Array of {seat, card, face_up}
var _deal_busy: bool = false
var _shuffle_done: bool = false
var _round_gen: int = 0
var _initial_deal_done: bool = false
var _awaiting_final_deal: bool = false

# States deferred until the deal animation finishes
var _pending_trump_selection: Dictionary = {}
var _pending_turn: Dictionary = {}
var _new_trick_pending: bool = true

# Active trick: maps seat index -> Control node for each played card (floating,
# not parented to a slot). Used by trick-collection animation.
var _trick_cards_by_seat: Dictionary = {}

func _ready() -> void:
	# Safety net: ensure suit glyphs render even if the default font lacks them.
	SuitFont.apply(trump_label)
	SuitFont.apply(trump_watermark)
	timer_label.visible = false
	_apply_card_sizing()
	get_viewport().size_changed.connect(_apply_card_sizing)
	_connect_signals()
	_trump_selector_overlay = TrumpSelectorScene.instantiate()
	_trump_selector_overlay.visible = false
	add_child(_trump_selector_overlay)
	_win_screen_overlay = WinScreenScene.instantiate()
	_win_screen_overlay.visible = false
	add_child(_win_screen_overlay)
	_win_screen_overlay.connect("history_requested", _on_history_button_pressed)
	_settings_overlay = SettingsOverlayScene.instantiate()
	_settings_overlay.visible = false
	add_child(_settings_overlay)
	_settings_overlay.connect("closed", _on_settings_closed)
	settings_button.pressed.connect(_on_settings_button_pressed)
	_history_overlay = HistoryOverlayScene.instantiate()
	_history_overlay.visible = false
	add_child(_history_overlay)
	history_button.pressed.connect(_on_history_button_pressed)
	toast_label.visible = false
	_refresh_south_name()
	Settings.changed.connect(_refresh_south_name)
	# Mobile: keep the display awake during play — AI turns + animations leave
	# the human idle for long stretches that would otherwise trip screen sleep.
	DisplayServer.screen_set_keep_on(true)
	if not GameState.multiplayer_mode:
		GameState.start_session()
	else:
		# Flush any server events buffered while the scene was swapping in.
		var src = GameState.game_source
		if src is NetGameView:
			(src as NetGameView).begin_live()
	_refresh_opponent_names()

func _exit_tree() -> void:
	# Release the wake lock when leaving the game scene.
	DisplayServer.screen_set_keep_on(false)

func _refresh_south_name() -> void:
	south_avatar.set_player_name(Settings.player_name)

## Reposition avatars above the actual first card in the side stacks.
## Called one frame after a dealing batch finishes so the VBoxContainer
## has laid out its children.
func _reposition_side_avatars() -> void:
	var avatar_gap: float = 10.0
	var avatar_h: float = 66.0  # 48 circle + 2 spacing + ~14 label
	if top_hand.get_child_count() > 0:
		north_avatar.visible = true
	if left_hand.get_child_count() > 0:
		var first_card := left_hand.get_child(0) as Control
		var card_top_y: float = left_hand.global_position.y + first_card.position.y
		west_avatar.offset_top = card_top_y - avatar_gap - avatar_h
		west_avatar.offset_bottom = card_top_y - avatar_gap
		west_avatar.visible = true
	if right_hand.get_child_count() > 0:
		var first_card := right_hand.get_child(0) as Control
		var card_top_y: float = right_hand.global_position.y + first_card.position.y
		east_avatar.offset_top = card_top_y - avatar_gap - avatar_h
		east_avatar.offset_bottom = card_top_y - avatar_gap
		east_avatar.visible = true

func _refresh_opponent_names() -> void:
	var west_player := GameState.get_player(1)
	var north_player := GameState.get_player(2)
	var east_player := GameState.get_player(3)
	if west_player != null:
		west_avatar.set_player_name(west_player.display_name)
	if north_player != null:
		north_avatar.set_player_name(north_player.display_name)
	if east_player != null:
		east_avatar.set_player_name(east_player.display_name)

func _get_avatar(seat: int):
	match seat:
		0: return south_avatar
		1: return west_avatar
		2: return north_avatar
		3: return east_avatar
	return null

func _set_all_avatars_inactive() -> void:
	for s in range(4):
		var avatar = _get_avatar(s)
		if avatar:
			avatar.set_active(false)

func _update_avatar_tricks(seat_books: Array) -> void:
	if seat_books.size() < 4:
		return
	for s in range(4):
		var avatar = _get_avatar(s)
		if avatar:
			avatar.set_tricks(int(seat_books[s]))

func _clear_avatar_tricks() -> void:
	for s in range(4):
		var avatar = _get_avatar(s)
		if avatar:
			avatar.clear_tricks()

## Mobile lifecycle handlers. Back button opens (or closes) the settings
## overlay; app-pause pauses the round clock so AI doesn't run in the
## background; app-resume restores play.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_handle_back_request()
		NOTIFICATION_APPLICATION_PAUSED:
			_set_menu_paused(true)
		NOTIFICATION_APPLICATION_RESUMED:
			# Only auto-unpause if the settings overlay isn't the visible pauser.
			if not _settings_overlay.visible:
				_set_menu_paused(false)

func _handle_back_request() -> void:
	# Close any open overlay first; otherwise treat back as "open settings".
	if _settings_overlay != null and _settings_overlay.visible:
		_settings_overlay.visible = false
		_on_settings_closed()
		return
	if _history_overlay != null and _history_overlay.visible:
		_history_overlay.visible = false
		return
	# Don't allow back to escape trump selection or win screen — user must
	# complete the required interaction.
	if _trump_selector_overlay != null and _trump_selector_overlay.visible:
		return
	if _win_screen_overlay != null and _win_screen_overlay.visible:
		return
	_on_settings_button_pressed()

## Compute card dimensions from viewport width and apply them to hand
## containers, trick slots, and any existing card nodes. Called at _ready and
## whenever the viewport size changes.
func _apply_card_sizing() -> void:
	var vp_rect: Rect2 = get_viewport_rect()
	var vp_w: float = vp_rect.size.x
	# Safe area insets (notches, home indicators). Zero on desktop.
	var safe_top: float = 0.0
	var safe_bottom: float = 0.0
	var safe_left: float = 0.0
	var safe_right: float = 0.0
	var win_size := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x > 0 and safe.size.y > 0 and win_size.x > 0 and win_size.y > 0:
		# Convert safe-area pixels to viewport units (they may differ under
		# stretching). vp_rect.size reports the stretched viewport size.
		var sx: float = vp_w / float(win_size.x)
		var sy: float = vp_rect.size.y / float(win_size.y)
		safe_top = maxf(0.0, float(safe.position.y) * sy)
		safe_bottom = maxf(0.0, float(win_size.y - (safe.position.y + safe.size.y)) * sy)
		safe_left = maxf(0.0, float(safe.position.x) * sx)
		safe_right = maxf(0.0, float(win_size.x - (safe.position.x + safe.size.x)) * sx)
	var eff_w: float = maxf(1.0, vp_w - safe_left - safe_right)
	var eff_h: float = maxf(1.0, vp_rect.size.y - safe_top - safe_bottom)
	var w_cap: float = minf(eff_h * CARD_HEIGHT_CAP_RATIO, CARD_MAX_WIDTH)
	var w: float = roundf(clampf(eff_w * CARD_WIDTH_RATIO, CARD_MIN_WIDTH, w_cap))
	var h: float = roundf(w * CARD_ASPECT)
	_card_size = Vector2(w, h)
	var sw: float = roundf(w * SMALL_CARD_RATIO)
	var sh: float = roundf(h * SMALL_CARD_RATIO)
	_small_card_size = Vector2(sw, sh)
	var sep_full: int = -int(roundf(w * CARD_SEP_RATIO))
	var sep_h: int = -int(roundf(sw * SMALL_H_SEP_RATIO))
	var sep_v: int = -int(roundf(sh * SMALL_V_SEP_RATIO))
	bottom_hand.add_theme_constant_override("separation", sep_full)
	top_hand.add_theme_constant_override("separation", sep_h)
	left_hand.add_theme_constant_override("separation", sep_v)
	right_hand.add_theme_constant_override("separation", sep_v)
	left_hand.custom_minimum_size = Vector2(sw, 0)
	right_hand.custom_minimum_size = Vector2(sw, 0)
	# Position the trick slots around center based on the full card size.
	_apply_trick_slot_layout()
	# Resize any cards that already exist in the scene.
	for child in bottom_hand.get_children():
		(child as Control).custom_minimum_size = _card_size
	for container in [top_hand, left_hand, right_hand]:
		for child in container.get_children():
			(child as Control).custom_minimum_size = _small_card_size
	# Adjust vertical layout so the larger cards fit above/below the mid row.
	# HUD shifts down by safe_top to clear any notch. NorthName and TopHand
	# follow.
	var hud: Control = $HUD as Control
	hud.offset_left = 6.0 + safe_left
	hud.offset_right = -6.0 - safe_right
	# HUD height: row1 uses 44px touch-target buttons + row2 of small text (~16px).
	var hud_height: float = 60.0
	hud.offset_top = safe_top
	hud.offset_bottom = safe_top + hud_height
	# Gap between avatars and adjacent card rows.
	var name_gap: float = 10.0
	var avatar_h: float = 66.0  # 48 circle + 2 spacing + ~14 label
	# North avatar: hidden until dealing populates top hand.
	north_avatar.visible = false
	north_avatar.offset_left = -24.0
	north_avatar.offset_right = 24.0
	north_avatar.offset_top = safe_top + hud_height
	north_avatar.offset_bottom = safe_top + hud_height + avatar_h
	var top_hand_top: float = safe_top + hud_height + avatar_h + name_gap
	top_hand_node.offset_top = top_hand_top
	var top_hand_bottom: float = top_hand_top + sh + 4.0
	top_hand_node.offset_bottom = top_hand_bottom
	mid_row.offset_top = top_hand_bottom
	# Bottom area: SouthAvatar sits above BottomHand so the trick count
	# is always visible and never covered by cards.
	var bottom_hand_height: float = h + 6.0
	var _south_section: float = bottom_hand_height + name_gap + avatar_h + safe_bottom
	# West/East avatars: horizontal layout set now; vertical deferred to
	# _reposition_side_avatars() after dealing populates containers.
	var side_avatar_w: float = 48.0
	west_avatar.anchor_left = 0.0
	west_avatar.anchor_right = 0.0
	west_avatar.offset_left = safe_left
	west_avatar.offset_right = safe_left + side_avatar_w
	east_avatar.anchor_left = 1.0
	east_avatar.anchor_right = 1.0
	east_avatar.offset_left = -safe_right - side_avatar_w
	east_avatar.offset_right = -safe_right
	# Hide until _reposition_side_avatars() places them at the correct height.
	west_avatar.visible = false
	east_avatar.visible = false
	bottom_hand.offset_top = -bottom_hand_height - safe_bottom
	bottom_hand.offset_bottom = -safe_bottom
	# South avatar: positioned above the bottom hand.
	var south_avatar_top: float = bottom_hand_height + name_gap + safe_bottom
	south_avatar.offset_left = -24.0
	south_avatar.offset_right = 24.0
	south_avatar.offset_top = -(south_avatar_top + avatar_h)
	south_avatar.offset_bottom = -south_avatar_top
	mid_row.offset_bottom = -(south_avatar_top + avatar_h + name_gap)
	# Respect horizontal safe insets on MidRow so side hands clear any
	# landscape-notch cutouts (no-op in portrait).
	mid_row.offset_left = safe_left
	mid_row.offset_right = -safe_right
	# Toast sits just above the south avatar.
	toast_label.offset_top = -(south_avatar_top + avatar_h + 20.0)
	toast_label.offset_bottom = -(south_avatar_top + avatar_h)

func _apply_trick_slot_layout() -> void:
	var w: float = _card_size.x
	var h: float = _card_size.y
	var gap: float = 1.0
	var layouts := {
		"NorthSlot": Vector2(0.0, -(h + gap)),
		"SouthSlot": Vector2(0.0, gap),
		"WestSlot": Vector2(-(w + gap), -h / 2.0),
		"EastSlot": Vector2(gap, -h / 2.0),
	}
	# NorthSlot and SouthSlot are horizontally centered (width=w).
	# WestSlot and EastSlot are vertically centered (height=h).
	for slot_name in layouts.keys():
		var slot := trick_area.get_node_or_null(slot_name) as Control
		if slot == null:
			continue
		var origin: Vector2 = layouts[slot_name]
		if slot_name == "NorthSlot" or slot_name == "SouthSlot":
			slot.offset_left = -w / 2.0
			slot.offset_right = w / 2.0
			slot.offset_top = origin.y
			slot.offset_bottom = origin.y + h
		else:
			slot.offset_left = origin.x
			slot.offset_right = origin.x + w
			slot.offset_top = origin.y
			slot.offset_bottom = origin.y + h

## Convenience pair — the source used for reads (signals, state fields) and
## a flag indicating which action path to use on writes.
func _source():
	return GameState.game_source

func _is_mp() -> bool:
	return GameState.multiplayer_mode

func _send_play(card: Card) -> void:
	if _is_mp():
		NetworkState.play_card(card)
	else:
		GameState.get_round_manager().play_card(0, card)

func _set_deal_paused(value: bool) -> void:
	var src = _source()
	if src != null and "deal_paused" in src:
		src.deal_paused = value

func _set_menu_paused(value: bool) -> void:
	if _is_mp():
		return  # Server owns pause in MP.
	var rm := GameState.get_round_manager()
	if rm != null:
		rm.menu_paused = value

func _on_settings_button_pressed() -> void:
	_set_menu_paused(true)
	_settings_overlay.visible = true

func _on_settings_closed() -> void:
	_set_menu_paused(false)

## Re-order the human's hand data array and reorder the bottom_hand children
## to match. No-op when the sort toggle is off.
func _resort_human_hand() -> void:
	if not GameState.sort_enabled:
		return
	var human := GameState.get_player(0)
	if human == null or human.hand == null:
		return
	human.hand.sort_hand()
	for i in range(human.hand.cards.size()):
		var card: Card = human.hand.cards[i]
		for child in bottom_hand.get_children():
			if child.get("card_data") == card:
				bottom_hand.move_child(child, i)
				break

func _on_history_button_pressed() -> void:
	# Informational overlay — does NOT pause the game.
	if _history_overlay == null:
		return
	var src = _source()
	_history_overlay.call("show_history", src.trick_history)

func _connect_signals() -> void:
	var src = _source()
	src.hand_dealt.connect(_on_hand_dealt)
	src.trump_selection_needed.connect(_on_trump_selection_needed)
	src.trump_declared.connect(_on_trump_declared)
	src.turn_started.connect(_on_turn_started)
	src.card_played_signal.connect(_on_card_played)
	src.trick_completed.connect(_on_trick_completed)
	src.round_ended.connect(_on_round_ended)
	if _is_mp():
		# NetGameView drives round start via round_starting, not GameState.
		src.round_starting.connect(_on_round_started)
		src.seat_taken_over_by_ai.connect(_on_seat_taken_over_by_ai)
		NetworkState.error_received.connect(_on_mp_error_received)
		NetworkState.connection_state_changed.connect(_on_mp_connection_changed)
	else:
		GameState.round_started.connect(_on_round_started)

func _get_hand_container(seat: int) -> BoxContainer:
	# Seats are clockwise from the human: 0=South, 1=West, 2=North, 3=East.
	match seat:
		0: return bottom_hand
		1: return left_hand
		2: return top_hand
		3: return right_hand
	return null

func _get_trick_slot(seat: int) -> Control:
	match seat:
		0: return trick_area.get_node("SouthSlot")
		1: return trick_area.get_node("WestSlot")
		2: return trick_area.get_node("NorthSlot")
		3: return trick_area.get_node("EastSlot")
	return null

# ── Dealing ───────────────────────────────────────────────────────────────────

func _on_hand_dealt(seat: int, cards: Array) -> void:
	var face_up := (seat == 0)
	for card in cards:
		_deal_queue.append({seat = seat, card = card, face_up = face_up})
	# Shuffle animation calls _maybe_start_deal when it finishes.
	# For subsequent deals (after trump selection), shuffle is already done.
	if _shuffle_done:
		_maybe_start_deal()

func _maybe_start_deal() -> void:
	if _deal_busy or _deal_queue.is_empty():
		return
	_deal_busy = true
	_process_deal_queue()

func _process_deal_queue() -> void:
	if _deal_queue.is_empty():
		_deal_busy = false
		_set_deal_paused(false)
		if _awaiting_final_deal:
			_awaiting_final_deal = false
			_initial_deal_done = true
		_resort_human_hand()
		# Reposition side names after VBoxContainer lays out the dealt cards.
		call_deferred("_reposition_side_avatars")
		_flush_pending()
		return
	var item: Dictionary = _deal_queue.pop_front()
	_animate_deal_one(item.seat, item.card, item.face_up)

func _flush_pending() -> void:
	if not _pending_trump_selection.is_empty():
		var s := _pending_trump_selection.duplicate()
		_pending_trump_selection.clear()
		_do_show_trump_selection(s.seat, s.initial_cards)
	elif not _pending_turn.is_empty():
		var t := _pending_turn.duplicate()
		_pending_turn.clear()
		_do_apply_turn(t.seat, t.valid_cards)

func _animate_deal_one(seat: int, card: Card, face_up: bool) -> void:
	var gen := _round_gen

	# Add the real card to its container, hidden while the fly-card animates
	var container := _get_hand_container(seat)
	var card_node := CardScene.instantiate() as PanelContainer
	if seat == 0:
		card_node.custom_minimum_size = _card_size
	else:
		card_node.custom_minimum_size = _small_card_size
	# Human cards arrive face-down then flip face-up via a ScaleX tween.
	# Opponents' cards stay face-down.
	card_node.call("setup", card, false)
	if face_up:
		card_node.connect("card_tapped", _on_card_tapped)
		card_node.connect("card_play_requested", _on_card_play_requested)
	container.add_child(card_node)
	card_node.modulate.a = 0.0

	# Let layout settle so we can read card_node's actual position/size
	await get_tree().process_frame

	if _round_gen != gen or not is_instance_valid(card_node):
		_process_deal_queue()
		return

	# Fly-card: starts at deck center and glides to the card's resting position
	var fly_size := card_node.size
	if fly_size == Vector2.ZERO:
		fly_size = card_node.custom_minimum_size if card_node.custom_minimum_size != Vector2.ZERO \
				else _small_card_size

	var fly := CardScene.instantiate() as PanelContainer
	# Fly card travels face-down regardless of destination — the flip happens
	# after arrival only for the human's cards.
	fly.call("setup", card, false)
	fly.custom_minimum_size = fly_size
	fly.size = fly_size
	add_child(fly)
	fly.z_index = 100
	fly.position = (get_viewport_rect().size / 2.0 - global_position) - fly_size / 2.0

	var target: Vector2 = card_node.global_position - global_position
	var tween := AnimationManager.deal_fly(fly, target)

	await tween.finished

	if is_instance_valid(fly):
		fly.queue_free()
	if is_instance_valid(card_node) and _round_gen == gen:
		card_node.modulate.a = 1.0
		# For the human's cards, flip face-down → face-up with a scale-X tween.
		if face_up:
			var flip_tween := AnimationManager.flip(card_node, true)
			await flip_tween.finished

	if _round_gen == gen:
		_process_deal_queue()

# ── Shuffle animation ─────────────────────────────────────────────────────────

func _play_shuffle_animation() -> void:
	AudioManager.play("shuffle")
	var gen := _round_gen
	var center: Vector2 = get_viewport_rect().size / 2.0 - global_position

	# Stack of face-down placeholders representing the deck
	var deck_cards: Array = []
	for i in range(6):
		var c := CardScene.instantiate() as PanelContainer
		c.call("setup", null, false)
		c.custom_minimum_size = _card_size
		c.size = _card_size
		add_child(c)
		c.z_index = 50 + i
		c.position = center - _card_size / 2.0
		deck_cards.append(c)

	await get_tree().process_frame

	if _round_gen != gen:
		for c in deck_cards:
			if is_instance_valid(c): c.queue_free()
		return

	# Fan the cards out
	var fan := create_tween()
	fan.set_parallel(true)
	for i in range(deck_cards.size()):
		var offset_x := (i - 2.5) * 20.0
		var rot := (i - 2.5) * 9.0
		fan.tween_property(deck_cards[i], "position",
				center + Vector2(offset_x, 0.0) - Vector2(26, 39), 0.22)
		fan.tween_property(deck_cards[i], "rotation_degrees", rot, 0.22)
	await fan.finished

	if _round_gen != gen:
		for c in deck_cards:
			if is_instance_valid(c): c.queue_free()
		return

	# Riffle back together
	var riffle := create_tween()
	riffle.set_parallel(true)
	for c in deck_cards:
		riffle.tween_property(c, "position", center - Vector2(26, 39), 0.2)
		riffle.tween_property(c, "rotation_degrees", 0.0, 0.2)
	await riffle.finished

	if _round_gen != gen:
		for c in deck_cards:
			if is_instance_valid(c): c.queue_free()
		return

	await get_tree().create_timer(0.1).timeout

	if _round_gen != gen:
		for c in deck_cards:
			if is_instance_valid(c): c.queue_free()
		return

	# Fade deck out
	var fade := create_tween()
	fade.set_parallel(true)
	for c in deck_cards:
		fade.tween_property(c, "modulate:a", 0.0, 0.15)
	await fade.finished

	for c in deck_cards:
		if is_instance_valid(c): c.queue_free()

	if _round_gen != gen:
		return

	_shuffle_done = true
	_maybe_start_deal()

# ── Trump selection ───────────────────────────────────────────────────────────

func _on_trump_selection_needed(seat: int, initial_cards: Array) -> void:
	if _is_animating():
		_pending_trump_selection = {seat = seat, initial_cards = initial_cards}
	else:
		_do_show_trump_selection(seat, initial_cards)

func _is_animating() -> bool:
	# True while shuffle is playing or while cards are still being dealt out
	return not _shuffle_done or _deal_busy or not _deal_queue.is_empty()

func _do_show_trump_selection(seat: int, initial_cards: Array) -> void:
	if seat == 0 and _trump_selector_overlay != null:
		_trump_selector_overlay.call("show_for_human", initial_cards)
		_trump_selector_overlay.call("animate_show")

func _on_trump_declared(suit: Card.Suit) -> void:
	# Trump is declared — discard any pending selector (AI may have declared during shuffle)
	_pending_trump_selection.clear()
	_awaiting_final_deal = true
	# Pause again while the 47 remaining cards animate out.
	_set_deal_paused(true)
	if _trump_selector_overlay != null:
		_trump_selector_overlay.call("animate_hide")
	trump_label.text = "Trump: " + Card.SUIT_NAMES[suit] + " " + Card.SUIT_SYMBOLS[suit]
	_show_trump_watermark(suit)

func _show_trump_watermark(suit: Card.Suit) -> void:
	if trump_watermark == null:
		return
	trump_watermark.text = Card.SUIT_SYMBOLS[suit]
	var is_red := suit == Card.Suit.HEARTS or suit == Card.Suit.DIAMONDS
	trump_watermark.add_theme_color_override("font_color",
			WATERMARK_RED if is_red else WATERMARK_BLACK)
	trump_watermark.modulate.a = 0.0
	trump_watermark.visible = true
	var tw := create_tween()
	tw.tween_property(trump_watermark, "modulate:a", 1.0, 0.3 * Settings.anim_multiplier())

func _hide_trump_watermark() -> void:
	if trump_watermark != null:
		trump_watermark.visible = false

# ── Turn handling ─────────────────────────────────────────────────────────────

func _on_turn_started(seat: int, valid_cards: Array) -> void:
	# Only clear slots when starting a new trick (after the previous trick has
	# been resolved and displayed). During an in-progress trick, leave played
	# cards visible so all 4 can be seen at trick completion.
	if _new_trick_pending:
		_clear_trick_slots()
		_new_trick_pending = false
	if _is_animating():
		_pending_turn = {seat = seat, valid_cards = valid_cards}
	else:
		_do_apply_turn(seat, valid_cards)

func _do_apply_turn(seat: int, valid_cards: Array) -> void:
	_set_all_avatars_inactive()
	var active_avatar = _get_avatar(seat)
	if active_avatar:
		active_avatar.set_active(true)
	_current_valid_cards.clear()
	for c in valid_cards:
		_current_valid_cards.append(c as Card)
	turn_label.text = "Your turn" if seat == 0 else GameState.get_player(seat).display_name + "'s turn"
	if seat == 0:
		GameState.vibrate(50)
		_highlight_valid_cards()
		# Auto-play the final card so the human doesn't have to tap a no-choice play.
		var human := GameState.get_player(0)
		if human != null and human.hand != null and human.hand.size() == 1:
			_auto_play_last_card(human.hand.cards[0])

func _auto_play_last_card(card: Card) -> void:
	var gen := _round_gen
	var fade_dur := 0.15 * Settings.anim_multiplier()
	toast_label.text = AUTO_PLAY_TOAST
	toast_label.modulate.a = 0.0
	toast_label.visible = true
	var fade_in := create_tween()
	fade_in.tween_property(toast_label, "modulate:a", 1.0, fade_dur)
	await get_tree().create_timer(AUTO_PLAY_DELAY).timeout
	if _round_gen != gen:
		toast_label.visible = false
		return
	_send_play(card)
	# Leave the toast up briefly after the play fires.
	var remaining := AUTO_PLAY_TOAST_DURATION - AUTO_PLAY_DELAY
	if remaining > 0.0:
		await get_tree().create_timer(remaining).timeout
	if _round_gen == gen:
		var fade_out := create_tween()
		fade_out.tween_property(toast_label, "modulate:a", 0.0, fade_dur)
		await fade_out.finished
		if _round_gen == gen:
			toast_label.visible = false

func _highlight_valid_cards() -> void:
	for child in bottom_hand.get_children():
		var card_data: Card = child.get("card_data")
		if card_data != null:
			child.call("set_valid", card_data in _current_valid_cards)
			child.call("set_highlight", true)

# ── Card interaction ──────────────────────────────────────────────────────────

func _on_card_tapped(card: Card) -> void:
	if not _initial_deal_done or card not in _current_valid_cards or _deal_busy:
		return
	if _selected_card == card:
		_confirm_play()
	else:
		if _selected_card != null:
			_deselect_current()
		_selected_card = card
		_select_in_hand(card)

func _on_card_play_requested(card: Card) -> void:
	if not _initial_deal_done or card not in _current_valid_cards or _deal_busy:
		return
	if _selected_card != null:
		_deselect_current()
	_selected_card = null
	_reset_hand_state()
	_send_play(card)

func _select_in_hand(card: Card) -> void:
	for child in bottom_hand.get_children():
		if child.get("card_data") == card:
			child.call("set_selected", true)

func _deselect_current() -> void:
	if _selected_card == null:
		return
	for child in bottom_hand.get_children():
		if child.get("card_data") == _selected_card:
			child.call("set_selected", false)
	_selected_card = null

func _input(event: InputEvent) -> void:
	# Deselect the current card when the user taps anywhere outside a card.
	# Uses _input (not _unhandled_input) so intermediate Control nodes that
	# absorb events (TrickArea, overlays) can't block deselection.
	if _selected_card == null:
		return
	# Touch taps are emulated as InputEventMouseButton by Godot (default
	# emulate_mouse_from_touch=true), so we only need to listen for mouse
	# events to cover both desktop and Android.
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if not (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
		return
	var pos_global: Vector2 = mb.global_position
	# Ignore taps inside any card in the player's hand.
	for child in bottom_hand.get_children():
		var ctrl := child as Control
		if ctrl != null and ctrl.get_global_rect().has_point(pos_global):
			return
	_deselect_current()

func _confirm_play() -> void:
	var card := _selected_card
	_selected_card = null
	_reset_hand_state()
	_send_play(card)

func _reset_hand_state() -> void:
	for child in bottom_hand.get_children():
		child.call("set_valid", true)
		child.call("set_selected", false)
		child.call("set_highlight", false)

# ── Card played & trick ───────────────────────────────────────────────────────

func _on_card_played(seat: int, card: Card) -> void:
	var played_avatar = _get_avatar(seat)
	if played_avatar:
		played_avatar.set_active(false)
	AudioManager.play("card_play")
	if seat == 0:
		GameState.vibrate(30)
	var gen := _round_gen
	# Remove the card from the player's hand and capture its on-screen position.
	var container := _get_hand_container(seat)
	var start_global := Vector2.ZERO
	var found := false
	if container != null:
		for child in container.get_children():
			if child.get("card_data") == card:
				start_global = (child as Control).global_position
				child.queue_free()
				found = true
				break
	var slot := _get_trick_slot(seat)
	if slot == null:
		return
	# Create a face-up flying card that will slide from the hand to the slot.
	var fly := CardScene.instantiate() as PanelContainer
	fly.call("setup", card, true)
	fly.custom_minimum_size = _card_size
	fly.size = _card_size
	add_child(fly)
	fly.z_index = 50
	# Wait one frame so the slot has its final global_position computed.
	await get_tree().process_frame
	if _round_gen != gen or not is_instance_valid(fly):
		return
	if seat == 0:
		_resort_human_hand()
	if found:
		fly.position = start_global - global_position
	else:
		fly.position = slot.global_position - global_position
	_trick_cards_by_seat[seat] = fly
	var target: Vector2 = slot.global_position - global_position
	var tween := AnimationManager.card_play(fly, target)
	await tween.finished

func _on_trick_completed(winner_seat: int, books: Array, seat_books: Array) -> void:
	_new_trick_pending = true
	# Team 0 = human + partner (seats 0, 2). Vibrate only on player-team wins.
	if winner_seat == 0 or winner_seat == 2:
		GameState.vibrate(100)
	_play_trick_collection(winner_seat, books, seat_books)

## Highlight the winning card, pause, then animate all 4 cards toward the
## winner's hand, shrinking as they travel. Books label and trick-win sound
## fire only after the collection animation completes.
func _play_trick_collection(winner_seat: int, books: Array, seat_books: Array = []) -> void:
	var gen := _round_gen
	# Highlight the winning card gold.
	var winner_node: Control = _trick_cards_by_seat.get(winner_seat, null)
	if winner_node != null and is_instance_valid(winner_node):
		winner_node.modulate = Color(1.0, 0.85, 0.15, 1.0)
	# Pause so players can read the completed trick.
	await get_tree().create_timer(
			AnimationManager.TRICK_DISPLAY_PAUSE * Settings.anim_multiplier()
	).timeout
	if _round_gen != gen:
		return
	# Gather the still-living cards.
	var cards: Array = []
	for seat_key in _trick_cards_by_seat.keys():
		var n: Control = _trick_cards_by_seat[seat_key] as Control
		if n != null and is_instance_valid(n):
			cards.append(n)
	# Target = center of the winner's hand container.
	var winner_container := _get_hand_container(winner_seat)
	if winner_container == null:
		_finalize_trick_collection(cards, books, seat_books)
		return
	var target: Vector2 = winner_container.global_position + winner_container.size / 2.0
	var tween := AnimationManager.trick_collect(cards, target, self)
	if tween != null:
		await tween.finished
	if _round_gen != gen:
		return
	_finalize_trick_collection(cards, books, seat_books)

func _finalize_trick_collection(cards: Array, books: Array, seat_books: Array = []) -> void:
	AudioManager.play("trick_win")
	books_label.text = "Books: %d–%d" % [books[0], books[1]]
	_update_avatar_tricks(seat_books)
	for node in cards:
		if is_instance_valid(node):
			(node as Node).queue_free()
	_trick_cards_by_seat.clear()

func _on_round_ended(winning_team: int) -> void:
	AudioManager.play("round_win" if winning_team == 0 else "round_loss")
	var wins := GameState.session_wins
	session_label.text = "Session: %d–%d" % [wins[0], wins[1]]
	if _win_screen_overlay != null:
		_win_screen_overlay.call("show_result", winning_team, wins)

# ── Table management ──────────────────────────────────────────────────────────

func _clear_trick_slots() -> void:
	for slot_name in ["NorthSlot", "WestSlot", "EastSlot", "SouthSlot"]:
		var slot := trick_area.get_node_or_null(slot_name)
		if slot != null:
			for child in slot.get_children():
				child.queue_free()

func _clear_table() -> void:
	for container in [bottom_hand, top_hand, left_hand, right_hand]:
		for child in container.get_children():
			child.queue_free()
	_clear_trick_slots()
	_selected_card = null
	_current_valid_cards.clear()
	trump_label.text = "Trump: —"
	books_label.text = "Books: 0–0"
	turn_label.text = "—'s turn"
	_clear_avatar_tricks()

func _on_round_started(_dealer_seat: int, _trump_selector_seat: int) -> void:
	_round_gen += 1
	_deal_queue.clear()
	_deal_busy = false
	_shuffle_done = false
	_pending_trump_selection.clear()
	_pending_turn.clear()
	_selected_card = null
	_current_valid_cards.clear()
	_new_trick_pending = true
	_initial_deal_done = false
	_awaiting_final_deal = false
	# Drop any stray trick cards left over from a previous round.
	for n in _trick_cards_by_seat.values():
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
	_trick_cards_by_seat.clear()
	_hide_trump_watermark()
	_set_deal_paused(true)
	_clear_table()
	_play_shuffle_animation()

# ── Multiplayer-only event handlers ──────────────────────────────────────────

func _on_seat_taken_over_by_ai(seat: int, display_name: String, reason: String) -> void:
	var verb := "disconnected" if reason == "disconnect" else "left"
	_show_toast("%s %s — AI taking over" % [display_name, verb])
	var avatar = _get_avatar(seat)
	if avatar != null and avatar.has_method("set_player_name"):
		avatar.set_player_name(display_name + " (AI)")

func _on_mp_error_received(code: String, _message: String) -> void:
	if code == Protocol.ERR_HOST_LEFT:
		_show_toast("Host left the room")
		get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")

func _on_mp_connection_changed(state: int) -> void:
	if state == NetworkState.ConnectionState.DISCONNECTED:
		_show_toast("Disconnected from server")
		get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")

func _show_toast(text: String) -> void:
	if toast_label == null:
		return
	toast_label.text = text
	toast_label.modulate.a = 1.0
	toast_label.visible = true
	var tw := create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(toast_label, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func(): toast_label.visible = false)
