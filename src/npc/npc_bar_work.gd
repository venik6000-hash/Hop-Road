class_name NpcBarWork
extends Node3D
## The innkeeper draws a beer at his bar (docs/LIFE.md, «Работа руками»). He
## bends and takes a tankard from the shelf under the counter with the left
## hand, holds it tilted under the long spigot of the keg on the counter,
## opens the tap with the right hand, rights the tankard as the beer fills
## it, closes the tap and sets the tankard on the counter in front of him.
## The node stands at his place of work, turned as he stands there: its
## props are in its own space, -z away from him across the counter, +x to his
## right. NpcReach bends his body; the tankard follows his hand.
const KEG := preload("res://assets/models/bar/keg.glb")
const STREAM := preload("res://assets/models/bar/stream.glb")
const STREAM_SHADER := preload("res://src/npc/beer_stream.gdshader")

## The counter's top over the floor where he stands, metres, until a ray
## finds it.
const TOP := 1.06
## The keg lies on the counter ahead and to his left, its tapped head at the
## counter's back edge: the spout hangs over the gap behind the counter.
const KEG_AT := Vector3(-0.32, 0.0, -0.55)
## The tankard's foot on the shelf under the counter (the shelf lies 0.34 m
## under the counter's top).
const SHELF := Vector3(-0.15, -0.34, -0.56)
## Where he sets the full tankard on the counter, in front of the keg.
const SERVE := Vector3(-0.06, 0.0, -0.47)
## His left shoulder, standing, in the node's space: a tankard in the left
## hand turns its handle to him so that the fingers go on from the forearm.
const SHOULDER := Vector3(-0.18, 1.36, 0.02)
## How far he turns to the keg while he draws, radians to his left: the
## pelvis over the planted feet, then the trunk over the pelvis.
const TURN_TO_KEG := 0.33
const TWIST_TO_KEG := 0.28
## The tankard under the spout: its rim this far under the outlet, tilted
## this far with its mouth to the keg at first.
const UNDER_SPOUT := 0.045
const TILT := deg_to_rad(32.0)
## Where the right hand rests on the counter while he sets the tankard down.
const BRACE := Vector3(0.22, 0.0, -0.42)
## The palm on the handle's outer face, in the tankard's own space; the
## fingers point along GRIP_ALONG, ahead and a little down, as they go on
## from a forearm that reaches down to the tankard.
const GRIP := Tankard.HANDLE + Vector3(0.02, 0.0, 0.0)
const GRIP_ALONG := Vector3(0.0, -0.42, 0.91)
## How fast the tankard in his hand turns after his forearm, radians a
## second: its handle stays across the line of the forearm.
const HEADING_RATE := 2.5
## The tap's lever turns this far to open, radians, about its own x.
const LEVER_OPEN := deg_to_rad(75.0)

## The times of the draw, seconds from the order.
const T_GRIP := 1.15
const T_TAKE := 1.45
const T_OUT := 1.95
const T_UNDER := 2.55
const T_OPEN := 2.95
const T_RUN := 3.1
const T_FULL := 6.0
const T_CLOSE := 6.35
const T_ASIDE := 6.75
const T_LIFT := 7.05
const T_OVER := 7.6
const T_SET := 7.9
const T_BACK := 8.6
## The whole draw lasts this long: then the claim on his arms ends.
const LENGTH := 8.6

var actor: VillageNPC
var keg: Node3D
var lever: Node3D
var spout: Node3D
var lever_grip: Node3D
var tankard: Tankard
var stream: MeshInstance3D
## Seconds into the draw; negative when he is not drawing.
var clock := -1.0
## The tankard is in his hand.
var held := false
## The tankard stands full on the counter.
var served := false
var _top := TOP
## The tankard in the hand's frame while he holds it.
var _in_hand := Transform3D.IDENTITY
## The hand closed on the tankard in this frame: its place in the hand is
## taken once the pose is final (follow).
var _closing := false
## The tankard's turn about the vertical while he holds it, node space.
var _heading := 0.0

