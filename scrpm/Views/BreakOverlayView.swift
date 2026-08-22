import SwiftUI

struct BreakOverlayView: View {
    @Environment(TimerStateManager.self) var timerManager

    var body: some View {
        ZStack {
            Color.clear
            VStack(spacing: 28) {
                Text(title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                CountdownLabel(remaining: timerManager.remaining, phase: timerManager.phase)

                VStack(spacing: 10) {
                    TodayTotalLabel(total: timerManager.todayTotalDuration)
                    SetProgressIndicator(completedSets: timerManager.completedSets)
                }

                if let session = timerManager.noteTarget {
                    SessionNoteField(session: session, isOverlay: true)
                }

                // 短い休憩にはボタンを一切出さない（スキップさせないため）。
                // 長い休憩は longBreakActionDelay 経過後にだけボタンを出す
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
                        .controlSize(.large)
                        .foregroundStyle(Color.white)
                    }
                }
            }
        }
        .colorScheme(.dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: String {
        switch timerManager.phase {
        case .longBreak: return "長い休憩"
        default:         return "短い休憩"
        }
    }
}
