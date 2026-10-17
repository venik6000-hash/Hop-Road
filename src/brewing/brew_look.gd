class_name BrewLook
extends Node3D
## What the brewery's day looks and sounds like on its own (BrewHouse): each
## vessel's surface at its level and of the colour of what it holds
## (brew_liquid.gdshader), the maltings' grain, the streams that run
## (BrewStream), steam over what is hot (brew_steam.gdshader), the fires
## under the copper and the kiln, the taps and cranks posed as the day has
## them, and the loops of what runs (BrewSounds). It stands at the house's
## origin: its points are in the building's frame.

const LIQUID := preload("res://src/brewing/brew_liquid.gdshader")
const STEAM := preload("res://src/brewing/brew_steam.gdshader")
const YEAST := Color(0.82, 0.74, 0.55)
## Kg of a heap as it was modelled (the floor's, the kiln's).
const HEAP_KG := {"couch_malt": 90.0, "kiln_malt": BrewMaltings.KILN_KG}
## Green malt's tint; how much darker grain shows wet.
const GREEN_MALT := Color(0.68, 0.62, 0.36)
const WET_DARK := 0.3
## Works whose pour is grain, or as coarse as grain.
const GRAIN_POURS: Array[String] = ["grain", "steep_barley", "pour_hopper", "cherry_cask"]
## Honey and cherries in a stream.
const HONEY := Color(0.72, 0.45, 0.1)
const CHERRY := Color(0.32, 0.03, 0.05)
## The tap or pump a control's water runs through: [nozzle anchor, vessel it fills].
const TAPS := {"liquor_cock": ["liquor_main_outlet", BrewDay.MASH_TUN], "mash_tap": ["mash_tap_nozzle", BrewDay.UNDERBACK],
	"copper_tap": ["copper_tap_nozzle", BrewDay.HOP_BACK], "hop_back_tap": ["hop_back_tap_nozzle", ""]}
## What things look like: water in a stream, water in a vessel or a trough
## (its wood or stone seen through it), the mash, a sack's grain, hops.
const WATER := Color(0.05, 0.065, 0.07)
const DEEP_WATER := Color(0.3, 0.28, 0.22)
## Hands of depth a vessel's wort is seen through (wort_color).
const VESSEL_DEPTH := 4.0
const MASH := Color(0.5, 0.4, 0.27)
const GRAIN := Color(0.78, 0.62, 0.36)
const HOPS := Color(0.45, 0.55, 0.22)
## The streams, by key: the taps', the pumps', the cellar's, and "grain" for
## what a tipped thing pours.
const STREAMS: Array[String] = ["grain", "pour", "liquor_cock", "mash_tap", "copper_tap", "hop_back_tap", "liquor_pipe",
	"wort_pump", "liquor_spout", "hops", "spout", "fermenter_tap_1", "fermenter_tap_2", "steep_drain", "lager_tap_1",
	"lager_tap_2", "lager_tap_3", "lager_tap_4"]

var house: BrewHouse
var sounds: BrewSounds
var streams: Dictionary[String, BrewStream] = {}
## Plume key -> CPUParticles3D: the copper, the mash tun, the hop back, the
## coolship, the cupola, the kiln.
var steam := {}
var fire: HearthFire
var kiln_fire: HearthFire
## Group -> the pose last given, so a pose is set only when it changes.
var _posed := {}

## The streams, the steam, the fires and the sounds, at the anchors of the
## house's layout; once its day stands.
func build() -> void:
	var layout := house.layout
	sounds = BrewSounds.new()
	sounds.name = "Sounds"
	add_child(sounds)
	for key: String in STREAMS:
		var stream := BrewStream.new()
		stream.name = key.to_pascal_case() + "Stream"
		add_child(stream)
		streams[key] = stream
	steam.copper = _plume(layout.anchors["copper_hatch"], 0.5)
	steam.mash = _plume(layout.surface_point(BrewDay.MASH_TUN), 0.6)
	steam.hop_back = _plume(layout.surface_point(BrewDay.HOP_BACK), 0.4)
	steam.coolship = _plume(layout.surface_point(BrewDay.COOLSHIP), 1.0)
	for vent: Dictionary in layout.table.get("vents", []):
		if vent.kind == "steam":
			steam.cupola = _plume(Values.vec3(vent.at), 1.4)
	fire = HearthFire.new()
	fire.name = "CopperFire"
	add_child(fire)
	var stoke: Vector3 = layout.anchors["copper_stoke"]
	fire.configure(stoke + Vector3(0.0, -0.13, 0.4), Vector3.RIGHT, 0.45, 0.32)
	fire.visible = false
	kiln_fire = HearthFire.new()
	kiln_fire.name = "KilnFire"
	add_child(kiln_fire)
	kiln_fire.configure(layout.anchors["kiln_stoke"] + Vector3(0.0, -0.1, 0.3), Vector3.RIGHT, 0.4, 0.3)
	kiln_fire.visible = false
	for vent: Dictionary in layout.table.get("vents", []):
		if vent.id == "kiln":
			steam.kiln = _plume(Values.vec3(vent.at), 1.2)

