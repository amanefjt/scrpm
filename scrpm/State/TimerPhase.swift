import Foundation

enum TimerPhase {
    case idle
    case working
    /// 1セット終了後の短い休憩。スキップできない（ボタンを一切出さない）
    case shortBreak
    /// setsPerCycle セット終了後の長い休憩。何をしてもよい時間
    case longBreak

    var isBreak: Bool {
        self == .shortBreak || self == .longBreak
    }

    /// そのフェーズが満了するまでの長さ
    var duration: TimeInterval {
        switch self {
        case .idle, .working: return workDuration
        case .shortBreak: return shortBreakDuration
        case .longBreak: return longBreakDuration
        }
    }
}
