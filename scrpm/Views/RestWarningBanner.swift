import SwiftUI
import SwiftData

/// 昨日までの noRestWarningDays 日間に休養日がない場合に表示する警告バナー。
/// 条件を満たさないときは何も描画しない
struct RestWarningBanner: View {
    @Query private var allSessions: [WorkSession]

    private var shouldWarn: Bool {
        let records = allSessions.map { SessionRecord(startTime: $0.startTime, duration: $0.duration) }
        return WorkloadStats.hasNoRestDay(asOf: Date(), sessions: records, calendar: .current)
    }

    var body: some View {
        if shouldWarn {
            Label(
                "\(noRestWarningDays)日間休みなく作業しています。休養日を取ることを検討してください",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.callout)
            .foregroundStyle(.orange)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