func _ready() -> void:
	keg = KEG.instantiate() as Node3D
	keg.name = "Keg"
	add_child(keg)
	lever = keg.find_child("TapLever", true, false) as Node3D
	spout = keg.find_child("Spout", true, false) as Node3D
	lever_grip = keg.find_child("LeverGrip", true, false) as Node3D
	tankard = Tankard.new()
	add_child(tankard)
	stream = MeshInstance3D.new()
	stream.name = "BeerStream"
	var stream_scene := STREAM.instantiate() as Node3D
	var stream_mesh := stream_scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	stream.mesh = stream_mesh.mesh
	stream_scene.free()
	var material := ShaderMaterial.new()
	material.shader = STREAM_SHADER
	stream.material_override = material
	stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stream.top_level = true
	stream.visible = false
	add_child(stream)
	# The bar stands in the tavern: its pieces take the tavern's lamps, not
	# the sky's light, and throw no lamp shadows, as the villagers inside.
	for item: GeometryInstance3D in find_children("*", "GeometryInstance3D", true, false):
		VillageNPC.set_layers(item, 1 | TavernSystem.LAYER)
		item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_place_props()
	_measure_top.call_deferred()

## The counter's top under the serving place, found by a ray once the level's
## colliders are in.
func _measure_top() -> void:
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var over := global_transform * (SERVE + Vector3.UP * 1.8)
	var ray := PhysicsRayQueryParameters3D.create(over, over + Vector3.DOWN * 1.6, PhysicsLayers.WORLD)
	var hit := space.intersect_ray(ray)
	if not hit.is_empty():
		_top = (global_transform.affine_inverse() * (hit.position as Vector3)).y
	_place_props()

## The counter's top over the floor, metres, in the node's space.
func top() -> float:
	return _top

func _place_props() -> void:
	keg.transform = Transform3D(Basis.IDENTITY, KEG_AT + Vector3.UP * _top)
	if clock < 0.0 and not served:
		tankard.transform = shelf_transform()

## The tankard's place on the shelf, in the node's space.
func shelf_transform() -> Transform3D:
	var foot := SHELF + Vector3.UP * _top
	return Transform3D(Basis(Vector3.UP, handle_yaw(foot, 0.0)), foot)

## The tankard's place on the counter where he serves it, in the node's space.
func serve_transform() -> Transform3D:
	var foot := SERVE + Vector3.UP * _top
	return Transform3D(Basis(Vector3.UP, handle_yaw(foot, 0.0)), foot)

## The tankard under the spout, turned `yaw` and tilted `tilt` away from its
## handle (the wrist rolls), in the node's space.
func under_spout(tilt: float, yaw: float) -> Transform3D:
	var outlet := to_local(spout.global_position)
	var turn := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, tilt)
	var rim := outlet + Vector3(0.0, -UNDER_SPOUT, 0.0)
	return Transform3D(turn, rim - turn * Vector3(0.0, Tankard.RIM, 0.0))

## The tankard's turn about the vertical at `point` (node space) that puts its
## +z, the way the fingers on the handle point, along the reach from his left
## shoulder, his trunk turned `turned` radians to the left: the handle is then
## on his side of the reach.
static func handle_yaw(point: Vector3, turned: float) -> float:
	var shoulder := Basis(Vector3.UP, turned) * SHOULDER
	var reach := point - shoulder
	return atan2(reach.x, reach.z)

## Starts a draw. False while one is going on or a tankard waits on the
## counter.
func start() -> bool:
	if clock >= 0.0 or served:
		return false
	clock = 0.0
	held = false
	tankard.fill = 0.0
	tankard.transform = shelf_transform()
	tankard.visible = true
	return true

## Whether he is drawing a beer now.
func drawing() -> bool:
	return clock >= 0.0

## Whether the beer runs into the tankard now.
func running() -> bool:
	return clock >= T_RUN and clock < T_CLOSE

## The player takes the tankard from the counter: a clean one is on the shelf.
func take() -> void:
	served = false
	tankard.fill = 0.0
	tankard.transform = shelf_transform()

## Puts the bar back in order: no draw, the tankard on its shelf, the tap shut.
func clear() -> void:
	clock = -1.0
	held = false
	served = false
	tankard.fill = 0.0
	tankard.transform = shelf_transform()
	stream.visible = false
	if lever != null:
		lever.rotation.x = 0.0
	_drop_hands()

