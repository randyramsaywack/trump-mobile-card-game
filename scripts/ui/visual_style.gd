class_name VisualStyle
extends RefCounted

const GOLD := Color(0.95, 0.78, 0.28, 1.0)
const GOLD_DIM := Color(0.78, 0.60, 0.22, 0.72)
const GOLD_SOFT := Color(1.0, 0.88, 0.46, 1.0)
const FELT_DARK := Color(0.025, 0.105, 0.055, 1.0)
const PANEL := Color(0.025, 0.13, 0.075, 0.92)
const PANEL_DARK := Color(0.01, 0.065, 0.04, 0.94)
const FIELD := Color(0.015, 0.075, 0.045, 0.78)
const TEXT := Color(0.94, 0.92, 0.84, 1.0)
const TEXT_DIM := Color(0.76, 0.74, 0.66, 0.86)
const RED := Color(0.72, 0.10, 0.07, 1.0)

static var felt_texture: Texture2D = null

static func apply_felt_background(root: Control) -> void:
	if felt_texture == null:
		var loaded := ResourceLoader.load("res://assets/ui/felt_background.png")
		if loaded is Texture2D:
			felt_texture = loaded as Texture2D
		else:
			var img := Image.new()
			var err := img.load("res://assets/ui/felt_background.png")
			if err == OK:
				felt_texture = ImageTexture.create_from_image(img)
	var existing := root.get_node_or_null("FeltBackground") as TextureRect
	if existing == null:
		existing = TextureRect.new()
		existing.name = "FeltBackground"
		existing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		existing.texture = felt_texture
		existing.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		existing.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		existing.anchors_preset = Control.PRESET_FULL_RECT
		existing.anchor_right = 1.0
		existing.anchor_bottom = 1.0
		root.add_child(existing)
		root.move_child(existing, 0)
	else:
		existing.texture = felt_texture
	var flat_bg := root.get_node_or_null("Background")
	if flat_bg is ColorRect:
		(flat_bg as ColorRect).color = Color(0, 0, 0, 0)
		(flat_bg as ColorRect).mouse_filter = Control.MOUSE_FILTER_IGNORE

static func panel_style(alpha: float = 0.94, radius: int = 8, border_alpha: float = 0.9) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(PANEL.r, PANEL.g, PANEL.b, alpha)
	style.border_color = Color(GOLD.r, GOLD.g, GOLD.b, border_alpha)
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 14
	style.content_margin_top = 12
	style.content_margin_right = 14
	style.content_margin_bottom = 12
	style.shadow_color = Color(0, 0, 0, 0.42)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 3)
	return style

static func button_style(kind: String = "normal", pressed: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var bg := PANEL_DARK
	var border := GOLD_DIM
	if kind == "primary":
		bg = Color(0.05, 0.30, 0.12, 0.96) if not pressed else Color(0.92, 0.64, 0.15, 1.0)
		border = GOLD
	elif kind == "danger":
		bg = Color(0.34, 0.03, 0.03, 0.96) if not pressed else Color(0.54, 0.06, 0.06, 1.0)
		border = Color(0.92, 0.26, 0.18, 0.95)
	elif kind == "segment":
		bg = Color(0.02, 0.09, 0.055, 0.88) if not pressed else Color(0.92, 0.66, 0.18, 1.0)
		border = GOLD_DIM if not pressed else GOLD
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.content_margin_left = 10
	style.content_margin_top = 8
	style.content_margin_right = 10
	style.content_margin_bottom = 8
	return style

static func field_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = FIELD
	style.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.42)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_top = 8
	style.content_margin_right = 10
	style.content_margin_bottom = 8
	return style

static func apply_button(button: Button, kind: String = "normal") -> void:
	button.add_theme_stylebox_override("normal", button_style(kind, false))
	button.add_theme_stylebox_override("hover", button_style(kind, true))
	button.add_theme_stylebox_override("pressed", button_style(kind, true))
	button.add_theme_stylebox_override("focus", button_style(kind, true))
	button.add_theme_color_override("font_color", GOLD_SOFT if kind != "danger" else Color(1, 0.88, 0.82, 1))
	button.add_theme_color_override("font_hover_color", Color(1, 0.96, 0.70, 1))
	button.add_theme_font_size_override("font_size", 15)

static func apply_line_edit(edit: LineEdit) -> void:
	edit.add_theme_stylebox_override("normal", field_style())
	edit.add_theme_stylebox_override("focus", field_style())
	edit.add_theme_color_override("font_color", TEXT)
	edit.add_theme_color_override("font_placeholder_color", Color(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.55))
	edit.add_theme_font_size_override("font_size", 14)

static func apply_label(label: Label, size: int = 14, color: Color = TEXT) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)

static func apply_title(label: Label, size: int = 34) -> void:
	label.add_theme_color_override("font_color", GOLD_SOFT)
	label.add_theme_color_override("font_outline_color", Color(0.22, 0.13, 0.025, 0.95))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 3)
	label.add_theme_font_size_override("font_size", size)
