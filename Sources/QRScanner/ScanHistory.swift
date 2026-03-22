import Foundation

struct ScanEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let content: String
    let timestamp: Date
    let source: Source

    enum Source: String, Codable {
        case camera
        case image
    }

    init(content: String, source: Source) {
        self.id = UUID()
        self.content = content
        self.timestamp = Date()
        self.source = source
    }
}

final class ScanHistory: ObservableObject {
    @Published var entries: [ScanEntry] = []

    private let maxEntries = 200
    private var saveURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = dir.appendingPathComponent("QRScanner", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("history.json")
    }

    init() {
        load()
    }

    func add(_ content: String, source: ScanEntry.Source) {
        // Deduplicate: if same content exists, move it to top with updated time
        if let idx = entries.firstIndex(where: { $0.content == content }) {
            entries.remove(at: idx)
        }
        entries.insert(ScanEntry(content: content, source: source), at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
    }

    func remove(_ entry: ScanEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clearAll() {
        entries.removeAll()
        save()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode([ScanEntry].self, from: data) else { return }
        entries = decoded
    }
}
