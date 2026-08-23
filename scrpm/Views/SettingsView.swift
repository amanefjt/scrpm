import SwiftUI
import SwiftData
import AppKit

/// タイマーの各種時間を変更する画面。TimerView の Idle 画面からのみ開ける
/// （作業中・休憩中は値を変えられない）。変更は UserDefaults に即座に保存され、
/// 次にそのフェーズへ入ったときから反映される（Durations.swift 参照）。
///
/// 開いている間に自動開始などで Idle から抜けた場合は、編集不可の制約を守るため
/// 自動でタイマー画面に戻す
///
/// クラウド同期（作業ログの書き出し先・端末間同期）の設定もここに集約している
/// （2026-08-23 追加。以前は作業ログウィンドウ側にあったが、⌘⇧L を押さないと
/// たどり着けず見つけにくかったため）。この画面自体が Idle 限定なので、
/// 同期設定も他の設定と同様「作業中・休憩中は変更できない」制約を継承する
struct SettingsView: View {
    @Environment(TimerStateManager.self) var timerManager
    @Environment(\.modelContext) private var context
    let onBack: () -> Void

    @State private var workMinutes: Int
    @State private var shortBreakMinutes: Int
    @State private var longBreakMinutes: Int
    @State private var setsPerCycleValue: Int
    @State private var longBreakActionDelayMinutes: Int
    @State private var idleActivationMinutesValue: Int
    @State private var workInactivityDeactivationMinutesValue: Int

    @State private var exportDirectory: URL? = WorkLogExporter.directoryURL
    @State private var deviceDisplayName: String = SessionSyncExporter.deviceDisplayName ?? ""
    @State private var lastImportedAt: Date? = SessionSyncExporter.lastImportedAt

    init(onBack: @escaping () -> Void) {
        self.onBack = onBack
        _workMinutes = State(initialValue: Int(workDuration / 60))
        _shortBreakMinutes = State(initialValue: Int(shortBreakDuration / 60))
        _longBreakMinutes = State(initialValue: Int(longBreakDuration / 60))
        _setsPerCycleValue = State(initialValue: setsPerCycle)
        _longBreakActionDelayMinutes = State(initialValue: Int(longBreakActionDelay / 60))
        _idleActivationMinutesValue = State(initialValue: Int(idleActivationMinutes))
        _workInactivityDeactivationMinutesValue = State(initialValue: Int(workInactivityDeactivationMinutes))
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
        .onChange(of: idleActivationMinutesValue) { syncIdleActivationMinutes() }
        .onChange(of: workInactivityDeactivationMinutesValue) { syncWorkInactivityDeactivationMinutes() }
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

    private func syncIdleActivationMinutes() {
        idleActivationMinutes = TimeInterval(idleActivationMinutesValue)
    }

    private func syncWorkInactivityDeactivationMinutes() {
        workInactivityDeactivationMinutes = TimeInterval(workInactivityDeactivationMinutesValue)
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

            Section("自動検知") {
                Stepper(value: $idleActivationMinutesValue, in: 1...30) {
                    Text("何分入力が続いたら自動的に作業を開始するか: \(idleActivationMinutesValue)分")
                }
                Stepper(value: $workInactivityDeactivationMinutesValue, in: 1...30) {
                    Text("何分操作が無ければ自動的に作業を終了するか: \(workInactivityDeactivationMinutesValue)分")
                }
            }

            Section("クラウド同期") {
                HStack(spacing: 8) {
                    Text("書き出し先")
                        .foregroundStyle(.secondary)
                    Text(exportDirectory?.path ?? "未設定（書き出さない）")
                        .foregroundStyle(exportDirectory == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer()
                    Button("変更…") { chooseExportDirectory() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    if exportDirectory != nil {
                        Button("解除") {
                            WorkLogExporter.directoryURL = nil
                            exportDirectory = nil
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                }

                HStack(spacing: 8) {
                    Text("このMacの名前")
                        .foregroundStyle(.secondary)
                    TextField("例: 研究室", text: $deviceDisplayName)
                        .disabled(exportDirectory == nil)
                        .onSubmit { commitDeviceDisplayName() }
                    Spacer()
                    Text(lastSyncText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("今すぐ同期") { syncNow() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(exportDirectory == nil
                                  || deviceDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Text("研究室PC・自宅PCなど、同じクラウド同期フォルダ（Google Drive 等）を"
                     + "指定した端末どうしで作業ログを統合できます。表示名は端末ごとに違う名前にしてください。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text("変更は次に開始する作業・休憩から反映されます。作業中・休憩中はこの画面を開けません。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var lastSyncText: String {
        guard let last = lastImportedAt else { return "未同期" }
        let fmt = DateFormatter()
        fmt.dateStyle = .none
        fmt.timeStyle = .short
        fmt.locale = Locale(identifier: "ja_JP")
        return "最終同期 \(fmt.string(from: last))"
    }

    /// クラウド同期フォルダ（Google Drive 等）を選ばせる。選んだ時点で当日分を1回書き出し、
    /// 実際にファイルが出ることをその場で確認できるようにする
    private func chooseExportDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "ここに書き出す"
        panel.message = "作業ログの書き出し先フォルダを選んでください（Google Drive 等のクラウド同期フォルダ）"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        WorkLogExporter.directoryURL = url
        exportDirectory = url
        WorkLogExporter.export(day: Date(), context: context)
    }

    private func commitDeviceDisplayName() {
        let trimmed = deviceDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        SessionSyncExporter.deviceDisplayName = trimmed.isEmpty ? nil : trimmed
    }

    /// 「今すぐ同期」: 表示名を確定させてから、書き出し→読み込み→（読み込みで埋まった
    /// note を反映するため）再書き出し、という一往復を行う
    private func syncNow() {
        commitDeviceDisplayName()
        SessionSyncExporter.syncNow(context: context)
        lastImportedAt = SessionSyncExporter.lastImportedAt
    }

    private var longBreakDelayRange: ClosedRange<Int> {
        0...max(longBreakMinutes - 1, 0)
    }

    private var longBreakActionDelayText: String {
        longBreakActionDelayMinutes == 0 ? "すぐ表示" : "\(longBreakActionDelayMinutes)分"
    }
}
