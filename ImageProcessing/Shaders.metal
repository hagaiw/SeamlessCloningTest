//
//  Shaders.metal
//  ImageProcessing
//
//  Created by Warren Moore on 10/4/14.
//  Copyright (c) 2014 Metal By Example. All rights reserved.
//

#include <metal_stdlib>

using namespace metal;

struct AdjustSaturationUniforms
{
    float saturationFactor;
};

kernel void adjust_saturation(texture2d<float, access::read> inTexture [[texture(0)]],
                              texture2d<float, access::write> outTexture [[texture(2)]],
                              constant AdjustSaturationUniforms &uniforms [[buffer(0)]],
                              uint2 gid [[thread_position_in_grid]])
{
    float4 inColor = inTexture.read(gid);
    float value = dot(inColor.rgb, float3(0.299, 0.587, 0.114));
    float4 grayColor(value, value, value, 1.0);
    float4 outColor = mix(grayColor, inColor, uniforms.saturationFactor);
    outTexture.write(outColor, gid);
}

struct AdjustIntegralBlurUniforms
{
  float blurRadius;
};

struct OffsetUniforms
{
  float xOffset;
  float yOffset;
};

kernel void gaussian_blur_integral(texture2d<float, access::read> inTexture [[texture(0)]],
                             texture2d<float, access::read> integralImage [[texture(1)]],
                             texture2d<float, access::write> outTexture [[texture(2)]],
                             texture2d<float, access::read> weights [[texture(3)]],
                             constant AdjustIntegralBlurUniforms &uniforms [[buffer(0)]],
                             uint2 gid [[thread_position_in_grid]])
{
  
  
  
  int radius = uniforms.blurRadius;
  
  uint2 bottomRight(gid.x + radius, gid.y + radius);
  uint2 bottomLeft(gid.x - radius, gid.y + radius);
  uint2 topRight(gid.x + radius, gid.y - radius);
  uint2 topLeft(gid.x - radius, gid.y - radius);
  
  float4 bottomRightValue = integralImage.read(bottomRight).rgba;
  float4 bottomLeftValue = integralImage.read(bottomLeft).rgba;
  float4 topRightValue = integralImage.read(topRight).rgba;
  float4 topLeftValue = integralImage.read(topLeft).rgba;

  
  float4 boxBlurColor = (topLeftValue - bottomLeftValue - topRightValue + bottomRightValue) / (radius * radius * 4);
  outTexture.write(float4(boxBlurColor.rgb, 1), gid);
  
//  outTexture.write(float4(boxBlurColor.rgb, 1), gid);
  
//    int size = weights.get_width();
//    int radius = size / 2;
//    
//    float4 accumColor(0, 0, 0, 0);
//    for (int j = 0; j < size; ++j)
//    {
//        for (int i = 0; i < size; ++i)
//        {
//            uint2 kernelIndex(i, j);
//            uint2 textureIndex(gid.x + (i - radius), gid.y + (j - radius));
//            float4 color = inTexture.read(textureIndex).rgba;
//            float4 weight = weights.read(kernelIndex).rrrr;
//            accumColor += weight * color;
//        }
//    }
//
//    outTexture.write(float4(accumColor.rgb, 1), gid);
}


kernel void gaussian_blur_horizontal(texture2d<float, access::read> inTexture [[texture(0)]],
                             texture2d<float, access::read> integralImage [[texture(1)]],
                             texture2d<float, access::write> outTexture [[texture(2)]],
                             texture2d<float, access::read> weights [[texture(3)]],
                             constant AdjustIntegralBlurUniforms &uniforms [[buffer(0)]],
                             uint2 gid [[thread_position_in_grid]])
{
//  int radius = uniforms.blurRadius;
  int size = weights.get_width();
  int radius = size / 2;
  
  float4 accumColor(0, 0, 0, 0);
  for (int i = 0; i < size; ++i)
  {
    uint2 kernelIndex(i, 0);
    uint2 textureIndex(gid.x + (i - radius), gid.y);
    float4 color = inTexture.read(textureIndex).rgba;
    float4 weight = weights.read(kernelIndex).rrrr;
    accumColor += weight * color;
  }
  
  outTexture.write(float4(accumColor.rgb, 1), gid);
}

kernel void gaussian_blur_vertical(texture2d<float, access::read> inTexture [[texture(0)]],
                                     texture2d<float, access::read> integralImage [[texture(1)]],
                                     texture2d<float, access::write> outTexture [[texture(2)]],
                                     texture2d<float, access::read> weights [[texture(3)]],
                                     constant AdjustIntegralBlurUniforms &uniforms [[buffer(0)]],
                                     uint2 gid [[thread_position_in_grid]])
{
  //  int radius = uniforms.blurRadius;
  int size = weights.get_width();
  int radius = size / 2;
  
  float4 accumColor(0, 0, 0, 0);
  for (int i = 0; i < size; ++i)
  {
    uint2 kernelIndex(i, 0);
    uint2 textureIndex(gid.x, gid.y + (i - radius));
    float4 color = inTexture.read(textureIndex).rgba;
    float4 weight = weights.read(kernelIndex).rrrr;
    accumColor += weight * color;
  }
  
  outTexture.write(float4(accumColor.rgb, 1), gid);
}

