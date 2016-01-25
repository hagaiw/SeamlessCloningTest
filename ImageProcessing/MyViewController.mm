// Copyright (c) 2016 Lightricks. All rights reserved.
// Created by Hagai Weinfeld.

#import "MyViewController.h"

#import "MBEViewController.h"
#import "MBEContext.h"
#import "MBEImageFilter.h"
#import "MBESaturationAdjustmentFilter.h"
#import "MBEGaussianBlur2DFilter.h"
#import "MBEMainBundleTextureProvider.h"

#import "MyImageFilter.h"
#import "MyBlurFilterEncoder.h"

#import "GaussianBlur.h"
#import "DiffFilter.h"
#import "MultiplyFilter.h"
#import "FinalFilter.h"

#import "AAPLTransforms.h"
#import "AAPLTexture.h"
#import "AAPLQuad.h"
#import <simd/simd.h>

#import "UIImage+MBETextureUtilities.h"

NS_ASSUME_NONNULL_BEGIN

@interface MyViewController ()

@property (nonatomic, strong) MBEContext *context;
@property (nonatomic, strong) id<MBETextureProvider> imageProvider;
@property (nonatomic, strong) MBESaturationAdjustmentFilter *desaturateFilter;
@property (nonatomic, strong) MBEGaussianBlur2DFilter *blurFilterIntegral;
@property (strong, nonatomic) id<MBETextureProvider> finalFilter;
@property (strong, nonatomic) DiffFilter *diffFilter;

@property (strong, nonatomic) id<MTLTexture> source;
@property (strong, nonatomic) id<MTLTexture> target;
@property (strong, nonatomic) id<MTLTexture> mask;
@property (strong, nonatomic) id<MTLTexture> outline;
@property (strong, nonatomic) id<MTLTexture> blurredOutline;

@property (nonatomic, strong) dispatch_queue_t renderingQueue;
@property (atomic, assign) uint64_t jobIndex;

@property (strong, nonatomic) MyBlurFilterEncoder *horizontalBlurEncoder;
@property (strong, nonatomic) MyBlurFilterEncoder *verticalBlurEncoder;

@property (strong, nonatomic) MyImageFilter *horizontalBlurFilter;
@property (strong, nonatomic) MyImageFilter *verticalBlurFilter;

@property (strong, nonatomic) id<MBETextureProvider> sourceProvider;

/// Display link used to trigger all the animations.
@property (strong, nonatomic) CADisplayLink *displayLink;

@end

static const NSUInteger kThreadgroupWidth  = 16;
static const NSUInteger kThreadgroupHeight = 16;
static const NSUInteger kThreadgroupDepth  = 1;

static const float kUIInterfaceOrientationLandscapeAngle = 35.0f;
static const float kUIInterfaceOrientationPortraitAngle  = 50.0f;

static const float kPrespectiveNear = 0.1f;
static const float kPrespectiveFar  = 100.0f;

static const uint32_t kSzSIMDFloat4x4         = sizeof(simd::float4x4);
static const uint32_t kSzBufferLimitsPerFrame = kSzSIMDFloat4x4;

static const uint32_t kInFlightCommandBuffers = 3;


@implementation MyViewController

#pragma mark -
#pragma mark AAPLViewDelegate
#pragma mark -

{
@private
  // Interface Orientation
  UIInterfaceOrientation  mnOrientation;
  
  // Renderer globals
  id <MTLDevice>             m_Device;
  id <MTLCommandQueue>       m_CommandQueue;
  id <MTLLibrary>            m_ShaderLibrary;
  id <MTLDepthStencilState>  m_DepthState;
  
  // Compute ivars
  id <MTLComputePipelineState>   m_Kernel;
  
  // Compute kernel parameters
  MTLSize m_ThreadgroupSize;
  MTLSize m_ThreadgroupCount;
  
  // textured Quad
  AAPLTexture                   *mpInTexture;
  id <MTLTexture>                m_OutTexture;
  id <MTLRenderPipelineState>    m_PipelineState;
  
  // Quad representation
  AAPLQuad *mpQuad;
  
  // App control
  dispatch_semaphore_t  m_InflightSemaphore;
  
  // Dimensions
  CGSize  m_Size;
  
  // Viewing matrix is derived from an eye point, a reference point
  // indicating the center of the scene, and an up vector.
  simd::float4x4 m_LookAt;
  
  // Translate the object in (x,y,z) space.
  simd::float4x4 m_Translate;
  
  // Quad transform buffers
  simd::float4x4  m_Transform;
  id <MTLBuffer>  m_TransformBuffer;
}

