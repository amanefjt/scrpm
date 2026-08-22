import SwiftUI

/// タイマーの各種時間を変更する画面。TimerView の Idle 画面からのみ開ける
/// （作業中・休憩中は値を変えられない）。変更は UserDefaults に即座に保存され、
/// 次にそのフェーズへ入ったときから反映される（Durations.swift 参照）。
///
/// 開いている間に自動開始などで Idle から抜けた場合は、編集不可の制約を守るため
/// 自動でタイマー画面に戻す
struct SettingsView: View {
    @Environment(TimerStateManager.self) var timerManager
    let onBack: () -> Void

    @State private var workMinutes: Int
    @State private var shortBreakMinutes: Int
    @State private var longBreakMinutes: Int
    @State private var setsPerCycleValue: Int
    @State private var longBreakActionDelayMinutes: Int

    init(onBack: @escaping () -> Void) {
        self.onBack = onBack
        _workMinutes = State(initialValue: Int(workDuration / 60))
        _shortBreakMinutes = State(initialValue: Int(shortBreakDuration / 60))
        _longBreakMinutes = State(initialValue: Int(longBreakDuration / 60))
        _setsPerCycleValue = State(initialValue: setsPerCycle)
        _longBreakActionDelayMinutes = State(initialValue: Int(longBreakActionDelay / 60))
    }

    var body: some View {
        VStack(spacing: 0) {
            backButton
            form
        }
        .frame(minWidth: 420, minHeight: 420)
        .onChange(of: workMinutes) { syncWorkMinutes() }
        .onChange(of: shortBreakMinutes) { syncShortBreakMinutes() }
        .onChange(of: longBreakMinutes) { syncLongBreakMinutes() }
        .onChange(of: setsPerCycleValue) { syncSetsPerCycle() }
        .onChange(of: longBreakActionDelayMinutes) { syncLongBreakActionDelay() }
        .onChange(of: timerManager.phase) { returnToTimerIfLeftIdle() }
    }

    private func syncWorkMinutes() {
        workDuration = TimeInterval(workMinutes * 60)
    }

    private func syncShortBreakMinutes() {
        shortBreakDuration = TimeInterval(shortBreakMinutes * 60)
    }

    private func syncLongBreakMinutes() {
        longBreakDuration = TimeInterval(longBreakMinutes * 60)
        // 再開ボタンの遅延が休憩そのものより長くならないように追従させる
        if longBreakActionDelayMinutes >= longBreakMinutes {
            longBreakActionDelayMinutes = max(longBreakMinutes - 1, 0)
        }
    }

    private func syncSetsPerCycle() {
        setsPerCycle = setsPerCycleValue
    }

    private func syncLongBreakActionDelay() {
        longBreakActionDelay = TimeInterval(longBreakActionDelayMinutes * 60)
    }

    private func returnToTimerIfLeftIdle() {
        if timerManager.phase != .idle { onBack() }
    }

    private var backButton: some View {
        HStack {
            Button("← タイマーに戻る") { onBack() }
                .buttonStyle(.borderless)
                .foregroundStyle(.blue)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var form: some View {
        Form {
            Section("作業サイクル") {
                Stepper(value: $workMinutes, in: 1...60) {
                    Text("作業時間: \(workMinutes)分")
                }
                Stepper(value: $shortBreakMinutes, in: 1...30) {
                    Text("短い休憩: \(shortBreakMinutes)分")
                }
                Stepper(value: $setsPerCycleValue, in: 1...10) {
                    Text("セット数（これを終えたら長い休憩）: \(setsPerCycleValue)セット")
                }
                Stepper(value: $longBreakMinutes, in: 1...60) {
                    Text("長い休憩: \(longBreakMinutes)分")
                }
                Stepper(value: $longBreakActionDelayMinutes, in: longBreakDelayRange) {
                    Text("長い休憩で再開ボタンが出るまで: \(longBreakActionDelayText)")
                }
            }

            Text("変更は次に開始する作業・休憩から反映されます。作業中・休憩中はこの画面を開けません。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var longBreakDelayRange: ClosedRange<Int> {
        0...max(longBreakMinutes - 1, 0)
    }

    private var longBreakActionDelayText: String {
        longBreakActionDelayMinutes == 0 ? "すぐ表示" : "\(longBreakActionDelayMinutes)分"
    }
}
