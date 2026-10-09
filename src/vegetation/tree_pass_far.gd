extends RefCounted
## Pass 3 of TreePlacer: the far field, the same lattice coarsened per block.
## Static functions over the TreePlacer `placer`, whose state they share.

# --- pass 3: the far field ----------------------------------------------------

static func place_far(placer: TreePlacer) -> void:
	var blocks := int(ceil(placer.far_rect.size.x / TreePlacer.FAR_BLOCK))
	var reach := placer.near_rect.grow(TreePlacer.FAR_REACH)
	for bz in blocks:
		for bx in blocks:
			var block := Rect2(placer.far_rect.position + Vector2(bx, bz) * TreePlacer.FAR_BLOCK, Vector2.ONE * TreePlacer.FAR_BLOCK)
			block = block.intersection(placer.far_rect)
			if placer.detail_rect.encloses(block) or not reach.intersects(block):
				continue
			if placer.terrain.far_forest_max(block) <= 0.0:
				continue
			_place_block(placer, block)

static func _place_block(placer: TreePlacer, block: Rect2) -> void:
	var t := placer.terrain
	var cell := TreePlacer.far_cell_size(TreePlacer.thinning(TreePlacer.rect_rect_distance(placer.near_rect, block)))
	var x0 := floori(block.position.x / cell)
	var z0 := floori(block.position.y / cell)
	var x1 := floori((block.end.x - 0.001) / cell)
	var z1 := floori((block.end.y - 0.001) / cell)
	var area := cell * cell / TreePlacer.AREA_PER_TREE
	# A salt per cell size keeps coarser lattices independent of finer ones.
	var salt_term := (TreePlacer.SALT_CELL + int(cell)) * 83492791
	var far_masks := t.far_masks
	var far_h := t.far_h
	var fsize := t.far_size
	var fox := t.far_origin.x
	var foz := t.far_origin.y
	var fcell := t.far_cell
	var row: int = fsize * 4
	var bx0 := block.position.x
	var bz0 := block.position.y
	var bx1 := block.end.x
	var bz1 := block.end.y
	var dx0 := placer.detail_rect.position.x
	var dz0 := placer.detail_rect.position.y
	var dx1 := placer.detail_rect.end.x
	var dz1 := placer.detail_rect.end.y
	var nx0 := placer.near_rect.position.x
	var nz0 := placer.near_rect.position.y
	var nx1 := placer.near_rect.end.x
	var nz1 := placer.near_rect.end.y
	var water := t.water_level
	for gz in range(z0, z1 + 1):
		for gx in range(x0, x1 + 1):
			var h: int = ((gx * 73856093) ^ (gz * 19349663) ^ salt_term) & 0xffffffff
			h = ((h >> 16) ^ h) * 0x45d9f3b & 0xffffffff
			h = ((h >> 16) ^ h) * 0x45d9f3b & 0xffffffff
			h = (h >> 16) ^ h
			var r: int = (h + 0x3c6ef372) & 0xffffffff
			r = ((r >> 16) ^ r) * 0x45d9f3b & 0xffffffff
			r = ((r >> 16) ^ r) * 0x45d9f3b & 0xffffffff
			r = (r >> 16) ^ r
			var roll: float = float(r & 0xffffff) / 16777216.0
			if roll >= area:
				continue
			var j: int = h ^ 0x1b873593
			j = ((j >> 16) ^ j) * 0x45d9f3b & 0xffffffff
			j = ((j >> 16) ^ j) * 0x45d9f3b & 0xffffffff
			j = (j >> 16) ^ j
			var px: float = (gx + float(h & 0xffffff) / 16777216.0) * cell
			var pz: float = (gz + float(j & 0xffffff) / 16777216.0) * cell
			if px < bx0 or px >= bx1 or pz < bz0 or pz >= bz1:
				continue
			if px >= dx0 and px < dx1 and pz >= dz0 and pz < dz1:
				continue
			var fx: float = clampf((px - fox) / fcell, 0.0, fsize - 1.001)
			var fz: float = clampf((pz - foz) / fcell, 0.0, fsize - 1.001)
			var fi: int = int(fx)
			var fj: int = int(fz)
			var ft: float = fx - fi
			var fu: float = fz - fj
			var k: int = (fj * fsize + fi) * 4
			var forest: float = lerpf(lerpf(far_masks[k + 2], far_masks[k + 6], ft),
				lerpf(far_masks[k + row + 2], far_masks[k + row + 6], ft), fu) / 255.0
			if roll >= forest * area:
				continue
			var snow: float = lerpf(lerpf(far_masks[k], far_masks[k + 4], ft),
				lerpf(far_masks[k + row], far_masks[k + row + 4], ft), fu) / 255.0
			forest *= 1.0 - snow
			var ddx: float = maxf(maxf(nx0 - px, px - nx1), 0.0)
			var ddz: float = maxf(maxf(nz0 - pz, pz - nz1), 0.0)
			var thin: float = TreePlacer.thinning(sqrt(ddx * ddx + ddz * ddz))
			if roll >= forest * thin * area:
				continue
			var hi: int = fj * fsize + fi
			var ground: float = lerpf(lerpf(far_h[hi], far_h[hi + 1], ft),
				lerpf(far_h[hi + fsize], far_h[hi + fsize + 1], ft), fu)
			var altitude: float = ground - water
			if altitude < 2.0:
				continue
			var pick := placer.choose(px, pz, altitude, forest, TreePlacer.hash_u32(h ^ 0x7f4a7c15))
			placer.trees.add(px, ground, pz, TreePlacer.unit(TreePlacer.hash_u32(h + 11)) * TAU, pick.y, TreePlacer.widening(thin), int(pick.x),
				TreePlacer.unit(TreePlacer.hash_u32(h + 13)), 0)
