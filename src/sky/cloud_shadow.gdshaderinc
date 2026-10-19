// What stands between a point outdoors and the sun besides the shadow map:
// the clouds and the mountains (terrain, trees, rocks, houses).
//
// Shadows of the cloud layer:
// the coverage of the sky's weather map where the ray toward the sun crosses
// the middle of the cloud layer (cloud_layer.w). Coarse on purpose; it only has to
// move with the clouds the sky draws. A closed layer casts none: there is no
// patch of sun left to tell them from, and what the layer takes of the sun
// is taken from the sun's lamp, for every material alike
// (WeatherSystem.sun_share). Needs the global `sun_direction` declared before
// it (src/sky/atmosphere.gdshaderinc declares it).

#include "res://src/terrain/sun_shadow.gdshaderinc"
#include "res://src/sky/cloud_weather.gdshaderinc"

global uniform vec4 cloud_params;
global uniform vec2 cloud_offset;
// z: how closed the layer is, 0 broken .. 1 without a gap (WeatherSystem.closed_sky).
global uniform vec4 weather_sky;
uniform float cloud_shadow_strength = 0.65;

// 1 in open sunlight, down to 1 - cloud_shadow_strength under a thick cloud
// of a broken sky.
float cloud_cover_visibility(vec3 p) {
	vec3 to_sun = sun_direction;
	float broken = 1.0 - weather_sky.z;
	if (to_sun.y <= 0.02 || cloud_shadow_strength * broken <= 0.0) {
		return 1.0;
	}
	vec2 at = p.xz + to_sun.xz / to_sun.y * (cloud_layer.w - p.y);
	vec4 weather = texture(cloud_weather, (at * 0.001 + cloud_offset) * cloud_layer.z);
	float coverage = clamp(cloud_params.x + (weather.r - 0.5) * 0.95, 0.0, 1.0);
	float cover = smoothstep(0.35, 0.75, coverage * weather.b * 1.25);
	return 1.0 - cover * cloud_shadow_strength * broken;
}

// The clouds and the ridges together, for a point anywhere above the ground.
float cloud_sun_visibility(vec3 p) {
	return cloud_cover_visibility(p) * ridge_sun_visibility(p);
}
