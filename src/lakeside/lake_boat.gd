class_name LakeBoat
extends CharacterBody3D
## Small clinker rowboat. Physics is independent of the camera and input focus.
## Top speed under the oars, m/s.
const TOP_SPEED := 2.7
## The hull's collision box, m.
const HULL := Vector3(1.50, 0.50, 3.7)
var terrain: TerrainSystem
var water: WaterSystem
var rowing := false
var throttle := 0.0
var steering := 0.0
var clock := 0.0
var oars: Array[Node3D] = []
var visual := Node3D.new()
var anchor := Vector3.ZERO
var last_stroke := -1
var _navigation_key: Array = []
var _navigation_clear := false
var _hull_yaw := INF
var _hull_basis := Basis.IDENTITY
signal stroke(point: Vector3)

func _ready() -> void:
	name = "Rowboat"
	collision_layer = PhysicsLayers.WORLD
	collision_mask = int(PhysicsLayers.exception_for(self, "mask")["mask"])
	add_child(visual)
	build_hull()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = HULL
	shape.shape = box
	shape.position.y = 0.0
	add_child(shape)
	anchor = position

func build_hull() -> void:
	var model := preload("res://assets/models/lakeside/rowboat.glb").instantiate() as Node3D
	visual.add_child(model)
	for part: String in ["OarPort", "OarStarboard"]:
		oars.append(model.find_child(part, true, false) as Node3D)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.visibility_range_end = 220
		mesh.visibility_range_end_margin = 20
		mesh.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

func can_navigate(at: Vector3) -> bool:
	# Buoyancy changes y each tick, but navigation depends only on x/z and yaw.
	var key: Array = [Vector2(at.x, at.z), rotation.y, water.water_level, terrain,
		terrain.near_image, terrain.far_image, terrain.near_origin, terrain.far_origin,
		terrain.near_cell, terrain.far_cell, terrain.near_size, terrain.far_size]
	if key == _navigation_key:
		return _navigation_clear
	_navigation_key = key
	_navigation_clear = _sample_navigation(at)
	return _navigation_clear

func _sample_navigation(at: Vector3) -> bool:
	if rotation.y != _hull_yaw:
		_hull_yaw = rotation.y
		_hull_basis = Basis(Vector3.UP, _hull_yaw)
	for z: float in [-1.85, 0.0, 1.85]:
		for x: float in [-0.72, 0.72]:
			var point := at + _hull_basis * Vector3(x, 0, z)
			if water.water_level - terrain.height_at(point.x, point.z) < 0.65:
				return false
	return true

func _physics_process(delta: float) -> void:
	clock += delta
	if rowing:
		var old_yaw := rotation.y
		rotation.y += steering * delta * 0.65
		if not can_navigate(global_position):
			rotation.y = old_yaw
	var forward := -global_basis.z
	var target := forward * throttle * TOP_SPEED if rowing else Vector3.ZERO
	velocity = velocity.move_toward(target, delta * (0.65 if rowing else 0.32))
	velocity.y = 0
	if can_navigate(global_position + velocity * delta):
		move_and_collide(velocity * delta)
	else:
		velocity = Vector3.ZERO
	var surface := water.surface_height(1)
	global_position.y = lerpf(global_position.y, surface, 1.0 - exp(-delta * 5.0))
	water.material.set_shader_parameter("lake_boat_pose", Vector4(global_position.x, global_position.z, rotation.y, global_position.y))
	visual.rotation.x = sin(clock * 1.4) * 0.025
	visual.rotation.z = sin(clock * 1.1 + 0.7) * 0.035
	for i in oars.size():
		var phase := clock * 2.5
		oars[i].rotation.y = sin(phase) * 0.45 * throttle * (-1 if i == 0 else 1)
		oars[i].rotation.z = cos(phase) * 0.16 * absf(throttle)
	var count := int(clock * 2.5 / TAU)
	if rowing and absf(throttle) > 0.1 and count != last_stroke:
		last_stroke = count
		stroke.emit(global_position)
