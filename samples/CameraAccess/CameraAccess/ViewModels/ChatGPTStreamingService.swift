import Foundation
import UIKit

enum ChatGPTError: Error {
    case invalidAPIKey
    case networkError(Error)
    case apiError(String)
    case decodingError
}

@MainActor
final class ChatGPTStreamingService {
    static let shared = ChatGPTStreamingService()

    private var apiKey: String?

    private init() {
        loadAPIKey()
    }

    private func loadAPIKey() {
        let environmentKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        let bundledKey: String?
        if let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) {
            bundledKey = dict["OPENAI_API_KEY"] as? String
        } else {
            bundledKey = nil
        }

        guard let key = (environmentKey ?? bundledKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty,
              key != "PASTE_YOUR_KEY_HERE",
              key != "PASTE_YOUR_OPENAI_KEY_HERE" else {
            print("⚠️ ChatGPTStreamingService: API Key not found or not set in Secrets.plist")
            return
        }
        self.apiKey = key
    }

    /// Sends a frame and a prompt to GPT-4o and returns the AI response.
    func analyzeFrame(image: UIImage, prompt: String) async throws -> String {
        guard let key = apiKey else {
            throw ChatGPTError.invalidAPIKey
        }

        // Convert image to base64 JPEG
        guard let imageData = image.jpegData(compressionQuality: 0.5) else {
            throw ChatGPTError.apiError("Failed to encode image")
        }
        let base64Image = imageData.base64EncodedString()

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]]
                    ]
                ]
            ],
            "max_tokens": 300
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown API error"
            throw ChatGPTError.apiError(errorMsg)
        }

        let decoded = try JSONDecoder().decode(ChatGPTResponse.self, from: data)
        return decoded.choices.first?.message.content ?? "No response from AI"
    }

    /// Sends a frame, an audio file, and a prompt to GPT-4o.
    /// Returns the AI's response as text and audio data.
    func analyzeVoiceAndFrame(image: UIImage, audioURL: URL, prompt: String) async throws -> (text: String, audio: Data) {
        guard let key = apiKey else {
            throw ChatGPTError.invalidAPIKey
        }

        // 1. Transcribe Audio using Whisper
        let transcription = try await transcribeAudio(url: audioURL)

        // 2. Get Response from GPT-4o
        let fullPrompt = "\(prompt)\n\nUser said: \(transcription)"
        let textResponse = try await analyzeFrame(image: image, prompt: fullPrompt)

        // 3. Convert Response to Speech using OpenAI TTS
        let audioData = try await synthesizeSpeech(text: textResponse)

        return (textResponse, audioData)
    }

    private func transcribeAudio(url: URL) async throws -> String {
        let endpoint = "https://api.openai.com/v1/audio/transcriptions"
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey ?? "")", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(try Data(contentsOf: url))
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-1\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body
        let (data, _) = try await URLSession.shared.data(for: request)
        let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return decoded.text
    }

    private func synthesizeSpeech(text: String) async throws -> Data {
        let endpoint = "https://api.openai.com/v1/audio/speech"
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey ?? "")", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": "tts-1",
            "input": text,
            "voice": "alloy"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }
}

struct TranscriptionResponse: Codable {
    let text: String
}

struct ChatGPTResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}
