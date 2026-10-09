shader_type spatial;
render_mode cull_back, depth_draw_always, specular_schlick_ggx, ambient_light_disabled;
#include "res://src/sky/atmosphere.gdshaderinc"
uniform vec2 crop_scale = vec2(1.0);
uniform vec2 crop_offset = vec2(0.0);
uniform bool physical_sky = false;
uniform bool indoor_lighting = false;
uniform vec3 indoor_ambient = vec3(0.10, 0.065, 0.035);
uniform mat3 view_to_world = mat3(1.0);
// The volume is reconstructed from the moving particles. Optical treatment
// follows the lake: depth absorption, refraction, Fresnel and rough whitecaps.
uniform sampler3D density_field : filter_linear, repeat_disable;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 field_low = vec3(-2.2,-2.0,-2.2);
uniform vec3 field_extent = vec3(4.4,6.4,4.4);
uniform float iso_level = 0.9;
varying vec3 local_vertex;
varying flat vec3 local_camera;
void vertex() {
    local_vertex=VERTEX;
    local_camera=(inverse(MODEL_MATRIX)*INV_VIEW_MATRIX[3]).xyz;
}
float density(vec3 p) { return texture(density_field,(p-field_low)/field_extent).r; }
float hash(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
float noise(vec3 p) {
    vec3 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),
        mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
// Unequal sub-millimetre bubbles, with a wet film between the cells.
// Screen derivatives suppress detail that is smaller than one pixel.
vec3 bubbles(vec2 uv) {
    vec2 cell=floor(uv), f=fract(uv);
    float nearest=10.0;
    vec2 delta=vec2(0);
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
        vec2 offset=vec2(float(x),float(y));
        vec2 seed=cell+offset;
        vec2 jitter=vec2(hash(vec3(seed,1)),hash(vec3(seed,7)));
        vec2 d=f-offset-(0.18+0.64*jitter);
        float radius=0.23+0.16*hash(vec3(seed,13));
        float distance=length(d)/radius;
        if(distance<nearest) { nearest=distance; delta=d/radius; }
    }
    float aa=max(fwidth(nearest),0.07);
    float film=smoothstep(0.62-aa,0.95+aa,nearest);
    float visible=1.0-smoothstep(0.8,2.0,max(length(dFdx(uv)),length(dFdy(uv))));
    return vec3(mix(0.75,film,visible),delta*visible*(1.0-film));
}
void fragment() {
    vec3 ray=normalize(local_vertex-local_camera);
    vec3 inv=1.0/(ray+vec3(0.000001));
    vec3 ta=(field_low-local_camera)*inv;
    vec3 tb=(field_low+field_extent-local_camera)*inv;
    vec3 near3=min(ta,tb), far3=max(ta,tb);
    float t=max(max(near3.x,near3.y),max(near3.z,0.0));
    float end=min(min(far3.x,far3.y),far3.z);
    // Stop at opaque mug/hand geometry instead of marching through hidden beer.
    float opaque_depth=texture(depth_texture,SCREEN_UV).r;
    if(opaque_depth>0.000001) {
        vec4 opaque_view=INV_PROJECTION_MATRIX*vec4(SCREEN_UV*2.0-1.0,opaque_depth,1.0);
        opaque_view/=opaque_view.w;
        vec3 opaque_local=(inverse(MODEL_MATRIX)*INV_VIEW_MATRIX*opaque_view).xyz;
        end=min(end,dot(opaque_local-local_camera,ray));
    }
    bool hit=false;
    vec3 p=local_camera+ray*t;
    for(int i=0;i<144;i++) {
        if(t>end) break;
        p=local_camera+ray*t;
        float value=density(p);
        if(value>iso_level) { hit=true; break; }
        t+=value<0.005 ? 0.14 : 0.045;
    }
    if(!hit) discard;
    float a=max(0.0,t-0.14), b=t;
    for(int i=0;i<5;i++) {
        float m=(a+b)*0.5;
        if(density(local_camera+ray*m)>iso_level) b=m; else a=m;
    }
    p=local_camera+ray*((a+b)*0.5);
    float e=0.08;
    vec3 n=normalize(vec3(density(p-vec3(e,0,0))-density(p+vec3(e,0,0)),
        density(p-vec3(0,e,0))-density(p+vec3(0,e,0)),density(p-vec3(0,0,e))-density(p+vec3(0,0,e))));
    vec4 view_pos=VIEW_MATRIX*MODEL_MATRIX*vec4(p,1);
    vec4 clip=PROJECTION_MATRIX*view_pos;
    DEPTH=clip.z/clip.w;
    LIGHT_VERTEX=view_pos.xyz;
    vec3 normal_view=normalize((VIEW_MATRIX*MODEL_MATRIX*vec4(n,0)).xyz);
    float agitation=texture(density_field,(p-field_low)/field_extent).g;

    float islands=noise(p*8.0+vec3(TIME*0.018,0,0));
    float fine=noise(p*11.0);
    float wall=smoothstep(0.62,0.90,length(p.xz));
    float cap=smoothstep(0.15,0.65,n.y);
    float foam=cap*smoothstep(0.32,0.57,islands*0.76+fine*0.24+wall*0.13+agitation*0.1);
    foam*=1.0-smoothstep(0.95,1.18,length(p.xz));
    vec3 cells=bubbles(p.xz*30.0+vec2(noise(p*9.0),noise(p*9.0+3.0))*0.35);
    n=normalize(n+vec3(cos(p.x*27.0+p.z*14.0+TIME*2.0),0,
        sin(p.z*31.0-p.x*12.0+TIME*1.7))*0.018*(1.0-foam));
    vec3 micro_normal=normalize(n+vec3(cells.y,0,cells.z)*0.15*foam);
    normal_view=normalize((VIEW_MATRIX*MODEL_MATRIX*vec4(micro_normal,0)).xyz);
    NORMAL=normal_view;

    // Thickness along the refracted ray makes thin sheets gold and the body
    // dark amber, instead of painting every drop the same opaque yellow.
    vec3 transmitted_ray=refract(ray,n,1.0/1.345);
    float thickness=0.0;
    for(int i=1;i<=24;i++) {
        if(density(p+transmitted_ray*(float(i)*0.09))<iso_level*0.7) break;
        thickness+=0.09;
    }
    foam*=smoothstep(0.18,0.5,thickness);
    vec3 transmission=exp(-vec3(1.5,5.0,15.0)*max(thickness,0.025));
    vec2 uv=clip.xy/clip.w*0.5+0.5;
    vec2 refracted_uv=clamp(uv+normal_view.xy*0.018*min(thickness,1.0)/crop_scale,(vec2(0.001)-crop_offset)/crop_scale,(vec2(0.999)-crop_offset)/crop_scale);
    float depth=texture(depth_texture,refracted_uv).r;
    vec4 behind=INV_PROJECTION_MATRIX*vec4(refracted_uv*2.0-1.0,depth,1.0);
    if(-behind.z/behind.w < -view_pos.z) refracted_uv=uv;
    vec4 scene=textureLod(screen_texture,refracted_uv,0.0);
    vec3 under=mix(vec3(0.40,0.24,0.08),scene.rgb,scene.a);
    float fresnel=0.021+0.979*pow(1.0-max(dot(-ray,n),0.0),5.0);
    vec3 beer=under*transmission+vec3(0.34,0.12,0.008)*(1.0-transmission);
    vec3 cream=mix(vec3(0.39,0.35,0.27),vec3(0.80,0.76,0.66),cells.x);
    vec3 reflected=normalize(view_to_world*reflect(normalize(view_pos.xyz),normal_view));
    vec3 sky=mix(vec3(0.18,0.14,0.10),vec3(0.55,0.72,0.95),smoothstep(-0.1,0.5,reflected.y));
    vec3 ambient=vec3(0.32,0.36,0.42);
    if(physical_sky) {
        reflected.y=abs(reflected.y);
        sky=atmo_sky_radiance(reflected);
        ambient=atmo_sky_radiance(vec3(0,1,0))*0.9;
        beer=under*transmission+vec3(0.34,0.12,0.008)*(1.0-transmission)
            *clamp(length(ambient)*1.5,0.02,1.4);
    }
    if(indoor_lighting) {
        sky=indoor_ambient;
        ambient=indoor_ambient;
        beer=under*transmission+vec3(0.34,0.12,0.008)*(1.0-transmission)
            *clamp(length(ambient)*1.5,0.02,1.4);
    }
    ALBEDO=mix(vec3(0.035,0.012,0.001),cream,foam);
    EMISSION=mix(beer,sky,fresnel)*(1.0-foam)+cream*foam*ambient*0.8;
    ROUGHNESS=mix(0.065,0.66,foam);
    METALLIC=0.0;
    SPECULAR=mix(0.27,0.18,foam);
    float inside=1.0-smoothstep(0.96,1.08,length(p.xz));
    float sheet_opacity=clamp(0.28+thickness*0.55+fresnel*0.35,0.3,0.95);
    ALPHA=mix(sheet_opacity,1.0,max(inside,foam));
}
