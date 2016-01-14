// Copyright (c) 2016 Lightricks. All rights reserved.
// Created by Hagai Weinfeld.

#import <UIKit/UIKit.h>
#import "MBETextureProvider.h"
@class MBEContext;

NS_ASSUME_NONNULL_BEGIN

@interface MultiplyFilter : NSObject <MBETextureProvider>

- (instancetype)initWithSource:(id<MTLTexture>)source target:(id<MTLTexture>)target
                  targetOffset:(CGSize)offset context:(MBEContext *)context;
- (id<MTLTexture>)texture;

@end

NS_ASSUME_NONNULL_END
