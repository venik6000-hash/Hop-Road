class_name BrewLayout
extends RefCounted
## Where things are in the brewery (BrewHouse): the anchors, stations and
## moving parts of its table (brewery.json), the utensils and the vessels'
## surfaces taken out of the rooms' scene, and the places the day and the
## cellar make of them (a surface at its level, a keg under a tap, where a
## tipped thing pours). Points are in the building's frame, the house's,
## unless a name says world.

## The vessels the day fills: their surfaces of the table.
const VESSELS: Array[String] = [BrewDay.COPPER, BrewDay.MASH_TUN, BrewDay.UNDERBACK, BrewDay.HOP_BACK, BrewDay.COOLSHIP]
## The fermenting tuns' surfaces of the table: the beer and its head of yeast.
const TUN_SURFACES: Array[String] = ["fermenting_tun_1_wort", "fermenting_tun_1_foam", "fermenting_tun_2_wort",
	"fermenting_tun_2_foam"]
## The maltings' grain: in the steeping tub, the heap on the floor, the kiln's.
const MALT_SURFACES: Array[String] = ["steep_grain", "couch_malt", "kiln_malt"]
## The spring's water, always full: the trough's in the brewhouse and the
## basin's in the cellar.
const SPRING_SURFACES: Array[String] = ["liquor_trough_water", "spring_basin_water"]
## Where a keg stands under a lager cask's tap, from the tap's nozzle: its bung
## hole just in front of the cask's head, the keg lying across the tap on the
## floor. The radius of a keg (its axis lies at that height).
const KEG_AT_TAP := Vector3(0.12, 0.0, 0.0)
const KEG_RADIUS := 0.19
## How far a lager cask's stand keeps from the spring basin's inner rim: its
## wall and the body.
const BASIN_CLEAR := 0.45
## Where the bucket is tipped into a lager cask, from its tap's nozzle: over
## the head's upper rim.
const CASK_MOUTH := Vector3(-0.08, 0.6, 0.0)
## Where a tipped thing is held at a station, and where what it pours lands:
## anchors of the table, by the work.
const POURS := {"grain": ["mash_in", BrewDay.MASH_TUN], "bucket_mash": ["mash_in", BrewDay.MASH_TUN],
	"bucket_copper": ["copper_hatch", BrewDay.COPPER], "fill_bucket": ["liquor_trough_brim", ""],
	"pour_coolship": ["coolship_pour", BrewDay.COOLSHIP], "weigh_hops": ["balance_pan_left", ""],
	"steep_barley": ["steep_brim", "steep_grain"], "steep_water": ["steep_brim", "steep_grain"], "pour_hopper": ["quern_eye", ""],
	"pour_honey": ["copper_hatch", BrewDay.COPPER]}

## The brewery whose frame the points are in, and whose day and cellar fill
## the vessels.
var house: BrewHouse
var table: Dictionary
var anchors: Dictionary[String, Vector3] = {}
## Station id -> its entry of the table; a lager cask's station is made here.
var stations := {}
## Moving part id -> its entry of the table, and its group (BuildingMachinery).
var moving := {}
var groups := {}
## id -> {entry, node (the utensil's own Node3D, origin at its `at`)}.
var utensils := {}
## id -> {entry, node, material, built (the height it was modelled at)}.
var surfaces := {}

func _init(of: BrewHouse, brewery: Dictionary) -> void:
	house = of
	table = brewery
	for entry: Dictionary in table.get("anchors", []):
		anchors[entry.id] = Values.vec3(entry.at)
	for entry: Dictionary in table.get("stations", []):
		stations[entry.id] = entry
	# A station for each lager cask, in front of its tap; before the spring's
	# basin, off its side.
	var basin := rim("spring_basin_brim")
	basin = basin.grow(BASIN_CLEAR) if basin.has_area() else basin
	for number in range(1, BrewCellar.CASKS + 1):
		var key := "lager_tap_%d_nozzle" % number
		if not anchors.has(key):
			continue
		var nozzle: Vector3 = anchors[key]
		var stand := Vector2(nozzle.x + 0.75, nozzle.z)
		if basin.has_point(stand):
			stand.y = basin.position.y
		stations["lager_%d" % number] = {"id": "lager_%d" % number, "title": "Лагерная бочка",
			"stand": [stand.x, 0.0, stand.y], "look": [nozzle.x - 0.05, nozzle.y + 0.1, nozzle.z]}
	for entry: Dictionary in table.get("moving", []):
		groups[entry.id] = str(entry.group)
		moving[entry.id] = entry

