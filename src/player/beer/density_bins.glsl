#[compute]
#version 450
// Invert the old tile->all-particles search. Each live particle marks only
// overlapping tiles; a 512-bit mask bounds memory and removes atomic ordering.
layout(local_size_x=64) in;
struct Particle { vec4 position; vec4 velocity; vec4 predicted; vec4 correction; vec4 constraint; };
layout(set=0,binding=0,std430) readonly restrict buffer Particles { Particle p[]; };
layout(set=0,binding=1,std430) restrict buffer Bins { uint bits[]; };
layout(push_constant,std430) uniform Params { vec4 low; vec4 extent; vec4 control; } u;

void main() {
    uint i=gl_GlobalInvocationID.x;
    if(i>=uint(u.control.x)||p[i].position.w==0.0) return;
    ivec3 field_size=ivec3(u.low.w,u.extent.w,u.control.z);
    ivec3 tiles=field_size/4;
    vec3 voxel=u.extent.xyz/vec3(field_size);
    vec3 tile_size=u.extent.xyz/vec3(tiles);
    float radius=u.control.y;
    // The extra tile on each side covers rounding in the inverse mapping.
    // The original sphere/AABB predicate below still selects exact membership.
    ivec3 lo=clamp(ivec3(floor((p[i].position.xyz-vec3(radius)-u.low.xyz)/tile_size))-ivec3(1),ivec3(0),tiles-1);
    ivec3 hi=clamp(ivec3(floor((p[i].position.xyz+vec3(radius)-u.low.xyz)/tile_size))+ivec3(1),ivec3(0),tiles-1);
    for(int z=lo.z;z<=hi.z;z++) {
        for(int y=lo.y;y<=hi.y;y++) {
            for(int x=lo.x;x<=hi.x;x++) {
                vec3 centre=u.low.xyz+(vec3(x,y,z)*4.0+2.0)*voxel;
                vec3 d=max(abs(p[i].position.xyz-centre)-voxel*2.0,vec3(0));
                if(dot(d,d)<radius*radius) {
                    uint tile=uint((z*tiles.y+y)*tiles.x+x);
                    atomicOr(bits[tile*16u+i/32u],1u<<(i%32u));
                }
            }
        }
    }
}
