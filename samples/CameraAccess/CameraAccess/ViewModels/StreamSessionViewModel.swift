/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
import AudioToolbox
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
  //
  // Flow (matches what the user asked for):
  //   tap "Ask AI" → INSTANTLY show "Listening…", beep, buzz the Watch
  //   → user speaks → auto-stops ~1.5s after they go quiet (12s hard cap)
  //   → beep, capture the frame NOW (what they're looking at when they finish)
  //   → "Thinking…" → transcribe + analyze + speak the reply back.

  // Silence-detection tuning. ponytail: thresholds are dead-reckoned for the
  // glasses/phone mic; calibrate against a real recording if speech gets clipped
  // (raise silenceThresholdDB) or it hangs on after you stop (lower it).
  private static let silenceThresholdDB: Float = -35.0
  private static let requiredSilence: TimeInterval = 1.5
  private static let maxRecordSeconds: TimeInterval = 12.0
  private static let meterPollSeconds: TimeInterval = 0.1

  /// Pure decision used by the metering loop: stop once the user has spoken and
  /// then gone quiet for `requiredSilence`, or once the hard cap is hit. Extracted
  /// so the timing logic is testable without an `AVAudioRecorder`.
  static func shouldStopRecording(
    elapsed: TimeInterval,
    silence: TimeInterval,
    heardSpeech: Bool
  ) -> Bool {
    (heardSpeech && silence >= requiredSilence) || elapsed >= maxRecordSeconds
  }

  func triggerVoiceQuery() async {
    if isRecording {
      await finishVoiceQuery()   // manual "Stop" tap ends it early
    } else if !isAnalyzing {
      await startVoiceRecording()
    }
  }

  private func startVoiceRecording() async {
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
      try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothA2DP])
      try AVAudioSession.sharedInstance().setActive(true)
      let recorder = try AVAudioRecorder(url: url, settings: settings)
      recorder.isMeteringEnabled = true   // needed for silence auto-stop
      recorder.record()
      audioRecorder = recorder
      recordingURL = url
      isRecording = true
    } catch {
      showError("Could not start recording: \(error.localizedDescription)")
      return
    }

    // Immediate feedback the moment recording starts — this is the fix for
    // "10 seconds before Listening shows up": the label used to appear AFTER the
    // recording window, not at the start.
    aiResponse = "Listening…"
    AudioServicesPlaySystemSound(1113)                       // "begin record" chime
    WatchConnectivityManager.shared.sendListeningState()     // buzz + label on the Watch

    monitorForSilence()
  }

  /// Polls the recorder's audio level and auto-stops ~1.5s after the user goes
  /// quiet (only once speech was actually detected), with a hard 12s cap.
  private func monitorForSilence() {
    Task { @MainActor in
      var elapsed: TimeInterval = 0
      var silence: TimeInterval = 0
      var heardSpeech = false

      while isRecording, let recorder = audioRecorder {
        try? await Task.sleep(nanoseconds: UInt64(Self.meterPollSeconds * 1_000_000_000))
        guard isRecording else { return }

        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        elapsed += Self.meterPollSeconds

        if power > Self.silenceThresholdDB {
          heardSpeech = true
          silence = 0
        } else if heardSpeech {
          silence += Self.meterPollSeconds
        }

        if Self.shouldStopRecording(elapsed: elapsed, silence: silence, heardSpeech: heardSpeech) {
          await finishVoiceQuery()
          return
        }
      }
    }
  }

  private func finishVoiceQuery() async {
    guard isRecording else { return }
    audioRecorder?.stop()
    audioRecorder = nil
    isRecording = false

    AudioServicesPlaySystemSound(1114)   // "end record" chime

    guard let url = recordingURL else { return }
    recordingURL = nil

    // Capture the frame NOW — after the question — so the AI sees what the user is
    // looking at when they finish asking, not what they saw when they tapped.
    guard let frame = currentVideoFrame else {
      showError("No video frame available — make sure streaming is active.")
      try? FileManager.default.removeItem(at: url)
      return
    }

    isAnalyzing = true
    aiResponse = "Thinking…"
    WatchConnectivityManager.shared.sendThinkingState()

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
      WatchConnectivityManager.shared.sendAIResponse(aiResponse)
    }

    isAnalyzing = false
    try? FileManager.default.removeItem(at: url)
  }

  private func playAudioData(_ data: Data) {
    print("🔊 TTS reply: \(data.count) bytes")
    guard !data.isEmpty else {
      print("⚠️ StreamSessionViewModel: TTS returned no audio")
      return
    }
    do {
      // .playback (NOT .playAndRecord) so Bluetooth uses the full-quality A2DP
      // profile. .playAndRecord forces the low-bandwidth HFP profile, which was
      // cutting the spoken reply off after a few words on the glasses.
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.allowBluetoothA2DP])
      try AVAudioSession.sharedInstance().setActive(true)
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
    // Pre-warm microphone permission so the first "Ask AI" tap doesn't stall on the
    // permission prompt the very first time. Fire-and-forget; result is read later.
    AVAudioSession.sharedInstance().requestRecordPermission { _ in }

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
