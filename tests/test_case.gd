extends Node
## Small vanilla test helper; the process supervisor also rejects runtime script errors.

var failures: int = 0
var checks: int = 0
var _owned: Array[Node] = []


## Record failures without aborting cleanup or hiding subsequent checks.
func check(condition: bool, message: String = "") -> void:
	checks += 1
	if not condition:
		failures += 1
		var caller: Dictionary = get_stack()[1]
		printerr("FAIL: %s:%d %s %s" % [caller.source, caller.line, caller.function, message])


## Own detached fixtures as well as fixtures later added to the tree.
func track(node: Node) -> Node:
	_owned.append(node)
	return node


## Advance real physics registration, including while a pausable fixture is suspended.
func frames(count: int) -> void:
	for index: int in range(count):
		await get_tree().physics_frame
	await get_tree().process_frame


## Always release fixtures, including ones intentionally removed from the tree.
func cleanup() -> void:
	for node: Node in _owned:
		if is_instance_valid(node):
			node.free()
	_owned.clear()
