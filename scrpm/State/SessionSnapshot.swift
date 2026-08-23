import Foundation

/// WorkSession の端末間同期用スナップショット。SwiftData 非依存（swiftc 単体でテスト可能）に
/// 保つための値型。`WorkLogEntry`（人間が読むテキスト用）とは別に、機械可読な JSON として
/// クラウド同期フォルダへ書き出す・読み込むために使う
struct SessionSnapshot: Codable, Equatable {
    let id: UUID
    let startTime: Date
    let endTime: Date
    let duration: TimeInterval
    let completed: Bool
    let note: String
}

/// 端末間同期のマージ計画・ファイル名整形。純関数のみで状態を持たない。
///
/// 同期は「DB が正本、JSON は派生物」という WorkLogExporter と同じ設計思想の上に、
/// 他マシンの JSON を読み込んで自分の DB へ取り込む処理を足したもの。
/// マージ方針は「note が空のときだけ埋める」に統一している。理由は、記録画面
/// （DaySummaryView）でどのセッションの note でもその場で書き足せる作りになっており、
/// 「他マシンの最新版で全フィールド上書き」だと、片方のマシンで書いた note が
/// 別マシンの古いスナップショットで消える事故が起こりうるため。
/// startTime/endTime/duration/completed はそもそもユーザーが編集できない値なので、
/// 上書き判定の対象は実質 note だけでよい
enum SessionSync {
    /// インポートで実際に適用すべき変更点。
    /// - toInsert: ローカルにまだ無いセッション（そのまま insert する）
    /// - notesToFill: ローカルに存在し、ローカルの note が空・インポート側が非空のもの
    ///   （id をキーに、埋めるべき note の値を持つ）
    struct ImportPlan: Equatable {
        let toInsert: [SessionSnapshot]
        let notesToFill: [UUID: String]
    }

    /// ローカルの全セッションと、他マシンから読み込んだセッション列から、
    /// 適用すべき差分だけを計算する（実際の適用はSwiftData側で行う）
    static func planImport(local: [SessionSnapshot], imported: [SessionSnapshot]) -> ImportPlan {
        let localByID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        var toInsert: [SessionSnapshot] = []
        var notesToFill: [UUID: String] = [:]

        for remote in imported {
            guard let existing = localByID[remote.id] else {
                toInsert.append(remote)
                continue
            }
            let localNote = existing.note.trimmingCharacters(in: .whitespacesAndNewlines)
            let remoteNote = remote.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if localNote.isEmpty && !remoteNote.isEmpty {
                notesToFill[remote.id] = remote.note
            }
        }

        return ImportPlan(toInsert: toInsert, notesToFill: notesToFill)
    }

    /// 同期ファイル名。表示名だけだと2台のマシンで同じ名前を設定した場合に衝突するため、
    /// 初回起動時に生成して固定する非表示のインスタンスIDをサフィックスに使う
    static func sanitizedFileName(deviceLabel: String, instanceID: UUID) -> String {
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "ぁ-んァ-ヶ一-龠々ー"))
        let trimmed = deviceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.unicodeScalars
            .map { allowed.contains($0) ? String($0) : "-" }
            .joined()
        let label = cleaned.isEmpty ? "device" : cleaned
        let suffix = instanceID.uuidString.prefix(6).lowercased()
        return "\(label)-\(suffix).json"
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func encode(_ snapshots: [SessionSnapshot]) throws -> Data {
        try encoder.encode(snapshots)
    }

    static func decode(_ data: Data) throws -> [SessionSnapshot] {
        try decoder.decode([SessionSnapshot].self, from: data)
    }
}
