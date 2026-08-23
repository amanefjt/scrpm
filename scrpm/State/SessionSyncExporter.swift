import Foundation
import SwiftData

/// WorkSession を端末間で同期する。
///
/// WorkLogExporter が「DB を正本、Markdown テキストを派生物」として書き出すのに対し、
/// こちらは同じディレクトリ配下に機械可読な JSON を書き出し・読み込みすることで、
/// 他マシンの記録を自分の DB に取り込む（読み込みが加わる点だけが WorkLogExporter と違う）。
/// マージ方針・ファイル名の設計は SessionSnapshot / SessionSync を参照。
///
/// CloudKit のような真のリアルタイム同期はフルスクリーンオーバーレイのために
/// App Sandbox を無効にしている本アプリでは使えないため、「起動時・記録画面を開いたとき」に
/// 読み込む緩やかな同期に留めている
enum SessionSyncExporter {
    private static let deviceDisplayNameKey = "sessionSyncDeviceDisplayName"
    private static let deviceInstanceIDKey = "sessionSyncDeviceInstanceID"
    private static let lastImportedAtKey = "sessionSyncLastImportedAt"

    /// このMacの表示名（例:「研究室」「自宅」）。未設定なら同期機能そのものをオフとみなす
    static var deviceDisplayName: String? {
        get { UserDefaults.standard.string(forKey: deviceDisplayNameKey) }
        set { UserDefaults.standard.set(newValue, forKey: deviceDisplayNameKey) }
    }

    /// このインストールを識別する非表示のID。初回アクセス時に生成し、以後固定する。
    /// 表示名がマシン間で衝突してもファイル名が衝突しないようにするためのもの
    static var deviceInstanceID: UUID {
        let d = UserDefaults.standard
        if let existing = d.string(forKey: deviceInstanceIDKey), let uuid = UUID(uuidString: existing) {
            return uuid
        }
        let newID = UUID()
        d.set(newID.uuidString, forKey: deviceInstanceIDKey)
        return newID
    }

    /// 直近でインポートに成功した日時（UI表示用）
    static private(set) var lastImportedAt: Date? {
        get { UserDefaults.standard.object(forKey: lastImportedAtKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastImportedAtKey) }
    }

    /// 同期ファイルの置き場所。WorkLogExporter の書き出し先（Markdown用）と同じ
    /// クラウド同期フォルダの配下に、混在しないようサブディレクトリを切る
    private static var syncDirectory: URL? {
        guard let base = WorkLogExporter.directoryURL else { return nil }
        return base.appendingPathComponent("session-sync", isDirectory: true)
    }

    /// このマシンの全セッションを JSON として書き出す。書き出し先または表示名が
    /// 未設定なら何もしない。当日分だけでなく毎回全件を書き直す冪等な方式
    /// （WorkLogExporter と同じ思想。差分更新にすると途中失敗時の整合性が複雑になるため）。
    /// 書き込み失敗は無視する（scrpm 本体の動作に影響を与えないため）
    static func export(context: ModelContext) {
        guard let directory = syncDirectory, let displayName = deviceDisplayName else { return }
        guard let sessions = fetchAllSessions(context: context) else { return }

        let snapshots = sessions.map {
            SessionSnapshot(id: $0.id, startTime: $0.startTime, endTime: $0.endTime,
                            duration: $0.duration, completed: $0.completed, note: $0.note)
        }
        guard let data = try? SessionSync.encode(snapshots) else { return }

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = SessionSync.sanitizedFileName(deviceLabel: displayName, instanceID: deviceInstanceID)
        let url = directory.appendingPathComponent(fileName)
        try? data.write(to: url, options: .atomic)
    }

    /// 同期フォルダ内の「自分以外」の JSON を読み込み、ローカルの DB に取り込む。
    /// 壊れているファイル・クラウドのプレースホルダでまだ実体が無いファイル等は
    /// 読み込みに失敗するだけで、他のファイルの取り込みは継続する
    static func importAll(context: ModelContext) {
        guard let directory = syncDirectory else { return }
        let ownFileName = deviceDisplayName.map {
            SessionSync.sanitizedFileName(deviceLabel: $0, instanceID: deviceInstanceID)
        }

        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        let otherFiles = files.filter { $0.pathExtension == "json" && $0.lastPathComponent != ownFileName }
        guard !otherFiles.isEmpty else { return }

        var imported: [SessionSnapshot] = []
        for file in otherFiles {
            guard let data = try? Data(contentsOf: file),
                  let snapshots = try? SessionSync.decode(data) else { continue }
            imported.append(contentsOf: snapshots)
        }
        guard !imported.isEmpty else { return }

        guard let localSessions = fetchAllSessions(context: context) else { return }
        let local = localSessions.map {
            SessionSnapshot(id: $0.id, startTime: $0.startTime, endTime: $0.endTime,
                            duration: $0.duration, completed: $0.completed, note: $0.note)
        }
        let plan = SessionSync.planImport(local: local, imported: imported)
        guard !plan.toInsert.isEmpty || !plan.notesToFill.isEmpty else {
            lastImportedAt = Date()
            return
        }

        for snapshot in plan.toInsert {
            context.insert(WorkSession(
                id: snapshot.id, startTime: snapshot.startTime, endTime: snapshot.endTime,
                duration: snapshot.duration, completed: snapshot.completed, note: snapshot.note
            ))
        }
        if !plan.notesToFill.isEmpty {
            let localByID = Dictionary(localSessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for (id, note) in plan.notesToFill {
                localByID[id]?.note = note
            }
        }
        try? context.save()
        lastImportedAt = Date()
    }

    /// 「今すぐ同期」ボタン用。書き出し→読み込み→（読み込みで埋まった note を）
    /// 自分のファイルにも反映するため再度書き出す、という一往復
    static func syncNow(context: ModelContext) {
        export(context: context)
        importAll(context: context)
        export(context: context)
    }

    private static func fetchAllSessions(context: ModelContext) -> [WorkSession]? {
        let descriptor = FetchDescriptor<WorkSession>(sortBy: [SortDescriptor(\.startTime)])
        return try? context.fetch(descriptor)
    }
}
