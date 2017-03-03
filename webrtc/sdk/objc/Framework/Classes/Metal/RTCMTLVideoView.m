/*
 *  Copyright 2017 The WebRTC project authors. All Rights Reserved.
 *
 *  Use of this source code is governed by a BSD-style license
 *  that can be found in the LICENSE file in the root of the source
 *  tree. An additional intellectual property rights grant can be found
 *  in the file PATENTS.  All contributing project authors may
 *  be found in the AUTHORS file in the root of the source tree.
 */

#import "WebRTC/RTCMTLVideoView.h"

#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

#import "WebRTC/RTCLogging.h"
#import "WebRTC/RTCVideoFrame.h"

#import "RTCMTLNV12Renderer.h"

@interface RTCMTLVideoView () <MTKViewDelegate>
@property(nonatomic, strong) id<RTCMTLRenderer> renderer;
@property(nonatomic, strong) MTKView *metalView;
@property(atomic, strong) RTCVideoFrame *videoFrame;
@end

@implementation RTCMTLVideoView {
  id<RTCMTLRenderer> _renderer;
}

@synthesize renderer = _renderer;
@synthesize metalView = _metalView;
@synthesize videoFrame = _videoFrame;

- (instancetype)initWithFrame:(CGRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    [self configure];
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)aCoder {
  self = [super initWithCoder:aCoder];
  if (self) {
    [self configure];
  }
  return self;
}

#pragma mark - Private

+ (BOOL)isMetalAvailable {
#if defined(RTC_SUPPORTS_METAL)
  return YES;
#else
  return NO;
#endif
}

- (void)configure {
  if ([RTCMTLVideoView isMetalAvailable]) {
    _metalView = [[MTKView alloc] initWithFrame:self.bounds];
    [self addSubview:_metalView];
    _metalView.delegate = self;
    _metalView.contentMode = UIViewContentModeScaleAspectFit;
    _metalView.translatesAutoresizingMaskIntoConstraints = NO;
    UILayoutGuide *margins = self.layoutMarginsGuide;
    [_metalView.topAnchor constraintEqualToAnchor:margins.topAnchor].active = YES;
    [_metalView.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor].active = YES;
    [_metalView.leftAnchor constraintEqualToAnchor:margins.leftAnchor].active = YES;
    [_metalView.rightAnchor constraintEqualToAnchor:margins.rightAnchor].active = YES;

    _renderer = [[RTCMTLNV12Renderer alloc] init];
    if (![(RTCMTLNV12Renderer *)_renderer addRenderingDestination:_metalView]) {
      _renderer = nil;
    };
  } else {
    RTCLogError("Metal configuration falied.");
  }
}
#pragma mark - MTKViewDelegate methods

- (void)drawInMTKView:(nonnull MTKView *)view {
  NSAssert(view == self.metalView, @"Receiving draw callbacks from foreign instance.");
  [_renderer drawFrame:self.videoFrame];
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
}

#pragma mark - RTCVideoRenderer

- (void)setSize:(CGSize)size {
  _metalView.drawableSize = size;
  [_metalView draw];
}

- (void)renderFrame:(nullable RTCVideoFrame *)frame {
  if (frame == nil) {
    RTCLogInfo(@"Incoming frame is nil. Exiting render callback.");
    return;
  }
  self.videoFrame = frame;
}

@end
