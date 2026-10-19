extends RefCounted
## What wheels and feet do to the ground of a yard. A region's plan
## (RegionDef.worn_ground) names the yards, the routes carts and people take
## across them, the things that stand in them, and the patches of softly worn
## earth round the village's yards; a building of the region adds its own
## yard from its table (`worn`). The ground bake makes from it
## (tools/pipeline/terrain/ground_bake.gd), and the game reads what it made:
##   - the terrain's path mask (near_control, R) is painted over. A yard is
##     bare along its routes and as far from them as people stray, and left
##     to the grass in the corners nobody crosses, at its edges, under its
##     walls and fences, and at the foot of what stands in it; a route beyond
##     a yard is worn bare. The grass and the flowers read the same mask;
##   - a field (wear_field of terrain.gdshader) says how far a point is from
##     the middle of the nearest cart track and of the nearest footpath, and
##     where the bare ground is trodden earth and not the stones of a road.
##     The shader draws the ruts and the trodden strips from it: a distance
##     holds up between texels, so a quarter of a metre to a texel draws a rut
##     a hand wide;
##   - a second field (cinder_field) says where coal dust and cinders are
##     trodden into the earth: a smithy's `cinder` patches. The ground is bare
##     there and its earth black;
##   - the patches wear the path mask bare round the yards of the village,
##     with ragged edges, and take the forest floor and the flowers there.
## The plan's file also holds the region's yard rule (`lawn`, `tree_wall`).
## The vegetation reads it, not the ground bake (ObstacleMap.lay_lawn,
## TreePlacer.wall_clearance).

const VILLAGE_BUILDINGS = preload("res://src/village/village_buildings.gd")
## Metres to a texel of the field, and the farthest distance it holds.
const CELL := 0.25
const REACH := 4.0
## Metres between the points of a smoothed route.
const STEP := 0.5
## The ground is bare within x metres of a route's middle and worn out to y:
## a cart's track, a footpath.
const CART := Vector2(1.0, 2.2)
const FOOT := Vector2(0.45, 1.5)
## The ruts of a track run out over this many metres at its ends.
const RUN_OUT := 2.5
## A yard's floor is bare within x metres of a route and grown over beyond y;
## the edge of the grass wanders by up to RAGGED metres, in bays FLOOR_PATCH
## metres across. The wear sets in over MARGIN metres from the yard's edge.
const TRAFFIC := Vector2(2.4, 4.4)
const RAGGED := 1.2
const FLOOR_PATCH := 2.6
const MARGIN := Vector2(0.4, 2.4)
## No foot falls within this share of a stand's radius of its middle.
const FOOT_OF_STAND := 0.5
## The cinders of a patch lie whole beyond its outline for up to this share
## of the metres they run out over, in bays CINDER_PATCH metres across.
const CINDER_RAGGED := 0.6
const CINDER_PATCH := 1.3

## The worn ground of `region` for the ground bake: paints the path mask
## `control` (texel (0, 0) at `origin`, `cell` metres apart) and returns the
## fields {wear, cinder (null without cinders), rect}; empty when the region
## wears no yard or route. The patches are painted either way, last.
static func bake(region: RegionDef, control: Image, origin: Vector2, cell: float) -> Dictionary:
	var plan := plan_of(region)
	var yards: Array = plan.yards
	var cart: Array = plan.cart
	var foot: Array = plan.foot
	var cinder: Array = plan.cinder
	var fields := {}
	if not (cart.is_empty() and foot.is_empty() and yards.is_empty() and cinder.is_empty()):
		paint(control, origin, cell, plan)
		var rect := field_rect(plan)
		fields = {"wear": field(plan, rect), "cinder": cinder_field(plan, rect) if not cinder.is_empty() else null,
			"rect": rect}
	paint_patches(control, origin, cell, plan)
	return fields

