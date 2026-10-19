class_name NpcTier
extends RefCounted
## How often a villager's body is brought up to date (VillageNPC.tier), by the
## distance to the camera (docs/LIFE.md, «Частота обновления»). Near, the
## clip, the pose modifiers, the look and the wiping run every frame, as the
## engine runs them. Farther, within the range of the meshes, the clip and the
## modifiers step once every MID_FRAMES frames by the time gone since the last
## step; the look and the wiping wait. Past the range nothing is drawn, and
## none of them runs. The round, the bar and the body's claims (NpcBody) run
## every tick at any distance. Without a camera (a tool) the villager is near.

enum Level {NEAR, MID, FAR}
## Within this many metres a villager is near: the feet keep to the ground
## up to here (NpcFooting).
const NEAR_REACH := NpcFooting.FAR
## The meshes of a villager are drawn up to this many metres.
const MESH_REACH := 65.0
## A villager in the middle steps the clip and the modifiers once in this many
## frames.
const MID_FRAMES := 3

var level := Level.NEAR
## Steps of the clip and the modifiers taken outside the engine's own frames.
var steps := 0
var _frames := 0
var _saved := 0.0
## The engine's process modes of the clip and the modifiers, back when near.
var _animation_mode := AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
var _skeleton_mode := Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE

## The level of a villager `distance` metres from the camera.
static func level_at(distance: float) -> Level:
	if distance <= NEAR_REACH:
		return Level.NEAR
	if distance <= MESH_REACH:
		return Level.MID
	return Level.FAR

## Whether the villager is near: the look and the wiping run.
func near() -> bool:
	return level == Level.NEAR

## A frame of `delta` seconds: the level by the camera, and in the middle the
## step of the clip and the modifiers when it is due.
func update(actor: VillageNPC, delta: float) -> void:
	var camera := actor.get_viewport().get_camera_3d()
	var wanted := Level.NEAR if camera == null else level_at(camera.global_position.distance_to(actor.global_position))
	if wanted != level:
		_set_level(actor, wanted)
	if level != Level.MID:
		return
	_saved += delta
	_frames += 1
	if _frames < MID_FRAMES:
		return
	if actor.animation != null:
		actor.animation.advance(_saved)
	if actor.skeleton != null:
		actor.skeleton.advance(_saved)
	steps += 1
	_frames = 0
	_saved = 0.0

## Hands the clip and the modifiers to the engine (near) or takes them over
## (farther), and switches the look on or off.
func _set_level(actor: VillageNPC, wanted: Level) -> void:
	var animation := actor.animation
	var skeleton := actor.skeleton
	if level == Level.NEAR:
		if animation != null:
			_animation_mode = animation.callback_mode_process
		if skeleton != null:
			_skeleton_mode = skeleton.modifier_callback_mode_process
	if wanted == Level.NEAR:
		if animation != null:
			animation.callback_mode_process = _animation_mode
		if skeleton != null:
			skeleton.modifier_callback_mode_process = _skeleton_mode
	else:
		if animation != null:
			animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		if skeleton != null:
			skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	if actor.gaze != null:
		actor.gaze.active = wanted == Level.NEAR
	level = wanted
	_frames = 0
	_saved = 0.0
