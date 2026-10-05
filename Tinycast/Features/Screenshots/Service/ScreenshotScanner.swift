import CoreServices
import Darwin
import Foundation
import UniformTypeIdentifiers

nonisolated enum ScreenshotScanner {
    struct Result: Sendable {
        var entries: [ScreenshotEntry] = []
        var unavailableScopes: [String] = []
    }

    static func scan(_ configuration: ScreenshotConfiguration) throws -> Result {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isSymbolicLinkKey, .creationDateKey, .contentModificationDateKey,
            .fileSizeKey, .contentTypeKey
        ]
        var result = Result()
        var seen = Set<String>()
        for scope in configuration.scopes {
            try Task.checkCancellation()
            var unavailable = false
            guard let enumerator = manager.enumerator(
                at: scope, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in unavailable = true; return true })
            else {
                result.unavailableScopes.append(scope.path)
                continue
            }
            for case let url as URL in enumerator {
                try Task.checkCancellation()
                guard seen.insert(url.standardizedFileURL.path).inserted,
                    let values = try? url.resourceValues(forKeys: keys),
                    values.isRegularFile == true, values.isSymbolicLink != true,
                    let type = values.contentType,
                    type.conforms(to: .image) || type.conforms(to: .movie)
                else { continue }
                let marked = MDItemCreate(nil, url.path as CFString).flatMap {
                    MDItemCopyAttribute($0, "kMDItemIsScreenCapture" as CFString) as? Bool
                } ?? false
                let capture = ScreenshotEntry.isCapture(name: url.lastPathComponent, markedBySystem: marked)
                guard configuration.includeAllMedia || capture else { continue }
                result.entries.append(ScreenshotEntry(
                    url: url, createdAt: values.creationDate ?? values.contentModificationDate ?? .distantPast,
                    modifiedAt: values.contentModificationDate ?? .distantPast,
                    byteCount: values.fileSize ?? 0, isVideo: type.conforms(to: .movie),
                    isScreenshot: capture, isCloudOnly: isCloudOnly(url)))
            }
            if unavailable { result.unavailableScopes.append(scope.path) }
        }
        result.entries.sort {
            $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt
        }
        return result
    }

    static func isCloudOnly(_ url: URL) -> Bool {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return true }
        return info.st_flags & UInt32(SF_DATALESS) != 0
    }

    static func defaultScopes(home: URL) -> [String] {
        let location = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
        return [location ?? home.appending(path: "Desktop").path]
    }
}
