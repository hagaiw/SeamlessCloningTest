// Copyright (c) 2016 Lightricks. All rights reserved.
// Created by Hagai Weinfeld.

#import "FinalFilter.h"

NS_ASSUME_NONNULL_BEGIN

@interface FinalFilter ()

@property (strong, nonatomic) id<MTLTexture> mixTexture;
@property (strong, nonatomic) id<MTLTexture> boundaryTexture;
@property (strong, nonatomic) id<MTLTexture> sourceTexture;
@property (strong, nonatomic) id<MTLTexture> targetTexture;
@property (strong, nonatomic) id<MTLTexture> maskTexture;
@property (nonatomic) CGSize sourceOffset;
@property (strong, nonatomic) id<MTLTexture> outputTexture;
@property (strong, nonatomic) MBEContext *context;
@property (nonatomic, strong) id<MTLComputePipelineState> pipeline;
@property (nonatomic, strong) id<MTLBuffer> uniformBuffer;

@end

@implementation FinalFilter

struct OffsetUniforms
{
  float xOffset;
  float yOffset;
};

- (instancetype)initWithMix:(id<MTLTexture>)mix boundary:(id<MTLTexture>)boundary
                     source:(id<MTLTexture>)source target:(id<MTLTexture>)target
                       mask:(id<MTLTexture>)mask targetOffset:(CGSize)offset
                    context:(MBEContext *)context {
  MTLTextureDescriptor *textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                               width:source.width
                                                                                              height:source.height
                                                                                           mipmapped:NO];
  if (self = [super init]) {
    self.mixTexture = mix;
    self.sourceTexture = source;
    self.targetTexture = target;
    self.maskTexture = mask;
    self.boundaryTexture = boundary;
    self.outputTexture = [context.device newTextureWithDescriptor:textureDescriptor];
    self.sourceOffset = offset;
    self.context = context;
    NSError *error = nil;
    self.pipeline = [context.device newComputePipelineStateWithFunction:[context.library newFunctionWithName:@"final"] error:&error];
    if (!_pipeline)
    {
      NSLog(@"Error occurred when building compute pipeline for function %@", @"diff");
      return nil;
    }
    
    struct OffsetUniforms uniforms;
    uniforms.xOffset = self.sourceOffset.width;
    uniforms.yOffset = self.sourceOffset.height;
    self.uniformBuffer = [self.context.device newBufferWithLength:sizeof(uniforms)
                                                          options:MTLResourceOptionCPUCacheModeDefault];
    memcpy([self.uniformBuffer contents], &uniforms, sizeof(uniforms));
  }
  return self;
}

- (id<MTLTexture>)texture {
  MTLSize threadgroupCounts = MTLSizeMake(8, 8, 1);
  MTLSize threadgroups = MTLSizeMake([self.sourceTexture width] / threadgroupCounts.width,
                                     [self.sourceTexture height] / threadgroupCounts.height,
                                     1);
  
  id<MTLCommandBuffer> commandBuffer = [self.context.commandQueue commandBuffer];
  commandBuffer.label = @"Final Buffer";
  
  id<MTLComputeCommandEncoder> commandEncoder = [commandBuffer computeCommandEncoder];
  [commandEncoder setComputePipelineState:self.pipeline];
  [commandEncoder setTexture:self.mixTexture atIndex:0];
  [commandEncoder setTexture:self.boundaryTexture atIndex:1];
  [commandEncoder setTexture:self.sourceTexture atIndex:2];
  [commandEncoder setTexture:self.targetTexture atIndex:3];
  [commandEncoder setTexture:self.maskTexture atIndex:4];
  [commandEncoder setTexture:self.outputTexture atIndex:5];
  
  [commandEncoder setBuffer:self.uniformBuffer offset:0 atIndex:0];
  
  [commandEncoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadgroupCounts];
  commandEncoder.label = @"Final Encoder";
  [commandEncoder endEncoding];
  
  [commandBuffer commit];
//  [commandBuffer waitUntilCompleted];
  return self.outputTexture;
}

@end

NS_ASSUME_NONNULL_END
