class_name TavernInteractions
extends Node
## Contextual E leaves the mug action available when no furnishing is targeted.
const REACH := 2.4
const TARGET_DOT := 0.93
const SEAT_TARGET_HEIGHT := 1.05
const LADDER_BOTTOM := Vector3(9.25, 10.86, -7.72)
const LADDER_TOP := Vector3(9.25, 14.875, -8.65)
var player: Player
var tavern: TavernSystem
var population: NpcPopulation
var camping: CampSystem
var lakeside: LakesideSystem
var camera: Camera3D
var prompt: Label
var seats: Array[Dictionary] = []
var seated: Dictionary = {}
var selected: Variant = null
var climbing := false
var _standing_eye := 1.6
var _climb_tween: Tween

func _ready() -> void:
	camera = player.get_node("CameraRig/Camera3D")
	_standing_eye = player.rig.position.y
	seats = tavern.seats
	for door: TavernDoor in tavern.doors:
		door.player = player
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

func _process(_delta: float) -> void:
	selected = null
	prompt.text = ""
	if not camera.current or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	# context_text() casts a ray (can_board); ask once and reuse the answer.
	var context := lakeside.context_text() if lakeside != null else ""
	if context != "" and not climbing:
		prompt.text = context
		return
	if climbing:
		prompt.text = "Подъём по лестнице…" if player.global_position.y < 13.0 else "Лестница на чердак"
		return
	if camping != null and camping.placing:
		prompt.text = camping.placement_text()
		return
	if not seated.is_empty():
		prompt.text = "E — встать   ·   Мышь — обзор"
		if camping != null:
			prompt.text += camping.seated_text()
		return
	var best := REACH
	if population != null and population.bartender != null:
		var barkeeper := population.bartender
		var distance := target_distance(barkeeper.interaction_point())
		if distance < best:
			best = distance
			selected = barkeeper
	for door: TavernDoor in tavern.doors:
		var distance := target_distance(door.center(), door)
		if distance < best:
			best = distance
			selected = door
	for seat: Dictionary in seats:
		var position := vector(seat.position) + Vector3.UP * SEAT_TARGET_HEIGHT
		var distance := target_distance(position)
		if distance < best:
			best = distance
			selected = seat
	var ladder := LADDER_BOTTOM + Vector3.UP if player.global_position.y < 13.0 else LADDER_TOP + Vector3.UP * 0.15
	var ladder_distance := target_distance(ladder, null, true)
	if ladder_distance < best:
		best = ladder_distance
		selected = "ladder"
	if camping != null:
		var target := camping.find_target(best)
		if not target.is_empty():
			selected = target.target
	if selected is VillageNPC:
		prompt.text = selected.interaction_text() if selected.job == "bartender" else camping.interaction_text(selected)
	elif selected is Campfire:
		prompt.text = selected.interaction_text(camping.holding_food())
	elif selected is TavernDoor:
		var door: TavernDoor = selected
		prompt.text = "E — %s · %s" % ["закрыть" if door.opened else "открыть", door.title]
		if door.obstructed:
			prompt.text = "Отойдите от створки · E — повернуть дверь"
	elif selected is Dictionary:
		prompt.text = "E — сесть · " + selected.name
	elif selected is String:
		prompt.text = "E — подняться на чердак" if player.global_position.y < 13.0 else "E — спуститься с чердака"

func target_distance(point: Vector3, door: TavernDoor = null, ladder := false, actor: VillageNPC = null) -> float:
	var offset := point - camera.global_position
	var distance := offset.length()
	if distance > REACH or distance < 0.01 or (-camera.global_basis.z).dot(offset / distance) < TARGET_DOT:
		return INF
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, point)
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider != door and hit.collider != actor and hit.position.distance_to(point) > (0.45 if ladder else 0.2):
		return INF
	return distance

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or event.is_echo() or not camera.current:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if lakeside != null and lakeside.interact():
		get_viewport().set_input_as_handled()
	elif climbing:
		get_viewport().set_input_as_handled()
	elif camping != null and camping.placing:
		camping.confirm_placement()
		get_viewport().set_input_as_handled()
	elif not seated.is_empty():
		stand()
		get_viewport().set_input_as_handled()
	elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and selected != null:
		if selected is VillageNPC:
			if selected.job == "bartender":
				selected.interact(player)
			else:
				camping.interact_npc(selected)
		elif selected is Campfire:
			camping.interact_fire(selected)
		elif selected is TavernDoor:
			selected.interact()
		elif selected is Dictionary:
			sit(selected)
		else:
			climb()
		get_viewport().set_input_as_handled()

func sit(seat: Dictionary) -> void:
	if climbing or not seated.is_empty():
		return
	if seat.get("camp", false) and camping.seat_occupied(seat):
		return
	seated = seat
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	(player.get_node("Collision") as CollisionShape3D).disabled = true
	player.global_position = vector(seat.position)
	player.rig.position.y = float(seat.height) + 0.74
	var direction := vector(seat.facing)
	player.rig.yaw_deg = rad_to_deg(atan2(-direction.x, -direction.z))
	player.rig.pitch_deg = -8.0
	player.rig.apply_look(Vector2.ZERO)

func stand() -> bool:
	if seated.is_empty():
		return true
	var candidates: Array[Vector3] = []
	for exit: Array in seated.exits:
		candidates.append(vector(exit))
	var origin := vector(seated.position)
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
	if floor_hit.is_empty() or floor_hit.normal.y < 0.7 or absf(floor_hit.position.y - point.y) > 0.15:
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
	restore_player()

static func vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])
