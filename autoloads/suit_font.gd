extends Node
## Global suit-symbol font manager.
##
## Loads Noto Sans Symbols + Noto Sans Symbols 2 at startup, chains them
## together, and registers the chain as a fallback on the engine's global
## fallback font. This makes every Label in the project gracefully render
## ♠ ♥ ♦ ♣ and any other unicode symbols, even on Android where the
## default font does not include these glyphs.
##
## Labels that display suit symbols should ALSO call SuitFont.apply(label)
## on _ready as a per-label safety net — this adds a direct font override
## so the chain is guaranteed regardless of the label's theme context.

const SYMBOL_FONT_PATH := "res://assets/fonts/NotoSansSymbols-Regular.ttf"
const SYMBOL2_FONT_PATH := "res://assets/fonts/NotoSansSymbols2-Regular.ttf"

var _chain: FontFile = null

func _ready() -> void:
	var symbols: FontFile = load(SYMBOL_FONT_PATH) as FontFile
	var symbols2: FontFile = load(SYMBOL2_FONT_PATH) as FontFile
	if symbols == null or symbols2 == null:
		push_error("SuitFont: failed to load symbol fonts from %s / %s" % [SYMBOL_FONT_PATH, SYMBOL2_FONT_PATH])
		return
	# Chain: Symbols -> Symbols2 for any glyphs Symbols lacks.
	var inner: Array[Font] = [symbols2]
	symbols.fallbacks = inner
	_chain = symbols
	# Register globally: append the chain to the engine's fallback font so
	# all Labels everywhere inherit the fallback automatically.
	var global_fb: Font = ThemeDB.fallback_font
	if global_fb != null:
		var existing: Array[Font] = []
		if global_fb.fallbacks != null:
			for f in global_fb.fallbacks:
				existing.append(f)
		existing.append(_chain)
		global_fb.fallbacks = existing

## Returns the chained symbol font, or null if loading failed.
func get_font() -> FontFile:
	return _chain

## Applies the symbol-font chain as a theme font override on `ctrl`.
## Safe to call on Labels and Buttons. Call this on any control whose
## text may include ♠ ♥ ♦ ♣ as a per-label safety net.
func apply(ctrl: Control) -> void:
	if _chain == null or ctrl == null:
		return
	ctrl.add_theme_font_override("font", _chain)
