class_name BrewEye
extends RefCounted
## What the player's eye has in sight at the brewery (BrewHouse): how far a
## point is when the eye is on it, and whether a wall stands between.

## Metres an eye reaches, and how close to the middle of the view a thing
## must be to be looked at (TavernInteractions').
const REACH := TavernInteractions.REACH
const AIM := TavernInteractions.TARGET_DOT
## Metres before a point read off that something may stand and the point
## still counts as seen (clear): a vessel's rim, a tap's own body.
const SEEN_SLACK := 0.5

var player: Player
var camera: Camera3D

func _init(body: Player, eye: Camera3D) -> void:
	player = body
	camera = eye

## How far a point is when the eye is on it, INF when it is not.
func aimed(point: Vector3) -> float:
	var offset := point - camera.global_position
	var distance := offset.length()
	if distance > REACH or distance < 0.01 or (-camera.global_basis.z).dot(offset / distance) < AIM:
		return INF
	return distance

## How far a point read off is when the eye is on it (aimed), INF when a wall
## stands between (clear).
func read_at(point: Vector3) -> float:
	var distance := aimed(point)
	return distance if distance < INF and clear(point) else INF

## Whether nothing stands between the eye and a point: a ray from the eye meets
## nothing farther than SEEN_SLACK from it (a vessel's own rim may stand before it).
func clear(point: Vector3) -> bool:
	var hit := ray(camera.global_position, point)
	if hit.is_empty():
		return true
	var met: Vector3 = hit.position
	return met.distance_to(point) <= SEEN_SLACK

## How much a point is off the middle of the view: 0 on it, 1 at a right angle.
func off_aim(point: Vector3) -> float:
	return 1.0 - (-camera.global_basis.z).dot((point - camera.global_position).normalized())

## What a ray from `from` to `to` meets first, the player's body left out
## (PhysicsDirectSpaceState3D.intersect_ray); `mask` the layers it sees.
func ray(from: Vector3, to: Vector3, mask := 0xFFFFFFFF) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask, [player.get_rid()])
	return player.get_world_3d().direct_space_state.intersect_ray(query)

## What the eye's ray meets within REACH, {} for nothing.
func ahead() -> Dictionary:
	return ray(camera.global_position, camera.global_position - camera.global_basis.z * REACH)
