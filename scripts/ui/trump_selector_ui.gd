extends Control

@onready var cards_container: HBoxContainer = $CardsContainer
@onready var spades_btn: Button = $SuitButtons/SpadesBtn
@onready var hearts_btn: Button = $SuitButtons/HeartsBtn
@onready var diamonds_btn: Button = $SuitButtons/DiamondsBtn
@onready var clubs_btn: Button = $SuitButtons/ClubsBtn
@onready var prompt_label: Label = $PromptLabel

const CardScene := preload("res://scenes/card.tscn")

func _ready() -> void:
	spades_btn.pressed.connect(func(): _choose(Card.Suit.SPADES))
	hearts_btn.pressed.connect(func(): _choose(Card.Suit.HEARTS))
	diamonds_btn.pressed.connect(func(): _choose(Card.Suit.DIAMONDS))
	clubs_btn.pressed.connect(func(): _choose(Card.Suit.CLUBS))

func show_for_human(initial_cards: Array) -> void:
	prompt_label.text = "Choose Trump Suit"
	_populate_cards(initial_cards)

func _populate_cards(cards: Array) -> void:
	for child in cards_container.get_children():
		child.queue_free()
	for card in cards:
		var card_node := CardScene.instantiate()
		card_node.call("setup", card, true)
		card_node.call("set_valid", false)  # not tappable during trump selection
		cards_container.add_child(card_node)

func _choose(suit: Card.Suit) -> void:
	GameState.get_round_manager().declare_trump(suit)
