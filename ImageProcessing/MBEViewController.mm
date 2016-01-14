//
//  MBEViewController.mm
//  ImageProcessing
//
//  Created by Warren Moore on 9/30/14.
//  Copyright (c) 2014 Metal By Example. All rights reserved.
//

#import "MBEViewController.h"
#import "MBEContext.h"
#import "MBEImageFilter.h"
#import "MBESaturationAdjustmentFilter.h"
#import "MBEGaussianBlur2DFilter.h"
#import "UIImage+MBETextureUtilities.h"
#import "MBEMainBundleTextureProvider.h"
#import "GaussianBlur.h"
#import "DiffFilter.h"
#import "MultiplyFilter.h"
#import "FinalFilter.h"

@interface MBEViewController ()

@property (nonatomic, strong) MBEContext *context;
@property (nonatomic, strong) id<MBETextureProvider> imageProvider;
@property (nonatomic, strong) MBESaturationAdjustmentFilter *desaturateFilter;
@property (nonatomic, strong) MBEGaussianBlur2DFilter *blurFilterIntegral;
@property (strong, nonatomic) id<MBETextureProvider> finalFilter;
@property (strong, nonatomic) DiffFilter *diffFilter;

@property (strong, nonatomic) id<MTLTexture> source;
@property (strong, nonatomic) id<MTLTexture> target;
@property (strong, nonatomic) id<MTLTexture> mask;

@property (strong, nonatomic) MBEMainBundleTextureProvider *outline;

@property (nonatomic, strong) dispatch_queue_t renderingQueue;
@property (atomic, assign) uint64_t jobIndex;

@end

@implementation MBEViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.renderingQueue = dispatch_queue_create("Rendering", DISPATCH_QUEUE_SERIAL);

    [self buildFilterGraph];
    [self updateImage];
}

- (void)buildFilterGraph
{
  self.context = [MBEContext newContext];

  
  self.source  = [[MBEMainBundleTextureProvider textureProviderWithImageNamed:@"bear"
                                                                              context:self.context] texture];
  
  self.target  = [[MBEMainBundleTextureProvider textureProviderWithImageNamed:@"beach"
                                                                               context:self.context] texture];
  
  self.mask  = [[MBEMainBundleTextureProvider textureProviderWithImageNamed:@"mask"
                                                                              context:self.context] texture];
  
  self.outline  = [MBEMainBundleTextureProvider textureProviderWithImageNamed:@"outline"
                                                                                               context:self.context];
  
//  self.finalFilter = self.diffFilter;
  
  
//
//  self.blurFilterVertical = [MBEGaussianBlur2DFilter filterWithRadius:self.blurRadiusSlider.value
//                                                              context:self.context blurType:BlurTypeVertical];
//  self.blurFilterVertical.provider = self.imageProvider;
//  
//  
//  self.blurFilterHorizontal = [MBEGaussianBlur2DFilter filterWithRadius:self.blurRadiusSlider.value
//                                                                context:self.context blurType:BlurTypeHorizontal];
//  self.blurFilterHorizontal.provider = self.blurFilterVertical;
//  
//  self.blurFilterOutput = self.gaussianBlur2D;
}

- (void)updateImage
{
  ++self.jobIndex;
  uint64_t currentJobIndex = self.jobIndex;
  
  // Grab these values while we're still on the main thread, since we could
  // conceivably get incomplete values by reading them in the background.
  float blurRadius = self.blurRadiusSlider.value;
  
  
  float xOffset = self.saturationSlider.value;
  float yOffset = self.ySlider.value;
  
  CGSize offset = CGSizeMake(xOffset, yOffset);
  
  dispatch_async(self.renderingQueue, ^{
    if (currentJobIndex != self.jobIndex)
      return;
    
    CFTimeInterval start = CACurrentMediaTime();
    
    
    
    self.diffFilter  = [[DiffFilter alloc] initWithSource:self.source target:self.target targetOffset:offset context:self.context];
    
    MultiplyFilter *diffMultipliedByBoundary = [[MultiplyFilter alloc] initWithSource:[self.diffFilter texture] target:[self.outline texture] targetOffset:offset context:self.context];
    
    GaussianBlur *blurredDiffBoundary = [[GaussianBlur alloc] initWithContext:self.context provider:diffMultipliedByBoundary blurRadius:blurRadius];
    
    GaussianBlur *blurredBoundary = [[GaussianBlur alloc] initWithContext:self.context provider:self.outline blurRadius:blurRadius];
    
    self.finalFilter = [[FinalFilter alloc] initWithMix:[blurredDiffBoundary texture] boundary:[blurredBoundary texture] source:self.source target:self.target mask:self.mask targetOffset:offset context:self.context];
    
    
    
    id<MTLTexture> texture = self.finalFilter.texture;
    CFTimeInterval end = CACurrentMediaTime();
    NSLog(@"Time: %g ms for     radius: %f", (end - start) * 1e3, blurRadius);
    UIImage *image = [UIImage imageWithMTLTexture:texture];
    
    dispatch_async(dispatch_get_main_queue(), ^{
      self.imageView.image = image;
    });
  });
}

- (IBAction)blurRadiusDidChange:(id)sender
{
    [self updateImage];
}

- (IBAction)saturationDidChange:(id)sender
{
    [self updateImage];
}

@end
