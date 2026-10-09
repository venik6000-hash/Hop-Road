#[compute]
#version 450
layout(local_size_x=8,local_size_y=8,local_size_z=1) in;
layout(set=0,binding=0) uniform sampler2D source_color;
layout(set=0,binding=1) uniform sampler2D source_depth;
layout(rgba16f,set=0,binding=2) uniform restrict writeonly image2D target;
layout(push_constant,std430) uniform Params { mat4 inverse_projection; } p;
void main(){
 ivec2 id=ivec2(gl_GlobalInvocationID.xy); ivec2 size=imageSize(target);
 if(any(greaterThanEqual(id,size)))return;
 vec2 uv=(vec2(id)+0.5)/vec2(size);
 float raw=texture(source_depth,uv).r;
 vec4 view=p.inverse_projection*vec4(uv*2.0-1.0,raw,1.0);
 float depth=raw>0.000001 ? max(0.0,-view.z/view.w) : 0.0;
 imageStore(target,id,vec4(texture(source_color,uv).rgb,depth));
}
