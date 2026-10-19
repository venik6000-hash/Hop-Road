class_name BuildingLight
extends Node3D
## The light of one building from its tables (docs/LEVEL.md, «Свет помещений»):
## the `rooms` (or the `probes` of a table that gives its rooms by their probes
## alone), the `openings` and the `lights` of each. It knows the building by its
## frame and its box alone, not by its name. The node stands at the building's
## origin, and its parts with it:
## - InteriorLamps: the lamps, the candles' halos, the probes over the rooms;
## - Daylight: the day and the moon through the openings that let them in;
## - InteriorSight: what the rooms see of the outdoors, and the lamps the
##   floors hide from them.
## The building's Interior goes to the level's Interiors, which answers for
## all the buildings how far the eye is indoors and draws their rooms'
## contact shadows.

var sky: SkySystem
## Asked for the ridges that take the sun from the windows (may be null).
var terrain: TerrainSystem
## The level's context; null in a tool that builds the building alone.
var world: WorldContext
var interior: Interior
var lamps := InteriorLamps.new()
var daylight: Daylight
var sight: InteriorSight

## `bounds`: what the building takes up, in world space. `contact`: the
## rooms' contact shadows are drawn (ContactShadows).
func _init(title: String, frame: Transform3D, bounds: AABB, contact := true) -> void:
	name = "Light"
	interior = Interior.new(title, frame, bounds)
	interior.lamps = lamps
	interior.contact = contact
	lamps.name = "Lamps"
	lamps.interior = interior
	add_child(lamps)

## Takes the rooms, the openings and the lights of a table, and returns the
## lamps of its `lights` in their order. With `walls_cast`, a point lamp
## outdoors that reaches the building casts the shadows of its walls; without,
## each row says its shadow.
func add_table(table: Dictionary, walls_cast := true) -> Array[Light3D]:
	lamps.sky = sky
	var near: AABB = interior.transform.affine_inverse() * interior.bounds if walls_cast else AABB()
	var added: Array[Light3D] = []
	for config: Dictionary in table.get("lights", []):
		added.append(lamps.add_light(config, near))
	for room: Interior.Room in Interior.rooms_of(Values.list(table.get("rooms", []))):
		interior.rooms.append(room)
		lamps.add_probe(room, "Probe " + room.name)
	for row: Dictionary in table.get("probes", []):
		var room := Interior.room_of_probe(row)
		interior.rooms.append(room)
		lamps.add_probe(room, str(row.name))
	interior.add_openings(Values.list(table.get("openings", [])))
	return added

## After every table: the halos, the day and the sight through the openings,
## the building's Interior given to the level while it has rooms. `leaves`
## are the building's doors', which stand in its openings.
func finish(leaves: Array[OpeningLeaf]) -> void:
	lamps.add_halos(interior.transform.affine_inverse() * interior.bounds)
	if Daylight.lets_in(interior):
		daylight = Daylight.new()
		daylight.name = "Daylight"
		daylight.sky = sky
		daylight.terrain = terrain
		daylight.interior = interior
		daylight.leaves = leaves
		add_child(daylight)
		daylight.build()
	if InteriorSight.looks_out(interior):
		sight = InteriorSight.new()
		sight.name = "Sight"
		sight.interior = interior
		sight.leaves = leaves
		sight.sky = sky
		sight.world = world
		add_child(sight)
		sight.build()
		sight.watch_lamps(lamps.steady)
	if world != null and not interior.rooms.is_empty():
		world.interiors.add(interior)
	lamps.await_probes()
	lamps._process(0.0)
