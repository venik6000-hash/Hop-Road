class_name CampSystem
extends Node3D
## Camps and outings belong to the alpine level, not to the tavern interior.
## The site check, the caption UI, the villagers at rest and the signs of
## closeness live in these helpers. What the people say is in their sheets
## (PeopleBook); when they say it is the Storyteller's.
const CAMP_SITE = preload("res://src/camping/camp_site.gd")
const CAMP_HUD = preload("res://src/camping/camp_hud.gd")
const CAMP_REST = preload("res://src/camping/camp_rest.gd")
const CAMP_SIGNS = preload("res://src/camping/camp_signs.gd")
## How many villagers walk with the player at once.
const COMPANIONS := 3
## How near a person hears and is heard, and how near a companion walks "with"
## the player.
const TALK_REACH := 5.0
const WALK_REACH := 12.0
## The pace (m/s) under which the player has stopped to listen.
const STILL_SPEED := 0.6
## Seconds walked together and seconds sat beside that warm (spec 7.1).
const WALK_SECONDS := 180.0
const SIT_SECONDS := 120.0
## How near the place a companion loves the companion and the player must be
## for both to have come to it.
const PLACE_REACH := 6.0
const PLACE_PLAYER_REACH := 10.0
## Seconds between looks for a sign of closeness to show (CAMP_SIGNS.look).
const SIGNS_SECONDS := 0.5
var player: Player
var interactions: TavernInteractions
var population: NpcPopulation
## The game's day, hour, weather and zone (the world loader's ValleyLoop);
## without it the moment is ValleyLoop.STILL.
var valley: ValleyLoop
var water_level := 0.72
var memory_path := "user://camping.json"
var fires: Array[Campfire] = []
var companions: Array[NpcOuting] = []
var placing := false
var placement: Dictionary = {}
var placement_reason := ""
var held_meal: CampMeal
var held_potato: Node3D
var memories: Dictionary = {}
var ghost: Node3D
var caption: Label
var caption_panel: PanelContainer
var food_hint: Label
var _caption_time := 0.0
var _bite_time := 0.0
var _guest_clock := 0.0
var _guest_requests: Dictionary = {}
## The day and the zone of the last frame, and the seconds of this day spent
## with each villager: "<person>:<event>" -> seconds.
var _day := 0
var _zone := ""
var _together: Dictionary = {}
## The player's visits to the villagers at rest: person id -> CampVisit.
var visits: Dictionary = {}
## The innkeeper may pour the usual: the player has come up to him anew.
var usual_due := true
var _signs_clock := 0.0
# player's CameraRig/Camera3D, looked up on first use (see _player_camera).
var _camera: Node
var _camera_owner: Node
## Query resources are reused, but collision results are never cached.
var _site_ground_query := PhysicsRayQueryParameters3D.new()
var _site_roof_query := PhysicsRayQueryParameters3D.new()
var _site_clearance_query := PhysicsShapeQueryParameters3D.new()
var _preview_query := PhysicsRayQueryParameters3D.new()
var _preview_tint := Color(-1, -1, -1, -1)

func _ready() -> void:
	CAMP_HUD.build(self)
	ghost = Node3D.new()
	ghost.name = "CampPlacementPreview"
	add_child(ghost)
	for index in range(11):
		var angle := TAU * index / 11.0
		CampProps.stone(ghost, Vector3(cos(angle) * 0.57, 0.10, sin(angle) * 0.57), Vector3(0.28, 0.18, 0.23), index)
	CampProps.log_mesh(ghost, Vector3.UP * 0.15, 0.84, 0.075, 0.6)
	ghost.visible = false
	_load_memory.call_deferred()
	player.viewmodel.sipped.connect(_sipped)

