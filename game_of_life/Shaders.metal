
#include <metal_stdlib>
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

float sigma_1(float x, float a, float alpha){
	return 1.0f / (1.0f + exp(-(x - a) * 4 / alpha));
}

float sigma_2(float x, float a, float b, float alpha){
	return sigma_1(x, a, alpha)*(1 - sigma_1(x, b, alpha));
}

float sigma_inner(float x, float y, float inner, float alpha){
	const float sigma_1_o = sigma_1(inner, 0.5f, alpha);
	return x * (1 - sigma_1_o) + y * sigma_1_o;
}

float s(float inner, float outer){
    const float b_1 = 0.278;
    const float b_2 = 0.365;
    const float d_1 = 0.267;
    const float d_2 = 0.445;
    const float alpha_outer = 0.028;
    const float alpha_inner = 0.147;

	const float sigma_inner_o1 = sigma_inner(b_1, d_1, inner, alpha_inner);
	const float sigma_inner_o2 = sigma_inner(b_2, d_2, inner, alpha_inner);
	return sigma_2(outer, sigma_inner_o1, sigma_inner_o2, alpha_outer);
}

kernel void smooth_life_update(uint index [[thread_position_in_grid]],
                         constant SmoothLifeUniforms& uniforms [[buffer(SmoothLifeUpdateBufferIndex_Uniforms)]],
                         constant const SmoothLifeData* in [[buffer(SmoothLifeUpdateBufferIndex_DataIn)]],
                         device SmoothLifeData* out [[buffer(SmoothLifeUpdateBufferIndex_DataOut)]],
                         constant uint32_t* radius_index [[buffer(SmoothLifeUpdateBufferIndex_RadiusIndex)]]) {
    const uint32_t r = index / uniforms.board_cell_count_1d;
    const uint32_t c = index % uniforms.board_cell_count_1d;
    const uint32_t data_index = r * uniforms.board_cell_count_1d + c;

    float inner_count = 0.0;
    for (uint32_t i = 0; i < uniforms.inner_radius_cell_count; ++i) {
        const uint32_t neighbor_r = (r + radius_index[i * 2 + 1]) % uniforms.board_cell_count_1d;
        const uint32_t neighbor_c = (c + radius_index[i * 2]) % uniforms.board_cell_count_1d;
        const uint32_t neighbor_index = neighbor_r * uniforms.board_cell_count_1d + neighbor_c;
        inner_count += in[neighbor_index];
    }
    inner_count /= float(uniforms.inner_radius_cell_count);
    
    float outer_count = 0.0;
    for (uint32_t i = uniforms.inner_radius_cell_count; i < uniforms.inner_radius_cell_count + uniforms.outer_radius_cell_count; ++i) {
        const uint32_t neighbor_r = (r + radius_index[i * 2 + 1]) % uniforms.board_cell_count_1d;
        const uint32_t neighbor_c = (c + radius_index[i * 2]) % uniforms.board_cell_count_1d;
        const uint32_t neighbor_index = neighbor_r * uniforms.board_cell_count_1d + neighbor_c;
        outer_count += in[neighbor_index];
    }
    outer_count /= float(uniforms.outer_radius_cell_count);
    
    out[data_index] = s(inner_count, outer_count);
}
