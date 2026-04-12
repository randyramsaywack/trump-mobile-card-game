# Pre-Multiplayer Polish — Design Spec

## Problem

Three issues need resolution before moving to multiplayer:

1. **Fonts broken on Android** — `.gdignore` in `assets/fonts/raw/` excludes font TTFs from the exported PCK. `FileAccess.open()` fails at runtime because the files aren't bundled.
2. **Touch input lacks feedback** — Cards have functional tap/drag handling but no visual press feedback. Players can't tell they've touched a card until the action completes.
3. **UI transitions are instant** — Trump selector, win screen, trump watermark, and toast messages snap visible/hidden with no animation, making the game feel unpolished.

## Scope

Subtle, fast polish. No new features. No architectural changes. All animation durations respect the existing `Settings.anim_multiplier()`.

---

## 1. Fix Android Font Loading

### Root Cause

`.gdignore` tells Godot to skip the directory entirely during export. The font files in `assets/fonts/raw/` are not included in the PCK/APK. At runtime on Android, `FileAccess.open("res://assets/fonts/raw/...")` returns null.

### Solution

Remove `.gdignore`. The fonts will be bundled in the PCK again. The FreeType "Error loading font" errors from Godot's import pipeline will reappear in the editor log, but these are cosmetic — the fonts render correctly via the `FileAccess` + `FontFile.data` approach regardless. The errors only affect the unused `.fontdata` import artifacts.

### Files Changed

- `assets/fonts/raw/.gdignore` — delete

### Verification

Export Android APK. Confirm:
- Main menu title "TRUMP" renders in Cinzel Decorative
- Suit symbols render on main menu and in-game

---

## 2. Touch Input Polish

### 2a. Card Press Feedback

Add a visual scale-up when a card is touched (press-down), before the tap/drag is resolved.

- On `BUTTON_LEFT` pressed: scale card to 1.05x over 0.08s
- On release (tap, drag-end, or cancel): scale back to 1.0 over 0.06s
- Only applies to valid, playable cards in the human's hand
- Selected cards already have a y-offset; press feedback stacks with that

### 2b. Double-Tap Window

Increase from 350ms to 400ms for more forgiving mobile input.

### Files Changed

- `scripts/ui/card_ui.gd` — press feedback tween, double-tap constant

---

## 3. Subtle Animations

All durations below are base values, multiplied by `Settings.anim_multiplier()`.

### 3a. Trump Selector Entrance/Exit

- **Show:** Background fades from transparent to 55% black over 0.2s. Panel slides up from +30px over 0.2s with ease-out.
- **Hide:** Reverse — panel slides down, background fades out over 0.15s.

**Files:** `scripts/ui/trump_selector_ui.gd`, `scenes/ui/trump_selector.tscn`

### 3b. Win Screen Entrance

- **Show:** Background fades from transparent to 70% black over 0.25s. Result label scales from 0.8 to 1.0 with ease-out-back over 0.25s. Buttons fade in after 0.15s delay.
- No exit animation needed (scene changes on button press).

**Files:** `scripts/ui/win_screen_ui.gd`

### 3c. Trump Watermark Fade

- Fade from 0 to target alpha over 0.3s when trump is declared (currently instant).

**Files:** `scripts/ui/game_table_ui.gd`

### 3d. Toast Fade In/Out

- Fade in over 0.15s, hold for existing duration, fade out over 0.15s (currently instant show/hide).

**Files:** `scripts/ui/game_table_ui.gd`

### 3e. Card Selection Scale

- When a card is selected (tapped): tween to 1.05x scale over 0.08s.
- When deselected: tween back to 1.0 over 0.06s.
- Stacks with the existing y-offset raise.

**Files:** `scripts/ui/card_ui.gd`

---

## Out of Scope

- New features or game logic changes
- Multiplayer networking
- Refactoring existing animation system
- Win screen celebratory effects beyond the entrance tween
- Sound effect changes