- (void)initMetalView {
  AAPLView *renderView = (AAPLView *)self.view;
  renderView.delegate = self;
  [self configure:renderView];
  
  m_InflightSemaphore = dispatch_semaphore_create(kInFlightCommandBuffers);
}

- (void)reshape:(AAPLView *)view;
{
  // To correctly compute the aspect ration determine the device
  // interface orientation.
  UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
  
  // Update the quad and linear _transformation matrices, if and
  // only if, the device orientation is changed.
  if(mnOrientation != orientation)
  {
    // Update the device orientation
    mnOrientation = orientation;
    
    // Get the bounds for the current rendering layer
    mpQuad.bounds = view.layer.frame;
    
    // Based on the device orientation, set the angle in degrees
    // between a plane which passes through the camera position
    // and the top of your screen and another plane which passes
    // through the camera position and the bottom of your screen.
    float dangle = 0.0f;
    
    switch(mnOrientation)
    {
      case UIInterfaceOrientationLandscapeLeft:
      case UIInterfaceOrientationLandscapeRight:
        dangle = kUIInterfaceOrientationLandscapeAngle;
        break;
        
      case UIInterfaceOrientationPortrait:
      case UIInterfaceOrientationPortraitUpsideDown:
      default:
        dangle = kUIInterfaceOrientationPortraitAngle;
        break;
    } // switch
    
    // Describes a tranformation matrix that produces a perspective projection
    const float near   = kPrespectiveNear;
    const float far    = kPrespectiveFar;
    const float rangle = AAPL::Math::radians(dangle);
    const float length = near * std::tan(rangle);
    
    float right   = length/mpQuad.aspect;
    float left    = -right;
    float top     = length;
    float bottom  = -top;
    
    simd::float4x4 perspective = AAPL::Math::LHT::frustum_oc(left, right, bottom, top, near, far);
    
    // Create a viewing matrix derived from an eye point, a reference point
    // indicating the center of the scene, and an up vector.
    m_Transform = m_LookAt * m_Translate;
    
    // Create a linear _transformation matrix
    m_Transform = perspective * m_Transform;
    
    // Update the buffer associated with the linear _transformation matrix
    float *pTransform = (float *)[m_TransformBuffer contents];
    
    memcpy(pTransform, &m_Transform, kSzSIMDFloat4x4);
  }
}

- (void) render:(AAPLView *)view
{
  dispatch_semaphore_wait(m_InflightSemaphore, DISPATCH_TIME_FOREVER);
  
  id <MTLCommandBuffer> commandBuffer = [m_CommandQueue commandBuffer];
  
  // compute image processing on the (same) drawable texture
  [self processImageWithCommandBuffer:commandBuffer];
  
  // create a render command encoder so we can render into something
  MTLRenderPassDescriptor *renderPassDescriptor = view.renderPassDescriptor;
  
  if(renderPassDescriptor)
  {
    // Get a render encoder
    id <MTLRenderCommandEncoder>  renderEncoder
    = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    
    // render textured quad
    [self encode:renderEncoder];
    
    // Present command buffer
    [commandBuffer presentDrawable:view.currentDrawable];
  }
  
  // Dispatch the command buffer
  __block dispatch_semaphore_t dispatchSemaphore = m_InflightSemaphore;
  [commandBuffer addCompletedHandler:^(id <MTLCommandBuffer> cmdb)
   {
     dispatch_semaphore_signal(dispatchSemaphore);
   }];
  
  [commandBuffer commit];
}

