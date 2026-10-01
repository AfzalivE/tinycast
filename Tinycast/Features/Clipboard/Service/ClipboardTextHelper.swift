import Foundation

@main
nonisolated enum ClipboardTextHelper {
    static func main() async {
        guard CommandLine.arguments.count == 4,
            ["image", "pdf"].contains(CommandLine.arguments[1]),
            ["accurate", "fast"].contains(CommandLine.arguments[3])
        else { exit(2) }
        do {
            let text = try await ClipboardTextExtractor.extract(
                at: URL(fileURLWithPath: CommandLine.arguments[2]),
                isPDF: CommandLine.arguments[1] == "pdf", accurate: CommandLine.arguments[3] == "accurate")
            try FileHandle.standardOutput.write(contentsOf: Data(text.utf8))
        } catch {
            exit(1)
        }
    }
}
