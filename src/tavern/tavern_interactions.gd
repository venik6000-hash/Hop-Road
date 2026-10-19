class_name TavernInteractions
extends Node
## Contextual E leaves the mug action available when no furnishing is targeted.
##
## Targets come from sources (add_source): each is asked in turn for its nearest
## target within the best distance found so far, and the nearest of all wins.
## The innkeeper is a source of this node; every node of Interaction.GROUP in
## the tree (a door, a work handle) is one by itself; the camping and the boat
## (LakesideSystem) add theirs, and the content's givers (`givers`: the
## tavern's furnishings, TavernFurnishings, and the brewery) add theirs when
## both stand. A source or a hold goes when the node it is of leaves the
## tree, the content's seats with their furnishings (drop_seats). Before the targets come the holds (add_hold): states that take
## E whole, each with its own prompt (the ladder climbed, the boat under way,
## a fire being laid, a brewery's station), then the seat the player sits on.
## A new kind of target or hold adds a source or a hold, not a branch here.

## The player is taken out of whatever held them (reset): a hold lets go.
signal released

const REACH := 2.4
const TARGET_DOT := 0.93
## Where the innkeeper is looked at, from his feet (VillageNPC.interaction_point):
## the jug he leaves on the counter is looked at there.
const BAR_TARGET := Vector3(0.0, 1.3, -0.6)
## The prompt of a seat sat on.
const STAND_HINT := "{interact} — встать   ·   {look} — обзор"
var player: Player
var population: NpcPopulation
## The content's sources of E (WorldContext.interaction_sources): each a
## Callable(TavernInteractions) that hands its targets, holds and seats here.
## Null in a tool that hands them itself.
var givers: ContentRegistry
var camping: CampSystem
## The game's day and night (the world loader's ValleyLoop); without it the
## beds are furniture.
var valley: ValleyLoop
var camera: Camera3D
var prompt: Label
## The seats of the level's buildings in the world, which the villagers take
## too; a building's source adds its own (TavernFurnishings).
var seats: Array[Dictionary] = []
## The seat the player sits on; {} when standing (the player is SEATED).
var seated: Dictionary = {}
## The thing E would act on this frame (Interaction.subject); null for none.
var selected: Variant = null
## A ladder carries the player (TavernFurnishings.climb; the player is on the
## LADDER).
var climbing := false
var _standing_eye := 1.6
## Callable(best: float) -> Interaction: the source's nearest target nearer
## than `best`, null for none. Asked in this order, then the nodes of
## Interaction.GROUP; a tie keeps the earlier.
var _sources: Array[Callable] = []
## Callable() -> Interaction: the state that takes E whole now, null when it
## does not. Asked in this order; the first that holds wins.
var _holds: Array[Callable] = []
## What E would do this frame, null for nothing.
var _chosen: Interaction
## The nodes whose sources and holds are here, heard leaving the tree.
var _heard := {}

func _ready() -> void:
	camera = player.camera
	_standing_eye = player.rig.position.y
	add_source(_bar_target)
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
	if givers != null:
		for give: Variant in givers.entries():
			_take(give)
		givers.added.connect(_take)

## A giver of the content hands its targets, holds and seats (`give`:
## Callable(TavernInteractions)).
func _take(give: Variant) -> void:
	var hand: Callable = give
	hand.call(self)

## Adds a source of targets for E: `source` is Callable(best: float) ->
## Interaction, the nearest target nearer than `best` or null. It goes when
## its node leaves the tree.
func add_source(source: Callable) -> void:
	_sources.append(source)
	_hear(source)

## Adds a state that takes E whole: `hold` is Callable() -> Interaction, its
## prompt and act while it holds, null when it does not. It goes when its
## node leaves the tree.
func add_hold(hold: Callable) -> void:
	_holds.append(hold)
	_hear(hold)

## Hears the node of `given` leave the tree.
func _hear(given: Callable) -> void:
	var node := given.get_object() as Node
	if node == null or node == self or _heard.has(node):
		return
	_heard[node] = true
	node.tree_exiting.connect(_drop_node.bind(node), CONNECT_ONE_SHOT)

