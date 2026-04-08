class_name AnimationManager
extends RefCounted

## Centralized animation primitives for the game table UI.
## All durations are scaled by Settings.anim_multiplier() so the Slow/Normal/Fast
## animation-speed setting affects every animation uniformly.
## Every function returns a Tween the caller can `await tween.finished` on.

const DEAL_DURATION := 0.3
const CARD_PLAY_DURATION := 0.25
const TRICK_DISPLAY_PAUSE := 0.75
const TRICK_COLLECT_DURATION := 0.4
const FLIP_DURATION := 0.2
const TRICK_COLLECT_SCALE := 0.3
const CARD_PLAY_BOUNCE_SCALE := 1.05

static func _mult() -> float:
	return Settings.anim_multiplier()

## Slide `node` from its current position to `target_pos` over DEAL_DURATION.
## Used for the fly-card that travels from deck center to a hand position.
static func deal_fly(node: Control, target_pos: Vector2) -> Tween:
	var tween := node.create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(node, "position", target_pos, DEAL_DURATION * _mult())
	return tween

## Flip a card via a scale-X tween: 1.0 → 0.0 (half flip), swap face, 0.0 → 1.0.
## `card_ui` must expose `set_face_up(face_up: bool)`.
static func flip(card_ui: Control, face_up: bool) -> Tween:
	# Pivot around the card's horizontal center so the flip looks right.
	card_ui.pivot_offset = Vector2(card_ui.size.x / 2.0, card_ui.size.y / 2.0)
	var half := FLIP_DURATION * _mult() * 0.5
	var tween := card_ui.create_tween()
	tween.tween_property(card_ui, "scale:x", 0.0, half) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(Callable(card_ui, "set_face_up").bind(face_up))
	tween.tween_property(card_ui, "scale:x", 1.0, half) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_LINEAR)
	return tween

## Slide `node` to `target_pos` with a 1.0 → 1.05 → 1.0 scale bounce.
## Used for cards travelling from a hand into the center trick slot.
static func card_play(node: Control, target_pos: Vector2) -> Tween:
	node.pivot_offset = Vector2(node.size.x / 2.0, node.size.y / 2.0)
	var dur := CARD_PLAY_DURATION * _mult()
	var tween := node.create_tween()
	tween.set_parallel(true)
	# Slide
	tween.tween_property(node, "position", target_pos, dur) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	# Scale bounce — up then back down
	tween.tween_property(node, "scale", Vector2(CARD_PLAY_BOUNCE_SCALE, CARD_PLAY_BOUNCE_SCALE), dur * 0.5)
	tween.chain().tween_property(node, "scale", Vector2.ONE, dur * 0.5)
	return tween

## Slide all `cards` toward `target_pos` while shrinking to TRICK_COLLECT_SCALE.
## Caller is responsible for the TRICK_DISPLAY_PAUSE pause beforehand.
static func trick_collect(cards: Array, target_pos: Vector2, owner: Node) -> Tween:
	var tween := owner.create_tween()
	tween.set_parallel(true)
	var dur := TRICK_COLLECT_DURATION * _mult()
	for c in cards:
		var node := c as Control
		if node == null or not is_instance_valid(node):
			continue
		node.pivot_offset = Vector2(node.size.x / 2.0, node.size.y / 2.0)
		# Adjust target so the scaled-down card centers on target_pos.
		var centered := target_pos - node.size * TRICK_COLLECT_SCALE / 2.0
		tween.tween_property(node, "global_position", centered, dur) \
				.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(node, "scale",
				Vector2(TRICK_COLLECT_SCALE, TRICK_COLLECT_SCALE), dur)
	return tween
