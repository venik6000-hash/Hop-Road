#[compute]
#version 450
// Persistent wetness and advected foam, adapted from Tidewater ShoreSim (MIT).
layout(local_size_x=8,local_size_y=8,local_size_z=1) in;
layout(set=0,binding=0) uniform sampler2D previous_state;
layout(rgba16f,set=0,binding=1) uniform restrict writeonly image2D next_state;
layout(set=0,binding=2) uniform sampler2D ground;
// Stable published texture: write the same result without a separate copy.
layout(rgba16f,set=0,binding=3) uniform restrict writeonly image2D display_state;
layout(push_constant,std430) uniform Params { vec4 clock; vec4 region; } p;
void main(){
 ivec2 id=ivec2(gl_GlobalInvocationID.xy); ivec2 size=imageSize(next_state);
 if(any(greaterThanEqual(id,size)))return;
 vec2 uv=(vec2(id)+0.5)/vec2(size);
 float h=texture(ground,uv).r; float depth=p.clock.z-h;
 float phase=p.clock.x*1.25-depth*3.0;
 float amplitude=p.clock.w*exp(-abs(depth)*1.5);
 float water=p.clock.z+sin(phase)*amplitude;
 vec2 texel=1.0/vec2(size);
 vec2 gradient=vec2(texture(ground,uv+vec2(texel.x,0)).r-texture(ground,uv-vec2(texel.x,0)).r,
                    texture(ground,uv+vec2(0,texel.y)).r-texture(ground,uv-vec2(0,texel.y)).r);
 vec2 flow=gradient/max(length(gradient),0.05)*cos(phase)*amplitude;
 vec4 old=texture(previous_state,uv-flow*p.clock.y/p.region.z);
 float covered=1.0-smoothstep(0.0,0.035,h-water);
 float band=exp(-abs(depth)*2.0);
 float foam=max(old.r*exp(-p.clock.y/2.6),covered*band*max(0.0,cos(phase))*p.clock.w*1.8);
 float wet=max(texture(previous_state,uv).g*exp(-p.clock.y/28.0),covered);
 float residue=max(texture(previous_state,uv).b*exp(-p.clock.y/5.0),old.r*(1.0-covered));
 vec4 state=vec4(foam,wet,residue,covered);
 imageStore(next_state,id,state);
 imageStore(display_state,id,state);
}