## How full the tankard is, 0..1.
func fill() -> float:
	return tankard.fill

## Moves the draw on by `delta` seconds and sets the body's pose for the frame.
func step(delta: float) -> void:
	if clock < 0.0:
		return
	clock += delta
	var reach := actor.reach
	if reach == null:
		return
	if lever != null:
		lever.rotation.x = LEVER_OPEN * (_ease(clock, T_OPEN - 0.25, T_OPEN) - _ease(clock, T_CLOSE - 0.25, T_CLOSE))
	tankard.fill = _ease(clock, T_RUN, T_FULL)
	stream.visible = running()
	if not held and clock >= T_TAKE and clock < T_SET:
		held = true
		_closing = true
	if held and clock >= T_SET:
		held = false
		served = true
		var put := tankard.transform
		put.basis = Basis(Vector3.UP, atan2(put.basis.z.x, put.basis.z.z))
		put.origin.y = _top
		tankard.transform = put
	_follow_forearm(delta)
	_pose_body(reach)
	if clock >= LENGTH:
		clock = -1.0
		_drop_hands()

## Turns the tankard's heading after the left forearm once he holds it.
func _follow_forearm(delta: float) -> void:
	if clock < T_TAKE:
		_heading = handle_yaw(SHELF + Vector3.UP * _top, 0.0)
		return
	var fore := global_basis.orthonormalized().inverse() * actor.reach.forearm("L")
	if Vector2(fore.x, fore.z).length() < 0.02:
		return
	var turn := angle_difference(_heading, atan2(fore.x, fore.z))
	_heading += clampf(turn, -HEADING_RATE * delta, HEADING_RATE * delta)

## The left hand's world frame.
func _hand_frame() -> Transform3D:
	var skeleton := actor.skeleton
	var bone := skeleton.find_bone("Hand_L")
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone)

## Follows the hand once the pose is final (VillageNPC.posed): the skeleton
## gives the posed bones only then. The tankard keeps the place in the hand it
## had when the hand closed on it.
func follow() -> void:
	if held:
		var hand := _hand_frame()
		if _closing:
			_closing = false
			_in_hand = hand.affine_inverse() * tankard.global_transform
		tankard.global_transform = hand * _in_hand
	if stream.visible:
		var outlet := spout.global_position
		var bottom := tankard.surface_point()
		bottom.x = outlet.x
		bottom.z = outlet.z
		var length := maxf(0.02, outlet.y - bottom.y)
		stream.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, length, 1.0)), outlet)

## Where the tankard should be at time `t`, in the node's space.
func _tankard_at(t: float) -> Transform3D:
	var shelf := shelf_transform()
	var out := Transform3D(Basis(Vector3.UP, _heading), Vector3(-0.12, shelf.origin.y + 0.05, -0.4))
	var tilt := TILT * (1.0 - _ease(t, T_OPEN + 0.4, T_FULL - 0.5))
	var under := under_spout(tilt, _heading)
	var aside := under
	aside.origin += Vector3(0.18, 0.0, 0.04)
	var lifted := aside
	lifted.origin.y = _top + 0.14
	lifted.origin.z = -0.5
	var serve := Transform3D(Basis(Vector3.UP, _heading), serve_transform().origin)
	var over := serve
	over.origin.y += 0.1
	if t < T_TAKE:
		return shelf
	if t < T_OUT:
		return _blend(shelf, out, _ease(t, T_TAKE, T_OUT))
	if t < T_UNDER:
		return _blend(out, under_spout(TILT, _heading), _ease(t, T_OUT, T_UNDER))
	if t < T_CLOSE:
		return under
	if t < T_ASIDE:
		return _blend(under, aside, _ease(t, T_CLOSE, T_ASIDE))
	if t < T_LIFT:
		return _blend(aside, lifted, _ease(t, T_ASIDE, T_LIFT))
	if t < T_OVER:
		return _blend(lifted, over, _ease(t, T_LIFT, T_OVER))
	return _blend(over, serve, _ease(t, T_OVER, T_SET))

