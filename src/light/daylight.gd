class_name Daylight
extends Node3D
## The day in a building's rooms, through the openings of its Interior that
## let it in (`daylight`): the centre of each on the wall's line, the wall's
## normal into the room, the clear width, sill, springing and top, the way
## from that line to the room's face of the wall, the floor of the room
## behind. How bright each part is, the room's profile says (LightProfile
## `daylight`). The node stands at the building's origin.
##
## The engine has no bounced light here, so three things stand in for what a
## window does to a room:
## - the sky: a lamp in each opening that shines into the room, as bright and
##   as blue as the day outside, with the shadows of what stands still;
## - the sun's beam in the dusty air: daylight_shaft.gdshader sums the lit air
##   along the eye's ray inside a hull behind each opening, all the hulls in
##   one mesh;
## - the floor the sun lies on, which lights the room from below: a warm lamp
##   over the patch, with no shadows.
## The sun itself comes in through the openings by the sun's own shadow map.
## The leaves of a door standing in an opening shut all three out as they close.
##
## By night the moon takes the sun's place in all three, and one thing more:
## to an eye used to candles the moon's own light is lost on the floor, so
## while the eye is in the building's rooms a lamp outside each opening the
## moon looks into throws the opening's outline onto the floor, bars and all.

const SHAFT := preload("res://src/light/daylight_shaft.gdshader")
## How far into the room a beam is followed, m.
const SHAFT_LENGTH := 6.5
## The sky's lamp in an opening.
const SKY_RANGE := 9.0
const SKY_ANGLE := 76.0
## The sky is wide: its lamp's shadows are blurred this much.
const SKY_SHADOW_BLUR := 3.0
## The openings the beams' shader can tell apart (its `air`).
const MOST_OPENINGS := 16
## A door's leaf hangs in an opening when its hinge is this near the jamb, m.
const HINGE_REACH := 0.5
const SKY_BLUE := Color(0.86, 0.91, 1.0)
const SKY_GREY := Color(0.9, 0.92, 0.95)
const SKY_DUSK := Color(1.0, 0.8, 0.62)
const SKY_NIGHT := Color(0.5, 0.66, 1.0)
## The colour of the floor's light, and how far over the patch its lamp hangs.
const BOUNCE_TINT := Color(0.62, 0.42, 0.27)
const BOUNCE_RANGE := 6.0
const BOUNCE_LIFT := 0.45
## The sun's patch is not followed further into the room than this, m.
const BOUNCE_REACH := 5.0
## How far outside the opening the moon's lamp hangs (m) and how far it
## reaches beyond.
const MOON_BACK := 7.0
const MOON_REACH := 16.0
## A spot lamp's bias is a depth in its map, not metres: 0.01 of it is 4 mm
## 1 m from the lamp and 0.4 m at 10 m (it grows with the square of the
## distance; the near plane is 0.025 m). The moon's lamp is 7 m and more from
## what it lights and its map is fine, so 0.02 left no shadow to a stool in
## the patch (0.8 m at 10 m); 0.005 is three steps of the map's 16 bits there.
const MOON_SHADOW_BIAS := 0.005
## The sun has moved by this much (its direction's change): place things again.
const SUN_STEP := 0.002
## Seconds over which a ridge takes the sun from the windows or gives it back.
const RIDGE_SECONDS := 1.5

var sky: SkySystem
## Asked for the ridges between the sun and the building; none without it.
var terrain: TerrainSystem
var interior: Interior
## The building's doors, whose leaves stand in its openings.
var doors: Array[TavernDoor] = []

## {centre, inward, width, sill, top, spring, floor, reveal, area, light
## (the profile's `daylight`), sky, bounce, moon, doors}
var _openings: Array[Dictionary] = []
var _shafts: MeshInstance3D
var _material := ShaderMaterial.new()
var _placed_for := Vector3.ZERO
var _sun_seen := 1.0
var _sun_clear := true
## The sun's or the moon's light, how much of it the ridges leave, the sky's
## openness and the doors' the lamps were last set for; whether it was the
## moon's, and whether the eye was in the building.
var _state := Vector4(-1.0, -1.0, -1.0, -1.0)
var _by_moon := false
var _eye_indoors := false

func _ready() -> void:
	_material.shader = SHAFT
	_material.set_shader_parameter("reach", SHAFT_LENGTH)

## Whether `interior` has an opening the day comes in by.
static func lets_in(interior: Interior) -> bool:
	for opening: Interior.Opening in interior.openings:
		if opening.daylight:
			return true
	return false

