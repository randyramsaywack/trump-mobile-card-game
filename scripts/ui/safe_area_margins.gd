class_name SafeAreaMargins
extends Control

@export var base_gutter: float = 8.0

func _ready() -> void:
	_apply()
	get_viewport().size_changed.connect(_apply)

func _apply() -> void:
	var safe := DisplayServer.get_display_safe_area()
	var win_size := DisplayServer.window_get_size()
	var vp_size := get_viewport_rect().size
	var top := base_gutter
	var bottom := base_gutter
	var left := base_gutter
	var right := base_gutter
	if safe.size.x > 0 and safe.size.y > 0 and win_size.x > 0 and win_size.y > 0:
		var sx := vp_size.x / float(win_size.x)
		var sy := vp_size.y / float(win_size.y)
		left = maxf(base_gutter, float(safe.position.x) * sx + base_gutter)
		top = maxf(base_gutter, float(safe.position.y) * sy + base_gutter)
		right = maxf(base_gutter, float(win_size.x - (safe.position.x + safe.size.x)) * sx + base_gutter)
		bottom = maxf(base_gutter, float(win_size.y - (safe.position.y + safe.size.y)) * sy + base_gutter)
	offset_left = left
	offset_top = top
	offset_right = -right
	offset_bottom = -bottom
