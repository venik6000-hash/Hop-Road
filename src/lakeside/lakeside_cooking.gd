extends RefCounted
## The catch after the line: sharing, the cook's help, the campfire grill and
## the cooked fish.
const COOK_SECONDS := 24.0

static func use_catch(lake: LakesideSystem) -> void:
	if lake.camping.holding_food():
		lake.notify("Сначала доешь или раздели картошку: F / Q.")
		return
	if lake.rod_out:
		lake.notify("J — убери удочку, чтобы достать улов.")
		return
	var companion := lake.camping.nearest_companion(3.0)
	var cooked := lake.fishing.first(true)
	if companion != null and not cooked.is_empty():
		if not lake.fishing.take(cooked.id).is_empty():
			var known := lake.camping._memory(companion)
			known["shared"] = int(known.get("shared", 0)) + 1
			lake.camping.memories[companion.name] = known
			lake.camping._save_memory()
			(companion.outing as NpcOuting).receive_food(fish_visual(true, 0.65))
			lake.camping.say(companion, "Спасибо за рыбу. Хорошо посидели у озера!")
		return
	for actor: VillageNPC in lake.interactions.population.actors:
		if actor.job in ["chop", "stir"] and actor.global_position.distance_to(lake.player.global_position) < 2.5:
			var raw := lake.fishing.first(false)
			if not raw.is_empty() and not lake.cooking.has("id"):
				lake.fishing.cook(raw.id)
				lake.camping.say(actor, "Отличный улов. Вот твоя порция — раздели со спутником.")
				return
	var fire := lake.camping.nearby_fire(lake.player.global_position, 3.0)
	if fire != null and fire.burning and lake.cooking.is_empty():
		var raw := lake.fishing.first(false)
		if not raw.is_empty():
			lake.cooking = raw.duplicate()
			lake.cooking_fire = fire
			lake.cook_time = 0
			lake.cooked_visual = make_grilling_fish()
			fire.add_child(lake.cooked_visual)
			lake.notify("Рыба на решётке. Готовится только пока горит огонь.")
			return
	if not cooked.is_empty() and lake.fishing.take(cooked.id).has("id"):
		lake.notify("Тёплая рыба с хрустящей корочкой. Хороший привал.")
	else:
		lake.notify("Нужен улов: J — удочка. Сырую рыбу можно приготовить у огня или отнести повару.")

static func make_grilling_fish() -> Node3D:
	var result := Node3D.new()
	result.position.y = 0.45
	for i in range(6):
		var bar := BoxMesh.new()
		bar.size = Vector3(0.55, 0.012, 0.012)
		NpcProps.mesh(result, bar, Color("34302c"), Vector3(0, 0, i * 0.07 - 0.175))
	var fish := fish_visual(false)
	fish.name = "Fish"
	fish.position.y = 0.07
	result.add_child(fish)
	return result

static func fish_visual(cooked: bool, size := 1.0) -> Node3D:
	# Reuse our existing trout texture and mesh; cooked food has no swimming shader.
	var fish := preload("res://assets/models/wildlife/trout.glb").instantiate() as Node3D
	fish.rotation.z = PI / 2
	fish.scale = Vector3.ONE * size
	for mesh: MeshInstance3D in fish.find_children("*", "MeshInstance3D", true, false):
		var material := mesh.get_active_material(0).duplicate() as StandardMaterial3D
		material.albedo_color = Color("bb8857") if cooked else Color.WHITE
		material.roughness = 0.8
		mesh.material_override = material
	return fish

static func advance_cooking(lake: LakesideSystem, delta: float) -> void:
	if lake.cooking.is_empty():
		return
	if not is_instance_valid(lake.cooking_fire):
		lake.cooking.clear()
		return
	if lake.cooking_fire.burning:
		lake.cook_time += delta
		for mesh: MeshInstance3D in lake.cooked_visual.get_node("Fish").find_children("*", "MeshInstance3D", true, false):
			(mesh.material_override as StandardMaterial3D).albedo_color = Color.WHITE.lerp(Color("bb8857"), minf(lake.cook_time / COOK_SECONDS, 1))
	if lake.cook_time >= COOK_SECONDS:
		if lake.fishing.cook(lake.cooking.id):
			lake.notify("Рыба готова и убрана в корзину. Z — поесть / угостить спутника рядом.")
		lake.cooking.clear()
		lake.cooked_visual.queue_free()
