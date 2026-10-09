#[compute]
#version 450
// Small, bounded PBF solver for one open tankard. Simulation units = inner radius.
// Position Based Fluids (Macklin & Müller, 2013); compression-only constraints.
layout(local_size_x=64) in;
struct Particle { vec4 position; vec4 velocity; vec4 predicted; vec4 correction; vec4 constraint; };
layout(set=0,binding=0,std430) restrict buffer Particles { Particle p[]; };
layout(set=0,binding=1,std430) restrict buffer Statistics { vec4 stats; };
// Phase 1 and phase 2 read exactly the same predicted positions. Preserve
// neighbour order and reuse that exact support set; no distance approximation.
layout(set=0,binding=2,std430) restrict buffer Neighbours { uint neighbour_data[]; };
layout(push_constant,std430) uniform Params {
    vec4 acceleration_dt;
    vec4 cup; // radius, rim, particle spacing, smoothing radius
    vec4 control; // count, phase, consume count, generation
} u;
// One cooperative load per workgroup replaces strided global reads in the
// all-pairs passes. Inactive lanes still reach the barrier before returning.
shared vec4 neighbour_position[512];
shared vec4 neighbour_velocity[512];
const float PI=3.14159265359;
float kernel(float r2) {
    float h=u.cup.w;
    float q=max(0.0,1.0-r2/(h*h));
    return 315.0/(64.0*PI*h*h*h)*q*q*q;
}
vec3 gradient(vec3 d) {
    float r=length(d), h=u.cup.w;
    if(r<0.00001 || r>=h) return vec3(0);
    float q=1.0-r/h;
    return -45.0/(PI*h*h*h*h)*q*q*d/r;
}
// Reflected neighbours approximate the missing fluid volume inside solid walls.
// Without boundary support, density is underestimated at the floor and the
// entire mug collapses into an unnaturally shallow layer.
vec3 mirror_wall(vec3 q) {
    float r=length(q.xz);
    return vec3(q.x*(2.0*(u.cup.x+0.10)-r)/max(r,0.0001),q.y,
                q.z*(2.0*(u.cup.x+0.10)-r)/max(r,0.0001));
}
void density_sample(vec3 d,float mass,bool movable,inout float rho,inout float grad2,inout vec3 sum) {
    rho+=mass*kernel(dot(d,d));
    vec3 g=mass*gradient(d);
    if(movable) grad2+=dot(g,g);
    sum+=g;
}
vec3 collide(vec3 q, bool contained) {
    float r=length(q.xz), radius=u.cup.x;
    // Open top, closed bottom; contained samples cannot cross the side wall.
    if(contained) {
        if(q.y<u.cup.y && r>radius) {
            q.xz*=radius/max(r,0.00001);
            q.y=max(q.y,0.08);
        }
        if(r<radius+0.12) q.y=max(q.y,0.08);
    } else if(q.y<u.cup.y && q.y>-0.08 && r>radius && r<radius+0.20) {
        // Escaped drops slide along the outside instead of entering the wood.
        q.xz*= (radius+0.20)/max(r,0.00001);
    }
    return q;
}
void main() {
    uint i=gl_GlobalInvocationID.x;
    int count=int(u.control.x), phase=int(u.control.y);
    if(phase==1 || phase==5) {
        for(uint j=gl_LocalInvocationID.x;j<uint(count);j+=64) {
            neighbour_position[j]=phase==1 ? p[j].predicted : p[j].position;
            if(phase==5) neighbour_velocity[j]=p[j].velocity;
        }
        barrier();
    }
    if(i>=count) return;
    float dt=u.acceleration_dt.w;
    if(phase==7) {
        if(i!=0) return;
        int consume=int(u.control.z), inside=0, outside=0;
        for(int j=count-1;j>=0;j--) {
            if(p[j].position.w==1.0 && consume>0) {
                p[j].position.w=0.0; p[j].predicted.w=0.0; consume--;
            }
            if(p[j].position.w==1.0) inside++;
            if(p[j].position.w==2.0) outside++;
        }
        stats=vec4(float(inside),float(outside),u.control.w,0);
        return;
    }
    if(p[i].position.w==0.0) return;
    vec3 xi=p[i].predicted.xyz;
    if(phase==8) {
        // Relax a freshly poured seed without turning pressure corrections
        // into a violent launch. Used only on refill, never during motion.
        xi.y=min(xi.y,u.cup.y-0.14);
        p[i].position.xyz=xi;
        p[i].velocity=vec4(0);
        return;
    }
    // Each sample carries its share of the measured interior volume.
    float mass=PI*pow(u.cup.x+0.15,2.0)*u.cup.y/float(count);
    // These fusions touch only this particle. Neighbour-reading phases 1/2/5
    // stay in separate dispatches, with their original cross-workgroup barriers.
    if(phase==10) p[i].velocity.xyz+=p[i].correction.xyz;
    if(phase==0 || phase==10) {
        vec3 v=p[i].velocity.xyz+u.acceleration_dt.xyz*dt;
        vec3 q=p[i].position.xyz+v*dt;
        p[i].predicted=vec4(collide(q,p[i].position.w==1.0),p[i].position.w);
    } else if(phase==1) {
        float rho=0.0, grad2=0.0;
        vec3 sum=vec3(0);
        uint base=i*uint(count+1), neighbours=0;
        for(int j=0;j<count;j++) {
            if(neighbour_position[j].w==0.0) continue;
            vec3 d=xi-neighbour_position[j].xyz;
            if(dot(d,d)>u.cup.w*u.cup.w) continue;
            neighbour_data[base+1+neighbours++]=uint(j);
            density_sample(d,mass,true,rho,grad2,sum);
            vec3 q=neighbour_position[j].xyz;
            if(neighbour_position[j].w==1.0) {
                density_sample(xi-vec3(q.x,-q.y,q.z),mass,false,rho,grad2,sum);
                if(q.y<u.cup.y) {
                    vec3 wall=mirror_wall(q);
                    density_sample(xi-wall,mass,false,rho,grad2,sum);
                    density_sample(xi-vec3(wall.x,-wall.y,wall.z),mass,false,rho,grad2,sum);
                }
            }
        }
        neighbour_data[base]=neighbours;
        p[i].constraint=vec4(-max(rho-1.0,0.0)/(grad2+dot(sum,sum)+0.04),rho,0,0);
    } else if(phase==2) {
        vec3 delta=vec3(0);
        uint base=i*uint(count+1);
        for(uint neighbour=0;neighbour<neighbour_data[base];neighbour++) {
            uint j=neighbour_data[base+1+neighbour];
            vec3 d=xi-p[j].predicted.xyz;
            // Weak artificial pressure keeps separated drops from clumping.
            float q=kernel(dot(d,d))/kernel(0.09*u.cup.w*u.cup.w);
            float tensile=-0.0002*q*q*q*q;
            delta+=(p[i].constraint.x+p[j].constraint.x+tensile)*mass*gradient(d);
            vec3 qj=p[j].predicted.xyz;
            if(p[j].predicted.w==1.0) {
                delta+=p[i].constraint.x*mass*gradient(xi-vec3(qj.x,-qj.y,qj.z));
                if(qj.y<u.cup.y) {
                    vec3 wall=mirror_wall(qj);
                    delta+=p[i].constraint.x*mass*gradient(xi-wall);
                    delta+=p[i].constraint.x*mass*gradient(xi-vec3(wall.x,-wall.y,wall.z));
                }
            }
        }
        p[i].correction=vec4(delta*0.65,0);
    } else if(phase==3 || phase==9) {
        p[i].predicted.xyz=collide(xi+p[i].correction.xyz,p[i].position.w==1.0);
    }
    if(phase==4 || phase==9) {
        // Reload the corrected FP32 position exactly as the former phase 4 did.
        xi=p[i].predicted.xyz;
        vec3 v=(xi-p[i].position.xyz)/dt;
        // Resting wall friction; no artificial spring attached to the cup.
        if(xi.y<0.081) v.xz*=0.985;
        float speed=length(v);
        if(speed>55.0) v*=55.0/speed;
        float state=p[i].position.w;
        if(state==1.0 && length(xi.xz)>u.cup.x+0.08 && xi.y>=u.cup.y) state=2.0;
        if(xi.y< -2.1 || xi.y>4.5 || length(xi.xz)>3.0) state=0.0;
        p[i].velocity=vec4(v*0.999,0);
        p[i].position=vec4(xi,state);
        p[i].predicted.w=state;
    } else if(phase==5) {
        vec3 dv=vec3(0);
        for(int j=0;j<count;j++) {
            if(neighbour_position[j].w==0.0) continue;
            vec3 d=xi-neighbour_position[j].xyz;
            if(dot(d,d)>u.cup.w*u.cup.w) continue;
            dv+=(neighbour_velocity[j].xyz-p[i].velocity.xyz)*mass*kernel(dot(d,d));
        }
        p[i].correction=vec4(dv*0.08,0);
    } else if(phase==6) {
        p[i].velocity.xyz+=p[i].correction.xyz;
    }
}
