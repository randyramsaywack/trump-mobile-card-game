# UI Polish & Main Menu — Design Spec

**Date:** 2026-04-04  
**Status:** Approved  

---

## Goal

Fix three problems with the current single-player build:
1. Cards look like plain text boxes; hands overflow the screen
2. The game crashes when pressing "Main Menu" after a round win
3. There is no main menu — the game jumps straight into a round

Deliver: a properly laid-out game table with classic white playing cards in a fan/overlap hand, a casino-green main menu, and a crash-free win screen.

---

## Visual Decisions (user-approved)

| Decision | Choice |
|---|---|
| Card face style | Classic white — rank top-left/bottom-right, large center suit, black/red by suit |
| Card back | Navy blue gradient, subtle cross-hatch border |
| Card hand layout | Fan/overlap — all 13 cards visible, ~16px offset per card |
| Table background | Casino green felt — radial gradient `#2d6a4f → #1a4a35` |
| Main menu style | Classic card table — green felt, serif TRUMP title, decorative corner cards |
| Turn timer | Present in HUD layout, hidden in single player, shown in multiplayer |

---

## Architecture

### Theme resource
A single `assets/ui/theme.tres` is created and applied to the root node of both `main_menu.tscn` and `game_table.tscn`. All child nodes inherit from it. This centralises:
- Card StyleBox (white fill, 6px radius, 1px `#cccccc` border, drop shadow)
- HUD Label font sizes (13px row 1, 11px row 2)
- Button normal/hover/pressed states (green felt palette)

No script logic reads from the theme — it is purely visual.

### Scene ownership of game start
`game_table_ui.gd` calls `GameState.start_session()` in its `_ready()`. The main menu navigates to `game_table.tscn` via `get_tree().change_scene_to_file(...)`. This means every arrival at the game table is a fresh session — no shared state between menu and game.

### Win screen navigation
`win_screen_ui._on_main_menu()` calls `get_tree().change_scene_to_file("res://scenes/main_menu.tscn")`. This was previously `reload_current_scene()` which reloaded `game_table.tscn` (wrong scene, and caused signal re-connection crashes). Changing to an explicit scene path fixes the crash and delivers the user to the real menu.

---

## Files Changed / Created

| File | Action | Notes |
|---|---|---|
| `assets/ui/theme.tres` | Create | Godot Theme resource, applied globally |
| `scenes/main_menu.tscn` | Create | New main menu scene |
| `scripts/ui/main_menu_ui.gd` | Create | Main menu script |
| `scenes/card.tscn` | Rewrite | New card layout with proper face/back structure |
| `scripts/ui/card_ui.gd` | Rewrite | Renders rank corners + center suit; handles face-up/down |
| `scenes/game_table.tscn` | Rewrite | New layout: 2-row HUD, compass trick area, fan hands |
| `scripts/ui/game_table_ui.gd` | Edit | Wire up new node paths; no structural logic changes |
| `scenes/ui/win_screen.tscn` | Edit | Minor layout touch-up only |
| `scripts/ui/win_screen_ui.gd` | Edit | Fix `_on_main_menu()` to use `change_scene_to_file` |
| `project.godot` | Edit | Change `config/run/main_scene` to `main_menu.tscn` |

---

## Detailed Design

### 1. Theme resource — `assets/ui/theme.tres`

Created as a Godot `Theme` resource. Key overrides:

**StyleBoxFlat "CardFace"**
- `bg_color`: `Color(1, 1, 1)` (white)
- `corner_radius_*`: 6
- `border_width_*`: 1, `border_color`: `Color(0.78, 0.78, 0.78)`
- `shadow_color`: `Color(0, 0, 0, 0.18)`, `shadow_size`: 3, `shadow_offset`: `Vector2(1, 2)`

**StyleBoxFlat "CardBack"**
- `bg_color`: `Color(0.1, 0.22, 0.42)` (navy)
- `corner_radius_*`: 6
- `border_width_*`: 1, `border_color`: `Color(0.2, 0.35, 0.6)`

**Button styles** — normal/hover/pressed use the green felt palette with white text.

### 2. Main Menu — `scenes/main_menu.tscn` + `scripts/ui/main_menu_ui.gd`

**Scene tree:**
```
Control (root, full-rect, theme applied)
  ColorRect "Background"         ← green felt radial gradient via shader or ColorRect
  TextureRect "CardLeft"         ← decorative A♥ card, rotated -15°, top-left
  TextureRect "CardRight"        ← decorative K♠ card, rotated +15°, top-right
  VBoxContainer "CenterLayout"   ← centered, ~80% width
    Label "TitleLabel"           ← "TRUMP", serif-style, large, white
    Label "SubtitleLabel"        ← "CARD GAME", small caps, muted white
    HBoxContainer "SuitRow"      ← ♠ ♥ ♦ ♣ spaced evenly, semi-transparent
    Button "SinglePlayerBtn"     ← "Single Player", full-width, white fill
    Button "MultiplayerBtn"      ← "Multiplayer", ghost style, disabled, "coming soon"
```