## Takes the openings of `interior` the day comes in by.
func build() -> void:
	for found: Interior.Opening in interior.openings:
		if not found.daylight:
			continue
		var room := interior.room(found.rooms[0])
		var opening := {"centre": found.centre, "inward": found.inward, "width": found.width, "sill": found.sill,
			"top": found.top, "spring": found.spring, "floor": found.floor_height, "reveal": found.reveal,
			"light": room.profile.daylight}
		opening.area = found.width * (found.top - found.sill)
		opening.sky = _sky_lamp(opening, found.name)
		opening.bounce = _bounce_lamp(found.name)
		opening.moon = _moon_lamp(found.name)
		opening.doors = _leaves_in(opening)
		_openings.append(opening)
	_build_shafts()
	_placed_for = Vector3.ZERO

func _sky_lamp(opening: Dictionary, title: String) -> SpotLight3D:
	var lamp := SpotLight3D.new()
	lamp.name = "Sky " + title
	lamp.spot_range = SKY_RANGE
	lamp.spot_angle = SKY_ANGLE
	lamp.spot_attenuation = 1.0
	lamp.spot_angle_attenuation = 0.5
	lamp.shadow_enabled = true
	lamp.shadow_bias = 0.02
	lamp.shadow_normal_bias = 0.2
	lamp.shadow_blur = SKY_SHADOW_BLUR
	lamp.light_specular = 0.3
	lamp.light_cull_mask = LightLayers.ROOMS
	lamp.shadow_caster_mask = LightLayers.LAMP_CASTERS
	FarLights.fade(lamp, "interior")
	add_child(lamp)
	# At the room's face of the wall, in the upper half of the opening, and
	# turned down a little: the sky is above.
	var inward: Vector3 = opening.inward
	var height: float = opening.top - opening.sill
	lamp.position = opening.centre + inward * (opening.reveal + 0.04) + Vector3.UP * (height * 0.15)
	lamp.basis = Basis.looking_at(inward + Vector3.DOWN * 0.35, Vector3.UP)
	return lamp

func _bounce_lamp(title: String) -> OmniLight3D:
	var lamp := OmniLight3D.new()
	lamp.name = "Sun on the floor " + title
	lamp.omni_range = BOUNCE_RANGE
	lamp.omni_attenuation = 1.2
	lamp.light_specular = 0.0
	lamp.light_cull_mask = LightLayers.ROOMS
	lamp.visible = false
	FarLights.fade(lamp, "interior")
	add_child(lamp)
	return lamp

func _moon_lamp(title: String) -> SpotLight3D:
	var lamp := SpotLight3D.new()
	lamp.name = "Moon through " + title
	lamp.spot_range = MOON_BACK + MOON_REACH
	# As even as the moon's own light: no fall with the way, none across the cone.
	lamp.spot_attenuation = 0.0
	lamp.spot_angle_attenuation = 0.05
	lamp.shadow_enabled = true
	lamp.shadow_bias = MOON_SHADOW_BIAS
	lamp.shadow_normal_bias = 0.2
	lamp.light_specular = 0.5
	lamp.light_cull_mask = LightLayers.ROOMS
	lamp.shadow_caster_mask = LightLayers.LAMP_CASTERS
	lamp.visible = false
	FarLights.fade(lamp, "interior")
	add_child(lamp)
	return lamp

## The leaves of the building's doors that hang in `opening`.
func _leaves_in(opening: Dictionary) -> Array[TavernDoor]:
	var leaves: Array[TavernDoor] = []
	var inward: Vector3 = opening.inward
	var across := Vector3.UP.cross(inward).normalized()
	var half: float = Values.real(opening.width) * 0.5 + HINGE_REACH
	for door: TavernDoor in doors:
		var hinge: Vector3 = door.position - opening.centre
		if absf(hinge.dot(across)) < half and absf(hinge.dot(inward)) < Values.real(opening.reveal) + HINGE_REACH:
			leaves.append(door)
	return leaves

## 0 with every leaf of `leaves` shut .. 1 with them open, or with none.
static func openness(leaves: Array[TavernDoor]) -> float:
	if leaves.is_empty():
		return 1.0
	var open := 0.0
	for door: TavernDoor in leaves:
		var swing := absf(door.open_angle - door.closed_angle)
		open += clampf(absf(door.rotation.y - door.closed_angle) / maxf(swing, 0.001), 0.0, 1.0)
	return open / leaves.size()

