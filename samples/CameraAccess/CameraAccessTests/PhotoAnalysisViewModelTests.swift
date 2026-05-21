/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CameraAccess
import SwiftUI
import XCTest

@MainActor
final class PhotoAnalysisViewModelTests: XCTestCase {

  func testAnalyzeHappyPathPublishesAnalysisText() async {
    let service = StubPhotoAnalysisService(result: "The photo shows a healthy plant.")
    let viewModel = PhotoAnalysisViewModel(service: service, apiKey: "test-key")
    viewModel.prompt = "What is in this photo?"

    await viewModel.analyze(photo: UIImage())

    XCTAssertEqual(viewModel.analysisText, "The photo shows a healthy plant.")
    XCTAssertEqual(viewModel.analysisError, "")
    XCTAssertFalse(viewModel.isAnalyzing)
    XCTAssertEqual(service.receivedPrompt, "What is in this photo?")
    XCTAssertEqual(service.receivedAPIKey, "test-key")
  }

  func testAnalyzeFailurePublishesErrorAndClearsAnalyzingState() async {
    let service = StubPhotoAnalysisService(error: TestAnalysisError.expectedFailure)
    let viewModel = PhotoAnalysisViewModel(service: service, apiKey: "test-key")

    await viewModel.analyze(photo: UIImage())

    XCTAssertEqual(viewModel.analysisText, "")
    XCTAssertEqual(viewModel.analysisError, "Expected analysis failure.")
    XCTAssertFalse(viewModel.isAnalyzing)
  }

  func testAnalyzeIgnoresSecondRequestWhileAnalyzing() async {
    let service = DelayedPhotoAnalysisService()
    let viewModel = PhotoAnalysisViewModel(service: service, apiKey: "test-key")

    let firstRequest = Task {
      await viewModel.analyze(photo: UIImage())
    }

    await service.waitUntilStarted()
    await viewModel.analyze(photo: UIImage())
    await service.finish(with: "Done")
    await firstRequest.value

    XCTAssertEqual(viewModel.analysisText, "Done")
    XCTAssertEqual(service.callCount, 1)
    XCTAssertFalse(viewModel.isAnalyzing)
  }
}

private final class StubPhotoAnalysisService: PhotoAnalysisService {
  let serviceName = "Stub Analysis"
  let supportsAPIKey = true

  private let result: String?
  private let error: Error?
  private(set) var receivedPrompt: String?
  private(set) var receivedAPIKey: String?

  init(result: String? = nil, error: Error? = nil) {
    self.result = result
    self.error = error
  }

  func analyze(photo: UIImage, prompt: String, apiKey: String?) async throws -> String {
    receivedPrompt = prompt
    receivedAPIKey = apiKey
    if let error {
      throw error
    }
    return result ?? ""
  }
}

private enum TestAnalysisError: LocalizedError {
  case expectedFailure

  var errorDescription: String? {
    "Expected analysis failure."
  }
}

private final class DelayedPhotoAnalysisService: PhotoAnalysisService {
  let serviceName = "Delayed Analysis"
  let supportsAPIKey = true

  private(set) var callCount = 0
  private var startedContinuation: CheckedContinuation<Void, Never>?
  private var finishContinuation: CheckedContinuation<String, Never>?

  func analyze(photo: UIImage, prompt: String, apiKey: String?) async throws -> String {
    callCount += 1
    startedContinuation?.resume()
    startedContinuation = nil

    return await withCheckedContinuation { continuation in
      finishContinuation = continuation
    }
  }

  func waitUntilStarted() async {
    guard callCount == 0 else { return }
    await withCheckedContinuation { continuation in
      startedContinuation = continuation
    }
  }

  func finish(with result: String) async {
    finishContinuation?.resume(returning: result)
    finishContinuation = nil
  }
}
