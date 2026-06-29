/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
import MWDATCamera
import MWDATCore
import Observation
import SwiftUI

enum StreamingStatus {
  case streaming
  case waiting
  case stopped
}

/// ViewModel for video streaming UI. Delegates device management to DeviceSessionManager.
@Observable
@MainActor
final class StreamSessionViewModel {
  // MARK: - State

  var currentVideoFrame: UIImage?
  var aiResponse: String = ""
  var isAnalyzing: Bool = false
  var isLiveModeEnabled: Bool = false
  var hasReceivedFirstFrame: Bool = false
  var streamingStatus: StreamingStatus = .stopped
  var showError: Bool = false
  var errorMessage: String = ""
  var requiresDATAppUpdate: Bool = false

  var capturedPhoto: UIImage?
  var showPhotoPreview: Bool = false
  var showPhotoCaptureError: Bool = false
  var isCapturingPhoto: Bool = false

  var isRecording: Bool = false

  var hasActiveDevice: Bool { sessionManager.hasActiveDevice }
  var isDeviceSessionReady: Bool { sessionManager.isReady }

  var isStreaming: Bool { streamingStatus != .stopped }

  // MARK: - Private

  private let sessionManager: DeviceSessionManager
  private let wearables: WearablesInterface
  private var stream: MWDATCamera.Stream?

  private var stateListenerToken: AnyListenerToken?
  private var videoFrameListenerToken: AnyListenerToken?
  private var errorListenerToken: AnyListenerToken?
  private var photoDataListenerToken: AnyListenerToken?

  private var audioRecorder: AVAudioRecorder?
  private var audioPlayer: AVAudioPlayer?
  private var recordingURL: URL?
  private var voiceQueryFrame: UIImage?

  // MARK: - Init

  init(wearables: WearablesInterface) {
    self.wearables = wearables
    self.sessionManager = DeviceSessionManager(wearables: wearables)

    // Setup Watch Connectivity
    WatchConnectivityManager.shared.onLiveModeToggled = { [weak self] in
      self?.toggleLiveMode()
    }
    WatchConnectivityManager.shared.onVoiceQueryTriggered = { [weak self] in
      Task { await self?.triggerVoiceQuery() }
    }
  }

  // MARK: - Public API

  func handleStartStreaming() async {
    let permission = Permission.camera
    do {
      var status = try await wearables.checkPermissionStatus(permission)
      if status != .granted {
        status = try await wearables.requestPermission(permission)
      }
      guard status == .granted else {
        showError("Permission denied")
        return
      }
      await startSession()
    } catch {
      showError("Permission error: \(error.description)")
    }
  }

  func stopSession() async {
    guard let activeStream = stream else { return }
    stream = nil
    clearListeners()
    streamingStatus = .stopped
    currentVideoFrame = nil
    hasReceivedFirstFrame = false
    await activeStream.stop()
  }

  /// Stops both the stream and the underlying device session. Call in test tearDown.
  func endSession() {
    stream = nil
    clearListeners()
    streamingStatus = .stopped
    currentVideoFrame = nil
    hasReceivedFirstFrame = false
    sessionManager.cleanup()
  }

  func capturePhoto() {
    guard !isCapturingPhoto, streamingStatus == .streaming else {
      showPhotoCaptureError = true
      return
    }
    isCapturingPhoto = true
    let success = stream?.capturePhoto(format: .jpeg) ?? false
    if !success {
      isCapturingPhoto = false
      showPhotoCaptureError = true
    }
  }

  func dismissError() {
    showError = false
    errorMessage = ""
  }

  func dismissPhotoCaptureError() {
    showPhotoCaptureError = false
  }

  func dismissPhotoPreview() {
    showPhotoPreview = false
    capturedPhoto = nil
  }

  func askAI() async {
    guard !isAnalyzing, let frame = currentVideoFrame else { return }

    isAnalyzing = true
    aiResponse = "Thinking..."

    do {
      let response = try await GeminiImageService.shared.analyzeFrame(
        image: frame,
        prompt: "You are a helpful, real-time AI assistant seeing a live stream from Meta Ray-Ban glasses. Your goal is to be the user's 'eyes' and 'brain'. Describe the scene concisely, identify key objects, and answer questions naturally. If you see something interesting or dangerous, point it out immediately. Keep responses brief and conversational."
      )
      aiResponse = response
      WatchConnectivityManager.shared.sendAIResponse(response)
    } catch {
      aiResponse = "Error: \(error.localizedDescription)"
    }

    isAnalyzing = false
  }

  func toggleLiveMode() {
    isLiveModeEnabled.toggle()
    if isLiveModeEnabled {
      startLiveAnalysisLoop()
    }
  }

  // MARK: - Voice Query

  func triggerVoiceQuery() async {
    if isRecording {
      await finishVoiceQuery()
    } else if !isAnalyzing {
      await startVoiceRecording()
    }
  }

  private func startVoiceRecording() async {
    guard let frame = currentVideoFrame else {
      showError("No video frame yet — make sure streaming is active.")
      return
    }

    let granted = await withCheckedContinuation { continuation in
      AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
    }
    guard granted else {
      showError("Microphone permission is required for voice queries.")
      return
    }

    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".m4a")
    let settings: [String: Any] = [
      AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
      AVSampleRateKey: 16000,
      AVNumberOfChannelsKey: 1,
      AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
    ]

