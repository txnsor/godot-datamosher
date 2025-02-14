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
    float MOSH_FLAG;
    float MOSH_DEPTH_FACTOR;
} p;

#define SCALE 21
#define DEPTH_FACTOR 25.0

// rng
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

    // lerp mosh frame with regular frame
    vec4 res;
    res = (imageLoad(SCREEN_TEXTURE, xy) * vec4(1.0 - p.MOSH_FLAG)) + (imageLoad(PREVIOUS_TEXTURE, xy2) * vec4(p.MOSH_FLAG));

    // set up depth buffer
    float depth = texelFetch(DEPTH_TEXTURE, xy, 0).x;
    mat4 inv_proj = inverse(p.PROJECTION_MATRIX);
    float lin_depth = 1.0 / (depth * inv_proj[2].w + inv_proj[3].w);
    lin_depth /= p.MOSH_DEPTH_FACTOR;

    // use depth buffer to blend mosh and regular frame
    vec4 mosh = imageLoad(PREVIOUS_TEXTURE, xy2);
    vec4 regular = imageLoad(SCREEN_TEXTURE, xy);
    vec4 blended = mosh*min(1.0, lin_depth) + (regular*(1.0 - min(1.0, lin_depth)));
    blended = (blended*p.MOSH_FLAG) + (regular*(1.0 - p.MOSH_FLAG));
    imageStore(SCREEN_TEXTURE, xy, blended);
}