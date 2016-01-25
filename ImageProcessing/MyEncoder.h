// Copyright (c) 2016 Lightricks. All rights reserved.
// Created by Hagai Weinfeld.

#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

@protocol MyEncoder <NSObject>

- (id<MTLComputeCommandEncoder>)commandEncoderForCommandBuffer:(id<MTLCommandBuffer>)commandBuffer;

@end

NS_ASSUME_NONNULL_END