    do {
      try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
      try AVAudioSession.sharedInstance().setActive(true)
      audioRecorder = try AVAudioRecorder(url: url, settings: settings)
      audioRecorder?.record(forDuration: 8)
      recordingURL = url
      voiceQueryFrame = frame
      isRecording = true
    } catch {
      showError("Could not start recording: \(error.localizedDescription)")
      return
    }

    // Auto-finish when the 8-second recording window closes
    Task {
      try? await Task.sleep(nanoseconds: 8_100_000_000)
      if isRecording { await finishVoiceQuery() }
    }
  }

  private func finishVoiceQuery() async {
    guard isRecording else { return }
    audioRecorder?.stop()
    audioRecorder = nil
    isRecording = false

    guard let url = recordingURL, let frame = voiceQueryFrame else { return }
    recordingURL = nil
    voiceQueryFrame = nil

    isAnalyzing = true
    aiResponse = "Listening..."

    do {
      let (text, audioData) = try await ChatGPTStreamingService.shared.analyzeVoiceAndFrame(
        image: frame,
        audioURL: url,
        prompt: "You are a helpful AI assistant the user can talk to through their Meta Ray-Ban glasses. Answer their question about what you see clearly and concisely. Your response will be read aloud, so speak naturally — no markdown, no bullet points."
      )
      aiResponse = text
      WatchConnectivityManager.shared.sendAIResponse(text)
      playAudioData(audioData)
    } catch {
      aiResponse = "Error: \(error.localizedDescription)"
    }

    isAnalyzing = false
    try? FileManager.default.removeItem(at: url)
  }

  private func playAudioData(_ data: Data) {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
      audioPlayer = try AVAudioPlayer(data: data)
      audioPlayer?.play()
    } catch {
      print("⚠️ StreamSessionViewModel: failed to play TTS audio: \(error)")
    }
  }

  private func startLiveAnalysisLoop() {
    Task {
      while isLiveModeEnabled {
        await askAI()
        // Wait 8 seconds between analyses to avoid API rate limits and cost
        try? await Task.sleep(nanoseconds: 8 * 1_000_000_000)
      }
    }
  }


  // MARK: - Private

  private func startSession() async {
    let deviceSession: DeviceSession
    do {
      deviceSession = try await sessionManager.getSession()
      requiresDATAppUpdate = false
    } catch DeviceSessionError.datAppOnTheGlassesUpdateRequired {
      requiresDATAppUpdate = true
      showError(DeviceSessionError.datAppOnTheGlassesUpdateRequired.localizedDescription)
      return
    } catch {
      showError("Failed to start session: \(error.localizedDescription)")
      return
    }

    guard deviceSession.state == .started else {
      showError("Device session is not ready. Please try again.")
      return
    }

    let config = StreamConfiguration(
      videoCodec: VideoCodec.raw,
      resolution: StreamingResolution.low,
      frameRate: 24
    )

    guard let newStream = try? deviceSession.addStream(config: config) else { return }
    stream = newStream
    streamingStatus = .waiting
    setupListeners(for: newStream)
    await newStream.start()
  }

  private func setupListeners(for stream: MWDATCamera.Stream) {
    stateListenerToken = stream.statePublisher.listen { [weak self] state in
      Task { @MainActor in self?.handleStateChange(state) }
    }

    videoFrameListenerToken = stream.videoFramePublisher.listen { [weak self] frame in
      Task { @MainActor in self?.handleVideoFrame(frame) }
    }

    errorListenerToken = stream.errorPublisher.listen { [weak self] error in
      Task { @MainActor in self?.handleError(error) }
    }

    photoDataListenerToken = stream.photoDataPublisher.listen { [weak self] data in
      Task { @MainActor in self?.handlePhotoData(data) }
    }
  }

  private func clearListeners() {
    stateListenerToken = nil
    videoFrameListenerToken = nil
    errorListenerToken = nil
    photoDataListenerToken = nil
  }

  private func handleStateChange(_ state: StreamState) {
    switch state {
    case .stopped:
      currentVideoFrame = nil
      streamingStatus = .stopped
    case .waitingForDevice, .starting, .stopping, .paused:
      streamingStatus = .waiting
    case .streaming:
      streamingStatus = .streaming
    }
  }

  private func handleVideoFrame(_ frame: VideoFrame) {
    if let image = frame.makeUIImage() {
      currentVideoFrame = image
      if !hasReceivedFirstFrame {
        hasReceivedFirstFrame = true
      }
    }
  }

  private func handleError(_ error: StreamError) {
    let message = error.localizedDescription
    if message != errorMessage {
      showError(message)
    }
  }

  private func handlePhotoData(_ data: PhotoData) {
    isCapturingPhoto = false
    if let image = UIImage(data: data.data) {
      capturedPhoto = image
      showPhotoPreview = true
    }
  }

  private func showError(_ message: String) {
    errorMessage = message
    showError = true
  }

}
