//
//  ShaderTypes.h
//  game_of_life
//
//  Created by Tim Bell on 2/7/2024.
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

#ifdef __METAL_VERSION__

#include <metal_stdlib>
//using namespace metal;
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
typedef metal::int32_t EnumBackingType;
#define METAL_ATTRIBUTE(attribute) [[attribute]]
#define exp_function metal::exp
#define ASSERT(x)
#define METAL_DEVICE_ADDRESS_SPACE device
#define METAL_CONSTANT_ADDRESS_SPACE constant

#else

#import <Foundation/Foundation.h>
#import <math.h>
#import <assert.h>
typedef NSInteger EnumBackingType;
#define METAL_ATTRIBUTE(attribute)
#define exp_function expf
#define ASSERT(x) assert(x)
#define METAL_DEVICE_ADDRESS_SPACE
#define METAL_CONSTANT_ADDRESS_SPACE

#endif

// MARK: helpers
matrix_float4x4 scale2d(float x, float y) {
    return (matrix_float4x4){(vector_float4){x, 0.0, 0.0, 0.0}, (vector_float4){0.0, y, 0.0, 0.0}, (vector_float4){0.0, 0.0, 1.0, 0.0}, (vector_float4){0.0, 0.0, 0.0, 1.0}};
}

inline matrix_float4x4 scale2dv(vector_float2 by) {
    return scale2d(by.x, by.y);
}

matrix_float4x4 translate2d(float x, float y) {
    return (matrix_float4x4){
        (vector_float4){1.0, 0.0, 0.0, 0.0},
        (vector_float4){0.0, 1.0, 0.0, 0.0},
        (vector_float4){0.0, 0.0, 1.0, 0.0},
        (vector_float4){x, y, 0.0, 1.0}};
}

inline matrix_float4x4 translate2dv(vector_float2 by) {
    return translate2d(by.x, by.y);
}

matrix_float4x4 translate3d(float x, float y, float z) {
    return (matrix_float4x4){
        (vector_float4){1.0, 0.0, 0.0, 0.0},
        (vector_float4){0.0, 1.0, 0.0, 0.0},
        (vector_float4){0.0, 0.0, 1.0, 0.0},
        (vector_float4){x, y, z, 1.0}};
}

inline matrix_float4x4 translate3dv(vector_float3 by) {
    return translate3d(by.x, by.y, by.z);
}

// MARK: game of life

typedef uint8_t GameOfLifeData;

typedef struct {
    vector_float2 position;
} GameOfLifeVertexIn;

typedef struct {
    uint32_t board_cell_count_1d;
    matrix_float4x4 projection_matrix;
} GameOfLifeUniforms;

typedef struct {
    vector_float4 position METAL_ATTRIBUTE(position);
    vector_float3 colour METAL_ATTRIBUTE(flat);
} GameOfLifeVertexOut;

typedef NS_ENUM(EnumBackingType, GameOfLifeVertexBufferIndex)
{
   GameOfLifeVertexBufferIndex_Vertices = 0,
   GameOfLifeVertexBufferIndex_Uniforms = 1,
   GameOfLifeVertexBufferIndex_Data = 2
};

typedef NS_ENUM(EnumBackingType, GameOfLifeUpdateBufferIndex)
{
   GameOfLifeUpdateBufferIndex_Uniforms = 0,
   GameOfLifeUpdateBufferIndex_DataIn = 1,
   GameOfLifeUpdateBufferIndex_DataOut = 2
};

// MARK: smooth life

typedef float SmoothLifeData;

typedef struct {
    vector_float2 position;
} SmoothLifeVertexIn;

typedef struct {
    matrix_float4x4 projection_matrix;
    uint32_t board_cell_count_1d;
    uint32_t inner_radius_cell_count;
    uint32_t outer_radius_cell_count;
    uint8_t inner_radius;
    uint8_t outer_radius;
} SmoothLifeUniforms;

typedef struct {
    vector_float4 position METAL_ATTRIBUTE(position);
    float colour METAL_ATTRIBUTE(flat);
} SmoothLifeVertexOut;

typedef NS_ENUM(EnumBackingType, SmoothLifeVertexBufferIndex)
{
   SmoothLifeVertexBufferIndex_Vertices = 0,
   SmoothLifeVertexBufferIndex_Uniforms = 1,
   SmoothLifeVertexBufferIndex_Data = 2
};

typedef NS_ENUM(EnumBackingType, SmoothLifeUpdateBufferIndex)
{
   SmoothLifeUpdateBufferIndex_Uniforms = 0,
   SmoothLifeUpdateBufferIndex_DataIn = 1,
   SmoothLifeUpdateBufferIndex_DataOut = 2,
    SmoothLifeUpdateBufferIndex_RadiusIndex = 3
};

float sigma_1(float x, float a, float alpha){
	return 1.0f / (1.0f + exp_function(-(x - a) * 4 / alpha));
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
	const float result = sigma_2(outer, sigma_inner_o1, sigma_inner_o2, alpha_outer);
    ASSERT(result >= 0.0 && result <= 1.0);
    return result;
}

void smooth_life_cell(uint32_t index, METAL_CONSTANT_ADDRESS_SPACE const SmoothLifeData* in, METAL_DEVICE_ADDRESS_SPACE SmoothLifeData* out, METAL_CONSTANT_ADDRESS_SPACE uint32_t* radius_index, uint32_t board_cell_count_1d, uint32_t inner_radius_cell_count, uint32_t outer_radius_cell_count) {
    const uint32_t r = index / board_cell_count_1d;
    const uint32_t c = index % board_cell_count_1d;
    const uint32_t data_index = r * board_cell_count_1d + c;

    float inner_count = 0.0;
    for (uint32_t i = 0; i < inner_radius_cell_count; ++i) {
        const uint32_t neighbor_r = (r + radius_index[i * 2 + 1]) % board_cell_count_1d;
        const uint32_t neighbor_c = (c + radius_index[i * 2]) % board_cell_count_1d;
        const uint32_t neighbor_index = neighbor_r * board_cell_count_1d + neighbor_c;
        inner_count += in[neighbor_index];
    }
    inner_count /= (float)(inner_radius_cell_count);
    
    float outer_count = 0.0;
    for (uint32_t i = inner_radius_cell_count; i < inner_radius_cell_count + outer_radius_cell_count; ++i) {
        const uint32_t neighbor_r = (r + radius_index[i * 2 + 1]) % board_cell_count_1d;
        const uint32_t neighbor_c = (c + radius_index[i * 2]) % board_cell_count_1d;
        const uint32_t neighbor_index = neighbor_r * board_cell_count_1d + neighbor_c;
        outer_count += in[neighbor_index];
    }
    outer_count /= (float)(outer_radius_cell_count);
    
    out[data_index] = s(inner_count, outer_count);
}


#endif /* ShaderTypes_h */