## The plan of `region` whole: its file (read()) and the yard each building
## brings in its table, in its own frame, stood at the building's place.
static func plan_of(region: RegionDef) -> Dictionary:
	var plan := read(region.worn_ground)
	for table: Dictionary in VILLAGE_BUILDINGS.tables(region):
		take(plan, Values.table(table.get("worn", {})), VILLAGE_BUILDINGS.pose(table))
	return plan

## The plan at `path`: {yards, cart, foot, stands, cinder, patches, lawn,
## tree_wall}. The first three are lists of PackedVector2Array (x, z): the
## yards' outlines and the routes, smoothed; the stands are Vector3 (x, z,
## the radius feet keep off); the patches of cinders are {outline:
## PackedVector2Array, fade: the metres over which the cinders run out round
## it}; the worn patches are Vector4 (x, z of the middle, the half sizes).
## The yard rule: `lawn` is Vector3 (metres round a cottage's yard, round a
## door, how near a wall a route's end makes a door), `tree_wall` the metres
## a trunk keeps from a wall; zero where the file names none. No path: an
## empty plan.
static func read(path: String) -> Dictionary:
	var plan := {"yards": [], "cart": [], "foot": [], "stands": [], "cinder": [], "patches": [],
		"lawn": Vector3.ZERO, "tree_wall": 0.0}
	if path.is_empty() or not FileAccess.file_exists(path):
		return plan
	var data: Variant = DataFile.read(path, BuildingSchemas.worn_ground())
	if data is Dictionary:
		var file: Dictionary = data
		take(plan, file, Transform3D.IDENTITY)
		var patches: Array = plan.patches
		for patch: Dictionary in file.get("patches", []):
			patches.append(Vector4(Values.real(patch.at[0]), Values.real(patch.at[1]), Values.real(patch.reach[0]), Values.real(patch.reach[1])))
		if file.has("lawn"):
			var lawn: Dictionary = file.lawn
			plan.lawn = Vector3(Values.real(lawn.yard), Values.real(lawn.door), Values.real(lawn.wall))
		plan.tree_wall = Values.real(file.get("tree_wall", 0.0))
	return plan

## Adds to `plan` what `data` names the way the plan's file does ({yards,
## routes, stands, cinder}), every point (x, z) stood in the map by `place`.
static func take(plan: Dictionary, data: Dictionary, place: Transform3D) -> void:
	var cinder: Array = plan.cinder
	for patch: Dictionary in data.get("cinder", []):
		cinder.append({"outline": _points(Values.list(patch.outline), place), "fade": Values.real(patch.fade)})
	var yards: Array = plan.yards
	for yard: Dictionary in data.get("yards", []):
		yards.append(_points(Values.list(yard.outline), place))
	for route: Dictionary in data.get("routes", []):
		var line: Array = plan[route.kind]
		line.append(smoothed(_points(Values.list(route.points), place)))
	var stands: Array = plan.stands
	for stand: Dictionary in data.get("stands", []):
		for at: Vector2 in _points(Values.list(stand.at), place):
			stands.append(Vector3(at.x, at.y, Values.real(stand.radius)))

static func _points(pairs: Array, place: Transform3D) -> PackedVector2Array:
	var points := PackedVector2Array()
	for pair: Array in pairs:
		var point := place * Vector3(Values.real(pair[0]), 0.0, Values.real(pair[1]))
		points.append(Vector2(point.x, point.z))
	return points

