class_name NpcMotion
extends RefCounted
## Recorded motion for the villagers' models: assets/models/npc/motion/<model>.glb
## holds the model's skeleton alone with one animation per clip
## (tools/pipeline/npc/motion.py), <model>.json what the game has to know of
## each. The clips come to a villager's AnimationPlayer as the library
## LIBRARY; the model's own file keeps the clips it came with.
const FOLDER := "res://assets/models/npc/motion/"
const LIBRARY := &"motion"
## Seconds over which one recorded clip gives way to the next.
const BLEND := 0.4
## The gaits, slowest first: a walker takes the one drawn nearest their speed.
const GAITS: Array[String] = ["walk_slow", "walk", "walk_brisk"]
## A gait is played no slower and no faster than this many times its own pace:
## past that the feet slide.
const GAIT_SLOWEST := 0.7
const GAIT_FASTEST := 1.9
## The models that are women: they walk by the gait recorded from a woman.
const WOMEN: Array[String] = ["bartender", "maid"]
const WOMANS_GAIT := "walk_woman"

## Model name -> AnimationLibrary, null for a model without recorded motion.
static var _libraries: Dictionary = {}
## Model name -> {clip: {length, speed}}.
static var _facts: Dictionary = {}


static func model_name(model_path: String) -> String:
	return model_path.get_file().get_basename()

## Gives `player` the recorded clips of the model; false when it has none.
## Tracks are bound by bone name to `skeleton`, so the motion file need not
## repeat the model's node names.
static func attach(model_path: String, player: AnimationPlayer, skeleton: Skeleton3D) -> bool:
	var model := model_name(model_path)
	if not _libraries.has(model):
		_libraries[model] = _library(model, player, skeleton)
	var library: AnimationLibrary = _libraries[model]
	if library == null:
		return false
	if not player.has_animation_library(LIBRARY):
		player.add_animation_library(LIBRARY, library)
	return true

## What is known of the model's clip: {length, speed}; empty for none.
static func facts(model_path: String, clip: String) -> Dictionary:
	var known: Dictionary = _facts.get(model_name(model_path), {})
	return known.get(clip, {})

## The gait of the model drawn nearest `speed`, m/s, and how fast to play it:
## {clip, scale}. `own` is tried first when the model has it (a villager's own
## way of walking); empty when the model has no recorded gait.
static func gait(model_path: String, speed: float, own := "") -> Dictionary:
	var best := ""
	var best_scale := 1.0
	var tried: Array[String] = []
	if own != "":
		tried.append(own)
	tried.append_array(GAITS)
	for clip in tried:
		var drawn := Values.real(facts(model_path, clip).get("speed", 0.0))
		if drawn <= 0.0:
			continue
		var scale := speed / drawn
		if clip == own and scale >= GAIT_SLOWEST and scale <= 1.25:
			return {"clip": clip, "scale": scale}
		if best == "" or absf(log(scale)) < absf(log(best_scale)):
			best = clip
			best_scale = scale
	if best == "":
		return {}
	return {"clip": best, "scale": clampf(best_scale, GAIT_SLOWEST, GAIT_FASTEST)}

static func _library(model: String, player: AnimationPlayer, skeleton: Skeleton3D) -> AnimationLibrary:
	var path := FOLDER + model + ".glb"
	if skeleton == null or not ResourceLoader.exists(path):
		return null
	var scene := (load(path) as PackedScene).instantiate()
	var source := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if source == null:
		scene.free()
		return null
	var bones := str(player.get_node(player.root_node).get_path_to(skeleton))
	var library := AnimationLibrary.new()
	for clip in source.get_animation_list():
		var animation := source.get_animation(clip).duplicate() as Animation
		for track in range(animation.get_track_count() - 1, -1, -1):
			var bone := animation.track_get_path(track).get_concatenated_subnames()
			if bone == "" or skeleton.find_bone(bone) < 0:
				animation.remove_track(track)
			else:
				animation.track_set_path(track, NodePath(bones + ":" + bone))
		library.add_animation(clip, animation)
	scene.free()
	var listed: Variant = DataFile.read(FOLDER + model + ".json", BodySchemas.npc_motion())
	_facts[model] = listed if listed is Dictionary else {}
	return library
