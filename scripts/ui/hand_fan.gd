## hand_fan.gd - The player's hand, laid out like a modern card game: cards sit side by side along the bottom,
## overlap more as the hand grows (so it never needs scrolling), fan out slightly, and the card under the
## mouse grows upwards and comes to the front.
class_name HandFan
extends Control

const GAP := 8.0          # space between cards while they all fit
const HOVER_SCALE := 1.28
var card_w: float = 245.0
var card_h: float = 325.0
var _views: Array[CardView] = []


func _init() -> void:
	clip_contents = false
	resized.connect(_relayout)


## Replaces the cards in the hand. Each view should already be created at card_w.
func set_views(views: Array) -> void:
	for v in _views:
		if is_instance_valid(v):
			v.queue_free()
	_views.clear()
	for v in views:
		_views.append(v)
		add_child(v)
		v.pivot_offset = Vector2(card_w * 0.5, card_h)  # grow upwards from the bottom edge, so the mouse stays on the card
		v.mouse_entered.connect(_on_enter.bind(v))
		v.mouse_exited.connect(_on_exit.bind(v))
	_relayout()


func get_views() -> Array:
	return _views


## Where card i of n goes: x position, a slight drop towards the ends of the fan, and its tilt.
func slot_for(i: int, n: int) -> Dictionary:
	var pad: float = 14.0  # room for the tilted end cards
	var width: float = maxf(size.x - pad * 2.0, card_w)
	var step: float = card_w + GAP
	var start: float = 0.0
	if n > 1:
		var need: float = card_w + float(n - 1) * step
		if need <= width:
			start = (width - need) * 0.5
		else:
			step = (width - card_w) / float(n - 1)
	else:
		start = (width - card_w) * 0.5
	var off: float = float(i) - float(n - 1) * 0.5
	var tilt: float = clampf(off * 1.6, -7.0, 7.0) if n > 2 else 0.0
	var drop: float = clampf(off * off * 1.1, 0.0, 22.0) if n > 2 else 0.0
	return {"x": pad + start + float(i) * step, "y": 6.0 + drop, "tilt": tilt}


func _relayout() -> void:
	var n: int = _views.size()
	for i in n:
		var v: CardView = _views[i]
		if not is_instance_valid(v):
			continue
		var s: Dictionary = slot_for(i, n)
		v.position = Vector2(s.x, s.y)
		v.rotation_degrees = s.tilt
		v.scale = Vector2.ONE
		v.z_index = i


func _on_enter(v: CardView) -> void:
	if not is_instance_valid(v):
		return
	v.z_index = 100
	var t := create_tween().set_parallel(true)
	t.tween_property(v, "scale", Vector2(HOVER_SCALE, HOVER_SCALE), 0.08)
	t.tween_property(v, "rotation_degrees", 0.0, 0.08)


func _on_exit(v: CardView) -> void:
	if not is_instance_valid(v):
		return
	var i: int = _views.find(v)
	if i < 0:
		return
	var s: Dictionary = slot_for(i, _views.size())
	v.z_index = i
	var t := create_tween().set_parallel(true)
	t.tween_property(v, "scale", Vector2.ONE, 0.08)
	t.tween_property(v, "rotation_degrees", float(s.tilt), 0.08)
