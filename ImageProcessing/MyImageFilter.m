// Copyright (c) 2016 Lightricks. All rights reserved.
// Created by Hagai Weinfeld.

#import "MyImageFilter.h"

#import "MBEContext.h"
#import <Metal/Metal.h>
#import "MyEncoder.h"

@import MetalPerformanceShaders;

NS_ASSUME_NONNULL_BEGIN

@interface MyImageFilter ()

@property (nonatomic, strong) MBEContext *context;
@property (nonatomic, strong) id<MTLBuffer> uniformBuffer;
@property (nonatomic, strong) id<MTLComputePipelineState> pipeline;
//@property (nonatomic, strong) id<MTLTexture> internalTexture;
@property (nonatomic, strong) id<MTLFunction> kernelFunction;
@property (nonatomic) MTLSize threadgroups;
@property (nonatomic) MTLSize threadgroupCounts;
@property (nonatomic, strong) id<MTLTexture> integralImage;

@end

@implementation MyImageFilter

struct AdjustIntegralBlurUniforms
{
  float blurRadius;
};


#pragma mark -
#pragma mark Initialization
#pragma mark -

- (instancetype)initWithFunctionName:(NSString *)functionName context:(MBEContext *)context {
  if ((self = [super init]))
  {
    NSError *error = nil;
    _context = context;
    _kernelFunction = [_context.library newFunctionWithName:functionName];
    _pipeline = [_context.device newComputePipelineStateWithFunction:_kernelFunction error:&error];
    if (!_pipeline)
    {
      NSLog(@"Error occurred when building compute pipeline for function %@", functionName);
      return nil;
    }
    _threadgroupCounts = MTLSizeMake(16, 16, 1);
  }
  
  return self;
}

#pragma mark -
#pragma mark Processing
#pragma mark -

- (void)configureArgumentTableWithCommandEncoder:(id<MTLComputeCommandEncoder>)commandEncoder
{
  struct AdjustIntegralBlurUniforms uniforms;
  uniforms.blurRadius = 50;
  if (!self.uniformBuffer)
  {
    self.uniformBuffer = [self.context.device newBufferWithLength:sizeof(uniforms)
                                                          options:MTLResourceOptionCPUCacheModeDefault];
  }
  memcpy([self.uniformBuffer contents], &uniforms, sizeof(uniforms));
  [commandEncoder setBuffer:self.uniformBuffer offset:0 atIndex:0];
}


- (void)encodeIntegralImageToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                  provider:(id<MBETextureProvider>)provider {
  id<MTLTexture> inputTexture = provider.texture;
  
  commandBuffer.label = @"Blur Command Buffer";
  
  
  // If input texture dimensions changed, reset the internal texture.
  if (!self.internalTexture ) {
    self.internalTexture = [self outputTextureWithInputTexture:[provider texture]];
  }

  self.threadgroups = MTLSizeMake([inputTexture width] / self.threadgroupCounts.width,
                                  [inputTexture height] / self.threadgroupCounts.height,
                                  1);
  
  if (!self.integralImage) {
    MTLTextureDescriptor *descriptor2 = [MTLTextureDescriptor
                                         texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float
                                         width:self.internalTexture.width
                                         height:self.internalTexture.height
                                         mipmapped:NO];
    self.integralImage = [self.context.device newTextureWithDescriptor:descriptor2];
  }
  
  MPSImageIntegral *integral = [[MPSImageIntegral alloc] initWithDevice:self.context.device];
  [integral encodeToCommandBuffer:commandBuffer
                    sourceTexture:inputTexture
               destinationTexture:self.integralImage];
  
  
  id<MTLComputeCommandEncoder> commandEncoder = [commandBuffer computeCommandEncoder];
  [commandEncoder setComputePipelineState:self.pipeline];
  [commandEncoder setTexture:inputTexture atIndex:0];
  [commandEncoder setTexture:self.integralImage atIndex:1];
  [commandEncoder setTexture:self.internalTexture atIndex:2];
  [self configureArgumentTableWithCommandEncoder:commandEncoder];
  [commandEncoder dispatchThreadgroups:self.threadgroups threadsPerThreadgroup:self.threadgroupCounts];
  [commandEncoder endEncoding];
  
}

- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                  withEncoder:(id<MyEncoder>)encoder provider:(id<MBETextureProvider>)provider {
  
  id<MTLTexture> inputTexture = provider.texture;
  
  commandBuffer.label = @"Blur Command Buffer";
  

  // If input texture dimensions changed, reset the internal texture.
  if (!self.internalTexture ) {
    self.internalTexture = [self outputTextureWithInputTexture:[provider texture]];
  }
  
  
  self.threadgroups = MTLSizeMake([inputTexture width] / self.threadgroupCounts.width,
                                  [inputTexture height] / self.threadgroupCounts.height,
                                  1);

  id<MTLComputeCommandEncoder> commandEncoder =
      [encoder commandEncoderForCommandBuffer:commandBuffer];
  [commandEncoder setComputePipelineState:self.pipeline];
  [commandEncoder setTexture:inputTexture atIndex:0];
  [commandEncoder setTexture:self.internalTexture atIndex:2];
  [commandEncoder dispatchThreadgroups:self.threadgroups
                 threadsPerThreadgroup:self.threadgroupCounts];
  [commandEncoder endEncoding];
  
}

- (id<MTLTexture>)outputTextureWithInputTexture:(id<MTLTexture>)texture {
  if (!self.internalTexture ||
      [self.internalTexture width] != [texture width] ||
      [self.internalTexture height] != [texture height])
  {
    MTLTextureDescriptor *textureDescriptor =
    [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:[texture pixelFormat]
                                                       width:[texture width]
                                                      height:[texture height]
                                                   mipmapped:NO];
    self.internalTexture = [self.context.device newTextureWithDescriptor:textureDescriptor];
  }
  return self.internalTexture;
}

- (id<MTLTexture>)texture
{
  return self.internalTexture;
}

@end

NS_ASSUME_NONNULL_END
