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

#define SCALE 21


float nrand(float x, float y) {return fract(sin(dot(vec2(x, y), vec2(12.9898, 78.233))) * 43758.5453);}

void main() {
    ivec2 xy = ivec2(gl_GlobalInvocationID.xy);
    int time = p.TIME;
    vec2 size = p.SCREEN_SIZE;

    // the current pixel
    // make sure nothing outside compute space is accessed
    if (xy.x >= size.x || xy.y >= size.y) {
        return;
    }

    // set up xy blocks
    ivec2 xyr = ivec2(vec2(xy)/SCALE)*SCALE;
    // set up random noise
    float n = nrand(time, xyr.x*xyr.y);

    // access and alter motion vectors
    vec4 motion = imageLoad(VELOCITY_TEXTURE, xyr);
    motion = max(abs(motion)-round(n/1.4),0)*sign(motion);

    // displace the screen using the motion
    ivec2 xy2 = ivec2(xy + ivec2(motion.rg*size));
    xy2.x = xy2.x % int(size.x);
    xy2.y = xy2.y % int(size.y);


    vec4 res;
    // either refresh the frame or mosh it
    if (time % 10000 < 100) {
        res = imageLoad(SCREEN_TEXTURE, xy2);
    } else {
        res = imageLoad(PREVIOUS_TEXTURE, xy2);
    }

    imageStore(SCREEN_TEXTURE, xy, res);
}