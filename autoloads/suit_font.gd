extends Node
## Global suit-symbol font manager.
##
## Loads Noto Sans Symbols + Noto Sans Symbols 2 at startup by reading the raw
## TTF bytes with FileAccess and feeding them to FontFile.set_data(). This
## completely bypasses Godot's import pipeline and avoids the FreeType
## "Error loading font: ''" spam that occurs with load() or load_dynamic_font()
## on imported .fontdata in Godot 4.6.x.
##
## Labels that display suit symbols should call SuitFont.apply(label)
## on _ready to add the symbol font as a fallback override.

const SYMBOL_FONT_PATH := "res://assets/fonts/raw/NotoSansSymbols-Regular.ttf"
const SYMBOL2_FONT_PATH := "res://assets/fonts/raw/NotoSansSymbols2-Regular.ttf"

var _chain: FontFile = null

func _ready() -> void:
	var symbols := _load_font(SYMBOL_FONT_PATH)
	var symbols2 := _load_font(SYMBOL2_FONT_PATH)
	if symbols == null or symbols2 == null:
		push_warning("SuitFont: failed to load symbol fonts")
		return
	symbols.fallbacks = [symbols2]
	_chain = symbols

func _load_font(path: String) -> FontFile:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("SuitFont: cannot open %s: %d" % [path, FileAccess.get_open_error()])
		return null
	var data := f.get_buffer(f.get_length())
	f.close()
	var ff := FontFile.new()
	ff.data = data
	return ff

## Returns the chained symbol font, or null if loading failed.
func get_font() -> FontFile:
	return _chain

## Applies the symbol-font chain as a theme font override on `ctrl`.
func apply(ctrl: Control) -> void:
	if _chain == null or ctrl == null:
		return
	ctrl.add_theme_font_override("font", _chain)
