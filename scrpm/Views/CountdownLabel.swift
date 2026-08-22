import SwiftUI

struct CountdownLabel: View {
    let remaining: TimeInterval
    let phase: TimerPhase

    var body: some View {
        Text(formattedTime)
            .font(.system(size: 72, weight: .medium, design: .monospaced))
            .foregroundStyle(foregroundColor)
            .monospacedDigit()
    }

    private var formattedTime: String {
        let total = max(0, Int(remaining))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private var foregroundColor: Color {
        switch phase {
        case .idle:       return .secondary
        case .working:    return Color("WorkingGray")
        case .shortBreak: return .blue
        case .longBreak:  return .teal
        }
    }
}
