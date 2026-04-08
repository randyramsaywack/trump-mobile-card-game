extends Control

@onready var single_player_btn: Button = $CenterLayout/SinglePlayerBtn
@onready var multiplayer_btn: Button = $CenterLayout/MultiplayerBtn
@onready var options_btn: Button = $CenterLayout/OptionsBtn
@onready var stats_btn: Button = $CenterLayout/StatsBtn
@onready var how_to_play_btn: Button = $CenterLayout/HowToPlayBtn
@onready var credits_btn: Button = $CenterLayout/CreditsBtn
@onready var spades_suit: Label = $CenterLayout/SuitRow/Spades
@onready var hearts_suit: Label = $CenterLayout/SuitRow/Hearts
@onready var diamonds_suit: Label = $CenterLayout/SuitRow/Diamonds
@onready var clubs_suit: Label = $CenterLayout/SuitRow/Clubs

const SettingsOverlayScene := preload("res://scenes/ui/settings_overlay.tscn")
const StatsOverlayScene := preload("res://scenes/ui/stats_overlay.tscn")
const HowToPlayOverlayScene := preload("res://scenes/ui/how_to_play_overlay.tscn")
const CreditsOverlayScene := preload("res://scenes/ui/credits_overlay.tscn")

var _settings_overlay: Control = null
var _stats_overlay: Control = null
var _how_to_play_overlay: Control = null
var _credits_overlay: Control = null

func _ready() -> void:
	# Safety net: ensure suit glyphs render on all platforms.
	SuitFont.apply(spades_suit)
	SuitFont.apply(hearts_suit)
	SuitFont.apply(diamonds_suit)
	SuitFont.apply(clubs_suit)
	single_player_btn.pressed.connect(_on_single_player)
	options_btn.pressed.connect(_on_options)
	stats_btn.pressed.connect(_on_stats)
	how_to_play_btn.pressed.connect(_on_how_to_play)
	credits_btn.pressed.connect(_on_credits)
	multiplayer_btn.disabled = true

## Android hardware back button. Closes any open overlay, otherwise quits.
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	if _settings_overlay != null and _settings_overlay.visible:
		_settings_overlay.visible = false
		return
	if _stats_overlay != null and _stats_overlay.visible:
		_stats_overlay.visible = false
		return
	if _how_to_play_overlay != null and _how_to_play_overlay.visible:
		_how_to_play_overlay.visible = false
		return
	if _credits_overlay != null and _credits_overlay.visible:
		_credits_overlay.visible = false
		return
	get_tree().quit()

func _on_single_player() -> void:
	var err := get_tree().change_scene_to_file("res://scenes/game_table.tscn")
	if err != OK:
		push_error("MainMenu: failed to load game_table.tscn, error: %d" % err)

func _on_options() -> void:
	if _settings_overlay == null:
		_settings_overlay = SettingsOverlayScene.instantiate()
		add_child(_settings_overlay)
		# Hide the Main Menu button since we're already on the main menu
		var main_menu_btn := _settings_overlay.get_node_or_null("Panel/VBox/MainMenuButton") as Button
		if main_menu_btn != null:
			main_menu_btn.visible = false
		_settings_overlay.connect("closed", func(): _settings_overlay.visible = false)
	_settings_overlay.visible = true

func _on_stats() -> void:
	if _stats_overlay == null:
		_stats_overlay = StatsOverlayScene.instantiate()
		add_child(_stats_overlay)
		_stats_overlay.connect("closed", func(): _stats_overlay.visible = false)
	_stats_overlay.visible = true

func _on_how_to_play() -> void:
	if _how_to_play_overlay == null:
		_how_to_play_overlay = HowToPlayOverlayScene.instantiate()
		add_child(_how_to_play_overlay)
		_how_to_play_overlay.connect("closed", func(): _how_to_play_overlay.visible = false)
	_how_to_play_overlay.visible = true

func _on_credits() -> void:
	if _credits_overlay == null:
		_credits_overlay = CreditsOverlayScene.instantiate()
		add_child(_credits_overlay)
		_credits_overlay.connect("closed", func(): _credits_overlay.visible = false)
	_credits_overlay.visible = true
