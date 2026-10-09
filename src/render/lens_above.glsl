#[compute]
#version 450
// Above-water, non-debug, single-view perspective specialization.
// Keeps the same inverse-projection ray and cos^4 expression. Depth only
// scales perspective rays, so near-plane reconstruction needs no depth read.
layout(local_size_x=8,local_size_y=8)in;
layout(rgba16f,set=0,binding=0)uniform restrict image2D color_image;
#include "lens_params.glslinc"

void main(){
 ivec2 pixel=ivec2(gl_GlobalInvocationID.xy);
 if(pixel.x>=int(p.size.x)||pixel.y>=int(p.size.y))return;
 vec2 uv=(vec2(pixel)+0.5)*p.size.zw;
 vec4 color=imageLoad(color_image,pixel);
 vec4 view_h=p.inv_projection*vec4(uv.x*2.0-1.0,1.0-uv.y*2.0,1.0,1.0);
 vec3 view_pos=view_h.xyz/view_h.w;
 vec3 view_dir=normalize(view_pos);
 float axis=max(-view_dir.z,0.0);
 vec3 result=color.rgb*mix(1.0,axis*axis*axis*axis,p.sun_scale.a);
 imageStore(color_image,pixel,vec4(result,color.a));
}
