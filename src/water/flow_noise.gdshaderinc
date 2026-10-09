// Noise for running water (stream.gdshader, waterfall.gdshader): gradient
// noise with a quintic fade, and fractal sums whose octaves turn by 37
// degrees as they halve in size, so that no octave lines up with another or
// with the axes of the flow and the grid the noise is built on never shows.

float flow_hash(vec2 p) {
	vec3 q = fract(p.xyx * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

vec2 flow_gradient(vec2 cell) {
	float a = flow_hash(cell) * 6.2831853;
	return vec2(cos(a), sin(a));
}

// Gradient noise, 0..1 around 0.5.
float flow_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(flow_gradient(i), f);
	float b = dot(flow_gradient(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(flow_gradient(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(flow_gradient(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return 0.5 + 0.7071 * mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float flow_fbm(vec2 p, int octaves) {
	// Each octave turned by 37 degrees and twice as fine.
	const mat2 turn = mat2(vec2(1.5973, 1.2036), vec2(-1.2036, 1.5973));
	float sum = 0.0;
	float amp = 0.5;
	float norm = 0.0;
	for (int i = 0; i < octaves; i++) {
		sum += flow_noise(p) * amp;
		norm += amp;
		p = turn * p + vec2(17.1, 3.7);
		amp *= 0.5;
	}
	return sum / norm;
}

// A normal bumped by `relief` (metres along `normal`), from the screen-space
// derivatives of both (Mikkelsen's surface gradient): for procedural relief
// that has no tangent-space derivatives of its own.
vec3 flow_bump(vec3 vertex, vec3 normal, float relief) {
	vec3 dpdx = dFdx(vertex);
	vec3 dpdy = dFdy(vertex);
	vec3 r1 = cross(dpdy, normal);
	vec3 r2 = cross(normal, dpdx);
	float det = dot(dpdx, r1);
	return normalize(abs(det) * normal - sign(det) * (dFdx(relief) * r1 + dFdy(relief) * r2));
}
