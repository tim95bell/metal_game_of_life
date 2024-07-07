
#include "ShaderTypes.h"

using namespace metal;

// MARK: game of life
vertex GameOfLifeVertexOut game_of_life_vertex(const uint vid [[vertex_id]],
                                 const uint instance_id [[instance_id]],
                                 constant GameOfLifeVertexIn* vertices [[buffer(GameOfLifeVertexBufferIndex_Vertices)]],
                                 constant GameOfLifeUniforms& uniforms [[buffer(GameOfLifeVertexBufferIndex_Uniforms)]],
                                 constant GameOfLifeData* data [[buffer(GameOfLifeVertexBufferIndex_Data)]]) {
    GameOfLifeVertexOut out;
    const uint32_t r_size = uniforms.board_cell_count_1d + 2;
    const uint32_t r = instance_id / uniforms.board_cell_count_1d;
    const uint32_t c = instance_id % uniforms.board_cell_count_1d;
    const uint32_t data_index = (r + 1) * r_size + (c + 1);
    float4x4 model_matrix = translate2dv(float2(c, r));
    out.position = uniforms.projection_matrix * model_matrix * float4(vertices[vid].position, 0.0, 1.0);
    out.colour = data[data_index] ? float3(1.0, 1.0, 1.0) : float3(0.0, 0.0, 0.0);
    return out;
}

fragment float4 game_of_life_fragment(GameOfLifeVertexOut in [[stage_in]]) {
    return float4(in.colour, 1.0);
}

kernel void game_of_life_update(uint index [[thread_position_in_grid]],
                         constant GameOfLifeUniforms& uniforms [[buffer(GameOfLifeUpdateBufferIndex_Uniforms)]],
                         constant const GameOfLifeData* in [[buffer(GameOfLifeUpdateBufferIndex_DataIn)]],
                         device GameOfLifeData* out [[buffer(GameOfLifeUpdateBufferIndex_DataOut)]]) {
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

// MARK: smooth life
vertex SmoothLifeVertexOut smooth_life_vertex(const uint vid [[vertex_id]],
                                 const uint instance_id [[instance_id]],
                                 constant SmoothLifeVertexIn* vertices [[buffer(SmoothLifeVertexBufferIndex_Vertices)]],
                                 constant SmoothLifeUniforms& uniforms [[buffer(SmoothLifeVertexBufferIndex_Uniforms)]],
                                 constant SmoothLifeData* data [[buffer(SmoothLifeVertexBufferIndex_Data)]]) {
    SmoothLifeVertexOut out;
    const uint32_t r = instance_id / uniforms.board_cell_count_1d;
    const uint32_t c = instance_id % uniforms.board_cell_count_1d;
    const uint32_t data_index = r * uniforms.board_cell_count_1d + c;
    float4x4 model_matrix = translate2dv(float2(c, r));
    out.position = uniforms.projection_matrix * model_matrix * float4(vertices[vid].position, 0.0, 1.0);
    out.colour = data[data_index];
    return out;
}

fragment float4 smooth_life_fragment(SmoothLifeVertexOut in [[stage_in]]) {
    return float4(in.colour, in.colour, in.colour, 1.0);
}

kernel void smooth_life_update(uint index [[thread_position_in_grid]],
                         constant SmoothLifeUniforms& uniforms [[buffer(SmoothLifeUpdateBufferIndex_Uniforms)]],
                         constant const SmoothLifeData* in [[buffer(SmoothLifeUpdateBufferIndex_DataIn)]],
                         device SmoothLifeData* out [[buffer(SmoothLifeUpdateBufferIndex_DataOut)]],
                         constant uint32_t* radius_index [[buffer(SmoothLifeUpdateBufferIndex_RadiusIndex)]]) {
    smooth_life_cell(index, in, out, radius_index, uniforms.board_cell_count_1d, uniforms.inner_radius_cell_count, uniforms.outer_radius_cell_count);
}
