shader_type spatial;
// Back faces: at the mouth the hand's camera is inside the field's box, where a
// front face never draws. The march starts at the camera and writes its own depth.
render_mode cull_front, depth_draw_always, specular_schlick_ggx, diffuse_lambert_wrap;
uniform vec2 crop_scale = vec2(1.0);
uniform vec2 crop_offset = vec2(0.0);
// The light of the world behind the hand, which the hand's viewport cannot
// see: a drop outside the mug shows it through the beer. The viewmodel's
// lighting sets it: the lit land outdoors, the room's light indoors.
uniform vec3 backdrop = vec3(0.30, 0.25, 0.18);
// The volume is reconstructed from the moving particles. Optical treatment of
// the liquid follows the lake: depth absorption, refraction, Fresnel. The head
// of foam is a second, looser shell of the same field lifted above the liquid;
// the distance between the two shells along the ray is the foam thickness.
// Ambient light and reflections are the engine's, from the hand's environment,
// as for the mug: the beer takes the same light as the hand that holds it.
uniform sampler3D density_field : filter_linear, repeat_disable;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 field_low = vec3(-2.2,-2.0,-2.2);
uniform vec3 field_extent = vec3(4.4,6.4,4.4);
uniform float iso_level = 0.9;
uniform float foam_iso = 0.45;
// Height of the head in simulation units (inner radius = 1). BeerFluid raises
// it after a pour and lets it settle over minutes.
uniform float foam_head = 0.3;
// A uniform bound keeps the Metal compiler from unrolling the marches; with a
// constant bound the first compile took minutes.
uniform int march_limit = 144;
// Beer is a clear golden medium: it absorbs blue most and red least, per
// simulation unit (8.7 cm). A thin sheet is pale gold, the body amber. The
// mug's beer sets both (BeerViewmodel.beer_look): darker beer absorbs more.
uniform vec3 absorption = vec3(0.12, 0.45, 3.0);
// What the beer's haze and the mug's wall scatter back up per unit of path.
uniform float scatter = 0.12;
varying vec3 local_vertex;
varying flat vec3 local_camera;
void vertex() {
    local_vertex=VERTEX;
    local_camera=(inverse(MODEL_MATRIX)*INV_VIEW_MATRIX[3]).xyz;
}
vec2 field(vec3 p) { return texture(density_field,(p-field_low)/field_extent).rg; }
float density(vec3 p) { return field(p).r; }
float hash(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
float hash2(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec3 p) {
    vec3 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),
        mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
float noise2(vec2 p) {
    vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(hash2(i),hash2(i+vec2(1,0)),f.x),mix(hash2(i+vec2(0,1)),hash2(i+vec2(1,1)),f.x),f.y);
}
// Low mounds and dimples of the head that drift slowly, about 0..1.
float mounds(vec2 xz) {
    vec2 flow=vec2(TIME*0.03,TIME*0.02);
    return noise2(xz*1.6+flow)+0.67*(noise2(xz*3.7-flow)-0.5);
}
// The head stands level over the beer right up to the wall; more foam where
// the liquid is agitated.
float lift(vec3 p, float agitation) {
    float mound=0.7+0.45*mounds(p.xz);
    float edge=smoothstep(1.2,1.0,length(p.xz));
    return (foam_head*mound+0.15*agitation)*edge;
}
float shell(vec3 p) {
    vec2 f=field(p);
    return density(p-vec3(0,lift(p,f.g),0));
}
// Unequal bubbles scattered in the matrix of the head. Returns the distance
// from the nearest bubble's centre in its radii (above 1 in the matrix), the
// offset from that centre in radii and the bubble's id.
vec4 bubble(vec2 uv) {
    vec2 cell=floor(uv), f=fract(uv);
    float nearest=10.0, id=0.0;
    vec2 delta=vec2(0);
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
        vec2 offset=vec2(float(x),float(y));
        vec2 seed=cell+offset;
        vec2 jitter=vec2(hash(vec3(seed,1)),hash(vec3(seed,7)));
        vec2 d=f-offset-(0.18+0.64*jitter);
        float radius=0.22+0.2*hash(vec3(seed,13));
        float distance=length(d)/radius;
        if(distance<nearest) { nearest=distance; delta=d/radius; id=hash(vec3(seed,29)); }
    }
    return vec4(nearest,delta,id);
}
// 1 where a bubble of this scale spans a few pixels, 0 where one pixel holds
// several: detail smaller than a pixel would only shimmer.
float resolved(vec2 uv) {
    return 1.0-smoothstep(0.3,0.75,max(length(dFdx(uv)),length(dFdy(uv))));
}
vec3 gradient(vec3 p, bool loose) {
    float e=0.08;
    if(loose) return normalize(vec3(shell(p-vec3(e,0,0))-shell(p+vec3(e,0,0)),
        shell(p-vec3(0,e,0))-shell(p+vec3(0,e,0)),shell(p-vec3(0,0,e))-shell(p+vec3(0,0,e))));
    return normalize(vec3(density(p-vec3(e,0,0))-density(p+vec3(e,0,0)),
        density(p-vec3(0,e,0))-density(p+vec3(0,e,0)),density(p-vec3(0,0,e))-density(p+vec3(0,0,e))));
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
    // 1. The loose shell: the top of the head, or the first air-liquid boundary.
    bool shell_hit=false;
    float previous=t;
    vec3 p=local_camera+ray*t;
    for(int i=0;i<march_limit;i++) {
        if(t>end) break;
        p=local_camera+ray*t;
        float value=shell(p);
        if(value>foam_iso) { shell_hit=true; break; }
        previous=t;
        t+=value<0.01 ? 0.14 : 0.05;
    }
    if(!shell_hit) discard;
    float a=previous, b=t;
    for(int i=0;i<5;i++) {
        float m=(a+b)*0.5;
        if(shell(local_camera+ray*m)>foam_iso) b=m; else a=m;
    }
    float t_shell=(a+b)*0.5;
    vec3 ps=local_camera+ray*t_shell;
    // Spilled drops away from the mug carry no head.
    bool foam_here=length(ps.xz)<1.06 && ps.y>0.25;
    // 2. The liquid behind the shell.
    bool hit=false;
    t=t_shell;
    previous=t;
    for(int i=0;i<march_limit;i++) {
        if(t>end) break;
        p=local_camera+ray*t;
        float value=density(p);
        if(value>iso_level) { hit=true; break; }
        previous=t;
        t+=value<0.005 ? 0.14 : 0.035;
    }
    if(!hit && !foam_here) discard;
    float foam_thickness=1.0;
    if(hit) {
        a=previous; b=t;
        for(int i=0;i<5;i++) {
            float m=(a+b)*0.5;
            if(density(local_camera+ray*m)>iso_level) b=m; else a=m;
        }
        t=(a+b)*0.5;
        foam_thickness=t-t_shell;
    }
    // Foam that is deeper than the head itself is a thin lace over nothing.
    if(foam_thickness>1.4) { foam_here=false; }
    if(!hit && !foam_here) discard;

    // Liquid. What lies behind it comes through, losing blue and green with
    // the path; what the beer's haze and the wall scatter back is the integral
    // of that loss down and up again, so it is gold at any depth and never
    // takes the colour of what was absorbed.
    vec3 liquid_albedo=vec3(0);
    vec3 liquid_emission=vec3(0);
    vec3 liquid_normal=vec3(0,0,1);
    float liquid_alpha=0.0;
    vec4 liquid_view=vec4(0);
    if(hit) {
        p=local_camera+ray*t;
        vec3 n=gradient(p,false);
        liquid_view=VIEW_MATRIX*MODEL_MATRIX*vec4(p,1);
        n=normalize(n+vec3(cos(p.x*27.0+p.z*14.0+TIME*2.0),0,
            sin(p.z*31.0-p.x*12.0+TIME*1.7))*0.018);
        liquid_normal=normalize((VIEW_MATRIX*MODEL_MATRIX*vec4(n,0)).xyz);
        vec4 clip=PROJECTION_MATRIX*liquid_view;
        // Thickness along the refracted ray makes thin sheets pale and the body
        // golden, instead of painting every drop the same opaque yellow.
        vec3 transmitted_ray=refract(ray,n,1.0/1.345);
        float thickness=0.0;
        for(int i=1;i<=24;i++) {
            if(density(p+transmitted_ray*(float(i)*0.09))<iso_level*0.7) break;
            thickness+=0.09;
        }
        thickness=max(thickness,0.05);
        vec3 transmission=exp(-absorption*thickness);
        liquid_albedo=scatter*(1.0-exp(-2.0*absorption*thickness))/(2.0*absorption);
        vec2 uv=clip.xy/clip.w*0.5+0.5;
        vec2 refracted_uv=clamp(uv+liquid_normal.xy*0.018*min(thickness,1.0)/crop_scale,(vec2(0.001)-crop_offset)/crop_scale,(vec2(0.999)-crop_offset)/crop_scale);
        float depth=texture(depth_texture,refracted_uv).r;
        vec4 behind=INV_PROJECTION_MATRIX*vec4(refracted_uv*2.0-1.0,depth,1.0);
        if(-behind.z/behind.w < -liquid_view.z) refracted_uv=uv;
        vec4 scene=textureLod(screen_texture,refracted_uv,0.0);
        liquid_emission=mix(backdrop,scene.rgb,scene.a)*transmission;
        float fresnel=0.021+0.979*pow(1.0-max(dot(-ray,n),0.0),5.0);
        float inside=1.0-smoothstep(0.96,1.08,length(p.xz));
        float sheet_opacity=clamp(0.28+thickness*0.55+fresnel*0.35,0.3,0.95);
        liquid_alpha=mix(sheet_opacity,1.0,inside);
    }

    // Head of foam, after the tankard in the reference (its yellow is the
    // light of its bar): a white matrix of fine bubbles, each a little lighter
    // or darker than the next and wet on its crown, tan where beer soaks the
    // head thin, with open bubbles of three sizes as pits that are dark inside
    // and lit on the lip. Open bubbles are more and larger toward the wall; a
    // few have burst and show the beer.
    float foam_alpha=0.0;
    vec3 foam_albedo=vec3(0), foam_normal=vec3(0,0,1);
    float foam_roughness=0.38, foam_ao=1.0;
    vec4 foam_view=vec4(0);
    if(foam_here) {
        vec3 ns=gradient(ps,true);
        foam_view=VIEW_MATRIX*MODEL_MATRIX*vec4(ps,1);
        float r=length(ps.xz);
        float wall=smoothstep(0.55,1.0,r);
        vec2 drift=vec2(TIME*0.004,TIME*0.003);
        vec2 warp=vec2(noise(ps*5.0),noise(ps*5.0+3.0))*0.35;
        vec2 scale_uv[3]=vec2[3](ps.xz*13.0+warp+drift*13.0,
            ps.xz*26.0+warp*1.6+vec2(3.7)+drift*26.0, ps.xz*52.0+vec2(1.3)+drift*52.0);
        float open_share[3]=float[3](0.08+0.35*wall, 0.25+0.25*wall, 0.45);
        float depth_scale[3]=float[3](1.0, 0.8, 0.6);
        float pit=0.0, lip=0.0, hole=0.0, crown=0.0, tone=0.0;
        vec2 bump=vec2(0);
        for(int s=0;s<3;s++) {
            vec4 cell=bubble(scale_uv[s]);
            float seen=resolved(scale_uv[s]);
            float inside_bubble=1.0-smoothstep(0.8,1.0,cell.x);
            float open=step(cell.w,open_share[s])*seen;
            float closed=(1.0-step(cell.w,open_share[s]))*seen*inside_bubble;
            // An open bubble is a bowl: its normal tilts toward the centre.
            // A closed one is a dome in the matrix.
            float bowl=open*inside_bubble*(1.0-cell.x*cell.x)*depth_scale[s];
            pit=max(pit,bowl);
            lip=max(lip,open*smoothstep(0.7,0.92,cell.x)*(1.0-smoothstep(0.92,1.1,cell.x)));
            crown=max(crown,closed*(1.0-cell.x));
            tone+=closed*(hash(vec3(cell.w,float(s),3.0))-0.5);
            bump+=(open*inside_bubble*-cell.yz*0.9+closed*cell.yz*0.5)*depth_scale[s];
            if(s==0) hole=step(cell.w,0.012+0.03*wall)*inside_bubble*seen;
        }
        vec3 nf=normalize(ns+vec3(bump.x,0,bump.y));
        foam_normal=normalize((VIEW_MATRIX*MODEL_MATRIX*vec4(nf,0)).xyz);
        vec3 cream=vec3(0.80,0.77,0.69);
        vec3 soaked=vec3(0.48,0.33,0.15);
        vec3 deep=vec3(0.12,0.06,0.016);
        // Beer soaks the head where it is thin, in the hollows between the
        // mounds, in drifting patches and in a ring against the wall.
        float thin=1.0-smoothstep(0.02,0.2,foam_thickness);
        float hollow=smoothstep(0.35,-0.05,mounds(ps.xz));
        float patches=smoothstep(0.55,0.85,noise2(ps.xz*1.8+drift*40.0+vec2(5.1)));
        float soak=clamp(max(max(thin,patches*0.5),hollow*0.4)+0.5*smoothstep(0.88,1.04,r),0.0,1.0);
        foam_albedo=mix(cream,soaked,soak);
        // Mottle of drier and wetter foam, and bubble by bubble.
        foam_albedo*=(0.88+0.24*noise(ps*vec3(6.0,2.0,6.0)+vec3(0,TIME*0.02,0)))*(1.0+0.35*tone);
        foam_albedo=mix(foam_albedo,mix(deep,soaked,0.15),pit*0.95);
        foam_albedo=mix(foam_albedo,cream*1.1,lip*0.5*(1.0-soak));
        foam_albedo=mix(foam_albedo,deep*0.6,hole);
        foam_ao=1.0-0.75*pit;
        foam_roughness=mix(0.4,0.15,max(max(lip,pit),crown*0.8));
        foam_alpha=smoothstep(0.0,0.06,foam_thickness)*(1.0-hole*0.6);
    }

    float f=foam_alpha;
    vec4 view_pos=f>0.5 ? foam_view : liquid_view;
    if(!hit) view_pos=foam_view;
    vec4 clip=PROJECTION_MATRIX*view_pos;
    DEPTH=clip.z/clip.w;
    LIGHT_VERTEX=view_pos.xyz;
    NORMAL=normalize(mix(liquid_normal,foam_normal,f));
    ALBEDO=mix(liquid_albedo,foam_albedo,f);
    EMISSION=liquid_emission*(1.0-f);
    ROUGHNESS=mix(0.06,foam_roughness,f);
    SPECULAR=mix(0.25,0.5,f);
    METALLIC=0.0;
    AO=mix(1.0,foam_ao,f);
    AO_LIGHT_AFFECT=0.35;
    ALPHA=max(liquid_alpha,f);
}
