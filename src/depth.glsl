#version 430 core

#define EYE eye.xyz
#define NEAR nfwh.x
#define FAR nfwh.y
#define WIDTH nfwh.z
#define HEIGHT nfwh.w
#define SAMPLES seed.w

#define SDF_SPHERE 0
#define SDF_BOX 1
#define SDF_PLANE 2
#define SDF_CONE 3
#define SDF_PYRAMID 4
#define SDF_TORUS 5
#define SDF_CYLINDER 6
#define SDF_CAPSULE 7
#define SDF_DISK 8
#define SDF_TYPE_COUNT 9

#define SDF_BLEND_UNION 0
#define SDF_BLEND_DIFF 1
#define SDF_BLEND_INT 2
#define SDF_BLEND_SMTH_UNION 3
#define SDF_BLEND_SMTH_DIFF 4
#define SDF_BLEND_SMTH_INT 5
#define SDF_BLEND_COUNT 6

#define MATERIAL_COUNT 4

#define sdf_inv_transform(i) sdfs[i].inv_xform
#define sdf_distance_type(i) int(sdfs[i].parameters.x)
#define sdf_blend_type(i) int(sdfs[i].parameters.y)
#define sdf_blend_smoothness(i) sdfs[i].parameters.z
#define sdf_material_id(i) int(sdfs[i].parameters.w)
#define sdf_uv_scale(i) sdfs[i].extra_params.y

layout(local_size_x = 8, local_size_y = 8) in;

layout(binding = 0, rgba32f) uniform image2D color;

layout(binding=2) uniform CAM_BUF
{
    mat4 IVP;
    vec4 eye;
    vec4 nfwh;
    vec4 seed;
};

struct SDF {
    mat4 inv_xform;
    vec4 parameters; // [dis_type, blend_type, smoothness, material_id]
    vec4 extra_params; // [object_id, uv_scale]
};

layout(binding=3) buffer SDF_BUF {   
    SDF sdfs[];
};

uniform int num_sdfs;

uniform sampler2D albedo0;
uniform sampler2D albedo1;
uniform sampler2D albedo2;
uniform sampler2D albedo3;

uniform sampler2D normal0;
uniform sampler2D normal1;
uniform sampler2D normal2;
uniform sampler2D normal3;

uniform sampler2D material0;
uniform sampler2D material1;
uniform sampler2D material2;
uniform sampler2D material3;

// w is emission
vec4 sdf_albedo_texture(int i, vec2 uv){
    int mat_id = sdf_material_id(i);
    switch(mat_id){
        default:
        case 0: return texture(albedo0, uv);
        case 1: return texture(albedo1, uv);
        case 2: return texture(albedo2, uv);
        case 3: return texture(albedo3, uv);
    }
    return vec4(0.0);
}

vec4 sdf_normal_texture(int i, vec2 uv){
    int mat_id = sdf_material_id(i);
    switch(mat_id){
        default:
        case 0: return texture(normal0, uv);
        case 1: return texture(normal1, uv);
        case 2: return texture(normal2, uv);
        case 3: return texture(normal3, uv);
    }
    return vec4(0.0);
}

vec4 sdf_material_texture(int i, vec2 uv){
    int mat_id = sdf_material_id(i);
    switch(mat_id){
        default:
        case 0: return texture(material0, uv);
        case 1: return texture(material1, uv);
        case 2: return texture(material2, uv);
        case 3: return texture(material3, uv);
    }
    return vec4(0.0);
}

float vmax(vec3 a){
    return max(max(a.x, a.y), a.z);
}

// these rays are all pre-transformed into unit space

vec2 sdf_sphere(int id, vec3 ray){
    return vec2(length(ray) - 1.0, float(id));
}

vec2 sdf_box(int id, vec3 ray){
    vec3 d = abs(ray) - vec3(1.0);
    return vec2(vmax(d), float(id));
}

vec2 sdf_plane(int id, vec3 ray){
    return vec2(dot(ray, vec3(0.0, 1.0, 0.0)), float(id));
}

// Not Yet Implemented
vec2 sdf_cone(int id, vec3 ray){
    return vec2(0.0);   
}

// Not Yet Implemented
vec2 sdf_pyramid(int id, vec3 ray){
    return vec2(0.0);   
}

// Not Yet Implemented
vec2 sdf_torus(int id, vec3 ray){
    return vec2(0.0);   
}

// Not Yet Implemented
vec2 sdf_cylinder(int id, vec3 ray){
    return vec2(0.0);   
}

// Not Yet Implemented
vec2 sdf_capsule(int id, vec3 ray){
    return vec2(0.0);   
}

// Not Yet Implemented
vec2 sdf_disk(int id, vec3 ray){
    return vec2(0.0);   
}

