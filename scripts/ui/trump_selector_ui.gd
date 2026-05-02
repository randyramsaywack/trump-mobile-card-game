extends Control

const VisualStyle := preload("res://scripts/ui/visual_style.gd")

@onready var background: ColorRect = $Background
@onready var cards_container: HBoxContainer = $CardsContainer
@onready var suit_buttons: HBoxContainer = $SuitButtons
@onready var spades_btn: Button = $SuitButtons/SpadesBtn
@onready var hearts_btn: Button = $SuitButtons/HeartsBtn
@onready var diamonds_btn: Button = $SuitButtons/DiamondsBtn
@onready var clubs_btn: Button = $SuitButtons/ClubsBtn
@onready var prompt_label: Label = $PromptLabel
@onready var sheet: PanelContainer = $Sheet

const CardScene := preload("res://scenes/card.tscn")
const SLIDE_OFFSET := 30.0
const CARD_GAP := 8.0
const SUIT_BUTTON_GAP := 6.0

var _anim_tween: Tween = null
var _selector_card_size: Vector2 = Vector2(60, 90)
var _selector_button_size: Vector2 = Vector2(64, 54)

func _ready() -> void:
	_apply_mockup_style()
	# Safety net: ensure suit glyphs render on all platforms.
	SuitFont.apply(spades_btn)
	SuitFont.apply(hearts_btn)
	SuitFont.apply(diamonds_btn)
	SuitFont.apply(clubs_btn)
	spades_btn.pressed.connect(func(): _choose(Card.Suit.SPADES))
	hearts_btn.pressed.connect(func(): _choose(Card.Suit.HEARTS))
	diamonds_btn.pressed.connect(func(): _choose(Card.Suit.DIAMONDS))
	clubs_btn.pressed.connect(func(): _choose(Card.Suit.CLUBS))
	_apply_layout_sizing()
	get_viewport().size_changed.connect(_apply_layout_sizing)
	if "--shot-trump-select" in OS.get_cmdline_user_args():
		call_deferred("_show_screenshot_sample")

func _apply_mockup_style() -> void:
	VisualStyle.apply_felt_background(self)
	background.color = Color(0, 0, 0, 0.12)
	sheet.anchor_left = 0.04
	sheet.anchor_top = 0.08
	sheet.anchor_right = 0.96
	sheet.anchor_bottom = 0.92
	sheet.add_theme_stylebox_override("panel", VisualStyle.panel_style(0.20, 10, 0.25))
	prompt_label.text = "SELECT TRUMP"
	VisualStyle.apply_title(prompt_label, 24)
	prompt_label.anchor_top = 0.10
	prompt_label.anchor_bottom = 0.18
	cards_container.anchor_top = 0.30
	cards_container.anchor_bottom = 0.46
	suit_buttons.anchor_top = 0.58
	suit_buttons.anchor_bottom = 0.66
	for btn in [spades_btn, hearts_btn, diamonds_btn, clubs_btn]:
		VisualStyle.apply_button(btn, "normal")
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER

func _apply_layout_sizing() -> void:
	var vp_w: float = get_viewport_rect().size.x
	var content_w: float = maxf(1.0, vp_w * 0.9)
	var card_w := floorf(clampf((content_w - (4.0 * CARD_GAP)) / 5.0, 46.0, 60.0))
	_selector_card_size = Vector2(card_w, roundf(card_w * 1.5))
	var button_w := floorf(clampf((content_w - (3.0 * SUIT_BUTTON_GAP)) / 4.0, 62.0, 76.0))
	_selector_button_size = Vector2(button_w, 54.0)
	for button in [spades_btn, hearts_btn, diamonds_btn, clubs_btn]:
		button.custom_minimum_size = _selector_button_size
		button.add_theme_font_size_override("font_size", 12 if button_w < 70.0 else 14)
	for child in cards_container.get_children():
		(child as Control).custom_minimum_size = _selector_card_size

func show_for_human(initial_cards: Array) -> void:
	prompt_label.text = "SELECT TRUMP"
	_populate_cards(initial_cards)

func _show_screenshot_sample() -> void:
	show_for_human([
		Card.new(Card.Suit.HEARTS, Card.Rank.ACE),
		Card.new(Card.Suit.HEARTS, Card.Rank.QUEEN),
		Card.new(Card.Suit.SPADES, Card.Rank.TEN),
		Card.new(Card.Suit.DIAMONDS, Card.Rank.NINE),
		Card.new(Card.Suit.CLUBS, Card.Rank.FIVE),
	])
	visible = true

func animate_show() -> void:
	_kill_tween()
	visible = true
	var dur := 0.2 * Settings.anim_multiplier()
	background.modulate.a = 0.0
	var content_nodes: Array[Control] = [prompt_label, cards_container, suit_buttons]
	# Capture base positions (anchor-derived) before offsetting.
	var base_y: Array[float] = []
	for node: Control in content_nodes:
		base_y.append(node.position.y)
		node.modulate.a = 0.0
		node.position.y = node.position.y + SLIDE_OFFSET
	_anim_tween = create_tween().set_parallel(true)
	_anim_tween.tween_property(background, "modulate:a", 1.0, dur)
	for i in content_nodes.size():
		var node: Control = content_nodes[i]
		_anim_tween.tween_property(node, "modulate:a", 1.0, dur)
		_anim_tween.tween_property(node, "position:y", base_y[i], dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

func animate_hide() -> void:
	_kill_tween()
	var dur := 0.15 * Settings.anim_multiplier()
	var content_nodes: Array[Control] = [prompt_label, cards_container, suit_buttons]
	var base_y: Array[float] = []
	for node: Control in content_nodes:
		base_y.append(node.position.y)
	_anim_tween = create_tween().set_parallel(true)
	_anim_tween.tween_property(background, "modulate:a", 0.0, dur)
	for i in content_nodes.size():
		var node: Control = content_nodes[i]
		_anim_tween.tween_property(node, "modulate:a", 0.0, dur)
		_anim_tween.tween_property(node, "position:y", node.position.y + SLIDE_OFFSET, dur).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	# Reset positions and hide after animation completes.
	_anim_tween.chain().tween_callback(func():
		for j in content_nodes.size():
			content_nodes[j].position.y = base_y[j]
		visible = false
	)

func _kill_tween() -> void:
	if _anim_tween != null and _anim_tween.is_valid():
		_anim_tween.kill()

func _populate_cards(cards: Array) -> void:
	for child in cards_container.get_children():
		child.queue_free()
	for card in cards:
		var card_node := CardScene.instantiate() as Control
		card_node.call("setup", card, true)
		# Display only — block interaction without dimming via set_valid.
		card_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_node.custom_minimum_size = _selector_card_size
		card_node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		card_node.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cards_container.add_child(card_node)

func _choose(suit: Card.Suit) -> void:
	if GameState.multiplayer_mode:
		NetworkState.declare_trump(suit)
	else:
		GameState.get_round_manager().declare_trump(suit)
