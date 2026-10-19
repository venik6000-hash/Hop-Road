class_name VillageBuilding
extends Building
## A building of the village made by tools/pipeline/buildings/kit.py and stood
## on the map by its table: the brewery, the lighthouse, the smithy, the mill.
## It is a Building, as the tavern is: the pieces are dressed the same way
## (materials by the names the glTF surfaces carry, layers, doors on their
## hinges, colliders by the `tav_*` properties), and so is the light of its
## rooms (Building.add_light): the table's `lights` and the rooms its `probes`
## give, in the building's own frame, at the table's origin and yaw. The rooms
## have no contact shadows yet, and no openings for the day and the sight
## (docs/plans/lighting.md, шаг 3). Each row says the shadow of its lamp. A
## fire of the work the table gives `hours` burns for that part of the day
## only (the forge's, by the game's clock); a lamp the table names in `dusk`
## burns by the sun, from dusk to dawn (SkySystem.lamp_dusk), as every
## lantern does. With the lamp of a fire the table draws
## (`fires`, BuildingFires) go its flames and the hot air over them, the
## smoke of its vent and its glow from afar. What the table has moving
## (`turning`, `moving`, `vanes`) is BuildingMachinery's, and a fire the
## bellows blow flares with their air; its `water` is MillWater's. The
## brewing a table's `utensils` serve is BrewHouse's: it takes the machinery
## and the fires, not the building.

const VILLAGE_BUILDINGS = preload("res://src/village/village_buildings.gd")
## The buildings in the tree: the vegetation's obstacle scan reaches as far as
## they stand.
const GROUP := &"village_building"
## A candle's light behind a window, for the glow the window is from afar.
const WINDOW_GLOW := Color(1.0, 0.64, 0.34)

## The building's table (RegionDef.buildings); set before it enters the tree.
var table: Dictionary
## The turning light, where the table has an `optic` (the lighthouse).
var optic: LighthouseOptic
## The falls, whose water a mill's is (the table's `water`); set before it
## enters the tree.
var falls: WaterfallSystem
## What moves, where the table has `turning`, `moving` or `vanes`.
var machinery: BuildingMachinery
## The table's `fires`; made in _ready, with the lamps.
var fires: BuildingFires
## The brewing, where the table has `utensils` (the brewery).
var brew_house: BrewHouse

## What the table's `hours` and `dusk` keep burning, by the name they share:
## {from, to (hours of the day), dusk (true: by the sun, the hours unused),
## lit (-1 before the first look), lamps, fires, plumes, glows (indices in
## lamp_set's glows)}.
var _kept := {}
## The lamps that leave what never stands outdoors to a twin: {lamp, twin}.
var _twins: Array[Dictionary] = []

func _ready() -> void:
	var start := Time.get_ticks_usec()
	transform = VILLAGE_BUILDINGS.pose(table)
	add_to_group(GROUP)
	# TavernCollision sets each shape by its piece's place in the world.
	add_body(true)
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
		brew_house.site = self
		brew_house.machinery = machinery
		add_child(brew_house)
	var scenes: Dictionary = table.scenes
	for part: String in scenes:
		load_part(str(scenes[part]), part.to_pascal_case(), part == "interior")
	var hours: Dictionary = table.get("hours", {})
	for kept: String in hours:
		_kept[kept] = {"from": Values.real(hours[kept][0]), "to": Values.real(hours[kept][1]), "dusk": false, "lit": -1,
			"lamps": [], "fires": [], "plumes": [], "glows": []}
	for kept: String in Values.list(table.get("dusk", [])):
		_kept[kept] = {"from": 0.0, "to": 0.0, "dusk": true, "lit": -1, "lamps": [], "fires": [], "plumes": [], "glows": []}
	add_light(false)
	fires = BuildingFires.new(light.lamps, machinery)
	if brew_house != null:
		brew_house.fires = fires
	var rows: Array = table.get("lights", [])
	var added := light.add_table(table, false)
	for index in added.size():
		var config: Dictionary = rows[index]
		var lamp := added[index]
		if _kept.has(config.name):
			var kept_lamps: Array = _kept[config.name].lamps
			kept_lamps.append(lamp)
		if lamp.shadow_enabled and config.get("layer", "interior") == "exterior":
			_twins.append({"lamp": lamp, "twin": twin_for_the_restless(lamp)})
	for config: Dictionary in table.get("fires", []):
		_add_fire(config)
	# The lighthouse's beam reaches far past its tower: it is always drawn.
	if world != null and optic == null and bounds.has_volume():
		world.interiors.watch(self, bounds.grow(InteriorSight.LAMP_REACH))
	if table.has("water") and falls != null:
		var water := MillWater.new()
		water.name = "Water"
		add_child(water)
		water.build(Values.table(table.water), falls, falls.water.water_level if falls.water != null else 0.0)
	_process(0.0)
	light.finish(leaves())
	var lamps := light.lamps
	print("BUILDING %s meshes=%d materials=%d lights=%d doors=%d bodies=%d load=%.2fs" % [name, mesh_count,
		materials.size(), lamps.flames.size() + lamps.lanterns.size(), doors.size(), bodies,
		(Time.get_ticks_usec() - start) / 1e6])

