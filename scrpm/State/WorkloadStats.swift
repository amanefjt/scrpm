import Foundation

/// WorkSession から必要最小限を写した値型。
/// WorkloadStats を SwiftData 非依存（swiftc 単体でテスト可能）に保つためのもの
struct SessionRecord {
    let startTime: Date
    let duration: TimeInterval
}

/// 負荷集計の純関数群。日付・セッション列を引数に取り、状態を持たない
enum WorkloadStats {
    static func totalDuration(onDay day: Date, sessions: [SessionRecord], calendar: Calendar) -> TimeInterval {
        sessions
            .filter { calendar.isDate($0.startTime, inSameDayAs: day) }
            .reduce(0) { $0 + $1.duration }
    }

    /// 昨日までの noRestWarningDays 日間に「休養日」（日合計 < restDayThreshold）が
    /// 1 日もなければ true。今日を含めないのは、今日はまだ途中で朝は必ず休養日に
    /// 見えてしまい、警告が夕方まで出なくなるため
    static func hasNoRestDay(asOf now: Date, sessions: [SessionRecord], calendar: Calendar) -> Bool {
        for offset in 1...noRestWarningDays {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { return false }
            if totalDuration(onDay: day, sessions: sessions, calendar: calendar) < restDayThreshold {
                return false
            }
        }
        return true
    }

    /// date が属する週の週初（月曜）。WeekChartView の weekStart と同じ定義
    static func weekStart(for date: Date, calendar: Calendar) -> Date {
        var cal = calendar
        cal.firstWeekday = 2
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    /// 表示週の週初から遡る 4 週間（28 日）の週平均作業時間。
    /// 最古のセッションが窓の開始より新しい場合は比較に足るデータがないので nil
    static func previousFourWeekAverage(asOf date: Date, sessions: [SessionRecord], calendar: Calendar) -> TimeInterval? {
        let thisWeekStart = weekStart(for: date, calendar: calendar)
        guard let windowStart = calendar.date(byAdding: .day, value: -28, to: thisWeekStart),
              let earliest = sessions.map(\.startTime).min(),
              earliest <= windowStart else { return nil }
        let total = sessions
            .filter { $0.startTime >= windowStart && $0.startTime < thisWeekStart }
            .reduce(0) { $0 + $1.duration }
        return total / 4
    }
}