## The body's pose for the frame.
func _pose_body(reach: NpcReach) -> void:
	var t := clock
	var frame := global_transform
	var turn := frame.basis.orthonormalized()
	# Down on the knees to the shelf, up for the tap.
	var bent := _ease(t, 0.15, T_GRIP) - _ease(t, T_TAKE, T_UNDER)
	var at_keg := _ease(t, T_OUT, T_UNDER) - _ease(t, T_CLOSE, T_LIFT)
	reach.drop = 0.22 * bent
	reach.lean = 0.5 * bent + 0.08 * at_keg
	reach.turn = TURN_TO_KEG * at_keg
	reach.twist = TWIST_TO_KEG * at_keg
	reach.tilt = 0.0
	# The left hand: to the tankard on the shelf, then with it.
	var left := reach.left
	var mug := frame * _tankard_at(t)
	if t < T_TAKE:
		var near := frame * shelf_transform()
		near.origin += turn * Vector3(0.0, 0.02, 0.14) * (1.0 - _ease(t, T_GRIP - 0.35, T_GRIP))
		mug = near
	left.weight = _ease(t, 0.1, 0.8) * (1.0 - _ease(t, T_SET + 0.05, T_BACK))
	left.palm = mug * GRIP
	left.along = mug.basis * GRIP_ALONG
	left.facing = mug.basis * Vector3.LEFT
	left.elbow = turn * Vector3(-0.6, -0.7, 0.3)
	# The right hand: by his side while he crouches to the shelf, on the
	# lever, then on the counter while he sets the tankard down.
	var right := reach.right
	var brace := _ease(t, T_ASIDE, T_OVER) * (1.0 - _ease(t, T_SET + 0.1, T_BACK))
	var on_lever := _ease(t, T_UNDER - 0.45, T_OPEN - 0.25) * (1.0 - _ease(t, T_CLOSE + 0.05, T_ASIDE + 0.2))
	right.weight = maxf(brace, on_lever)
	if on_lever > brace and lever_grip != null:
		# The fist closes round the knob from the right, the fingers going on
		# from the forearm as it lies, and pulls it to him.
		var fore := reach.forearm("R")
		if fore.length_squared() < 0.0001 or right.weight < 0.5:
			var shoulder := frame * (Basis(Vector3.UP, reach.turn + reach.twist) * Vector3(-SHOULDER.x, SHOULDER.y, SHOULDER.z))
			fore = lever_grip.global_position - shoulder
		var ahead := Vector3(fore.x, 0.0, fore.z).normalized()
		right.palm = lever_grip.global_position
		right.along = fore.normalized()
		right.facing = Vector3.UP.cross(ahead)
		right.elbow = turn * Vector3(0.8, -0.6, 0.2)
	else:
		right.palm = frame * (BRACE + Vector3.UP * _top)
		right.along = turn * Vector3(-0.25, 0.0, -1.0).normalized()
		right.facing = Vector3.DOWN
		right.elbow = turn * Vector3(0.8, -0.4, 0.2)
	# He looks at what his hands do.
	reach.look_weight = 0.85 * _ease(t, 0.0, 0.5) * (1.0 - _ease(t, T_SET + 0.1, T_BACK))
	if t < T_TAKE:
		reach.look = frame * (shelf_transform().origin + Vector3.UP * 0.15)
	elif t < T_CLOSE:
		reach.look = spout.global_position.lerp(tankard.surface_point(), 0.3)
	else:
		reach.look = tankard.global_position + Vector3.UP * 0.12

func _drop_hands() -> void:
	if actor == null or actor.reach == null:
		return
	actor.reach.left.weight = 0.0
	actor.reach.right.weight = 0.0
	actor.reach.look_weight = 0.0
	actor.reach.drop = 0.0
	actor.reach.lean = 0.0
	actor.reach.twist = 0.0
	actor.reach.turn = 0.0

## 0 before `from`, 1 after `to`, eased between.
static func _ease(t: float, from: float, to: float) -> float:
	var x := clampf((t - from) / maxf(to - from, 0.0001), 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

static func _blend(a: Transform3D, b: Transform3D, weight: float) -> Transform3D:
	return a.interpolate_with(b, weight)