- (void) encode:(id <MTLRenderCommandEncoder>)renderEncoder
{
  // set context state with the render encoder
  [renderEncoder pushDebugGroup:@"encode quad"];
  {
    [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
    [renderEncoder setDepthStencilState:m_DepthState];
    
    [renderEncoder setRenderPipelineState:m_PipelineState];
    
    [renderEncoder setVertexBuffer:m_TransformBuffer
                            offset:0
                           atIndex:2 ];
    
    [renderEncoder setFragmentTexture:m_OutTexture
                              atIndex:0];
    
    // Encode quad vertex and texture coordinate buffers
    [mpQuad encode:renderEncoder];
    
    // tell the render context we want to draw our primitives
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:0
                      vertexCount:6
                    instanceCount:1];
    
    [renderEncoder endEncoding];
  }
  [renderEncoder popDebugGroup];
  
} // _encode

- (void)configure:(AAPLView *)view
{
  // find a usable Device
  m_Device = view.device;
  
  view.depthPixelFormat   = MTLPixelFormatInvalid;
  view.stencilPixelFormat = MTLPixelFormatInvalid;
  view.sampleCount        = 1;
  
  // we need to set the framebuffer only property of the layer to NO so we
  // can perform compute on the drawable's texture
  CAMetalLayer *metalLayer = (CAMetalLayer *)view.layer;
  metalLayer.framebufferOnly = NO;
  
  // create a new command queue
  m_CommandQueue = [m_Device newCommandQueue];
  if(!m_CommandQueue) {
    NSLog(@">> ERROR: Couldnt create a command queue");
    
    assert(0);
  }
  
  m_ShaderLibrary = [m_Device newDefaultLibrary];
  if(!m_ShaderLibrary) {
    NSLog(@">> ERROR: Couldnt create a default shader library");
    
    assert(0);
  }
  
  if(![self preparePipelineState:view])
  {
    NSLog(@">> ERROR: Failed creating a compiled pipeline state object!");
    
    assert(0);
  }
  
  if(![self prepareTexturedQuad:@"128x128" ext:@"png"])
  {
    NSLog(@">> ERROR: Failed creating a textured quad!");
    
    assert(0);
  }
  
  if(![self prepareCompute])
  {
    NSLog(@">> ERROR: Failed creating a compute stage!");
    
    assert(0);
  }
  
  if(![self prepareDepthStencilState])
  {
    NSLog(@">> ERROR: Failed creating a depth stencil state!");
    
    assert(0);
  }
  
  if(![self prepareTransformBuffer])
  {
    NSLog(@">> ERROR: Failed creating a transform buffer!");
    
    assert(0);
  }
  
  // Default orientation is unknown
  mnOrientation = UIInterfaceOrientationUnknown;
  
  // Create linear transformation matrices
  [self prepareTransforms];
}

- (BOOL) preparePipelineState:(AAPLView *)view
{
  // get the fragment function from the library
  id <MTLFunction> fragmentProgram = [m_ShaderLibrary newFunctionWithName:@"texturedQuadFragment"];
  
  // get the vertex function from the library
  id <MTLFunction> vertexProgram = [m_ShaderLibrary newFunctionWithName:@"texturedQuadVertex"];
  
  //  create a pipeline state for the quad
  MTLRenderPipelineDescriptor *pQuadPipelineStateDescriptor = [MTLRenderPipelineDescriptor new];
  pQuadPipelineStateDescriptor.depthAttachmentPixelFormat      = view.depthPixelFormat;
  pQuadPipelineStateDescriptor.stencilAttachmentPixelFormat    = view.stencilPixelFormat;
  pQuadPipelineStateDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
  pQuadPipelineStateDescriptor.sampleCount      = view.sampleCount;
  pQuadPipelineStateDescriptor.vertexFunction   = vertexProgram;
  pQuadPipelineStateDescriptor.fragmentFunction = fragmentProgram;
  
  NSError *pError = nil;
  m_PipelineState = [m_Device newRenderPipelineStateWithDescriptor:pQuadPipelineStateDescriptor error:&pError];
  if(!m_PipelineState)
  {
    NSLog(@">> ERROR: Failed acquiring pipeline state descriptor: %@", pError);
    
    return NO;
  } // if
  
  return YES;
} // preparePipelineState