vec2 sdf_distance(int i, vec3 point){
    // transform point into unit sphere space
    vec4 xpoint = sdf_inv_transform(i) * vec4(point.xyz, 1.0);
    point = (xpoint / xpoint.w).xyz;

    // use unit-sphere sdfs
    switch(sdf_distance_type(i)){
        case SDF_SPHERE: return sdf_sphere(i, point);
        case SDF_BOX: return sdf_box(i, point);
        case SDF_PLANE: return sdf_plane(i, point);
        case SDF_CONE: return sdf_cone(i, point);
        case SDF_PYRAMID: return sdf_pyramid(i, point);
        case SDF_TORUS: return sdf_torus(i, point);
        case SDF_CYLINDER: return sdf_cylinder(i, point);
        case SDF_CAPSULE: return sdf_capsule(i, point);
        case SDF_DISK: return sdf_disk(i, point);
    }
    
    return vec2(100000.0, 0.0);
}

vec2 sdf_blend_union(vec2 a, vec2 b){
    return a.x < b.x ? a : b;
}

vec2 sdf_blend_difference(vec2 a, vec2 b){
    b.x = -b.x;
    return a.x > b.x ? a : b;
}

vec2 sdf_blend_intersect(vec2 a, vec2 b){
    return a.x > b.x ? a : b;
}

vec2 sdf_blend_smooth_union(vec2 a, vec2 b, float k){
    float e = max(k - abs(a.x - b.x), 0.0);
    float dis = min(a.x, b.x) - e * e * 0.25 / k;
    return vec2(dis, a.x < b.x ? a.y : b.y);
}

vec2 sdf_blend_smooth_difference(vec2 a, vec2 b, float k){
    a.x = -a.x;
    vec2 r = sdf_blend_smooth_union(a, b, k);
    r.x = -r.x;
    return r;
}

vec2 sdf_blend_smooth_intersect(vec2 a, vec2 b, float k){
    float e = max(k - abs(a.x - b.x), 0.0);
    float dis = max(a.x, b.x) - e * e * 0.25 / k;
    return vec2(dis, a.x > b.x ? a.y : b.y);
}

vec2 sdf_blend(int i, vec2 a, vec2 b){
    switch(sdf_blend_type(i)){
        case SDF_BLEND_UNION: return sdf_blend_union(a, b);
        case SDF_BLEND_DIFF: return sdf_blend_difference(a, b);
        case SDF_BLEND_INT: return sdf_blend_intersect(a, b);
        case SDF_BLEND_SMTH_UNION: return sdf_blend_smooth_union(a, b, sdf_blend_smoothness(i));
        case SDF_BLEND_SMTH_DIFF: return sdf_blend_smooth_difference(a, b, sdf_blend_smoothness(i));
        case SDF_BLEND_SMTH_INT: return sdf_blend_smooth_intersect(a, b, sdf_blend_smoothness(i));
    }
    return sdf_blend_union(a, b);
}

vec2 sdf_map(vec3 ray){
    vec2 sam;
    sam.x = 100000.0;
    sam.y = -1.0;
    for(int i = 0; i < num_sdfs; ++i){
        sam = sdf_blend(i, sam, sdf_distance(i, ray));
    }
    return sam;
}

vec3 sdf_map_normal(vec3 point){
    vec3 e = vec3(0.0001, 0.0, 0.0);
    return normalize(vec3(
        sdf_map(point + e.xyz).x - sdf_map(point - e.xyz).x,
        sdf_map(point + e.zxy).x - sdf_map(point - e.zxy).x,
        sdf_map(point + e.zyx).x - sdf_map(point - e.zyx).x
    ));
}

vec3 toWorld(float x, float y, float z){
    vec4 t = vec4(x, y, z, 1.0);
    t = IVP * t;
    return vec3(t/t.w);
}

float randUni(inout uint f){
    f = (f ^ 61) ^ (f >> 16);
    f *= 9;
    f = f ^ (f >> 4);
    f *= 0x27d4eb2d;
    f = f ^ (f >> 15);
    return fract(float(f) * 2.3283064e-10);
}

float rand( inout uint f) {
   return randUni(f) * 2.0 - 1.0;
}

vec3 uniHemi(vec3 N, inout uint s){
    vec3 dir;
    float len;
    int i = 0;
    do {
        dir = vec3(rand(s), rand(s), rand(s));
        len = length(dir);
    }
    while(len > 1.0 && i < 5);
    
    if(dot(dir, N) < 0.0)
        dir *= -1.0;
    
    return dir / len;
}

vec3 roughBlend(vec3 newdir, vec3 I, vec3 N, float roughness){
    return normalize(
        mix(
            normalize(
                reflect(I, N)), 
            newdir, 
            roughness
            )
        );
}

