extends RefCounted
## Off-axis crop in full-target pixel coordinates; no change in pixel density.
const QUANTUM := 64

static func project_bounds(points: PackedVector3Array, full: Vector2i, fov: float, near_plane: float) -> Rect2i:
	var whole := Rect2i(Vector2i.ZERO, full)
	var focal := float(full.y) / (2.0 * tan(deg_to_rad(fov) * 0.5))
	var lower := Vector2(full)
	var upper := Vector2.ZERO
	for point in points:
		# A box crossing the eye cannot safely be bounded by its eight corners.
		if point.z >= -near_plane: return whole
		var pixel := Vector2(full) * 0.5 + Vector2(point.x, -point.y) * focal / -point.z
		lower = lower.min(pixel)
		upper = upper.max(pixel)
	# Maximum refraction is 1.8% of the FULL target, plus filtering/MSAA guard.
	var guard := Vector2(full) * 0.02 + Vector2(8, 8)
	lower -= guard
	upper += guard
	var start := Vector2i(floori(lower.x / QUANTUM), floori(lower.y / QUANTUM)) * QUANTUM
	var end := Vector2i(ceili(upper.x / QUANTUM), ceili(upper.y / QUANTUM)) * QUANTUM
	var result := Rect2i(start, end - start).intersection(whole)
	if not result.has_area() or result.get_area() > whole.get_area() * 0.90: return whole
	return result

static func apply_camera(camera: Camera3D, full: Vector2i, rect: Rect2i, fov: float) -> void:
	if rect == Rect2i(Vector2i.ZERO, full):
		camera.set_perspective(fov, camera.near, camera.far)
		return
	var full_height := 2.0 * camera.near * tan(deg_to_rad(fov) * 0.5)
	var metres_per_pixel := full_height / full.y
	var centre := Vector2(rect.position) + Vector2(rect.size) * 0.5 - Vector2(full) * 0.5
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.set_frustum(rect.size.y * metres_per_pixel,
		Vector2(centre.x, -centre.y) * metres_per_pixel, camera.near, camera.far)
