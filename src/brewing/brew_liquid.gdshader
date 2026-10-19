shader_type spatial;
// What stands in a brewery vessel: water, wort, mash. `boil` rolls the
// surface the way a copper over a fire rolls: the wort wells up over the
// hottest middle and runs out to the wall, domes swell and burst in
// clusters, and the hot break (`foam`) lies as a torn blanket that drifts out
// and gathers at the wall. The mash is thick and dull (`thick`). A stream falling
// in (`impacts`) rings the face and froths it where it lands. Where the face
// meets the wall it climbs a little and catches the light; wort leaves a
// line of scum there.
render_mode specular_schlick_ggx, cull_disabled;

uniform vec4 tint : source_color = vec4(0.4, 0.22, 0.06, 1.0);
uniform float boil : hint_range(0.0, 1.0) = 0.0;
uniform float foam : hint_range(0.0, 1.0) = 0.0;
uniform float thick : hint_range(0.0, 1.0) = 0.0;
// The vessel: the middle of its face (world), and its radius, or the half
// sides of a rectangular one (`extent.y` > 0).
uniform vec3 centre = vec3(0.0);
uniform vec2 extent = vec2(0.5, 0.0);
// The building's X along the ground (world xz): the sides of a rectangle.
uniform vec2 across = vec2(1.0, 0.0);
// Wort leaves scum at the wall, water does not (0..1).
uniform float scum = 0.0;
// Streams falling in: world xz, the height unused, w their strength (0..1).
uniform vec4 impacts[2];

varying vec3 world;

float hash(vec2 p) {
	vec3 q = fract(p.xyx * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return noise(p) * 0.55 + noise(p * 2.1 + 3.7) * 0.3 + noise(p * 4.3 - 1.9) * 0.15;
}

// Distance to the nearest of jittered points: the round cells of foam pores.
float cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float best = 2.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 jitter = vec2(hash(i + o), hash(i + o + 17.3));
			best = min(best, length(o + jitter - f));
		}
	}
	return best;
}

// Domes of one size: in each cell one swells and bursts, and a ring runs
// out from where it burst. Cells are let through where `crowd` is high.
float domes(vec2 p, float time, float crowd, float size) {
	vec2 cell = floor(p);
	float seed = hash(cell);
	if (seed > crowd) {
		return 0.0;
	}
	float life = fract(time * (0.7 + seed * 0.9) + seed * 7.0);
	vec2 off = vec2(hash(cell + 3.1), hash(cell + 5.7)) - 0.5;
	float d = length(fract(p) - 0.5 - off * 0.45);
	float grow = smoothstep(0.0, 0.8, life);
	float r = size * (0.4 + 0.6 * grow);
	float dome = life < 0.8 ? sqrt(max(0.0, 1.0 - (d * d) / (r * r))) * grow : 0.0;
	float after = clamp((life - 0.8) / 0.2, 0.0, 1.0);
	float ring = life >= 0.8 ? smoothstep(0.05, 0.0, abs(d - r * (1.0 + after * 1.5))) * (1.0 - after) * 0.5 : 0.0;
	return dome + ring;
}

