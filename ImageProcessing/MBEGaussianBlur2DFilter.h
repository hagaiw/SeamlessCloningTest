//
//  MBEGaussianBlur2DFilter.h
//  ImageProcessing
//
//  Created by Warren Moore on 10/8/14.
//  Copyright (c) 2014 Metal By Example. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MBEImageFilter.h"

typedef NS_ENUM(NSInteger, BlurType) {
  BlurTypeIntegral,
  BlurTypeVertical,
  BlurTypeHorizontal
};

@interface MBEGaussianBlur2DFilter : MBEImageFilter

@property (nonatomic) float radius;
@property (nonatomic, assign) float sigma;

+ (instancetype)filterWithRadius:(float)radius context:(MBEContext *)context
                        blurType:(BlurType)blurType;

@end

