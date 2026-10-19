extends NpcCookJob
## The cook at the hearth: stirs the stew. The spoon is in the hand while she
## stirs and lies in the pot otherwise. The steaming pot stands at the work
## file's `pot`.

func _init() -> void:
	super()
	held.assign(["stir"])
	rest = Transform3D(Basis(Vector3(0.7412, 0.0, -0.6713), 0.28), Vector3(0.08, 0.98, -0.42))

func make_utensil() -> Node3D:
	return NpcProps.spoon()

func place_work(population: NpcPopulation, _actor: VillageNPC, work: Dictionary) -> void:
	if not work.has("pot"):
		return
	var pot := Node3D.new()
	pot.name = "CookingStew"
	population.add_child(pot)
	pot.position = Values.vec3(work.pot)
	NpcProps.mesh(pot, NpcProps.cylinder(0.17, 0.18, true), Color("786847"), Vector3.ZERO, 0.5)
	NpcProps.mesh(pot, NpcProps.cylinder(0.155, 0.012), Color("704b26"), Vector3.UP * 0.075)
	shade_with_tavern(pot)
	var steam := CPUParticles3D.new()
	pot.add_child(steam)
	steam.position.y = 0.1
	steam.amount = 10
	steam.lifetime = 1.6
	steam.direction = Vector3.UP
	steam.spread = 10
	steam.initial_velocity_min = 0.15
	steam.initial_velocity_max = 0.25
	steam.gravity = Vector3(0, 0.1, 0)
	steam.scale_amount_min = 0.04
	steam.scale_amount_max = 0.08
	var puff := SphereMesh.new()
	puff.radius = 0.5
	puff.height = 1.0
	puff.radial_segments = 8
	puff.rings = 4
	var puff_material := NpcProps.material(Color(0.65,0.62,0.57,0.15))
	puff.material = puff_material
	puff_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	steam.mesh = puff
	steam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
