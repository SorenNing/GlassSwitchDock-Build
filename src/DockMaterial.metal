// Appended to the pinned Theseus shader at build time. The functions below
// are the actual upstream shapeDistance/shapeGradient/edgeReflection/glassLight.
// No source texture, sampler, wallpaper, capture or time parameter exists.
struct NGDockParams { float2 size; float radius; float scale; uint dark; uint prominent; uint corners; };
kernel void ngDockMaterial(texture2d<float, access::write> output [[texture(0)]],
                           constant NGDockParams& p [[buffer(0)]],
                           uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
    float2 q = (float2(gid) + 0.5) / p.scale;
    float2 hs = p.size * 0.5;
    uint corner = q.y < hs.y ? (q.x < hs.x ? 1u : 2u) : (q.x < hs.x ? 4u : 8u);
    float radius = (p.corners & corner) != 0 ? p.radius : 0.0;
    float d = shapeDistance(q, hs, hs, radius);
    float2 n = shapeGradient(q, hs, hs, radius);
    float depth = max(-d, 0.0);
    float coverage = clamp(0.5 - d * p.scale, 0.0, 1.0);
    float facing = dot(n, normalize(LIGHT_VECTOR));
    // Keep the face almost clear; concentrate optical shading near the edge.
    float edgeWeight = exp(-depth / 6.0);
    float light = glassLight(depth, 1.0 / p.scale, 4.0, -0.35, 0.5, 0.7, facing) * edgeWeight;
    float reflection = edgeReflection(n, float2(0.0, -1.0)) * exp(-depth / 5.0);
    float thickness = exp(-depth / 7.0) * (0.5 + 0.5 * n.y);
    float strength = p.prominent != 0 ? 1.2 : 1.0;
    float alpha = ((p.dark != 0 ? 0.015 : 0.025) + 0.22 * light + 0.16 * reflection + 0.09 * thickness) * strength;
    alpha = clamp(alpha * coverage, 0.0, 0.8);
    float3 tint = mix(float3(0.64, 0.71, 0.80), float3(1.0), clamp(0.75 + light + reflection - thickness * 0.55, 0.0, 1.0));
    // Premultiplied RGBA. Outside is transparent, never an opaque black base.
    output.write(float4(tint * alpha, alpha), gid);
}
