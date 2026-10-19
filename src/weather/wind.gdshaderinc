// The wind over the ground, one field for every plant (WeatherSystem writes
// the global `wind`, pack_wind). The gusts are those that raise the lake's
// waves (water.gdshader, vertex(): the weather map at LAKE_GUST_SCALE), with
// a finer field that travels downwind across the meadow into the forest.
#ifndef WIND_GDSHADERINC
#define WIND_GDSHADERINC

#include "res://src/sky/cloud_weather.gdshaderinc"

// x, y: where the wind blows to on the ground (x, z), unit length; z:
// strength (0 calm .. 1 fresh breeze .. 2.2 storm); w: speed, m/s.
global uniform vec4 wind;
// Metres the travelling gusts have gone downwind (x, z), wrapped at ten
// repeats of their field: WeatherSystem adds the wind of each frame, so a
// wind that turns or changes its speed carries them on from where they are.
global uniform vec2 wind_drift;

// Metres one repeat of the travelling gusts spans (WeatherSystem.GUST_WRAP: ten of them).
const float GUST_SCALE = 180.0;
// Metres one repeat of the lake's gusts spans (water.gdshader, frozen).
const float LAKE_GUST_SCALE = 1700.0;
// What wind_strength() gives on average in a fresh breeze (6 m/s): a plant
// that sways by a set amount sways by it there, more in a storm, less in a calm.
const float BREEZE_STRENGTH = 0.4;

// 0.72 .. 1.28: the lake's gusts at a ground position, as its waves take them.
float lake_gust(vec2 xz) {
	return 0.72 + 0.56 * textureLod(cloud_weather, xz / LAKE_GUST_SCALE, 0.0).r;
}

// 0..1 travelling gust strength at a ground position.
float wind_gust(vec2 xz) {
	vec2 uv = (xz - wind_drift) / GUST_SCALE;
	float a = texture(cloud_weather, uv).r;
	float b = texture(cloud_weather, uv * 2.7 + vec2(0.31, 0.77)).r;
	return clamp((a * 0.7 + b * 0.3 - 0.35) * 2.2, 0.0, 1.0);
}

// What bends a plant at a ground position: pressure grows with the square of
// the speed, and `wind.z` is already that.
float wind_strength(vec2 xz) {
	return wind.z * lake_gust(xz) * (0.45 + 0.9 * wind_gust(xz));
}

#endif
