/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import SwiftUI

protocol PhotoAnalysisService {
  var serviceName: String { get }
  var supportsAPIKey: Bool { get }

  func analyze(photo: UIImage, prompt: String, apiKey: String?) async throws -> String
}

enum PhotoAnalysisServiceFactory {
  static var defaultAPIKey: String {
    ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
  }

  static func makeDefault() -> any PhotoAnalysisService {
    OpenAIBackedPhotoAnalysisService(
      openAIService: OpenAIImageAnalysisService(),
      fallbackService: SamplePhotoAnalysisService()
    )
  }

  static func makeSample() -> any PhotoAnalysisService {
    SamplePhotoAnalysisService()
  }
}

struct OpenAIBackedPhotoAnalysisService: PhotoAnalysisService {
  let openAIService: OpenAIImageAnalysisService
  let fallbackService: SamplePhotoAnalysisService

  var serviceName: String { "ChatGPT" }
  var supportsAPIKey: Bool { true }

  func analyze(photo: UIImage, prompt: String, apiKey: String?) async throws -> String {
    let trimmedAPIKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmedAPIKey.isEmpty else {
      return try await fallbackService.analyze(photo: photo, prompt: prompt, apiKey: nil)
    }

    return try await openAIService.analyze(photo: photo, prompt: prompt, apiKey: trimmedAPIKey)
  }
}

struct SamplePhotoAnalysisService: PhotoAnalysisService {
  var serviceName: String { "Sample Analysis" }
  var supportsAPIKey: Bool { false }

  func analyze(photo: UIImage, prompt: String, apiKey: String?) async throws -> String {
    "Sample analysis: The captured photo appears to show a healthy green plant in the scene. Lighting and framing look usable for a quick visual check, and nothing needs urgent attention."
  }
}

struct OpenAIImageAnalysisService {
  private let endpoint = URL(string: "https://api.openai.com/v1/responses")!
  private let model = "gpt-4.1-mini"
  private let urlSession: URLSession

  init(urlSession: URLSession = .shared) {
    self.urlSession = urlSession
  }

  func analyze(photo: UIImage, prompt: String, apiKey: String) async throws -> String {
    guard let jpegData = photo.jpegData(compressionQuality: 0.82) else {
      throw OpenAIImageAnalysisError.imageEncodingFailed
    }

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(
      ResponsesRequest(
        model: model,
        input: [
          .init(
            role: "user",
            content: [
              .init(type: "input_text", text: prompt, detail: nil, imageURL: nil),
              .init(
                type: "input_image",
                text: nil,
                detail: "auto",
                imageURL: "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
              ),
            ]
          ),
        ],
        maxOutputTokens: 350
      )
    )

    let (data, response) = try await urlSession.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw OpenAIImageAnalysisError.invalidResponse
    }

    let decoded = try JSONDecoder().decode(ResponsesResponse.self, from: data)
    if let message = decoded.error?.message {
      throw OpenAIImageAnalysisError.api(message)
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      throw OpenAIImageAnalysisError.api("OpenAI returned HTTP \(httpResponse.statusCode).")
    }

    let text = (decoded.output ?? [])
      .flatMap { $0.content ?? [] }
      .compactMap(\.text)
      .joined(separator: "\n\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard !text.isEmpty else {
      throw OpenAIImageAnalysisError.emptyOutput
    }

    return text
  }
}

private struct ResponsesRequest: Encodable {
  let model: String
  let input: [InputMessage]
  let maxOutputTokens: Int

  enum CodingKeys: String, CodingKey {
    case model
    case input
    case maxOutputTokens = "max_output_tokens"
  }

  struct InputMessage: Encodable {
    let role: String
    let content: [InputContent]
  }

  struct InputContent: Encodable {
    let type: String
    let text: String?
    let detail: String?
    let imageURL: String?

    enum CodingKeys: String, CodingKey {
      case type
      case text
      case detail
      case imageURL = "image_url"
    }
  }
}

private struct ResponsesResponse: Decodable {
  let output: [OutputItem]?
  let error: APIError?

  struct OutputItem: Decodable {
    let content: [OutputContent]?
  }

  struct OutputContent: Decodable {
    let text: String?
  }

  struct APIError: Decodable {
    let message: String
  }
}

enum OpenAIImageAnalysisError: LocalizedError {
  case imageEncodingFailed
  case invalidResponse
  case emptyOutput
  case api(String)

  var errorDescription: String? {
    switch self {
    case .imageEncodingFailed:
      return "Unable to encode the captured photo as JPEG."
    case .invalidResponse:
      return "OpenAI returned an invalid response."
    case .emptyOutput:
      return "ChatGPT did not return any text for this photo."
    case .api(let message):
      return message
    }
  }
}