## A curve through `points`, a point to every STEP metres or less.
static func smoothed(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var line := PackedVector2Array()
	var last := points.size() - 1
	for i in last:
		var from := points[i]
		var to := points[i + 1]
		var steps := maxi(1, ceili(from.distance_to(to) / STEP))
		for k in steps:
			line.append(from.cubic_interpolate(to, points[maxi(i - 1, 0)], points[mini(i + 2, last)], float(k) / steps))
	line.append(points[last])
	return line

## How far `point` is from `line` (x) and how far along the line the nearest
## point of it lies (y), metres.
static func nearest(line: PackedVector2Array, point: Vector2) -> Vector2:
	var best := Vector2(INF, 0.0)
	var along := 0.0
	for i in line.size() - 1:
		var near := Geometry2D.get_closest_point_to_segment(point, line[i], line[i + 1])
		var distance := near.distance_to(point)
		if distance < best.x:
			best = Vector2(distance, along + line[i].distance_to(near))
		along += line[i].distance_to(line[i + 1])
	return best

static func length_of(line: PackedVector2Array) -> float:
	var length := 0.0
	for i in line.size() - 1:
		length += line[i].distance_to(line[i + 1])
	return length

## Metres from `point` to the middle of the nearest cart track (x) and of the
## nearest footpath (y); INF where the plan has none.
static func routes_away(plan: Dictionary, point: Vector2) -> Vector2:
	var away := Vector2(INF, INF)
	for line: PackedVector2Array in plan.cart:
		away.x = minf(away.x, nearest(line, point).x)
	for line: PackedVector2Array in plan.foot:
		away.y = minf(away.y, nearest(line, point).x)
	return away

## How bare (0..1) the routes wear the ground `away` (routes_away()) from them.
static func route_wear(away: Vector2) -> float:
	return maxf(1.0 - smoothstep(CART.x, CART.y, away.x), 1.0 - smoothstep(FOOT.x, FOOT.y, away.y))

## Metres from `point` to the edge of the yard it stands in, or -1 outside
## every yard.
static func inside(plan: Dictionary, point: Vector2) -> float:
	var depth := -1.0
	for yard: PackedVector2Array in plan.yards:
		if not Geometry2D.is_point_in_polygon(point, yard):
			continue
		var edge := INF
		for i in yard.size():
			edge = minf(edge, Geometry2D.get_closest_point_to_segment(point, yard[i], yard[(i + 1) % yard.size()]).distance_to(point))
		depth = maxf(depth, edge)
	return depth

## How much (0..1) of the ground `depth` metres in from a yard's edge is the
## yard's trodden floor and not the grass of its margin.
static func trodden(depth: float) -> float:
	return smoothstep(MARGIN.x, MARGIN.y, depth)

## How much (0..1) of a yard's wear reaches `point`: none at the foot of what
## stands there, all of it a stand's radius away.
static func open_ground(plan: Dictionary, point: Vector2) -> float:
	var open := 1.0
	for stand: Vector3 in plan.stands:
		open = minf(open, smoothstep(stand.z * FOOT_OF_STAND, stand.z, Vector2(stand.x, stand.y).distance_to(point)))
	return open

## How much (0..1) of the earth at `point` is cinders: all of it inside a
## patch, none `fade` metres from it, and a ragged edge between.
static func cinders(plan: Dictionary, point: Vector2) -> float:
	var black := 0.0
	for patch: Dictionary in plan.get("cinder", []):
		var outline: PackedVector2Array = patch.outline
		var fade: float = patch.fade
		var out := 0.0
		if not Geometry2D.is_point_in_polygon(point, outline):
			out = INF
			for i in outline.size():
				out = minf(out, Geometry2D.get_closest_point_to_segment(point, outline[i],
					outline[(i + 1) % outline.size()]).distance_to(point))
		black = maxf(black, 1.0 - smoothstep(noise(point / CINDER_PATCH) * CINDER_RAGGED * fade, fade, out))
	return black

## How bare (0..1) a yard's floor is at `point`, `depth` metres in from its
## edge and `away` metres from the nearest route.
static func floor_wear(point: Vector2, depth: float, away: float) -> float:
	var strayed := away + (noise(point / FLOOR_PATCH) - 0.5) * 2.0 * RAGGED
	return (1.0 - smoothstep(TRAFFIC.x, TRAFFIC.y, strayed)) * trodden(depth)

## Paints the plan into the path mask `image` (R: how bare; B: wood; A: flowers),
## whose texel (0, 0) lies at `origin` and whose texels are `cell` metres.
static func paint(image: Image, origin: Vector2, cell: float, plan: Dictionary) -> void:
	var box := _bounds(plan, CART.y)
	var lo := Vector2i(((box.position - origin) / cell).floor()).max(Vector2i.ZERO)
	var hi := Vector2i(((box.end - origin) / cell).ceil()).min(image.get_size() - Vector2i.ONE)
	for iz in range(lo.y, hi.y + 1):
		for ix in range(lo.x, hi.x + 1):
			var point := origin + Vector2(ix, iz) * cell
			var away := routes_away(plan, point)
			var worn := route_wear(away)
			var depth := inside(plan, point)
			var black := cinders(plan, point)
			var color := image.get_pixel(ix, iz)
			if depth >= 0.0:
				# The yard's own wear, in place of the blanket the mask laid over it.
				color.r = maxf(worn, floor_wear(point, depth, minf(away.x, away.y)) * open_ground(plan, point))
			elif worn > 0.0:
				color.r = maxf(color.r, worn)
			elif black <= 0.0:
				continue
			# Nothing grows in cinders.
			color.r = maxf(color.r, black)
			# No tree of the wood and no flowers where the ground is worn.
			color.b *= 1.0 - color.r
			color.a *= 1.0 - color.r
			image.set_pixel(ix, iz, color)

## Paints the worn patches of `plan` into the path mask `image` (texel (0, 0)
## at `origin`, `cell` metres apart): bare in an ellipse round each middle,
## with an edge that wanders, and no wood and no flowers where it is bare.
static func paint_patches(image: Image, origin: Vector2, cell: float, plan: Dictionary) -> void:
	for patch: Vector4 in plan.patches:
		var centre := Vector2(patch.x, patch.y)
		var reach := Vector2(patch.z, patch.w)
		var lo := Vector2i(((centre - reach * 1.2 - origin) / cell).floor())
		var hi := Vector2i(((centre + reach * 1.2 - origin) / cell).ceil())
		for iz in range(maxi(0, lo.y), mini(image.get_height(), hi.y + 1)):
			for ix in range(maxi(0, lo.x), mini(image.get_width(), hi.x + 1)):
				var point := origin + Vector2(ix, iz) * cell
				var distance := ((point - centre) / reach).length()
				distance += sin(point.x * 1.7) * cos(point.y * 1.3) * 0.055
				var wear := 1.0 - smoothstep(0.72, 1.12, distance)
				var color := image.get_pixel(ix, iz)
				color.r = maxf(color.r, wear)
				color.b *= 1.0 - wear
				color.a *= 1.0 - wear
				image.set_pixel(ix, iz, color)

## The rectangle (x, z) the field covers: every yard and route and REACH
## around them, on whole texels.
static func field_rect(plan: Dictionary) -> Rect2:
	var box := _bounds(plan, REACH)
	var corner := (box.position / CELL).floor() * CELL
	return Rect2(corner, ((box.end - corner) / CELL).ceil() * CELL)

## The field over `rect`, RGBA half floats: R the distance to the middle of
## the nearest cart track, G to that of the nearest footpath (REACH where
## none is as near), B how much of its ruts a track has at its nearest point
## (0 at its ends, 1 beyond RUN_OUT from them), A how much of the ground is
## trodden earth: a yard's floor, and what the routes wear beyond it.
static func field(plan: Dictionary, rect: Rect2) -> Image:
	var size := Vector2i((rect.size / CELL).round())
	var values := PackedFloat32Array()
	values.resize(size.x * size.y * 4)
	for index in size.x * size.y:
		values[index * 4] = REACH
		values[index * 4 + 1] = REACH
	for line: PackedVector2Array in plan.cart:
		_lay(values, size, rect.position, line, 0)
	for line: PackedVector2Array in plan.foot:
		_lay(values, size, rect.position, line, 1)
	for iz in size.y:
		for ix in size.x:
			var index := (iz * size.x + ix) * 4
			var earth := route_wear(Vector2(values[index], values[index + 1]))
			var at := rect.position + (Vector2(ix, iz) + Vector2(0.5, 0.5)) * CELL
			var depth := inside(plan, at)
			var bare := maxf(earth, trodden(depth)) if depth >= 0.0 else earth
			values[index + 3] = maxf(bare, cinders(plan, at))
	var image := Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBAF, values.to_byte_array())
	image.convert(Image.FORMAT_RGBAH)
	return image