vec2 uv_from_ray(vec3 N, vec3 p){
    vec3 d = abs(N);
    float a = vmax(d);
    if(a == d.x){
        return vec2(p.z, p.y);
    }
    else if(a == d.y){
        return vec2(p.x, p.z);
    }
    return vec2(p.x, p.y);
}

float DisGGX(vec3 N, vec3 H, float roughness)
{
    const float a = roughness * roughness;
    const float a2 = a * a;
    const float NdH = max(dot(N, H), 0.0);
    const float NdH2 = NdH * NdH;

    const float nom = a2;
    const float denom_term = (NdH2 * (a2 - 1.0) + 1.0);
    const float denom = 3.141592 * denom_term * denom_term;

    return nom / denom;
}

float GeomSchlickGGX(float NdV, float roughness)
{
    const float r = (roughness + 1.0);
    const float k = (r * r) / 8.0;

    const float nom = NdV;
    const float denom = NdV * (1.0 - k) + k;

    return nom / denom;
}

float GeomSmith(vec3 N, vec3 V, vec3 L, float roughness)
{
    const float NdV = max(dot(N, V), 0.0);
    const float NdL = max(dot(N, L), 0.0);
    const float ggx2 = GeomSchlickGGX(NdV, roughness);
    const float ggx1 = GeomSchlickGGX(NdL, roughness);

    return ggx1 * ggx2;
}

vec3 fresnelSchlick(float cosTheta, vec3 F0)
{
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

vec3 pbr_lighting(vec3 V, vec3 L, vec3 N, vec3 albedo, float metalness, float roughness)
{
    const float NdL = max(0.0, dot(N, L));
    const vec3 F0 = mix(vec3(0.04), albedo, metalness);
    const vec3 H = normalize(V + L);

    const float NDF = DisGGX(N, H, roughness);
    const float G = GeomSmith(N, V, L, roughness);
    const vec3 F = fresnelSchlick(max(dot(H, V), 0.0), F0);

    const vec3 nom = NDF * G * F;
    const float denom = 4.0 * max(dot(N, V), 0.0) * NdL + 0.001;
    const vec3 specular = nom / denom;

    const vec3 kS = F;
    const vec3 kD = (vec3(1.0) - kS) * (1.0 - metalness);

    return (kD * albedo / 3.141592 + specular) * NdL;
}

vec3 trace(vec3 rd, vec3 eye, inout uint s){
    const float e = 0.001;
    vec3 col = vec3(0.0);
    vec3 mask = vec3(1.0);
    
    for(int i = 0; i < 5; i++){
        vec2 sam;
        
        for(int j = 0; j < 60; j++){
            sam = sdf_map(eye);
            if(abs(sam.x) < e){
                break;
            }
            eye = eye + rd * sam.x;
        }

        const int sdf_id = int(sam.y);
        if(sdf_id < 0 || sdf_id >= num_sdfs)
            break;

        vec3 N;
        vec2 uv;
        {
            mat3 TBN;
            TBN[2] = sdf_map_normal(eye);
            TBN[0] = normalize(cross(TBN[2], normalize(vec3(0.01 * rand(s), 1.0, 0.0))));
            TBN[1] = cross(TBN[2], TBN[0]);
            uv = uv_from_ray(TBN[2], eye) * sdf_uv_scale(sdf_id);
            const vec4 tN = sdf_normal_texture(sdf_id, uv);
            N = TBN * normalize(tN.xyz * 2.0 - 1.0);
        }
        
        const vec3 V = -rd;
        rd = uniHemi(N, s);
        eye += N * e * 4.0f;

        const vec4 albedo = sdf_albedo_texture(sdf_id, uv);
        const vec4 material = sdf_material_texture(sdf_id, uv);

        col += mask * albedo.rgb * albedo.a * 100.0;
        mask *= pbr_lighting(V, rd, N, albedo.xyz, material.x, material.y);
    }
    
    return col;
}

void main(){
    const ivec2 pix = ivec2(gl_GlobalInvocationID.xy);  
    const ivec2 size = imageSize(color);
    if (pix.x >= size.x || pix.y >= size.y) return;
    
    uint s = uint(seed.z + 10000.0 * dot(seed.xy, gl_GlobalInvocationID.xy));
    const vec2 aa = vec2(rand(s), rand(s)) * 0.5;
    const vec2 uv = (vec2(pix + aa) / vec2(size))* 2.0 - 1.0;
    const vec3 rd = normalize(toWorld(uv.x, uv.y, 0.0) - EYE);
    
    vec3 col = trace(rd, EYE, s);
    const vec3 oldcol = imageLoad(color, pix).rgb;
    
    col = mix(oldcol, col, 1.0 / SAMPLES);
    
    imageStore(color, pix, vec4(col, 1.0));
}
