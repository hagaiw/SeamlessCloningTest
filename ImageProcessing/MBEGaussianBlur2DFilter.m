//
//  MBEGaussianBlur2DFilter.m
//  ImageProcessing
//
//  Created by Warren Moore on 10/8/14.
//  Copyright (c) 2014 Metal By Example. All rights reserved.
//

#import "MBEGaussianBlur2DFilter.h"
#import <Metal/Metal.h>
#import <UIKit/UIkit.h>

@import MetalPerformanceShaders;

struct AdjustIntegralBlurUniforms
{
  float blurRadius;
};

@interface MBEGaussianBlur2DFilter ()
@property (nonatomic, strong) id<MTLTexture> blurWeightTexture;
@property (nonatomic, strong) id<MTLTexture> integralImage;

@property (nonatomic, strong) id<MTLTexture> gaussianKernel1D;

@property (nonatomic) BlurType blurType;

@end

@implementation MBEGaussianBlur2DFilter

@synthesize radius = _radius;
@synthesize sigma = _sigma;

+ (instancetype)filterWithRadius:(float)radius context:(MBEContext *)context blurType:(BlurType)blurType
{
    return [[self alloc] initWithRadius:radius context:context blurType:(BlurType)blurType];
}

- (instancetype)initWithRadius:(float)radius context:(MBEContext *)context blurType:(BlurType)blurType
{
  switch (blurType) {
    case BlurTypeIntegral:
      self = [super initWithFunctionName:@"gaussian_blur_integral" context:context];
      break;
    case BlurTypeHorizontal:
      self = [super initWithFunctionName:@"gaussian_blur_horizontal" context:context];
      break;
    case BlurTypeVertical:
      self = [super initWithFunctionName:@"gaussian_blur_vertical" context:context];
      break;
    default:
      break;
  }
  
  if (self)
  {
    self.radius = radius;
    self.blurType = blurType;
  }
  return self;
}

- (void)gaussianCoefficients1D
{
  NSAssert(self.radius >= 0, @"Blur radius must be non-negative");

  NSInteger radius = self.radius;
  
  const float sigma = radius/2;
  const int size = (round(radius) * 2) + 1;
  
  float delta = 0;
  float expScale = 0;;
  if (radius > 0.0)
  {
    delta = (radius * 2) / (size - 1);;
    expScale = -1 / (2 * sigma * sigma);
  }
  
  float *weights = malloc(sizeof(float) * size);
  
  float weightSum = 0;

  float x = -radius;
    
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
  
  MTLTextureDescriptor *horizontalTextureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR32Float
                                                                                               width:size
                                                                                              height:1
                                                                                           mipmapped:NO];
  
  self.gaussianKernel1D = [self.context.device newTextureWithDescriptor:horizontalTextureDescriptor];
  
  MTLRegion horizontalRegion = MTLRegionMake2D(0, 0, size, 1);
  [self.gaussianKernel1D replaceRegion:horizontalRegion mipmapLevel:0 withBytes:weights bytesPerRow:sizeof(float) * size];
  
  free(weights);
}

- (void)divCoefficients1D
{
  NSAssert(self.radius >= 0, @"Blur radius must be non-negative");
  
  NSInteger radius = self.radius;
  int power = 1.0;
  const int size = (round(radius) * 2) + 1;
  float *weights = malloc(sizeof(float) * size);
  float weightSum = 0;
  
  for (int i = 0; i < size; ++i)
  {
    float index = i-radius;
    
    float weight;
    if (index == 0) {
      weight = 10;
    } else {
      weight = fabs(1/(pow(index, power)));
    }
    weights[i] = weight;
    weightSum += weight;
  }
  
  const float weightScale = 1 / weightSum;
  
  for (int i = 0; i < size; ++i)
  {
    weights[i] *= weightScale;
  }
  
  MTLTextureDescriptor *horizontalTextureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR32Float
                                                                                                         width:size
                                                                                                        height:1
                                                                                                     mipmapped:NO];
  
  self.gaussianKernel1D = [self.context.device newTextureWithDescriptor:horizontalTextureDescriptor];
  
  MTLRegion horizontalRegion = MTLRegionMake2D(0, 0, size, 1);
  [self.gaussianKernel1D replaceRegion:horizontalRegion mipmapLevel:0 withBytes:weights bytesPerRow:sizeof(float) * size];
  
  free(weights);
}