## Takes the utensils and the vessels' surfaces out of a part scene onto
## nodes of their own under the house, before the building batches what is
## left; the scene is in the building's frame, as the house is.
func take(scene: Node3D, liquid: Shader, deep_water: Color) -> void:
	for entry: Dictionary in table.get("utensils", []):
		var node := _gather(scene, Values.list(entry.nodes), Values.vec3(entry.at))
		if node != null:
			node.name = str(entry.id).to_pascal_case()
			utensils[entry.id] = {"entry": entry, "node": node}
	for entry: Dictionary in table.get("surfaces", []):
		if not VESSELS.has(entry.id) and not TUN_SURFACES.has(entry.id) and not MALT_SURFACES.has(entry.id) \
				and not SPRING_SURFACES.has(entry.id):
			continue
		# A heap grows from where it stands.
		var node := _gather(scene, [entry.node], Values.vec3(entry.at) if entry.has("heap") else Vector3.ZERO)
		if node == null:
			continue
		var material := ShaderMaterial.new()
		material.shader = liquid
		for item: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			item.material_override = material
		var built := 0.0
		if entry.has("brim"):
			built = Values.real(entry.bottom) + (Values.real(entry.brim) - Values.real(entry.bottom)) * Values.real(entry.level)
		if SPRING_SURFACES.has(entry.id):
			material.set_shader_parameter("tint", deep_water)
		surfaces[entry.id] = {"entry": entry, "node": node, "material": material, "built": built}

## The scene's nodes named `names` hung on a new node at `origin`, where they stood.
func _gather(scene: Node3D, names: Array, origin: Vector3) -> Node3D:
	var holder: Node3D
	for name: String in names:
		var item := scene.find_child(name.validate_node_name(), true, false) as Node3D
		if item == null:
			continue
		if holder == null:
			holder = Node3D.new()
			holder.position = origin
			house.add_child(holder)
		var placed := item.transform
		var above := item.get_parent_node_3d()
		while above != null and above != scene.get_parent():
			placed = above.transform * placed
			above = above.get_parent_node_3d()
		item.get_parent().remove_child(item)
		item.owner = null
		for inner: Node in item.find_children("*", "", true, false):
			inner.owner = null
		holder.add_child(item)
		item.transform = holder.transform.affine_inverse() * placed
	return holder

## The level rectangle the table gives anchor `id` (a brim), x and z;
## empty when none.
func rim(id: String) -> Rect2:
	for entry: Dictionary in table.get("anchors", []):
		if entry.id == id and entry.has("rect"):
			var corners: Array = entry.rect
			return Rect2(Values.vec2(corners[0]), Vector2.ZERO).expand(Values.vec2(corners[1]))
	return Rect2()

## The radius the table gives anchor `id` (a brim), 0 when none.
func brim_radius(id: String) -> float:
	for entry: Dictionary in table.get("anchors", []):
		if entry.id == id:
			return Values.real(entry.get("radius", 0.0))
	return 0.0

## A moving part's pivot, world space; not finite for none.
func moving_point(id: String) -> Vector3:
	if not moving.has(id):
		return Vector3(INF, INF, INF)
	return house.to_global(Values.vec3(moving[id].pivot))

## World points of the parts `works` move (their grip and pivot).
func part_points(works: Array) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for work: Dictionary in works:
		var part := str(work.get("part", ""))
		if not moving.has(part):
			continue
		var entry: Dictionary = moving[part]
		points.append(house.to_global(Values.vec3(entry.pivot)))
		if entry.has("grip"):
			points.append(house.to_global(Values.vec3(entry.grip)))
	return points

## Whether the work's part turns round an upright axis (a quern's crank).
func flat_crank(work: Dictionary) -> bool:
	if not work.has("part") or not moving.has(work.part):
		return false
	var part: Dictionary = moving[work.part]
	return str(part.kind) == "spin" and absf(Values.vec3(part.axis).normalized().y) > 0.9

