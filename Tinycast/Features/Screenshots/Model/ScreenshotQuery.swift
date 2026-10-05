import Foundation

struct ScreenshotQuery: Sendable {
    private struct Term: Sendable {
        let field: String
        let value: String
    }
    private let terms: [Term]
    var isEmpty: Bool { terms.isEmpty }

    init(_ text: String) {
        let pattern = #"(?:(name|text|date):)?(?:"([^"]*)"|(\S+))"#
        let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let source = text as NSString
        terms = expression?.matches(in: text, range: NSRange(location: 0, length: source.length)).map {
            let field = $0.range(at: 1)
            let quoted = $0.range(at: 2)
            return Term(
                field: field.location == NSNotFound ? "" : source.substring(with: field).lowercased(),
                value: source.substring(with: quoted.location == NSNotFound ? $0.range(at: 3) : quoted))
        } ?? []
    }

    func matches(_ entry: ScreenshotEntry, text: String, now: Date, calendar: Calendar) -> Bool {
        terms.allSatisfy { term in
            switch term.field {
            case "name": return nameMatches(term.value, entry.name)
            case "text": return text.localizedStandardContains(term.value)
            case "date": return dateMatches(term.value, entry.createdAt, now: now, calendar: calendar)
            default:
                return nameMatches(term.value, entry.name) || text.localizedStandardContains(term.value)
                    || dateMatches(term.value, entry.createdAt, now: now, calendar: calendar)
            }
        }
    }

    private func nameMatches(_ term: String, _ name: String) -> Bool {
        FuzzyMatch.match(query: term, candidate: name) != nil
    }

    private func dateMatches(_ term: String, _ date: Date, now: Date, calendar: Calendar) -> Bool {
        switch term.lowercased() {
        case "today": return calendar.isDate(date, inSameDayAs: now)
        case "yesterday":
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return false }
            return calendar.isDate(date, inSameDayAs: yesterday)
        default:
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            let stamp = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
            return !term.isEmpty && stamp.hasPrefix(term)
        }
    }
}
