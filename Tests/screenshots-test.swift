import AppKit
import Foundation

@main @MainActor
struct ScreenshotsTests {
    static var failures = 0
    static var checks = 0

    static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { failures += 1; print("FAIL: \(message)") }
    }

    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_790_856_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let entry = ScreenshotEntry(
            url: URL(fileURLWithPath: "/fixtures/Screenshot Food Log.png"),
            createdAt: now, modifiedAt: now, byteCount: 10,
            isVideo: false, isScreenshot: true, isCloudOnly: false)
        func matches(_ query: String) -> Bool {
            ScreenshotQuery(query).matches(entry, text: "Breakfast Café 309 kcal", now: now, calendar: calendar)
        }
        expect(matches(""), "empty search shows all media")
        expect(matches("food"), "plain search finds names")
        expect(matches("breakfast"), "plain search finds recognized text")
        expect(matches("name:food text:cafe"), "field searches combine and fold accents")
        expect(matches("name:\"Food Log\" text:\"309 kcal\""), "quoted phrases are preserved")
        expect(!matches("name:Breakfast"), "name filter does not match recognized text")
        expect(!matches("text:Screenshot"), "text filter does not match filenames")
        expect(matches("date:today"), "today uses the injected clock")
        expect(!matches("date:yesterday"), "yesterday excludes today's image")
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        let stamp = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        expect(matches("date:\(stamp)"), "date filter accepts ISO dates")
        expect(matches("date:\(stamp.prefix(7))"), "date filter accepts months")
        expect(!matches("food missing"), "all terms must match")
        expect(ScreenshotEntry.isCapture(name: "Snapzy_2026.png", markedBySystem: false), "Snapzy names work")
        expect(ScreenshotEntry.isCapture(name: "Custom.png", markedBySystem: true), "metadata identifies renamed captures")
        expect(!ScreenshotEntry.isCapture(name: "holiday.png", markedBySystem: false), "ordinary media is excluded")
        expect(ScreenshotFilter.images.includes(entry, pinned: []), "images filter")
        expect(!ScreenshotFilter.movies.includes(entry, pinned: []), "movies filter")
        expect(!ScreenshotFilter.pinned.includes(entry, pinned: []), "unpinned entries stay out of pinned")
        expect(ScreenshotFilter.pinned.includes(entry, pinned: [entry.id]), "pinned filter")
        expect(!entry.expires(retentionDays: 0, pinned: [], now: now.addingTimeInterval(86_400 * 90)), "Never keeps originals")
        expect(entry.expires(retentionDays: 7, pinned: [], now: now.addingTimeInterval(86_400 * 8)), "old captures expire")
        expect(!entry.expires(retentionDays: 7, pinned: [entry.id], now: now.addingTimeInterval(86_400 * 8)), "pins never expire")
        expect(!entry.expires(retentionDays: 7, pinned: [], now: now.addingTimeInterval(86_400 * 7)), "cutoff is exclusive")
        let unknownDate = ScreenshotEntry(
            url: entry.url, createdAt: .distantPast, modifiedAt: .distantPast, byteCount: 10,
            isVideo: false, isScreenshot: true, isCloudOnly: false)
        expect(!unknownDate.expires(retentionDays: 7, pinned: [], now: now), "unknown dates never expire")
        let cloud = ScreenshotEntry(
            url: entry.url, createdAt: now, modifiedAt: now, byteCount: 10,
            isVideo: false, isScreenshot: true, isCloudOnly: true)
        expect(!cloud.expires(retentionDays: 7, pinned: [], now: now.addingTimeInterval(86_400 * 8)),
               "cloud-only originals never expire")
        try filesystem(now: now)
        print("\(checks) checks, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }

    static func filesystem(now: Date) throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appending(path: "screenshots-\(UUID().uuidString)")
        let nested = root.appending(path: "Nested")
        try manager.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let png = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
        let screenshot = root.appending(path: "Screenshot first.png")
        try png.write(to: screenshot)
        try png.write(to: nested.appending(path: "Snapzy_second.png"))
        try png.write(to: root.appending(path: "holiday.png"))
        try png.write(to: root.appending(path: ".Screenshot hidden.png"))
        try Data().write(to: root.appending(path: "recording.mov"))
        try manager.createSymbolicLink(at: root.appending(path: "Screenshot alias.png"), withDestinationURL: screenshot)
        func configuration(_ all: Bool, scopes: [URL]? = nil) -> ScreenshotConfiguration {
            .init(scopes: scopes ?? [root, nested], includeAllMedia: all, recognizeText: false,
                  recognitionMode: .fast, allowCloudFiles: false, retentionDays: 0)
        }
        let captures = try ScreenshotScanner.scan(configuration(false))
        expect(captures.entries.count == 2, "recursive scan deduplicates overlapping scopes and skips hidden files and symlinks")
        expect(captures.unavailableScopes.isEmpty, "readable scope has no failure")
        let all = try ScreenshotScanner.scan(configuration(true))
        expect(all.entries.count == 4, "include all media admits images and movies")
        expect(all.entries.filter(\.isVideo).count == 1, "movies are classified")
        expect(try ScreenshotScanner.scan(configuration(true, scopes: [])).entries.isEmpty, "empty scopes stay empty")
        let missing = try ScreenshotScanner.scan(configuration(true, scopes: [root.appending(path: "missing")]))
        expect(!missing.unavailableScopes.isEmpty, "missing scope is reported")
        let ordinary = all.entries.first { $0.name == "holiday.png" }!
        expect(!ordinary.expires(retentionDays: 1, pinned: [], now: now.addingTimeInterval(86_400 * 365)),
               "cleanup never removes ordinary media")
        let capture = captures.entries.first { $0.name == screenshot.lastPathComponent }!
        expect(!capture.isCloudOnly, "local files are resident")
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let data = try ScreenshotTransfer.read(capture)
        ScreenshotTransfer.write(data, entry: capture, to: board)
        expect(board.data(forType: .png) == png, "copy preserves original image bytes")
        expect(board.string(forType: .fileURL) != nil, "copy also supports file-taking apps")
        try manager.removeItem(at: screenshot)
        do {
            _ = try ScreenshotTransfer.read(capture)
            expect(false, "vanished file must fail")
        } catch { expect(true, "vanished file is reported") }
    }
}
