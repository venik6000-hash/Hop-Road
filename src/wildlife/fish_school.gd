class_name FishSchool
extends Node3D
## Coherent schools with individual tail motion, depth and diver avoidance.
##
## Each species keeps to its own water: rudd cruise the open water near the
## surface, perch hang in tight groups over the eelgrass, trout hold low by
## drowned wood and barely move, and a pike lies at the edge of a meadow.
const SceneUtil = preload("res://src/common/scene_util.gd")
const HABITS := {
	"fish": {"count": 12, "radius": Vector2(6, 4), "rate": 0.14, "spread": 1.0, "hover": Vector2(1.6, 6.0), "below": 1.3, "wander": 0.23},
	"perch": {"count": 8, "radius": Vector2(2.6, 2.0), "rate": 0.09, "spread": 0.55, "hover": Vector2(0.6, 2.2), "below": 1.1, "wander": 0.14},
	"trout": {"count": 4, "radius": Vector2(2.4, 1.6), "rate": 0.06, "spread": 0.8, "hover": Vector2(0.45, 1.3), "below": 2.0, "wander": 0.09},
	"pike": {"count": 1, "radius": Vector2(1.2, 0.8), "rate": 0.025, "spread": 1.0, "hover": Vector2(0.35, 0.9), "below": 1.2, "wander": 0.03},
}
var habitat: WildlifeSystem
var center := Vector3.ZERO
var count := 12
var species := "fish"
var radius := Vector2(6, 4)
var rate := 0.14
var spread_scale := 1.0
var hover := Vector2(1.6, 6.0)
var below := 1.3
var wander := 0.23
var phase := 0.0
var fishes: Array[Node3D] = []
var animations: Array[AnimationPlayer] = []
var _clock := 0.0
var active := true

func _ready() -> void:
	var habit: Dictionary = HABITS.get(species, HABITS.fish)
	radius = habit.radius
	rate = habit.rate
	spread_scale = habit.spread
	hover = habit.hover
	below = habit.below
	wander = habit.wander
	for index in count:
		var fish := Node3D.new()
		fish.name = "Fish%02d" % index
		var model := WildlifeModel.instantiate(species, 65.0)
		fish.add_child(model)
		var size := 0.65 + float(index % 5) * 0.13
		fish.scale = Vector3.ONE * size
		add_child(fish)
		fishes.append(fish)
		var animation: AnimationPlayer = SceneUtil.animation_player(model)
		animations.append(animation)
		WildlifeModel.play(animation, "swim", (0.8 + float(index % 4) * 0.1) * (0.5 if species in ["trout", "pike"] else 1.0))
		if animation != null:
			animation.seek(float(index) * 0.21, true)
	advance(0.0)

func set_active(value: bool) -> void:
	active = value
	visible = value
	set_process(value)
	for animation in animations:
		if animation != null:
			animation.set_active(value)

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	_clock += delta
	var angle := _clock * rate + phase
	var leader := center + Vector3(cos(angle) * radius.x, sin(angle * 1.7) * 0.4, sin(angle) * radius.y)
	for index in fishes.size():
		var fish := fishes[index]
		var spread := Vector3(float(index % 4) * 0.85 - 1.3, float(index % 3) * 0.28 - 0.3, float(index / 4) * 0.95 - 1.0) * spread_scale
		var next := leader + spread + Vector3(sin(_clock * 0.7 + index), sin(_clock + index) * 0.2, cos(_clock * 0.5 + index)) * wander
		if habitat.player != null:
			var away := next - habitat.player.global_position
			if away.length_squared() < 9.0:
				next += away.normalized() * (3.0 - away.length())
		var floor_y := _floor(next)
		var ceiling := habitat.terrain.water_level - below
		if ceiling - floor_y < hover.x + 0.3:
			# The slope, or a boulder breaking the surface, rises into water
			# too shallow for this species: the fish turns back toward the
			# school's centre, which lies deep enough.
			next = Vector3(center.x, next.y, center.z) + (next - center) * 0.3
			floor_y = _floor(next)
			if ceiling - floor_y < hover.x + 0.3:
				next = Vector3(center.x, next.y, center.z)
				floor_y = _floor(next)
		var low := floor_y + hover.x
		var high := maxf(low, minf(floor_y + hover.y, ceiling))
		next.y = clampf(next.y, low, high)
		var direction := next - fish.position
		if direction.length_squared() > 0.00001:
			var heading := atan2(-direction.x, -direction.z)
			fish.rotation.y = heading if delta == 0.0 else lerp_angle(fish.rotation.y, heading, minf(delta * 4.0, 1.0))
		fish.position = next

func _floor(point: Vector3) -> float:
	# seabed_at already includes the exact terrain height at this point.
	if habitat.bed != null:
		return habitat.bed.seabed_at(point.x, point.z)
	return habitat.terrain.height_at(point.x, point.z)
