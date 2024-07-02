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

typedef struct {
    vector_float2 position;
} VertexIn;

typedef struct {
    uint32_t board_size;
    float cell_size;
    float padding_size;
    vector_float2 board_pos;
    matrix_float4x4 projection_matrix;
} Uniforms;

typedef struct {
    vector_float4 position METAL_ATTRIBUTE(position);
    vector_float3 colour METAL_ATTRIBUTE(flat);
} VertexOut;

typedef NS_ENUM(EnumBackingType, VertexBufferIndex)
{
    VertexBufferIndex_Vertices = 0,
    VertexBufferIndex_Uniforms = 1,
    VertexBufferIndex_Data = 2
};

typedef NS_ENUM(EnumBackingType, GameOfLifeBufferIndex)
{
    GameOfLifeBufferIndex_Uniforms = 0,
    GameOfLifeBufferIndex_DataIn = 1,
    GameOfLifeBufferIndex_DataOut = 2
};

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

#endif /* ShaderTypes_h */