func _process(delta: float) -> void:
	var active: bool = _player_camera().current and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_caption_time = maxf(0.0, _caption_time - delta)
	caption_panel.visible = active and _caption_time > 0
	caption_panel.modulate.a = minf(1.0, _caption_time)
	food_hint.visible = active and holding_food()
	var hint := "Печёная картошка · F — съесть половину · Q — поделиться · V — пиво" if holding_food() else ""
	if food_hint.text != hint:
		food_hint.text = hint
	if placing:
		ghost.visible = active
		if active:
			_update_preview()
	else:
		ghost.visible = false
	if held_potato != null:
		held_potato.visible = active and holding_food() and not player.viewmodel.drinking()
		_bite_time = maxf(0.0, _bite_time - delta)
		held_potato.position = Vector3(-0.19, -0.20 + sin(_bite_time * PI / 0.65) * 0.10, -0.46)
	_guest_clock += delta
	if _guest_clock > 3.0 and active:
		_guest_clock = 0.0
		_check_passersby()
	if active:
		_keep_company(delta)
		_signs_clock += delta
		if _signs_clock >= SIGNS_SECONDS:
			_signs_clock = 0.0
			CAMP_SIGNS.look(self)

## The node at player's "CameraRig/Camera3D", as get_node() would return it.
## Looked up lazily: the player and its script can be set after _ready (tools
## swap in tools/lib/background_player.gd), and again when the node is replaced.
func _player_camera() -> Node:
	if _camera_owner != player or not is_instance_valid(_camera) or _camera.get_parent() == null \
			or _camera.get_parent().get_parent() != player:
		_camera = player.get_node("CameraRig/Camera3D")
		_camera_owner = player
	return _camera

func _input(event: InputEvent) -> void:
	if not _player_camera().current or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or event.is_echo():
		return
	if event.is_action_pressed("place_camp"):
		if interactions.climbing or not interactions.seated.is_empty():
			say(null, "Сначала встань на тропу, чтобы выбрать место для костра.")
		else:
			placing = not placing
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("eat_potato") and holding_food():
		eat()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camp_secondary"):
		var actor := targeted_companion()
		if holding_food():
			share()
		elif interactions.selected is Campfire:
			(interactions.selected as Campfire).set_burning(false)
		elif actor != null:
			dismiss(actor)
		else:
			return
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("guide_outing"):
		var actor := targeted_companion()
		if actor == null:
			actor = nearest_companion(3.5)
		if actor == null:
			return
		if favorite_path(actor).is_empty():
			say(actor, line_of(actor, "guide_none"))
		else:
			(actor.outing as NpcOuting).guide()
			say(actor, line_of(actor, "guide"))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camp_refill"):
		if nearby_fire(player.global_position, 3.0) != null and not player.viewmodel.drinking():
			player.viewmodel.refill()
			say(null, "Дорожный кувшин ещё полон. Нальём по кружке.")
			get_viewport().set_input_as_handled()

func ground_at(point: Vector3, above := 2.0, below := 5.0) -> Dictionary:
	return CAMP_SITE.ground_at(self, point, above, below)

func check_site(point: Vector3, restoring := false) -> Dictionary:
	return CAMP_SITE.check_site(self, point, restoring)

func _update_preview() -> void:
	var camera := _player_camera() as Camera3D
	_preview_query.from = camera.global_position
	_preview_query.to = camera.global_position - camera.global_basis.z * 5.0
	_preview_query.collision_mask = 1
	_preview_query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(_preview_query)
	placement = {}
	if hit.is_empty():
		placement_reason = "Посмотри на землю в нескольких шагах от себя"
		ghost.visible = false
		return
	placement = check_site(hit.position)
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

func placement_text() -> String:
	if placement.has("position"):
		return "E — положить дрова здесь · K — отменить"
	return placement_reason + " · K — отменить"

func confirm_placement() -> bool:
	# Recheck at the moment of the action: an NPC may have walked into the spot.
	_update_preview()
	if not placement.has("position"):
		return false
	_create_fire(placement)
	placing = false
	_save_memory()
	say(null, "Дрова уложены. Разожги костёр и выбирай полено поудобнее.")
	return true

