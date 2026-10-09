// Light reaching what lies under the lake surface: the terrain's bed and the
// boulders in the shallows. Sky light comes down through the water and is
// dimmed by it (the albedo carries that, so every light is dimmed); the sun
// comes along its refracted, longer path and is focused into caustics by the
// very waves drawn on the surface. Needs the global `sun_direction` declared
// before it. WaterSystem sets the optics on the materials that include it.

global uniform sampler2DArray water_derivatives : filter_linear_mipmap, repeat_enable;
global uniform vec4 water_tiles;
global uniform vec4 water_cascade_weights;
uniform vec3 water_absorption = vec3(0.42, 0.075, 0.036);
uniform vec3 water_scattering = vec3(0.041, 0.046, 0.052);

// Caustics from the FFT waves. Refracted sunlight lands displaced by
// depth * (1 - 1/1.33) * slope, so the light density on the bed is
// 1 / det(I + depth * k * Hessian(h)): bright where the wave curvature focuses
// it, and the pattern moves with the very waves drawn on the surface. Only
// the two short cascades curve enough to matter.
float caustics(vec2 xz, float depth, float wave_scale) {
	const float SHIFT = 0.25;
	const float STEP = 0.06;
	mat2 hessian = mat2(0.0);
	for (int c = 1; c < 3; c++) {
		float tile = water_tiles[c];
		vec4 x0 = texture(water_derivatives, vec3((xz - vec2(STEP, 0.0)) / tile, float(c)));
		vec4 x1 = texture(water_derivatives, vec3((xz + vec2(STEP, 0.0)) / tile, float(c)));
		vec4 z0 = texture(water_derivatives, vec3((xz - vec2(0.0, STEP)) / tile, float(c)));
		vec4 z1 = texture(water_derivatives, vec3((xz + vec2(0.0, STEP)) / tile, float(c)));
		// Slopes of the displaced surface (as the water shader forms them).
		vec2 sx0 = x0.xy / (1.0 + x0.zw);
		vec2 sx1 = x1.xy / (1.0 + x1.zw);
		vec2 sz0 = z0.xy / (1.0 + z0.zw);
		vec2 sz1 = z1.xy / (1.0 + z1.zw);
		hessian += mat2((sx1 - sx0) / (2.0 * STEP), (sz1 - sz0) / (2.0 * STEP)) * water_cascade_weights[c];
	}
	mat2 jacobian = mat2(1.0) + hessian * (depth * SHIFT * wave_scale);
	return clamp(1.0 / max(abs(determinant(jacobian)), 0.12), 0.0, 5.0);
}

// For a point `depth` (> 0) metres under the surface, seen from `dist` metres:
// returns the factor on its albedo (the sky light straight down), and in
// `sun_tint` the sunlight that reaches it relative to that. `gust` scales
// the waves that focus the caustics.
vec3 underwater_light(vec2 xz, float depth, float dist, float gust, out vec3 sun_tint) {
	vec3 k_down = (water_absorption + water_scattering * 0.3) * 1.2;
	vec3 into_water = refract(-sun_direction, vec3(0.0, 1.0, 0.0), 1.0 / 1.333);
	float path = depth / max(-into_water.y, 0.2);
	vec2 entry = xz - into_water.xz * path;
	float shore = mix(0.08, 1.0, smoothstep(0.0, 7.0, depth));
	// Far away the pattern would only alias; deep down it spreads out and
	// the scattered sky light washes it: in a mountain lake the dancing
	// light belongs to the first few metres.
	float weight = (1.0 - smoothstep(25.0, 70.0, dist)) * (1.0 - smoothstep(3.0, 10.0, depth));
	// The weight is exactly 0 beyond 70 m or below 10 m, and there the mix
	// below gives exactly 1. Skip the fetches only where the whole 2x2 pixel
	// quad has weight 0, so the fetches that do run see the same neighbours
	// (and mip levels) as before. Two fine-derivative steps carry a nonzero
	// weight to the row, the column and then the diagonal neighbour.
	float quad_row_col = weight + abs(dFdxFine(weight)) + abs(dFdyFine(weight));
	float quad_any = quad_row_col + abs(dFdxFine(quad_row_col)) + abs(dFdyFine(quad_row_col));
	float focus = 1.0;
	if (weight > 0.0 || quad_any > 0.0) {
		focus = mix(1.0, caustics(entry, depth, shore * gust), weight);
	}
	focus = min(focus, mix(4.0, 2.2, smoothstep(1.5, 6.0, depth)));
	sun_tint = exp(-k_down * (path - depth)) * focus;
	return exp(-k_down * depth);
}
