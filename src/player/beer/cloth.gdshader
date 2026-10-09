shader_type spatial;
uniform vec4 cloth_color : source_color = vec4(0.16,0.085,0.035,1);
uniform float weave = 0.0;
varying vec3 model_pos;
void vertex() { model_pos=VERTEX; }
void fragment() {
    vec3 p=model_pos*2200.0;
    float grain=fract(sin(dot(floor(p),vec3(12.9898,78.233,39.425)))*43758.5453);
    float cloth=sin(p.x*0.7)*sin(p.y*0.7)*0.06*weave;
    ALBEDO=cloth_color.rgb*(0.87+grain*0.22+cloth);
    ROUGHNESS=0.72+weave*0.18;
    SPECULAR=0.28;
}