**`main_menu_ui.gd`:**
```gdscript
extends Control

@onready var single_player_btn: Button = $CenterLayout/SinglePlayerBtn
@onready var multiplayer_btn: Button = $CenterLayout/MultiplayerBtn

func _ready() -> void:
    single_player_btn.pressed.connect(_on_single_player)
    multiplayer_btn.disabled = true

func _on_single_player() -> void:
    get_tree().change_scene_to_file("res://scenes/game_table.tscn")
```

**Background:** A `ColorRect` fills the screen. Its color is set to `Color(0.18, 0.42, 0.31)` as a base. A `CanvasLayer` or shader adds the radial darkening toward edges. Simplest approach: use two stacked `ColorRect` nodes — solid green base + a radial vignette using a `ShaderMaterial` with a simple radial gradient fragment shader, or just accept a solid dark green if shader is too complex.

> **Simplification rule:** If the radial gradient requires a shader and adds implementation complexity, use a solid `Color(0.13, 0.35, 0.24)` instead. The felt effect is nice but not required.

**Decorative cards:** Two `PanelContainer` nodes using the CardFace StyleBox, instantiated directly in the scene (not from `card.tscn`) with hardcoded label text. Positioned absolutely, rotated ±15°. These are purely decorative — no script interaction.

### 3. Card visual — `scenes/card.tscn` + `scripts/ui/card_ui.gd`

**Card size:** `custom_minimum_size = Vector2(52, 78)` for trick area and trump selector. The fan layout script further constrains display width via overlap.

**Scene tree (face-up):**
```
PanelContainer "CardUI"         ← StyleBoxFlat CardFace applied
  MarginContainer               ← 4px margins all sides
    Control "FaceContent"
      Label "TopRank"           ← top-left, font size 13, bold
      Label "TopSuit"           ← below TopRank, font size 10
      Label "CenterSuit"        ← centered, font size 32
      Label "BottomRank"        ← bottom-right, rotated 180°, font size 13
      Label "BottomSuit"        ← above BottomRank (rotated), font size 10
  Control "BackContent"         ← visible only when face-down
    ColorRect "BackFill"        ← navy, full-rect
    ColorRect "BackBorder"      ← inner inset border for cross-hatch look
```

`card_ui.gd` toggles `FaceContent.visible` / `BackContent.visible` in `setup()`.

**Color rules:**
- `Card.Suit.HEARTS`, `Card.Suit.DIAMONDS` → `Color(0.78, 0.08, 0.08)`
- `Card.Suit.SPADES`, `Card.Suit.CLUBS` → `Color(0.05, 0.05, 0.05)`

**`set_valid(false)`:** `modulate.a = 0.45` (dimmed). In trump selector overlay, cards are shown at full opacity since they inform the choice — `set_valid(true)` is called on all 5 cards there.

**`set_selected(true)`:** `position.y -= 15.0` (pops up within the fan container).

### 4. Fan hand layout

Bottom hand uses a custom `HandFan` Control script (`scripts/ui/hand_fan.gd`) attached to the `BottomHand` node. It overrides `_notification(NOTIFICATION_SORT_CHILDREN)` to manually position children:

```gdscript
const OVERLAP_OFFSET := 16  # px per card
const CARD_WIDTH := 52

func _notification(what: int) -> void:
    if what == NOTIFICATION_SORT_CHILDREN:
        var n := get_child_count()
        if n == 0:
            return
        var total_width := CARD_WIDTH + (n - 1) * OVERLAP_OFFSET
        var start_x := (size.x - total_width) / 2.0
        for i in range(n):
            var child := get_child(i) as Control
            if child == null:
                continue
            fit_child_in_rect(child, Rect2(start_x + i * OVERLAP_OFFSET, 0, CARD_WIDTH, size.y))
            child.z_index = i  # rightmost card on top
```

The `BottomHand` node in `game_table.tscn` uses `hand_fan.gd` as its script. `game_table_ui.gd` adds child cards to it exactly as before — no change to the signal/card logic.

Top hand (partner) uses the same `HandFan` script but cards are smaller (`custom_minimum_size = Vector2(26, 38)`) and face-down. Left and right hands use a `VHandFan` variant with vertical stacking.

**`VHandFan`** (`scripts/ui/v_hand_fan.gd`) — same pattern but vertical:
```gdscript
const OVERLAP_OFFSET := 10  # px per card vertically
const CARD_HEIGHT := 38

func _notification(what: int) -> void:
    if what == NOTIFICATION_SORT_CHILDREN:
        var n := get_child_count()
        if n == 0:
            return
        var total_height := CARD_HEIGHT + (n - 1) * OVERLAP_OFFSET
        var start_y := (size.y - total_height) / 2.0
        for i in range(n):
            var child := get_child(i) as Control
            if child == null:
                continue
            fit_child_in_rect(child, Rect2(0, start_y + i * OVERLAP_OFFSET, size.x, CARD_HEIGHT))
            child.z_index = i
```

### 5. Game table layout — `scenes/game_table.tscn`

**Viewport:** 390×844px portrait.