## The parts posed and the surfaces levelled for this frame, before the
## hands take hold of them.
func settle() -> void:
	_pose_parts()
	_level_surfaces()

## The streams, the fires and the sounds of this frame, after the hands: a
## tipped thing pours from where the hand holds it now.
func run(delta: float) -> void:
	_run_streams()
	_burn()
	_sound_running(delta)

# ---- Parts ------------------------------------------------------------------------

## The taps, cocks, damper and hatch as the day has them; the work's part as
## the hand holds it; the windlass at the bucket's height; the hourglass.
func _pose_parts() -> void:
	var building := house.building
	if building == null or building.machinery == null:
		return
	var day := house.day
	for work_id: String in BrewStation.CONTROLS:
		_set_pose(_part_of(work_id), Values.real(day.controls[work_id]))
	for control: String in BrewCellar.CONTROLS:
		_set_pose(str(BrewCellar.PARTS[control]), Values.real(house.cellar.controls[control]))
	for control: String in BrewMaltings.CONTROLS:
		_set_pose(str(BrewMaltings.PARTS[control]), Values.real(house.maltings.controls[control]))
	_set_pose("quern_runner", house.maltings.quern_angle)
	_set_pose("windlass", day.lift / BrewDay.LIFT_TURN * TAU)
	_set_pose("hourglass", 1.0 if day.hourglass_up else 0.0)
	var station := house.work.station
	if station != null and station.work().has("part") and (station.work().gesture == "rock" or station.work().id == "taste"):
		_set_pose(str(station.work().part), station.pose(day))

static func _part_of(work_id: String) -> String:
	for works: Array in BrewStation.stations().values():
		for work: Dictionary in works:
			if work.id == work_id:
				return str(work.get("part", ""))
	return ""

func _set_pose(part: String, amount: float) -> void:
	var group := str(house.layout.groups.get(part, ""))
	if group == "" or is_equal_approx(Values.real(_posed.get(group, NAN)), amount):
		return
	_posed[group] = amount
	house.building.machinery.set_pose(group, amount)

# ---- Surfaces ---------------------------------------------------------------------

