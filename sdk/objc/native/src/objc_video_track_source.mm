/*
 *  Copyright (c) 2017 The WebRTC project authors. All Rights Reserved.
 *
 *  Use of this source code is governed by a BSD-style license
 *  that can be found in the LICENSE file in the root of the source
 *  tree. An additional intellectual property rights grant can be found
 *  in the file PATENTS.  All contributing project authors may
 *  be found in the AUTHORS file in the root of the source tree.
 */

#include "sdk/objc/native/src/objc_video_track_source.h"

#import "base/RTCVideoFrame.h"
#import "base/RTCVideoFrameBuffer.h"
#import "components/video_frame_buffer/RTCCVPixelBuffer.h"
#import "components/video_frame_buffer/RTCH264Buffer.h"

#include "api/video/i420_buffer.h"
#include "sdk/objc/native/src/objc_frame_buffer.h"

@interface RTCObjCVideoSourceAdapter ()
@property(nonatomic) webrtc::ObjCVideoTrackSource *objCVideoTrackSource;
@end

@implementation RTCObjCVideoSourceAdapter

@synthesize objCVideoTrackSource = _objCVideoTrackSource;

- (void)capturer:(RTCVideoCapturer *)capturer didCaptureVideoFrame:(RTCVideoFrame *)frame {
  _objCVideoTrackSource->OnCapturedFrame(frame);
}

@end

namespace webrtc {

ObjCVideoTrackSource::ObjCVideoTrackSource() :
  AdaptedVideoTrackSource(/* required resolution alignment */ 4) {}

ObjCVideoTrackSource::ObjCVideoTrackSource(RTCObjCVideoSourceAdapter *adapter) : adapter_(adapter) {
  adapter_.objCVideoTrackSource = this;
}

bool ObjCVideoTrackSource::is_screencast() const {
  return false;
}

absl::optional<bool> ObjCVideoTrackSource::needs_denoising() const {
  return false;
}

MediaSourceInterface::SourceState ObjCVideoTrackSource::state() const {
  return SourceState::kLive;
}

bool ObjCVideoTrackSource::remote() const {
  return false;
}

void ObjCVideoTrackSource::OnOutputFormatRequest(int width, int height, int fps) {
  cricket::VideoFormat format(width, height, cricket::VideoFormat::FpsToInterval(fps), 0);
  video_adapter()->OnOutputFormatRequest(format);
}

void ObjCVideoTrackSource::OnCapturedH264Frame(RTCVideoFrame *frame) {
  const int64_t timestamp_us = frame.timeStampNs / rtc::kNumNanosecsPerMicrosec;
  const int64_t translated_timestamp_us =
      timestamp_aligner_.TranslateTimestamp(timestamp_us, rtc::TimeMicros());

  rtc::scoped_refptr<VideoFrameBuffer> buffer;
  if ([frame.buffer isKindOfClass:[RTCH264Buffer class]]) {
    buffer = new rtc::RefCountedObject<ObjCFrameBuffer>((RTCH264Buffer *)frame.buffer);
  }
  // Applying rotation is only supported for legacy reasons and performance is
  // not critical here.
  VideoRotation rotation = static_cast<VideoRotation>(frame.rotation);
  // rotation = kVideoRotation_0;

  OnFrame(VideoFrame::Builder()
              .set_video_frame_buffer(buffer)
              .set_rotation(rotation)
              .set_timestamp_us(translated_timestamp_us)
              .build());
}

void ObjCVideoTrackSource::OnCapturedFrame(RTCVideoFrame *frame) {
  if ([frame.buffer isKindOfClass:[RTCH264Buffer class]]) {
    OnCapturedH264Frame(frame);
    return;
  }

  const int64_t timestamp_us = frame.timeStampNs / rtc::kNumNanosecsPerMicrosec;
  const int64_t translated_timestamp_us =
      timestamp_aligner_.TranslateTimestamp(timestamp_us, rtc::TimeMicros());

  int adapted_width;
  int adapted_height;
  int crop_width;
  int crop_height;
  int crop_x;
  int crop_y;
  if (!AdaptFrame(frame.width,
                  frame.height,
                  timestamp_us,
                  &adapted_width,
                  &adapted_height,
                  &crop_width,
                  &crop_height,
                  &crop_x,
                  &crop_y)) {
    return;
  }

  rtc::scoped_refptr<VideoFrameBuffer> buffer;
  if (adapted_width == frame.width && adapted_height == frame.height) {
    // No adaption - optimized path.
    buffer = new rtc::RefCountedObject<ObjCFrameBuffer>(frame.buffer);
  } else if ([frame.buffer isKindOfClass:[RTCCVPixelBuffer class]]) {
    // Adapted CVPixelBuffer frame.
    RTCCVPixelBuffer *rtcPixelBuffer = (RTCCVPixelBuffer *)frame.buffer;
    buffer = new rtc::RefCountedObject<ObjCFrameBuffer>([[RTCCVPixelBuffer alloc]
        initWithPixelBuffer:rtcPixelBuffer.pixelBuffer
               adaptedWidth:adapted_width
              adaptedHeight:adapted_height
                  cropWidth:crop_width
                 cropHeight:crop_height
                      cropX:crop_x + rtcPixelBuffer.cropX
                      cropY:crop_y + rtcPixelBuffer.cropY]);
  } else {
    // Adapted I420 frame.
    // TODO(magjed): Optimize this I420 path.
    rtc::scoped_refptr<I420Buffer> i420_buffer = I420Buffer::Create(adapted_width, adapted_height);
    buffer = new rtc::RefCountedObject<ObjCFrameBuffer>(frame.buffer);
    i420_buffer->CropAndScaleFrom(*buffer->ToI420(), crop_x, crop_y, crop_width, crop_height);
    buffer = i420_buffer;
  }

  // Applying rotation is only supported for legacy reasons and performance is
  // not critical here.
  VideoRotation rotation = static_cast<VideoRotation>(frame.rotation);
  // if (apply_rotation() && rotation != kVideoRotation_0) {
  //   buffer = I420Buffer::Rotate(*buffer->ToI420(), rotation);
  //   rotation = kVideoRotation_0;
  // }
  //sll modify：（1）当采集的buffer颜色空间问BGRA时，且帧方向kVideoRotation_0，则会跳过帧数据的转换，
  //造成在渲染的时候经帧数据误认为NV12，由于渲染只支持I420和NV12，即而出现渲染拉升即颜色异常。因此在此
  //去掉kVideoRotation_0的检测。目前从效果及源码描述来看，不会造成效率问题。(20200729)
  //（2）当浏览器和iOS同时登陆一个账号时，iOS创建会议，然后浏览器结束会议，iOS出现短暂黄屏，主要是因为在结束会议时，会移除sink，而且会把
  //apply_rotation()的值职位false，从造成不会将RGBA转换为I420，造成黄屏。目前的修改方法是去掉“if (apply_rotation())”判断条件，
  //从代码来看，推测此处修改可能会造成效率受影响。经多次测试验证，暂未发现问题（20200812）
  // if (apply_rotation()) {
    buffer = I420Buffer::Rotate(*buffer->ToI420(), rotation);
    rotation = kVideoRotation_0;
  // }

  OnFrame(VideoFrame::Builder()
              .set_video_frame_buffer(buffer)
              .set_rotation(rotation)
              .set_timestamp_us(translated_timestamp_us)
              .build());
}

}  // namespace webrtc
