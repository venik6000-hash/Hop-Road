class_name VillagerSight
extends RefCounted
## What the player sees of the villagers (VillagerPresence): a villager is
## moved to another place only where the player sees neither them nor the
## place.

## The villagers' meshes end this far from the camera.
const FAR := 65.0
## The heights over the feet at which a body is looked for: the chest and the
## head. One who shows either is seen.
const LOOKS: Array[float] = [0.9, 1.55]
## A look that ends at least this far short of the point has met a wall.
const SHORT := 0.5

var population: NpcPopulation
var player: Player
## The player's camera; the viewport's camera stands in while it is not the
## current one.
var camera: Camera3D

func _init(people: NpcPopulation, viewer: Player, eye: Camera3D) -> void:
	population = people
	player = viewer
	camera = eye

## Whether the player sees nothing at `point` (the feet of a body, or of the
## place for one): it is farther than the villagers are drawn, out of the
## picture, or behind something. `body` is the villager who stands there.
func unseen(point: Vector3, body: VillageNPC = null) -> bool:
	var eye := _eye()
	if eye == null:
		return true
	for height: float in LOOKS:
		if _shows(eye, point + Vector3.UP * height, body):
			return false
	return true

## Whether the camera has the point in the picture with nothing solid before
## it. `body` is looked through.
func _shows(eye: Camera3D, at: Vector3, body: VillageNPC) -> bool:
	var from := eye.global_position
	if from.distance_to(at) > FAR or not eye.is_position_in_frustum(at):
		return false
	var query := PhysicsRayQueryParameters3D.create(from, at, PhysicsLayers.GROUND)
	var passed: Array[RID] = [player.get_rid()]
	if body != null:
		passed.append(body.get_rid())
	query.exclude = passed
	var hit := population.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	var met: Vector3 = hit.position
	return met.distance_to(at) <= SHORT

## The camera the player looks through now; null when there is none.
func _eye() -> Camera3D:
	if is_instance_valid(camera) and camera.is_inside_tree() and camera.current:
		return camera
	return population.get_viewport().get_camera_3d()
