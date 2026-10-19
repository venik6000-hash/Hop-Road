class_name TavernFurnishings
extends Node
## What E finds in the rooms of a tavern (TavernSystem.furnish): its seats,
## the ladder to the attic and the beds. The tables give them in the
## tavern's frame; the tavern's place turns them into the world. A source of
## targets and a hold of the player's E (TavernInteractions.add_source,
## add_hold): the core of E names none of them. The tavern gives it to E
## through WorldContext.interaction_sources (TavernSystem.furnish).

## Where a seat is looked at, above its place on the floor.
const SEAT_TARGET_HEIGHT := 1.05

var tavern: TavernSystem
var interactions: TavernInteractions
## The tavern's seats in the world: where the player and the villagers sit.
var seats: Array[Dictionary] = []
## The player is on this tavern's ladder.
var _on_ladder := false
var _climb_tween: Tween

func _ready() -> void:
	var place := tavern.global_transform
	for seat: Dictionary in tavern.seats:
		seats.append(placed(seat, place))
	interactions.seats.append_array(seats)
	interactions.add_source(_seat_target)
	if tavern.ladder != null:
		interactions.add_source(_ladder_target)
		interactions.add_hold(_climb_hold)
	interactions.add_source(_bed_target)
	interactions.released.connect(_released)

## The seats go with the tavern; its sources and holds go by themselves
## (TavernInteractions.add_source).
func _exit_tree() -> void:
	if is_instance_valid(interactions):
		interactions.drop_seats(seats, _on_ladder)

## A seat of a table, its place, facing and ways out turned into the world
## by the tavern's `place`.
static func placed(seat: Dictionary, place: Transform3D) -> Dictionary:
	var world := seat.duplicate()
	world.position = _listed(place * Values.vec3(seat.position))
	world.facing = _listed(place.basis * Values.vec3(seat.facing))
	var exits: Array = []
	for exit: Variant in Values.list(seat.exits):
		exits.append(_listed(place * Values.vec3(exit)))
	world.exits = exits
	return world

static func _listed(point: Vector3) -> Array:
	return [point.x, point.y, point.z]

## Whether the player is below the attic of the tavern.
func _below_attic() -> bool:
	return tavern.ladder.below(tavern.global_transform.affine_inverse() * interactions.player.global_position)

func _seat_target(best: float) -> Interaction:
	var valley := interactions.valley
	var presence: VillagerPresence = valley.presence if valley != null else null
	var found: Interaction = null
	for seat: Dictionary in seats:
		if presence != null and presence.seat_taken(seat):
			continue
		var distance := interactions.target_distance(Values.vec3(seat.position) + Vector3.UP * SEAT_TARGET_HEIGHT)
		if distance < best:
			best = distance
			found = interactions.seat_interaction(seat, distance)
	return found

func _ladder_target(best: float) -> Interaction:
	var below := _below_attic()
	var ladder := tavern.ladder
	var point := tavern.global_transform * (ladder.foot + Vector3.UP if below else ladder.attic + Vector3.UP * 0.15)
	var distance := interactions.target_distance(point, null, true)
	if distance >= best:
		return null
	var text := "{interact} — подняться на чердак" if below else "{interact} — спуститься с чердака"
	return Interaction.of("ladder", distance, func() -> String: return text, climb)

## A bed in a guest room; only the game's day and night (valley) make it one.
func _bed_target(best: float) -> Interaction:
	var valley := interactions.valley
	if valley == null:
		return null
	var camera := interactions.camera
	var bed: Variant = TavernBeds.looked_at(tavern.beds, tavern.global_transform, camera.global_position,
		-camera.global_basis.z)
	if bed == null:
		return null
	var on_bed: Vector3 = bed
	# The point lies on the bed's collider: the ladder's leeway covers the
	# little by which the box here and the collider differ.
	var distance := interactions.target_distance(on_bed, null, true)
	if distance >= best:
		return null
	return Interaction.of("bed", distance, func() -> String: return "{interact} — спать до утра", valley.sleep_till_morning)

## The ladder climbed holds E: it does nothing until the top or the foot.
func _climb_hold() -> Interaction:
	if not _on_ladder:
		return null
	var text := "Подъём по лестнице…" if _below_attic() else "Лестница на чердак"
	return Interaction.of("ladder", 0.0, func() -> String: return text, func() -> void: pass)

## Climbs the ladder up to the attic or down to the corridor: to the foot,
## through the hatch, then a step clear of it.
func climb() -> bool:
	if interactions.player.mode != Player.WALK:
		return false
	var player := interactions.player
	var place := tavern.global_transform
	var ladder := tavern.ladder
	var up := _below_attic()
	var target := place * (ladder.attic if up else ladder.corridor)
	if not interactions.can_stand(target):
		interactions.prompt.text = "Выход с лестницы занят"
		return false
	if not interactions.carry_player(Player.LADDER):
		return false
	interactions.climbing = true
	_on_ladder = true
	player.rig.yaw_deg = rad_to_deg(place.basis.get_euler().y) + (0.0 if up else 180.0)
	player.rig.pitch_deg = 12.0 if up else -25.0
	player.rig.apply_look(Vector2.ZERO)
	var tween := create_tween()
	_climb_tween = tween
	var approach := place * (ladder.foot if up else ladder.hatch)
	var rim := place * (ladder.hatch if up else ladder.foot)
	tween.tween_property(player, "global_position", approach, 0.4)
	tween.tween_property(player, "global_position", rim, 3.0)
	tween.tween_property(player, "global_position", target + Vector3.UP * 0.015, 0.65)
	await tween.finished
	interactions.climbing = false
	_on_ladder = false
	_climb_tween = null
	interactions.restore_player()
	return true

## The player was taken out of whatever held them (TavernInteractions.reset):
## off the ladder at once.
func _released() -> void:
	if _climb_tween != null:
		_climb_tween.kill()
		_climb_tween = null
	_on_ladder = false
