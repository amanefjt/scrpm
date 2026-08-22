import SwiftUI
import SwiftData
import Charts

struct WeekChartView: View {
    let date: Date
    @Query private var allSessions: [WorkSession]

    private var weekStart: Date {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    private var dailyMinutes: [(label: String, day: Date, minutes: Double)] {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "E"
        fmt.locale = Locale(identifier: "ja_JP")
        return (0..<7).map { offset in
            let day = cal.date(byAdding: .day, value: offset, to: weekStart)!
            let total = allSessions
                .filter { cal.isDate($0.startTime, inSameDayAs: day) }
                .reduce(0.0) { $0 + $1.duration }
            return (fmt.string(from: day), day, total / 60.0)
        }
    }

    private var totalMinutes: Double {
        dailyMinutes.reduce(0) { $0 + $1.minutes }
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("週合計: \(formattedTotal)")
                .font(.headline)
                .padding(.top, 8)

            Text("過去4週平均: \(formattedFourWeekAverage)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Chart(dailyMinutes, id: \.label) { item in
                BarMark(
                    x: .value("曜日", item.label),
                    y: .value("分", item.minutes)
                )
                .foregroundStyle(.orange)
            }
            .frame(height: 180)
            .padding(.horizontal)
        }
    }

    private var formattedTotal: String {
        let h = Int(totalMinutes) / 60
        let m = Int(totalMinutes) % 60
        return String(format: "%02d:%02d", h, m)
    }

    private var formattedFourWeekAverage: String {
        let records = allSessions.map { SessionRecord(startTime: $0.startTime, duration: $0.duration) }
        guard let avg = WorkloadStats.previousFourWeekAverage(asOf: date, sessions: records, calendar: .current) else {
            return "—（データ4週間未満）"
        }
        let totalMin = Int(avg / 60)
        return String(format: "%02d:%02d", totalMin / 60, totalMin % 60)
    }
}
