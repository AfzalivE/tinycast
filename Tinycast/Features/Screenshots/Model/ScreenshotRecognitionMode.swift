import Foundation

enum ScreenshotRecognitionMode: String, CaseIterable, Identifiable, Sendable {
    case fast, accurate
    var id: Self { self }
    var title: String { self == .fast ? "Fast" : "Accurate" }
}
