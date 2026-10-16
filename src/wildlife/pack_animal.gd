extends CharacterBody3D
## Imported skeletal motion; walking ducks collide with the world, birds fly.
const SceneUtil = preload("res://src/common/scene_util.gd")
const BodyPace = preload("res://src/common/body_pace.gd")
## Ground speed, m/s, of an animal that walks its circle.
const WALK_SPEED := 0.28
var kind := "dog"
var home := Vector2.ZERO
var height := 1.0
var clip := ""
var radius := 0.0
var phase := 0.0
var terrain: TerrainSystem
var player: Player
var animation: AnimationPlayer
var model: Node3D
var active_clip := ""
var _pace := BodyPace.new()
## Per kind: the global transform the bounds were measured under, and the bounds.
static var _bounds_cache := {}

func _ready() -> void:
	name = "Pack_" + kind
	collision_layer = PhysicsLayers.ANIMALS
	collision_mask = PhysicsLayers.mask_of(PhysicsLayers.ANIMALS)
	floor_snap_length = 0.5
	var pivot := Node3D.new()
	add_child(pivot)
	model = (load("res://assets/models/village_pack/" + kind + "/scene.gltf") as PackedScene).instantiate()
	pivot.add_child(model)
	# A fresh instance of the same model under the same transform poses the
	# same way, so a later animal of a kind reuses the first one's bounds.
	var cached: Dictionary = _bounds_cache.get(kind, {})
	var reuse: bool = not cached.is_empty() and cached.transform == global_transform
	var bounds: AABB = cached.bounds if reuse else AABB()
	var first := true
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if not reuse:
			var box := global_transform.affine_inverse() * posed_bounds(mesh)
			bounds = box if first else bounds.merge(box)
			first = false
		mesh.visibility_range_end = 100.0
		mesh.visibility_range_end_margin = 10.0
		mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		# An animal never stands still: beside a lamp that casts a shadow it
		# would have the lamp draw its map again in every frame (the goats ten
		# metres from the forge did, all day).
		mesh.layers = TavernSystem.RESTLESS_LAYER
	if not reuse:
		_bounds_cache[kind] = {"transform": global_transform, "bounds": bounds}
	var factor := height / maxf(bounds.size.y, 0.001)
	if kind == "goose":
		factor = 1.6 / maxf(bounds.size.x, bounds.size.z)
	pivot.scale = Vector3.ONE * factor
	model.position -= Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	var shape := CapsuleShape3D.new()
	shape.radius = shape_radius(height)
	shape.height = maxf(height * 0.75, shape.radius * 2)
	_pace.max_step = shape.radius
	var holder := CollisionShape3D.new()
	holder.shape = shape
	holder.position.y = shape.height * 0.5
	holder.disabled = kind == "goose"
	add_child(holder)
	position = Vector3(home.x, terrain.height_at(home.x, home.y) + 0.04, home.y)
	animation = SceneUtil.animation_player(model)
	if animation != null:
		# Resolve the original clip name, allowing sanitized import names.
		for candidate in animation.get_animation_list():
			if candidate == clip or candidate.replace("_", "|") == clip.replace("_", "|"):
				active_clip = candidate
		if active_clip.is_empty():
			push_error("Pack animal has no requested clip: " + kind + "/" + clip)
		else:
			animation.get_animation(active_clip).loop_mode = Animation.LOOP_LINEAR
			animation.play(active_clip)
			animation.seek(fmod(phase, animation.current_animation_length), true)
	rotation.y = phase

func _physics_process(delta: float) -> void:
	var active := player == null or global_position.distance_squared_to(player.global_position) < 130.0 * 130.0
	if animation != null:
		animation.active = active
	if not active:
		return
	delta = _pace.begin(delta)
	if delta == 0.0:
		return
	if kind == "goose":
		phase += delta * 0.19
		var p := home + Vector2(cos(phase), sin(phase)) * radius
		position = Vector3(p.x, terrain.height_at(p.x, p.y) + 12.0 + sin(phase * 2.0) * 0.6, p.y)
		rotation.y = atan2(-sin(phase), cos(phase))
		return
	velocity = Vector3(0, -0.5 if is_on_floor() else velocity.y - 18 * delta, 0)
	if radius > 0:
		phase += delta * 0.12
		var target := home + Vector2(cos(phase), sin(phase)) * radius
		var direction := Vector3(target.x - position.x, 0, target.y - position.z).normalized()
		var ahead := position + direction * 0.8
		if terrain.height_at(ahead.x, ahead.z) > terrain.water_level + 0.2:
			velocity.x = direction.x * WALK_SPEED
			velocity.z = direction.z * WALK_SPEED
			rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), delta * 2.0)
	_pace.slide(self, delta)

## The radius, m, of the body capsule of an animal `height` m tall.
static func shape_radius(height: float) -> float:
	return minf(0.35, height * 0.22)

## Skinned source meshes can carry unapplied scales and inverse bind transforms.
## Their raw AABBs do not describe the visible animal; evaluate the bind pose.
static func posed_bounds(mesh: MeshInstance3D) -> AABB:
	var skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
	if skeleton == null or mesh.skin == null:
		return mesh.global_transform * mesh.get_aabb()
	skeleton.force_update_all_bone_transforms()
	var skin: Skin = mesh.skin
	var matrices: Array[Transform3D] = []
	for i: int in skin.get_bind_count():
		var bone := skin.get_bind_bone(i)
		if bone < 0:
			bone = skeleton.find_bone(skin.get_bind_name(i))
		matrices.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(i))
	var box := AABB()
	var first := true
	for surface: int in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var influences := joints.size() / vertices.size()
		for i: int in vertices.size():
			var point := Vector3.ZERO
			for j: int in influences:
				var index: int = i * influences + j
				point += (matrices[joints[index]] * vertices[i]) * weights[index]
			box = AABB(point, Vector3.ZERO) if first else box.expand(point)
			first = false
	return box
