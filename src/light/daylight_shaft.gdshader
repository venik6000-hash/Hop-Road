shader_type spatial;
// The sun in the dusty air of a room (Daylight). Each opening has a
// hull: its outline carried along the sun's way into the room. The eye's ray
// is cut to the part that lies in the hull and in front of what is seen, and
// the lit air along it is summed, so the beam is the same soft body from
// every side.
// NORMAL is the wall's, into the room; UV2.x is 0 on the hull's end in the
// wall and 1 on its far end; CUSTOM0 the middle of the sill on the wall's
// line and half the opening's width; CUSTOM1 the opening's height, the
// height of the springing over the sill and the opening's number.
render_mode unshaded, blend_add, cull_front, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;

const int STEPS = 16;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
// The sun's way through the room (a unit vector) and how far the beam is followed, m.
uniform vec3 beam = vec3(0.0, -1.0, 0.0);
uniform float reach = 6.5;
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.75);
// The sun's or the moon's light on the air.
uniform float strength = 0.0;
// What a metre of that lit air adds behind each opening to what is seen
// through it: its room's dust (Daylight), less as a door's leaves shut it.
uniform float air[16];

varying vec3 from_eye;
varying flat vec3 eye;
varying flat vec3 inward;
varying flat vec4 sill;
varying flat vec3 shape;

void vertex() {
	inward = NORMAL;
	sill = CUSTOM0;
	shape = CUSTOM1.xyz;
	VERTEX += beam * (reach * UV2.x);
	eye = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	from_eye = VERTEX - eye;
}

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

// Narrows `span` (from, to along the ray) to where at + by * s lies in low..high.
vec2 within(vec2 span, float at, float by, float low, float high) {
	if (abs(by) < 1e-5) {
		return at < low || at > high ? vec2(1.0, 0.0) : span;
	}
	float a = (low - at) / by;
	float b = (high - at) / by;
	return vec2(max(span.x, min(a, b)), min(span.y, max(a, b)));
}

void fragment() {
	float lit = strength * air[int(shape.z + 0.5)];
	// A sun that grazes the wall sends little through its opening.
	float lean = dot(beam, inward);
	float entering = smoothstep(0.05, 0.3, lean);
	if (lit * entering < 0.0005) {
		discard;
	}
	vec3 ray = normalize(from_eye);
	// What is seen behind the air.
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 seen = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene = length(seen.xyz / seen.w);
	// The hull is a box in these three: how far down the beam a point is,
	// and where the beam left the opening (across it, -1..1, and up from
	// the sill, m). All three change evenly along the ray.
	vec3 across = normalize(cross(vec3(0.0, 1.0, 0.0), inward));
	vec3 rel = eye - sill.xyz;
	float along_at = dot(rel, inward) / lean;
	float along_by = dot(ray, inward) / lean;
	vec3 left_at = rel - beam * along_at;
	vec3 left_by = ray - beam * along_by;
	float u_at = dot(left_at, across) / sill.w;
	float u_by = dot(left_by, across) / sill.w;
	vec2 span = vec2(0.0, scene);
	span = within(span, along_at, along_by, 0.0, reach);
	span = within(span, u_at, u_by, -1.0, 1.0);
	span = within(span, left_at.y, left_by.y, 0.0, shape.x);
	if (span.y <= span.x) {
		discard;
	}
	float pace = (span.y - span.x) / float(STEPS);
	// The steps are taken at the same places in every pixel: the beam's
	// edges are soft enough to show no bands, and grain would crawl.
	float sum = 0.0;
	for (int i = 0; i < STEPS; i++) {
		float s = span.x + (float(i) + 0.5) * pace;
		float along = (along_at + along_by * s) / reach;
		float u = abs(u_at + u_by * s);
		float v = left_at.y + left_by.y * s;
		// The sun's disc blurs the opening's outline with the way from it.
		float soft = 0.08 + along * 0.45;
		float inside = smoothstep(0.0, soft, 1.0 - u) * smoothstep(0.0, soft * sill.w, v);
		float head = (v - shape.y) / max(shape.x - shape.y, 0.001);
		if (head > 0.0) {
			// The arched head: half an ellipse over the springing.
			inside *= 1.0 - smoothstep(1.0 - soft, 1.0, length(vec2(u, head)));
		}
		// The air shows less of the beam the further it has gone into the room.
		sum += inside * pow(1.0 - along, 1.5) * smoothstep(0.0, 0.04, along);
	}
	// Dust drifts through the beam.
	vec3 middle = eye + ray * (span.x + span.y) * 0.5;
	float dust = 0.75 + 0.25 * noise(middle * 2.4 + vec3(TIME * 0.05, -TIME * 0.03, TIME * 0.04));
	ALBEDO = sun_color * (lit * entering * sum * pace * dust);
}
