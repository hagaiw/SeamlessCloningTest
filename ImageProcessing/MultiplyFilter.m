// Copyright (c) 2016 Lightricks. All rights reserved.
// Created by Hagai Weinfeld.

#import "MultiplyFilter.h"

#import <Metal/Metal.h>

#import "MBEContext.h"

NS_ASSUME_NONNULL_BEGIN

@interface MultiplyFilter ()

@property (strong, nonatomic) id<MTLTexture> sourceTexture;
@property (strong, nonatomic) id<MTLTexture> targetTexture;
@property (nonatomic) CGSize sourceOffset;
@property (strong, nonatomic) id<MTLTexture> diffTexture;
@property (strong, nonatomic) MBEContext *context;
@property (nonatomic, strong) id<MTLComputePipelineState> pipeline;

@end

@implementation MultiplyFilter

- (instancetype)initWithSource:(id<MTLTexture>)source target:(id<MTLTexture>)target targetOffset:(CGSize)offset context:(MBEContext *)context {
  MTLTextureDescriptor *textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float
                                                                                               width:source.width
                                                                                              height:source.height
                                                                                           mipmapped:NO];
  if (self = [super init]) {
    self.sourceTexture = source;
    self.targetTexture = target;
    self.diffTexture = [context.device newTextureWithDescriptor:textureDescriptor];
    self.sourceOffset = offset;
    self.context = context;
    NSError *error = nil;
    self.pipeline = [context.device newComputePipelineStateWithFunction:[context.library newFunctionWithName:@"mult"] error:&error];
    if (!_pipeline)
    {
      NSLog(@"Error occurred when building compute pipeline for function %@", @"diff");
      return nil;
    }
  }
  return self;
}

- (id<MTLTexture>)texture {
  MTLSize threadgroupCounts = MTLSizeMake(8, 8, 1);
  MTLSize threadgroups = MTLSizeMake([self.sourceTexture width] / threadgroupCounts.width,
                                     [self.sourceTexture height] / threadgroupCounts.height,
                                     1);
  
  id<MTLCommandBuffer> commandBuffer = [self.context.commandQueue commandBuffer];
  commandBuffer.label = @"Multiply Buffer";
  
  id<MTLComputeCommandEncoder> commandEncoder = [commandBuffer computeCommandEncoder];
  [commandEncoder setComputePipelineState:self.pipeline];
  [commandEncoder setTexture:self.sourceTexture atIndex:0];
  [commandEncoder setTexture:self.targetTexture atIndex:1];
  [commandEncoder setTexture:self.diffTexture atIndex:2];
  [commandEncoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadgroupCounts];
  commandEncoder.label = @"Multiply Encoder";
  [commandEncoder endEncoding];
  
  [commandBuffer commit];
//  [commandBuffer waitUntilCompleted];
  return self.diffTexture;
}

@end

NS_ASSUME_NONNULL_END
