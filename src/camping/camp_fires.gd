class_name CampFires
extends Node3D
## The fires of the camp (CampSystem) and what E, Q and X do at them: lay a
## log, light, take the potato out of the coals or put one in, put the fire
## out, fill the mug. The fires are the children of the node. Its part of the
## save is `sites` (CampSystem.to_dict). The part reads Q and X in GAME: Q
## only while the player aims at a fire.

var camp: CampSystem
var fires: Array[Campfire] = []
## Saved fires that restore has read but not laid yet (sites keeps them).
var _unlaid_sites: Array = []

func _input(event: InputEvent) -> void:
	if not camp.in_play() or event.is_echo():
		return
	if InputActions.takes_in(event, &"camp_secondary", InputActions.GAME):
		if camp.interactions.selected is Campfire:
			var fire: Campfire = camp.interactions.selected
			fire.set_burning(false)
			get_viewport().set_input_as_handled()
	elif InputActions.takes_in(event, &"camp_refill", InputActions.GAME):
		var player := camp.player
		if nearby_fire(player.global_position, 3.0) != null and not player.viewmodel.drinking():
			player.viewmodel.refill()
			camp.say(null, camp.lines.text(&"jug_full"))
			get_viewport().set_input_as_handled()

## A fire of wood laid at `site` (CampSystem.check_site), not burning.
func lay_fire(site: Dictionary) -> Campfire:
	var fire := Campfire.new()
	fire.name = "Campfire" + str(fires.size())
	fire.position = site.position
	fire.seats.assign(Values.list(site.seats))
	add_child(fire)
	fire.burnt_out.connect(func() -> void: camp.say(null, camp.lines.text(&"burnt_out")))
	fires.append(fire)
	return fire

## The burning fire nearest `point` within `reach`, null for none.
func nearby_fire(point: Vector3, reach: float) -> Campfire:
	var closest: Campfire
	for fire in fires:
		var distance := point.distance_to(fire.global_position)
		if fire.burning and distance < reach:
			reach = distance
			closest = fire
	return closest

## Whether somebody sits on the seat by a fire: the player or a companion.
func seat_occupied(seat: Dictionary) -> bool:
	return camp.interactions.seated == seat or camp.company.holds_seat(seat)

## What E would do nearest within `best` metres among the fires and their
## free seats: {distance, target}; {} when nothing.
func find_target(best: float) -> Dictionary:
	var result: Dictionary = {}
	var interactions := camp.interactions
	for fire in fires:
		var distance := interactions.target_distance(fire.global_position + Vector3.UP * 0.45, null, true)
		if distance < best:
			best = distance
			result = {"distance": best, "target": fire}
		for seat: Dictionary in fire.seats:
			if seat_occupied(seat):
				continue
			distance = interactions.target_distance(Values.vec3(seat.position) + Vector3.UP * 0.5, null, true)
			if distance < best:
				best = distance
				result = {"distance": best, "target": seat}
	return result

## The valley's brewery, whose logs burn here too; null in a valley without one.
func _brewery() -> BrewHouse:
	return get_tree().get_first_node_in_group(BrewHouse.GROUP) as BrewHouse

## Whether the player carries a log of the brewery's (BrewHouse) to burn.
func holding_log() -> bool:
	var brewery := _brewery()
	return brewery != null and brewery.work.carrying.holding_log()

## E at the fire.
func interact_fire(fire: Campfire) -> void:
	var lines := camp.lines
	var food := camp.food
	if holding_log():
		if not fire.fuel.add_log():
			camp.say(null, lines.text(&"fire_full"))
			return
		_brewery().work.carrying.throw_log(fire.global_position + Vector3.UP * 0.2)
		if not fire.burning:
			fire.set_burning(true)
			camp.say(null, lines.text(&"log_caught"))
		camp.mark_changed()
		return
	if not fire.burning:
		if fire.fuel.empty():
			camp.say(null, lines.text(&"need_wood"))
			return
		fire.set_burning(true)
		camp.say(null, lines.text(&"fire_caught"))
	elif fire.meal.ready():
		if food.holding():
			return
		var busy := camp.player.hands.busy_text(BodyChannels.POTATO)
		if busy != "":
			camp.say(null, busy)
			return
		if not fire.meal.take():
			return
		food.take_meal(fire.meal)
		camp.say(null, lines.text(&"potato_hot"))
	elif not food.holding() and fire.meal.put_in_coals():
		camp.say(null, lines.text(&"potato_in_coals"))
	camp.mark_changed()

## The key a fire is remembered by: its place in whole metres.
static func fire_key(fire: Campfire) -> String:
	return "%d:%d" % [roundi(fire.position.x), roundi(fire.position.z)]

## The fires as the save holds them: [[x, y, z, fuel seconds], ...], with
## those still waiting to be laid again (restore) as they were read.
func sites() -> Array:
	var result: Array = []
	for fire in fires:
		result.append([fire.position.x, fire.position.y, fire.position.z, fire.fuel.seconds])
	result.append_array(_unlaid_sites)
	return result

## Lays the saved fires again, checked, on ground that still takes them, once
## the ground under the first of them stands (PhysicsLayers.ground_stands).
func restore(saved_sites: Variant) -> void:
	if not saved_sites is Array:
		return
	_unlaid_sites = saved_sites
	var first := _first_point(_unlaid_sites)
	if not first.is_finite():
		_unlaid_sites = []
		return
	await PhysicsLayers.ground_stands(self, first)
	var unlaid := _unlaid_sites
	_unlaid_sites = []
	if not is_inside_tree():
		return
	for item: Variant in unlaid:
		var values := _site_values(item)
		if values.is_empty():
			continue
		var site := camp.check_site(Values.vec3(values), true)
		if site.has("position"):
			var fire := lay_fire(site)
			# The logs left in a fire put out wait for it to be lit again.
			if values.size() == 4 and (values[3] is float or values[3] is int) and is_finite(Values.real(values[3])):
				fire.fuel.seconds = clampf(Values.real(values[3]), 0.0, CampFuel.MAX_LOGS * CampFuel.LOG_SECONDS)

## The values of a saved site that can be read ([x, y, z] or [x, y, z, fuel]
## with a finite point), [] for one that cannot.
static func _site_values(item: Variant) -> Array:
	if not item is Array:
		return []
	var values: Array = item
	if values.size() != 3 and values.size() != 4:
		return []
	return values if Values.vec3(values).is_finite() else []

## The point of the first site that can be read; not finite for none.
static func _first_point(saved: Array) -> Vector3:
	for item: Variant in saved:
		var values := _site_values(item)
		if not values.is_empty():
			return Values.vec3(values)
	return Vector3(NAN, NAN, NAN)