func _create_fire(site: Dictionary) -> Campfire:
	var fire := Campfire.new()
	fire.name = "Campfire" + str(fires.size())
	fire.position = site.position
	fire.seats.assign(site.seats)
	add_child(fire)
	fires.append(fire)
	return fire

func find_target(best: float) -> Dictionary:
	var result: Dictionary = {}
	for actor in population.actors:
		if not CAMP_REST.approachable(self, actor):
			continue
		var distance := interactions.target_distance(actor.global_position + Vector3.UP * 1.15, null, false, actor)
		if distance < best:
			best = distance
			result = {"distance": best, "target": actor}
	for fire in fires:
		var distance := interactions.target_distance(fire.global_position + Vector3.UP * 0.45, null, true)
		if distance < best:
			best = distance
			result = {"distance": best, "target": fire}
		for seat: Dictionary in fire.seats:
			if seat_occupied(seat):
				continue
			distance = interactions.target_distance(TavernInteractions.vector(seat.position) + Vector3.UP * 0.5, null, true)
			if distance < best:
				best = distance
				result = {"distance": best, "target": seat}
	return result

func interaction_text(actor: VillageNPC) -> String:
	if actor.outing != null:
		return "E — поговорить · Q — попрощаться · G — любимое место"
	if actor.invitable():
		return "E — позвать гулять · " + actor.title
	return "E — поговорить · " + actor.title

func interact_npc(actor: VillageNPC) -> void:
	if actor.outing != null or not actor.invitable():
		talk(actor)
		return
	if companions.size() >= COMPANIONS:
		say(actor, line_of(actor, "company_full"))
		return
	take_along(actor)
	var again: bool = _memory(actor).get("shared", 0) > 0
	say(actor, line_of(actor, "accept_again" if again and circle_of(actor) < CAMP_SIGNS.NEAR_CIRCLE else "accept"))

## The villager sets out with the player as a companion.
func take_along(actor: VillageNPC) -> void:
	if valley != null and valley.presence != null:
		valley.presence.release(actor)
	var outing := NpcOuting.new()
	outing.actor = actor
	outing.camping = self
	outing.teller = population.people.teller(actor.person_id)
	if outing.teller == null:
		outing.teller = population.people.passerby()
	outing.teller.begin_outing()
	actor.outing = outing
	actor.add_child(outing)
	companions.append(outing)

func interact_fire(fire: Campfire) -> void:
	if not fire.burning:
		fire.set_burning(true)
		say(null, "Огонь занялся. Картошку можно положить прямо в угли.")
	elif fire.meal.ready():
		if holding_food() or not fire.meal.take():
			return
		held_meal = fire.meal
		if held_potato != null:
			held_potato.queue_free()
		held_potato = CampProps.potato(true)
		held_potato.scale = Vector3.ONE * 0.70
		player.get_node("CameraRig/Camera3D").add_child(held_potato)
		for mesh in held_potato.find_children("*", "MeshInstance3D", true, false):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var material := mesh.material_override as StandardMaterial3D
			material.no_depth_test = true
			material.render_priority = 2
		say(null, "Горячая картошка, щепотка соли. Можно разломить и угостить спутника.")
	elif not holding_food() and fire.meal.put_in_coals():
		say(null, "Картошка в углях. Устройся рядом — есть время поговорить.")
	_save_memory()

func holding_food() -> bool:
	return held_meal != null and held_meal.portions > 0

func eat() -> bool:
	if not holding_food() or _bite_time > 0 or not held_meal.consume():
		return false
	_bite_time = 0.65
	say(null, "Под хрустящей кожурой — горячая мягкая картошка. Хороший вечер.")
	return true

