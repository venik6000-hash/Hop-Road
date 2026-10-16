class_name BrewStalls
extends Node3D
## The brewing's trade in the valley (docs/plans/brewing.md, section 6): a
## trust stall (chest, price board, coin box) at each place of trade.json's
## `stalls`, the order board at the market, the cart at the cellar gates. Each
## stands where the data says, turned so that its front faces the data's
## `face`, on colliders of its boxes. The models, their points (where the
## eye takes them, their boxes) and their materials (the tavern's, by the
## names the glTF surfaces carry) are assets/models/trade/. The level stands it
## before the vegetation, whose obstacle scan must see its colliders. What E
## does at them is BrewHouse's.

const MODELS := {"stall": "res://assets/models/trade/stall.glb", "order_board": "res://assets/models/trade/order_board.glb",
	"cart": "res://assets/models/trade/cart.glb"}
const POINTS := "res://assets/models/trade/trade.json"
const TAVERN_MATERIALS := preload("res://src/tavern/tavern_materials.gd")
## The points of a model the eye takes it by.
const LOOKS := {"stall": ["price_board", "coin_slot", "chest_lid"], "order_board": ["board"], "cart": ["bed"]}

## id -> {kind ("stall", "order_board", "cart"), title, node, looks (world points)}.
var places := {}

## The stalls, the board and the cart of `trade`'s data.
func build(trade: BrewTrade) -> void:
	var points: Variant = DataFile.read(POINTS, BuildingSchemas.trade_models())
	if not points is Dictionary:
		return
	for entry: Dictionary in trade.stalls():
		_place(str(entry.id), "stall", entry, points)
	if trade.data.has("order_board"):
		_place("order_board", "order_board", trade.data.order_board, points)
	if trade.data.has("cart"):
		_place("cart", "cart", trade.data.cart, points)

## Where a place of the data stands: at `at`, its front (+Z) turned to `face`.
static func placement(entry: Dictionary) -> Transform3D:
	var at: Array = entry.at
	var face: Array = entry.face
	var origin := Vector3(float(at[0]), float(at[1]), float(at[2]))
	var yaw := atan2(float(face[0]) - origin.x, float(face[1]) - origin.z)
	return Transform3D(Basis(Vector3.UP, yaw), origin)

func _place(id: String, kind: String, entry: Dictionary, points: Dictionary) -> void:
	var model_points: Dictionary = points.get(kind, {})
	var node := (load(MODELS[kind]) as PackedScene).instantiate() as Node3D
	node.name = id.to_pascal_case()
	node.transform = placement(entry)
	add_child(node)
	# The grime of the materials gathers at the foot of the place.
	var materials := {}
	TAVERN_MATERIALS.build(points, node.position.y, materials)
	for item: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		for surface in item.mesh.get_surface_count():
			var old := item.mesh.surface_get_material(surface)
			if old != null and materials.has(old.resource_name):
				item.set_surface_override_material(surface, materials[old.resource_name])
		item.layers = TavernSystem.SUN_LAYER
		item.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var body := StaticBody3D.new()
	body.name = "Body"
	node.add_child(body)
	for box: Dictionary in model_points.get("colliders", []):
		var shape := BoxShape3D.new()
		shape.size = _vector(box.size)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position = _vector(box.center)
		body.add_child(collider)
	var looks: Array[Vector3] = []
	for key: String in LOOKS[kind]:
		if model_points.has(key):
			looks.append(node.transform * _seen(_vector(model_points[key]), model_points.get("colliders", [])))
	places[id] = {"kind": kind, "title": str(entry.get("title", "")), "node": node, "looks": looks}

## A point inside one of the boxes is seen on the box's front face, from where
## the buyer stands: the eye's ray stops there.
static func _seen(point: Vector3, boxes: Array) -> Vector3:
	for box: Dictionary in boxes:
		var bounds := AABB(_vector(box.center) - _vector(box.size) * 0.5, _vector(box.size))
		if bounds.has_point(point):
			point.z = bounds.end.z + 0.01
	return point

static func _vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
