#[compute]
#version 450
// workgroups
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
// textures
layout(rgba16f, set = 0, binding = 0) uniform image2D SCREEN_TEXTURE;
layout(set = 1, binding = 0) uniform sampler2D DEPTH_TEXTURE;
layout(rgba16f, set = 2, binding = 0) uniform image2D VELOCITY_TEXTURE;
layout(rgba16f, set = 3, binding = 0) uniform image2D PREVIOUS_TEXTURE;
// params
layout(set = 4, binding = 0, std430) restrict buffer Params {
    mat4 INV_VIEW_MATRIX;
    mat4 PROJECTION_MATRIX;
    vec2 SCREEN_SIZE;
    int TIME;
} p;

#define AMT 2.1
#define PHI 1.61803398874989484820459
#define SCALE 9.0
#define REFRESH_RATE 12500
#define REFRESH_LIM REFRESH_RATE*0.01

float gold_noise(in vec2 xy, in float seed){
       return fract(tan(distance(xy*PHI, xy)*seed)*xy.x);
}

void main() {
    ivec2 xy = ivec2(gl_GlobalInvocationID.xy);
    int time = p.TIME;
    vec2 size = p.SCREEN_SIZE;

    // vec2 uv = vec2(xy) / p.SCREEN_SIZE;

    // the current pixel
    // make sure nothing outside compute space is accessed
    if (xy.x >= size.x || xy.y >= size.y) {
        return;
    }

    ivec2 floor_xy = ivec2(vec2(xy)/SCALE)*int(SCALE);
    float rand_factor = gold_noise(xy, time);

    // access screen textures
    vec4 color = imageLoad(SCREEN_TEXTURE, xy);
    vec4 motion = imageLoad(VELOCITY_TEXTURE, xy);

    // get offset
    ivec2 xy_offset = ivec2(vec2(AMT)*motion.rg*size);

    // get new mapping (uv displacement), but account for black space
    ivec2 xy2 = ivec2(xy + ivec2(xy_offset));
    xy2.x = xy2.x % int(size.x);
    xy2.y = xy2.y % int(size.y);

    vec4 res;

    if (time % REFRESH_RATE < REFRESH_LIM) {
        res = imageLoad(SCREEN_TEXTURE, xy2);
    } else {
        res = imageLoad(PREVIOUS_TEXTURE, xy2);
    }
    imageStore(SCREEN_TEXTURE, xy, res);
}