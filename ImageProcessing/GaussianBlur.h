// Copyright (c) 2016 Lightricks. All rights reserved.
// Created by Hagai Weinfeld.

#import <UIKit/UIKit.h>
#import "MBETextureProvider.h"
@class MBEContext;

NS_ASSUME_NONNULL_BEGIN

@interface GaussianBlur : NSObject<MBETextureProvider>

- (instancetype)initWithContext:(MBEContext *)context provider:(id<MBETextureProvider>)provider
                     blurRadius:(float)blurRadius;

@property (nonatomic) float radius;

@end

NS_ASSUME_NONNULL_END