- (BOOL) prepareTexturedQuad:(NSString *)texStr
                         ext:(NSString *)extStr
{
  mpInTexture = [[AAPLTexture alloc] initWithResourceName:texStr
                                                extension:extStr];
  
  mpInTexture.texture.label = texStr;
  
  BOOL isAcquired = [mpInTexture finalize:m_Device];
  
  if(!isAcquired)
  {
    NSLog(@">> ERROR: Failed creating an input 2d texture!");
    
    return NO;
  } // if
  
  m_Size.width  = CGFloat(mpInTexture.width);
  m_Size.height = CGFloat(mpInTexture.height);
  
  mpQuad = [[AAPLQuad alloc] initWithDevice:m_Device];
  
  if(!mpQuad)
  {
    NSLog(@">> ERROR: Failed creating a quad object!");
    
    return NO;
  } // if
  
  mpQuad.size = m_Size;
  
  return YES;
} // prepareTexturedQuad

- (BOOL) prepareCompute
{
  
  m_OutTexture = [self.verticalBlurFilter outputTextureWithInputTexture:mpInTexture.texture];
  return YES;
  NSError *pError = nil;
  
  // Create a compute kernel function
  id <MTLFunction> function = [m_ShaderLibrary newFunctionWithName:@"grayscale"];
  
  if(!function)
  {
    NSLog(@">> ERROR: Failed creating a new function!");
    
    return NO;
  } // if
  
  // Create a compute kernel
  m_Kernel = [m_Device newComputePipelineStateWithFunction:function
                                                     error:&pError];
  
  if(!m_Kernel)
  {
    NSLog(@">> ERROR: Failed creating a compute kernel: %@", pError);
    
    return NO;
  } // if
  
  MTLTextureDescriptor *pTexDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                      width:mpInTexture.width
                                                                                     height:mpInTexture.height
                                                                                  mipmapped:NO];
  
  if(!pTexDesc)
  {
    NSLog(@">> ERROR: Failed creating a texture 2d descriptor with RGBA unnormalized pixel format!");
    
    return NO;
  } // if
  
  m_OutTexture = [m_Device newTextureWithDescriptor:pTexDesc];
  
  if(!m_OutTexture)
  {
    NSLog(@">> ERROR: Failed creating an output 2d texture!");
    
    return NO;
  } // if
  
  // Set the compute kernel's thread group size of 16x16
  m_ThreadgroupSize = MTLSizeMake(kThreadgroupWidth, kThreadgroupHeight, kThreadgroupDepth);
  
  // Calculate the compute kernel's width and height
  NSUInteger nThreadCountW = (mpInTexture.width  + m_ThreadgroupSize.width -  1) / m_ThreadgroupSize.width;
  NSUInteger nThreadCountH = (mpInTexture.height + m_ThreadgroupSize.height - 1) / m_ThreadgroupSize.height;
  
  // Set the compute kernel's thread count
  m_ThreadgroupCount = MTLSizeMake(nThreadCountW, nThreadCountH, 1);
  
  return YES;
} // prepareCompute

- (BOOL) prepareDepthStencilState
{
  MTLDepthStencilDescriptor *pDepthStateDesc = [MTLDepthStencilDescriptor new];
  
  if(!pDepthStateDesc)
  {
    NSLog(@">> ERROR: Failed creating a depth stencil descriptor!");
    
    return NO;
  } // if
  
  pDepthStateDesc.depthCompareFunction = MTLCompareFunctionAlways;
  pDepthStateDesc.depthWriteEnabled    = YES;
  
  m_DepthState = [m_Device newDepthStencilStateWithDescriptor:pDepthStateDesc];
  
  if(!m_DepthState)
  {
    return NO;
  } // if
  
  return YES;
} // prepareDepthStencilState