## Each vessel's surface at its level, of the colour of what it holds; the
## steam over what is hot.
func _level_surfaces() -> void:
	var layout := house.layout
	var day := house.day
	for id: String in layout.surfaces:
		var surface: Dictionary = layout.surfaces[id]
		var node: Node3D = surface.node
		if BrewLayout.TUN_SURFACES.has(id):
			_level_tun(id, surface)
			continue
		if BrewLayout.MALT_SURFACES.has(id):
			_level_malt(id, surface)
			continue
		if BrewLayout.SPRING_SURFACES.has(id):
			continue
		var held := BrewGauges.contents(day, id)
		node.visible = held != ""
		if held == "":
			continue
		node.position.y = layout.surface_height(id) - Values.real(surface.built)
		var material: ShaderMaterial = surface.material
		var boil := 0.0
		var foam := 0.0
		if id == BrewDay.COPPER:
			boil = boiling()
			if held == "wort" and boil > 0.5:
				foam = 0.85 if day.batch.boil_minutes < BrewBatch.FOAM_MINUTES else 0.3
		elif held == "wort":
			foam = 0.15
		material.set_shader_parameter("tint", _tint(id, held))
		material.set_shader_parameter("boil", boil)
		material.set_shader_parameter("foam", foam)
		material.set_shader_parameter("thick", 1.0 if held == "mash" or held == "grain" else 0.0)
	var maltings := house.maltings
	for key: String in steam:
		var plume: CPUParticles3D = steam[key]
		if key == "kiln":
			# Drying malt breathes out of the kiln's cowl.
			plume.emitting = maltings.kiln != null and maltings.kiln.stage == "green" and maltings.kiln.moisture > MaltLot.DAMP \
				and maltings.kiln_temp > MaltLot.WARM
			continue
		var hot := 0.0
		match key:
			"copper":
				hot = (BrewGauges.temperature(day, BrewDay.COPPER) - 60.0) / 40.0 * Values.real(day.controls.hatch)
			"cupola":
				hot = (BrewGauges.temperature(day, BrewDay.COPPER) - 95.0) / 5.0
			"mash":
				hot = (BrewGauges.temperature(day, BrewDay.MASH_TUN) - 45.0) / 30.0
			"hop_back":
				hot = (BrewGauges.temperature(day, BrewDay.HOP_BACK) - 50.0) / 40.0
			"coolship":
				hot = (BrewGauges.temperature(day, BrewDay.COOLSHIP) - 35.0) / 50.0
		var vessel := str({"mash": BrewDay.MASH_TUN, "hop_back": BrewDay.HOP_BACK, "coolship": BrewDay.COOLSHIP}.get(key, BrewDay.COPPER))
		plume.emitting = hot > 0.0 and BrewGauges.contents(day, vessel) != ""
		plume.speed_scale = clampf(0.5 + hot, 0.5, 1.5)

## The maltings' grain: the tub's at the level of its grain and water, a heap
## as large as its kg; tinted by how far the grain has come.
func _level_malt(id: String, surface: Dictionary) -> void:
	var node: Node3D = surface.node
	var maltings := house.maltings
	var lot: MaltLot = {"steep_grain": maltings.steep, "couch_malt": maltings.couch, "kiln_malt": maltings.kiln}[id]
	var water := maltings.steep_water_l if id == "steep_grain" else 0.0
	node.visible = lot != null or water > 0.5
	if not node.visible:
		return
	var material: ShaderMaterial = surface.material
	var entry: Dictionary = surface.entry
	if entry.has("heap"):
		var size := clampf(lot.kg / Values.real(HEAP_KG[id]), 0.15, 1.2)
		node.scale = Vector3(sqrt(size), size, sqrt(size))
	else:
		var bulk := (lot.kg * BrewGauges.GRAIN_BULK if lot != null else 0.0) + water
		var full := Values.real(house.day.capacity.get(id, 0.0))
		var level := clampf(bulk / full, 0.0, 1.0) if full > 0.0 else 0.0
		node.position.y = lerpf(Values.real(entry.bottom), Values.real(entry.brim), level) - Values.real(surface.built)
	var wet := water > 0.5 or (lot != null and (lot.stage == "steeped" or (lot.stage == "green" and lot.moisture > MaltLot.WET)))
	var tint := DEEP_WATER if lot == null else malt_tint(lot)
	material.set_shader_parameter("tint", tint.darkened(WET_DARK) if wet and lot != null else tint)
	material.set_shader_parameter("boil", 0.0)
	material.set_shader_parameter("foam", 0.0)
	material.set_shader_parameter("thick", 1.0 if lot != null else 0.0)

## The colour of a lot of grain: barley straw-gold, green malt duller, kilned
## malt as dark as its colour, the kiln's darkening as it roasts.
static func malt_tint(lot: MaltLot) -> Color:
	var base := GREEN_MALT if lot.stage == "steeped" or lot.stage == "green" else GRAIN
	var dark := clampf(log(maxf(lot.color, 4.0) / 4.0) / log(150.0), 0.0, 0.9)
	if lot.stage == "green":
		dark = maxf(dark, clampf(lot.roast_minutes / 120.0, 0.0, 0.7))
		if lot.stew_minutes >= MaltLot.STEW_MINUTES:
			dark = maxf(dark, 0.3)
		if lot.peak_heat > MaltLot.BURN_HEAT:
			dark = 0.9
	return base.darkened(dark)

