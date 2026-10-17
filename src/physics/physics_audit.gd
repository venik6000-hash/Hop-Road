class_name PhysicsAudit
extends Node
## Holds every CollisionObject3D of the level to the rules of PhysicsLayers
## (docs/LEVEL.md, «Сторож»): a live shape that is not degenerate, one layer
## of PhysicsLayers.MASKS, the mask of that layer, CCD and mass on a rigid
## body. It checks the bodies under its parent when it enters the tree and
## each body added later, once, at the end of the frame the body is added in:
## code often gives a body its shapes after add_child. A body that gets its
## shapes only after an await is checked too early. Nothing runs per frame.

## A body breaks a rule: `message` names the body, the rule and the values.
signal violation(body: CollisionObject3D, message: String)

## Every violation seen so far.
var violations: PackedStringArray = []
## Bodies checked so far.
var checked := 0
## Untyped: a body may be freed before the flush.
var _pending: Array = []

const EPSILON := 0.00001

func _enter_tree() -> void:
	get_tree().node_added.connect(_on_node_added)

func _exit_tree() -> void:
	get_tree().node_added.disconnect(_on_node_added)

func _ready() -> void:
	for node in get_parent().find_children("*", "CollisionObject3D", true, false):
		_queue(node)

## Checks every body under the parent again now; returns what is wrong now.
func audit_all() -> PackedStringArray:
	var found := PackedStringArray()
	for node in get_parent().find_children("*", "CollisionObject3D", true, false):
		found.append_array(_check(node as CollisionObject3D))
	return found

func _on_node_added(node: Node) -> void:
	if node is CollisionObject3D and get_parent().is_ancestor_of(node):
		_queue(node)

func _queue(body: Object) -> void:
	if _pending.is_empty():
		_flush.call_deferred()
	_pending.append(body)

func _flush() -> void:
	var bodies := _pending
	_pending = []
	for item: Variant in bodies:
		if not is_instance_valid(item):
			continue
		var body: CollisionObject3D = item
		if body.is_inside_tree():
			_check(body)

func _check(body: CollisionObject3D) -> PackedStringArray:
	checked += 1
	var found := PackedStringArray()
	for problem in problems(body):
		var where: Variant = body.get_path() if body.is_inside_tree() else body.name
		var message := "PhysicsAudit: %s: %s" % [where, problem]
		push_error(message)
		violations.append(message)
		violation.emit(body, message)
		found.append(message)
	return found

## What is wrong with `body`, one line a rule; empty when nothing is.
static func problems(body: CollisionObject3D) -> PackedStringArray:
	var out := PackedStringArray()
	var live := 0
	for owner_id in body.get_shape_owners():
		var shapes := body.shape_owner_get_shape_count(owner_id)
		if shapes == 0:
			out.append("shape: a shape owner without a shape (%s)" % body.shape_owner_get_owner(owner_id))
		if body.is_shape_owner_disabled(owner_id):
			continue
		var flat := absf(body.shape_owner_get_transform(owner_id).basis.determinant()) < EPSILON
		for index in shapes:
			var shape := body.shape_owner_get_shape(owner_id, index)
			var why := degenerate(shape)
			if why.is_empty() and flat:
				why = "the owner's scale is zero"
			if why.is_empty():
				live += 1
			else:
				out.append("shape: degenerate %s: %s" % [shape.get_class() if shape != null else "null", why])
	if live == 0 and PhysicsLayers.exception_for(body, "shape").is_empty():
		out.append("shape: no live shape")
	var layer := body.collision_layer
	var mask := PhysicsLayers.mask_of(layer)
	if mask < 0:
		out.append("layer: %d is not one layer of PhysicsLayers" % layer)
	else:
		var zone := layer == PhysicsLayers.ZONES
		if zone != (body is Area3D):
			out.append("layer: an Area3D lies on ZONES and only an Area3D does (layer %d)" % layer)
		var allowed := mask
		var row := PhysicsLayers.exception_for(body, "mask")
		if not row.is_empty():
			allowed = Values.whole(row["mask"])
		if body.collision_mask != allowed:
			out.append("mask: %d on layer %s, PhysicsLayers wants %d" % [body.collision_mask, PhysicsLayers.NAMES[layer], allowed])
	if body is RigidBody3D:
		var rigid := body as RigidBody3D
		if not rigid.continuous_cd:
			out.append("rigid: continuous_cd is off")
		if rigid.mass <= 0.0:
			out.append("rigid: mass %f is not above zero" % rigid.mass)
	return out

## Why `shape` encloses nothing, or "" when it is a working shape.
static func degenerate(shape: Shape3D) -> String:
	if shape == null:
		return "no shape resource"
	if shape is BoxShape3D:
		var size := (shape as BoxShape3D).size
		if minf(size.x, minf(size.y, size.z)) <= EPSILON:
			return "size %s" % size
	elif shape is SphereShape3D:
		if (shape as SphereShape3D).radius <= EPSILON:
			return "radius 0"
	elif shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		if capsule.radius <= EPSILON or capsule.height <= EPSILON:
			return "radius %f, height %f" % [capsule.radius, capsule.height]
	elif shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		if cylinder.radius <= EPSILON or cylinder.height <= EPSILON:
			return "radius %f, height %f" % [cylinder.radius, cylinder.height]
	elif shape is ConcavePolygonShape3D:
		if (shape as ConcavePolygonShape3D).get_faces().size() < 3:
			return "no faces"
	elif shape is ConvexPolygonShape3D:
		if (shape as ConvexPolygonShape3D).points.size() < 4:
			return "fewer than four points"
	elif shape is HeightMapShape3D:
		var map := shape as HeightMapShape3D
		if map.map_width < 2 or map.map_depth < 2 or map.map_data.size() < map.map_width * map.map_depth:
			return "map %d x %d with %d heights" % [map.map_width, map.map_depth, map.map_data.size()]
	elif shape is SeparationRayShape3D:
		if (shape as SeparationRayShape3D).length <= EPSILON:
			return "length 0"
	return ""
