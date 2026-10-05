import Foundation

struct ScreenshotConfiguration: Equatable, Sendable {
    let scopes: [URL]
    let includeAllMedia: Bool
    let recognizeText: Bool
    let recognitionMode: ScreenshotRecognitionMode
    let allowCloudFiles: Bool
    let retentionDays: Int
}
