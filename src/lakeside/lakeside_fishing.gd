extends RefCounted
## Casting, waiting for the bite and the fight with the fish.

static func cast(lake: LakesideSystem) -> bool:
	var eye := lake.interactions.camera.global_position
	var direction := -lake.interactions.camera.global_basis.z
	var flat := Vector3(direction.x, 0, direction.z).normalized()
	var distance := lerpf(4.0, 22.0, clampf(lake.charge / 1.4, 0, 1))
	lake.catch_point = lake.player.global_position + flat * distance
	lake.catch_point.y = lake.water.water_level + 0.03
	var depth := lake.water.water_level - lake.terrain.height_at(lake.catch_point.x, lake.catch_point.z)
	var ray := PhysicsRayQueryParameters3D.create(eye, lake.catch_point)
	ray.exclude = [lake.player.get_rid(), lake.boat.get_rid()]
	var hit := lake.get_world_3d().direct_space_state.intersect_ray(ray)
	if depth < 0.35 or (not hit.is_empty() and hit.position.distance_to(lake.catch_point) > 0.3):
		lake.phase = "idle"
		lake.notify("Здесь не забросить: выбери открытую воду перед собой.")
		return false
	lake.fish_kind = lake.fishing.choose(depth, distance_to_shore(lake, lake.catch_point), lake.sky.time_of_day)
	lake.phase = "waiting"
	lake.wait_time = lake.fishing.rng.randf_range(5.0, 11.0)
	lake.bobber.visible = true
	lake.play("rod_swish", eye)
	lake.play("plop", lake.catch_point)
	return true

static func distance_to_shore(lake: LakesideSystem, point: Vector3) -> float:
	# Sample bathymetry at the cast, not the distance from the angler (who may be afloat).
	for radius: float in [2, 5, 10, 20, 40]:
		for i in 12:
			var edge := point + Vector3(cos(i * TAU / 12), 0, sin(i * TAU / 12)) * radius
			if lake.terrain.height_at(edge.x, edge.z) >= lake.water.water_level:
				return radius
	return 60.0

## The phase timers of one frame; `active` as in LakesideSystem._process.
static func advance(lake: LakesideSystem, delta: float, active: bool) -> void:
	if lake.phase == "charging" and active:
		lake.charge = minf(lake.charge + delta, 1.4)
	elif lake.phase == "charging" and not active:
		lake.cancel_fishing()
	elif lake.phase in ["waiting", "bite"] and active:
		lake.wait_time -= delta
		if lake.wait_time <= 0:
			if lake.phase == "waiting":
				lake.phase = "bite"
				lake.wait_time = 4.0
				lake.play("fish_splash", lake.catch_point)
			else:
				lake.phase = "waiting"
				lake.wait_time = 5.0
	elif lake.phase == "fight" and active:
		var reel := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		advance_fight(lake, delta, reel)
	if lake.phase in ["waiting", "bite", "fight"]:
		if lake.player.global_position.distance_to(lake.catch_point) > 30:
			lake.cancel_fishing()
		else:
			lake.bobber.position = lake.catch_point
			lake.bobber.position.y = lake.water.surface_height(2) + (0.04 if lake.phase == "waiting" else -0.08) + sin(lake.clock * 6) * 0.02
			lake.draw_line()

static func advance_fight(lake: LakesideSystem, delta: float, reel: bool) -> void:
	var pull := 0.14 + maxf(0, sin(lake.clock * 1.8)) * 0.23
	lake.tension = clampf(lake.tension + delta * (pull + 0.23 if reel else -0.58), 0, 1)
	if reel and lake.tension > 0.15 and lake.tension < 0.85:
		lake.progress += delta * 0.14
	elif not reel:
		lake.progress = maxf(0, lake.progress - delta * 0.015)
	if lake.tension >= 1:
		lake.cancel_fishing()
		lake.notify("Рыба ушла. Снасть цела — можно попробовать снова.")
	elif lake.progress >= 1:
		var full := lake.fishing.bag.size() >= FishingState.CAPACITY
		var fish := lake.fishing.catch_fish(lake.fish_kind, lake.sky.time_of_day)
		lake.cancel_fishing()
		lake.play("fish_flop", lake.player.position)
		lake.notify("%s · %.1f см · %.2f кг\n%s" % [FishingState.SPECIES[fish.species].title, fish.cm, fish.kg,
			"Корзина полна: рыба отпущена, запись сохранена." if full else "Улов в корзине · I — журнал · Z у костра — приготовить"])
