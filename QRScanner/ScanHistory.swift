import Foundation
import Combine
import OSLog

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
    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "QRScanner", category: "ScanHistory")
    private var saveURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = dir.appendingPathComponent("QRScanner", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("history.json")
    }

    init(settings: AppSettings) {
        self.settings = settings
        if settings.historyEnabled {
            load()
        }

        settings.$historyEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.load()
                } else {
                    self.entries.removeAll()
                    self.deletePersistedHistory()
                }
            }
            .store(in: &cancellables)
    }

    func add(_ content: String, source: ScanEntry.Source) {
        guard settings.historyEnabled else { return }
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
        guard settings.historyEnabled else { return }
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: saveURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            logger.error("Failed to save scan history: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func load() {
        guard settings.historyEnabled else { return }
        do {
            let data = try Data(contentsOf: saveURL)
            entries = try JSONDecoder().decode([ScanEntry].self, from: data)
        } catch CocoaError.fileNoSuchFile {
            entries = []
        } catch {
            logger.error("Failed to load scan history: \(error.localizedDescription, privacy: .public)")
            entries = []
        }
    }

    private func deletePersistedHistory() {
        do {
            try FileManager.default.removeItem(at: saveURL)
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            logger.error("Failed to delete scan history: \(error.localizedDescription, privacy: .public)")
        }
    }
}
