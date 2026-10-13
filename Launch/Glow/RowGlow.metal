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
// blobs: 14 floats each, [rx, ry, cx, cy, r, g, b, a0, p1, a1, p2, a2, p3, along]
//   Alpha over the normalised distance t from the centre falls piecewise linearly
//   through (0, a0) → (p1, a1) → (p2, a2) → (p3, 0), and is 0 beyond p3.
//   `along` is 1 for a blob on a left or right edge (its ry runs along the border).
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

// Arc-length coordinates along a rounded rectangle's border. Returns
// float3(s, d, P): s is the clockwise distance along the border from the top
// centre, d the distance inside it (negative outside) and P the perimeter. The
// corners are circular arcs: this only places blobs along the border, so it
// moves one by a fraction of a point at most and does not touch the edge.
static float3 borderPathCoord(float2 rel, float2 halfSize, float r) {
    float ex = max(halfSize.x - r, 0.0);
    float ey = max(halfSize.y - r, 0.0);
    float arc = 0.5 * M_PI_F * r;
    float P = 4.0 * ex + 4.0 * ey + 4.0 * arc;
    float halfPi = 0.5 * M_PI_F;
    float x = rel.x, y = rel.y;
    float ax = fabs(x), ay = fabs(y);

    if (ax > ex && ay > ey) {
        float2 k = float2(copysign(ex, x), copysign(ey, y));
        float2 v = rel - k;
        float d = r - length(v);
        float a, base;
        if (x >= 0.0 && y < 0.0)  { a = atan2(v.x, -v.y);  base = ex; }
        else if (x >= 0.0)        { a = atan2(v.y, v.x);   base = ex + arc + 2.0 * ey; }
        else if (y >= 0.0)        { a = atan2(-v.x, v.y);  base = 3.0 * ex + 2.0 * arc + 2.0 * ey; }
        else                      { a = atan2(-v.y, -v.x); base = 3.0 * ex + 3.0 * arc + 4.0 * ey; }
        return float3(base + r * clamp(a, 0.0, halfPi), d, P);
    }

    bool vertBand;
    if (ax > ex)      vertBand = true;
    else if (ay > ey) vertBand = false;
    else              vertBand = (halfSize.x - ax) < (halfSize.y - ay);

    if (vertBand) {
        if (x >= 0.0) return float3(ex + arc + (y + ey), halfSize.x - x, P);
        return float3(3.0 * ex + 3.0 * arc + 2.0 * ey + (ey - y), x + halfSize.x, P);
    }
    if (y < 0.0) {
        return float3((x >= 0.0) ? x : P + x, y + halfSize.y, P);
    }
    return float3(ex + 2.0 * arc + 2.0 * ey + (ex - x), halfSize.y - y, P);
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
    float wrapCorners,      // 1 = place blobs along the border, round the corners
    device const float *blobs, int blobCount,
    device const float *cm, int cmCount,
    float opacity
) {
    float2 rel = position - size * 0.5;
    float2 halfSize = size * 0.5;
    bool wrap = wrapCorners > 0.5;

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

    float3 path = float3(0.0);
    if (wrap) path = borderPathCoord(rel, halfSize, radius);

    // Edge fade for the area. Wrapped, it follows the border's inside distance,
    // so it bends round the corners instead of forming a square.
    float mask = 1.0;
    if (geomKind > 0.5 && edgeMaskPx > 0.0) {
        if (wrap) {
            mask *= clamp(1.0 - path.y / edgeMaskPx, 0.0, 1.0);
        } else {
            float ev = max(1.0 - position.y / edgeMaskPx, 1.0 - (size.y - position.y) / edgeMaskPx);
            float eh = max(1.0 - position.x / edgeMaskPx, 1.0 - (size.x - position.x) / edgeMaskPx);
            mask *= clamp(max(ev, 0.0) + max(eh, 0.0), 0.0, 1.0);
        }
    }
    if (mask <= 0.001) return half4(0.0);

    // Blob stack, premultiplied, first blob on top. Wrapped, a blob is measured
    // along the border and inward from it, so a glow bends round a corner
    // instead of two straight-edged ellipses overlapping where edges meet.
    float4 acc = float4(0.0);
    int count = blobCount / 14;
    for (int i = count - 1; i >= 0; i--) {
        device const float *e = blobs + i * 14;
        float rx = max(e[0], 0.001);
        float ry = max(e[1], 0.001);
        float2 centre = float2(e[2], e[3]);
        float t;
        if (wrap) {
            float3 at = borderPathCoord(centre - halfSize, halfSize, radius);
            float along = path.x - at.x;
            along -= path.z * rint(along / max(path.z, 0.0001));
            float inward = path.y - at.y;
            bool vertical = e[13] > 0.5;
            t = length(float2(along / (vertical ? ry : rx), inward / (vertical ? rx : ry)));
        } else {
            t = length((position - centre) / float2(rx, ry));
        }
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
