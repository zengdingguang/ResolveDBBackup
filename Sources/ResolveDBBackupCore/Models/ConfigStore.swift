import Foundation

/// 配置与历史记录的持久化（JSON，位于 ~/Library/Application Support/ResolveDBBackup/）。
struct ConfigStore {
    var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("ResolveDBBackup", isDirectory: true)
    }
    var configURL: URL { directory.appendingPathComponent("config.json") }
    var historyURL: URL { directory.appendingPathComponent("history.json") }

    func loadConfig() -> AppConfig? {
        guard let data = try? Data(contentsOf: configURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AppConfig.self, from: data)
    }

    func configExists() -> Bool {
        FileManager.default.fileExists(atPath: configURL.path)
    }

    func saveConfig(_ config: AppConfig) throws {
        try atomicWrite(config, to: configURL)
    }

    func loadHistory() -> [BackupRecord] {
        guard let data = try? Data(contentsOf: historyURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([BackupRecord].self, from: data)) ?? []
    }

    func saveHistory(_ history: [BackupRecord]) throws {
        try atomicWrite(history, to: historyURL)
    }

    private func atomicWrite<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        let tmp = directory.appendingPathComponent(".\(url.lastPathComponent).tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }
}