## A fermenting tun's beer at its level, its head of yeast over it while one
## stands to be skimmed.
func _level_tun(id: String, surface: Dictionary) -> void:
	var node: Node3D = surface.node
	var cellar := house.cellar
	var foam := id.ends_with("_foam")
	var number := int(id.get_slice("_", 2))
	node.visible = cellar.tun_l(number) > 0.5 and (not foam or BrewYeast.head(cellar, number))
	if not node.visible:
		return
	var wort := "fermenting_tun_%d_wort" % number
	node.position.y = house.layout.surface_height(wort) - Values.real(house.layout.surfaces[wort].built) + (0.03 if foam else 0.0)
	var material: ShaderMaterial = surface.material
	var batch := cellar.tun_batch(number)
	var working := batch.stage == BrewIds.STAGE_PITCHED and batch.ferment_days >= 1 and batch.ferment < 1.0
	material.set_shader_parameter("tint", YEAST if foam else wort_color(batch_ebc(batch), VESSEL_DEPTH))
	material.set_shader_parameter("boil", 0.0)
	material.set_shader_parameter("foam", 1.0 if foam else (0.35 if working else 0.15))
	material.set_shader_parameter("thick", 1.0 if foam else 0.0)

## EBC of a batch's wort or beer.
static func batch_ebc(batch: BrewBatch) -> float:
	return 300.0 * (1.0 - exp(-batch.color_points / maxf(batch.volume_l, 1.0) * 7.0 / 300.0))

## The colour of what a vessel holds.
func _tint(id: String, held: String) -> Color:
	match held:
		"water":
			return DEEP_WATER
		"mash", "grain":
			return MASH.darkened(clampf(_ebc(id) / 120.0, 0.0, 0.6) + (0.25 if held == "grain" else 0.0))
	return wort_color(_ebc(id), VESSEL_DEPTH)

## EBC of the wort or mash in a vessel now.
func _ebc(id: String) -> float:
	var day := house.day
	var liters := day.batch.volume_l if day.batch.volume_l > 0.0 else maxf(BrewGauges.liters(day, id), day.batch.mash_l)
	return 300.0 * (1.0 - exp(-day.batch.color_points / maxf(liters, 1.0) * 7.0 / 300.0))

## The colour wort of `ebc` shows: light through `depth` hands of it, the
## red going through farthest. A vessel shows more depth than a stream, and
## its body sends back less light than a thin jet lit through. Pale wort
## (8 EBC) is gold in a vessel; dark goes red-brown, then near black.
static func wort_color(ebc: float, depth := 1.0) -> Color:
	var through := Vector3(exp(-ebc * 0.003 * depth), exp(-ebc * 0.008 * depth), exp(-ebc * 0.035 * depth))
	var body := 1.0 if depth <= 1.0 else 0.9
	return Color(0.68 * through.x * body, 0.54 * through.y * body, 0.22 * through.z * body)

## How hard the copper boils, 0..1.
func boiling() -> float:
	var day := house.day
	if BrewGauges.contents(day, BrewDay.COPPER) == "":
		return 0.0
	return clampf((BrewGauges.temperature(day, BrewDay.COPPER) - 85.0) / 15.0, 0.0, 1.0) * clampf(0.3 + day.fire, 0.0, 1.0)

# ---- Streams ----------------------------------------------------------------------

## The streams that run now.
func _run_streams() -> void:
	var layout := house.layout
	var day := house.day
	for key: String in streams:
		streams[key].stop()
	for control: String in TAPS:
		var open := Values.real(day.controls[control])
		var source := BrewDay.HOP_BACK if control == "hop_back_tap" else BrewDay.MASH_TUN if control == "mash_tap" else BrewDay.COPPER
		var runs := BrewGauges.liters(day, source) > 0.01
		match control:
			"liquor_cock":
				runs = BrewGauges.contents(day, BrewDay.COPPER) == "water"
			"mash_tap":
				runs = day.free_wort() > 0.0
		if open <= 0.0 or not runs:
			continue
		var from: Vector3 = layout.anchors[TAPS[control][0]]
		var into: String = TAPS[control][1]
		var to := layout.surface_point(into) if into != "" else _floor_under(control, from)
		var colour := WATER if control == "liquor_cock" else wort_color(_ebc(source))
		streams[control].pour(to_global(from), to_global(Vector3(from.x, to.y, from.z)), open, 0.035,
			Color(colour, 0.85))
	_run_cellar_streams()
	var plug := Values.real(house.maltings.controls.steep_plug)
	if plug > 0.0 and house.maltings.steep_water_l > 0.01:
		var drain: Vector3 = layout.anchors["steep_drain"]
		var under := _floor_under("steep_drain", drain)
		streams["steep_drain"].pour(to_global(drain), to_global(Vector3(drain.x, under.y, drain.z)), plug, 0.03,
			Color(WATER, 0.85))
	_run_work_streams()

