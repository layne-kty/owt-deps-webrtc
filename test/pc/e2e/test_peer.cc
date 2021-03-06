/*
 *  Copyright (c) 2019 The WebRTC project authors. All Rights Reserved.
 *
 *  Use of this source code is governed by a BSD-style license
 *  that can be found in the LICENSE file in the root of the source
 *  tree. An additional intellectual property rights grant can be found
 *  in the file PATENTS.  All contributing project authors may
 *  be found in the AUTHORS file in the root of the source tree.
 */
#include "test/pc/e2e/test_peer.h"

#include <string>
#include <utility>

#include "absl/memory/memory.h"
#include "api/scoped_refptr.h"
#include "modules/audio_processing/include/audio_processing.h"

namespace webrtc {
namespace webrtc_pc_e2e {

bool TestPeer::AddIceCandidates(
    std::vector<std::unique_ptr<IceCandidateInterface>> candidates) {
  bool success = true;
  for (auto& candidate : candidates) {
    if (!pc()->AddIceCandidate(candidate.get())) {
      std::string candidate_str;
      bool res = candidate->ToString(&candidate_str);
      RTC_CHECK(res);
      RTC_LOG(LS_ERROR) << "Failed to add ICE candidate, candidate_str="
                        << candidate_str;
      success = false;
    } else {
      remote_ice_candidates_.push_back(std::move(candidate));
    }
  }
  return success;
}

TestPeer::TestPeer(
    rtc::scoped_refptr<PeerConnectionFactoryInterface> pc_factory,
    rtc::scoped_refptr<PeerConnectionInterface> pc,
    std::unique_ptr<MockPeerConnectionObserver> observer,
    std::unique_ptr<Params> params,
    std::vector<std::unique_ptr<test::FrameGeneratorInterface>>
        video_generators,
    rtc::scoped_refptr<AudioProcessing> audio_processing)
    : PeerConnectionWrapper::PeerConnectionWrapper(std::move(pc_factory),
                                                   std::move(pc),
                                                   std::move(observer)),
      params_(std::move(params)),
      video_generators_(std::move(video_generators)),
      audio_processing_(audio_processing) {}

}  // namespace webrtc_pc_e2e
}  // namespace webrtc
