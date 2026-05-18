/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// PhotoPreviewView.swift
//
// UI for previewing and sharing photos captured from Meta wearable devices via the DAT SDK.
// This view displays photos captured using Stream.capturePhoto() and provides sharing
// functionality.
//

import Foundation
import SwiftUI

struct PhotoPreviewView: View {
  let photo: UIImage
  let onDismiss: () -> Void

  @State private var showShareSheet = false
  @State private var prompt = "Describe what you see and call out anything that may need my attention."
  @State private var apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
  @State private var analysisText = ""
  @State private var analysisError = ""
  @State private var isAnalyzing = false
  @State private var dragOffset = CGSize.zero

  var body: some View {
    ZStack {
      // Semi-transparent background overlay
      Color.black.opacity(0.8)
        .ignoresSafeArea()
        .onTapGesture {
          dismissWithAnimation()
        }

      VStack(spacing: 20) {
        photoDisplayView

        actionPanel

        HStack(spacing: 14) {
          CircleButton(icon: "sparkles", text: nil) {
            analyzePhoto()
          }
          .accessibilityIdentifier("ask_chatgpt_button")
          .disabled(isAnalyzing)
          .opacity(isAnalyzing ? 0.6 : 1.0)

          CircleButton(icon: "square.and.arrow.up", text: nil) {
            showShareSheet = true
          }
        }
      }
      .padding()
      .offset(dragOffset)
      .animation(.spring(response: 0.6, dampingFraction: 0.8), value: dragOffset)

      // Close button in top right
      VStack {
        HStack {
          Spacer()
          CircleButton(icon: "xmark", text: nil) {
            dismissWithAnimation()
          }
          .accessibilityIdentifier("close_preview_button")
          .padding(.trailing, 20)
          .padding(.top, 50)
        }
        Spacer()
      }
    }
    .sheet(isPresented: $showShareSheet) {
      ShareSheet(photo: photo)
    }
  }

  private var actionPanel: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Ask ChatGPT")
        .font(.headline)
        .foregroundStyle(.white)

      SecureField("OpenAI API key", text: $apiKey)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .font(.system(size: 14))
        .padding(12)
        .background(.white.opacity(0.14))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))

      TextField("Prompt", text: $prompt, axis: .vertical)
        .lineLimit(2...4)
        .font(.system(size: 14))
        .padding(12)
        .background(.white.opacity(0.14))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))

      if isAnalyzing {
        ProgressView("Analyzing photo...")
          .tint(.white)
          .foregroundStyle(.white)
      }

      if !analysisText.isEmpty {
        ScrollView {
          Text(analysisText)
            .font(.system(size: 14))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 140)
      }

      if !analysisError.isEmpty {
        Text(analysisError)
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(.red.opacity(0.9))
      }
    }
    .padding(16)
    .background(.black.opacity(0.45))
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  private var photoDisplayView: some View {
    GeometryReader { geometry in
      Image(uiImage: photo)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height * 0.6)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        .frame(width: geometry.size.width, height: geometry.size.height)
        .gesture(
          DragGesture()
            .onChanged { value in
              dragOffset = value.translation
            }
            .onEnded { value in
              if abs(value.translation.height) > 100 {
                dismissWithAnimation()
              } else {
                withAnimation(.spring()) {
                  dragOffset = .zero
                }
              }
            }
        )
    }
  }

  private func dismissWithAnimation() {
    withAnimation(.easeInOut(duration: 0.3)) {
      dragOffset = CGSize(width: 0, height: UIScreen.main.bounds.height)
    }
    Task {
      try? await Task.sleep(nanoseconds: 300_000_000)
      onDismiss()
    }
  }

  private func analyzePhoto() {
    let trimmedApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedApiKey.isEmpty else {
      analysisError = "Add an OpenAI API key to analyze this glasses photo."
      return
    }

    isAnalyzing = true
    analysisError = ""
    analysisText = ""

    Task {
      do {
        let result = try await OpenAIImageAnalysisService().analyze(
          photo: photo,
          prompt: prompt,
          apiKey: trimmedApiKey
        )
        await MainActor.run {
          analysisText = result
          isAnalyzing = false
        }
      } catch {
        await MainActor.run {
          analysisError = error.localizedDescription
          isAnalyzing = false
        }
      }
    }
  }
}

struct ShareSheet: UIViewControllerRepresentable {
  let photo: UIImage

  func makeUIViewController(context: Context) -> UIActivityViewController {
    let activityViewController = UIActivityViewController(
      activityItems: [photo],
      applicationActivities: nil
    )

    // Exclude certain activity types if needed
    activityViewController.excludedActivityTypes = [
      .assignToContact,
      .addToReadingList,
    ]

    return activityViewController
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    // No updates needed
  }
}

private struct OpenAIImageAnalysisService {
  private let endpoint = URL(string: "https://api.openai.com/v1/responses")!
  private let model = "gpt-4.1-mini"

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
              .init(type: "input_text", text: prompt, imageURL: nil),
              .init(
                type: "input_image",
                text: nil,
                imageURL: "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
              ),
            ]
          ),
        ],
        maxOutputTokens: 350
      )
    )

    let (data, response) = try await URLSession.shared.data(for: request)
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
    let imageURL: String?

    enum CodingKeys: String, CodingKey {
      case type
      case text
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

private enum OpenAIImageAnalysisError: LocalizedError {
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