## What the hand's work pours: a tipped thing's stream, a pump's spout.
func _run_work_streams() -> void:
	var station := house.work.station
	if station == null:
		return
	var layout := house.layout
	var day := house.day
	var held := house.carry.held
	var work := station.work()
	var land := layout.pour_landing(str(work.id), station)
	if land.is_finite() and station.gesture.flow() > 0.0:
		var node := layout.node_of(held)
		var mouth := node.global_transform * (layout.grip_local(held) * 1.05)
		if layout.sideways(held):
			mouth = layout.grip(held) - house.body.hold_frame().basis.x * layout.radius(held)
		var grain: bool = GRAIN_POURS.has(work.id) or work.id == "weigh_hops"
		var colour := GRAIN if GRAIN_POURS.has(work.id) else HOPS if work.id == "weigh_hops" else WATER
		if work.id == "pour_honey":
			colour = HONEY
		elif work.id == "cherry_cask":
			colour = CHERRY
		match str(work.id):
			"pour_coolship":
				colour = wort_color(_ebc(BrewDay.COOLSHIP))
			"pitch":
				colour = YEAST
			"fill_cask":
				var bucket := house.cellar.bucket_batch
				colour = wort_color(batch_ebc(bucket)) if bucket != null else WATER
		var landing := to_global(land)
		landing.x = mouth.x
		landing.z = mouth.z
		streams["grain"].pour(mouth, landing, station.gesture.flow(), 0.14 if grain else 0.06, Color(colour, 0.9), grain)
	elif work.gesture == "rock" and station.gesture.amount > 0.5:
		var outlet: Vector3 = layout.anchors["liquor_pipe_outlet" if work.id == "pump_liquor" else "wort_pump_outlet"]
		if work.id == "pump_liquor" and Values.real(day.controls.pipe_cock) < 0.5:
			outlet = layout.anchors["liquor_spout"]
		var to := Vector3(outlet.x, layout.surface_height(BrewDay.COPPER) if BrewGauges.contents(day, BrewDay.COPPER) != "" else 1.2, outlet.z)
		if outlet == layout.anchors["liquor_spout"]:
			to.y = 0.5
		streams["liquor_pipe"].pour(to_global(outlet), to_global(to), station.gesture.amount, 0.04, Color(WATER, 0.8))

## The cellar's taps: the plate's wort down the spout into a tun, a tun's
## tap into the bucket under it, a cask's tap into the keg under it; else
## onto the floor.
func _run_cellar_streams() -> void:
	var layout := house.layout
	var cellar := house.cellar
	if Values.real(cellar.controls.coolship_gate) > 0.0 and house.day.coolship_l > 0.01:
		var tun := cellar.spout_tun()
		var nozzle: Vector3 = layout.anchors["spout_nozzle_%d" % tun]
		var into := layout.surface_point("fermenting_tun_%d_wort" % tun) if cellar.tun_l(tun) > 0.5 \
			else layout.anchors["fermenting_tun_%d_bottom" % tun]
		_pour_stream("spout", nozzle, into.y, Values.real(cellar.controls.coolship_gate), wort_color(_ebc(BrewDay.COOLSHIP)))
	for number in range(1, BrewCellar.TUNS + 1):
		var tap := Values.real(cellar.controls["fermenter_tap_%d" % number])
		if tap <= 0.0 or cellar.tun_l(number) <= 0.01:
			continue
		var nozzle: Vector3 = layout.anchors["fermenter_tap_%d_nozzle" % number]
		var bottom := 0.0
		var under := "fermenter_%d_bucket" % number
		if cellar.bucket_at == under:
			bottom = layout.anchors[under].y + 0.05 + 0.45 * cellar.bucket_l / BrewCellar.BUCKET_L
		_pour_stream("fermenter_tap_%d" % number, nozzle, bottom, tap, wort_color(batch_ebc(cellar.tun_batch(number))))
	var station := house.work.station
	for number in range(1, BrewCellar.CASKS + 1):
		var cask: Dictionary = cellar.casks[number - 1]
		var open := Values.real(cellar.controls["lager_tap_%d" % number])
		if station != null and station.number == number and station.work().id == "taste":
			open = station.gesture.amount
		if open <= 0.0 or Values.real(cask.liters) <= 0.01:
			continue
		var nozzle: Vector3 = layout.anchors["lager_tap_%d_nozzle" % number]
		var keg := cellar.rack.keg_under[number - 1]
		var bottom := layout.bung(keg).y if keg != "" else 0.0
		var batch: BrewBatch = cask.batch
		_pour_stream("lager_tap_%d" % number, nozzle, bottom, open, wort_color(batch_ebc(batch)))

