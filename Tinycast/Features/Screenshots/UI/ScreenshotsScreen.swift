import SwiftUI

struct ScreenshotsScreen: PaletteScreen {
    let coordinator: ScreenshotsCoordinator
    let openActions: () -> Void

    var rows: [ScreenshotEntry] { coordinator.rows }
    var primaryActionTitle: String { "Copy to Clipboard" }

    func activate(at selection: Int) {
        guard let entry = entry(at: selection) else { return }
        coordinator.copy(entry)
    }

    func secondary(at selection: Int) -> Bool {
        guard let entry = entry(at: selection) else { return false }
        coordinator.copy(entry, paste: true)
        return true
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        guard let entry = entry(at: selection) else { return false }
        switch shortcut {
        case .pin: coordinator.togglePin(entry)
        case .delete, .commandDelete: coordinator.trash(entry)
        case .copyFile: coordinator.copy(entry)
        case .pasteFile: coordinator.copy(entry, paste: true)
        case .quickLook: coordinator.palette.isQuickLookPresented.toggle()
        default: return false
        }
        return true
    }

    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int? {
        let step = axis == .vertical ? coordinator.columns : 1
        return min(max(selection + delta * step, 0), max(rows.count - 1, 0))
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let entry = entry(at: selection) else { return nil }
        let pinned = coordinator.store.pinned.contains(entry.id)
        return PopoverMenuContent(header: entry.name, items: [
            .init(title: "Copy to Clipboard", systemImage: "doc.on.doc", shortcut: "↵") {
                coordinator.copy(entry)
            },
            .init(title: "Paste", systemImage: "doc.on.clipboard", shortcut: "⌘↵") {
                coordinator.copy(entry, paste: true)
            },
            .init(title: "Open", systemImage: "arrow.up.forward.app") { coordinator.open(entry) },
            .init(title: "Show in Finder", systemImage: "folder") { coordinator.reveal(entry) },
            .init(title: "Quick Look", systemImage: "eye", shortcut: "⌘Y") {
                coordinator.palette.isQuickLookPresented = true
            },
            .init(title: pinned ? "Unpin" : "Pin", systemImage: pinned ? "pin.slash" : "pin",
                  startsSection: true, shortcut: "⌘.") { coordinator.togglePin(entry) },
            .init(title: "Screenshot Settings…", systemImage: "gearshape", startsSection: true) {
                coordinator.showSettings()
            },
            .init(title: "Move to Trash", systemImage: "trash", startsSection: true,
                  shortcut: "⌃X", isDestructive: true) { coordinator.trash(entry) }
        ])
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        let entries = rows
        let palette = coordinator.palette
        return AnyView(ScreenshotsGrid(
            entries: entries, selection: selection, scroll: scroll, openActions: openActions)
            .overlay {
                if palette.isVisible, palette.isQuickLookPresented, entries.indices.contains(selection) {
                    let entry = entries[selection]
                    FileSearchQuickLook(url: entry.url, name: entry.name) { palette.isQuickLookPresented = false }
                }
            }
            .onChange(of: entries.isEmpty) {
                if entries.isEmpty { palette.isQuickLookPresented = false }
            })
    }

    private func entry(at selection: Int) -> ScreenshotEntry? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }
}
