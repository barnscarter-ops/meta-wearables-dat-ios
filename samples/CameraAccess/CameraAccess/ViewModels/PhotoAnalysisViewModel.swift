/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Observation
import SwiftUI

@Observable
@MainActor
final class PhotoAnalysisViewModel {
  var prompt = "Describe what you see and call out anything that may need my attention."
  var apiKey: String
  var analysisText = ""
  var analysisError = ""
  var isAnalyzing = false

  let service: any PhotoAnalysisService

  var serviceName: String { service.serviceName }
  var supportsAPIKey: Bool { service.supportsAPIKey }

  init(
    service: any PhotoAnalysisService = PhotoAnalysisServiceFactory.makeDefault(),
    apiKey: String = PhotoAnalysisServiceFactory.defaultAPIKey
  ) {
    self.service = service
    self.apiKey = apiKey
  }

  func analyze(photo: UIImage) async {
    guard !isAnalyzing else { return }

    isAnalyzing = true
    analysisError = ""
    analysisText = ""
    defer { isAnalyzing = false }

    do {
      analysisText = try await service.analyze(
        photo: photo,
        prompt: prompt,
        apiKey: apiKey
      )
    } catch {
      analysisError = error.localizedDescription
    }
  }
}
