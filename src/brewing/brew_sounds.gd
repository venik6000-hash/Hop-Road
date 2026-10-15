class_name BrewSounds
extends Node3D
## The brewery's work sounds (assets/audio/brewery; sources in CREDITS.md
## there): a one-shot for each stroke of a pump, blow of the mallet, pass of
## a shovel, throw; a squeak when a tap starts to turn, a clank when the hatch
## or a damper comes to an end; a loop for what runs on as loud as it runs (a
## stream, the boil, the fire, the paddle, the windlass, the quern).

const FOLDER := "res://assets/audio/brewery/"
## One-shots: name -> variations.
const SHOTS := {"pump": 4, "tap": 3, "clank": 4, "scrape": 5, "knock": 3, "log": 3, "rustle": 1}
const LOOPS: Array[String] = ["pour", "grain", "boil", "stir", "windlass", "quern", "fire"]
## Decibels of each sound at full.
const LEVELS := {"pump": -6.0, "tap": -10.0, "clank": -8.0, "scrape": -8.0, "knock": -4.0, "log": -6.0, "rustle": -10.0,
	"pour": -6.0, "grain": -8.0, "boil": -10.0, "stir": -10.0, "windlass": -8.0, "quern": -8.0, "fire": -12.0}
## The one-shot each count of a work's gesture makes.
const WORK_SHOTS := {"pump_liquor": "pump", "pump_wort": "pump", "bung_cask": "knock", "bung_keg": "knock",
	"skim": "scrape", "shovel_out": "scrape", "turn_couch": "scrape", "load_kiln": "scrape", "rake": "scrape",
	"throw_hops": "rustle", "throw_linden": "rustle", "stoke": "log", "kiln_stoke": "log"}
## The loop a turning work runs while it turns.
const WORK_LOOPS := {"stir_mash": "stir", "stir_copper": "stir", "wind": "windlass", "grind": "quern"}
## Draw works whose part clanks at either end of its travel; the other draw
## works on a part are taps, which squeak as they start to turn.
const CLANKS: Array[String] = ["hatch", "damper", "kiln_damper", "coolship_gate", "steep_plug", "quern_wedge"]
## Turns a second at which a turning work's loop is at full.
const FULL_TURNS := 1.2
## A draw work's part counts as at an end within this of it.
const END := 0.03
## Loops fade in and out over this many seconds.
const FADE := 0.25
## Metres at which a sound is half as loud.
const NEAR := 2.5
## One-shot voices at once.
const VOICES := 6

var _shots := {}
var _streams := {}
var _voices: Array[AudioStreamPlayer3D] = []
var _next := 0
## key -> {player, want (0..1 asked this frame), level (0..1 now)}.
var _loops := {}

## The one-shot a count of work `work_id`'s gesture makes, "" for none.
static func shot_of(work_id: String) -> String:
	return str(WORK_SHOTS.get(work_id, ""))

## The loop a work runs while it goes on, "" for none: a turning work's own;
## a tipped thing pours grain or liquid.
static func loop_of(work: Dictionary) -> String:
	if WORK_LOOPS.has(work.id):
		return str(WORK_LOOPS[work.id])
	if work.gesture == "tilt":
		return "grain" if BrewHouse.GRAIN_POURS.has(work.id) or str(work.id) in ["weigh_hops", "sack_kiln", "sack_bin", "line_tun"] else "pour"
	return ""

## The sound a draw work's part makes going from `before` to `after` (0..1):
## a tap squeaks as it leaves either end of its turn; the hatch and the
## dampers clank as they come to either end. "" for none.
static func draw_sound(work_id: String, before: float, after: float) -> String:
	if CLANKS.has(work_id):
		var shut := before > END and after <= END
		var open := before < 1.0 - END and after >= 1.0 - END
		return "clank" if shut or open else ""
	var leaves := before <= END and after > END or before >= 1.0 - END and after < 1.0 - END
	return "tap" if leaves else ""

func _ready() -> void:
	for name: String in SHOTS:
		var variations: Array[AudioStream] = []
		for n in int(SHOTS[name]):
			variations.append(load("%s%s_%d.wav" % [FOLDER, name, n]))
		_shots[name] = variations
	for name in LOOPS:
		var stream := load("%s%s_loop.wav" % [FOLDER, name]) as AudioStreamWAV
		LakeSoundscape.set_loop(stream)
		_streams[name] = stream
	for n in VOICES:
		var voice := _player()
		add_child(voice)
		_voices.append(voice)

## Plays one-shot `name` at `at` (world space).
func play(name: String, at: Vector3, loudness := 1.0) -> void:
	if not _shots.has(name):
		return
	var voice := _voices[_next]
	_next = (_next + 1) % _voices.size()
	var variations: Array = _shots[name]
	voice.stream = variations[randi() % variations.size()]
	voice.global_position = at
	voice.volume_db = float(LEVELS[name]) + linear_to_db(clampf(loudness, 0.01, 1.0))
	voice.pitch_scale = randf_range(0.94, 1.06)
	voice.play()

## Keeps loop `sound` running this frame under `key` at `at`, `amount` (0..1)
## loud. A loop not kept in a frame fades out.
func hum(key: String, sound: String, at: Vector3, amount: float, pitch := 1.0) -> void:
	if not _loops.has(key):
		var player := _player()
		player.stream = _streams[sound]
		add_child(player)
		_loops[key] = {"player": player, "sound": sound, "want": 0.0, "level": 0.0}
	var loop: Dictionary = _loops[key]
	loop.want = maxf(float(loop.want), clampf(amount, 0.0, 1.0))
	var player: AudioStreamPlayer3D = loop.player
	player.global_position = at
	player.pitch_scale = clampf(pitch, 0.5, 2.0)

## Loops fade to what was asked of them this frame; then the asks are cleared.
func settle(delta: float) -> void:
	for key: String in _loops:
		var loop: Dictionary = _loops[key]
		var level := move_toward(float(loop.level), float(loop.want), delta / FADE)
		loop.level = level
		loop.want = 0.0
		var player: AudioStreamPlayer3D = loop.player
		if level <= 0.001:
			if player.playing:
				player.stop()
			continue
		player.volume_db = float(LEVELS[loop.sound]) + linear_to_db(level)
		if not player.playing:
			player.play(randf() * player.stream.get_length())

func _player() -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.unit_size = NEAR
	player.max_distance = 25.0
	player.bus = &"Master"
	return player
