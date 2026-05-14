/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// SampleAppsView.swift
//
// Main screen listing available sample apps that demonstrate DAT SDK Display features.
// Each sample shows an icon, title, and description at the top with a "Try it" button
// pinned to the bottom of the screen that sends the display view to the glasses.
//

import SwiftUI

// MARK: - SampleAppItem

enum SampleAppItem: String, CaseIterable, Identifiable {
  case carMaintenance = "car-maintenance"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .carMaintenance: "Car maintenance guide"
    }
  }

  var description: String {
    switch self {
    case .carMaintenance:
      "A sample of a display experience where you follow a step by step guide to complete car maintenance task."
    }
  }

  var iconName: String {
    switch self {
    case .carMaintenance: "car.fill"
    }
  }

  var iconBackground: Color {
    switch self {
    case .carMaintenance: Color(red: 0.32, green: 0.10, blue: 0.10)
    }
  }
}

// MARK: - SampleAppsView

struct SampleAppsView: View {
  var displayViewModel: DisplayViewModel

  private let item: SampleAppItem = .carMaintenance

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: item.iconName)
        .font(.system(size: 32, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 72, height: 72)
        .background(item.iconBackground, in: RoundedRectangle(cornerRadius: 16))
        .padding(.top, 48)

      Text(item.title)
        .font(.title3.weight(.semibold))
        .foregroundStyle(.primary)
        .multilineTextAlignment(.center)

      Text(item.description)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      Spacer()

      SwiftUI.Button {
        Task { await sendSample(item) }
      } label: {
        Text("Try it")
          .font(.body.weight(.semibold))
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 16)
          .background(
            LinearGradient(
              colors: [Color(red: 0.30, green: 0.45, blue: 0.95), Color(red: 0.15, green: 0.25, blue: 0.85)],
              startPoint: .leading,
              endPoint: .trailing
            ),
            in: Capsule()
          )
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 24)
    .padding(.bottom, 16)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .toolbar(.hidden, for: .navigationBar)
  }

  private func sendSample(_ item: SampleAppItem) async {
    switch item {
    case .carMaintenance:
      await displayViewModel.sendCarMaintenanceTutorialList()
    }
  }
}
