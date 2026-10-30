extends "res://tests/test_case.gd"

const Fixture: PackedScene = preload("res://tests/fixtures/wetness_simulation.tscn")

## Public contact state stands in for a host's carrying or placement component.
var holder: Node
## Height above the floor blocks absorption while retaining direct-hit eligibility.
var lift: float = 0.0
## Placement state can independently suspend ground contact.
var available: bool = true


func test_configured_contact_conditions_and_full_doses() -> void:
	var receiver: Wettable2D = track(Wettable2D.new()) as Wettable2D
	receiver.contact_required_paths = [NodePath("..:available")]
	receiver.contact_blocked_paths = [NodePath("..:holder"), NodePath("..:lift")]
	receiver.settings.report_full_dose = true
	add_child(receiver)
	receiver.refresh_contact()
	check(receiver.contact_enabled)
	lift = 2.0
	receiver.refresh_contact()
	check(not receiver.contact_enabled)
	var doses: Array[float] = []
	receiver.water_added.connect(func(dose: float) -> void: doses.append(dose))
	check(receiver.add_water(2.0))
	check(receiver.add_water(3.0))
	check(doses == [2.0, 3.0])
	check(receiver.saturation == 1.0)
	lift = 0.0
	holder = self
	receiver.refresh_contact()
	check(not receiver.contact_enabled)
	holder = null
	available = false
	receiver.refresh_contact()
	check(not receiver.contact_enabled)
	available = true
	receiver.refresh_contact()
	check(receiver.contact_enabled)


func test_surface_discovery_tracks_reparenting_and_detachment() -> void:
	var first: Node2D = track(Fixture.instantiate()) as Node2D
	var second: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(first)
	add_child(second)
	var surface: WetSurface2D = first.get_node("Layer/Surface") as WetSurface2D
	var other: WetSurface2D = second.get_node("Layer/Surface") as WetSurface2D
	surface.contact_scope = first
	other.contact_scope = second
	var receiver: Wettable2D = first.get_node("Receiver") as Wettable2D
	receiver.automatic_surface = true
	receiver.refresh_contact()
	check(receiver.surface == surface)
	receiver.reparent(second)
	receiver.refresh_contact()
	check(receiver.surface == other)
	receiver.reparent(self)
	receiver.refresh_contact()
	check(receiver.surface == null)
