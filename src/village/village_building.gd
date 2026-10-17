class_name VillageBuilding
extends TavernSystem
## A building of the village made by tools/pipeline/buildings/kit.py and stood
## on the map by its table: the brewery, the lighthouse, the smithy, the mill.
## It is the tavern's loader on another table. The pieces are dressed the same
## way (materials by the names the glTF surfaces carry, layers, doors on their
## hinges, colliders by the `tav_*` properties), the lights and the probes
## over the rooms are InteriorLamps', the rooms an Interior of the level's;
## all of it in the building's own frame, at the table's origin and yaw. A
## fire the table gives `hours` burns for that part of the day only: the
## forge's, the smith's candle. With the lamp of a fire the table draws
## (`fires`) go its flames and the hot air over them, the smoke of its vent
## and its glow from afar. What the table
## has moving (`turning`, `moving`, `vanes`) is BuildingMachinery's, and a
## fire the bellows blow flares with their air; its `water` is MillWater's.
## The brewing a table's `utensils` serve is BrewHouse's.

const VILLAGE_BUILDINGS = preload("res://src/village/village_buildings.gd")
## The buildings in the tree: the vegetation's obstacle scan reaches as far as
## they stand.
const GROUP := &"village_building"
## A candle's light behind a window, for the glow the window is from afar.
const WINDOW_GLOW := Color(1.0, 0.64, 0.34)
## How far a room's probe reaches past the room. The tavern's walls are half
## a metre of stone; a wall here may be a board, and a probe that reached
## through it would give the wall's weather side the room's darkness.
const PROBE_REACH := 0.12
## The profile of the rooms (assets/light/profiles.json).
const PROFILE := "hall"
## A fire under a full draught of the bellows: how much taller its flames
## stand, and how much brighter its lamps burn.
const FLARE := 0.45
const FLARE_LIGHT := 0.6

## The building's table (RegionDef.buildings); set before it enters the tree.
var table: Dictionary
## The turning light, where the table has an `optic` (the lighthouse).
var optic: LighthouseOptic
## The lamps and the probes of the table, and its rooms (an Interior of the
## level's while it has rooms).
var lamps: InteriorLamps
var interior: Interior
## The falls, whose water a mill's is (the table's `water`); set before it
## enters the tree.
var falls: WaterfallSystem
## What moves, where the table has `turning`, `moving` or `vanes`.
var machinery: BuildingMachinery
## The brewing, where the table has `utensils` (the brewery).
var brew_house: BrewHouse

## What the table's `hours` keep burning, by the name they share: {from, to
## (hours of the day), lit (-1 before the first look at the sky), lamps,
## fires, plumes, glows (FarLights' indices)}.
var _kept := {}
## The table's `fires`: {fire: HearthFire, blown (the machinery's group whose
## air it takes), lamps (its lamps' names), draught}.
var _fires: Array[Dictionary] = []
## The lamps that leave what never stands outdoors to a twin: {lamp, twin}.
var _twins: Array[Dictionary] = []
var _far: FarLights

