shader_type spatial;
// The rain's drops (RainFall): each instance is one drop of a box of air that
// follows the eye, drawn as the streak it smears into while the eye's own
// exposure lasts. A drop keeps its place in the world and comes round to the
// other side of the box as the eye leaves it behind.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, skip_vertex_transform;

// The box of air, m.
uniform vec3 box = vec3(26.0, 18.0, 26.0);
// The drops' velocity, m/s, and their way so far, m (RainFall wraps it).
uniform vec3 velocity = vec3(0.0, -9.0, 0.0);
uniform vec3 travelled = vec3(0.0);
// The share of the drops that fall now, 0..1.
uniform float amount = 0.0;
// Seconds of a drop's way one streak shows.
uniform float streak = 0.05;
uniform float half_width = 0.002;
// The least half width, as an angle seen from the eye.
uniform float least_angle = 0.0012;
// The building no rain falls in, known before the map below is drawn;
// `roofed` is 1 when there is one.
uniform vec3 room_min = vec3(0.0);
uniform vec3 room_max = vec3(0.0);
uniform float roofed = 0.0;
// No drops under the lake.
uniform float water_level = -1000.0;
// What the rain falls on first, as a map of heights from above (RainShelter):
// no drop under a roof, an awning or a bridge. `rain_shelter_rect` is the
// map's corner (x, z), its side (m) and 1 once it is drawn.
global uniform sampler2D rain_shelter : filter_linear, repeat_disable;
global uniform vec4 rain_shelter_rect;
// A drop is a lens: it shows the eye a patch of the bright sky, so it is
// lighter than a white card under the same light.
uniform vec3 drop_light = vec3(1.7, 1.8, 1.95);
uniform float opacity = 0.5;

varying float fade;

void vertex() {
	// The instance's origin is its drop's place in the box, 0..1.
	vec3 seed = MODEL_MATRIX[3].xyz;
	vec3 eye = CAMERA_POSITION_WORLD;
	// Drops of three sizes fall at three speeds (RainFall.TRAVEL_WRAP keeps
	// each of them whole when it wraps the way).
	float pace = 0.8 + 0.2 * floor(fract(seed.x * 37.0 + seed.z * 17.0) * 3.0);
	vec3 at = eye + mod(seed * box + travelled * pace - eye, box) - 0.5 * box;
	vec3 along = normalize(velocity);
	vec3 to_eye = eye - at;
	float away = length(to_eye);
	vec3 side = normalize(cross(along, to_eye));
	float span = length(velocity) * pace * streak;
	float width = max(half_width, away * least_angle);
	vec3 world = at + along * (UV.y - 0.5) * span + side * (UV.x - 0.5) * 2.0 * width;
	// Thin out at the box's sides, and where a drop would be on the lens.
	vec3 edge = 1.0 - abs(at - eye) / (0.5 * box);
	fade = smoothstep(0.0, 0.25, min(edge.x, min(edge.y, edge.z))) * smoothstep(0.4, 1.4, away);
	bool indoors = roofed > 0.5 && all(greaterThan(at, room_min)) && all(lessThan(at, room_max));
	if (rain_shelter_rect.w > 0.5) {
		vec2 from_above = (at.xz - rain_shelter_rect.xy) / rain_shelter_rect.z;
		if (all(greaterThan(from_above, vec2(0.0))) && all(lessThan(from_above, vec2(1.0)))) {
			// The whole streak stays above the roof it falls on.
			indoors = indoors || at.y - 0.5 * span < textureLod(rain_shelter, from_above, 0.0).r;
		}
	}
	if (fract(seed.y * 91.0 + seed.x * 13.0) >= amount || indoors || at.y < water_level) {
		// Not falling: all its corners at one point.
		world = eye;
		fade = 0.0;
	}
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	// Lit as a patch of the sky's own light, whichever way the streak leans.
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float ends = smoothstep(0.0, 0.3, UV.y) * (1.0 - smoothstep(0.7, 1.0, UV.y));
	ALBEDO = drop_light;
	ALPHA = opacity * fade * across * ends;
}
