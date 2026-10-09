class_name FlyingAnimal
extends Node3D
## Small flocks share a flight corridor, with individual phase and wingbeats.
##
## Species fly differently: the shrike flaps in short loops over the meadows,
## ravens beat and glide in wide circles over the woods, gulls glide low along
## the lake with a few beats between long slides.
const SceneUtil = preload("res://src/common/scene_util.gd")
var kind := "bird"
var species := "bird"
var habitat: WildlifeSystem
var home := Vector3.ZERO
var radius := Vector2(18, 12)
var phase := 0.0
var rate := 0.18
var height := 20.0
var flock_offset := Vector3.ZERO
## Share of the time spent gliding, and how long a flap-glide cycle lasts (s).
var glide_share := 0.33
var cycle := 9.0
var animation: AnimationPlayer
var _clock := 0.0
var _previous := Vector3.ZERO
var active := true

func _ready() -> void:
	var model := WildlifeModel.instantiate(species if kind == "bird" else kind, 240.0 if kind == "bird" else 38.0)
	add_child(model)
	animation = SceneUtil.animation_player(model)
	if species == "seagull":
		glide_share = 0.7
		cycle = 12.0
	elif species == "raven":
		glide_share = 0.45
		cycle = 10.0
	WildlifeModel.play(animation, "fly", 0.9 + fmod(phase, 0.4))
	if animation != null and animation.current_animation_length > 0.0:
		animation.seek(fmod(phase, animation.current_animation_length), true)
	advance(0.0)
	_previous = position

func set_active(value: bool) -> void:
	active = value
	set_process(value)
	if animation != null:
		animation.set_active(value)

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	_clock += delta
	if kind == "bird":
		var gliding := fmod(_clock + phase * 11.0, cycle) > cycle * (1.0 - glide_share)
		WildlifeModel.play(animation, "glide" if gliding else "fly", 1.2 + fmod(phase, 0.5))
	var angle := _clock * rate + phase
	var next := home + Vector3(cos(angle) * radius.x, 0.0, sin(angle) * radius.y) + flock_offset
	var ground := habitat.terrain.height_at(next.x, next.z)
	if kind == "bird":
		var floor_y := maxf(ground, habitat.terrain.water_level)
		next.y = maxf(home.y + height + sin(angle * 2.0 + phase) * 2.4, floor_y + (4.0 if species == "seagull" else 12.0))
	else:
		next.y = ground + height + sin(angle * 3.0) * 0.25
		# Brief hovering over the meadow alternates with wandering.
		next += Vector3(sin(angle * 4.7), 0, cos(angle * 3.1)) * 0.3
	var direction := next - _previous
	if direction.length_squared() > 0.00001:
		rotation.y = atan2(-direction.x, -direction.z)
		rotation.z = lerpf(rotation.z, sin(angle) * (0.16 if kind == "bird" else 0.25), minf(delta * 3.0, 1.0))
	position = next
	_previous = next