## Half of the potato goes to the nearest companion, else to the nearest
## villager at rest.
func share() -> bool:
	if not holding_food() or _bite_time > 0:
		return false
	var companion := nearest_companion(3.6)
	var actor: VillageNPC = companion if companion != null else nearest_at_rest(3.0)
	if actor == null:
		say(null, "Подойди к спутнику поближе, чтобы поделиться картошкой.")
		return false
	if not held_meal.consume():
		return false
	if companion != null:
		(companion.outing as NpcOuting).toast()
		(companion.outing as NpcOuting).receive_food()
	fed(actor, "potato")
	return true

## The nearest villager at rest within `reach` of the player, null for none.
func nearest_at_rest(reach: float) -> VillageNPC:
	return CAMP_REST.nearest(self, reach)

## A villager was treated to `food` ("potato" or "fish"): they remember it,
## warm to it — more to the food they love — and say their thanks.
func fed(actor: VillageNPC, food: String) -> void:
	var known := _memory(actor)
	known["shared"] = int(known.get("shared", 0)) + 1
	memories[actor.name] = known
	var loved := population.people.sheet(actor.person_id).favorite_food == food
	warm(actor, "food", Acquaintance.FAVORITE_FOOD if loved else -1)
	say(actor, line_of(actor, "food_" + food))
	_save_memory()

## A cook was brought a raw catch.
func brought_catch(actor: VillageNPC) -> void:
	warm(actor, "catch")
	say(actor, line_of(actor, "catch"))

func _memory(actor: VillageNPC) -> Dictionary:
	return memories.get(actor.name, {})

func say(actor: VillageNPC, words: String) -> void:
	if words.is_empty():
		return
	caption.text = words if actor == null else actor.title + ":  " + words
	_caption_time = Storyteller.caption_seconds(words)

## What the person says for `key` at the circle the player has reached with
## them: their own line, else the common one.
func line_of(actor: VillageNPC, key: String) -> String:
	return population.people.line_at(actor.person_id, key)

## The circle the player has reached with the villager; 0 with a passer-by.
func circle_of(actor: VillageNPC) -> int:
	var bond := population.people.bond(actor.person_id)
	return bond.circle if bond != null else 0

## Counts an event of the spec's table (7.1) for a villager, once a game day,
## and opens the next circle when the warmth has reached it. A passer-by
## without a sheet keeps no warmth.
func warm(actor: VillageNPC, event: String, amount := -1) -> void:
	var bond := population.people.bond(actor.person_id)
	if bond == null:
		return
	var today := _today()
	if bond.note(event, today, amount) > 0:
		bond.settle(today)
		_changed()

## The player asked a companion or a villager at rest to talk (E on them).
func talk(actor: VillageNPC) -> void:
	var teller := teller_of(actor)
	if teller == null:
		return
	var speaker := _telling()
	_voice(actor, teller.ask(moment_of(actor), speaker == null or speaker == teller))

## The villager's voice: the outing's for a companion, their own otherwise;
## null for a passer-by who is not one.
func teller_of(actor: VillageNPC) -> Storyteller:
	if actor.outing != null:
		return (actor.outing as NpcOuting).teller
	return population.people.teller(actor.person_id)

## The moment as the villager's storyteller takes it (Storyteller).
func moment_of(actor: VillageNPC) -> Dictionary:
	if actor.outing != null:
		return _moment_for(actor.outing as NpcOuting)
	return CAMP_REST.moment(self, actor)

## The way to the place the person loves, as [x, z] points from their road.
func favorite_path(actor: VillageNPC) -> Array[Vector2]:
	return population.people.sheet(actor.person_id).favorite_path

## Whether the companion and the player stand at the place the companion loves.
func at_favorite(actor: VillageNPC) -> bool:
	var path := favorite_path(actor)
	if path.is_empty():
		return false
	var place := path[path.size() - 1]
	return Vector2(actor.global_position.x, actor.global_position.z).distance_to(place) < PLACE_REACH \
		and Vector2(player.global_position.x, player.global_position.z).distance_to(place) < PLACE_PLAYER_REACH

