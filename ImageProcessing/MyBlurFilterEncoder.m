// Copyright (c) 2016 Lightricks. All rights reserved.
// Created by Hagai Weinfeld.

#import "MyBlurFilterEncoder.h"

NS_ASSUME_NONNULL_BEGIN

struct AdjustIntegralBlurUniforms
{
  float blurRadius;
};

@interface MyBlurFilterEncoder ()

@property (strong, nonatomic) id<MTLTexture> weights;
@property (strong, nonatomic) id<MTLBuffer> uniforms;
@property (strong, nonatomic) NSString *label;

@end

@implementation MyBlurFilterEncoder

#pragma mark -
#pragma mark Initialization
#pragma mark -
- (instancetype)initWithBlurRadius:(NSUInteger)radius device:(id<MTLDevice>)device
                             label:(nonnull NSString *)label {
  if (self = [super init]) {
    _weights = [self weightTextureWithBlurRadius:radius device:device];
    _uniforms = [self uniformBufferWithBlurRadius:radius device:device];
    _label = label;
  }
  return self;
}

#pragma mark -
#pragma mark MyEncoder
#pragma mark -

- (id<MTLComputeCommandEncoder>)commandEncoderForCommandBuffer:(id<MTLCommandBuffer>)commandBuffer {
  id<MTLComputeCommandEncoder> commandEncoder = [commandBuffer computeCommandEncoder];
  commandEncoder.label = self.label;
  [commandEncoder setTexture:self.weights atIndex:3];
  [commandEncoder setBuffer:self.uniforms offset:0 atIndex:0];
  return commandEncoder;
}

#pragma mark -
#pragma mark Weight Calculation
#pragma mark -

- (id<MTLTexture>)weightTextureWithBlurRadius:(NSInteger)blurRadius device:(id<MTLDevice>)device {
  
  NSAssert(blurRadius >= 0, @"Blur radius must be non-negative");
  const float sigma = blurRadius/2;
  const int size = (round(blurRadius) * 2) + 1;
  
  float delta = 0;
  float expScale = 0;;
  delta = (blurRadius * 2) / (size - 1);;
  expScale = -1 / (2 * sigma * sigma);
  float *weights = malloc(sizeof(float) * size);
  float weightSum = 0;
  float x = -blurRadius;
  
  for (int i = 0; i < size; ++i, x += delta)
  {
    float weight = expf((x * x) * expScale);
    weights[i] = weight;
    weightSum += weight;
  }
  const float weightScale = 1 / weightSum;
  for (int i = 0; i < size; ++i)
  {
    weights[i] *= weightScale;
  }
  
  MTLTextureDescriptor *textureDescriptor =
      [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR32Float
                                                         width:size
                                                        height:1
                                                     mipmapped:NO];
  
  id<MTLTexture> weightTexture = [device newTextureWithDescriptor:textureDescriptor];
  MTLRegion region = MTLRegionMake2D(0, 0, size, 1);
  [weightTexture replaceRegion:region mipmapLevel:0 withBytes:weights
                   bytesPerRow:sizeof(float) * size];
  free(weights);
  return weightTexture;
}

- (id<MTLBuffer>)uniformBufferWithBlurRadius:(NSUInteger)radius device:(id<MTLDevice>)device {
  struct AdjustIntegralBlurUniforms uniforms;
  uniforms.blurRadius = radius;
  id<MTLBuffer> uniformBuffer = [device newBufferWithLength:sizeof(uniforms)
                                                    options:MTLResourceOptionCPUCacheModeDefault];
  memcpy([uniformBuffer contents], &uniforms, sizeof(uniforms));
  return uniformBuffer;
}



@end

NS_ASSUME_NONNULL_END
