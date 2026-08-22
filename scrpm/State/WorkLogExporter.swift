import Foundation
import SwiftData

/// 作業ログをテキストファイルとして書き出す。
///
/// SwiftData の SQLite（.store / -wal / -shm）を Google Drive 等のクラウド同期フォルダに
/// 置くと、同期クライアントが3ファイルを原子的に扱わないため DB が破損する。
/// 一方 CloudKit 同期はエンタイトルメントを要求し、フルスクリーンオーバーレイのために
/// App Sandbox を無効・アドホック署名にしている本アプリでは使えない。
///
/// そこで「DB が正本、テキストが派生物」とし、書き出したテキストだけをクラウドに載せる。
/// 別マシンからはファイルを読むだけで済み、DB を同期する必要がなくなる。
/// 書き出しは当日分を丸ごと書き直す方式なので冪等で、途中で落ちてもファイルは壊れない
enum WorkLogExporter {
    private static let directoryKey = "workLogExportDirectory"

    /// 書き出し先。未設定なら nil（書き出しを行わない）
    static var directoryURL: URL? {
        get {
            guard let path = UserDefaults.standard.string(forKey: directoryKey) else { return nil }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        set {
            UserDefaults.standard.set(newValue?.path, forKey: directoryKey)
        }
    }

    /// 指定日のログを書き出す。書き出し先が未設定なら何もしない。
    /// 書き込み失敗は無視する（scrpm 本体の動作に影響を与えないため）
    static func export(day: Date, context: ModelContext, calendar: Calendar = .current) {
        guard let directory = directoryURL else { return }
        guard let sessions = fetchSessions(on: day, context: context, calendar: calendar) else { return }

        let entries = sessions.map {
            WorkLogEntry(startTime: $0.startTime, endTime: $0.endTime, note: $0.note)
        }
        let total = sessions.reduce(0.0) { $0 + $1.duration }
        let document = WorkLog.document(entries: entries, on: day,
                                        totalDuration: total, calendar: calendar)

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(WorkLog.fileName(for: day, calendar: calendar))
        try? document.write(to: url, atomically: true, encoding: .utf8)
    }

    static func fetchSessions(on day: Date, context: ModelContext,
                              calendar: Calendar = .current) -> [WorkSession]? {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return nil }
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<WorkSession>(
            predicate: #Predicate { $0.startTime >= start && $0.startTime < end },
            sortBy: [SortDescriptor(\.startTime)]
        )
        return try? context.fetch(descriptor)
    }
}
