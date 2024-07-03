
#include <metal_stdlib>
#include "ShaderTypes.h"

using namespace metal;

vertex VertexOut vertex_function(const uint vid [[vertex_id]],
                                 const uint instance_id [[instance_id]],
                                 constant VertexIn* vertices [[buffer(VertexBufferIndex_Vertices)]],
                                 constant Uniforms& uniforms [[buffer(VertexBufferIndex_Uniforms)]],
                                 constant uint8_t* data [[buffer(VertexBufferIndex_Data)]]) {
    VertexOut out;
    const uint32_t r_size = uniforms.board_cell_count_1d + 2;
    const uint32_t r = instance_id / uniforms.board_cell_count_1d;
    const uint32_t c = instance_id % uniforms.board_cell_count_1d;
    const uint32_t data_index = (r + 1) * r_size + (c + 1);
    float4x4 model_matrix = translate2dv(float2(c, r));
    out.position = uniforms.projection_matrix * model_matrix * float4(vertices[vid].position, 0.0, 1.0);
    out.colour = data[data_index] ? float3(1.0, 1.0, 1.0) : float3(0.0, 0.0, 0.0);
    return out;
}

fragment float4 fragment_function(VertexOut in [[stage_in]]) {
    return float4(in.colour, 1.0);
}

kernel void game_of_life(uint index [[thread_position_in_grid]],
                         constant Uniforms& uniforms [[buffer(GameOfLifeBufferIndex_Uniforms)]],
                         constant const uint8_t* in [[buffer(GameOfLifeBufferIndex_DataIn)]],
                         device uint8_t* out [[buffer(GameOfLifeBufferIndex_DataOut)]]) {
    const uint32_t r_size = uniforms.board_cell_count_1d + 2;
    const uint32_t r = index / uniforms.board_cell_count_1d;
    const uint32_t c = index % uniforms.board_cell_count_1d;
    const uint32_t data_index = (r + 1) * r_size + (c + 1);
    uint8_t count = in[data_index - 1]
        + in[data_index + 1]
        + in[(data_index - r_size) - 1]
        + in[data_index - r_size]
        + in[(data_index - r_size) + 1]
        + in[(data_index + r_size) - 1]
        + in[data_index + r_size]
        + in[(data_index + r_size) + 1];

    out[data_index] = in[data_index] ? (count == 2 || count == 3) : (count == 3);
}
