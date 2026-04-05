// Copyright (c) 2019, OpenEmu Team
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright
//       notice, this list of conditions and the following disclaimer in the
//       documentation and/or other materials provided with the distribution.
//     * Neither the name of the OpenEmu Team nor the
//       names of its contributors may be used to endorse or promote products
//       derived from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
// DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#include <metal_stdlib>
#include <simd/simd.h>

typedef enum
{
    BufferIndexUniforms  = 1,
    BufferIndexPositions = 4,
} BufferIndex;

typedef enum
{
    VertexAttributePosition = 0,
    VertexAttributeTexcoord = 1,
    VertexAttributeColor    = 2,
} VertexAttribute;

typedef enum
{
    TextureIndexColor = 0,
} TextureIndex;

typedef enum
{
    SamplerIndexDraw = 0,
} SamplerIndex;

typedef struct
{
    simd_float4 position [[attribute(VertexAttributePosition)]];
    simd_float2 texCoord [[attribute(VertexAttributeTexcoord)]];
} Vertex;

typedef struct
{
    simd_float4 position [[position]];
    simd_float2 texCoord;
} ColorInOut;

typedef struct
{
    simd_float4x4   projectionMatrix;
    simd_float2     outputSize;
    float time;
    float gamma;
    float saturation;
    float padding1;
    simd_float2 padding2;
} Uniforms;


using namespace metal;

#pragma mark - functions using projected coordinates

vertex ColorInOut basic_vertex_proj_tex(const Vertex in [[ stage_in ]],
                                        const device Uniforms &uniforms [[ buffer(BufferIndexUniforms) ]])
{
    ColorInOut out;
    out.position = uniforms.projectionMatrix * in.position;
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 basic_fragment_proj_tex(ColorInOut in [[stage_in]],
                                        constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]],
                                        texture2d<half> tex          [[ texture(TextureIndexColor) ]],
                                        sampler samp                 [[ sampler(SamplerIndexDraw) ]])
{
    half4 colorSample = tex.sample(samp, in.texCoord.xy);
    
    // Apply Gamma Correction (pre-computed inverse gamma on CPU would be ideal,
    // but we compute it here in half precision for 2x ALU throughput on Apple Silicon)
    if (uniforms.gamma != 1.0) {
        half invGamma = half(1.0h / half(uniforms.gamma));
        colorSample.rgb = pow(colorSample.rgb, half3(invGamma));
    }
    
    // Apply Saturation (entirely in half precision for 2x throughput)
    if (uniforms.saturation != 1.0) {
        half luma = dot(colorSample.rgb, half3(0.2126h, 0.7152h, 0.0722h));
        colorSample.rgb = mix(half3(luma), colorSample.rgb, half(uniforms.saturation));
    }
    
    return float4(colorSample);
}
