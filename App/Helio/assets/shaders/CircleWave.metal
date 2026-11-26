#include <metal_stdlib>
using namespace metal;

[[ stitchable ]] half4 circleWave(float2 position, half4 color, float2 size, float time, float brightness, float speed, float strength, float density, float2 center, half4 circleColor) {
    if (color.a > 0.0h) {
        half2 uv = half2(position / size);

        half2 delta = uv - half2(center);

        half aspectRatio = size.x / size.y;

        delta.x *= aspectRatio;

        half pixelDistance = sqrt((delta.x * delta.x) + (delta.y * delta.y));

        half waveSpeed = -(time * speed * 10.0h);

        half3 newBrightness = half3(brightness);

        half3 gradientColor = half3(circleColor.r, circleColor.g, circleColor.b) * newBrightness;

        half colorStrength = pow(1.0h - pixelDistance, 3.0h);

        colorStrength *= strength;

        half waveDensity = density * pixelDistance;

        half cosine = cos(waveSpeed + waveDensity);

        half cosineAdjustment = (0.5h * cosine) + 0.5h;

        half luma = colorStrength * (strength + cosineAdjustment);

        luma *= 1.0h - (pixelDistance * 2.0h);
        luma = max(0.0h, luma);

        half4 finalColor = half4(gradientColor * luma, luma);

        return finalColor * color.a;
    } else {
        return color;
    }
}
