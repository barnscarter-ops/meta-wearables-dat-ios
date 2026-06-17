import Foundation
import AVFoundation
import UIKit

enum GrizzlyEvent {
    case photo(UIImage, Date)
    case measurement(String, Date)
    case segmentMarker(String, Date)
}

struct GrizzlySegment {
    let id: UUID
    let name: String
    let startTime: Date
    var events: [GrizzlyEvent]
    var audioURL: URL?
}

@MainActor
final class GrizzlyCaptureManager {
    static let shared = GrizzlyCaptureManager()

    private var audioRecorder: AVAudioRecorder?
    private var currentSegment: GrizzlySegment
    private var segments: [GrizzlySegment] = []

    private init() {
        // Initialize with the first segment
        self.currentSegment = GrizzlySegment(
            id: UUID(),
            name: "Initial Section",
            startTime: Date(),
            events: [],
            audioURL: nil
        )
        segments.append(currentSegment)
    }

    func startRecording() throws {
        let fileName = "segment_\(currentSegment.id.uuidString).m4a"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.record()
        currentSegment.audioURL = url
    }

    func stopRecording() {
        audioRecorder?.stop()
    }

    func addPhoto(_ image: UIImage) {
        let event = GrizzlyEvent.photo(image, Date())
        currentSegment.events.append(event)
    }

    func addMeasurement(_ value: String) {
        let event = GrizzlyEvent.measurement(value, Date())
        currentSegment.events.append(event)
    }

    func startNewSegment(name: String) {
        // 1. Stop current audio
        stopRecording()

        // 2. Save current segment to history
        segments.append(currentSegment)

        // 3. Start new segment
        currentSegment = GrizzlySegment(
            id: UUID(),
            name: name,
            startTime: Date(),
            events: [],
            audioURL: nil
        )

        // 4. Start new audio recording
        try? startRecording()
    }

    func finalizeSession() -> [GrizzlySegment] {
        stopRecording()
        segments.append(currentSegment)
        return segments
    }

    func reset() {
        segments = []
        currentSegment = GrizzlySegment(
            id: UUID(),
            name: "Initial Section",
            startTime: Date(),
            events: [],
            audioURL: nil
        )
        segments.append(currentSegment)
    }
}
