#include <metal_stdlib>
using namespace metal;

// The glow on the selected row. Adapted from the pulse-inner layer shader of
// BorderBeamKit (border-beam by Jakub Antalik, MIT, see NOTICE.md), cut down to
// what Launch draws, with SwiftUI's continuous corners in place of circular ones
// and no colour of its own: every colour comes in through `blobs`.
//
// A glow is a stack of "blobs", ellipses of one colour whose alpha falls off from
// the centre, composited source-over (first on top), inside a rounded rectangle:
// either its whole area (`geomKind` 1, faded out over `edgeMaskPx` from the edge)
// or just its border ring (`geomKind` 0). A blob's centre and radii are in the
// layer's own points.
//
// blobs: 13 floats each, [rx, ry, cx, cy, r, g, b, a0, p1, a1, p2, a2, p3]
//   Alpha over the normalised distance t from the centre falls piecewise linearly
//   through (0, a0) → (p1, a1) → (p2, a2) → (p3, 0), and is 0 beyond p3.
// cm: a row-major 3x3 colour matrix applied to the blended colour.

// Continuous corners, as SwiftUI's `.continuous`: a superellipse corner fitted to
// the path SwiftUI draws for RoundedRectangle(style: .continuous). An extent of
// 1.22 x the radius and an exponent of 2.55 stay within 0.04 pt of it at any
// radius. A first-order signed distance (the gradient of the superellipse norm
// divides it out), so a 1 pt ring stays 1 pt wide through the corners.
constant float kContinuousExtent = 1.22;
constant float kContinuousExponent = 2.55;

static float continuousRoundedRectSDF(float2 p, float2 halfSize, float radius) {
    float R = min(radius * kContinuousExtent, min(halfSize.x, halfSize.y));
    float2 q = abs(p) - halfSize + R;
    if (R <= 0.0) return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
    if (q.x > 0.0 && q.y > 0.0) {
        float n = kContinuousExponent;
        float norm = pow(pow(q.x, n) + pow(q.y, n), 1.0 / n);
        float2 g = pow(q / norm, float2(n - 1.0));
        return (norm - R) / length(g);
    }
    return max(q.x, q.y) - R;
}

static float stopAlpha(float t, float a0, float p1, float a1, float p2, float a2, float p3) {
    if (t >= p3) return 0.0;
    if (t <= 0.0) return a0;
    if (t < p1) return mix(a0, a1, t / max(p1, 0.0001));
    if (t < p2) return mix(a1, a2, (t - p1) / max(p2 - p1, 0.0001));
    return mix(a2, 0.0, (t - p2) / max(p3 - p2, 0.0001));
}

static float4 srcOver(float4 src, float4 dst) {
    return src + dst * (1.0 - src.a);
}

[[ stitchable ]] half4 rowGlowLayer(
    float2 position,
    half4 inColor,
    float2 size,
    float radius,
    float borderWidth,
    float geomKind,         // 0 = border ring, 1 = whole area
    float edgeMaskPx,       // area only: fade out over this distance from the edge
    device const float *blobs, int blobCount,
    device const float *cm, int cmCount,
    float opacity
) {
    float2 rel = position - size * 0.5;
    float2 halfSize = size * 0.5;

    // The shape: the whole rounded rectangle, or the band between it and itself
    // inset by the border width.
    float aa = 1.0;
    float outerSDF = continuousRoundedRectSDF(rel, halfSize, radius);
    float geom = 1.0 - smoothstep(-aa, 0.0, outerSDF);
    if (geomKind < 0.5) {
        // A continuous corner's extent is 1.22 x its radius, so the radius gives
        // up border / 1.22 to lose a border's width.
        float innerRadius = max(radius - borderWidth / kContinuousExtent, 0.0);
        float innerSDF = continuousRoundedRectSDF(rel, halfSize - borderWidth, innerRadius);
        geom -= 1.0 - smoothstep(-aa, 0.0, innerSDF);
    }
    if (geom <= 0.0) return half4(0.0);

    // Edge fade for the area: the sum of a fade in from the top and bottom and one
    // in from the left and right. A sum has no crease where the two meet, and
    // when `edgeMaskPx` is half the height or less the vertical fade reaches
    // exactly zero in the middle, so nothing shows there either. (Measuring the
    // fade as the distance to the nearest edge does crease, along the diagonals
    // at the ends of a short row.)
    float mask = 1.0;
    if (geomKind > 0.5 && edgeMaskPx > 0.0) {
        float vertical = max(1.0 - position.y / edgeMaskPx, 1.0 - (size.y - position.y) / edgeMaskPx);
        float horizontal = max(1.0 - position.x / edgeMaskPx, 1.0 - (size.x - position.x) / edgeMaskPx);
        mask = clamp(max(vertical, 0.0) + max(horizontal, 0.0), 0.0, 1.0);
    }
    if (mask <= 0.001) return half4(0.0);

    // Blob stack, premultiplied, first blob on top.
    float4 acc = float4(0.0);
    int count = blobCount / 13;
    for (int i = count - 1; i >= 0; i--) {
        device const float *e = blobs + i * 13;
        float rx = max(e[0], 0.001);
        float ry = max(e[1], 0.001);
        float2 centre = float2(e[2], e[3]);
        float t = length((position - centre) / float2(rx, ry));
        float alpha = stopAlpha(t, e[7], e[8], e[9], e[10], e[11], e[12]);
        if (alpha <= 0.0) continue;
        acc = srcOver(float4(float3(e[4], e[5], e[6]) * alpha, alpha), acc);
    }

    if (acc.a > 0.0001 && cmCount >= 9) {
        float3 rgb = acc.rgb / acc.a;
        float3 mapped = float3(
            dot(float3(cm[0], cm[1], cm[2]), rgb),
            dot(float3(cm[3], cm[4], cm[5]), rgb),
            dot(float3(cm[6], cm[7], cm[8]), rgb)
        );
        acc.rgb = clamp(mapped, 0.0, 1.0) * acc.a;
    }

    float alpha = acc.a * geom * mask * clamp(opacity, 0.0, 1.0);
    if (acc.a <= 0.0001) return half4(0.0);
    return half4(half3(acc.rgb / acc.a) * alpha, alpha);
}
