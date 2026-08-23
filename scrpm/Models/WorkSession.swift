import SwiftData
import Foundation

@Model
final class WorkSession {
    /// 端末間同期での一意識別子。
    /// 注意: `= UUID()` というデフォルト値は SwiftData の軽量マイグレーションでは
    /// 移行時に1回だけ評価される可能性があり、既存レコード全件が同じ UUID になりうる
    /// （CoreData/SwiftData のよく知られた落とし穴）。このフィールドを初めて追加した
    /// 起動時に `ScrpmApp` が既存レコード全件の id を無条件で振り直すため、
    /// ここでのデフォルト値は「マイグレーション直後の一時的な値」でしかない
    var id: UUID = UUID()
    var startTime: Date
    var endTime: Date
    var duration: TimeInterval
    var completed: Bool
    /// そのセッションで何をやったか。休憩中に入力する。未入力のままでもよい。
    /// デフォルト値を持つため SwiftData の軽量マイグレーションで既存レコードは空文字になる
    var note: String = ""

    init(id: UUID = UUID(), startTime: Date, endTime: Date, duration: TimeInterval,
         completed: Bool, note: String = "") {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.completed = completed
        self.note = note
    }
}
