extends Node2D
## Standalone controls use built-in keys directly; no project InputMap or autoload is required.

## Fixed water source; its rays cannot pass through the wall.
@export var emitter: WaterEmitter2D
## Circle follows the mouse, showing the intended landing footprint even behind the wall.
@export var footprint: WaterFootprint2D
## Movable receiver with independent drying and contact state.
@export var receiver: Wettable2D
## Live normalized saturation readout; configuration stays on the authored components.
@export var status: Label
## Pointer bounds match the demonstration floor.
@export var aim_bounds: Rect2 = Rect2(64, 128, 768, 384)


func _ready() -> void:
	# A dry floor at startup makes the first water/dry transition visible on user input.
	footprint.global_position = Vector2(288, 368)


func _process(_delta: float) -> void:
	if get_viewport().get_visible_rect().has_point(get_viewport().get_mouse_position()):
		footprint.global_position = get_global_mouse_position().clamp(
			aim_bounds.position, aim_bounds.end)
	emitter.set_active(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		or Input.is_physical_key_pressed(KEY_SPACE))
	status.text = "Floor at receiver: {0}%    Object: {1}%    Contact: {2}".format([
		roundi(emitter.surface.saturation_at(receiver.global_position) * 100.0),
		roundi(receiver.saturation * 100.0),
		"grounded" if receiver.contact_enabled else "lifted"])
