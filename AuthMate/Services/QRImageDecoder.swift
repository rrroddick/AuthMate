import Foundation
import CoreImage
import ImageIO
import Vision

enum QRImageError: LocalizedError {
    case unreadableImage
    case noCodeFound

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return String(localized: "The selected file could not be read as an image.")
        case .noCodeFound:
            return String(localized: "No QR code was found in the image.")
        }
    }
}

/// Extracts QR payloads from a still image, so an account can be imported from a saved
/// screenshot or photo instead of holding the code up to the webcam.
enum QRImageDecoder {
    /// Every distinct QR payload in the file, in the order the detectors found them.
    /// - Throws: `QRImageError` when the file is not a readable image or holds no QR code.
    static func payloads(in url: URL) throws -> [String] {
        // A URL from the open panel or a drop carries a sandbox extension; the app is
        // sandboxed with only `files.user-selected.read-only`, so nothing else is readable.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw QRImageError.unreadableImage
        }
        return try payloads(in: image)
    }

    static func payloads(in image: CGImage) throws -> [String] {
        var found = visionPayloads(in: image)

        // CIDetector and Vision fail on different images — low-contrast or heavily scaled
        // screenshots in particular — so fall back rather than give up on one detector.
        if found.isEmpty {
            found = coreImagePayloads(in: image)
        }

        var seen = Set<String>()
        let unique = found.filter { seen.insert($0).inserted }
        guard !unique.isEmpty else { throw QRImageError.noCodeFound }
        return unique
    }

    private static func visionPayloads(in image: CGImage) -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            print("Vision error: \(error)")
            return []
        }
        return (request.results ?? []).compactMap { $0.payloadStringValue }
    }

    private static func coreImagePayloads(in image: CGImage) -> [String] {
        let detector = CIDetector(ofType: CIDetectorTypeQRCode,
                                  context: nil,
                                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let features = detector?.features(in: CIImage(cgImage: image)) as? [CIQRCodeFeature] ?? []
        return features.compactMap { $0.messageString }
    }
}