kernel void diff(texture2d<float, access::read> sourceTexture [[texture(0)]],
                           texture2d<float, access::read> targetTexture [[texture(1)]],
                           texture2d<float, access::write> diffTexture [[texture(2)]],
                           constant OffsetUniforms &uniforms [[buffer(0)]],
                           uint2 gid [[thread_position_in_grid]]) {
  
  uint2 targetCoord(gid.x + uniforms.xOffset, gid.y + uniforms.yOffset);
  float4 target = targetTexture.read(targetCoord);
  diffTexture.write((float4(target.rgb -sourceTexture.read(gid).rgb, 1.0)), gid);
}

kernel void mult(texture2d<float, access::read> sourceTexture [[texture(0)]],
                 texture2d<float, access::read> targetTexture [[texture(1)]],
                 texture2d<float, access::write> diffTexture [[texture(2)]],
                 constant OffsetUniforms &uniforms [[buffer(0)]],
                 uint2 gid [[thread_position_in_grid]]) {
  diffTexture.write((float4(targetTexture.read(gid).rgb * sourceTexture.read(gid).rgb, 1.0)), gid);
}

kernel void final(texture2d<float, access::read> mixTexture [[texture(0)]],
                  texture2d<float, access::read> boundaryTexture [[texture(1)]],
                  texture2d<float, access::read> sourceTexture [[texture(2)]],
                  texture2d<float, access::read> targetTexture [[texture(3)]],
                  texture2d<float, access::read> maskTexture [[texture(4)]],
                  texture2d<float, access::write> outputTexture [[texture(5)]],
                  constant OffsetUniforms &uniforms [[buffer(0)]],
                  uint2 gid [[thread_position_in_grid]]) {
  float4 boundaryColor = boundaryTexture.read(gid);
  float4 source = sourceTexture.read(gid);
  uint2 targetCoord(gid.x + uniforms.xOffset, gid.y + uniforms.yOffset);
  float4 target = targetTexture.read(targetCoord);
  float4 mask = maskTexture.read(gid);
  
  float4 sourceColor;
  if (boundaryColor.r == 0) {
    sourceColor = float4(source.rgb, 1.0);
  } else {
    float3 divResult = mixTexture.read(gid).rgb / boundaryColor.rgb;
    sourceColor = (float4(divResult+source.rgb, 1.0));
  }
  float4 result = mix(target, sourceColor, mask);
  outputTexture.write(result,gid);
  
}










// Rec 709 LUMA values for grayscale image conversion
constant half3 kRec709Luma = half3(0.2126, 0.7152, 0.0722);

// Grayscale compute shader
kernel void grayscale(texture2d<half, access::read>  inTexture   [[ texture(0) ]],
                      texture2d<half, access::write> outTexture  [[ texture(1) ]],
                      uint2                          gid         [[ thread_position_in_grid ]])
{
  if((gid.x < outTexture.get_width()) && (gid.y < outTexture.get_height()))
  {
    half4 inColor  = inTexture.read(gid);
    half  gray     = dot(inColor.rgb, kRec709Luma);
    half4 outColor = half4(gray, gray, gray, 1.0);
    
    outTexture.write(outColor, gid);
  }
}

// Vertex input/output structure for passing results
// from a vertex shader to a fragment shader
struct VertexIO
{
  float4 m_Position [[position]];
  float2 m_TexCoord [[user(texturecoord)]];
};

// Vertex shader for a textured quad
vertex VertexIO texturedQuadVertex(device float4         *pPosition   [[ buffer(0) ]],
                                   device packed_float2  *pTexCoords  [[ buffer(1) ]],
                                   constant float4x4     &MVP         [[ buffer(2) ]],
                                   uint                   vid         [[ vertex_id ]])
{
  VertexIO outVertices;
  
  outVertices.m_Position = MVP * pPosition[vid];
  outVertices.m_TexCoord = pTexCoords[vid];
  
  return outVertices;
}

// Fragment shader for a textured quad
fragment half4 texturedQuadFragment(VertexIO         inFrag  [[ stage_in ]],
                                    texture2d<half>  tex2D   [[ texture(0) ]])
{
  constexpr sampler quadSampler;
  
  half4 color = tex2D.sample(quadSampler, inFrag.m_TexCoord);
  
  return color;
}

