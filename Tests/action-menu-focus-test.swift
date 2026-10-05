import AppKit
import SwiftUI

@MainActor @Observable
final class PaletteState {
    var menuQuery = ""
    var menuPresentationToken = UUID()
    var hoverHighlightArmed = false
}

struct PasteTarget { let iconPath: String? }

@MainActor
enum IconCache {
    static func cached(forFile: String) -> NSImage? { nil }
    static func loadAsync(forFile: String) async -> NSImage? { nil }
}

struct IconRequest: Hashable {
    let path: String
    init(_ path: String) { self.path = path }
}

enum SystemSymbolName {
    static func resolve(_ name: String) -> String { name }
}

enum ExtensionRuntime {
    static func jsonArray(from json: String) -> [Any] { [] }
}

extension EnvironmentValues {
    var isDarkAppearance: Bool { colorScheme == .dark }
}

enum ExtensionImage {
    static func resolve(_ value: RenderValue?, assetsPath: String?, isDark: Bool) -> Image? { nil }
}

struct ExtensionPickerRow: View {
    let title: String
    let detail: String?
    let icon: Image?
    let checked: Bool
    let selected: Bool
    let onActivate: () -> Void

    var body: some View { EmptyView() }
}

@main @MainActor
struct ActionMenuFocusTests {
    static func main() {
        _ = NSApplication.shared
        for isExtension in [false, true] {
            let state = PaletteState()
            let panel = NSPanel(
                contentRect: NSRect(x: 100, y: 100, width: 306, height: 200),
                styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
            let host = NSHostingView(rootView: menu(state, isExtension: isExtension))
            panel.contentView = host
            host.layoutSubtreeIfNeeded()
            panel.displayIfNeeded()
            settle()
            panel.makeKeyAndOrderFront(nil)
            settle()
            check(panel, "first presentation, extension: \(isExtension)")
            for index in 0..<10 {
                panel.makeFirstResponder(nil)
                panel.orderOut(nil)
                state.menuPresentationToken = UUID()
                state.menuQuery = ""
                host.rootView = menu(state, isExtension: isExtension)
                host.layoutSubtreeIfNeeded()
                panel.makeKeyAndOrderFront(nil)
                settle()
                check(panel, "reopened presentation \(index), extension: \(isExtension)")
                guard let editor = panel.firstResponder as? NSTextView else { exit(1) }
                editor.insertText("copy", replacementRange: NSRange(location: NSNotFound, length: 0))
                editor.setSelectedRange(NSRange(location: 1, length: 2))
                host.rootView = menu(state, isExtension: isExtension)
                settle()
                guard state.menuQuery == "copy", editor.selectedRange() == NSRange(location: 1, length: 2) else {
                    print("FAIL: menu update reset text or selection")
                    exit(1)
                }
            }
            panel.orderOut(nil)
        }
        print("PASS: 22 presentations focus search; 20 menu updates preserve editing")
    }

    static func menu(_ state: PaletteState, isExtension: Bool) -> AnyView {
        if isExtension {
            return AnyView(VStack {
                Button("First Action") {}
                ExtensionMenuSearchField(placeholder: "Search for actions…", height: 36, verticalOffset: -1)
            }.environment(state))
        }
        return AnyView(PopoverMenu(
            items: [.init(title: "First Action", systemImage: "doc.on.doc", action: {})],
            selection: .constant(0), onActivate: { _ in },
            search: .init(placeholder: "Search for actions…", placement: .bottom)
        ).environment(state))
    }

    static func settle() {
        let deadline = Date().addingTimeInterval(0.1)
        while Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    }

    static func check(_ panel: NSPanel, _ label: String) {
        guard let editor = panel.firstResponder as? NSTextView, editor.isFieldEditor else {
            print("FAIL: \(label): first responder is \(String(describing: panel.firstResponder))")
            exit(1)
        }
    }
}
