import CoreGraphics
import Foundation
import Vision

/// Reads the text out of schedule screenshots, on the phone (Apple's Vision text recognition, no internet).
enum ScreenshotReader {
    /// Lines of text, top to bottom.
    static func text(from image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            // Keep names and times exactly as printed ("TA- MARTIN LAWRENCE", "4:30pm").
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            let observations = request.results ?? []
            return observations
                .sorted { $0.boundingBox.midY > $1.boundingBox.midY } // Vision's y goes up, so this is top to bottom
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }.value
    }
}
