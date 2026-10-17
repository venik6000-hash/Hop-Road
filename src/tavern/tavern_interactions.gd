class_name TavernInteractions
extends Node
## Contextual E leaves the mug action available when no furnishing is targeted.
##
## Targets come from sources (add_source): each is asked in turn for its nearest
## target within the best distance found so far, and the nearest of all wins.
## The tavern's own furnishings (the innkeeper, the seats, the ladder, the
## beds) are sources of this node; every node of Interaction.GROUP (a door, a
## work handle) is one by itself; the brewery, the camping and the boat
## (LakesideSystem) add theirs. Before the targets come the holds
## (add_hold): states that take E whole, each with its own prompt (the ladder
## climbed, the boat under way, a fire being laid, a brewery's station), then
## the seat the player sits on. A new kind of target or hold adds a source or
## a hold, not a branch here.

## The player is taken out of whatever held them (reset): a hold lets go.
signal released

const REACH := 2.4
const TARGET_DOT := 0.93
const SEAT_TARGET_HEIGHT := 1.05
const LADDER_BOTTOM := Vector3(9.25, 10.86, -7.72)
const LADDER_TOP := Vector3(9.25, 14.875, -8.65)
## Where the innkeeper is looked at, from his feet (VillageNPC.interaction_point):
## the jug he leaves on the counter is looked at there.
const BAR_TARGET := Vector3(0.0, 1.3, -0.6)
## The prompt of a seat sat on.
const STAND_HINT := "{interact} — встать   ·   {look} — обзор"
var player: Player
## The tavern; null in a region without it.
var tavern: TavernSystem
var population: NpcPopulation
var camping: CampSystem
## The game's day and night (the world loader's ValleyLoop); without it the
## beds are furniture.
var valley: ValleyLoop
var camera: Camera3D
var prompt: Label
var seats: Array[Dictionary] = []
var seated: Dictionary = {}
## The thing E would act on this frame (Interaction.subject); null for none.
var selected: Variant = null
var climbing := false
var _standing_eye := 1.6
var _climb_tween: Tween
## Callable(best: float) -> Interaction: the source's nearest target nearer
## than `best`, null for none. Asked in this order; a tie keeps the earlier.
var _sources: Array[Callable] = []
## Callable() -> Interaction: the state that takes E whole now, null when it
## does not. Asked in this order; the first that holds wins.
var _holds: Array[Callable] = []
## What E would do this frame, null for nothing.
var _chosen: Interaction

func _ready() -> void:
	camera = player.get_node("CameraRig/Camera3D")
	_standing_eye = player.rig.position.y
	add_source(_bar_target)
	for node: Node in get_tree().get_nodes_in_group(Interaction.GROUP):
		add_source(Callable(node, &"interaction").bind(self))
	# A region without the tavern has none of its seats, its ladder and its beds.
	if tavern != null:
		seats = tavern.seats
		for source: Callable in [_seat_target, _ladder_target, _bed_target]:
			add_source(source)
		add_hold(_climb_hold)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	prompt = Label.new()
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.offset_top = -112
	prompt.offset_bottom = -64
	prompt.anchor_left = 0.0
	prompt.anchor_right = 1.0
	prompt.offset_left = 24
	prompt.offset_right = -24
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 24)
	prompt.add_theme_color_override("font_color", Color("fff5dc"))
	prompt.add_theme_color_override("font_shadow_color", Color.BLACK)
	prompt.add_theme_constant_override("shadow_offset_x", 2)
	prompt.add_theme_constant_override("shadow_offset_y", 2)
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(prompt)

## Adds a source of targets for E: `source` is Callable(best: float) ->
## Interaction, the nearest target nearer than `best` or null.
func add_source(source: Callable) -> void:
	_sources.append(source)

## Adds a state that takes E whole: `hold` is Callable() -> Interaction, its
## prompt and act while it holds, null when it does not.
func add_hold(hold: Callable) -> void:
	_holds.append(hold)

## The hold that has E now, null for none.
func _hold() -> Interaction:
	for hold: Callable in _holds:
		var held: Interaction = hold.call()
		if held != null:
			return held
	return null

## The ladder climbed holds E: it does nothing until the top or the foot.
func _climb_hold() -> Interaction:
	if not climbing:
		return null
	var text := "Подъём по лестнице…" if player.global_position.y < 13.0 else "Лестница на чердак"
	return Interaction.of("ladder", 0.0, func() -> String: return text, func() -> void: pass)

func _process(_delta: float) -> void:
	selected = null
	_chosen = null
	prompt.text = InputActions.hint(tr(_prompt_text()))