func _ready() -> void:
	var start := Time.get_ticks_usec()
	transform = VILLAGE_BUILDINGS.pose(table)
	add_to_group(GROUP)
	body = StaticBody3D.new()
	body.name = "Solid"
	# TavernCollision sets each shape by its piece's place in the world.
	body.top_level = true
	add_child(body)
	has_interior = true
	TAVERN_MATERIALS.build(table, position.y, materials)
	if table.has("optic"):
		optic = LighthouseOptic.new()
		optic.name = "Optic"
		optic.sky_system = sky_system
		optic.interiors = world.interiors if world != null else null
		add_child(optic)
		optic.configure(Values.table(table.optic))
	if table.has("turning") or table.has("moving") or table.has("vanes"):
		machinery = BuildingMachinery.new()
		machinery.name = "Machinery"
		add_child(machinery)
		machinery.configure(table)
	if table.has("utensils"):
		brew_house = BrewHouse.new()
		brew_house.name = "BrewHouse"
		brew_house.table = table
		brew_house.building = self
		add_child(brew_house)
	var scenes: Dictionary = table.scenes
	for part: String in scenes:
		var scene := (load(str(scenes[part])) as PackedScene).instantiate() as Node3D
		scene.name = part.to_pascal_case()
		add_child(scene)
		var room := part == "interior"
		for item: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			var box := item.global_transform * item.mesh.get_aabb()
			bounds = box if mesh_count == 0 else bounds.merge(box)
			TAVERN_DRESSING.dress(self, item, room)
			if not room and stands_outdoors(str(item.name), table):
				item.layers &= ~LightLayers.ROOMS
		# The flames the model has stand for the pictures: the game draws its own.
		if table.has("fires"):
			TAVERN_DRESSING.remove_replaced_fire(scene)
		if optic != null:
			optic.take(scene)
		if machinery != null:
			machinery.take(scene, room)
		if brew_house != null:
			brew_house.take(scene)
		_batch(scene, room)
	var hours: Dictionary = table.get("hours", {})
	for kept: String in hours:
		_kept[kept] = {"from": Values.real(hours[kept][0]), "to": Values.real(hours[kept][1]), "lit": -1, "lamps": [], "fires": [],
			"plumes": [], "glows": []}
	lamps = InteriorLamps.new()
	lamps.name = "Lamps"
	lamps.sky = sky_system
	add_child(lamps)
	for config: Dictionary in table.get("lights", []):
		var light := lamps.add_light(config)
		if _kept.has(config.name):
			var kept_lamps: Array = _kept[config.name].lamps
			kept_lamps.append(light)
		if light.shadow_enabled and config.get("layer", "interior") == "exterior":
			_twins.append({"lamp": light, "twin": twin_for_the_restless(light)})
	for config: Dictionary in table.get("fires", []):
		_add_fire(config)
	interior = Interior.new(str(name), global_transform, bounds)
	interior.lamps = lamps
	lamps.interior = interior
	for config: Dictionary in table.get("probes", []):
		var room := room_of_probe(config)
		interior.rooms.append(room)
		lamps.add_probe(room, str(config.name))
	if world != null:
		if not interior.rooms.is_empty():
			world.interiors.add(interior)
		# The lighthouse's beam reaches far past its tower: it is always drawn.
		if optic == null and bounds.has_volume():
			world.interiors.watch(self, bounds.grow(InteriorSight.LAMP_REACH))
	if table.has("water") and falls != null:
		var water := MillWater.new()
		water.name = "Water"
		add_child(water)
		water.build(Values.table(table.water), falls, falls.water.water_level if falls.water != null else 0.0)
	lamps.await_probes()
	_process(0.0)
	lamps._process(0.0)
	print("BUILDING %s meshes=%d materials=%d lights=%d doors=%d bodies=%d load=%.2fs" % [name, mesh_count,
		materials.size(), lamps.flames.size() + lamps.lanterns.size(), doors.size(), bodies,
		(Time.get_ticks_usec() - start) / 1e6])

## A fire of the table's `fires`: flames with hot air over them (HearthFire)
## along `along` at `at`, `width` across and `height` tall.
func _add_fire(config: Dictionary) -> void:
	var fire := HearthFire.from_table(config)
	add_child(fire)
	_fires.append({"fire": fire, "blown": str(config.get("blown", "")),
		"lamps": PackedStringArray(Values.list(config.get("lamps", []))), "draught": 0.0})
	if _kept.has(config.name):
		var fires: Array = _kept[config.name].fires
		fires.append(fire)

func _process(_delta: float) -> void:
	for entry: Dictionary in _fires:
		_blow(entry)
	for pair: Dictionary in _twins:
		var twin: Light3D = pair.twin
		var lamp: Light3D = pair.lamp
		twin.light_energy = lamp.light_energy
	if sky_system == null:
		return
	var hour := sky_system.time_of_day
	for kept: Dictionary in _kept.values():
		var lit := burns(hour, Values.real(kept.from), Values.real(kept.to))
		if Values.whole(lit) == Values.whole(kept.lit):
			continue
		kept.lit = int(lit)
		for lamp: Light3D in kept.lamps:
			lamp.visible = lit
		for fire: HearthFire in kept.fires:
			fire.visible = lit
		for plume: CPUParticles3D in kept.plumes:
			plume.emitting = lit
		for index: int in kept.glows:
			_far.set_lit(index, lit)

## The bellows' air on a fire: taller flames, more hot air, brighter lamps.
func _blow(entry: Dictionary) -> void:
	if machinery == null or entry.blown == "":
		return
	var draught := machinery.draught(str(entry.blown))
	if draught == Values.real(entry.draught):
		return
	entry.draught = draught
	var fire: HearthFire = entry.fire
	fire.scale = Vector3.ONE * (1.0 + FLARE * draught)
	fire.haze_strength = 1.0 + draught
	for lamp: String in entry.lamps:
		lamps.set_strength(lamp, 1.0 + FLARE_LIGHT * draught)

## The lamp of the table named `lamp` burns at `strength` of its light: a
## fire stoked or let die (BrewHouse). At 0 it is out.
func stoke(lamp: String, strength: float) -> void:
	lamps.set_strength(lamp, strength)
	for flame: Dictionary in lamps.flames:
		var light: Light3D = flame.light
		if str(light.name) == lamp:
			light.visible = strength > 0.01

## The wind blows along `wind_heading` (OceanFFT.wind_direction_deg, in
## radians): what the building has for the wind to turn comes round to it.
func take_wind(wind_heading: float) -> void:
	if machinery != null:
		machinery.face(global_basis.inverse() * Vector3(cos(wind_heading), 0.0, sin(wind_heading)))

