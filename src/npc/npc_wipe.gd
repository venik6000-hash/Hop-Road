class_name NpcWipe
extends Node3D
## The one who keeps the hall wipes a counter or a table (docs/LIFE.md,
## «Работа руками»). The rag lies on the top: a ray finds the top under each
## point of its path, and the palm presses the rag from above. The path is a
## run of small loops sliding along a strip in front of the villager and
## back; the trunk turns and bends after the hand (NpcReach), the other hand
## rests on the top. The innkeeper wipes his counter the same way. The node
## is the villager's child; the rag is top level.
const RAG := preload("res://assets/models/bar/rag.glb")
## The rag's pad is this thick: the palm lies on it.
const PAD := 0.035
## A loop of the rag: how far it goes to either side, metres (ahead it spans
## the strip), and loops a second.
const LOOP := 0.085
const LOOPS := 1.3
## Seconds the loops take to slide along the strip and back.
const SWEEP := 6.0
## How far over and under the strip's expected top the ray looks, metres.
const PROBE := 0.35

var actor: VillageNPC
## The strip wiped, in the villager's own space (+x to the right, -z ahead):
## its middle `middle` metres to the right, `across` to either side of it,
## from `near` to `far` ahead.
var middle := 0.0
var across := 0.25
var near := 0.36
var far := 0.46
## Where the other hand rests on the top, in the villager's own space; zero
## when it hangs as the clip has it.
var rest := Vector3(-0.38, 0.0, -0.36)
## Metres the pelvis goes down, the knees bending, for a low top.
var drop := 0.0
var rag: Node3D
## Seconds into the wiping; negative when the villager does not wipe.
var clock := -1.0
## Where the top lies over the villager's feet, metres, once found.
var top := NAN
## The top's height found under the rag in the last frame, world.
var surface := Vector3.ZERO
## Where the other hand rests on the top, world, found when the wiping
## starts.
var rest_point: Vector3:
	get:
		return _rest_point
var _ray: PhysicsRayQueryParameters3D
var _rest_point := Vector3.ZERO

func _ready() -> void:
	rag = RAG.instantiate() as Node3D
	rag.name = "Rag"
	rag.top_level = true
	rag.visible = false
	add_child(rag)
	# The villager puts its pieces under its zone's lights as they come; the
	# rag comes after the node itself.
	actor.lamp_zone.light(rag)

## Sets the strip and the stance from `row` (keys "middle", "across", "near",
## "far", "rest", "drop", as the fields; a missing key takes the field's first
## value).
func set_strip(row: Dictionary) -> void:
	middle = Values.real(row.get("middle", 0.0))
	across = Values.real(row.get("across", 0.25))
	near = Values.real(row.get("near", 0.36))
	far = Values.real(row.get("far", 0.46))
	rest = row.get("rest", Vector3(-0.38, 0.0, -0.36))
	drop = Values.real(row.get("drop", 0.0))

## Starts wiping the top in front of the villager. False when no top is within reach.
func start() -> bool:
	top = _find_top()
	if is_nan(top):
		return false
	clock = 0.0
	rag.visible = true
	if rest != Vector3.ZERO:
		_rest_point = _on_top(actor.global_transform * rest)
	return true

## Stops wiping: the rag goes with the villager (hidden); NpcBody eases the
## hands back to the clip.
func stop() -> void:
	clock = -1.0
	rag.visible = false

## Whether the villager wipes now.
func wiping() -> bool:
	return clock >= 0.0

## Where the rag's middle goes at `t` seconds, in the villager's own space (y is not
## used: the top's height comes from the ray).
func path(t: float) -> Vector3:
	var slide := middle - cos(TAU * t / SWEEP) * across
	var ahead := (near + far) * 0.5
	var loop := TAU * LOOPS * t
	return Vector3(slide + sin(loop) * LOOP, 0.0, -(ahead + cos(loop) * (far - near) * 0.5))

## Moves the wiping on by `delta` seconds and sets the pose.
func step(delta: float) -> void:
	if clock < 0.0 or actor.poses.reach == null:
		return
	clock += delta
	var reach := actor.poses.reach
	var frame := actor.global_transform
	var turn := frame.basis.orthonormalized()
	var local := path(clock)
	surface = _on_top(frame * local)
	# The rag lies on the top, turned as the hand moves it.
	var heading := path(clock + 0.05) - local
	var yaw := 0.25 * clampf(heading.x / 0.02, -1.0, 1.0)
	rag.global_transform = Transform3D(turn * Basis(Vector3.UP, yaw), surface)
	var right := reach.right
	right.weight = 1.0
	right.palm = surface + Vector3.UP * PAD
	right.facing = Vector3.DOWN
	right.along = _heading(reach.forearm("R"), turn * Basis(Vector3.UP, 0.35 + yaw) * Vector3.FORWARD)
	right.elbow = turn * Vector3(0.7, -0.5, 0.35)
	var left := reach.left
	left.weight = 1.0 if rest != Vector3.ZERO else 0.0
	left.palm = _rest_point
	left.facing = Vector3.DOWN
	left.along = _heading(reach.forearm("L"), turn * Basis(Vector3.UP, -0.3) * Vector3.FORWARD)
	left.elbow = turn * Vector3(-0.7, -0.5, 0.35)
	# The trunk turns to the hand and leans over it.
	var lateral := local.x - middle * 0.5
	reach.twist = -atan2(lateral, -local.z) * 0.55
	reach.tilt = -lateral * 0.25
	reach.lean = 0.18 + 0.05 * sin(TAU * LOOPS * clock)
	reach.drop = drop
	reach.look = surface
	reach.look_weight = 0.7

## The way the fingers point on the top: on in plan from the forearm as it
## lay in the last frame, the palm flat; `first` before the work drove it.
static func _heading(forearm: Vector3, first: Vector3) -> Vector3:
	var flat := Vector3(forearm.x, 0.0, forearm.z)
	return flat.normalized() if flat.length_squared() > 0.0004 else first

## The top under `point` (world), found by a ray; where the strip's top was
## first found when the ray misses (the path runs off its edge).
func _on_top(point: Vector3) -> Vector3:
	var space := actor.get_world_3d().direct_space_state
	var expected := actor.global_position.y + top
	if _ray == null:
		_ray = PhysicsRayQueryParameters3D.new()
		_ray.collision_mask = PhysicsLayers.WORLD
	_ray.from = Vector3(point.x, expected + PROBE, point.z)
	_ray.to = Vector3(point.x, expected - PROBE, point.z)
	var hit := space.intersect_ray(_ray)
	if hit.is_empty():
		return Vector3(point.x, expected, point.z)
	return hit.position

## The height of the top in front of the villager over the feet, metres; NAN when no
## top at working height (0.6 to 1.2 m) lies under the strip.
func _find_top() -> float:
	var space := actor.get_world_3d().direct_space_state
	var frame := actor.global_transform
	var centre := frame * Vector3(middle, 0.0, -(near + far) * 0.5)
	var ray := PhysicsRayQueryParameters3D.create(centre + Vector3.UP * 1.25, centre + Vector3.UP * 0.55, PhysicsLayers.WORLD)
	var hit := space.intersect_ray(ray)
	if hit.is_empty():
		return NAN
	var normal: Vector3 = hit.normal
	if normal.y < 0.9:
		return NAN
	var top: Vector3 = hit.position
	return top.y - actor.global_position.y
