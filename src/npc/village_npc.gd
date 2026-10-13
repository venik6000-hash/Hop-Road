class_name VillageNPC
extends CharacterBody3D
## Imported skeletal clips drive the visible model; collision drives routes.
const SceneUtil = preload("res://src/common/scene_util.gd")
const BodyPace = preload("res://src/common/body_pace.gd")
const SPEED := 0.85
const GRAVITY := 18.0
## Seconds between checks of whether the actor stands inside the tavern.
const LAMP_ZONE_SECONDS := 0.25
## How far behind a face that was met its top is looked for.
const LIP := 0.06
## Seconds one who walks about their work stands on once a story they tell no
## longer holds them (stop_to_talk).
const TALK_HOLD := 1.5
## The ground speed, m/s, the "walk" clip is drawn for: measured from the
## planted foot, 1.0 to 1.5 over the four models.
const WALK_STRIDE := 1.1
## The clip is played no faster than this many times its own pace: the feet
## of one who hurries more than that slide.
const WALK_HASTE := 2.0
var model_path := ""
var job := "wander"
var title := "Житель"
## The villager's sheet in PeopleBook; "" for a passer-by without one.
var person_id := ""
var route: Array[Vector3] = []
var animation: AnimationPlayer
var skeleton: Skeleton3D
var state := "working"
var mug: Node3D
var utensil: Node3D
var stream: MeshInstance3D
var _point := 0
var _direction := 1
var _wait := 0.0
var _clock := 0.0
var _blocked := 0.0
var _beer := 0.0
var _cleaning := false
var _left_hand := -1
var _right_hand := -1
var outing: Node
## Where the villager's day has them (VillagerPresence): "" as the job says,
## else one of VillagerDay.PLACES.
var place := ""
## Where the villager works and which way they face there (NpcPopulation.settle).
var work_point := Vector3.ZERO
var work_yaw := 0.0
## Sits on a seat of the hall (VillagerPresence): the body has no collision
## and is not moved.
var seated := false
var _hall_navigation: TavernNavigation
var _hall_path := PackedVector3Array()
var _hall_target := -1
var _hall_ready := false
var _route_probe: PhysicsShapeQueryParameters3D
# 1 inside the tavern, 0 outside, -1 before the first check.
var _lamp_zone := -1
## Within reach of a lit lantern outdoors (LampShadowGuard sets it): no shadow
## there either, or the lantern draws its shadow map again in every frame.
var near_lit_lamp := false:
	set(value):
		if value != near_lit_lamp:
			near_lit_lamp = value
			_light_for_zone(self)
var _lamp_zone_clock := 0.0
var _pace := BodyPace.new()
var _ground_ray: PhysicsRayQueryParameters3D


func _ready() -> void:
	collision_layer = 1 | 4
	collision_mask = 1 | 4
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(48.0)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.23
	capsule.height = 1.65
	var solid := CollisionShape3D.new()
	solid.shape = capsule
	solid.position.y = 0.83
	add_child(solid)
	var model := (load(model_path) as PackedScene).instantiate() as Node3D
	model.name = "Model"
	model.rotation.y = PI # glTF is +Z forward; actors face -Z.
	add_child(model)
	animation = SceneUtil.animation_player(model)
	for node in model.find_children("*", "Skeleton3D", true, false):
		skeleton = node
		break
	for node: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		node.visibility_range_end = 65.0
	if skeleton != null:
		_left_hand = skeleton.find_bone("Hand_L")
		_right_hand = skeleton.find_bone("Hand_R")
	_setup_props()
	# What the actor is handed later (a mug, a meal) follows the same rule.
	child_entered_tree.connect(_light_for_zone)
	_update_lamp_zone()
	play("idle")
	if job == "maid":
		_prepare_hall_navigation.call_deferred()

func _prepare_hall_navigation() -> void:
	await get_tree().physics_frame
	_hall_navigation = TavernNavigation.new()
	_hall_navigation.build(self)
	_route_probe = PhysicsShapeQueryParameters3D.new()
	var probe := CapsuleShape3D.new()
	probe.radius = 0.25
	probe.height = 1.6
	_route_probe.shape = probe
	_route_probe.collision_mask = 1 | 4
	_route_probe.exclude = [get_rid()]
	_hall_ready = true

