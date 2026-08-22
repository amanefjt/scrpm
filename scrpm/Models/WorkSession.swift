import SwiftData
import Foundation

@Model
final class WorkSession {
    var startTime: Date
    var endTime: Date
    var duration: TimeInterval
    var completed: Bool
    /// そのセッションで何をやったか。休憩中に入力する。未入力のままでもよい。
    /// デフォルト値を持つため SwiftData の軽量マイグレーションで既存レコードは空文字になる
    var note: String = ""

    init(startTime: Date, endTime: Date, duration: TimeInterval, completed: Bool, note: String = "") {
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.completed = completed
        self.note = note
    }
}
