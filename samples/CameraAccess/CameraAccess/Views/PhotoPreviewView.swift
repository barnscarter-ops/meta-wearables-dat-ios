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
  @State private var analysisViewModel: PhotoAnalysisViewModel
  @State private var dragOffset = CGSize.zero

  @MainActor
  init(
    photo: UIImage,
    analysisViewModel: PhotoAnalysisViewModel? = nil,
    onDismiss: @escaping () -> Void
  ) {
    self.photo = photo
    self._analysisViewModel = State(wrappedValue: analysisViewModel ?? PhotoAnalysisViewModel())
    self.onDismiss = onDismiss
  }

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
          .disabled(analysisViewModel.isAnalyzing)
          .opacity(analysisViewModel.isAnalyzing ? 0.6 : 1.0)

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
    @Bindable var analysisViewModel = analysisViewModel

    VStack(alignment: .leading, spacing: 12) {
      Text(analysisViewModel.serviceName)
        .font(.headline)
        .foregroundStyle(.white)

      if analysisViewModel.supportsAPIKey {
        SecureField("OpenAI API key (optional for demo)", text: $analysisViewModel.apiKey)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .font(.system(size: 14))
          .padding(12)
          .background(.white.opacity(0.14))
          .foregroundStyle(.white)
          .clipShape(RoundedRectangle(cornerRadius: 8))
      }

      TextField("Prompt", text: $analysisViewModel.prompt, axis: .vertical)
        .lineLimit(2...4)
        .font(.system(size: 14))
        .padding(12)
        .background(.white.opacity(0.14))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))

      if analysisViewModel.isAnalyzing {
        ProgressView("Analyzing photo...")
          .tint(.white)
          .foregroundStyle(.white)
      }

      if !analysisViewModel.analysisText.isEmpty {
        ScrollView {
          Text(analysisViewModel.analysisText)
            .font(.system(size: 14))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 140)
      }

      if !analysisViewModel.analysisError.isEmpty {
        Text(analysisViewModel.analysisError)
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
    Task {
      await analysisViewModel.analyze(photo: photo)
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

#Preview {
  PhotoPreviewView(
    photo: UIImage(systemName: "camera.fill") ?? UIImage(),
    analysisViewModel: PhotoAnalysisViewModel(service: PhotoAnalysisServiceFactory.makeSample()),
    onDismiss: {}
  )
}
