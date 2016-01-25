// Copyright (c) 2016 Lightricks. All rights reserved.
// Created by Hagai Weinfeld.

#import "MyEncoder.h"

NS_ASSUME_NONNULL_BEGIN

@interface MyBlurFilterEncoder : NSObject <MyEncoder>

- (instancetype)initWithBlurRadius:(NSUInteger)radius device:(id<MTLDevice>)device
                             label:(NSString *)label;

@end

NS_ASSUME_NONNULL_END