## A lamp outdoors that casts a shadow would draw its map again in every
## frame beside a wheel that never stands or a goat that grazes
## (LightLayers.RESTLESS). It leaves them out of its light; its twin,
## the lamp once more with no shadow, lights nothing else. The twin is the
## lamp's child: it is lit and put out with it.
static func twin_for_the_restless(lamp: Light3D) -> Light3D:
	lamp.light_cull_mask &= ~LightLayers.RESTLESS
	var twin := lamp.duplicate(0) as Light3D
	twin.name = "OnTheRestless"
	twin.transform = Transform3D.IDENTITY
	twin.shadow_enabled = false
	twin.light_cull_mask = LightLayers.RESTLESS
	lamp.add_child(twin)
	return twin

## The room under a row of the table's `probes`: its air, PROBE_REACH past it
## on every side.
static func room_of_probe(config: Dictionary) -> Interior.Room:
	var half := Values.vec3(config.extents)
	var air: Array[AABB] = [AABB(Values.vec3(config.position) - half, half * 2.0)]
	var a: Array = config.ambient
	return Interior.Room.new(str(config.room), air, Vector3.ONE * PROBE_REACH, air[0].position.y, LightProfile.named(PROFILE),
		Color(Values.real(a[0]), Values.real(a[1]), Values.real(a[2])))

## Whether the shell's piece `piece` stands outside every room (the table's
## `outdoors`, by how the names begin). Such a piece takes no room's probe
## and no room's lamp: a round tower's stone lies in the corners of the box
## its stair's probe is.
static func stands_outdoors(piece: String, table: Dictionary) -> bool:
	return VILLAGE_BUILDINGS.begins(piece, PackedStringArray(Values.list(table.get("outdoors", []))))

## Whether a fire kept from `from` to `to` (hours of the day; past midnight
## when `to` is the smaller) burns at `hour`.
static func burns(hour: float, from: float, to: float) -> bool:
	if from <= to:
		return hour >= from and hour < to
	return hour >= from or hour < to

## Gives `far` the building's glows; that of a fire the table's `hours` keep
## burns while the fire does.
func light_from_afar(far: FarLights) -> void:
	_far = far
	for glow: Dictionary in glows():
		var at: Vector3 = glow.at
		var color: Color = glow.color
		var facing: Vector3 = glow.facing
		var index := far.add_glow(at, color, Values.real(glow.radius), facing)
		var fire := str(glow.get("fire", ""))
		if _kept.has(fire):
			var kept_glows: Array = _kept[fire].glows
			kept_glows.append(index)
			far.set_lit(index, Values.whole(_kept[fire].lit) != 0)

## What the building is from far away at night, in world space: its lanterns,
## its lit windows and its fires ({at, color, radius, facing}, see
## FarLights.add_glow; a fire's glow names it, `fire`).
func glows() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for glow: Dictionary in lamps.far_glows:
		var facing: Vector3 = glow.facing
		var at: Vector3 = glow.at
		result.append({"at": to_global(at), "color": glow.color, "radius": glow.radius,
			"facing": global_basis * facing})
	for window: Dictionary in table.get("windows", []):
		var size: Array = window.size
		result.append({"at": to_global(Values.vec3(window.at)), "color": WINDOW_GLOW,
			"radius": minf(0.3, 0.5 * maxf(Values.real(size[0]), Values.real(size[1]))), "facing": global_basis * Values.vec3(window.out)})
	for config: Dictionary in table.get("fires", []):
		if config.has("far"):
			var flame_height: float = config.height
			result.append({"at": to_global(Values.vec3(config.at) + Vector3.UP * flame_height * 0.5), "color": _lamp_color(str(config.name)),
				"radius": Values.real(config.far.radius), "facing": global_basis * Values.vec3(config.far.out), "fire": str(config.name)})
	return result

## The colour of the table's lamp `lamp`, or a candle's.
func _lamp_color(lamp: String) -> Color:
	for config: Dictionary in table.get("lights", []):
		if config.name == lamp:
			return Color(Values.real(config.color[0]), Values.real(config.color[1]), Values.real(config.color[2]))
	return WINDOW_GLOW

## Where smoke leaves the building (the table's `vents` of kind "smoke"), in
## world space.
func smoke_vents() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for vent: Dictionary in table.get("vents", []):
		if vent.kind == "smoke":
			result.append(to_global(Values.vec3(vent.at)))
	return result

## The plumes over smoke_vents(), in their order. The smoke of a vent that
## names a fire the table's `hours` keep (`fire`) rises while it burns.
func take_plumes(plumes: Array[CPUParticles3D]) -> void:
	var index := 0
	for vent: Dictionary in table.get("vents", []):
		if vent.kind != "smoke":
			continue
		var fire := str(vent.get("fire", ""))
		if _kept.has(fire):
			var kept_plumes: Array = _kept[fire].plumes
			kept_plumes.append(plumes[index])
			plumes[index].emitting = Values.whole(_kept[fire].lit) != 0
		index += 1
