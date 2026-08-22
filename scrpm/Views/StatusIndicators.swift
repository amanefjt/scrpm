import SwiftUI

/// 今日の記録済み作業時間の合計。作業中も休憩中も常に見せる。
///
/// 値は `TimerStateManager.todayTotalDuration` から取る（@Query を使わないのは、
/// 休憩オーバーレイが modelContainer の無い NSHostingView 直下で描画されるため）
struct TodayTotalLabel: View {
    let total: TimeInterval

    var body: some View {
        HStack(spacing: 6) {
            Text("今日の作業")
            Text(formatted)
                .monospacedDigit()
                .fontWeight(.medium)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var formatted: String {
        let seconds = max(0, Int(total))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours)時間\(minutes)分" : "\(minutes)分"
    }
}

/// このサイクルで何セット終えたかを点で示す（setsPerCycle 個中いくつ塗るか）。
/// 文字は添えない（点だけの方が休憩中の視覚的な静けさを保てる）
struct SetProgressIndicator: View {
    let completedSets: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<setsPerCycle, id: \.self) { index in
                Circle()
                    .fill(index < completedSets ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 9, height: 9)
            }
        }
    }
}
