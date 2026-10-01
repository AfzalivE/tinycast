import Foundation
import Observation
import OSLog

@MainActor @Observable
final class ScreenshotStore {
    typealias Recognize = @Sendable (URL, ScreenshotRecognitionMode) async throws -> String

    private struct SearchRequest: Equatable {
        let query: String
        let revision: Int
        let mode: ScreenshotRecognitionMode
        let day: Date
    }

    private(set) var entries: [ScreenshotEntry] = []
    private(set) var pinned: Set<String>
    private(set) var isScanning = false
    private(set) var isRecognizing = false
    private(set) var problem: String?
    private var configuration: ScreenshotConfiguration?
    private var revision = 0
    private var textMatches: Set<String> = []
    @ObservationIgnored private var request: SearchRequest?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let cacheURL: URL
    @ObservationIgnored private let recognize: Recognize
    @ObservationIgnored private var stamps: [String: ScreenshotTextIndex.Stamp]?
    @ObservationIgnored private var retryAfter: [String: Date] = [:]
    private static let pinsKey = "screenshotPinnedPaths"
    private static let logger = Logger(subsystem: "com.tinycast", category: "Screenshots")

    init(defaults: UserDefaults, cacheURL: URL, recognize: @escaping Recognize) {
        self.defaults = defaults
        self.cacheURL = cacheURL
        self.recognize = recognize
        pinned = Set(defaults.stringArray(forKey: Self.pinsKey) ?? [])
    }

    func apply(_ configuration: ScreenshotConfiguration?) {
        guard configuration != self.configuration else { return }
        self.configuration = configuration
        revision &+= 1
        retryAfter = [:]
        cancelSearch()
        refresh()
    }