func _setup_props() -> void:
	if job == "bartender":
		mug = NpcProps.mug()
		utensil = NpcProps.jug()
		add_child(mug)
		add_child(utensil)
		mug.visible = false
		utensil.visible = false
		stream = NpcProps.mesh(self, NpcProps.cylinder(0.007, 0.15), Color("d8a43a"))
		stream.visible = false
	elif job in ["chop", "stir"]:
		utensil = NpcProps.knife() if job == "chop" else NpcProps.spoon()
		add_child(utensil)
	elif job == "maid":
		utensil = Node3D.new()
		add_child(utensil)
		var cloth := BoxMesh.new()
		cloth.size = Vector3(0.12, 0.012, 0.1)
		NpcProps.mesh(utensil, cloth, Color("c8bda1"))

## The tavern's lamps keep their shadow maps while nothing they light moves
## (TavernSystem.SHADOW_LAYER); a body that could cast a shadow has every lamp
## in whose reach it is animated drawn again in each frame. So an actor is on
## the tavern's layer, lit by its lamps, only inside the building, and casts no
## shadow there. Outdoors it is lit by the sun and casts the sun's shadow.
func _update_lamp_zone() -> void:
	var zone := int(TavernSystem.BUILDING_BOUNDS.grow(0.3).has_point(global_position + Vector3.UP * 0.9))
	if zone == _lamp_zone:
		return
	_lamp_zone = zone
	_light_for_zone(self)

func _light_for_zone(root: Node) -> void:
	if _lamp_zone < 0:
		return
	var items: Array[Node] = root.find_children("*", "GeometryInstance3D", true, false)
	if root is GeometryInstance3D:
		items.append(root)
	for item: GeometryInstance3D in items:
		# The setting the piece came with is the one it has in the open.
		if not item.has_meta(&"outdoor_shadow"):
			item.set_meta(&"outdoor_shadow", item.cast_shadow)
		set_layers(item, (1 | TavernSystem.LAYER) if _lamp_zone == 1 else 1)
		item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if _lamp_zone == 1 or near_lit_lamp \
			else item.get_meta(&"outdoor_shadow")

## Puts a piece on other render layers. Godot 4.7.2 keeps a piece paired with
## the lights in whose reach it stands while its layers change (Forward+), yet
## counts a pair only where the light's cull mask meets the layers. A piece
## that takes the tavern's layer under a lamp is therefore missing from the
## engine's count of the lights that give it a soft shadow, and the engine
## prints "geom->softshadow_count==0 - BUG!" when it leaves the lamp or is
## hidden. So the server holds the piece hidden over the change: hidden it has
## no pairs, and shown again it is paired by its new layers. The engine's
## master does the same on its own (53ec17a1d).
static func set_layers(item: GeometryInstance3D, layers: int) -> void:
	if item.layers == layers:
		return
	var instance := item.get_instance()
	RenderingServer.instance_set_visible(instance, false)
	item.layers = layers
	RenderingServer.instance_set_visible(instance, item.is_visible_in_tree())

func play(clip: String, loop := true) -> void:
	if animation == null: return
	if not animation.has_animation(clip): clip = "idle"
	animation.speed_scale = 1.0
	if animation.current_animation == clip and animation.is_playing(): return
	animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	animation.play(clip, 0.18)

## Walks at `speed`, m/s: the "walk" clip, played as fast as the feet need.
func stride(speed: float) -> void:
	play("walk" if animation != null and animation.has_animation("walk") else "source_walk")
	if animation != null:
		animation.speed_scale = clampf(speed / WALK_STRIDE, 1.0, WALK_HASTE)

