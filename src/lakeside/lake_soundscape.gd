class_name LakeSoundscape
extends Node3D
## Event-driven field recordings, adapted from Tidewater SoundScape (MIT).
## Each sample's original author and CC0 source are in assets/audio/lakeside.
const DIRECTORY := "res://assets/audio/lakeside/"
const BUS := "LakesideAbove"
var player: Player
var water: WaterSystem
var terrain: TerrainSystem
var sky: SkySystem
var activities: LakesideSystem
var bank: Dictionary = {}
var voices: Array[AudioStreamPlayer3D] = []
var lowpass: AudioEffectLowPassFilter
var wind: AudioStreamPlayer
var night: AudioStreamPlayer
var lap: AudioStreamPlayer3D
var hull_lap: AudioStreamPlayer3D
var _last_runup := 0
var _reel_time := 0.0
var step_distance := 0.0
var bird_time := 2.0
var submerged := false
var _last := Vector3.ZERO
var _bank_index: Dictionary = {}
var _bus_owned := false
# player's CameraRig/Camera3D, looked up on first use (see _player_camera).
var _camera: Node
var _camera_owner: Node

func _ready() -> void:
	var files: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY + "bank.json"))
	for key: String in files:
		var streams: Array[AudioStream] = []
		for file: String in files[key]:
			streams.append(load(DIRECTORY + file))
		bank[key] = streams
	var index := AudioServer.get_bus_index(BUS)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, BUS)
		_bus_owned = true
		lowpass = AudioEffectLowPassFilter.new()
		lowpass.cutoff_hz = 20000
		AudioServer.add_bus_effect(index, lowpass)
	else:
		lowpass = AudioServer.get_bus_effect(index, 0) as AudioEffectLowPassFilter
	for i in range(12):
		var voice := AudioStreamPlayer3D.new()
		voice.bus = BUS
		voice.max_distance = 55
		voice.unit_size = 4
		add_child(voice)
		voices.append(voice)
	wind = make_loop("wind")
	night = make_loop("crickets")
	lap = AudioStreamPlayer3D.new()
	lap.stream = bank.pier_lap[0]
	set_loop(lap.stream as AudioStreamWAV)
	lap.bus = BUS
	lap.unit_size = 5
	lap.max_distance = 45
	lap.volume_db = -14
	add_child(lap)
	lap.position = activities.boat.anchor
	lap.play()
	hull_lap = AudioStreamPlayer3D.new()
	hull_lap.stream = bank.boat_lap[0]
	set_loop(hull_lap.stream as AudioStreamWAV)
	hull_lap.bus = BUS
	hull_lap.max_distance = 16
	hull_lap.unit_size = 2
	hull_lap.volume_db = -22
	activities.boat.add_child(hull_lap)
	hull_lap.play()
	_last = player.global_position
	_replace_forest_loop.call_deferred()

func _replace_forest_loop() -> void:
	# Wildlife finishes populating before this deferred callback.
	var wildlife := get_parent().get_node_or_null("Wildlife")
	if wildlife != null and wildlife.audio != null:
		wildlife.audio.stop()

func _exit_tree() -> void:
	if _bus_owned:
		var index := AudioServer.get_bus_index(BUS)
		if index > 0:
			AudioServer.remove_bus(index)

static func set_loop(stream: AudioStreamWAV) -> void:
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = int(stream.get_length() * stream.mix_rate)

func make_loop(key: String) -> AudioStreamPlayer:
	var stream := bank[key][0] as AudioStreamWAV
	set_loop(stream)
	var voice := AudioStreamPlayer.new()
	voice.stream = stream
	voice.bus = BUS
	voice.volume_db = -35
	add_child(voice)
	voice.play()
	return voice

func play_event(key: String, point: Vector3, gain := -14.0) -> void:
	if not bank.has(key):
		return
	for voice in voices:
		if voice.playing:
			continue
		var index: int = int(_bank_index.get(key, 0)) % bank[key].size()
		_bank_index[key] = index + 1
		voice.stream = bank[key][index]
		voice.position = point
		voice.volume_db = gain
		voice.pitch_scale = randf_range(0.95, 1.05)
		voice.bus = "Master" if key in ["uw_swim", "submerge", "emerge"] else BUS
		voice.play()
		return

func surface_sound() -> String:
	if water.water_level - player.global_position.y > 0.05:
		return "step_water"
	var ray := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 0.3, player.global_position - Vector3.UP * 0.3)
	ray.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		var label := str(hit.collider.get_path()).to_lower()
		if "terrain" not in label:
			return "step_rock" if "rock" in label or "stone" in label else "step_wood"
	var at := player.global_position
	if at.y < water.water_level + 1.2:
		return "step_sand"
	if absf(at.x) < 5.0 and at.z > -45 and at.z < 15:
		return "step_rock"
	return "step_grass"

## The node at player's "CameraRig/Camera3D", as get_node() would return it.
## Looked up lazily: the player and its script can be set after _ready (tools
## swap in tools/lib/background_player.gd), and again when the node is
## replaced.
func _player_camera() -> Node:
	if _camera_owner != player or not is_instance_valid(_camera) or _camera.get_parent() == null \
			or _camera.get_parent().get_parent() != player:
		_camera = player.get_node("CameraRig/Camera3D")
		_camera_owner = player
	return _camera

func _process(delta: float) -> void:
	var eye := _player_camera() as Camera3D
	var under := eye.global_position.y < player.water_surface - 0.03
	if under != submerged:
		submerged = under
		play_event("submerge" if under else "emerge", eye.global_position, -11)
	lowpass.cutoff_hz = lerpf(lowpass.cutoff_hz, 650.0 if under else 20000.0, 1.0 - exp(-delta * 8))
	wind.volume_db = -34 + clampf(water.ocean.wind_speed, 0, 20) * 0.5
	var is_night := sky.time_of_day < 5.5 or sky.time_of_day > 20
	night.volume_db = lerpf(night.volume_db, -25.0 if is_night and eye.global_position.y > water.water_level else -70.0, delta)
	hull_lap.volume_db = -25 + minf(activities.boat.velocity.length(), 3.0) * 2.0
	var runup := int(activities.clock * 1.25 / TAU)
	if runup != _last_runup:
		_last_runup = runup
		var point := player.global_position
		if point.y > water.water_level and point.y < water.water_level + 1.3:
			play_event("splash", point + Vector3(0, -0.4, -2), -27)
	_reel_time = maxf(0, _reel_time - delta)
	if activities.phase == "fight" and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _reel_time <= 0:
		play_event("reel_wind", eye.global_position, -25)
		_reel_time = 0.6
	var moved := player.global_position.distance_to(_last)
	_last = player.global_position
	if moved < 2 and not activities.aboard and player.is_physics_processing() and (player.is_on_floor() or player.swimming):
		step_distance += moved
		if step_distance > (1.7 if player.swimming else 1.4):
			step_distance = 0
			play_event(("uw_swim" if under else "swim") if player.swimming else surface_sound(), player.global_position, -15)
	bird_time -= delta
	if bird_time <= 0:
		bird_time = randf_range(4, 10) if not is_night else 15
		var at := player.global_position + Vector3(randf_range(-22,22), 0, randf_range(-22,22))
		at.y = terrain.height_at(at.x, at.z)
		if not is_night and at.y > water.water_level + 1 and not under:
			play_event("bird_forest" if randf() > 0.25 else "bird_dove", at + Vector3.UP * 5, -23)
