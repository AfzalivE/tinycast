import Foundation

@main @MainActor
struct ScreenshotIndexTests {
    static var failures = 0
    static var checks = 0

    static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { failures += 1; print("FAIL: \(message)") }
    }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "screenshot-index-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try index(root: root)
        try await lifecycle(root: root)
        print("\(checks) checks, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }

    static func index(root: URL) throws {
        let database = root.appending(path: "index.sqlite3")
        let now = Date()
        let entry = ScreenshotEntry(
            url: root.appending(path: "Screenshot 'receipt'.png"), createdAt: now,
            modifiedAt: now, byteCount: 128, isVideo: false, isScreenshot: true, isCloudOnly: false)
        try ScreenshotTextIndex.save("Invoice Alpha café 1234", entry: entry, mode: .fast, at: database)
        let stamps = try ScreenshotTextIndex.stamps(at: database)
        expect(stamps[entry.id] == .init(entry, mode: .fast), "fingerprint persists independently of text")
        func matches(_ query: String, mode: ScreenshotRecognitionMode = .fast) throws -> Set<String> {
            try ScreenshotTextIndex.matches(
                query: ScreenshotQuery(query), entries: [entry], mode: mode,
                now: now, calendar: .current, at: database)
        }
        expect(try matches("text:invoice") == [entry.id], "disk text is searchable")
        expect(try matches("name:receipt text:cafe") == [entry.id], "names and recognized phrases combine")
        expect(try matches("text:invoice", mode: .accurate).isEmpty, "a changed recognition mode invalidates old text")
        expect(try matches("text:\"' OR 1=1\"").isEmpty, "SQL-looking queries remain data")
        try ScreenshotTextIndex.save("Replacement beta", entry: entry, mode: .fast, at: database)
        expect(try matches("text:invoice").isEmpty, "replacement removes old text")
        expect(try matches("text:beta") == [entry.id], "replacement is searchable")
        let stale = ScreenshotEntry(
            url: entry.url, createdAt: now, modifiedAt: now.addingTimeInterval(1), byteCount: 256,
            isVideo: false, isScreenshot: true, isCloudOnly: false)
        expect(try ScreenshotTextIndex.matches(
            query: ScreenshotQuery("beta"), entries: [stale], mode: .fast,
            now: now, calendar: .current, at: database).isEmpty, "a changed image cannot match stale text")
        try ScreenshotTextIndex.remove([entry.id], at: database)
        expect(try ScreenshotTextIndex.stamps(at: database).isEmpty, "removed scope records are pruned")
    }

    static func lifecycle(root: URL) async throws {
        let scope = root.appending(path: "images")
        try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: true)
        let first = scope.appending(path: "Screenshot one.png")
        let second = scope.appending(path: "Screenshot two.png")
        try Data([1]).write(to: first)
        try Data([2]).write(to: second)
        let suite = "screenshots-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let cache = root.appending(path: "store.sqlite3")
        let probe = RecognitionProbe()
        let store = ScreenshotStore(defaults: defaults, cacheURL: cache) { url, mode in
            await probe.recognize(url, mode: mode)
        }
        defer { store.stop() }
        func configuration(_ text: Bool, mode: ScreenshotRecognitionMode = .fast) -> ScreenshotConfiguration {
            .init(scopes: [scope], includeAllMedia: false, recognizeText: text,
                  recognitionMode: mode, allowCloudFiles: false, retentionDays: 0)
        }
        func results(_ query: String, filter: ScreenshotFilter = .all) -> [ScreenshotEntry] {
            store.results(query: query, filter: filter, now: Date(), calendar: .current)
        }
        store.apply(configuration(false))
        try await waitUntil { store.entries.count == 2 && !store.isScanning }
        expect(probe.calls == 0, "OCR off performs no recognition")
        expect(!FileManager.default.fileExists(atPath: cache.path), "OCR off creates no index")
        expect(results("name:one").count == 1, "name search works with OCR off")
        let pin = store.entries.first { $0.name == first.lastPathComponent }!
        store.togglePin(pin)
        expect(results("").first?.id == pin.id, "pins lead the newest-first grid")
        expect(results("", filter: .pinned).map(\.id) == [pin.id], "pinned filtering")
        store.apply(configuration(true))
        try await waitUntil { results("text:receipt").count == 2 }
        expect(probe.calls == 2, "each image is recognized once")
        store.refresh()
        try await Task.sleep(for: .milliseconds(200))
        expect(probe.calls == 2, "a refresh reuses unchanged text")
        expect(results("text:absent").isEmpty, "a changed query discards previous text matches immediately")
        store.apply(configuration(false))
        expect(results("text:receipt").isEmpty, "switching OCR off hides recognized results immediately")
        store.apply(configuration(true, mode: .accurate))
        try await waitUntil { results("text:accurate").count == 2 }
        expect(probe.calls == 4, "changing recognition mode reprocesses images")
        store.apply(nil)
        expect(store.entries.isEmpty, "disabling clears visible data")
        let restored = ScreenshotStore(defaults: defaults, cacheURL: cache) { url, mode in
            await probe.recognize(url, mode: mode)
        }
        defer { restored.stop() }
        restored.apply(configuration(true, mode: .accurate))
        try await waitUntil {
            restored.results(query: "text:receipt", filter: .all, now: Date(), calendar: .current).count == 2
        }
        expect(restored.pinned.contains(pin.id), "pins survive reconstruction")
        expect(probe.calls == 4, "reconstruction reuses the disk index")
        restored.apply(nil)
        probe.delay = .milliseconds(300)
        store.apply(configuration(true, mode: .fast))
        try await waitUntil { probe.active > 0 }
        store.apply(nil)
        store.apply(configuration(true, mode: .accurate))
        try await waitUntil { !store.isScanning && store.entries.count == 2 && probe.active == 0 }
        expect(probe.maximumActive == 1, "cancellation and rapid reenable serialize recognition")
        try await waitUntil { results("text:accurate").count == 2 }
        expect(store.problem == nil, "cancellation is not reported as a failure")
    }

    static func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw CocoaError(.coderValueNotFound) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
private final class RecognitionProbe {
    var calls = 0
    var active = 0
    var maximumActive = 0
    var delay = Duration.milliseconds(10)

    func recognize(_ url: URL, mode: ScreenshotRecognitionMode) async -> String {
        calls += 1
        active += 1
        maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        try? await Task.sleep(for: delay)
        return "Receipt \(url.lastPathComponent) \(mode.rawValue)"
    }
}
