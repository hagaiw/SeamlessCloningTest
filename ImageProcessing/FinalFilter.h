// Copyright (c) 2016 Lightricks. All rights reserved.
// Created by Hagai Weinfeld.

#import "DiffFilter.h"

#import <Metal/Metal.h>

#import "MBEContext.h"


@class MBEContext;


NS_ASSUME_NONNULL_BEGIN

@interface FinalFilter : NSObject <MBETextureProvider>

- (instancetype)initWithMix:(id<MTLTexture>)mix boundary:(id<MTLTexture>)boundary
                     source:(id<MTLTexture>)source target:(id<MTLTexture>)target
                       mask:(id<MTLTexture>)mask targetOffset:(CGSize)offset
                    context:(MBEContext *)context;
- (id<MTLTexture>)texture;

@end

NS_ASSUME_NONNULL_END
