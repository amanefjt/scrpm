import Foundation

/// 作業ログ1行分。WorkSession から必要最小限を写した値型。
/// WorkLog を SwiftData 非依存（swiftc 単体でテスト可能）に保つためのもの
struct WorkLogEntry {
    let startTime: Date
    let endTime: Date
    let note: String
}

/// 作業ログのテキスト整形。純関数のみで状態を持たない。
///
/// このテキストがクラウド同期の実体になる。SwiftData の SQLite（.store / -wal / -shm の
/// 3ファイル）を Google Drive 等に置くと、同期クライアントが3ファイルを原子的に扱わないため
/// DB が破損する。DB を正本、テキストを派生物として書き出すことで、別マシンからは
/// 「ファイルを読むだけ」で済ませる
enum WorkLog {
    /// "12:12-12:27 読み方第1章を読む" 形式の行。作業内容が空なら時刻だけの行になる
    static func line(for entry: WorkLogEntry, calendar: Calendar) -> String {
        let start = hhmm(entry.startTime, calendar: calendar)
        let end = hhmm(entry.endTime, calendar: calendar)
        let note = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return note.isEmpty ? "\(start)-\(end)" : "\(start)-\(end) \(note)"
    }

    /// 指定日のセッションを開始時刻順に並べた行の集まり。そのままコピペできる素のテキスト
    static func body(entries: [WorkLogEntry], on day: Date, calendar: Calendar) -> String {
        entries
            .filter { calendar.isDate($0.startTime, inSameDayAs: day) }
            .sorted { $0.startTime < $1.startTime }
            .map { line(for: $0, calendar: calendar) }
            .joined(separator: "\n")
    }

    /// ファイルに書き出す形式。見出しと合計時間を付ける。
    /// 記録のたびに当日分を丸ごと書き直す（冪等なので途中で落ちても壊れない）
    static func document(entries: [WorkLogEntry], on day: Date,
                         totalDuration: TimeInterval, calendar: Calendar) -> String {
        var text = "# \(dateString(day, calendar: calendar))\n\n"
        let lines = body(entries: entries, on: day, calendar: calendar)
        if !lines.isEmpty {
            text += lines + "\n"
        }
        text += "\n合計 \(hhmmDuration(totalDuration))\n"
        return text
    }

    /// 日付ごとのファイル名。日付単位で分けることで、別マシンが同じ日に書いても
    /// 上書きが起きるのは「その日そのマシンで作業した分」に閉じる
    static func fileName(for day: Date, calendar: Calendar) -> String {
        "\(dateString(day, calendar: calendar)).md"
    }

    // MARK: - 整形ヘルパ

    private static func hhmm(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private static func dateString(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func hhmmDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 3600, (total % 3600) / 60)
    }
}
