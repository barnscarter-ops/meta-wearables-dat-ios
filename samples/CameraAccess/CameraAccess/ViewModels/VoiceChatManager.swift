import Foundation
import AVFoundation

enum VoiceChatError: Error {
    case recordingFailed
    case playbackFailed
    case permissionDenied
}

@MainActor
final class VoiceChatManager: NSObject {
    static let shared = VoiceChatManager()

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private let audioSession = AVAudioSession.sharedInstance()

    private override init() {
        super.init()
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
        } catch {
            print("⚠️ VoiceChatManager: Failed to set up audio session: \(error)")
        }
    }

    func startRecording() async throws {
        let recordingURL = FileManager.default.temporaryDirectory.appendingPathComponent("voice_input.m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
        audioRecorder?.prepareToRecord()
        audioRecorder?.record()
    }

    func stopRecording() -> URL? {
        audioRecorder?.stop()
        return audioRecorder?.url
    }

    func playResponse(data: Data) throws {
        let playbackURL = FileManager.default.temporaryDirectory.appendingPathComponent("ai_response.mp3")
        try data.write(to: playbackURL)

        audioPlayer = try AVAudioPlayer(contentsOf: playbackURL)
        audioPlayer?.play()
    }
}