    func refresh() {
        let previous = task
        previous?.cancel()
        guard let configuration else {
            entries = []
            stamps = nil
            isScanning = false
            isRecognizing = false
            return
        }
        isScanning = true
        task = Task { [weak self] in
            await previous?.value
            while !Task.isCancelled {
                guard let self else { return }
                await update(configuration)
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }

    func stop() {
        task?.cancel()
        cancelSearch()
    }

    func results(query raw: String, filter: ScreenshotFilter, now: Date, calendar: Calendar) -> [ScreenshotEntry] {
        let query = ScreenshotQuery(raw)
        if let configuration, configuration.recognizeText, !query.isEmpty {
            searchText(query, raw: raw, mode: configuration.recognitionMode, now: now, calendar: calendar)
        } else {
            cancelSearch()
        }
        return entries.filter {
            filter.includes($0, pinned: pinned)
                && (textMatches.contains($0.id) || query.matches($0, text: "", now: now, calendar: calendar))
        }.sorted {
            let left = pinned.contains($0.id)
            let right = pinned.contains($1.id)
            if left != right { return left }
            return $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt
        }
    }

    func togglePin(_ entry: ScreenshotEntry) {
        if !pinned.insert(entry.id).inserted { pinned.remove(entry.id) }
        defaults.set(pinned.sorted(), forKey: Self.pinsKey)
    }

    func remove(_ entry: ScreenshotEntry) {
        entries.removeAll { $0.id == entry.id }
        pinned.remove(entry.id)
        defaults.set(pinned.sorted(), forKey: Self.pinsKey)
        revision &+= 1
    }

    private func update(_ configuration: ScreenshotConfiguration) async {
        isScanning = true
        defer { isScanning = false; isRecognizing = false }
        do {
            let scan = Task.detached(priority: .utility) { try ScreenshotScanner.scan(configuration) }
            let result = try await withTaskCancellationHandler {
                try await scan.value
            } onCancel: { scan.cancel() }
            try Task.checkCancellation()
            if entries != result.entries { entries = result.entries; revision &+= 1 }
            problem = result.unavailableScopes.isEmpty ? nil
                : "Cannot read: " + result.unavailableScopes.joined(separator: ", ")
            isScanning = false
            try await prune(configuration)
            guard configuration.recognizeText else { stamps = nil; return }
            try await updateText(configuration)
        } catch is CancellationError {
            return
        } catch {
            problem = error.localizedDescription
            Self.logger.error("Screenshot indexing failed: \(error.localizedDescription)")
        }
    }

    private func updateText(_ configuration: ScreenshotConfiguration) async throws {
        let url = cacheURL
        if stamps == nil {
            let loaded = try await Task.detached(priority: .utility) { try ScreenshotTextIndex.stamps(at: url) }.value
            try Task.checkCancellation()
            stamps = loaded
            revision &+= 1
        }
        let removed = Set(stamps?.keys.map { $0 } ?? []).subtracting(entries.map(\.id))
        try await Task.detached(priority: .utility) { try ScreenshotTextIndex.remove(removed, at: url) }.value
        for id in removed { stamps?.removeValue(forKey: id); retryAfter.removeValue(forKey: id) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(25))
        for entry in entries where !entry.isVideo {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { break }
            let stamp = ScreenshotTextIndex.Stamp(entry, mode: configuration.recognitionMode)
            guard stamps?[entry.id] != stamp, (retryAfter[entry.id] ?? .distantPast) < Date() else { continue }
            let cloudOnly = await Task.detached(priority: .utility) { ScreenshotScanner.isCloudOnly(entry.url) }.value
            guard configuration.allowCloudFiles || !cloudOnly else { continue }
            isRecognizing = true
            do {
                let text = try await recognize(entry.url, configuration.recognitionMode)
                try Task.checkCancellation()
                try await Task.detached(priority: .utility) {
                    try ScreenshotTextIndex.save(text, entry: entry, mode: configuration.recognitionMode, at: url)
                }.value
                try Task.checkCancellation()
                stamps?[entry.id] = stamp
                revision &+= 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                retryAfter[entry.id] = Date().addingTimeInterval(300)
                problem = "Some images could not be read. Text recognition will retry."
                Self.logger.error("Text recognition failed: \(error.localizedDescription)")
            }
        }
    }

    private func searchText(
        _ query: ScreenshotQuery, raw: String, mode: ScreenshotRecognitionMode, now: Date, calendar: Calendar
    ) {
        let next = SearchRequest(query: raw, revision: revision, mode: mode, day: calendar.startOfDay(for: now))
        guard request != next else { return }
        cancelSearch()
        request = next
        let entries = entries
        let url = cacheURL
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(100))
                let search = Task.detached(priority: .userInitiated) {
                    try ScreenshotTextIndex.matches(
                        query: query, entries: entries, mode: mode, now: now, calendar: calendar, at: url)
                }
                let matches = try await withTaskCancellationHandler {
                    try await search.value
                } onCancel: { search.cancel() }
                try Task.checkCancellation()
                guard let self, request == next else { return }
                textMatches = matches
            } catch is CancellationError {
                return
            } catch {
                self?.problem = error.localizedDescription
            }
        }
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        request = nil
        if !textMatches.isEmpty { textMatches = [] }
    }

    private func prune(_ configuration: ScreenshotConfiguration) async throws {
        for entry in entries {
            try Task.checkCancellation()
            guard entry.expires(retentionDays: configuration.retentionDays, pinned: pinned, now: Date())
            else { continue }
            do {
                let trashed = try await Task.detached(priority: .utility) {
                    let current = try entry.url.resourceValues(forKeys: [
                        .contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey
                    ])
                    guard current.contentModificationDate == entry.modifiedAt, current.fileSize == entry.byteCount,
                        current.isRegularFile == true, current.isSymbolicLink != true,
                        !ScreenshotScanner.isCloudOnly(entry.url)
                    else { return false }
                    try FileManager.default.trashItem(at: entry.url, resultingItemURL: nil)
                    return true
                }.value
                if trashed { remove(entry) }
            } catch {
                problem = "Could not move \(entry.name) to Trash: \(error.localizedDescription)"
                Self.logger.error("Screenshot cleanup failed: \(error.localizedDescription)")
            }
        }
    }
}