## The companion and the player have come to the place the companion loves,
## led there or not: once an outing.
func reach_favorite(outing: NpcOuting) -> void:
	outing.reached_favorite = true
	warm(outing.actor, "favorite_place")
	say(outing.actor, line_of(outing.actor, "favorite"))

func targeted_companion() -> VillageNPC:
	if interactions.selected is VillageNPC:
		var actor := interactions.selected as VillageNPC
		if actor.outing != null and actor.outing.mode != "return":
			return actor
	return null

func nearest_companion(reach: float) -> VillageNPC:
	var closest: VillageNPC
	for outing in companions:
		if not is_instance_valid(outing) or outing.mode == "return":
			continue
		var distance := player.global_position.distance_to(outing.actor.global_position)
		if distance < reach and sees(outing.actor):
			reach = distance
			closest = outing.actor
	return closest

## Whether nothing solid stands between the player and the villager, `height`
## over the feet of each: at the waist a counter or a table is in the way, at
## the eyes it is not.
func sees(actor: VillageNPC, height := 0.65) -> bool:
	var query := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * height,
		actor.global_position + Vector3.UP * height, 1)
	query.exclude = [player.get_rid(), actor.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func dismiss(actor: VillageNPC) -> void:
	var outing := actor.outing as NpcOuting
	companions.erase(outing)
	outing.dismiss()
	say(actor, line_of(actor, "farewell"))

## A villager who set out for the fire by themselves and found no way to it
## goes back as they came, without a farewell.
func turn_back(actor: VillageNPC) -> void:
	var outing := actor.outing as NpcOuting
	companions.erase(outing)
	outing.dismiss()

func nearby_fire(point: Vector3, reach: float) -> Campfire:
	var closest: Campfire
	for fire in fires:
		var distance := point.distance_to(fire.global_position)
		if fire.burning and distance < reach:
			reach = distance
			closest = fire
	return closest

func seat_occupied(seat: Dictionary) -> bool:
	if interactions.seated == seat:
		return true
	for outing in companions:
		if is_instance_valid(outing) and outing.camp_seat == seat:
			return true
	return false

## The free seat by the fire the companion takes: the nearest to them, and
## for one who is near enough to the player, the nearest to the player.
func companion_seat(fire: Campfire, actor: VillageNPC) -> Dictionary:
	var from: Vector3 = player.global_position if circle_of(actor) >= CAMP_SIGNS.NEAR_CIRCLE else actor.global_position
	var best := INF
	var result: Dictionary = {}
	for seat: Dictionary in fire.seats:
		var at := TavernInteractions.vector(seat.position)
		if seat_occupied(seat) or at.distance_to(player.global_position) < 0.9:
			continue
		var distance := at.distance_to(from)
		if distance < best:
			best = distance
			result = seat
	return result

func arrive_at_fire(outing: NpcOuting) -> void:
	var actor := outing.actor
	var known := _memory(actor)
	var key := _fire_key(outing.fire)
	var familiar: bool = known.get("camp", "") == key
	known["camp"] = key
	memories[actor.name] = known
	if familiar:
		warm(actor, "old_camp")
	var words := line_of(actor, "fire_old" if familiar else "fire_new")
	if CAMP_SIGNS.treat(self, outing) and not line_of(actor, "treat").is_empty():
		words = line_of(actor, "treat")
	say(actor, words)
	_save_memory()

func seated_text() -> String:
	if not interactions.seated.get("camp", false):
		return ""
	return " · V — пиво · X — налить" + (" · F — есть · Q — поделиться" if holding_food() else "")

## The player took a sip. Companions resting near raise their mugs, and it is
## a toast with the villagers at rest the player sits or stands at the bar
## with; the one telling a story, or else the nearest companion, or else the
## nearest villager visited, goes on with their story by a beat; when there is
## no story to move, the toast is said aloud.
func _sipped() -> void:
	var toasted: VillageNPC
	for outing in companions:
		if is_instance_valid(outing) and outing.mode == "rest" and player.global_position.distance_to(outing.actor.global_position) < 4.0:
			outing.toast()
			warm(outing.actor, "toast")
			if toasted == null:
				toasted = outing.actor
	var host: VillageNPC = CAMP_REST.toast(self)
	if toasted == null:
		toasted = host
	var speaker := _storyteller()
	if speaker == null:
		speaker = nearest_companion(TALK_REACH)
	if speaker == null:
		speaker = CAMP_REST.nearest_visited(self)
	if speaker != null and _voice(speaker, teller_of(speaker).sip(moment_of(speaker), true)):
		return
	if toasted != null and _caption_time <= 0:
		say(toasted, line_of(toasted, "toast"))

## Keeps the company the player is in: counts the time walked and sat
## together, notices the place a companion loves, and lets each companion and
## each villager at rest the player has come up to speak when it is their turn.
func _keep_company(delta: float) -> void:
	var today := _today()
	if today != _day:
		_day = today
		_together.clear()
		# A circle the day's rule held back opens with the new day.
		for id: String in population.people.bonds:
			if population.people.bond(id).settle(today):
				_changed()
	var zone := valley.zone if valley != null else ""
	var moved := zone != _zone
	_zone = zone
	var speaker := _telling()
	for outing in companions:
		if not is_instance_valid(outing) or outing.mode == "return":
			continue
		# Another zone is another halt.
		if moved:
			outing.halt += 1
		var actor := outing.actor
		var near := player.global_position.distance_to(actor.global_position)
		if outing.mode == "rest":
			if near < TALK_REACH and interactions.seated.get("camp", false):
				_spend(actor, "sit", delta, SIT_SECONDS)
		elif near < WALK_REACH:
			_spend(actor, "walk", delta, WALK_SECONDS)
		if not outing.reached_favorite and at_favorite(actor):
			reach_favorite(outing)
		_voice(actor, outing.teller.advance(delta, _moment_for(outing), speaker == null or speaker == outing.teller,
			_caption_time <= 0.0 and near <= TALK_REACH))
	CAMP_REST.keep(self, delta, speaker)

## Adds `delta` to the seconds of today spent in `event` with the villager;
## the event counts when they come to `enough`.
func _spend(actor: VillageNPC, event: String, delta: float, enough: float) -> void:
	if not population.people.knows(actor.person_id):
		return
	var key := actor.person_id + ":" + event
	var before: float = _together.get(key, 0.0)
	_together[key] = before + delta
	if before < enough and before + delta >= enough:
		warm(actor, event)

## The moment as the companion's storyteller takes it (Storyteller).
func _moment_for(outing: NpcOuting) -> Dictionary:
	var now: Dictionary = valley.moment() if valley != null else ValleyLoop.STILL.duplicate()
	var by_fire := outing.mode == "rest"
	var still := player_still()
	var bond := population.people.bond(outing.actor.person_id)
	now["activity"] = "fire" if by_fire else ("table" if at_table() else ("stand" if still else "walk"))
	now["listening"] = (by_fire or still) and player.global_position.distance_to(outing.actor.global_position) <= TALK_REACH
	now["halt"] = outing.halt
	now["company"] = CAMP_REST.company(self, outing.actor)
	now["gift"] = bond.gift(_today()) if bond != null else ""
	now["can_guide"] = not favorite_path(outing.actor).is_empty() and not outing.reached_favorite and outing.mode != "guide"
	return now

## Whether the player has stopped: stands, or sits.
func player_still() -> bool:
	return Vector2(player.velocity.x, player.velocity.z).length() < STILL_SPEED

## Whether the player sits on a seat of the tavern, not on a log by a fire.
func at_table() -> bool:
	var camp_seat: bool = interactions.seated.get("camp", false)
	return not interactions.seated.is_empty() and not camp_seat

## The storyteller who is telling a story now, null when nobody is.
func _telling() -> Storyteller:
	var actor := _storyteller()
	return teller_of(actor) if actor != null else null

## The villager who is telling a story now, a companion or one at rest; null
## when nobody is.
func _storyteller() -> VillageNPC:
	for outing in companions:
		if is_instance_valid(outing) and outing.mode != "return" and not outing.teller.telling.is_empty():
			return outing.actor
	for actor in population.actors:
		if actor.outing == null and population.people.knows(actor.person_id) \
				and not population.people.teller(actor.person_id).telling.is_empty():
			return actor
	return null

## Shows a storyteller's line; false when there is none. A beat of a shared
## story (PersonSheet) is said by the one of the two whose it is, and the
## story heard to the end warms the other teller as well.
func _voice(actor: VillageNPC, line: Dictionary) -> bool:
	if line.is_empty():
		return false
	var by: String = line.get("by", "")
	var voice := actor
	if not by.is_empty() and by != actor.person_id:
		# The second teller speaks while they are beside the first; a beat of
		# one who has gone is the first teller's to say.
		var other := population.actor_of(by)
		if other != null and other.present() \
				and other.global_position.distance_to(actor.global_position) <= CAMP_REST.COMPANY_REACH:
			voice = other
	say(voice, line.text)
	if line.kind == "beat" or line.kind == "hook_after":
		# The story's last beat ends the telling as it is said: one who walks
		# about their work stays for its caption, and until the hook that
		# follows it has been said.
		var words: String = line.text
		actor.stop_to_talk(player.global_position, 0.0,
			Storyteller.caption_seconds(words) + Storyteller.NEXT_PAUSE + VillageNPC.TALK_HOLD)
	if line.kind == "introduce":
		# From now on the person goes by the name.
		population.refresh_titles()
	var partner: String = line.get("with", "")
	var last: bool = line.get("last", false)
	if last:
		# The story has warmed its teller (Acquaintance.finish): the circle it
		# has reached opens now.
		var bond := population.people.bond(actor.person_id)
		if bond != null:
			bond.settle(_today())
		if not partner.is_empty() and population.actor_of(partner) != null:
			warm(population.actor_of(partner), "story")
	_changed()
	return true

func _today() -> int:
	return valley.day if valley != null else 1

## What the player has with the villagers has changed: it is saved soon.
func _changed() -> void:
	if valley != null:
		valley.save_soon()

func _check_passersby() -> void:
	var fire := nearby_fire(player.global_position, 4.0)
	if fire == null or _caption_time > 0 or CAMP_SIGNS.join_fire(self, fire):
		return
	for actor in population.actors:
		var key := actor.name + _fire_key(fire)
		if actor.present() and actor.on_road() and actor.global_position.distance_to(fire.global_position) < 4.5 and not _guest_requests.has(key):
			_guest_requests[key] = true
			actor._wait = 8.0
			say(actor, line_of(actor, "warm_by_fire"))
			return

func _fire_key(fire: Campfire) -> String:
	return "%d:%d" % [roundi(fire.position.x), roundi(fire.position.z)]

func cancel_placement() -> void:
	placing = false
	ghost.visible = false

func fast_travel() -> void:
	cancel_placement()
	for outing in companions.duplicate():
		if is_instance_valid(outing):
			dismiss(outing.actor)

func _save_memory() -> void:
	if memory_path.is_empty():
		return
	var sites: Array = []
	for fire in fires:
		sites.append([fire.position.x, fire.position.y, fire.position.z])
	var file := FileAccess.open(memory_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"version": 1, "memories": memories, "sites": sites}))

func _load_memory() -> void:
	if memory_path.is_empty() or not FileAccess.file_exists(memory_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(memory_path))
	if not data is Dictionary or data.get("version") != 1:
		return
	if data.get("memories") is Dictionary:
		memories = data.memories
	await get_tree().physics_frame
	for values in data.get("sites", []):
		if not values is Array or values.size() != 3:
			continue
		var point := TavernInteractions.vector(values)
		if not point.is_finite():
			continue
		var site := check_site(point, true)
		if site.has("position"):
			_create_fire(site)