func _physics_process(delta: float) -> void:
	delta = _pace.begin(delta)
	if delta == 0.0:
		return
	_clock += delta
	_lamp_zone_clock -= delta
	if _lamp_zone_clock <= 0.0:
		_lamp_zone_clock = LAMP_ZONE_SECONDS
		_update_lamp_zone()
	velocity.y = -0.3 if is_on_floor() else velocity.y - GRAVITY * delta
	velocity.x = 0.0
	velocity.z = 0.0
	if outing != null:
		outing.drive(delta)
	elif place in ["hall", "yard"]:
		play("idle")
	elif job == "bartender" and at_work():
		_update_bar(delta)
	elif not route.is_empty():
		_walk_route(delta)
	else:
		play(job)
	if seated:
		return
	var step := Vector3(velocity.x, 0.0, velocity.z) * delta
	_pace.slide(self, delta)
	# The lane has kerbs and stairs: a walker held by one steps onto it.
	if outing == null and job == "wander" and step != Vector3.ZERO and is_on_wall():
		for index in get_slide_collision_count():
			var met := get_slide_collision(index)
			if met.get_normal().y < 0.7 and not met.get_collider() is CharacterBody3D and step_onto(met, step):
				break

## A kerb, a stair, the edge of a cobble: what stands no higher than a step is
## stepped on, if the `step` over it is free. Its top is found just behind the
## face that was met.
func step_onto(collision: KinematicCollision3D, step: Vector3) -> bool:
	if _ground_ray == null:
		_ground_ray = PhysicsRayQueryParameters3D.new()
		_ground_ray.collision_mask = 1
		_ground_ray.exclude = [get_rid()]
	var behind := collision.get_position() - collision.get_normal() * LIP
	_ground_ray.from = Vector3(behind.x, global_position.y + Player.STEP_HEIGHT + 0.05, behind.z)
	_ground_ray.to = Vector3(behind.x, global_position.y - 0.1, behind.z)
	var top := get_world_3d().direct_space_state.intersect_ray(_ground_ray)
	if top.is_empty():
		return false
	var rise: float = top.position.y - global_position.y + 0.03
	if rise <= 0.03 or test_move(global_transform, Vector3.UP * rise):
		return false
	var elevated := global_transform
	elevated.origin.y += rise
	if test_move(elevated, step):
		return false
	global_position.y += rise
	return true

func _walk_route(delta: float) -> void:
	if job == "maid" and not _hall_ready:
		return
	_wait = maxf(0.0, _wait - delta)
	if _wait > 0.0:
		play("wipe" if _cleaning else "idle")
		return
	var destination := route[_point]
	if _hall_navigation != null:
		if _hall_target != _point:
			_hall_path = _hall_navigation.path(global_position, destination)
			_hall_target = _point
		if _hall_path.is_empty():
			# No reachable path: wait and retry, never walk straight through furniture.
			_hall_target = -1
			_wait = 1.0
			play("idle")
			return
		while _hall_path.size() > 1 and Vector2(global_position.x - _hall_path[0].x,
				global_position.z - _hall_path[0].z).length() < 0.1:
			_hall_path.remove_at(0)
		destination = _hall_path[0]
	var offset := destination - global_position
	offset.y = 0.0
	if offset.length() < (0.12 if _hall_navigation != null else 0.22) and (_hall_navigation == null or _hall_path.size() == 1):
		_cleaning = job == "maid" and _point == 0
		_wait = 4.0 if _cleaning else 1.2 + float(_point % 3) * 0.8
		_next_point()
		play("idle")
		return
	var direction := offset.normalized()
	rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(delta * 5.0, 1.0))
	# A moving neighbour or the player has priority. Avoid pushing them.
	if _route_obstructed(direction, offset.length()):
		_blocked += delta
		play("idle")
		if _blocked > 3.0:
			_direction *= -1
			_next_point()
			_hall_target = -1
			_blocked = 0.0
		return
	_blocked = 0.0
	var speed := SPEED if _hall_navigation == null else minf(SPEED, offset.length() / maxf(delta, 0.001))
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	play("source_walk" if animation.has_animation("source_walk") else "walk")

func _route_obstructed(direction: Vector3, distance: float) -> bool:
	var space := get_world_3d().direct_space_state
	if _route_probe != null:
		_route_probe.transform.origin = global_position + Vector3.UP * 0.85
		_route_probe.motion = direction * minf(0.42, distance)
		return space.cast_motion(_route_probe)[0] < 1.0
	var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.8,
		global_position + Vector3.UP * 0.8 + direction * 0.65, 1 | 4)
	ray.exclude = [get_rid()]
	return not space.intersect_ray(ray).is_empty()

