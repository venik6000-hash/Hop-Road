#[compute]
#version 450
// Camera-lens effects on the HDR image after transparent geometry:
//  - under the lake surface the eye ray loses light by Beer-Lambert extinction
//    and gains the water body's in-scattered light, as the surface shader does
//    for rays seen from above;
//  - a dark meniscus where the surface crosses the lens;
//  - natural cos^4 vignetting.
// Whether the lens is under water is decided per pixel at the near plane,
// against the FFT wave surface of this very frame (the textures the surface
// shader displaces with), so the waterline sweeps across the picture exactly
// where the drawn surface crosses the lens.
#include "../sky/atmosphere_common.glslinc"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict image2D color_image;
layout(set = 0, binding = 1) uniform sampler2D depth_texture;
layout(set = 0, binding = 2) uniform sampler2D skyview_lut;
layout(set = 0, binding = 3) uniform sampler2D transmittance_lut;
layout(set = 0, binding = 5) uniform sampler2DArray displacement;
#include "lens_params.glslinc"

vec3 sky_zenith() {
	vec2 lut = vec2(textureSize(skyview_lut, 0));
	return textureLod(skyview_lut, skyview_uv(p.sun.w, 1.0, 1.0, false, lut), 0.0).rgb * p.sun_scale.rgb;
}

vec3 sun_at_surface() {
	float mu = p.sun.y;
	vec2 uv = transmittance_uv(p.sun.w, mu);
	uv = (uv * vec2(255.0, 63.0) + 0.5) / vec2(256.0, 64.0);
	return textureLod(transmittance_lut, uv, 0.0).rgb * p.sun_scale.rgb * max(mu, 0.0);
}

vec3 wave_offset(vec2 xz) {
	vec3 sum = vec3(0.0);
	for (int c = 0; c < 3; c++) {
		sum += textureLod(displacement, vec3(xz / p.tiles[c], float(c)), 0.0).xyz * p.weights[c];
	}
	return sum;
}

// Height of the displaced surface above x/z: find the grid point that the
// horizontal displacement carries there (fixed-point, as fft_query does).
float surface_height(vec2 target) {
	vec2 origin = target;
	for (int i = 0; i < 4; i++) {
		origin = target - wave_offset(origin).xz;
	}
	return p.surface.x + wave_offset(origin).y;
}

void main() {
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
	if (pixel.x >= int(p.size.x) || pixel.y >= int(p.size.y)) {
		return;
	}
	vec2 uv = (vec2(pixel) + 0.5) * p.size.zw;
	vec4 color = imageLoad(color_image, pixel);

	float raw = textureLod(depth_texture, uv, 0.0).r;
	// Image rows run top-down; the projection's NDC y runs bottom-up.
	vec4 view_h = p.inv_projection * vec4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, raw, 1.0);
	vec3 view_pos = view_h.xyz / view_h.w;
	vec3 view_dir = normalize(view_pos);
	vec3 eye = p.camera[3].xyz;
	vec3 dir = normalize(mat3(p.camera) * view_dir);
	float scene = length(view_pos);

	vec3 result = color.rgb;
	// surface.y is 1 when the CPU has proven that every wave crest lies more
	// than 20 meniscus half widths below the lens. Then the lens is not under
	// water and the meniscus factor below is exactly 1: the whole water block
	// leaves the colour as it is.
	if (p.surface.y < 0.5) {
		vec3 lens = eye + dir * p.surface.w;
		float level = surface_height(lens.xz);
		float submerged = level - lens.y;
		if (submerged > 0.0) {
			// Path radiance of deep water: the light reaching the camera's depth
			// times the single-scattering albedo b/c, strongly forward-peaked, so
			// looking up toward the lit surface is far brighter than looking down.
			float depth_here = max(level - eye.y, 0.0);
			vec3 irradiance = sky_zenith() * PI * 0.8 + sun_at_surface();
			vec3 albedo = p.scatter.rgb / p.extinction.rgb;
			float toward_light = dir.y * 0.5 + 0.5;
			vec3 body = albedo * irradiance * 0.08 * exp(-p.extinction.rgb * depth_here * 1.1)
				* mix(0.35, 2.6, toward_light * toward_light);
			vec3 transmit = exp(-p.extinction.rgb * min(scene, 500.0));
			result = result * transmit + body * (1.0 - transmit);
		}
		float band = submerged / max(p.scatter.a, 1e-5);
		result *= 1.0 - 0.75 * exp(-band * band);
	}

	float axis = max(-view_dir.z, 0.0);
	result *= mix(1.0, axis * axis * axis * axis, p.sun_scale.a);

	int debug = int(p.extinction.a + 0.5);
	if (debug == 1) {
		// World position from depth: 2 m checker, red below the lake level.
		vec3 world = eye + dir * scene;
		vec2 cell = floor(world.xz * 0.5);
		float checker = mod(cell.x + cell.y, 2.0);
		result = vec3(world.y < 0.72 ? 1.0 : 0.1, checker * 0.8, fract(world.y) * 0.5) * 0.5;
	} else if (debug == 2) {
		result = vec3(raw * 20.0, fract(raw * 2000.0), 0.0);
	} else if (debug == 3) {
		result = abs(view_dir) * 0.5;
	} else if (debug == 4) {
		result = vec3(fract(scene / 10.0), clamp(scene / 200.0, 0.0, 1.0), view_h.w > 0.0 ? 0.5 : 0.0);
	}
	imageStore(color_image, pixel, vec4(result, color.a));
}
