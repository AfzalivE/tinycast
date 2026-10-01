import AppKit
import UniformTypeIdentifiers

nonisolated enum ScreenshotTransfer {
    enum Failure: LocalizedError {
        case tooLarge
        var errorDescription: String? { "This image is too large to copy. Use Open or Show in Finder." }
    }

    static func read(_ entry: ScreenshotEntry) throws -> Data? {
        let values = try entry.url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw CocoaError(.fileReadNoSuchFile) }
        guard !entry.isVideo else { return nil }
        let size = values.fileSize ?? 0
        guard size <= 64 * 1024 * 1024 else { throw Failure.tooLarge }
        return try Data(contentsOf: entry.url, options: .mappedIfSafe)
    }

    @MainActor
    static func write(_ data: Data?, entry: ScreenshotEntry, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.writeObjects([entry.url as NSURL])
        if let data, let type = UTType(filenameExtension: entry.url.pathExtension) {
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type.identifier))
        }
    }
}