func _next_point() -> void:
	var next := _point + _direction
	if next < 0 or next >= route.size():
		_direction *= -1
		next = _point + _direction
	_point = clampi(next, 0, route.size() - 1)

func _update_bar(delta: float) -> void:
	match state:
		"working":
			play("wipe")
		"pouring":
			play("pour", false)
			_beer = minf(1.0, _beer + delta / 3.2)
			if _beer >= 1.0:
				state = "serving"
				_clock = 0.0
				stream.visible = false
				utensil.visible = false
				play("serve", false)
		"serving":
			if _clock >= 1.5:
				state = "ready"
				play("idle")
		"ready":
			play("idle")

func _process(_delta: float) -> void:
	if utensil != null and utensil.visible:
		utensil.global_transform = Transform3D(global_basis, hand_position(_right_hand))
		if job == "bartender":
			utensil.rotate_object_local(Vector3.FORWARD, -0.85)
	if mug != null and mug.visible:
		if state == "ready":
			mug.global_transform = Transform3D(global_basis, global_position + global_basis * Vector3(0.1, 1.09, -0.79))
		else:
			mug.global_transform = Transform3D(global_basis, hand_position(_left_hand) + Vector3.UP * 0.02)
		var liquid := mug.get_node("Beer") as MeshInstance3D
		liquid.position.y = 0.018 + 0.115 * _beer
	if stream != null and stream.visible:
		var top := (utensil.get_node("Lip") as Marker3D).global_position
		var bottom := mug.global_position + Vector3.UP * 0.14
		var direction := top - bottom
		stream.global_position = (top + bottom) * 0.5
		stream.global_basis = Basis(Quaternion(Vector3.UP, direction.normalized()))
		stream.scale = Vector3(1, direction.length() / 0.15, 1)

func hand_position(index: int) -> Vector3:
	if skeleton == null or index < 0: return global_position + Vector3.UP
	return (skeleton.global_transform * skeleton.get_bone_global_pose(index)).origin

func interaction_point() -> Vector3:
	return global_position + global_basis * Vector3(0, 1.3, -0.6)

func interaction_text() -> String:
	match state:
		"pouring": return "%s наливает пиво…" % title
		"serving": return "%s подаёт кружку…" % title
		"ready": return "E — взять пиво · " + title
	return "E — заказать пиво · " + title

func interact(player: Player) -> bool:
	if state == "working":
		state = "pouring"
		_beer = 0.0
		_clock = 0.0
		mug.visible = true
		utensil.visible = true
		stream.visible = true
		return true
	if state == "ready":
		player.viewmodel.refill()
		state = "working"
		mug.visible = false
		return true
	return false

## One who walks about their work is telling a story to someone at `listener`:
## they stand where they are and turn to them, and walk on `hold` seconds
## after the last call. Those who keep to one place do not turn from it.
func stop_to_talk(listener: Vector3, delta: float, hold := TALK_HOLD) -> void:
	if job != "maid" or not at_work() or seated:
		return
	_wait = maxf(_wait, hold)
	_cleaning = false
	var offset := listener - global_position
	if Vector2(offset.x, offset.z).length() > 0.3:
		rotation.y = lerp_angle(rotation.y, atan2(-offset.x, -offset.z), minf(delta * 4.0, 1.0))

## Puts the bar back in order when the innkeeper leaves it: nothing is being
## poured and nothing stands ready.
func clear_bar() -> void:
	if job != "bartender":
		return
	state = "working"
	_beer = 0.0
	mug.visible = false
	utensil.visible = false
	stream.visible = false

## Whether the villager is in the valley, not away at home.
func present() -> bool:
	return place != "home"

## Whether the villager keeps to one place, where the player may come up and
## talk to them.
func at_rest() -> bool:
	return outing == null and (place in ["work", "hall", "yard"] or (place == "" and job != "wander"))

## Whether the villager is free to be asked along on an outing.
func invitable() -> bool:
	return outing == null and (place in ["road", "yard", "hall"] or (place == "" and job == "wander"))

## Whether the villager is at their work: behind the bar, in the kitchen, about
## the hall.
func at_work() -> bool:
	return outing == null and (place == "work" or (place == "" and job != "wander"))

## Whether the villager walks their road.
func on_road() -> bool:
	return outing == null and job == "wander" and place in ["", "road"]
