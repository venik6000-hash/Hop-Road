shader_type spatial;
// A stream falling from `from` to `to` (world space), a ribbon that faces the
// camera. UV.x runs across it, UV.y down it. The fall bends it the way a jet
// leaving a nozzle bends: the drop grows as the square of the way across.
// `grain` turns the liquid into a fall of grains.
render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_schlick_ggx;

uniform vec3 from = vec3(0.0);
uniform vec3 to = vec3(0.0, -1.0, 0.0);
uniform float width = 0.03;
uniform float flow : hint_range(0.0, 1.0) = 1.0;
uniform vec4 tint : source_color = vec4(0.55, 0.32, 0.08, 1.0);
uniform float grain : hint_range(0.0, 1.0) = 0.0;

varying float along;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	float t = UV.y;
	vec3 drop = to - from;
	vec3 centre = from + vec3(drop.x * sqrt(t), drop.y * t, drop.z * sqrt(t));
	vec3 tangent = normalize(vec3(drop.x * 0.5 / sqrt(max(t, 0.02)), drop.y, drop.z * 0.5 / sqrt(max(t, 0.02))));
	vec3 eye = normalize(CAMERA_POSITION_WORLD - centre);
	vec3 side = normalize(cross(tangent, eye));
	// A falling jet thins as it speeds up; a thin flow is a thread. Falling
	// grains spread apart instead.
	float thick = width * mix(0.35, 1.0, flow) * mix(1.0, mix(0.6, 1.6, grain), t);
	// A jet of liquid wavers a little as it falls and spreads where it lands.
	float fall = length(drop);
	thick *= 1.0 + 0.6 * smoothstep(0.85, 1.0, t) * (1.0 - grain);
	centre += side * (noise(vec2(t * fall * 6.0 - TIME * 8.0, 0.5)) - 0.5) * thick * 0.4 * t * (1.0 - grain);
	vec3 world = centre + side * (UV.x - 0.5) * thick;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(normalize(eye + side * (UV.x - 0.5) * 1.6), 0.0)).xyz;
	along = t * fall;
}

void fragment() {
	float across = abs(UV.x - 0.5) * 2.0;
	float streak = noise(vec2(UV.x * 7.0, along * 9.0 - TIME * 6.0));
	if (grain > 0.5) {
		// Kernels in cells a grain wide: fewer of them as the flow thins and
		// as they spread apart on the way down.
		vec2 at = vec2(UV.x * 10.0, along * 70.0 - mod(TIME, 100.0) * 35.0);
		vec2 cell = floor(at);
		float keep = mix(0.3, 0.97, flow) * (1.0 - 0.45 * UV.y) * (1.0 - smoothstep(0.6, 1.0, across));
		vec2 off = (vec2(hash(cell + 1.7), hash(cell + 4.3)) - 0.5) * 0.4;
		vec2 kernel = (fract(at) - 0.5 - off) / vec2(0.3, 0.42);
		float round_off = dot(kernel, kernel);
		if (hash(cell) > keep || round_off > 1.0) {
			discard;
		}
		ALBEDO = tint.rgb * mix(0.65, 1.15, hash(cell + 9.1)) * mix(1.0, 0.7, round_off);
		ROUGHNESS = 0.75;
		SPECULAR = 0.3;
		ALPHA = 1.0;
	} else {
		// A rope of glass that twists as it falls: a bright core, thin edges.
		// A thin flow breaks into drops; the jet froths where it lands.
		float twist = noise(vec2(UV.x * 3.0 + along * 4.0, along * 12.0 - TIME * 9.0));
		float edge = smoothstep(1.0, 0.55 - 0.25 * twist, across);
		if (flow < 0.35 && noise(vec2(0.5, along * 25.0 - TIME * 18.0)) > flow / 0.35 + 0.15) {
			discard;
		}
		float land = smoothstep(0.85, 1.0, UV.y) * flow;
		vec3 froth = mix(tint.rgb, vec3(0.86, 0.83, 0.76), 0.55);
		ALBEDO = mix(tint.rgb * mix(0.75, 1.2, streak * twist + 0.3), froth, land * 0.6);
		ROUGHNESS = mix(0.04, 0.35, land);
		SPECULAR = 0.7;
		ALPHA = clamp(tint.a * edge * mix(0.8, 1.0, streak) + land * 0.3, 0.0, 1.0);
	}
}
