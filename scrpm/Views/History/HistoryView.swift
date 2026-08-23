import SwiftUI
import SwiftData

enum HistoryTab: Hashable {
    case day, week, month
}

struct HistoryView: View {
    let onBack: () -> Void

    @Environment(\.modelContext) private var context
    @State private var selectedTab: HistoryTab = .day
    @State private var currentDate: Date = Date()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("← タイマーに戻る") { onBack() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.blue)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 8)

            RestWarningBanner()
                .padding(.horizontal)
                .padding(.bottom, 8)

            Picker("表示", selection: $selectedTab) {
                Text("日").tag(HistoryTab.day)
                Text("週").tag(HistoryTab.week)
                Text("月").tag(HistoryTab.month)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            HStack {
                Button {
                    navigate(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
                Text(navigationTitle)
                    .font(.headline)
                Spacer()
                Button {
                    navigate(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .disabled(isAtPresent)
            }
            .padding()

            Divider()

            switch selectedTab {
            case .day:
                DaySummaryView(date: currentDate)
                    .id(currentDate)
            case .week:
                WeekChartView(date: currentDate)
                    .id(currentDate)
            case .month:
                MonthChartView(date: currentDate)
                    .id(currentDate)
            }

            Spacer()
        }
        .frame(minWidth: 400, minHeight: 380)
        .onChange(of: selectedTab) { _, _ in
            currentDate = Date()
        }
        .onAppear {
            SessionSyncExporter.importAll(context: context)
        }
    }

    private var navigationTitle: String {
        let cal = Calendar.current
        switch selectedTab {
        case .day:
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            fmt.locale = Locale(identifier: "ja_JP")
            return fmt.string(from: currentDate)
        case .week:
            var c = cal
            c.firstWeekday = 2
            let start = c.dateInterval(of: .weekOfYear, for: currentDate)?.start ?? currentDate
            let end = cal.date(byAdding: .day, value: 6, to: start) ?? currentDate
            let fmt = DateFormatter()
            fmt.dateFormat = "MM/dd"
            return "\(fmt.string(from: start)) – \(fmt.string(from: end))"
        case .month:
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy年M月"
            fmt.locale = Locale(identifier: "ja_JP")
            return fmt.string(from: currentDate)
        }
    }

    private var isAtPresent: Bool {
        let cal = Calendar.current
        let today = Date()
        switch selectedTab {
        case .day:
            return cal.isDate(currentDate, inSameDayAs: today)
        case .week:
            var c = cal
            c.firstWeekday = 2
            let curStart = c.dateInterval(of: .weekOfYear, for: currentDate)?.start ?? currentDate
            let todStart = c.dateInterval(of: .weekOfYear, for: today)?.start ?? today
            return curStart >= todStart
        case .month:
            let curComps = cal.dateComponents([.year, .month], from: currentDate)
            let todComps = cal.dateComponents([.year, .month], from: today)
            let curDate = cal.date(from: curComps)!
            let todDate = cal.date(from: todComps)!
            return curDate >= todDate
        }
    }

    private func navigate(by delta: Int) {
        let cal = Calendar.current
        switch selectedTab {
        case .day:
            currentDate = cal.date(byAdding: .day, value: delta, to: currentDate) ?? currentDate
        case .week:
            currentDate = cal.date(byAdding: .weekOfYear, value: delta, to: currentDate) ?? currentDate
        case .month:
            currentDate = cal.date(byAdding: .month, value: delta, to: currentDate) ?? currentDate
        }
    }
}
