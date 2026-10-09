class_name WeatherSound
extends Node
## The weather's sounds: the rain, and thunder after each strike by the time
## sound needs to arrive from it. The samples are synthesised
## (tools/pipeline/weather/weather_audio.py).

const DIRECTORY := "res://assets/audio/weather/"
const THUNDERS := 3
const SOUND_SPEED := 343.0
## Loudness of the rain at its full, outdoors and in a room, dB.
const RAIN_DB := -13.0
const RAIN_ROOM_DB := -27.0
const SILENT_DB := -70.0

var weather: WeatherSystem
## The rooms, as boxes in world space: the rain is duller inside.
var rooms: Array[AABB] = []

var _rain: AudioStreamPlayer
var _thunder: Array[AudioStreamPlayer] = []
var _streams: Array[AudioStream] = []
## Thunder on its way: {wait: seconds, db: loudness, pitch: scale}.
var _coming: Array[Dictionary] = []

func _ready() -> void:
	var loop := load(DIRECTORY + "rain_loop.wav") as AudioStreamWAV
	LakeSoundscape.set_loop(loop)
	_rain = AudioStreamPlayer.new()
	_rain.stream = loop
	_rain.volume_db = SILENT_DB
	add_child(_rain)
	for index in THUNDERS:
		_streams.append(load(DIRECTORY + "thunder_%d.wav" % index))
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		_thunder.append(voice)
	if weather != null:
		weather.lightning_struck.connect(_on_strike)

func _process(delta: float) -> void:
	if weather == null:
		return
	var camera := get_viewport().get_camera_3d()
	var indoors := EyeAdaptation.indoors(camera.global_position, rooms) if camera != null else 0.0
	var rain: float = weather.state.rain
	var wanted := lerpf(SILENT_DB, lerpf(RAIN_DB, RAIN_ROOM_DB, indoors), pow(rain, 0.3)) if rain > 0.01 else SILENT_DB
	_rain.volume_db = lerpf(_rain.volume_db, wanted, minf(delta * 2.0, 1.0))
	if rain > 0.01 and not _rain.playing:
		_rain.play()
	elif rain <= 0.01 and _rain.playing and _rain.volume_db < SILENT_DB + 3.0:
		_rain.stop()
	for thunder: Dictionary in _coming:
		thunder.wait -= delta
	while not _coming.is_empty() and _coming[0].wait <= 0.0:
		_play(_coming.pop_front(), indoors)

func _on_strike(strike: Dictionary) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var away: float = camera.global_position.distance_to(strike.at)
	var thunder := thunder_for(away, strike.power)
	# Kept in the order they arrive: a near strike can overtake a far one.
	var index := 0
	while index < _coming.size() and _coming[index].wait <= thunder.wait:
		index += 1
	_coming.insert(index, thunder)

func _play(thunder: Dictionary, indoors: float) -> void:
	for voice: AudioStreamPlayer in _thunder:
		if voice.playing:
			continue
		voice.stream = _streams[randi() % _streams.size()]
		voice.volume_db = thunder.db - 8.0 * indoors
		voice.pitch_scale = thunder.pitch
		voice.play()
		return

## When and how a strike `away` metres off is heard: later, quieter and
## duller with distance.
static func thunder_for(away: float, power: float) -> Dictionary:
	return {
		"wait": away / SOUND_SPEED,
		"db": -3.0 - 20.0 * log(maxf(away, 500.0) / 500.0) / log(10.0) * 0.75 + 6.0 * (power - 1.0),
		"pitch": lerpf(1.0, 0.78, clampf(away / 9000.0, 0.0, 1.0)),
	}
