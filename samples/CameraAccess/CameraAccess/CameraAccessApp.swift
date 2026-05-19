/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// CameraAccessApp.swift
//
// Main entry point for the CameraAccess sample app demonstrating the Meta Wearables DAT SDK.
// This app shows how to connect to wearable devices (like Ray-Ban Meta smart glasses),
// stream live video from their cameras, and capture photos. It provides a complete example
// of DAT SDK integration including device registration, permissions, and media streaming.
//

import Foundation
import MWDATCore
import SwiftUI

#if DEBUG
import MWDATMockDevice
#endif

@main
struct CameraAccessApp: App {
  #if DEBUG
  // Debug menu for simulating device connections during development
  @State private var debugMenuViewModel: DebugMenuViewModel?
  #endif
  private let wearables: WearablesInterface
  private let isRunningUnitTests: Bool
  @State private var wearablesViewModel: WearablesViewModel

  init() {
    let processInfo = ProcessInfo.processInfo
    let isUITesting = processInfo.arguments.contains("--ui-testing")
    let shouldSkipAppStartup = processInfo.environment["CAMERAACCESS_SKIP_APP_STARTUP"] == "1"
    let isRunningUnitTests =
      (shouldSkipAppStartup || processInfo.environment["XCTestConfigurationFilePath"] != nil) && !isUITesting
    self.isRunningUnitTests = isRunningUnitTests

    if !isRunningUnitTests {
      do {
        try Wearables.configure()
      } catch {
        #if DEBUG
        NSLog("[CameraAccess] Failed to configure Wearables SDK: \(error)")
        #endif
      }
    }

    #if DEBUG
    self._debugMenuViewModel = State(
      wrappedValue: isRunningUnitTests ? nil : DebugMenuViewModel(mockDeviceKit: MockDeviceKit.shared)
    )

    // Start the test server when launched by XCUITests so tests can control
    // mock device setup via HTTP commands from the test process.
    if isUITesting {
      MockDeviceKit.shared.enable(config: MockDeviceKitConfig(initiallyRegistered: false))

      let portFilePath = processInfo.environment["MWDAT_TEST_SERVER_PORT_FILE"]
      Task {
        do {
          try await MockDeviceKit.shared.startTestServer(portFilePath: portFilePath)
        } catch {
          NSLog("[CameraAccess] Failed to start MockDeviceKit test server: \(error)")
        }
      }
    }
    #endif

    let wearables = Wearables.shared
    self.wearables = wearables
    self._wearablesViewModel = State(wrappedValue: WearablesViewModel(wearables: wearables))
  }

  var body: some Scene {
    WindowGroup {
      if isRunningUnitTests {
        EmptyView()
      } else {
        // Main app view with access to the shared Wearables SDK instance
        // The Wearables.shared singleton provides the core DAT API
        MainAppView(wearables: Wearables.shared, viewModel: wearablesViewModel)
          // Show error alerts for view model failures
          .alert("Error", isPresented: $wearablesViewModel.showError) {
            Button("OK") {
              wearablesViewModel.dismissError()
            }
          } message: {
            Text(wearablesViewModel.errorMessage)
          }
          #if DEBUG
          .sheet(
            isPresented: Binding(
              get: { debugMenuViewModel?.showDebugMenu ?? false },
              set: { debugMenuViewModel?.showDebugMenu = $0 }
            )
          ) {
            if let debugMenuViewModel {
              MockDeviceKitView(viewModel: debugMenuViewModel.mockDeviceKitViewModel)
            }
          }
          .overlay {
            if let debugMenuViewModel {
              DebugMenuView(debugMenuViewModel: debugMenuViewModel)
            }
          }
          #endif

        // Registration view handles the flow for connecting to the glasses via Meta AI
        RegistrationView(viewModel: wearablesViewModel)
      }
    }
  }
}
