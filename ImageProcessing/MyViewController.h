// Copyright (c) 2016 Lightricks. All rights reserved.
// Created by Hagai Weinfeld.

#import <UIKit/UIKit.h>
#import "AAPLView.h"

NS_ASSUME_NONNULL_BEGIN

@interface MyViewController : UIViewController <AAPLViewDelegate>

@property (weak, nonatomic) IBOutlet UIImageView *imageView;
@property (weak, nonatomic) IBOutlet UISlider *blurRadiusSlider;
@property (weak, nonatomic) IBOutlet UISlider *xSlider;
@property (weak, nonatomic) IBOutlet UISlider *ySlider;

- (IBAction)blurRadiusDidChange:(id)sender;

@end

NS_ASSUME_NONNULL_END
