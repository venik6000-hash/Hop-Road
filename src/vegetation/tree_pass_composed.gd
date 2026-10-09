extends RefCounted
## Pass 1 of TreePlacer: the trees of the Blender composition, and the grid
## of accepted composed trees the lattice passes keep clear of. Static
## functions over the TreePlacer `placer`, whose state they share.

# --- pass 1: the Blender composition ---------------------------------------

static func place_composed(placer: TreePlacer, composed: Array) -> void:
	for entry: Dictionary in composed:
		var template := str(entry.get("template", ""))
		if not TreePlacer.COMPOSED.has(template):
			continue
		var position: Array = entry.position
		var px := float(position[0])
		var pz := float(position[2])
		var h := TreePlacer.cell_hash(int(floor(px * 16.0)), int(floor(pz * 16.0)), TreePlacer.SALT_CELL + 2)
		var backdrop := template.begins_with("Dense distant")
		if backdrop and TreePlacer.unit(TreePlacer.hash_u32(h ^ 0x68e31da4)) >= backdrop_share(px, pz):
			continue
		var mapping: Array = TreePlacer.COMPOSED[template]
		var choices: Array = mapping[0]
		var kind: int = choices[h % choices.size()]
		var target := float(mapping[1]) * float(entry.get("scale", 1.0)) * float(mapping[2])
		# Small backdrop trees become young firs rather than miniature spruces.
		if backdrop and kind != TreePlacer.BEECH_A and kind != TreePlacer.BEECH_B and target < 8.0:
			kind = TreePlacer.FIR_YOUNG
		var grow := clampf(target / TreePlacer.SPECIES_HEIGHT[kind], 0.45, 1.25 if kind != TreePlacer.FIR_YOUNG else 2.0)
		if not placer.ground_ok(px, pz, TreePlacer.SPECIES_CROWN[kind] * grow * 0.45, 0.3):
			continue
		placer.trees.add(px, placer.terrain.height(px, pz), pz, float(entry.get("yaw", 0.0)), grow, 1.0, kind,
			TreePlacer.unit(TreePlacer.hash_u32(h + 7)), TreeSet.DETAIL | TreeSet.COMPOSED)
		var key := Vector2i(floori(px / 8.0), floori(pz / 8.0))
		if not placer._composed_grid.has(key):
			placer._composed_grid[key] = []
		placer._composed_grid[key].append(Vector3(px, pz, TreePlacer.SPECIES_SPACING[kind] * grow))
		var spot := Rect2(px, pz, 0.0, 0.0)
		placer._composed_bounds = placer._composed_bounds.merge(spot) if placer._has_composed else spot
		placer._has_composed = true

## 0..1: how much of the forest near (x, z) the Blender backdrop provides.
## Its rectangle edge wanders with noise, so the fade does not run straight.
static func backdrop_share(x: float, z: float) -> float:
	if not TreePlacer.BACKDROP.grow(20.0).has_point(Vector2(x, z)):
		return 0.0
	var inside := minf(minf(x - TreePlacer.BACKDROP.position.x, TreePlacer.BACKDROP.end.x - x), minf(z - TreePlacer.BACKDROP.position.y, TreePlacer.BACKDROP.end.y - z))
	return smoothstep(-2.0, 16.0, inside + (TreePlacer.value_noise(x, z, 23.0, TreePlacer.SALT_EDGE) - 0.5) * 26.0)

static func near_composed(placer: TreePlacer, x: float, z: float, spacing: float) -> bool:
	if not placer._has_composed or not placer._composed_bounds.grow(12.0).has_point(Vector2(x, z)):
		return false
	var cx := floori(x / 8.0)
	var cz := floori(z / 8.0)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := Vector2i(cx + dx, cz + dz)
			if not placer._composed_grid.has(key):
				continue
			for other: Vector3 in placer._composed_grid[key]:
				var gap := maxf(spacing, other.z)
				if Vector2(x - other.x, z - other.y).length_squared() < gap * gap:
					return true
	return false
