shader_type spatial;
// Flames of a hearth's fire bed (FireBed): cards of a MultiMesh turned to the
// eye about their upright axis, each playing the CC0 flame flipbook at its own
// speed and phase. The flipbook's brightness is mapped to the colour of a
// wood flame and added to the picture; flames fade where they enter the logs
// and the brick, at their foot and at their sides, so no card edge shows.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;

uniform sampler2D fire_atlas : source_color, filter_linear, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
// Fire strength 0..1 (FireBed.burn): flames grow with it, the weak ones go out first.
uniform float fire : hint_range(0.0, 1.0) = 1.0;
uniform float intensity = 1.1;
// Distance over which a flame fades into what is behind it, m.
uniform float softness = 0.025;
// The draught's pull on the flames' tops toward the back of the hearth
// (the MultiMesh's Z), m per m of height.
uniform float lean = 0.18;

varying float v_speed;
varying float v_phase;
varying float v_bright;

void vertex() {
	// INSTANCE_CUSTOM: phase, flipbook frames per second, the fire it needs, ±brightness (sign flips the card).
	v_phase = INSTANCE_CUSTOM.x;
	v_speed = INSTANCE_CUSTOM.y;
	float presence = clamp((fire - INSTANCE_CUSTOM.z) / 0.2, 0.0, 1.0);
	v_bright = abs(INSTANCE_CUSTOM.w);
	if (INSTANCE_CUSTOM.w < 0.0) {
		UV.x = 1.0 - UV.x;
	}
	vec3 origin = MODEL_MATRIX[3].xyz;
	float width = length(MODEL_MATRIX[0].xyz);
	float height = length(MODEL_MATRIX[1].xyz) * presence * mix(0.45, 1.0, fire);
	vec3 to_eye = CAMERA_POSITION_WORLD - origin;
	vec3 view = normalize(to_eye);
	// Seen from above, an upright card would turn edge-on: it leans back
	// toward the eye part of the way.
	vec3 upright = normalize(MODEL_MATRIX[1].xyz);
	vec3 facing = upright - view * dot(upright, view);
	vec3 up = normalize(mix(upright, normalize(facing + upright * 0.001), 0.75));
	vec3 right = normalize(cross(up, to_eye));
	float rise = VERTEX.y;
	// The top licks and sways; the foot stays on the log.
	float sway = sin(TIME * 1.7 + v_phase) * 0.6 + sin(TIME * 3.1 + v_phase * 1.7) * 0.4;
	vec3 world = origin + right * (VERTEX.x * width * presence + sway * 0.025 * rise * rise * height)
			+ up * rise * height + normalize(MODEL_MATRIX[2].xyz) * lean * rise * rise * height;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = (VIEW_MATRIX * vec4(normalize(to_eye), 0.0)).xyz;
}

vec4 frame_sample(float frame, vec2 uv) {
	vec2 cell = vec2(mod(frame, 16.0), floor(frame / 16.0));
	vec2 inset = vec2(0.5 / 64.0, 0.5 / 128.0);
	return texture(fire_atlas, (cell + mix(inset, vec2(1.0) - inset, uv)) / vec2(16.0, 4.0));
}

// Colour of a wood flame by the flipbook's brightness: deep red at the
// thin edges, orange in the body, yellow only in the thick core.
vec3 flame_colour(float l) {
	vec3 c = mix(vec3(0.45, 0.04, 0.0), vec3(1.0, 0.26, 0.02), smoothstep(0.08, 0.5, l));
	return mix(c, vec3(1.0, 0.5, 0.12), smoothstep(0.6, 1.0, l));
}

void fragment() {
	vec2 uv = UV;
	// Turbulence: the upper flame wavers more than its root.
	float wave = sin(uv.y * 9.0 - TIME * 6.0 + v_phase) * 0.5 + sin(uv.y * 17.0 - TIME * 9.5 + v_phase * 2.3) * 0.25;
	uv.x += wave * 0.035 * (1.0 - uv.y);
	float clock = mod(TIME * v_speed + v_phase, 64.0);
	vec4 a = frame_sample(floor(clock), uv);
	vec4 b = frame_sample(mod(floor(clock) + 1.0, 64.0), uv);
	vec3 rgb = mix(a.rgb, b.rgb, fract(clock));
	float l = max(rgb.r, max(rgb.g, rgb.b)) * v_bright;
	float edge = smoothstep(0.0, 0.14, UV.x) * smoothstep(1.0, 0.86, UV.x) * smoothstep(1.0, 0.82, UV.y) * smoothstep(0.0, 0.08, UV.y);
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	behind.xyz /= behind.w;
	float soft = clamp((VERTEX.z - behind.z) / softness, 0.0, 1.0);
	float body = smoothstep(0.03, 0.35, l);
	ALBEDO = flame_colour(l) * intensity * (0.2 + 0.8 * l * l);
	ALPHA = body * edge * soft;
}
