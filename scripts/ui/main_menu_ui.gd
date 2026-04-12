extends Control

@onready var single_player_btn: Button = $CenterLayout/SinglePlayerBtn
@onready var multiplayer_btn: Button = $CenterLayout/MultiplayerBtn
@onready var options_btn: Button = $CenterLayout/OptionsBtn
@onready var stats_btn: Button = $CenterLayout/StatsBtn
@onready var how_to_play_btn: Button = $CenterLayout/HowToPlayBtn
@onready var credits_btn: Button = $CenterLayout/CreditsBtn
@onready var title_label: Label = $CenterLayout/TitleLabel
@onready var subtitle_label: Label = $CenterLayout/SubtitleLabel
@onready var spades_suit: Label = $CenterLayout/DividerRow/Spades
@onready var hearts_suit: Label = $CenterLayout/DividerRow/Hearts
@onready var diamonds_suit: Label = $CenterLayout/DividerRow/Diamonds
@onready var clubs_suit: Label = $CenterLayout/DividerRow/Clubs

const SettingsOverlayScene := preload("res://scenes/ui/settings_overlay.tscn")
const StatsOverlayScene := preload("res://scenes/ui/stats_overlay.tscn")
const HowToPlayOverlayScene := preload("res://scenes/ui/how_to_play_overlay.tscn")
const CreditsOverlayScene := preload("res://scenes/ui/credits_overlay.tscn")

var _settings_overlay: Control = null
var _stats_overlay: Control = null
var _how_to_play_overlay: Control = null
var _credits_overlay: Control = null

func _ready() -> void:
	# Load decorative fonts via raw bytes to bypass Godot's broken fontdata import (4.6.x).
	# The .ttf files use the "keep" importer (see .import sidecars) so the raw
	# bytes are bundled as-is in the exported PCK.
	_apply_raw_font(title_label, "res://assets/fonts/raw/CinzelDecorative-Bold.ttf")
	_apply_raw_font(subtitle_label, "res://assets/fonts/raw/Cinzel-Bold.ttf")
	# Safety net: ensure suit glyphs render on all platforms.
	SuitFont.apply(spades_suit)
	SuitFont.apply(hearts_suit)
	SuitFont.apply(diamonds_suit)
	SuitFont.apply(clubs_suit)
	single_player_btn.pressed.connect(_on_single_player)
	multiplayer_btn.pressed.connect(_on_multiplayer)
	options_btn.pressed.connect(_on_options)
	stats_btn.pressed.connect(_on_stats)
	how_to_play_btn.pressed.connect(_on_how_to_play)
	credits_btn.pressed.connect(_on_credits)

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

func _on_multiplayer() -> void:
	var err := get_tree().change_scene_to_file("res://scenes/ui/multiplayer_menu.tscn")
	if err != OK:
		push_error("MainMenu: failed to load multiplayer_menu.tscn, error: %d" % err)

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

## Load a TTF via raw FileAccess and apply as theme font override.
## Bypasses Godot's import pipeline which produces broken .fontdata in 4.6.x.
func _apply_raw_font(ctrl: Control, path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("MainMenu: cannot open font %s" % path)
		return
	var ff := FontFile.new()
	ff.data = f.get_buffer(f.get_length())
	f.close()
	ctrl.add_theme_font_override("font", ff)