## A station's stand and look, building frame.
func stand(station_id: String) -> Vector3:
	return Values.vec3(stations[station_id].stand)

func look(station_id: String) -> Vector3:
	return Values.vec3(stations[station_id].look)

# ---- Utensils --------------------------------------------------------------

## The Node3D of utensil `id`.
func node_of(id: String) -> Node3D:
	return utensils[id].node

func entry_of(id: String) -> Dictionary:
	return utensils[id].entry

## Where the hand takes a utensil, world space.
func grip(id: String) -> Vector3:
	return node_of(id).global_transform * grip_local(id)

func grip_local(id: String) -> Vector3:
	var entry := entry_of(id)
	return Values.vec3(entry.grip) - Values.vec3(entry.at)

## Where utensil `id` stands at home.
func home(id: String) -> Vector3:
	return Values.vec3(entry_of(id).at)

## Utensil `id` back at home under the house.
func send_home(id: String) -> void:
	var node := node_of(id)
	node.reparent(house)
	node.transform = Transform3D(Basis.IDENTITY, home(id))

## Whether utensil `id` is tipped over sideways at a pour: a basket or a
## pot, held by its rim or its handle.
func sideways(id: String) -> bool:
	return str(entry_of(id).kind) == "raw"

## Half the widest of utensil `id` across, metres: its rim's radius.
func radius(id: String) -> float:
	var entry: Dictionary = utensils[id]
	if not entry.has("radius"):
		var node: Node3D = entry.node
		var whole := AABB()
		for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			var box := node.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
			whole = box if whole.size == Vector3.ZERO else whole.merge(box)
		entry.radius = maxf(whole.size.x, whole.size.z) * 0.5
	return Values.real(entry.radius)

# ---- Kegs and casks ----------------------------------------------------------

## The turn about its own length that lays a keg with its bung hole up; kegs
## lie on the rack with it to the side.
func keg_upright(id: String) -> Basis:
	var bung_at := bung_local(id)
	return Basis(Vector3.RIGHT, -atan2(bung_at.z, bung_at.y))

## The bung hole of keg `id` in its own frame: the oak plug of its model.
func bung_local(id: String) -> Vector3:
	var node := node_of(id)
	for item: MeshInstance3D in node.find_children("*oak_end*", "MeshInstance3D", true, false):
		var box := item.get_aabb()
		return node.global_transform.affine_inverse() * item.global_transform * box.get_center()
	return Vector3(0.25, KEG_RADIUS, 0.0)

## The bung hole of keg `id` where it stands.
func bung(id: String) -> Vector3:
	return house.to_local(node_of(id).global_transform * bung_local(id))

## Where a keg lies under the tap of cask `number`: its bung hole up under
## the nozzle, the keg across the tap on the floor. The kegs are one model.
func keg_at_tap(number: int) -> Transform3D:
	var nozzle: Vector3 = anchors["lager_tap_%d_nozzle" % number]
	var facing := Basis(Vector3.UP, PI * 0.5) * keg_upright(BrewKegRack.KEGS[0])
	var origin := nozzle + KEG_AT_TAP - facing * bung_local(BrewKegRack.KEGS[0])
	origin.y = KEG_RADIUS
	return Transform3D(facing, origin)

## Where the eye puts a keg under the tap of cask `number`: the floor under
## the keg's middle.
func keg_aim(number: int) -> Vector3:
	var middle := keg_at_tap(number) * Vector3(bung_local(BrewKegRack.KEGS[0]).x, 0.0, 0.0)
	return Vector3(middle.x, 0.0, middle.z)

## Where a lager cask is filled: over the upper rim of its head.
func cask_mouth(number: int) -> Vector3:
	return anchors["lager_tap_%d_nozzle" % number] + CASK_MOUTH

# ---- Surfaces -------------------------------------------------------------------

## How full a vessel is, 0..1: the brewing day's, or a fermenting tun.
func fill(id: String) -> float:
	if not TUN_SURFACES.has(id):
		return BrewGauges.fill(house.day, id)
	var full := Values.real(house.day.capacity.get(id, 0.0))
	var liters := house.cellar.tun_l(int(id.get_slice("_", 2)))
	return clampf(liters / full, 0.0, 1.0) if full > 0.0 else 0.0