- (void)setRadius:(float)radius
{
    self.dirty = YES;
    _radius = radius;
    _sigma = radius / 2;
    self.gaussianKernel1D = nil;
}

- (void)setSigma:(float)sigma
{
    self.dirty = YES;
    _sigma = sigma;
    self.blurWeightTexture = nil;
}

- (void)configureArgumentTableWithCommandEncoder:(id<MTLComputeCommandEncoder>)commandEncoder
{
  
  struct AdjustIntegralBlurUniforms uniforms;
  uniforms.blurRadius = self.radius;
  if (!self.uniformBuffer)
  {
    self.uniformBuffer = [self.context.device newBufferWithLength:sizeof(uniforms)
                                                          options:MTLResourceOptionCPUCacheModeDefault];
  }
  
  memcpy([self.uniformBuffer contents], &uniforms, sizeof(uniforms));
  
  [commandEncoder setBuffer:self.uniformBuffer offset:0 atIndex:0];
  
  if (!self.gaussianKernel1D) {
//    [self gaussianCoefficients1D];
    [self divCoefficients1D];
  }
    
  [commandEncoder setTexture:self.gaussianKernel1D atIndex:3];
}

#pragma mark -
#pragma mark Overloaded Methods
#pragma mark -

- (void)applyFilter
{
  id<MTLTexture> inputTexture = self.provider.texture;
  
  if (!self.internalTexture ||
      [self.internalTexture width] != [inputTexture width] ||
      [self.internalTexture height] != [inputTexture height])
  {
    MTLTextureDescriptor *textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:[inputTexture pixelFormat]
                                                                                                 width:[inputTexture width]
                                                                                                height:[inputTexture height]
                                                                                             mipmapped:NO];
    self.internalTexture = [self.context.device newTextureWithDescriptor:textureDescriptor];
  }
  
  
//  CFTimeInterval start = CACurrentMediaTime();
  
  if (self.blurType == BlurTypeIntegral) {
    id<MTLCommandBuffer> integralCommandBuffer = [self.context.commandQueue commandBuffer];
    
    if (!self.integralImage) {
      MTLTextureDescriptor *descriptor2 = [MTLTextureDescriptor
                                           texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float
                                           width:self.internalTexture.width
                                           height:self.internalTexture.height
                                           mipmapped:NO];
      self.integralImage = [self.context.device newTextureWithDescriptor:descriptor2];
    }
    
    MPSImageIntegral *integral = [[MPSImageIntegral alloc] initWithDevice:self.context.device];
    [integral encodeToCommandBuffer:integralCommandBuffer
                      sourceTexture:inputTexture
                 destinationTexture:self.integralImage];
    
    [integralCommandBuffer commit];
  }
  
  
  MTLSize threadgroupCounts = MTLSizeMake(8, 8, 1);
  MTLSize threadgroups = MTLSizeMake([inputTexture width] / threadgroupCounts.width,
                                     [inputTexture height] / threadgroupCounts.height,
                                     1);
  
  
  id<MTLCommandBuffer> commandBuffer = [self.context.commandQueue commandBuffer];
  id<MTLComputeCommandEncoder> commandEncoder = [commandBuffer computeCommandEncoder];
  [commandEncoder setComputePipelineState:self.pipeline];
  [commandEncoder setTexture:inputTexture atIndex:0];
  [commandEncoder setTexture:self.integralImage atIndex:1];
  [commandEncoder setTexture:self.internalTexture atIndex:2];
  [self configureArgumentTableWithCommandEncoder:commandEncoder];
  [commandEncoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadgroupCounts];
  [commandEncoder endEncoding];
  
  
  [commandBuffer commit];
//  [commandBuffer waitUntilCompleted];
  
//  CFTimeInterval end = CACurrentMediaTime();
//  NSLog(@"Time: %g ms", (end - start) * 1e3);
}

@end
