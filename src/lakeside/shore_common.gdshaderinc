// Regional lake shore; outside the region all added effects are zero.
global uniform sampler2D lake_shore_state : filter_linear, repeat_disable;
global uniform vec4 lake_shore_region;
global uniform vec2 lake_shore_clock; // seconds, amplitude in metres
vec4 lake_shore_at(vec2 xz) {
 vec2 uv=(xz-lake_shore_region.xy)/max(lake_shore_region.z,1.0);
 float edge=smoothstep(0.0,0.05,min(min(uv.x,uv.y),min(1.0-uv.x,1.0-uv.y)));
 return texture(lake_shore_state,clamp(uv,vec2(0.0),vec2(1.0)))*edge;
}
float lake_runup(vec2 xz,float depth){
 vec2 uv=(xz-lake_shore_region.xy)/max(lake_shore_region.z,1.0);
 float edge=smoothstep(0.0,0.05,min(min(uv.x,uv.y),min(1.0-uv.x,1.0-uv.y)));
 return sin(lake_shore_clock.x*1.25-depth*3.0)*lake_shore_clock.y*exp(-abs(depth)*1.5)*edge;
}