- (BOOL) prepareTransformBuffer
{
  // allocate regions of memory for the constant buffer
  m_TransformBuffer = [m_Device newBufferWithLength:kSzBufferLimitsPerFrame
                                            options:0];
  
  if(!m_TransformBuffer)
  {
    return NO;
  } // if
  
  m_TransformBuffer.label = @"TransformBuffer";
  
  return YES;
} // prepareTransformBuffer

- (void) prepareTransforms
{
  // Create a viewing matrix derived from an eye point, a reference point
  // indicating the center of the scene, and an up vector.
  simd::float3 eye    = {0.0, 0.0, 0.0};
  simd::float3 center = {0.0, 0.0, 1.0};
  simd::float3 up     = {0.0, 1.0, 0.0};
  
  m_LookAt = AAPL::Math::LHT::lookAt(eye, center, up);
  
  // Translate the object in (x,y,z) space.
  m_Translate = AAPL::Math::translate(0.0f, -0.25f, 2.0f);
} // prepareTransforms

#pragma mark -
#pragma mark UIViewController
#pragma mark -

- (void)viewDidLoad
{
  [super viewDidLoad];
  
  self.renderingQueue = dispatch_queue_create("Rendering", DISPATCH_QUEUE_SERIAL);
  
  [self initialization];
  
  [self initMetalView];
  

  
//  [self updateImage];
  
  [(AAPLView *)self.view display];

  self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(loop:)];
  [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

#pragma mark -
#pragma mark Initialization
#pragma mark -

- (void)initialization {
  self.context = [[MBEContext alloc] initWithDevice:m_Device];
  self.sourceProvider = [MBEMainBundleTextureProvider textureProviderWithImageNamed:@"bear"
                                                                            context:self.context];
  self.source  = [self.sourceProvider texture];
  self.target  = [[MBEMainBundleTextureProvider textureProviderWithImageNamed:@"beach"
                                                                      context:self.context] texture];
  self.mask  = [[MBEMainBundleTextureProvider textureProviderWithImageNamed:@"mask"
                                                                    context:self.context] texture];
  self.outline  = [[MBEMainBundleTextureProvider textureProviderWithImageNamed:@"outline"
                                                                       context:self.context] texture];
  
  self.horizontalBlurFilter = [[MyImageFilter alloc] initWithFunctionName:@"gaussian_blur_horizontal"
                                                                  context:self.context];
  
  self.verticalBlurFilter = [[MyImageFilter alloc] initWithFunctionName:@"gaussian_blur_vertical"
                                                                context:self.context];

  m_OutTexture = self.verticalBlurFilter.internalTexture;
  
  
//  self.blurredOutline = [[GaussianBlur alloc] initWithContext:self.context provider:self.outline blurRadius:self.outline];
}

- (void)processImageWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer {
  int numIterations = 1;
  
  
  float blurRadius = self.blurRadiusSlider.value;
//  float blurRadius = 100;
  
  self.horizontalBlurEncoder = [[MyBlurFilterEncoder alloc] initWithBlurRadius:blurRadius
                                                                        device:self.context.device
                                                                         label:@"Horizontal Blur Encoder"];
  
  self.verticalBlurEncoder = [[MyBlurFilterEncoder alloc] initWithBlurRadius:blurRadius
                                                                      device:self.context.device
                                                                       label:@"Vertical Blur Encoder"];
  
  [self.horizontalBlurFilter encodeToCommandBuffer:commandBuffer withEncoder:self.horizontalBlurEncoder
                                          provider:mpInTexture];
  
  
  [self.verticalBlurFilter encodeToCommandBuffer:commandBuffer withEncoder:self.verticalBlurEncoder
                                        provider:self.horizontalBlurFilter];
  
  for (int i=0; i<(numIterations-1); ++i) {
    [self.horizontalBlurFilter encodeToCommandBuffer:commandBuffer withEncoder:self.horizontalBlurEncoder
                                            provider:self.verticalBlurFilter];
    
    [self.verticalBlurFilter encodeToCommandBuffer:commandBuffer withEncoder:self.verticalBlurEncoder
                                          provider:self.horizontalBlurFilter];
  }
}

- (void)updateImage {
  ++self.jobIndex;
  uint64_t currentJobIndex = self.jobIndex;
  
  // Grab these values while we're still on the main thread, since we could
  // conceivably get incomplete values by reading them in the background.
  float blurRadius = self.blurRadiusSlider.value;
  float xOffset = self.xSlider.value;
  float yOffset = self.ySlider.value;
  CGSize offset = CGSizeMake(xOffset, yOffset);
  
  
  
  dispatch_async(self.renderingQueue, ^{
    if (currentJobIndex != self.jobIndex) {
      return;
    }
    
    self.horizontalBlurEncoder = [[MyBlurFilterEncoder alloc] initWithBlurRadius:blurRadius
                                                                          device:self.context.device
                                                                           label:@"Horizontal Blur Encoder"];
    
    self.verticalBlurEncoder = [[MyBlurFilterEncoder alloc] initWithBlurRadius:blurRadius
                                                                        device:self.context.device
                                                                         label:@"vertical Blur Encoder"];
    
    
    CFTimeInterval start = CACurrentMediaTime();
    
    id<MTLCommandBuffer> tempCommandBuffer = [self.context.commandQueue commandBuffer];
    
    [self processImageWithCommandBuffer:tempCommandBuffer];
    
    [tempCommandBuffer commit];
    [tempCommandBuffer waitUntilCompleted];
    
//    self.diffFilter  = [[DiffFilter alloc] initWithSource:self.source target:self.target targetOffset:offset context:self.context];
//    
//    MultiplyFilter *diffMultipliedByBoundary = [[MultiplyFilter alloc] initWithSource:[self.diffFilter texture] target:self.outline targetOffset:offset context:self.context];
    
    
//    GaussianBlur *blurredDiffBoundary = [[GaussianBlur alloc] initWithContext:self.context provider:diffMultipliedByBoundary blurRadius:blurRadius];
//    
//    GaussianBlur *blurredBoundary = [[GaussianBlur alloc] initWithContext:self.context provider:self.outline blurRadius:blurRadius];
//    
//    self.finalFilter = [[FinalFilter alloc] initWithMix:[self.blurFilter texture] boundary:[self.blurFilter texture] source:self.source target:self.target mask:self.mask targetOffset:offset context:self.context];
    
//    id<MTLTexture> texture = self.finalFilter.texture;
    
    CFTimeInterval end = CACurrentMediaTime();
    NSUInteger numSamples = 2*((blurRadius*2)+1);
    NSLog(@"Time: %g ms for   radius: %f  samples: %lu", (end - start) * 1e3, blurRadius, (unsigned long)numSamples);
    
    id<MTLTexture> outputTexture = [[self.verticalBlurFilter texture] newTextureViewWithPixelFormat:MTLPixelFormatRGBA8Unorm];
    UIImage *image = [UIImage imageWithMTLTexture:outputTexture];
    dispatch_async(dispatch_get_main_queue(), ^{
      self.imageView.image = image;
    });
  });
  
  
  
}

#pragma mark -
#pragma mark DisplayLink
#pragma mark -

- (void) loop:(CADisplayLink *)sender {
//  [self updateImage];
  [(AAPLView *)self.view display];
}

#pragma mark -
#pragma mark UIElements
#pragma mark -

- (IBAction)blurRadiusDidChange:(id)sender
{
  [self updateImage];
}

@end

NS_ASSUME_NONNULL_END
