import Foundation

// MARK: - ユーザーが設定画面で変更できる値
//
// UserDefaults に保存する。呼び出し側（TimerStateManager, TimerPhase 等）は
// 従来どおり `workDuration` のようにグローバル変数として参照するだけでよく、
// 値は参照するたびに UserDefaults から読み直される。
//
// 「作業中・休憩中は変更できない」という制約はここでは持たず、SettingsView 側
// （Idle のときしか開けない画面）で保証する。フェーズ遷移のたびに値を読み直す
// だけの実装なので、変更は自然に「次のフェーズから」反映される。

private enum DurationDefaults {
    static let workDuration: TimeInterval = 15 * 60
    static let shortBreakDuration: TimeInterval = 2 * 60
    static let longBreakDuration: TimeInterval = 10 * 60
    static let setsPerCycle: Int = 4
    static let longBreakActionDelay: TimeInterval = 5 * 60   // 長い休憩の開始からこの秒数経つまでボタンを表示しない
}

private enum SettingsKey {
    static let workDuration = "settings.workDuration"
    static let shortBreakDuration = "settings.shortBreakDuration"
    static let longBreakDuration = "settings.longBreakDuration"
    static let setsPerCycle = "settings.setsPerCycle"
    static let longBreakActionDelay = "settings.longBreakActionDelay"
}

private func storedDuration(_ key: String, default def: TimeInterval) -> TimeInterval {
    let d = UserDefaults.standard
    return d.object(forKey: key) != nil ? d.double(forKey: key) : def
}

var workDuration: TimeInterval {
    get { storedDuration(SettingsKey.workDuration, default: DurationDefaults.workDuration) }
    set { UserDefaults.standard.set(newValue, forKey: SettingsKey.workDuration) }
}

var shortBreakDuration: TimeInterval {
    get { storedDuration(SettingsKey.shortBreakDuration, default: DurationDefaults.shortBreakDuration) }
    set { UserDefaults.standard.set(newValue, forKey: SettingsKey.shortBreakDuration) }
}

var longBreakDuration: TimeInterval {
    get { storedDuration(SettingsKey.longBreakDuration, default: DurationDefaults.longBreakDuration) }
    set { UserDefaults.standard.set(newValue, forKey: SettingsKey.longBreakDuration) }
}

var setsPerCycle: Int {
    get {
        let d = UserDefaults.standard
        return d.object(forKey: SettingsKey.setsPerCycle) != nil
            ? d.integer(forKey: SettingsKey.setsPerCycle)
            : DurationDefaults.setsPerCycle
    }
    set { UserDefaults.standard.set(newValue, forKey: SettingsKey.setsPerCycle) }
}

var longBreakActionDelay: TimeInterval {
    get { storedDuration(SettingsKey.longBreakActionDelay, default: DurationDefaults.longBreakActionDelay) }
    set { UserDefaults.standard.set(newValue, forKey: SettingsKey.longBreakActionDelay) }
}

// MARK: - ユーザーが変更できない値（挙動の根幹に関わる・秒単位の微調整は不要なため）

let minimumRecordDuration: TimeInterval = 60
let idlePollingInterval: TimeInterval = 30
let idleActivationCount: Int = 10   // idlePollingInterval(30s) × 10 = 5分の入力継続でIdle自動開始
let workInactivityDeactivationCount: Int = 10   // idlePollingInterval(30s) × 10 = 5分の無操作でWorking自動中断
let restDayThreshold: TimeInterval = 1800   // 日合計がこれ未満なら「休養日」
let noRestWarningDays: Int = 10             // 休養日ゼロ警告の対象期間（昨日までの日数）
