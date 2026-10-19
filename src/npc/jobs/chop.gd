extends NpcCookJob
## The cook at the cutting board: chops, slices and kneads. The knife is in
## the hand in the cutting clips and lies on the board in the others. The
## board with the carrots on it stands at the work file's `board`.

func _init() -> void:
	super()
	held.assign(["chop", "chop_quick", "slice"])
	rest = Transform3D(Basis(Vector3.UP, 1.1), Vector3(0.21, 0.997, -0.4))

func make_utensil() -> Node3D:
	return NpcProps.knife()

func place_work(population: NpcPopulation, _actor: VillageNPC, work: Dictionary) -> void:
	if not work.has("board"):
		return
	var cutting := Node3D.new()
	cutting.name = "FoodPreparation"
	population.add_child(cutting)
	cutting.position = Values.vec3(work.board)
	var board := BoxMesh.new()
	board.size = Vector3(0.32, 0.018, 0.23)
	NpcProps.mesh(cutting, board, Color("85633f"))
	for i in range(4):
		var carrot := NpcProps.mesh(cutting, NpcProps.cylinder(0.013, 0.04), Color("b97a3f"), Vector3(0.04 * i - 0.06, 0.022, -0.025))
		carrot.rotation.x = PI / 2.0
	shade_with_tavern(cutting)