## What the prompt says in this frame: a key of the table or words already
## translated, with the labels of InputActions.hint still to put in; picks
## `_chosen` and `selected`.
func _prompt_text() -> String:
	if not camera.current or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return ""
	return choose()

## Picks `_chosen` and `selected` where the eye looks and returns the prompt's
## words, as each frame does while the pointer is captured. A tool without a
## window, where the pointer is never captured, calls it and act() itself.
func choose() -> String:
	if valley != null and valley.sleeping:
		return ""
	var hold := _hold()
	if hold != null:
		return str(hold.describe.call())
	if not seated.is_empty():
		return STAND_HINT
	var best := REACH
	for source: Callable in _sources:
		var found: Interaction = source.call(best)
		if found != null and found.distance < best:
			best = found.distance
			_chosen = found
	if _chosen == null:
		return ""
	selected = _chosen.subject
	return str(_chosen.describe.call())

## A villager as a target: the innkeeper at work serves, anyone else goes by
## the camping (talk, invite for a walk).
func npc_interaction(actor: VillageNPC, distance: float) -> Interaction:
	if actor.job == "bartender" and actor.at_work():
		return Interaction.of(actor, distance, actor.interaction_text, actor.interact.bind(player))
	return Interaction.of(actor, distance, camping.interaction_text.bind(actor), camping.interact_npc.bind(actor))

## A seat as a target: the tavern's own (seats) or one at a campfire.
func seat_interaction(seat: Dictionary, distance: float) -> Interaction:
	return Interaction.of(seat, distance, func() -> String: return tr("{interact} — сесть · %s") % tr(seat_title(str(seat.name))),
		sit.bind(seat))

## The name of a seat as the player reads it: Blender's copy number
## ("Большой стол.003") is not part of it.
static func seat_title(title: String) -> String:
	var dot := title.rfind(".")
	return title.left(dot) if dot > 0 and title.substr(dot + 1).is_valid_int() else title

## The innkeeper at work, or the jug he leaves on the counter while he is out.
func _bar_target(best: float) -> Interaction:
	if population == null or population.bartender == null:
		return null
	var barkeeper := population.bartender
	if barkeeper.at_work():
		var distance := target_distance(barkeeper.interaction_point())
		return npc_interaction(barkeeper, distance) if distance < best else null
	if valley == null or valley.presence == null:
		return null
	var jug_distance := target_distance(bar_point(barkeeper))
	if jug_distance >= best:
		return null
	return Interaction.of("jug", jug_distance, func() -> String: return "{interact} — налить из кувшина", pour_from_jug)

func _seat_target(best: float) -> Interaction:
	var presence: VillagerPresence = valley.presence if valley != null else null
	var found: Interaction = null
	for seat: Dictionary in seats:
		if presence != null and presence.seat_taken(seat):
			continue
		var distance := target_distance(Values.vec3(seat.position) + Vector3.UP * SEAT_TARGET_HEIGHT)
		if distance < best:
			best = distance
			found = seat_interaction(seat, distance)
	return found

func _ladder_target(best: float) -> Interaction:
	var below := player.global_position.y < 13.0
	var ladder := LADDER_BOTTOM + Vector3.UP if below else LADDER_TOP + Vector3.UP * 0.15
	var distance := target_distance(ladder, null, true)
	if distance >= best:
		return null
	var text := "{interact} — подняться на чердак" if below else "{interact} — спуститься с чердака"
	return Interaction.of("ladder", distance, func() -> String: return text, climb)

## A bed in a guest room; only the game's day and night (valley) make it one.
func _bed_target(best: float) -> Interaction:
	if valley == null:
		return null
	var bed: Variant = TavernBeds.looked_at(camera.global_position, -camera.global_basis.z)
	if bed == null:
		return null
	var on_bed: Vector3 = bed
	# The point lies on the bed's collider: the ladder's leeway covers the
	# little by which the box here and the collider differ.
	var distance := target_distance(on_bed, null, true)
	if distance >= best:
		return null
	return Interaction.of("bed", distance, func() -> String: return "{interact} — спать до утра", valley.sleep_till_morning)

## The point over the counter where the innkeeper is looked at when he works.
func bar_point(barkeeper: VillageNPC) -> Vector3:
	return barkeeper.work_point + Basis(Vector3.UP, barkeeper.work_yaw) * BAR_TARGET

func target_distance(point: Vector3, door: TavernDoor = null, ladder := false, actor: VillageNPC = null) -> float:
	var offset := point - camera.global_position
	var distance := offset.length()
	if distance > REACH or distance < 0.01 or (-camera.global_basis.z).dot(offset / distance) < TARGET_DOT:
		return INF
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, point)
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var hit_at: Vector3 = hit.position
		if hit.collider != door and hit.collider != actor and hit_at.distance_to(point) > (0.45 if ladder else 0.2):
			return INF
	return distance

