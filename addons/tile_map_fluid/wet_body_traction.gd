class_name TileFluidBodyTraction
extends RefCounted
## Per-receiver dry damping snapshots; surface configuration owns the wet response.

var _body: RigidBody2D
var _dry_linear: float
var _dry_angular: float
var _last_linear: float
var _last_angular: float


## Preserve external changes to dry damping, and restore it when ground contact is lost.
func apply(body: RigidBody2D, surface: TileFluidSurface2D, wet: float) -> void:
	if not is_instance_valid(surface):
		surface = null
	if body != _body:
		restore()
		_body = body
		if body == null:
			return
		_dry_linear = body.linear_damp
		_dry_angular = body.angular_damp
		_last_linear = _dry_linear
		_last_angular = _dry_angular
	if not is_instance_valid(_body):
		return
	if not is_equal_approx(body.linear_damp, _last_linear):
		_dry_linear = body.linear_damp
	if not is_equal_approx(body.angular_damp, _last_angular):
		_dry_angular = body.angular_damp
	var multiplier: float = surface.traction_multiplier(wet) if surface != null else 1.0
	_last_linear = _dry_linear * multiplier
	_last_angular = _dry_angular * multiplier \
		if surface != null and surface.traction_affects_rotation else _dry_angular
	body.linear_damp = _last_linear
	body.angular_damp = _last_angular


## Release only the damping values still owned by this receiver.
func restore() -> void:
	if is_instance_valid(_body):
		if is_equal_approx(_body.linear_damp, _last_linear):
			_body.linear_damp = _dry_linear
		if is_equal_approx(_body.angular_damp, _last_angular):
			_body.angular_damp = _dry_angular
	_body = null
