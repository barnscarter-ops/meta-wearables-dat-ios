/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CameraAccess
import Foundation
import MWDATCore
import SwiftUI
import XCTest

@MainActor
final class StreamSessionViewModelUnitTests: XCTestCase {

  func testCapturePhotoWithoutActiveStreamShowsError() {
    let viewModel = StreamSessionViewModel(wearables: FakeWearables())

    XCTAssertFalse(viewModel.showPhotoCaptureError)

    viewModel.capturePhoto()

    XCTAssertTrue(viewModel.showPhotoCaptureError)
    XCTAssertFalse(viewModel.isCapturingPhoto)
  }

  func testDismissPhotoPreviewClearsCapturedPhoto() {
    let viewModel = StreamSessionViewModel(wearables: FakeWearables())
    viewModel.capturedPhoto = UIImage()
    viewModel.showPhotoPreview = true

    viewModel.dismissPhotoPreview()

    XCTAssertNil(viewModel.capturedPhoto)
    XCTAssertFalse(viewModel.showPhotoPreview)
  }

  // Voice-query auto-stop-on-silence timing logic.
  func testShouldStopRecordingOnSilenceAfterSpeech() {
    // Spoke, then quiet for 1.5s → stop.
    XCTAssertTrue(StreamSessionViewModel.shouldStopRecording(elapsed: 4.0, silence: 1.5, heardSpeech: true))
  }

  func testShouldNotStopWhileStillSpeaking() {
    // Speech detected but only 0.5s of silence so far → keep recording.
    XCTAssertFalse(StreamSessionViewModel.shouldStopRecording(elapsed: 4.0, silence: 0.5, heardSpeech: true))
  }

  func testShouldNotStopOnLeadingSilence() {
    // Quiet for a while but the user hasn't started talking yet → keep waiting.
    XCTAssertFalse(StreamSessionViewModel.shouldStopRecording(elapsed: 3.0, silence: 3.0, heardSpeech: false))
  }

  func testShouldStopAtHardCapEvenWithoutSpeech() {
    // Nobody spoke, but we've hit the 12s cap → stop anyway.
    XCTAssertTrue(StreamSessionViewModel.shouldStopRecording(elapsed: 12.0, silence: 0.0, heardSpeech: false))
  }
}

private final class FakeListenerToken: AnyListenerToken, @unchecked Sendable {
  func cancel() async {}
}

private final class FakeWearables: WearablesInterface, @unchecked Sendable {
  var registrationState: RegistrationState { .unavailable }
  var devices: [DeviceIdentifier] { [] }

  func addRegistrationStateListener(
    _ listener: @escaping @Sendable (RegistrationState) -> Void
  ) -> any AnyListenerToken {
    FakeListenerToken()
  }

  func registrationStateStream() -> AsyncStream<RegistrationState> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }

  func startRegistration() async throws(RegistrationError) {}

  func handleUrl(_ url: URL) async throws(WearablesHandleURLError) -> Bool {
    false
  }

  func startUnregistration() async throws(UnregistrationError) {}

  func openFirmwareUpdate() async throws(NavigationError) {}

  func openDATGlassesAppUpdate() async throws(NavigationError) {}

  func addDevicesListener(
    _ listener: @escaping @Sendable ([DeviceIdentifier]) -> Void
  ) -> any AnyListenerToken {
    FakeListenerToken()
  }

  func devicesStream() -> AsyncStream<[DeviceIdentifier]> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }

  func deviceForIdentifier(_ identifier: DeviceIdentifier) -> Device? {
    nil
  }

  func checkPermissionStatus(_ permission: Permission) async throws(PermissionError) -> PermissionStatus {
    .granted
  }

  func requestPermission(_ permission: Permission) async throws(PermissionError) -> PermissionStatus {
    .granted
  }

  func createSession(deviceSelector: any DeviceSelector) throws(DeviceSessionError) -> DeviceSession {
    throw .noEligibleDevice
  }

  func deviceStateStream(for identifier: DeviceIdentifier) -> AsyncStream<DeviceState> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
