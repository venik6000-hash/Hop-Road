class_name AudioBuses
extends RefCounted
## The sound buses of the game (default_bus_layout.tres) and their volumes.
## Every source of sound plays on one of these buses, never on Master. The
## player sets the volume of each bus in VOLUMES (GameSettings). mute_world
## is the pause's: it mutes WORLD, the parent of the buses of the world, and
## MUSIC and UI play on.

const MASTER := &"Master"
const MUSIC := &"Music"
const UI := &"UI"
## Parent of AMBIENCE, EFFECTS and VOICE.
const WORLD := &"World"
const AMBIENCE := &"Ambience"
const EFFECTS := &"Effects"
const VOICE := &"Voice"
## The ambience and effects of the lake heard from above its water. A
## low-pass filter on each muffles them for an eye under the water
## (LakeSoundscape).
const LAKE_AMBIENCE := &"LakeAmbience"
const LAKE_EFFECTS := &"LakeEffects"
## The buses whose volume the player sets, in the order of the settings panel.
const VOLUMES: Array[StringName] = [MASTER, MUSIC, AMBIENCE, EFFECTS, VOICE, UI]

## Sets the volume of `bus`, 0..1 of its full loudness; 0 mutes it.
static func set_volume(bus: StringName, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	var level := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(index, level <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(level, 0.0001)))

## Mutes or unmutes the sounds of the world (a pause).
static func mute_world(muted: bool) -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index(WORLD), muted)

## The low-pass filters of the lake's buses.
static func lake_filters() -> Array[AudioEffectLowPassFilter]:
	var filters: Array[AudioEffectLowPassFilter] = []
	for bus: StringName in [LAKE_AMBIENCE, LAKE_EFFECTS]:
		filters.append(AudioServer.get_bus_effect(AudioServer.get_bus_index(bus), 0) as AudioEffectLowPassFilter)
	return filters