**Scene tree:**
```
Control "GameTable" (root, full-rect, theme applied)
  ColorRect "Background"          ← green felt, full-rect, z=-1
  VBoxContainer "HUD"             ← anchor top, full width, 44px height
    HBoxContainer "HUDRow1"       ← Trump label (left) + Books label (right)
      Label "TrumpLabel"
      Label "BooksLabel"
    HBoxContainer "HUDRow2"       ← Session label + Turn label + Timer label
      Label "SessionLabel"
      Label "TurnLabel"
      Label "TimerLabel"          ← hidden in single player
  Label "NorthName"               ← "North", below HUD, centered
  Control "TopHand"               ← script: hand_fan.gd, anchor top-center area
  HBoxContainer "MidRow"          ← fills middle area
    Control "LeftHand"            ← script: v_hand_fan.gd
    Label "WestName"              ← "West", rotated -90°
    Control "TrickArea"           ← 2×2 grid via GridContainer
    Label "EastName"              ← "East", rotated 90°
    Control "RightHand"           ← script: v_hand_fan.gd
  Label "SouthName"               ← "You", above bottom hand
  Control "BottomHand"            ← script: hand_fan.gd, anchor bottom
```

**Trick area (`TrickArea`):** A `GridContainer` with 2 columns. Cards are added in seat order: top-left slot = partner (seat 1), top-right = empty placeholder, bottom-left = left opponent (seat 2)... 

Actually, simpler: use 4 fixed `Control` slots (North, West, East, South) positioned absolutely in a compass arrangement. Each slot holds one card or is empty.

**Revised TrickArea:**
```
Control "TrickArea"               ← 160×160px centered
  Control "NorthSlot"             ← top-center
  Control "WestSlot"              ← left-center
  Control "EastSlot"              ← right-center
  Control "SouthSlot"             ← bottom-center
```

`game_table_ui.gd` tracks which seat maps to which slot and places cards accordingly.

**Anchor values (approximate, fine-tuned in implementation):**

| Node | anchor_top | anchor_bottom | anchor_left | anchor_right |
|---|---|---|---|---|
| HUD | 0.0 | 0.0 | 0.0 | 1.0 (offset_bottom=44) |
| TopHand | 0.0 | 0.0 | 0.1 | 0.9 (offset_top=50, offset_bottom=100) |
| MidRow | 0.0 | 1.0 | 0.0 | 1.0 (offset_top=106, offset_bottom=-110) |
| BottomHand | 1.0 | 1.0 | 0.0 | 1.0 (offset_top=-100) |

### 6. `game_table_ui.gd` changes

Only the node paths that changed need updating. Signal logic, card play, and GameState wiring are unchanged.

New `@onready` for `TimerLabel`:
```gdscript
@onready var timer_label: Label = $HUD/HUDRow2/TimerLabel
```

New method for trick area compass placement:
```gdscript
func _get_trick_slot(seat: int) -> Control:
    match seat:
        0: return $TrickArea/SouthSlot
        1: return $TrickArea/NorthSlot
        2: return $TrickArea/WestSlot
        3: return $TrickArea/EastSlot
    return null
```

`_on_card_played` adds the card to the compass slot instead of a flat HBoxContainer:
```gdscript
func _on_card_played(seat: int, card: Card) -> void:
    # remove from hand ...
    var slot := _get_trick_slot(seat)
    if slot != null:
        var trick_card := CardScene.instantiate()
        trick_card.call("setup", card, true)
        slot.add_child(trick_card)
```

### 7. Win screen fix — `scripts/ui/win_screen_ui.gd`

Single line change:
```gdscript
# Before:
func _on_main_menu() -> void:
    get_tree().reload_current_scene()

# After:
func _on_main_menu() -> void:
    get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
```

### 8. project.godot change

```ini
# Before:
config/run/main_scene="res://scenes/game_table.tscn"

# After:
config/run/main_scene="res://scenes/main_menu.tscn"
```

---

## Spec Self-Review

**Placeholder scan:** No TBDs. The shader/radial gradient has an explicit simplification fallback (solid color). The `HandFan` notification pattern is fully specified.

**Internal consistency:** 
- `game_table_ui.gd` references `$TrickArea/SouthSlot` etc — these must exist in the new `game_table.tscn`. ✓ Specified in scene tree.
- `hand_fan.gd` is attached to `BottomHand` and `TopHand` nodes, `v_hand_fan.gd` to `LeftHand` and `RightHand`. ✓ Consistent.
- Card size 52×78px in trick area / trump selector; fan layout further constrains via overlap. ✓ No conflict.

**Scope check:** Single plan covers: main menu, card redesign, layout, win crash fix, theme resource. All changes are coupled to the same visual overhaul and belong together.

**Ambiguity fixes:**
- "Decorative cards in main menu corners" — specified as plain `PanelContainer` with hardcoded labels, not `card.tscn` instances. No script logic.
- "Radial gradient background" — explicit fallback to solid color if shader adds complexity.
- Trick area compass layout fully specified with slot names.

---

## Out of Scope

- Sound effects (CLAUDE.md priority 8, separate task)
- Multiplayer networking (CLAUDE.md priority 9)
- Turn timer logic (multiplayer only — layout slot reserved but no logic)
- Score carry-over / persistent stats
