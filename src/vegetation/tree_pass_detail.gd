extends RefCounted
## Pass 2 of TreePlacer: the jittered lattice of the detail region. Static
## functions over the TreePlacer `placer`, whose state they share.
const Composed = preload("res://src/vegetation/tree_pass_composed.gd")

# --- pass 2: the detail region ----------------------------------------------

## Beach, rock outcrops and the Blender backdrop take share from the mask forest.
static func _detail_factor(placer: TreePlacer, x: float, z: float, w: float) -> float:
	var factor := 1.0 - Composed.backdrop_share(x, z)
	if w > 0.0:
		factor *= (1.0 - placer.terrain.control_at(x, z, 1)) * (1.0 - 0.85 * placer.terrain.extra_at(x, z, 0))
	return factor

static func place_detail(placer: TreePlacer) -> void:
	var t := placer.terrain
	var cell := TreePlacer.DETAIL_CELL
	var x0 := floori(placer.detail_rect.position.x / cell)
	var z0 := floori(placer.detail_rect.position.y / cell)
	var nx := int(ceil(placer.detail_rect.size.x / cell))
	var nz := int(ceil(placer.detail_rect.size.y / cell))
	var p_full := cell * cell / TreePlacer.AREA_PER_TREE
	var salt_term := TreePlacer.SALT_CELL * 83492791
	# Local copies: member and property access cost a lookup per use.
	var far_masks := t.far_masks
	var fsize := t.far_size
	var fox := t.far_origin.x
	var foz := t.far_origin.y
	var fcell := t.far_cell
	var control := t.control
	var msize := t.mask_size
	var mox := t.mask_origin.x
	var moz := t.mask_origin.y
	var mcell := t.mask_cell
	var nox := t.near_origin.x
	var noz := t.near_origin.y
	var ncell := t.near_cell
	var nlast := (t.near_size - 1) * ncell
	# Accepted trunks of the previous and current row: x, z, spacing.
	var previous := PackedVector3Array()
	var current := PackedVector3Array()
	previous.resize(nx + 2)
	current.resize(nx + 2)
	var empty := Vector3(INF, INF, 0.0)
	previous.fill(empty)
	for iz in nz:
		current.fill(empty)
		var gz: int = z0 + iz
		for ix in nx:
			var gx: int = x0 + ix
			var h: int = ((gx * 73856093) ^ (gz * 19349663) ^ salt_term) & 0xffffffff
			h = ((h >> 16) ^ h) * 0x45d9f3b & 0xffffffff
			h = ((h >> 16) ^ h) * 0x45d9f3b & 0xffffffff
			h = (h >> 16) ^ h
			var r: int = (h + 0x3c6ef372) & 0xffffffff
			r = ((r >> 16) ^ r) * 0x45d9f3b & 0xffffffff
			r = ((r >> 16) ^ r) * 0x45d9f3b & 0xffffffff
			r = (r >> 16) ^ r
			var roll: float = float(r & 0xffffff) / 16777216.0
			if roll >= p_full:
				continue
			var j: int = h ^ 0x1b873593
			j = ((j >> 16) ^ j) * 0x45d9f3b & 0xffffffff
			j = ((j >> 16) ^ j) * 0x45d9f3b & 0xffffffff
			j = (j >> 16) ^ j
			var px: float = (gx + float(h & 0xffffff) / 16777216.0) * cell
			var pz: float = (gz + float(j & 0xffffff) / 16777216.0) * cell
			# Far forest mask, bilinear.
			var fx: float = clampf((px - fox) / fcell, 0.0, fsize - 1.001)
			var fz: float = clampf((pz - foz) / fcell, 0.0, fsize - 1.001)
			var fi: int = int(fx)
			var fj: int = int(fz)
			var ft: float = fx - fi
			var fu: float = fz - fj
			var k: int = (fj * fsize + fi) * 4 + 2
			var row: int = fsize * 4
			var forest: float = lerpf(lerpf(far_masks[k], far_masks[k + 4], ft),
				lerpf(far_masks[k + row], far_masks[k + row + 4], ft), fu) / 255.0
			# Near forest mask, blended in over the near field's outer 40 m.
			var lx: float = px - nox
			var lz: float = pz - noz
			var w: float = clampf(minf(minf(lx, lz), minf(nlast - lx, nlast - lz)) / VegetationTerrain.NEAR_FADE, 0.0, 1.0)
			if w > 0.0:
				var mx: float = clampf((px - mox) / mcell, 0.0, msize - 1.001)
				var mz: float = clampf((pz - moz) / mcell, 0.0, msize - 1.001)
				var mi: int = int(mx)
				var mj: int = int(mz)
				var mt: float = mx - mi
				var mu: float = mz - mj
				var m: int = (mj * msize + mi) * 4 + 2
				var mrow: int = msize * 4
				var near_forest: float = lerpf(lerpf(control[m], control[m + 4], mt),
					lerpf(control[m + mrow], control[m + mrow + 4], mt), mu) / 255.0
				forest = lerpf(forest, near_forest, w)
			if roll >= forest * p_full:
				continue
			var density: float = forest * _detail_factor(placer, px, pz, w)
			if roll >= density * p_full:
				continue
			var altitude := t.height(px, pz) - t.water_level
			var pick := placer.choose(px, pz, altitude, density, TreePlacer.hash_u32(h ^ 0x7f4a7c15))
			var kind := int(pick.x)
			var grow := pick.y
			var spacing: float = TreePlacer.SPECIES_SPACING[kind] * grow
			if _crowded(px, pz, spacing, previous, current, ix):
				continue
			if not placer.ground_ok(px, pz, TreePlacer.SPECIES_CROWN[kind] * grow * 0.5, 0.25):
				continue
			if Composed.near_composed(placer, px, pz, spacing):
				continue
			current[ix + 1] = Vector3(px, pz, spacing)
			placer.trees.add(px, TreePlacer.seat(t, px, pz, altitude + t.water_level, kind, grow), pz,
				TreePlacer.unit(TreePlacer.hash_u32(h + 11)) * TAU, grow, 1.0, kind,
				TreePlacer.unit(TreePlacer.hash_u32(h + 13)), TreeSet.DETAIL)
		var swap := previous
		previous = current
		current = swap

## True when an accepted trunk in the four already visited neighbour cells
## (left, and the three above) stands closer than the larger spacing.
static func _crowded(x: float, z: float, spacing: float, previous: PackedVector3Array, current: PackedVector3Array,
		ix: int) -> bool:
	for other in [current[ix], previous[ix], previous[ix + 1], previous[ix + 2]]:
		if other.x == INF:
			continue
		var gap := maxf(spacing, other.z)
		var dx: float = x - other.x
		var dz: float = z - other.y
		if dx * dx + dz * dz < gap * gap:
			return true
	return false