## One mesh for the beams of every opening: a hull each, the opening's
## rectangle on the wall's line and the same again, which the shader carries
## to the beam's far end.
func _build_shafts() -> void:
	if _shafts == null:
		_shafts = MeshInstance3D.new()
		_shafts.name = "Shafts"
		_shafts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_shafts.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_shafts.layers = LightLayers.ROOMS
		_shafts.material_override = _material
		add_child(_shafts)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs2 := PackedVector2Array()
	var sills := PackedFloat32Array()
	var shapes := PackedFloat32Array()
	var indices := PackedInt32Array()
	var bounds := AABB()
	for number in mini(_openings.size(), MOST_OPENINGS):
		var opening: Dictionary = _openings[number]
		var inward: Vector3 = opening.inward
		var half: float = Values.real(opening.width) * 0.5
		var height: float = opening.top - opening.sill
		var across := Vector3.UP.cross(inward).normalized()
		var low := Vector3(Values.real(opening.centre.x), Values.real(opening.sill), Values.real(opening.centre.z))
		var first := vertices.size()
		# Corner `bits`: across (1), up (2), at the beam's far end (4).
		for bits in 8:
			vertices.append(low + across * (half if bits & 1 else -half) + Vector3.UP * (height if bits & 2 else 0.0))
			normals.append(inward)
			uvs2.append(Vector2(1.0 if bits & 4 else 0.0, 0.0))
			sills.append_array([low.x, low.y, low.z, half])
			shapes.append_array([height, Values.real(opening.spring) - Values.real(opening.sill), Values.real(number), 0.0])
		# The shader draws the hull's far side (cull_front), so every face is
		# wound clockwise as seen from outside; (across, up, inward) is a
		# right-handed frame.
		for face: Array in [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]:
			for corner: int in [0, 2, 1, 0, 3, 2]:
				indices.append(first + Values.whole(face[corner]))
		var box := AABB(low - across * half, Vector3.ZERO).expand(low + across * half + Vector3.UP * height).grow(SHAFT_LENGTH)
		bounds = box if bounds.size == Vector3.ZERO else bounds.merge(box)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV2] = uvs2
	arrays[Mesh.ARRAY_CUSTOM0] = sills
	arrays[Mesh.ARRAY_CUSTOM1] = shapes
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT))
	# The hulls leave the wall in the vertex shader.
	mesh.custom_aabb = bounds
	_shafts.mesh = mesh

func _process(delta: float) -> void:
	if sky == null or _openings.is_empty():
		return
	# The moon has the room once the sun is gone, as it has the shadows.
	var by_moon := not sky.sun.visible
	var source := sky.moon_direction if by_moon else sky.sun_direction
	var body := sky.moon if by_moon else sky.sun
	var moved := not source.is_equal_approx(_placed_for) and source.distance_to(_placed_for) > SUN_STEP
	if moved:
		_sun_clear = _clear_of_ridges(source)
	var seen := move_toward(_sun_seen, 1.0 if _sun_clear else 0.0, delta / RIDGE_SECONDS)
	var light := body.light_energy if body.visible else 0.0
	var camera := get_viewport().get_camera_3d()
	var indoors := camera != null and interior.depth_of(camera.global_position) > 0.0
	var open := PackedFloat32Array()
	open.resize(MOST_OPENINGS)
	var open_sum := 0.0
	for number in mini(_openings.size(), MOST_OPENINGS):
		var leaves: Array[TavernDoor] = _openings[number].doors
		open[number] = openness(leaves)
		open_sum += open[number]
	var state := Vector4(light, seen, sky.sun_share, open_sum)
	if not moved and state.is_equal_approx(_state) and by_moon == _by_moon and indoors == _eye_indoors:
		return
	_state = state
	_by_moon = by_moon
	_eye_indoors = indoors
	_sun_seen = seen
	_placed_for = source
	var colour := body.light_color
	var air := PackedFloat32Array()
	air.resize(MOST_OPENINGS)
	for number in mini(_openings.size(), MOST_OPENINGS):
		var numbers: Dictionary = _openings[number].light
		air[number] = open[number] * Values.real(numbers.beam) * (Values.real(numbers.moon_air) if by_moon else 1.0)
	_material.set_shader_parameter("beam", (global_basis.inverse() * -source).normalized())
	_material.set_shader_parameter("air", air)
	_material.set_shader_parameter("sun_color", colour)
	_material.set_shader_parameter("strength", light * seen)
	_shafts.visible = light * seen > 0.01
	var sun := sky.sun_direction
	var daylight := smoothstep(-0.08, 0.3, sun.y)
	var dusk := 1.0 - smoothstep(0.03, 0.3, sun.y)
	# The moonlit sky: the share of a full moon's light the moon gives now.
	var moonlit := sky.moon.light_energy / maxf(sky.moon_energy, 0.001) if sky.moon.visible else 0.0
	for number in _openings.size():
		var opening: Dictionary = _openings[number]
		var numbers: Dictionary = opening.light
		var closed := lerpf(Values.real(numbers.overcast), 1.0, sky.sun_share)
		var by_day := Values.real(numbers.sky) * daylight * closed
		var by_night := Values.real(numbers.moonlit) * moonlit
		var sky_colour := SKY_GREY.lerp(SKY_BLUE, sky.sun_share).lerp(SKY_DUSK, dusk * sky.sun_share) \
			.lerp(SKY_NIGHT, by_night / maxf(by_day + by_night, 0.0001))
		var share := clampf(Values.real(opening.area) / Values.real(numbers.sky_area), 0.4, 2.0) \
			* (open[number] if number < MOST_OPENINGS else 1.0)
		var lamp: SpotLight3D = opening.sky
		lamp.light_color = sky_colour
		lamp.light_energy = (by_day + by_night) * share
		lamp.visible = lamp.light_energy > 0.01
		var patch := Values.real(numbers.moon_patch) * light / maxf(sky.moon_energy, 0.001) * seen * share if by_moon else 0.0
		_place_moon(opening, source, colour, patch if indoors else 0.0)
		_place_bounce(opening, source, colour,
			(patch * Values.real(numbers.moon_bounce) if by_moon else light * seen * share) * Values.real(numbers.bounce))

