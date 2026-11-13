## drop_zone.gd - A panel on the board that accepts dragged cards. The screen gives it two functions:
## check(data) -> bool says whether the dropped card may land here, and done(data) handles the drop.
## While a card is being dragged over it, the zone is outlined so the player can see where it will land.
class_name DropZone
extends PanelContainer

var check: Callable = Callable()
var done: Callable = Callable()
var _hover: bool = false
var normal_style: StyleBox = null
var hover_style: StyleBox = null


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var ok: bool = check.is_valid() and bool(check.call(data))
	if ok != _hover:
		_hover = ok
		if hover_style != null and normal_style != null:
			add_theme_stylebox_override("panel", hover_style if ok else normal_style)
	return ok


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_reset()
	if done.is_valid():
		done.call(data)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT:
		_reset()


func _reset() -> void:
	_hover = false
	if normal_style != null:
		add_theme_stylebox_override("panel", normal_style)
