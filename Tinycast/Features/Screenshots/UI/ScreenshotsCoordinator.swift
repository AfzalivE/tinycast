import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class ScreenshotsCoordinator {
    let store: ScreenshotStore
    let settings: AppSettings
    let palette: PaletteState
    var filter = ScreenshotFilter.all {
        didSet { palette.selection = 0; palette.resetToken = UUID() }
    }
    @ObservationIgnored private let windowController: PaletteWindowController
    @ObservationIgnored private unowned let core: AppCore
    @ObservationIgnored private var operation: Task<Void, Never>?

    init(store: ScreenshotStore, windowController: PaletteWindowController, core: AppCore) {
        self.store = store
        self.windowController = windowController
        self.core = core
        settings = core.settings
        palette = core.palette
    }

    var rows: [ScreenshotEntry] {
        store.results(query: palette.query, filter: filter, now: Date(), calendar: .current)
    }

    var columns: Int { min(6, max(3, settings.screenshotColumns)) }

    func applySettings() {
        core.appIndex.setCommandsVisible([.searchScreenshots, .pasteLastScreenshot], settings.screenshotsEnabled)
        store.apply(settings.screenshotsEnabled ? configuration : nil)
        if !settings.screenshotsEnabled {
            operation?.cancel()
            if palette.mode == .screenshots { palette.prepare(mode: .launcher) }
        }
    }

    func show() {
        guard settings.screenshotsEnabled else { return }
        filter = .all
        store.refresh()
        core.paletteCoordinator.togglePalette(mode: .screenshots)
    }

    func copy(_ entry: ScreenshotEntry, paste: Bool = false) {
        guard settings.screenshotsEnabled, operation == nil else { return }
        let target = previousApp
        operation = Task { [weak self] in
            guard let self else { return }
            defer { operation = nil }
            await transfer(entry, paste: paste, target: target)
        }
    }

    func pasteLastScreenshot() {
        guard settings.screenshotsEnabled, operation == nil else { return }
        let configuration = configuration
        let target = previousApp
        operation = Task { [weak self] in
            guard let self else { return }
            defer { operation = nil }
            do {
                let scan = Task.detached(priority: .userInitiated) { try ScreenshotScanner.scan(configuration) }
                let result = try await withTaskCancellationHandler {
                    try await scan.value
                } onCancel: { scan.cancel() }
                try Task.checkCancellation()
                guard let entry = result.entries.first(where: { $0.isScreenshot && !$0.isVideo }) else {
                    core.showMessage("No screenshots found", tone: .neutral)
                    return
                }
                await transfer(entry, paste: true, target: target)
            } catch is CancellationError {
                return
            } catch { core.showMessage(error.localizedDescription, tone: .danger) }
        }
    }

    func togglePin(_ entry: ScreenshotEntry) {
        store.togglePin(entry)
        palette.selection = rows.firstIndex(where: { $0.id == entry.id }) ?? 0
        palette.followToken = UUID()
    }

    func reveal(_ entry: ScreenshotEntry) {
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
    }

    func open(_ entry: ScreenshotEntry) {
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        guard NSWorkspace.shared.open(entry.url) else {
            core.showMessage("Could not open \(entry.name)", tone: .danger)
            return
        }
    }

    func trash(_ entry: ScreenshotEntry) {
        guard operation == nil else { return }
        operation = Task { [weak self] in
            guard let self else { return }
            defer { operation = nil }
            guard await core.confirm(
                title: "Move Screenshot to Trash?", message: entry.name,
                symbol: "trash", confirmTitle: "Move to Trash"), !Task.isCancelled else { return }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.trashItem(at: entry.url, resultingItemURL: nil)
                }.value
                store.remove(entry)
                palette.selection = min(palette.selection, max(0, rows.count - 1))
                core.showMessage("Moved to Trash")
            } catch { core.showMessage(error.localizedDescription, tone: .danger) }
        }
    }

    func setRetention(_ days: Int) {
        guard operation == nil else { return }
        operation = Task { [weak self] in
            guard let self else { return }
            defer { operation = nil }
            if days > 0 {
                guard await core.confirm(
                    title: "Automatically Trash Old Screenshots?",
                    message: "Original screenshots older than \(days) days in your search folders will move to Trash. "
                        + "Pinned files and other media are kept.",
                    symbol: "trash", confirmTitle: "Enable Cleanup") else { return }
            }
            guard !Task.isCancelled else { return }
            settings.screenshotRetentionDays = days
        }
    }

    func dragLanded() { core.paletteCoordinator.dragLanded() }

    func showSettings() { core.settingsCoordinator.showSettings(tab: .screenshots) }

    func stop() { operation?.cancel(); store.stop() }

    private var configuration: ScreenshotConfiguration {
        ScreenshotConfiguration(
            scopes: FileSearchScope.roots(
                for: settings.screenshotScopes, homeDirectory: FileManager.default.homeDirectoryForCurrentUser),
            includeAllMedia: settings.screenshotIncludeAllMedia,
            recognizeText: settings.screenshotRecognizeText, recognitionMode: settings.screenshotRecognitionMode,
            allowCloudFiles: settings.screenshotAllowCloudFiles, retentionDays: settings.screenshotRetentionDays)
    }

    private var previousApp: NSRunningApplication? {
        windowController.isVisible ? windowController.previousApp : NSWorkspace.shared.frontmostApplication
    }

    private func transfer(_ entry: ScreenshotEntry, paste: Bool, target: NSRunningApplication?) async {
        guard !paste || Permissions.ensureAccessibility() else { return }
        let changeCount = NSPasteboard.general.changeCount
        do {
            let data = try await Task.detached(priority: .userInitiated) {
                try ScreenshotTransfer.read(entry)
            }.value
            try Task.checkCancellation()
            guard NSPasteboard.general.changeCount == changeCount else {
                core.showMessage("Clipboard changed, screenshot not copied", tone: .neutral)
                return
            }
            ScreenshotTransfer.write(data, entry: entry, to: .general)
            guard paste else { core.showMessage("Copied to Clipboard"); return }
            core.paletteCoordinator.hidePalette(restoreFocus: false)
            target?.activate()
            try await Task.sleep(for: .milliseconds(80))
            Paster.postCommandV()
        } catch is CancellationError {
            return
        } catch { core.showMessage(error.localizedDescription, tone: .danger) }
    }
}