## A stream from `from` straight down to the height `to_y`; a lip above the
## nozzle takes it at the nozzle's foot.
func _pour_stream(key: String, from: Vector3, to_y: float, open: float, colour: Color) -> void:
	var to := Vector3(from.x, minf(to_y, from.y - 0.05), from.z)
	streams[key].pour(to_global(from), to_global(to), open, 0.03, Color(colour, 0.85))

## Where a tap with no vessel of its own pours: into the hoist bucket under it, or onto the floor.
func _floor_under(control: String, from: Vector3) -> Vector3:
	if control == "hop_back_tap" and house.day.hooked and house.day.lift <= 0.01:
		return Vector3(from.x, house.layout.home("hoist_bucket").y + 0.35, from.z)
	return Vector3(from.x, 0.0, from.z)

# ---- Fires and sounds --------------------------------------------------------------

## The fire under the copper and the kiln's: their flames and their lamps.
func _burn() -> void:
	var day := house.day
	fire.visible = day.fire > BrewDay.FIRE_OUT
	fire.scale = Vector3.ONE * (0.4 + 0.8 * day.fire)
	kiln_fire.visible = house.maltings.fire() > 0.02
	kiln_fire.scale = Vector3.ONE * (0.4 + 0.8 * house.maltings.fire())
	if house.building != null:
		house.building.stoke("Copper firebox", clampf(day.fire * 1.4, 0.0, 1.4))
		house.building.stoke("Kiln fire", clampf(house.maltings.fire() * 1.4, 0.0, 1.4))

## The sounds of what runs on its own: each stream, the boil, the fires.
func _sound_running(delta: float) -> void:
	var anchors := house.layout.anchors
	for key: String in streams:
		var stream: BrewStream = streams[key]
		if stream.flow > 0.0:
			sounds.hum(key, "grain" if stream.grain else "pour", stream.from_point, stream.flow)
	sounds.hum("boil", "boil", to_global(anchors["copper_hatch"]), boiling())
	sounds.hum("copper_fire", "fire", to_global(anchors["copper_stoke"]), house.day.fire)
	sounds.hum("kiln_fire", "fire", to_global(anchors["kiln_stoke"]), house.maltings.fire())
	sounds.settle(delta)

func _plume(at: Vector3, size: float) -> CPUParticles3D:
	var material := ShaderMaterial.new()
	material.shader = STEAM
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = material
	var plume := CPUParticles3D.new()
	plume.position = at
	plume.mesh = quad
	plume.amount = 24
	plume.lifetime = 3.5
	plume.direction = Vector3.UP
	plume.spread = 12.0
	plume.initial_velocity_min = 0.2
	plume.initial_velocity_max = 0.45
	plume.gravity = Vector3(0.0, 0.08, 0.0)
	plume.damping_min = 0.05
	plume.damping_max = 0.1
	plume.angle_min = -180.0
	plume.angle_max = 180.0
	plume.angular_velocity_min = -20.0
	plume.angular_velocity_max = 20.0
	plume.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	plume.emission_sphere_radius = size * 0.3
	# Steam spreads as it rises and thins away.
	plume.scale_amount_min = 0.5
	plume.scale_amount_max = 0.8
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 1.0))
	plume.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	fade.add_point(0.2, Color(1.0, 1.0, 1.0, 1.0))
	plume.color_ramp = fade
	plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plume.emitting = false
	add_child(plume)
	return plume
