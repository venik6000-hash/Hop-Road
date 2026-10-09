class_name CampSystem
extends Node3D
## Camps and outings belong to the alpine level, not to the tavern interior.
## The site check, the caption UI and the talk lines live in these helpers.
const CAMP_SITE = preload("res://src/camping/camp_site.gd")
const CAMP_HUD = preload("res://src/camping/camp_hud.gd")
const CAMP_DIALOGUE = preload("res://src/camping/camp_dialogue.gd")
var player: Player
var interactions: TavernInteractions
var population: NpcPopulation
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
var _talk_indices: Dictionary = {}
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
	player.viewmodel.sipped.connect(_shared_toast)

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
		var outing := actor.outing as NpcOuting
		outing.guide()
		say(actor, "Пойдём, покажу место, где люблю смотреть на долину. Не спеши — я подожду.")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camp_talk"):
		var actor := nearest_companion(4.0)
		if actor != null:
			talk(actor)
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
		if actor.job != "wander" or (actor.outing != null and actor.outing.mode == "return"):
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
	if actor.outing == null:
		return "E — позвать гулять · " + actor.title
	return "E — поговорить · Q — попрощаться · G — любимое место"

func interact_npc(actor: VillageNPC) -> void:
	if actor.outing != null:
		talk(actor)
		return
	var outing := NpcOuting.new()
	outing.actor = actor
	outing.camping = self
	actor.outing = outing
	actor.add_child(outing)
	companions.append(outing)
	var known := _memory(actor)
	say(actor, "Пойдём. Может, снова испечём картошку?" if known.get("shared", 0) > 0 else "Прогуляемся? Давно хотелось выбраться к воде. Веди, я с тобой.")

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

func share() -> bool:
	var actor := nearest_companion(3.6)
	if not holding_food() or _bite_time > 0:
		return false
	if actor == null:
		say(null, "Подойди к спутнику поближе, чтобы поделиться картошкой.")
		return false
	if not held_meal.consume():
		return false
	var known := _memory(actor)
	known["shared"] = int(known.get("shared", 0)) + 1
	memories[actor.name] = known
	(actor.outing as NpcOuting).toast()
	(actor.outing as NpcOuting).receive_food()
	say(actor, "Спасибо. В следующий раз хлеб за мной. Запомню этот привал.")
	_save_memory()
	return true

func _memory(actor: VillageNPC) -> Dictionary:
	return memories.get(actor.name, {})

func say(actor: VillageNPC, line: String) -> void:
	caption.text = line if actor == null else actor.title + ":  " + line
	_caption_time = maxf(5.0, float(line.length()) / 14.0)

func talk(actor: VillageNPC) -> void:
	var outing := actor.outing as NpcOuting
	if outing == null:
		return
	var lines := CAMP_DIALOGUE.talk_lines(actor, outing)
	var index: int = _talk_indices.get(actor.name, 0)
	_talk_indices[actor.name] = index + 1
	say(actor, lines[index % lines.size()])
	outing._remark = 32.0

func companion_remark(outing: NpcOuting) -> void:
	if _caption_time > 0 or outing.actor.global_position.distance_to(player.global_position) > 5.0:
		return
	talk(outing.actor)

func favorite_index(actor: VillageNPC) -> int:
	return CAMP_DIALOGUE.favorite_index(actor)

func favorite_line(actor: VillageNPC) -> String:
	return CAMP_DIALOGUE.favorite_line(actor)

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
		if distance < reach:
			var query := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 0.65,
				outing.actor.global_position + Vector3.UP * 0.65, 1)
			query.exclude = [player.get_rid(), outing.actor.get_rid()]
			if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
				reach = distance
				closest = outing.actor
	return closest

func dismiss(actor: VillageNPC) -> void:
	var outing := actor.outing as NpcOuting
	companions.erase(outing)
	outing.dismiss()
	say(actor, "Спасибо за компанию. Возвращайся, ещё посидим.")

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

func companion_seat(fire: Campfire, actor: VillageNPC) -> Dictionary:
	var best := INF
	var result: Dictionary = {}
	for seat: Dictionary in fire.seats:
		var at := TavernInteractions.vector(seat.position)
		if seat_occupied(seat) or at.distance_to(player.global_position) < 0.9:
			continue
		var distance := at.distance_to(actor.global_position)
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
	say(actor, "Наше место. Здесь уже всё как дома." if familiar else "Хорошее место выбрал. Я тоже присяду. За этот вечер!")
	_save_memory()

func seated_text() -> String:
	if not interactions.seated.get("camp", false):
		return ""
	return " · V — пиво · X — налить · T — разговор" + (" · F — есть · Q — поделиться" if holding_food() else "")

func _shared_toast() -> void:
	for outing in companions:
		if is_instance_valid(outing) and outing.mode == "rest" and player.global_position.distance_to(outing.actor.global_position) < 4.0:
			outing.toast()
			if _caption_time <= 0:
				say(outing.actor, "За хорошую дорогу и добрую компанию.")

func _check_passersby() -> void:
	var fire := nearby_fire(player.global_position, 4.0)
	if fire == null or _caption_time > 0:
		return
	for actor in population.actors:
		var key := actor.name + _fire_key(fire)
		if actor.job == "wander" and actor.outing == null and actor.global_position.distance_to(fire.global_position) < 4.5 and not _guest_requests.has(key):
			_guest_requests[key] = true
			actor._wait = 8.0
			say(actor, "Можно погреться рядом? Позови, если не помешаю. (E — пригласить)")
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
