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

//using namespace metal;
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
typedef metal::int32_t EnumBackingType;
#define METAL_ATTRIBUTE(attribute) [[attribute]]

#else

#import <Foundation/Foundation.h>
typedef NSInteger EnumBackingType;
#define METAL_ATTRIBUTE(attribute)

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

#endif /* ShaderTypes_h */
