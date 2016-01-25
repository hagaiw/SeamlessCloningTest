// Copyright (c) 2016 Lightricks. All rights reserved.
// Created by Hagai Weinfeld.

#import <Foundation/Foundation.h>
#import "MBETextureProvider.h"
#import "MBETextureConsumer.h"
#import "MBEContext.h"

@protocol MTLCommandBuffer, MyEncoder;

NS_ASSUME_NONNULL_BEGIN

@protocol MTLTexture, MTLBuffer, MTLComputeCommandEncoder, MTLComputePipelineState;

@interface MyImageFilter : NSObject <MBETextureProvider>

- (instancetype)initWithFunctionName:(NSString *)functionName context:(MBEContext *)context;

- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                  withEncoder:(id<MyEncoder>)encoder provider:(id<MBETextureProvider>)provider;

- (id<MTLTexture>)outputTextureWithInputTexture:(id<MTLTexture>)texture;

@property (nonatomic, strong) id<MTLTexture> internalTexture;

@end

NS_ASSUME_NONNULL_END
