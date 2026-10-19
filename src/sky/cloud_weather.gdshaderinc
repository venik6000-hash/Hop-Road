// The sky's weather map (assets/generated/sky/cloud_weather.png): r the
// clouds' coverage, b their type. SkySystem writes the global once; the sky
// marches its clouds over it, the ground reads their shadows from it and the
// wind its gusts (src/weather/wind.gdshaderinc). The cloud layer it maps
// (SkySystem.cloud_layer()): x its base above y = 0, km; y its thickness, km;
// z the map's repeats a km; w the height of its middle, m.
#ifndef CLOUD_WEATHER_GDSHADERINC
#define CLOUD_WEATHER_GDSHADERINC

global uniform sampler2D cloud_weather : filter_linear_mipmap, repeat_enable;
global uniform vec4 cloud_layer;

#endif