## Drops the sources and holds of `node`, which leaves the tree.
func _drop_node(node: Node) -> void:
	_heard.erase(node)
	_sources = _sources.filter(func(source: Callable) -> bool: return source.get_object() != node)
	_holds = _holds.filter(func(hold: Callable) -> bool: return hold.get_object() != node)
	selected = null
	_chosen = null

## Drops the seats `given` (TavernFurnishings, as it leaves the tree); the
## player stands up from one of them, or leaves the ladder when `holding`.
func drop_seats(given: Array[Dictionary], holding: bool) -> void:
	var kept: Array[Dictionary] = []
	var sat := false
	for seat: Dictionary in seats:
		var mine := false
		for other: Dictionary in given:
			mine = mine or is_same(seat, other)
		if not mine:
			kept.append(seat)
		elif is_same(seat, seated):
			sat = true
	seats = kept
	if sat or (holding and climbing):
		reset()
	selected = null
	_chosen = null

## How many sources of targets E asks now: the added ones and the nodes of
## Interaction.GROUP.
func source_count() -> int:
	return _sources.size() + (get_tree().get_nodes_in_group(Interaction.GROUP).size() if is_inside_tree() else 0)

## The hold that has E now, null for none.
func _hold() -> Interaction:
	for hold: Callable in _holds:
		var held: Interaction = hold.call()
		if held != null:
			return held
	return null

func _process(_delta: float) -> void:
	selected = null
	_chosen = null
	prompt.text = InputActions.hint(tr(_prompt_text()))

## What the prompt says in this frame: a key of the table or words already
## translated, with the labels of InputActions.hint still to put in; picks
## `_chosen` and `selected`.
func _prompt_text() -> String:
	if not camera.current or not InputActions.live(&"interact"):
		return ""
	return choose()

## Picks `_chosen` and `selected` where the eye looks and returns the prompt's
## words, as each frame does while E is the game's (InputActions.live). A
## tool calls it and act() itself.
func choose() -> String:
	if player.mode == Player.SLEEP:
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
	if is_inside_tree():
		for node: Node in get_tree().get_nodes_in_group(Interaction.GROUP):
			var found: Interaction = node.call(&"interaction", best, self)
			if found != null and found.distance < best:
				best = found.distance
				_chosen = found
	if _chosen == null:
		return ""
	selected = _chosen.subject
	return str(_chosen.describe.call())

## A villager as a target: one at work whose job has E (NpcJob.interaction_text,
## the innkeeper's order) works it, anyone else goes by the camping (talk,
## invite for a walk).
func npc_interaction(actor: VillageNPC, distance: float) -> Interaction:
	if actor.at_work() and actor.interaction_text() != "":
		return Interaction.of(actor, distance, actor.interaction_text, actor.interact.bind(player))
	return Interaction.of(actor, distance, camping.interaction_text.bind(actor), camping.interact_npc.bind(actor))

## A seat as a target: a building's (TavernFurnishings) or one at a campfire.
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
	if not InputActions.takes(event, &"interact") or event.is_echo() or not camera.current:
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
	if player.mode != Player.WALK:
		return
	if seat.get("camp", false) and camping.seat_occupied(seat):
		return
	if valley != null and valley.presence != null and valley.presence.seat_taken(seat):
		return
	if not carry_player(Player.SEATED):
		return
	seated = seat
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
	var shape := player.collision
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape.shape
	query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 0.89)
	query.exclude = [player.get_rid()]
	return space.intersect_shape(query, 1).is_empty()

## A seat or a ladder carries the player: `mode` is Player.SEATED or
## Player.LADDER, and the body stops and lets go of the floor (Player.enter).
## False when another system owns the player's mode. restore_player gives
## the body back.
func carry_player(mode: StringName) -> bool:
	return player.enter(mode, self)

func restore_player() -> void:
	player.rig.position.y = _standing_eye
	player.leave(self)

func reset() -> void:
	climbing = false
	seated = {}
	released.emit()
	restore_player()
