import Foundation

/// 保留策略执行器。
///
/// v1.6.9：三个策略（天档 / 时间机器式 / 达芬奇式）共用「收集 + 清 0 字节 + 删除未保留」公共辅助，
/// 消除重复代码；各策略语义不变。
enum RetentionManager {
    /// 递归收集目录内备份/快照文件（.backup 与 .zip），按修改时间倒序。
    static func backupFiles(in folder: URL,
                            extensions: [String] = BackupNaming.snapshotExtensions) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator {
            if extensions.contains(url.pathExtension.lowercased()) {
                result.append(url)
            }
        }
        return result.sorted { date(of: $0) > date(of: $1) }
    }

    static func date(of url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }

    // MARK: - 公共辅助（三个策略共用）

    /// 收集目录内备份文件，并始终清除 0 字节损坏/被中断残留（合法自定义格式备份必非空）。
    private static func cleanedFiles(in folder: URL) -> (files: [URL], deleted: [URL]) {
        var files = backupFiles(in: folder)
        let deleted: [URL] = files.filter { size(of: $0) == 0 }
        for f in deleted { try? FileManager.default.removeItem(at: f) }
        files = files.filter { size(of: $0) > 0 }
        return (files, deleted)
    }

    /// 删除不在 kept 集合中的文件，返回（保留、累计删除）。
    private static func deleteNotKept(_ files: [URL], kept: Set<URL>,
                                      deleted: [URL]) -> (kept: [URL], deleted: [URL]) {
        var deleted = deleted
        for f in files where !kept.contains(f) {
            if (try? FileManager.default.removeItem(at: f)) != nil { deleted.append(f) }
        }
        return (files.filter { kept.contains($0) }, deleted)
    }

    private static func size(of url: URL) -> Int {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return 0 }
        return (attrs[.size] as? NSNumber)?.intValue ?? 0
    }

    // MARK: - 策略 1：每库保留 N 份 + 天档

    /// 每库保留最近 `keepCount` 份（keepCount<=0 表示不启用）；
    /// 在此基础上天档策略（keepDays7/30/90，0=不启用）各保留落在该时间窗内的最新 N 份；
    /// 全部档位都为 0/不启用 → 不清理任何文件。
    @discardableResult
    static func apply(
        folder: URL,
        keepCount: Int,
        policy: RetentionPolicy,
        now: Date = Date()
    ) -> (kept: [URL], deleted: [URL]) {
        let (files, deleted) = cleanedFiles(in: folder)
        guard !files.isEmpty else { return ([], deleted) }

        let recentEnabled = keepCount > 0
        let tiersEnabled = policy.keepDays7 > 0 || policy.keepDays30 > 0 || policy.keepDays90 > 0
        guard recentEnabled || tiersEnabled else { return (files, deleted) }

        var kept = Set<URL>()
        if recentEnabled {
            for f in files.prefix(min(keepCount, files.count)) { kept.insert(f) }
        }
        let tiers: [(days: Int, count: Int)] = [
            (7, policy.keepDays7),
            (30, policy.keepDays30),
            (90, policy.keepDays90)
        ]
        for tier in tiers where tier.count > 0 {
            let cutoff = now.addingTimeInterval(-Double(tier.days) * 86400)
            var added = 0
            for f in files where date(of: f) >= cutoff && !kept.contains(f) && added < tier.count {
                kept.insert(f)
                added += 1
            }
        }
        return deleteNotKept(files, kept: kept, deleted: deleted)
    }

    // MARK: - 策略 2：时间机器式（当前使用，v1.7.5 三级）

    /// 三级保留：最近 24 小时内全部保留；超过 24 小时且在 30 天内按天分组，
    /// 每天只保留该天最后一份；超过 30 天按月分组，每月只保留该月最后一份。
    @discardableResult
    static func apply24hDaily(
        folder: URL,
        now: Date = Date()
    ) -> (kept: [URL], deleted: [URL]) {
        let (files, deleted) = cleanedFiles(in: folder)
        guard !files.isEmpty else { return ([], deleted) }

        let cutoff24h = now.addingTimeInterval(-86400)
        let cutoff30d = now.addingTimeInterval(-30 * 86400)
        let calendar = Calendar.current
        var kept = Set<URL>()

        // 1) 24 小时内：全留
        for f in files where date(of: f) >= cutoff24h { kept.insert(f) }

        // 2) 超过 24 小时且在 30 天内：按天分组，每天留该天最后一份
        var dayLast: [Date: URL] = [:]
        for f in files where date(of: f) < cutoff24h && date(of: f) >= cutoff30d {
            let day = calendar.startOfDay(for: date(of: f))
            if let existing = dayLast[day], date(of: f) <= date(of: existing) { continue }
            dayLast[day] = f
        }
        for f in dayLast.values { kept.insert(f) }

        // 3) 超过 30 天：按月分组，每月留该月最后一份
        var monthLast: [Date: URL] = [:]
        for f in files where date(of: f) < cutoff30d {
            let comps = calendar.dateComponents([.year, .month], from: date(of: f))
            guard let month = calendar.date(from: comps) else { continue }
            if let existing = monthLast[month], date(of: f) <= date(of: existing) { continue }
            monthLast[month] = f
        }
        for f in monthLast.values { kept.insert(f) }

        return deleteNotKept(files, kept: kept, deleted: deleted)
    }

    // MARK: - 策略 3：达芬奇式三层时间桶（历史方案，保留）

    /// 最近 `hourlyHours` 小时内的分钟级备份全部保留；`hourlyHours` 到 `dailyDays` 天之间
    /// 按小时分组，每小时只保留该小时最后一份；超过 `dailyDays` 天删除。
    @discardableResult
    static func applyDaVinci(
        folder: URL,
        hourlyHours: Int,
        dailyDays: Int,
        now: Date = Date()
    ) -> (kept: [URL], deleted: [URL]) {
        let (files, deleted) = cleanedFiles(in: folder)
        guard !files.isEmpty else { return ([], deleted) }

        let hourlyCutoff = now.addingTimeInterval(-TimeInterval(max(hourlyHours, 1)) * 3600)
        let dailyCutoff = now.addingTimeInterval(-TimeInterval(max(dailyDays, 1)) * 86400)
        let calendar = Calendar.current
        var kept = Set<URL>()

        // 1) 最近 hourlyHours 小时内：全部保留（分钟级）
        for f in files where date(of: f) >= hourlyCutoff { kept.insert(f) }

        // 2) hourlyHours 到 dailyDays 之间：按小时分组，每小时保留最后一份
        var hourLast: [Date: URL] = [:]
        for f in files where date(of: f) < hourlyCutoff && date(of: f) >= dailyCutoff {
            let hour = calendar.dateInterval(of: .hour, for: date(of: f))?.start
                ?? calendar.date(bySetting: .minute, value: 0, of: date(of: f))
            guard let hour else { continue }
            if let existing = hourLast[hour], date(of: f) <= date(of: existing) { continue }
            hourLast[hour] = f
        }
        for f in hourLast.values { kept.insert(f) }

        // 3) 超过 dailyDays：删除（不在 kept 中）
        return deleteNotKept(files, kept: kept, deleted: deleted)
    }

    /// 按月归档：把刚生成的备份移入 {folder}/YYYY-MM/。成功返回新路径，否则返回原路径。
    @discardableResult
    static func archiveIfNeeded(fileURL: URL, policy: RetentionPolicy) -> URL {
        guard policy.monthlyArchive else { return fileURL }
        let folder = fileURL.deletingLastPathComponent()
        let month = BackupNaming.monthFormatter.string(from: date(of: fileURL))
        let monthFolder = folder.appendingPathComponent(month, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: monthFolder, withIntermediateDirectories: true)
            let dest = monthFolder.appendingPathComponent(fileURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: fileURL, to: dest)
            return dest
        } catch {
            return fileURL
        }
    }
}