## The cinders over `rect`, texel for texel with field(): R how much of the
## earth is cinders.
static func cinder_field(plan: Dictionary, rect: Rect2) -> Image:
	var size := Vector2i((rect.size / CELL).round())
	var image := Image.create(size.x, size.y, false, Image.FORMAT_R8)
	for iz in size.y:
		for ix in size.x:
			image.set_pixel(ix, iz, Color(cinders(plan, rect.position + (Vector2(ix, iz) + Vector2(0.5, 0.5)) * CELL), 0.0, 0.0))
	return image

## Lays the distances to `line` into channel 0 or 1 of `values`, segment by
## segment over the texels within REACH of each.
static func _lay(values: PackedFloat32Array, size: Vector2i, corner: Vector2, line: PackedVector2Array, channel: int) -> void:
	var length := length_of(line)
	var along := 0.0
	for i in line.size() - 1:
		var from := line[i]
		var to := line[i + 1]
		var lo := Vector2i(((from.min(to) - Vector2.ONE * REACH - corner) / CELL).floor()).max(Vector2i.ZERO)
		var hi := Vector2i(((from.max(to) + Vector2.ONE * REACH - corner) / CELL).ceil()).min(size - Vector2i.ONE)
		for iz in range(lo.y, hi.y + 1):
			for ix in range(lo.x, hi.x + 1):
				var point := corner + (Vector2(ix, iz) + Vector2(0.5, 0.5)) * CELL
				var near := Geometry2D.get_closest_point_to_segment(point, from, to)
				var distance := near.distance_to(point)
				var index := (iz * size.x + ix) * 4
				if distance >= values[index + channel]:
					continue
				values[index + channel] = distance
				if channel == 0:
					var run := along + from.distance_to(near)
					values[index + 2] = smoothstep(0.0, RUN_OUT, minf(run, length - run))
		along += from.distance_to(to)