func _input(event: InputEvent) -> void:
	if not InputActions.pressed(event, "interact") or event.is_echo() or not camera.current:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if act():
		get_viewport().set_input_as_handled()

## What E does now: the hold, standing up from a seat, or the target
## choose() picked. False when there is nothing to do.
func act() -> bool:
	var hold := _hold()
	if hold != null:
		hold.act.call()
	elif not seated.is_empty():
		stand()
	elif _chosen != null:
		_chosen.act.call()
	else:
		return false
	return true

func sit(seat: Dictionary) -> void:
	if climbing or not seated.is_empty():
		return
	if seat.get("camp", false) and camping.seat_occupied(seat):
		return
	if valley != null and valley.presence != null and valley.presence.seat_taken(seat):
		return
	seated = seat
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	(player.get_node("Collision") as CollisionShape3D).disabled = true
	player.global_position = Values.vec3(seat.position)
	player.rig.position.y = Values.real(seat.height) + 0.74
	var direction := Values.vec3(seat.facing)
	player.rig.yaw_deg = rad_to_deg(atan2(-direction.x, -direction.z))
	player.rig.pitch_deg = -8.0
	player.rig.apply_look(Vector2.ZERO)

## The innkeeper is out and has left a jug on the counter: the mug is filled
## from it, with the beer of the keg on the counter when one stands there.
func pour_from_jug() -> void:
	player.viewmodel.refill(BrewHouse.draw_beer(get_tree()))
	if camping != null:
		camping.say(null, "Хозяин вышел, а кувшин оставил на стойке.")

func stand() -> bool:
	if seated.is_empty():
		return true
	var candidates: Array[Vector3] = []
	for exit: Array in seated.exits:
		candidates.append(Values.vec3(exit))
	var origin := Values.vec3(seated.position)
	for radius: float in [0.8, 1.0, 1.25]:
		for index in range(16):
			var angle := float(index) * TAU / 16.0
			candidates.append(origin + Vector3(cos(angle), 0, sin(angle)) * radius)
	for point: Vector3 in candidates:
		if can_stand(point):
			player.global_position = point + Vector3.UP * 0.015
			seated = {}
			restore_player()
			return true
	prompt.text = "Нет места, чтобы встать. Освободите проход."
	return false

func can_stand(point: Vector3) -> bool:
	var space := player.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.25, point - Vector3.UP * 0.35)
	ray.exclude = [player.get_rid()]
	var floor_hit := space.intersect_ray(ray)
	if floor_hit.is_empty() or floor_hit.normal.y < 0.7 or absf(Values.real(floor_hit.position.y - point.y)) > 0.15:
		return false
	if valley != null and valley.presence != null and valley.presence.sits_near(point):
		return false
	var shape := player.get_node("Collision") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape.shape
	query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 0.89)
	query.exclude = [player.get_rid()]
	return space.intersect_shape(query, 1).is_empty()

func climb() -> bool:
	if climbing or not seated.is_empty():
		return false
	var up := player.global_position.y < 13.0
	var target := LADDER_TOP if up else Vector3(9.25, 10.86, -7.3)
	if not can_stand(target):
		prompt.text = "Выход с лестницы занят"
		return false
	climbing = true
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	(player.get_node("Collision") as CollisionShape3D).disabled = true
	player.rig.yaw_deg = 0.0 if up else 180.0
	player.rig.pitch_deg = 12.0 if up else -25.0
	player.rig.apply_look(Vector2.ZERO)
	var tween := create_tween()
	_climb_tween = tween
	# Follow the existing ladder through its hatch, then step clear of it.
	var approach := LADDER_BOTTOM if up else Vector3(9.25, 14.89, -7.70)
	var rim := Vector3(9.25, 14.89, -7.70) if up else LADDER_BOTTOM
	tween.tween_property(player, "global_position", approach, 0.4)
	tween.tween_property(player, "global_position", rim, 3.0)
	tween.tween_property(player, "global_position", target + Vector3.UP * 0.015, 0.65)
	await tween.finished
	climbing = false
	_climb_tween = null
	restore_player()
	return true

func restore_player() -> void:
	player.rig.position.y = _standing_eye
	player.velocity = Vector3.ZERO
	(player.get_node("Collision") as CollisionShape3D).disabled = false
	player.set_physics_process(true)

func reset() -> void:
	if _climb_tween != null:
		_climb_tween.kill()
		_climb_tween = null
	climbing = false
	seated = {}
	released.emit()
	restore_player()
