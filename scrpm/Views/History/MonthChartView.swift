import SwiftUI
import SwiftData
import Charts

struct MonthChartView: View {
    let date: Date
    @Query private var allSessions: [WorkSession]

    private var monthStart: Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date)
        return cal.date(from: comps)!
    }

    private var daysInMonth: Int {
        Calendar.current.range(of: .day, in: .month, for: date)!.count
    }

    private var dailyMinutes: [(day: Int, minutes: Double)] {
        let cal = Calendar.current
        return (0..<daysInMonth).map { offset in
            let day = cal.date(byAdding: .day, value: offset, to: monthStart)!
            let total = allSessions
                .filter { cal.isDate($0.startTime, inSameDayAs: day) }
                .reduce(0.0) { $0 + $1.duration }
            return (offset + 1, total / 60.0)
        }
    }

    private var totalMinutes: Double {
        dailyMinutes.reduce(0) { $0 + $1.minutes }
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("月合計: \(formattedTotal)")
                .font(.headline)
                .padding(.top, 8)

            Chart(dailyMinutes, id: \.day) { item in
                BarMark(
                    x: .value("日", "\(item.day)"),
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
}
