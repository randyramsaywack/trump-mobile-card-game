extends Control

## Waiting room. Reacts to NetworkState.room_state_changed to re-render seats.
## Host sees an enabled Start button; everyone else sees it hidden.

@onready var code_label: Label = $Center/CodeLabel
@onready var seat_labels: Array[Label] = [
	$Center/Seat0,
	$Center/Seat1,
	$Center/Seat2,
	$Center/Seat3,
]
@onready var start_button: Button = $Center/StartButton
@onready var leave_button: Button = $Center/LeaveButton
@onready var copy_button: Button = $Center/CopyButton

func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	leave_button.pressed.connect(_leave)
	copy_button.pressed.connect(_on_copy_pressed)
	NetworkState.room_state_changed.connect(_render)
	NetworkState.connection_state_changed.connect(_on_connection_state_changed)
	NetworkState.error_received.connect(_on_error_received)
	_render()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_leave()

func _render() -> void:
	code_label.text = NetworkState.room_code if NetworkState.room_code != "" else "------"
	copy_button.disabled = NetworkState.room_code == ""
	var by_seat := {}
	for p in NetworkState.players:
		by_seat[int(p["seat"])] = p
	for i in 4:
		var label := seat_labels[i]
		if by_seat.has(i):
			var p: Dictionary = by_seat[i]
			var suffix := " (Host)" if bool(p["is_host"]) else ""
			label.text = "Seat %d: %s%s" % [i + 1, String(p["username"]), suffix]
		else:
			label.text = "Seat %d: Empty — AI will fill" % [i + 1]
	start_button.visible = NetworkState.is_host
	# Per CLAUDE.md: Start is enabled only when 2+ humans are in the room.
	# Empty seats will be filled with AI when game logic lands.
	start_button.disabled = NetworkState.players.size() < 2

func _on_start_pressed() -> void:
	NetworkState.start_game()

func _on_copy_pressed() -> void:
	if NetworkState.room_code == "":
		return
	DisplayServer.clipboard_set(NetworkState.room_code)
	_show_toast("Code copied to clipboard")

func _on_connection_state_changed(state: int) -> void:
	if state == NetworkState.ConnectionState.DISCONNECTED:
		_show_toast("Disconnected from server")
		_return_to_main_menu()

func _on_error_received(code: String, message: String) -> void:
	if code == Protocol.ERR_HOST_LEFT:
		_show_toast(message)
		_return_to_main_menu()

func _leave() -> void:
	NetworkState.leave_room()
	_return_to_main_menu()

func _return_to_main_menu() -> void:
	# Defer so we don't change scenes mid-signal.
	get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")

## Simple auto-dismissing toast without a dedicated node — creates a Label
## overlay, fades it out, frees itself. Sufficient for milestone 1.
func _show_toast(text: String) -> void:
	var toast := Label.new()
	toast.text = text
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_font_size_override("font_size", 16)
	toast.add_theme_color_override("font_color", Color(1, 0.95, 0.7, 1))
	toast.anchor_left = 0.1
	toast.anchor_right = 0.9
	toast.anchor_top = 0.05
	toast.anchor_bottom = 0.12
	add_child(toast)
	var tw := create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(toast, "modulate:a", 0.0, 0.3)
	tw.tween_callback(toast.queue_free)
