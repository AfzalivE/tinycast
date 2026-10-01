import SwiftUI

struct ScreenshotsGrid: View {
    let entries: [ScreenshotEntry]
    let selection: Int
    let scroll: ScrollIntent
    let openActions: () -> Void
    @Environment(ScreenshotsCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics

    private struct Row: Identifiable {
        let start: Int
        var id: String { String(start) }
    }

    private var columns: Int { coordinator.columns }
    private var rowStarts: [Row] { stride(from: 0, to: entries.count, by: columns).map { Row(start: $0) } }
    private var selectedRow: String { String(selection / columns * columns) }
    private var cellSize: CGFloat {
        (metrics.size.panelWidth - metrics.size.emojiGridInset * 2
            - metrics.spacing.md * CGFloat(columns - 1)) / CGFloat(columns)
    }

    var body: some View {
        if !coordinator.palette.isVisible {
            Color.clear
        } else if entries.isEmpty {
            EmptyResults(text: coordinator.store.isScanning ? "Finding screenshots…"
                : coordinator.store.problem ?? "No screenshots found. Add search folders in Screenshots settings.")
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: metrics.spacing.md) {
                    HStack(spacing: metrics.spacing.md) {
                        Text("Images & Movies")
                        Text(entries.count, format: .number).foregroundStyle(Theme.Colors.textTertiary)
                        Spacer()
                        if coordinator.store.isRecognizing { Text("Reading text…") }
                    }
                    .font(metrics.typography.sectionHeader)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    if let problem = coordinator.store.problem {
                        Text(problem).font(metrics.typography.sectionHeader)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    ForEach(rowStarts) { row in
                        let start = row.start
                        HStack(alignment: .top, spacing: metrics.spacing.md) {
                            ForEach(start..<min(start + columns, entries.count), id: \.self) { index in
                                ScreenshotTile(
                                    entry: entries[index], selected: index == selection,
                                    pinned: coordinator.store.pinned.contains(entries[index].id), size: cellSize,
                                    onSelect: { coordinator.palette.selection = index },
                                    onActivate: { coordinator.copy(entries[index]) },
                                    onActions: {
                                        coordinator.palette.selection = index
                                        openActions()
                                    })
                            }
                        }
                        .selectionFrame(row.id == selectedRow)
                    }
                }
                .padding(.horizontal, metrics.size.emojiGridInset)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(scroll, row: selectedRow, atOrigin: selectedRow == "0", proxy: proxy)
        }
    }
}

private struct ScreenshotTile: View {
    private struct ThumbnailRequest: Hashable {
        let entry: ScreenshotEntry
        let pixels: CGFloat
    }

    let entry: ScreenshotEntry
    let selected: Bool
    let pinned: Bool
    let size: CGFloat
    let onSelect: () -> Void
    let onActivate: () -> Void
    let onActions: () -> Void
    @Environment(\.metrics) private var metrics
    @Environment(\.displayScale) private var displayScale
    @State private var image: NSImage?
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                    .fill(hovered ? Theme.Colors.rowHover : Theme.Colors.cardFill)
                if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    SymbolImage(name: entry.isCloudOnly ? "icloud" : entry.isVideo ? "film" : "photo",
                                size: metrics.size.rowIcon)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.clear,
                                  lineWidth: metrics.spacing.xxs)
            }
            HStack(spacing: metrics.spacing.xs) {
                if pinned { SymbolImage(name: "pin.fill", size: metrics.size.keyCap) }
                if entry.isVideo { SymbolImage(name: "play.rectangle", size: metrics.size.keyCap) }
                Text(entry.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .lineLimit(1)
            }
            .font(metrics.typography.rowTrailing)
            .foregroundStyle(Theme.Colors.textPrimary)
        }
        .frame(width: size)
        .contentShape(.rect)
        .onTapGesture(perform: onSelect)
        .simultaneousGesture(TapGesture(count: 2).onEnded(onActivate))
        .onRightClick(perform: onActions)
        .armedHover($hovered)
        .tooltip(entry.name)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.name)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction(named: "Copy to Clipboard", onActivate)
        .accessibilityAction(named: "Actions", onActions)
        .onDisappear { image = nil }
        .task(id: ThumbnailRequest(entry: entry, pixels: size * displayScale)) {
            image = nil
            guard !entry.isCloudOnly else { return }
            let pixels = size * displayScale
            let loaded = entry.isVideo
                ? await FilePreviewThumbnail.loadAsync(entry.url, maxPixel: pixels)
                : await ImageThumbnail.loadAsync(entry.url, maxPixel: pixels)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}
