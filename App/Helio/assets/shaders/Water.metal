#include <metal_stdlib>
using namespace metal;

[[ stitchable ]] float2 water(float2 position, float2 size, float time, float speed, float strength, float frequency) {
    half2 uv = half2(position / size);

    half adjustedSpeed = time * speed * 0.05h;
    half adjustedStrength = strength / 100.0h;

    uv.x += sin((uv.x + adjustedSpeed) * frequency) * adjustedStrength;
    uv.y += cos((uv.y + adjustedSpeed) * frequency) * adjustedStrength;

    return float2(uv) * size;
}
