import Foundation

enum ScreenshotFilter: String, CaseIterable, Identifiable, Sendable {
    case all, images, movies, pinned
    var id: Self { self }
    var title: String {
        switch self {
        case .all: "All"
        case .images: "Images"
        case .movies: "Movies"
        case .pinned: "Pinned"
        }
    }

    func includes(_ entry: ScreenshotEntry, pinned: Set<String>) -> Bool {
        switch self {
        case .all: true
        case .images: !entry.isVideo
        case .movies: entry.isVideo
        case .pinned: pinned.contains(entry.id)
        }
    }
}
