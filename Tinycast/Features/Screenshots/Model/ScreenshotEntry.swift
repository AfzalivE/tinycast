import Foundation

struct ScreenshotEntry: Identifiable, Hashable, Sendable {
    let url: URL
    let createdAt: Date
    let modifiedAt: Date
    let byteCount: Int
    let isVideo: Bool
    let isScreenshot: Bool
    let isCloudOnly: Bool

    var id: String { url.path }
    var name: String { url.lastPathComponent }

    static func isCapture(name: String, markedBySystem: Bool) -> Bool {
        if markedBySystem { return true }
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return ["screenshot", "screen shot", "screen recording", "snapzy_", "cleanshot"].contains {
            folded.hasPrefix($0)
        }
    }

    func expires(retentionDays: Int, pinned: Set<String>, now: Date) -> Bool {
        retentionDays > 0 && createdAt != .distantPast && isScreenshot && !isCloudOnly && !pinned.contains(id)
            && createdAt < now.addingTimeInterval(-Double(retentionDays) * 86_400)
    }
}
