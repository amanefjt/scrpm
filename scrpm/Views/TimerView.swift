import SwiftUI

struct TimerView: View {
    @Environment(TimerStateManager.self) var timerManager
    let onShowHistory: () -> Void
    let onShowSettings: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            CountdownLabel(remaining: timerManager.remaining, phase: timerManager.phase)

            TodayTotalLabel(total: timerManager.todayTotalDuration)

            switch timerManager.phase {
            case .idle:
                VStack(spacing: 12) {
                    Button("作業開始") {
                        timerManager.startWork()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.return, modifiers: [])

                    Button("記録") {
                        onShowHistory()
                    }
                    .buttonStyle(.bordered)

                    Button("設定") {
                        onShowSettings()
                    }
                    .buttonStyle(.bordered)

                    RestWarningBanner()
                }
            case .working:
                VStack(spacing: 12) {
                    SetProgressIndicator(completedSets: timerManager.completedSets)

                    Button("作業をやめる") {
                        timerManager.stopWork()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    // 作業中でも記録は見られるようにする（進行中のこのセットはまだ
                    // 記録されていないので、当然ながら一覧には含まれない）
                    Button("記録を見る") {
                        onShowHistory()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            case .shortBreak, .longBreak:
                VStack(spacing: 16) {
                    SetProgressIndicator(completedSets: timerManager.completedSets)

                    if let session = timerManager.noteTarget {
                        SessionNoteField(session: session)
                    }

                    // オーバーレイ裏での抜け道を防ぐため、表示条件はオーバーレイと揃える
                    if timerManager.phase == .longBreak,
                       timerManager.remaining <= longBreakDuration - longBreakActionDelay {
                        VStack(spacing: 12) {
                            Button("作業を再開する") {
                                timerManager.resumeWork()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .tint(.orange)

                            Button("作業をやめる") {
                                timerManager.stopWork()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .padding(32)
        .frame(minWidth: 320, maxWidth: .infinity, minHeight: 260, maxHeight: .infinity)
    }
}
