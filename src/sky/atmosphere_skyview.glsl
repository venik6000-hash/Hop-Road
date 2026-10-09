#[compute]
#version 450
// Sky-view LUT: sky radiance per unit top-of-atmosphere sun illuminance, for
// the current sun elevation and viewer altitude (Hillaire 2020, section 5.3).
#include "atmosphere_common.glslinc"
#define USE_MULTISCATTER_LUT

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0) uniform sampler2D transmittance_lut;
layout(set = 0, binding = 1) uniform sampler2D multiscatter_lut;
layout(rgba16f, set = 0, binding = 2) uniform restrict writeonly image2D out_lut;
layout(push_constant, std430) uniform Params {
	vec4 tune;
	vec4 size;      // xy = LUT size
	vec4 view;      // x = sun zenith cosine, y = viewer radius (km)
} params;

#include "atmosphere_integrate.glslinc"

void main() {
	ivec2 texel = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(texel, ivec2(params.size.xy)))) {
		return;
	}
	vec2 uv = (vec2(texel) + 0.5) / params.size.xy;
	uv = (uv * params.size.xy - 0.5) / (params.size.xy - 1.0);
	float view_height = params.view.y;
	float v_horizon = sqrt(max(view_height * view_height - R_GROUND * R_GROUND, 0.0));
	float beta = acos(clamp(v_horizon / view_height, -1.0, 1.0));
	float zenith_horizon = PI - beta;
	float view_zenith_cos;
	if (uv.y < 0.5) {
		float coord = 1.0 - 2.0 * uv.y;
		coord = 1.0 - coord * coord;
		view_zenith_cos = cos(zenith_horizon * coord);
	} else {
		float coord = uv.y * 2.0 - 1.0;
		view_zenith_cos = cos(zenith_horizon + beta * coord * coord);
	}
	float light_view_cos = -(uv.x * uv.x * 2.0 - 1.0);
	float view_zenith_sin = sqrt(max(0.0, 1.0 - view_zenith_cos * view_zenith_cos));
	vec3 dir = vec3(view_zenith_sin * light_view_cos, view_zenith_cos,
			view_zenith_sin * sqrt(max(0.0, 1.0 - light_view_cos * light_view_cos)));
	float sun_zenith_cos = params.view.x;
	vec3 sun_dir = vec3(sqrt(max(0.0, 1.0 - sun_zenith_cos * sun_zenith_cos)), sun_zenith_cos, 0.0);
	vec3 origin = vec3(0.0, view_height, 0.0);
	ScatterResult result = integrate_scattering(origin, dir, sun_dir, 32, false, false, params.tune);
	imageStore(out_lut, texel, vec4(result.luminance, 1.0));
}
