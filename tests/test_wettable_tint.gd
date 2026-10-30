extends "res://tests/test_case.gd"

const Fixture: PackedScene = preload("res://tests/fixtures/wettable_tint.tscn")


## The dedicated wrapper composes with parent/child modulation and never edits a shared material.
func test_drying_restores_authored_color_without_overwriting_other_effects() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var receiver: Wettable2D = world.get_node("Receiver") as Wettable2D
	var wrapper: WettableTint2D = world.get_node("Artwork") as WettableTint2D
	var sprite: Sprite2D = world.get_node("Artwork/Sprite") as Sprite2D
	var other: Sprite2D = world.get_node("OtherSprite") as Sprite2D
	var authored: Color = wrapper.modulate
	var child_color: Color = sprite.modulate
	var material: Material = sprite.material
	receiver.set_physics_process(false)
	receiver.settings = receiver.settings.duplicate() as WettableSettings
	receiver.settings.dry_seconds = 1.0
	receiver.add_water(1.0)
	check(wrapper.modulate.is_equal_approx(authored * wrapper.wet_multiplier))
	world.modulate = Color(0.5, 1, 1)
	sprite.self_modulate = Color(1, 0.5, 1)
	receiver.advance(1.0)
	check(wrapper.modulate.is_equal_approx(authored))
	check(sprite.modulate.is_equal_approx(child_color))
	check(sprite.self_modulate.is_equal_approx(Color(1, 0.5, 1)))
	check(world.modulate.is_equal_approx(Color(0.5, 1, 1)))
	check((sprite.material) == (material))
	check((other.material) == (material))


## Removing presentation restores dry artwork; a receiver without any presenter still works.
func test_detach_reentry_and_freed_receiver_restore_tint() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var wrapper: WettableTint2D = world.get_node("Artwork") as WettableTint2D
	var receiver: Wettable2D = wrapper.receiver
	var authored: Color = wrapper.modulate
	receiver.add_water(0.8)
	world.remove_child(wrapper)
	check(wrapper.modulate.is_equal_approx(authored))
	check(receiver.add_water(0.2))
	check((receiver.saturation) == (1.0))
	world.add_child(wrapper)
	wrapper.refresh()
	check(wrapper.modulate.is_equal_approx(authored * wrapper.wet_multiplier))
	receiver.free()
	wrapper.refresh()
	check(wrapper.modulate.is_equal_approx(authored))
