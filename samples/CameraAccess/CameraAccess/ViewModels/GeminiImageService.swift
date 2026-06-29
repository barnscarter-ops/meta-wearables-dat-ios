import Foundation
import UIKit

enum GeminiError: LocalizedError {
    case invalidAPIKey
    case networkError(Error)
    case apiError(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "No valid Gemini API key found. Add your key to Secrets.plist under GEMINI_API_KEY."
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .apiError(let message):
            return message
        case .emptyResponse:
            return "Gemini returned an empty response."
        }
    }
}

// Singleton used by the live-streaming path (StreamSessionViewModel.askAI).
@MainActor
final class GeminiImageService {
    static let shared = GeminiImageService()

    private var apiKey: String?

    private init() {
        let key = GeminiImageService.loadKey()
        guard !key.isEmpty else {
            print("⚠️ GeminiImageService: API key not found or not set in Secrets.plist")
            return
        }
        apiKey = key
    }

    // nonisolated: reads only ProcessInfo/Bundle (no actor state), so it can be
    // called from nonisolated contexts like PhotoAnalysisServiceFactory.defaultAPIKey.
    nonisolated static func loadKey() -> String {
        if let env = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !env.isEmpty {
            return env
        }
        if let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path),
           let key = dict["GEMINI_API_KEY"] as? String,
           key != "PASTE_YOUR_GEMINI_KEY_HERE",
           !key.isEmpty {
            return key
        }
        return ""
    }

    func analyzeFrame(image: UIImage, prompt: String) async throws -> String {
        guard let key = apiKey else {
            throw GeminiError.invalidAPIKey
        }
        return try await GeminiVisionCaller(apiKey: key).analyze(image: image, prompt: prompt)
    }
}

// Conforms to PhotoAnalysisService for the captured-photo path.
struct GeminiPhotoAnalysisService: PhotoAnalysisService {
    var serviceName: String { "Gemini" }
    var supportsAPIKey: Bool { true }

    private let fallback = SamplePhotoAnalysisService()

    func analyze(photo: UIImage, prompt: String, apiKey: String?) async throws -> String {
        let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return try await fallback.analyze(photo: photo, prompt: prompt, apiKey: nil)
        }
        return try await GeminiVisionCaller(apiKey: trimmed).analyze(image: photo, prompt: prompt)
    }
}

// Low-level Gemini vision caller shared by both paths above.
struct GeminiVisionCaller {
    private let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")!
    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func analyze(image: UIImage, prompt: String) async throws -> String {
        guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
            throw GeminiError.apiError("Failed to encode image as JPEG.")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(
            GeminiRequest(
                contents: [
                    .init(parts: [
                        .init(text: prompt, inlineData: nil),
                        .init(text: nil, inlineData: .init(mimeType: "image/jpeg", data: jpegData.base64EncodedString())),
                    ])
                ],
                generationConfig: .init(maxOutputTokens: 350)
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw GeminiError.networkError(error)
        }

        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)

        if let message = decoded.error?.message {
            throw GeminiError.apiError(message)
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GeminiError.apiError("Gemini returned an unexpected HTTP status.")
        }

        let text = (decoded.candidates ?? [])
            .compactMap { $0.content?.parts.compactMap(\.text).joined() }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { throw GeminiError.emptyResponse }
        return text
    }
}

// MARK: - Codable types

private struct GeminiRequest: Encodable {
    let contents: [Content]
    let generationConfig: GenerationConfig

    struct Content: Encodable {
        let parts: [Part]
    }

    struct Part: Encodable {
        let text: String?
        let inlineData: InlineData?

        enum CodingKeys: String, CodingKey {
            case text
            case inlineData = "inline_data"
        }
    }

    struct InlineData: Encodable {
        let mimeType: String
        let data: String

        enum CodingKeys: String, CodingKey {
            case mimeType = "mime_type"
            case data
        }
    }

    struct GenerationConfig: Encodable {
        let maxOutputTokens: Int

        enum CodingKeys: String, CodingKey {
            case maxOutputTokens = "max_output_tokens"
        }
    }
}

private struct GeminiResponse: Decodable {
    let candidates: [Candidate]?
    let error: APIError?

    struct Candidate: Decodable {
        let content: Content?
    }

    struct Content: Decodable {
        let parts: [Part]
    }

    struct Part: Decodable {
        let text: String?
    }

    struct APIError: Decodable {
        let message: String
    }
}