## The lamp outside `opening` that throws its outline into the room, down the
## way of the moon at `source`.
func _place_moon(opening: Dictionary, source: Vector3, colour: Color, energy: float) -> void:
	var lamp: SpotLight3D = opening.moon
	var inward: Vector3 = opening.inward
	energy *= smoothstep(0.05, 0.3, -source.dot(inward))
	lamp.visible = energy > 0.01 and source.y > 0.02
	if not lamp.visible:
		return
	var height: float = opening.top - opening.sill
	var middle := Vector3(Values.real(opening.centre.x), Values.real(opening.sill) + height * 0.5, Values.real(opening.centre.z))
	lamp.position = middle + source * MOON_BACK
	lamp.basis = Basis.looking_at(-source, Vector3.UP)
	# The cone holds the whole opening; the wall cuts the outline out of it.
	var half := 0.5 * Vector2(Values.real(opening.width), height).length()
	lamp.spot_angle = rad_to_deg(atan(half * 1.15 / MOON_BACK))
	lamp.light_color = colour
	lamp.light_energy = energy

## The lamp over the floor the sun lies on behind `opening`, sending back
## `energy` of the light that comes in.
func _place_bounce(opening: Dictionary, sun: Vector3, sun_colour: Color, energy: float) -> void:
	var lamp: OmniLight3D = opening.bounce
	var inward: Vector3 = opening.inward
	energy *= smoothstep(0.05, 0.3, -sun.dot(inward))
	lamp.visible = energy > 0.01 and sun.y > 0.02
	if not lamp.visible:
		return
	# From the middle of the opening down the sun's way to the floor.
	var from: Vector3 = opening.centre + inward * Values.real(opening.reveal)
	var fall: float = (from.y - Values.real(opening.floor)) / sun.y
	var flat := Vector2(-sun.x, -sun.z) * fall
	if flat.length() > BOUNCE_REACH:
		flat = flat.normalized() * BOUNCE_REACH
	lamp.position = Vector3(from.x + flat.x, Values.real(opening.floor) + BOUNCE_LIFT, from.z + flat.y)
	lamp.light_color = Color(sun_colour.r * BOUNCE_TINT.r, sun_colour.g * BOUNCE_TINT.g, sun_colour.b * BOUNCE_TINT.b)
	lamp.light_energy = energy

## Whether no ridge of the terrain stands between the sun and the building.
func _clear_of_ridges(sun: Vector3) -> bool:
	if terrain == null or sun.y <= 0.0:
		return sun.y > 0.0
	var from := interior.bounds.get_center()
	var reach := 40.0
	while reach < 16000.0:
		var at := from + sun * reach
		if terrain.height_at(at.x, at.z) > at.y:
			return false
		reach *= 1.2
	return true