## The height of a vessel's surface at its level.
func surface_height(id: String) -> float:
	var entry: Dictionary = surfaces[id].entry
	return lerpf(Values.real(entry.bottom), Values.real(entry.brim), fill(id))

## The middle of a vessel's surface at its level.
func surface_point(id: String) -> Vector3:
	for entry: Dictionary in table.get("surfaces", []):
		if entry.id == id:
			var at := Values.vec3(entry.at)
			if house.day != null and surfaces.has(id):
				at.y = surface_height(id)
			return at
	return Vector3.ZERO

# ---- Pours ------------------------------------------------------------------------

## Where a tipped thing is held over at work `work_id` of `station`; not
## finite for a work that tips nothing.
func pour_over(work_id: String, station: BrewStation) -> Vector3:
	if POURS.has(work_id):
		return anchors[POURS[work_id][0]]
	match work_id:
		"pitch":
			return anchors["fermenting_tun_%d_brim" % station.number]
		"dip_yeast":
			return home("yeast_crock") + Vector3.UP * 0.3
		"scoop":
			return anchors["copper_hatch"]
		"fill_cask", "scald", "cherry_cask":
			return cask_mouth(station.number)
	return Vector3.INF

## Where what a tipped thing pours lands at work `work_id` of `station`; not
## finite for a work whose pour shows no stream (a bucket or a dipper filled).
func pour_landing(work_id: String, station: BrewStation) -> Vector3:
	if work_id == "fill_bucket" or work_id == "dip_yeast" or work_id == "scoop":
		return Vector3.INF
	var into := pour_vessel(work_id, station)
	if into != "":
		return surface_point(into)
	if POURS.has(work_id):
		return anchors[POURS[work_id][0]] - Vector3.UP * 0.2
	match work_id:
		"pitch":
			return anchors["fermenting_tun_2_bottom"]
		"fill_cask", "scald", "cherry_cask":
			return cask_mouth(station.number) - Vector3.UP * 0.1
	return Vector3.INF

## The surface a tipped thing pours onto at work `work_id` of `station`; ""
## when it lands in no vessel's face (a bucket, a cask, the floor).
func pour_vessel(work_id: String, station: BrewStation) -> String:
	if POURS.has(work_id):
		return str(POURS[work_id][1])
	if work_id == "pitch" and station.number == 1:
		return "fermenting_tun_1_wort"
	return ""

# ---- Save ---------------------------------------------------------------------------

## Where each utensil under the house stands that is not at home and not in
## the hand: id -> [x, y, z, yaw].
func places(held: String) -> Dictionary:
	var moved := {}
	for id: String in utensils:
		var node := node_of(id)
		if node.get_parent() != house:
			continue
		if id != held and node.position.distance_to(home(id)) > 0.001 and not (id == "hoist_bucket" and house.day.hooked):
			moved[id] = [node.position.x, node.position.y, node.position.z, node.rotation.y]
	return moved

## Reads back places(); a place that is wrong or far off is left out.
func restore_places(saved: Variant) -> void:
	if not saved is Dictionary:
		return
	var moved: Dictionary = saved
	for id: Variant in moved:
		var place: Variant = moved[id]
		if not utensils.has(id) or not place is Array:
			continue
		var values: Array = place
		if values.size() != 4:
			continue
		var numbers: Array[float] = []
		for value: Variant in values:
			if (value is float or value is int) and is_finite(Values.real(value)):
				numbers.append(Values.real(value))
		if numbers.size() == 4 and Vector3(numbers[0], numbers[1], numbers[2]).length() < 50.0:
			node_of(str(id)).transform = Transform3D(Basis(Vector3.UP, numbers[3]), Vector3(numbers[0], numbers[1], numbers[2]))

## The kegs upright under the taps and the funnel in a bung hole, as the cellar has them.
func seat_kegs(cellar: BrewCellar) -> void:
	for number in range(1, BrewCellar.CASKS + 1):
		var keg := cellar.rack.keg_under[number - 1]
		if keg != "":
			node_of(keg).transform = keg_at_tap(number)
	if cellar.rack.funnel_on != "" and cellar.rack.keg_under.has(cellar.rack.funnel_on):
		node_of("funnel").transform = Transform3D(Basis.IDENTITY, bung(cellar.rack.funnel_on))
