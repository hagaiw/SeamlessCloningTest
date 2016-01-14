// Copyright (c) 2016 Lightricks. All rights reserved.
// Created by Hagai Weinfeld.

#import "GaussianBlur.h"


#import "MBEContext.h"
#import "MBEImageFilter.h"
#import "MBESaturationAdjustmentFilter.h"
#import "MBEGaussianBlur2DFilter.h"
#import "UIImage+MBETextureUtilities.h"
#import "MBEMainBundleTextureProvider.h"

NS_ASSUME_NONNULL_BEGIN

@interface GaussianBlur ()

@property (nonatomic, strong) MBEGaussianBlur2DFilter *blurFilterVertical;
@property (nonatomic, strong) MBEGaussianBlur2DFilter *blurFilterHorizontal;

@end

@implementation GaussianBlur

- (instancetype)initWithContext:(MBEContext *)context provider:(id<MBETextureProvider>)provider
                     blurRadius:(float)blurRadius {
  self = [super init];
  if (self) {
    self.blurFilterVertical = [MBEGaussianBlur2DFilter filterWithRadius:blurRadius
                                                                context:context blurType:BlurTypeVertical];
    self.blurFilterVertical.provider = provider;
    
    
    self.blurFilterHorizontal = [MBEGaussianBlur2DFilter filterWithRadius:blurRadius
                                                                  context:context blurType:BlurTypeHorizontal];
    self.blurFilterHorizontal.provider = self.blurFilterVertical;
  }
  return self;
}

- (id<MTLTexture>)texture {
  return self.blurFilterHorizontal.texture;
}

- (void)setRadius:(float)radius {
  self.blurFilterVertical.radius = radius;
  self.blurFilterHorizontal.radius = radius;
}

@end

NS_ASSUME_NONNULL_END
