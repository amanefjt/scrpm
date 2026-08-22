import SwiftUI
import SwiftData
import AppKit

struct DaySummaryView: View {
    let date: Date
    @Query(sort: \WorkSession.startTime) private var allSessions: [WorkSession]
    @State private var copied = false

    private var sessions: [WorkSession] {
        let cal = Calendar.current
        return allSessions.filter { cal.isDate($0.startTime, inSameDayAs: date) }
    }

    private var logText: String {
        WorkLog.body(entries: sessions.map(\.logEntry), on: date, calendar: .current)
    }

    var body: some View {
        let totalSec = sessions.reduce(0.0) { $0 + $1.duration }
        let hours = Int(totalSec) / 3600
        let minutes = (Int(totalSec) % 3600) / 60
        let completedCount = sessions.filter { $0.completed }.count
        let interruptedCount = sessions.filter { !$0.completed }.count

        VStack(spacing: 16) {
            HStack(spacing: 40) {
                StatItem(label: "合計", value: String(format: "%02d:%02d", hours, minutes))
                StatItem(label: "完走", value: "\(completedCount)")
                StatItem(label: "中断", value: "\(interruptedCount)")
            }
            .padding(.top, 20)

            Divider()

            if sessions.isEmpty {
                Text("この日の記録はありません")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
            } else {
                HStack {
                    Text("作業ログ")
                        .font(.headline)
                    Spacer()
                    Button(copied ? "コピーしました" : "コピー") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(logText, forType: .string)
                        copied = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(logText.isEmpty)
                }
                .padding(.horizontal)

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(sessions) { session in
                            SessionLogRow(session: session)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }
            }
        }
        .onChange(of: date) { _, _ in copied = false }
    }
}

/// 1セッション分の行。作業内容はここで直接書き足せる
/// （休憩中に入力しそびれた分を、あとから記録画面で補えるようにするため）
private struct SessionLogRow: View {
    @Bindable var session: WorkSession

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(timeRange)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(session.completed ? .primary : .secondary)

            TextField("（未入力）", text: $session.note)
                .textFieldStyle(.plain)
                .font(.system(size: 13))

            if !session.completed {
                Text("中断")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var timeRange: String {
        let cal = Calendar.current
        func hhmm(_ d: Date) -> String {
            let c = cal.dateComponents([.hour, .minute], from: d)
            return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        }
        return "\(hhmm(session.startTime))-\(hhmm(session.endTime))"
    }
}

private struct StatItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 40, weight: .bold, design: .monospaced))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

extension WorkSession {
    var logEntry: WorkLogEntry {
        WorkLogEntry(startTime: startTime, endTime: endTime, note: note)
    }
}