## The pieces stand in the building's bounds. A piece of the shell the table
## names `outdoors` takes no room's lamp.
func _dress_piece(item: MeshInstance3D, room: bool) -> void:
	var box := item.global_transform * item.mesh.get_aabb()
	bounds = box if mesh_count == 0 else bounds.merge(box)
	super(item, room)
	if not room and stands_outdoors(str(item.name), table):
		item.layers &= ~LightLayers.ROOMS

## The flames the model has stand for the pictures: the game draws its own.
## The optic, the machinery and the brewing take their pieces.
func _take_part(scene: Node3D, room: bool) -> void:
	if table.has("fires"):
		TAVERN_DRESSING.remove_replaced_fire(scene)
	if optic != null:
		optic.take(scene)
	if machinery != null:
		machinery.take(scene, room)
	if brew_house != null:
		brew_house.take(scene)

## A fire of the table's `fires` (BuildingFires.add); one the table's `hours`
## keep burns by them.
func _add_fire(config: Dictionary) -> void:
	var fire := fires.add(config)
	add_child(fire)
	if _kept.has(config.name):
		var kept_fires: Array = _kept[config.name].fires
		kept_fires.append(fire)

func _process(_delta: float) -> void:
	fires.blow()
	for pair: Dictionary in _twins:
		var twin: Light3D = pair.twin
		var lamp: Light3D = pair.lamp
		twin.light_energy = lamp.light_energy
	if sky_system == null:
		return
	var hour := GameClock.hour()
	for kept: Dictionary in _kept.values():
		var lit := sky_system.lamp_dusk > SkySystem.LIT_DUSK if Values.flag(kept.dusk) \
			else burns(hour, Values.real(kept.from), Values.real(kept.to))
		if Values.whole(lit) == Values.whole(kept.lit):
			continue
		kept.lit = int(lit)
		for lamp: Light3D in kept.lamps:
			lamp.visible = lit
		for fire: HearthFire in kept.fires:
			fire.burn(1.0 if lit else 0.0)
		for plume: CPUParticles3D in kept.plumes:
			plume.emitting = lit
		for index: int in kept.glows:
			lamp_set.set_lit(index, lit)

## The wind blows along `wind_heading` (WeatherSystem.wind_heading_deg, in
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

## The glow of a fire the table's `hours` keep (lamps_for) burns while the
## fire does.
func _glow_added(glow: Dictionary, index: int) -> void:
	var fire := str(glow.get("fire", ""))
	if not _kept.has(fire):
		return
	var kept_glows: Array = _kept[fire].glows
	kept_glows.append(index)
	if Values.whole(_kept[fire].lit) == 0:
		lamp_set.set_lit(index, false)

## What the building is from far away at night, in world space: its lanterns
## (Building.glows), its lit windows and its fires (a fire's glow names it,
## `fire`).
func glows() -> Array[Dictionary]:
	var result := super()
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
