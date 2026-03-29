import Vision
import AppKit

/// 从静态图片中检测 QR 码 / 条形码
enum ImageCodeDetector {

    /// 返回检测到的所有码值（去重）
    static func detectCodes(in image: NSImage) -> [String] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }

        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr, .ean8, .ean13, .code128, .code39, .upce, .aztec, .pdf417]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
            let codes = request.results?
                .compactMap { $0.payloadStringValue }
                .removingDuplicates() ?? []
            return codes
        } catch {
            return []
        }
    }
}

// MARK: - Array dedup helper

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