// How far out from the middle, 1 at the wall.
float out_to_wall(vec2 p) {
	vec2 d = p - centre.xz;
	if (extent.y > 0.0) {
		vec2 local = vec2(dot(d, across), dot(d, vec2(-across.y, across.x)));
		return max(abs(local.x) / extent.x, abs(local.y) / extent.y);
	}
	return length(d) / max(extent.x, 0.01);
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world.xz;
	float t = TIME;
	float wall = out_to_wall(p);
	// The roll: the face runs out from the middle. Two phases of a flow map
	// half a cycle apart keep the pattern from stretching.
	// Slow over the middle where it wells up, fastest half way out.
	vec2 from_middle = p - centre.xz;
	vec2 away = extent.y > 0.0 ? vec2(0.0) : from_middle / max(extent.x, 0.01) * smoothstep(1.1, 0.4, wall) * 0.35 * boil;
	float cycle = t * 0.35;
	float phase_a = fract(cycle);
	float phase_b = fract(cycle + 0.5);
	float blend = abs(1.0 - 2.0 * phase_a);
	vec2 pa = p - away * phase_a / 0.35;
	vec2 pb = p - away * phase_b / 0.35 + 0.37;
	float roll = mix(fbm(pa * 7.0 + t * 0.4), fbm(pb * 7.0 + t * 0.4), blend);
	// Domes crowd where the heat comes up: over the middle and in drifting clusters.
	float crowd = boil * clamp(1.15 - wall * 0.6, 0.0, 1.0) * smoothstep(0.25, 0.75, noise(p * 2.5 + vec2(t * 0.25, -t * 0.18)) + 0.25);
	float bubbling = domes(p * 9.0, t * 1.4, crowd, 0.42) + domes(p * 23.0 + 7.0, t * 2.3, crowd * 0.9, 0.38) * 0.5;
	float calm = noise(p * 6.0 + t * 0.05) * 0.08;
	float h = mix(calm, roll * 0.9 + bubbling, boil);
	// Mash: grist in water, lumps and husks break its face.
	h += thick * (noise(p * 45.0) * 0.6 + noise(p * 140.0) * 0.4);
	// Streams falling in ring the face and froth it.
	float froth = 0.0;
	for (int i = 0; i < 2; i++) {
		vec4 hit = impacts[i];
		if (hit.w <= 0.0) {
			continue;
		}
		float d = length(p - hit.xz);
		h += sin(d * 70.0 - t * 22.0) * exp(-d * 9.0) * 0.35 * hit.w;
		float bubbles_up = smoothstep(0.4, 0.75, noise(p * 90.0 + t * 4.0));
		froth = max(froth, hit.w * smoothstep(0.07 + 0.04 * hit.w, 0.01, d) * bubbles_up);
	}
	// The meniscus: the face climbs the wall in the last centimetre.
	float rim = smoothstep(0.965, 1.0, wall);
	h += rim * 0.6;
	// The hot break: a blanket of foam that rides the roll out to the wall,
	// torn open where the boil wells up. Little foam leaves islands at the wall.
	float cover_a = fbm(pa * 4.0 + t * 0.03) * 0.7 + fbm(pa * 13.0) * 0.3;
	float cover_b = fbm(pb * 4.0 + t * 0.03) * 0.7 + fbm(pb * 13.0) * 0.3;
	float cover = mix(cover_a, cover_b, blend) + 0.35 * smoothstep(0.6, 1.0, wall) * smoothstep(0.1, 0.5, foam);
	float torn = 1.0 - smoothstep(0.3, 0.9, bubbling) * boil;
	float edge = 1.0 - foam * 0.85;
	float head = foam > 0.0 ? smoothstep(edge, edge + 0.12, cover) * torn : 0.0;
	float line = scum * rim * smoothstep(0.45, 0.75, noise(p * 70.0)) * 0.6;
	float white = max(max(head, line), froth * 0.7);
	h += white * 0.5;
	// The face from the height: screen derivatives of the displaced point.
	float lift = mix(mix(0.004, 0.016, boil), 0.006, thick);
	vec3 displaced = world + vec3(0.0, h * lift, 0.0);
	vec3 n = normalize(cross(dFdy(displaced), dFdx(displaced)));
	if (n.y < 0.0) {
		n = -n;
	}
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;
	// Foam: cream, its pores darker; the wort shows darker in the gaps.
	// Pores of the foam: fine bubbles, and a few large ones about to burst.
	float pores = smoothstep(0.08, 0.25, cells(p * 140.0 + t * 0.2)) * mix(0.7, 1.0, smoothstep(0.1, 0.3, cells(p * 40.0 - t * 0.1)));
	// Hot break is tan, not white; froth on wort takes the wort's colour.
	vec3 cream = mix(vec3(0.66, 0.53, 0.34), tint.rgb * 1.6 + 0.25, 0.25) * mix(0.75, 1.0, pores) * mix(0.85, 1.05, noise(p * 30.0));
	float husk = noise(p * 260.0);
	vec3 body = tint.rgb * mix(1.0, 0.7 + 0.5 * husk, thick) * mix(1.0, 0.85, boil * (1.0 - roll));
	ALBEDO = mix(body, cream, white);
	ROUGHNESS = mix(mix(mix(0.03, 0.12, boil), 0.75, thick), 0.65, white);
	SPECULAR = mix(0.5, 0.2, white);
}
