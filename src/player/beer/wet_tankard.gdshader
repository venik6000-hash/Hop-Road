shader_type spatial;
render_mode cull_disabled;
// The tankard's own maps under a wet layer: beer run down from the rim, a wet
// inner wall and drops of condensation on the iron. Wetness follows the head
// of foam: a fresh pour soaks the mug, then it dries.
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_map : hint_default_white, filter_linear_mipmap_anisotropic;
uniform float wetness : hint_range(0.0, 1.0) = 1.0;
uniform float rim_height = 0.24;
uniform float inner_radius = 0.095;
uniform float body_radius = 0.118;
varying vec3 local_pos;
void vertex() { local_pos=VERTEX; }
float hash2(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
// Runs of beer from the rim: a few slots per turn, each with its own width and
// length, narrowing as it runs down.
float streaks(float angle, float height) {
    float turns=angle/TAU*32.0;
    float slot=floor(turns), f=fract(turns);
    if(hash2(vec2(slot,3.0))>0.65) return 0.0;
    float centre=0.3+0.4*hash2(vec2(slot,11.0));
    float width=0.2+0.25*hash2(vec2(slot,17.0));
    float reach=0.04+0.16*hash2(vec2(slot,23.0));
    float along=rim_height-height;
    float profile=1.0-smoothstep(width*0.5,width,abs(f-centre)*(1.0+along*6.0));
    float bead=1.0-smoothstep(0.0,0.012,abs(along-reach));
    return max(profile*(1.0-smoothstep(reach*0.6,reach,along)),profile*bead);
}
// Drops of condensation about 3 mm across. Returns the mask and the tilt of the
// drop's surface at this point.
vec3 drops(float angle, float height, float level) {
    vec2 uv=vec2(angle/TAU*110.0,height*480.0);
    vec2 cell=floor(uv), f=fract(uv);
    if(hash2(cell)>0.25*level) return vec3(0);
    vec2 centre=0.25+0.5*vec2(hash2(cell+1.0),hash2(cell+2.0));
    float radius=0.12+0.2*hash2(cell+3.0);
    vec2 d=(f-centre)/radius;
    float r2=dot(d,d);
    if(r2>1.0) return vec3(0);
    return vec3(1.0,d);
}
void fragment() {
    vec4 orm=texture(orm_map,UV);
    vec3 albedo=texture(albedo_map,UV).rgb;
    float metallic=orm.b;
    float iron=step(0.5,metallic);
    float angle=atan(local_pos.z,local_pos.x);
    float r=length(local_pos.xz);
    float body=step(r,body_radius);
    float rim=smoothstep(rim_height-0.02,rim_height-0.004,local_pos.y);
    float inner=step(r,inner_radius)*0.8;
    float run=body*streaks(angle,local_pos.y);
    float wet=max(max(rim,inner),run)*wetness;
    vec3 drop=iron*body>0.5 ? drops(angle,local_pos.y,wetness) : vec3(0);
    // Wet wood darkens and warms; wet iron only loses some of its roughness:
    // a film on old iron is no mirror, and as one the rim showed the sky blue.
    ALBEDO=mix(albedo,albedo*vec3(0.28,0.22,0.16),wet*(1.0-iron));
    ALBEDO*=1.0-drop.x*0.15;
    METALLIC=metallic;
    ROUGHNESS=mix(orm.g,mix(0.08,0.3,iron),max(wet,drop.x));
    SPECULAR=mix(0.5,0.85,wet);
    NORMAL_MAP=texture(normal_map,UV).rgb;
    if(drop.x>0.0) {
        vec3 around=vec3(-sin(angle),0,cos(angle));
        vec3 bulge=around*drop.y+vec3(0,1,0)*drop.z;
        NORMAL=normalize(NORMAL+(VIEW_MATRIX*MODEL_MATRIX*vec4(bulge*0.8,0)).xyz);
    }
}
