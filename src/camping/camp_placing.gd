class_name CampPlacing
extends Node3D
## Laying a fire (CampSystem): the ghost of the wood on the ground the player
## looks at, green on a site that takes a fire (CampSystem.check_site), red
## with the reason on one that does not. K in GAME starts it and lays the
## PLACE context of the input over the game; K in PLACE stops it. E lays the
## wood (the hold of TavernInteractions, CampSystem).

var camp: CampSystem
## Whether the player is choosing the place of a fire.
var active := false
## The site under the look (check_site), {} when the look meets no ground.
var placement: Dictionary = {}
var placement_reason := ""
var ghost: Node3D
var _preview_query := PhysicsRayQueryParameters3D.new()
var _preview_tint := Color(-1, -1, -1, -1)

func _ready() -> void:
	ghost = Node3D.new()
	ghost.name = "CampPlacementPreview"
	add_child(ghost)
	for index in range(11):
		var angle := TAU * index / 11.0
		CampProps.stone(ghost, Vector3(cos(angle) * 0.57, 0.10, sin(angle) * 0.57), Vector3(0.28, 0.18, 0.23), index)
	CampProps.log_mesh(ghost, Vector3.UP * 0.15, 0.84, 0.075, 0.6)
	ghost.visible = false

func _process(_delta: float) -> void:
	if not active:
		ghost.visible = false
		return
	var shown := camp.in_play()
	ghost.visible = shown
	if shown:
		update_placement()

func _input(event: InputEvent) -> void:
	if not camp.in_play() or event.is_echo():
		return
	if InputActions.takes_in(event, &"place_camp", InputActions.PLACE):
		cancel()
		get_viewport().set_input_as_handled()
	elif InputActions.takes_in(event, &"place_camp", InputActions.GAME):
		if Player.CARRIED.has(camp.player.mode):
			camp.say(null, camp.lines.text(&"stand_on_path"))
		else:
			start()
		get_viewport().set_input_as_handled()

## The player starts choosing the place of a fire.
func start() -> void:
	active = true
	InputActions.push(InputActions.PLACE, self)

## The player stops choosing: no wood is laid.
func cancel() -> void:
	active = false
	ghost.visible = false
	InputActions.pop(self, InputActions.PLACE)

## Where the wood would go now: the ground the player looks at, checked as a
## site (`placement`, or `placement_reason` and no position).
func update_placement() -> void:
	var camera := camp.player.camera
	_preview_query.from = camera.global_position
	_preview_query.to = camera.global_position - camera.global_basis.z * 5.0
	_preview_query.collision_mask = PhysicsLayers.GROUND
	_preview_query.exclude = [camp.player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(_preview_query)
	placement = {}
	if hit.is_empty():
		placement_reason = "Посмотри на землю в нескольких шагах от себя"
		ghost.visible = false
		return
	var at: Vector3 = hit.position
	placement = camp.check_site(at)
	placement_reason = placement.reason
	ghost.global_position = hit.position + Vector3.UP * 0.01
	ghost.visible = true
	var tint := Color("91c79c") if placement.has("position") else Color("d27760")
	if tint == _preview_tint:
		return
	_preview_tint = tint
	for mesh: MeshInstance3D in ghost.get_children():
		var material := mesh.material_override as StandardMaterial3D
		material.albedo_color = tint
		material.emission_enabled = true
		material.emission = tint * 0.2

## E while the player chooses (TavernInteractions.add_hold, CampSystem).
func hold() -> Interaction:
	return Interaction.of(self, 0.0, placement_text, confirm_placement)

func placement_text() -> String:
	if placement.has("position"):
		return "{interact} — положить дрова здесь · {place_camp} — отменить"
	return tr("%s · {place_camp} — отменить") % tr(placement_reason)

func confirm_placement() -> bool:
	# Recheck at the moment of the action: an NPC may have walked into the spot.
	update_placement()
	if not placement.has("position"):
		return false
	camp.campfires.lay_fire(placement)
	cancel()
	camp.mark_changed()
	camp.say(null, camp.lines.text(&"wood_laid"))
	return true

func _exit_tree() -> void:
	InputActions.pop(self)
