#include <metal_stdlib>
using namespace metal;
struct NGTransportVertex { float4 position [[position]]; float2 uv; };
vertex NGTransportVertex ng_transport_vertex(uint i [[vertex_id]]) {
    float2 p=float2((i<<1)&2,i&2);
    return {float4(p*float2(2,-2)+float2(-1,1),0,1),p};
}
// Normalised sampling/format transport only. The material shaders stay the
// project's existing Theseus/Glassify shaders; this adds no glass effect.
fragment float4 ng_transport_copy(NGTransportVertex v [[stage_in]],texture2d<float> source [[texture(0)]]) {
    constexpr sampler s(filter::linear,address::clamp_to_edge);
    return source.sample(s,v.uv);
}