static func _bounds(plan: Dictionary, margin: float) -> Rect2:
	var box := Rect2()
	var first := true
	for kind: String in ["yards", "cart", "foot"]:
		for line: PackedVector2Array in plan[kind]:
			for point in line:
				box = Rect2(point, Vector2.ZERO) if first else box.expand(point)
				first = false
	for patch: Dictionary in plan.get("cinder", []):
		# A patch reaches as far as its cinders run out.
		var reach := Vector2.ONE * Values.real(patch.fade)
		var outline: PackedVector2Array = patch.outline
		for point in outline:
			box = Rect2(point - reach, reach * 2.0) if first else box.expand(point - reach).expand(point + reach)
			first = false
	return box.grow(margin)

## Smooth noise 0..1 with a feature to every whole step of `at`, from a hash
## of whole numbers: the same on every machine.
static func noise(at: Vector2) -> float:
	var cell := at.floor()
	var t := at - cell
	t = t * t * (Vector2(3.0, 3.0) - 2.0 * t)
	return lerpf(lerpf(_chance(cell), _chance(cell + Vector2(1.0, 0.0)), t.x),
		lerpf(_chance(cell + Vector2(0.0, 1.0)), _chance(cell + Vector2(1.0, 1.0)), t.x), t.y)

static func _chance(cell: Vector2) -> float:
	var n := (int(cell.x) * 73856093) ^ (int(cell.y) * 19349663)
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float((n ^ (n >> 16)) & 0xffff) / 65535.0
