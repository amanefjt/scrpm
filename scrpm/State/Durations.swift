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
    static let idleActivationMinutes: TimeInterval = 5           // 何分入力が続いたらIdle→Working自動開始するか
    static let workInactivityDeactivationMinutes: TimeInterval = 5  // 何分無操作が続いたらWorking→Idle自動中断するか
}

private enum SettingsKey {
    static let workDuration = "settings.workDuration"
    static let shortBreakDuration = "settings.shortBreakDuration"
    static let longBreakDuration = "settings.longBreakDuration"
    static let setsPerCycle = "settings.setsPerCycle"
    static let longBreakActionDelay = "settings.longBreakActionDelay"
    static let idleActivationMinutes = "settings.idleActivationMinutes"
    static let workInactivityDeactivationMinutes = "settings.workInactivityDeactivationMinutes"
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

/// 何分入力が続いたら Idle→Working を自動開始するか（分単位）
var idleActivationMinutes: TimeInterval {
    get { storedDuration(SettingsKey.idleActivationMinutes, default: DurationDefaults.idleActivationMinutes) }
    set { UserDefaults.standard.set(newValue, forKey: SettingsKey.idleActivationMinutes) }
}

/// 何分無操作が続いたら Working→Idle を自動中断するか（分単位）
var workInactivityDeactivationMinutes: TimeInterval {
    get { storedDuration(SettingsKey.workInactivityDeactivationMinutes, default: DurationDefaults.workInactivityDeactivationMinutes) }
    set { UserDefaults.standard.set(newValue, forKey: SettingsKey.workInactivityDeactivationMinutes) }
}

// MARK: - ユーザーが変更できない値（挙動の根幹に関わる・秒単位の微調整は不要なため）

let minimumRecordDuration: TimeInterval = 60
let idlePollingInterval: TimeInterval = 30   // ポーリング間隔自体は固定。設定できるのは「何分で検知するか」（上記）
let restDayThreshold: TimeInterval = 1800   // 日合計がこれ未満なら「休養日」
let noRestWarningDays: Int = 10             // 休養日ゼロ警告の対象期間（昨日までの日数）

/// idleActivationMinutes を idlePollingInterval 単位の回数に換算したもの。
/// 少なくとも1回は必要（0分設定などで即座に反応してしまうのを防ぐ）
var idleActivationCount: Int {
    max(1, Int((idleActivationMinutes * 60 / idlePollingInterval).rounded()))
}

/// workInactivityDeactivationMinutes を idlePollingInterval 単位の回数に換算したもの
var workInactivityDeactivationCount: Int {
    max(1, Int((workInactivityDeactivationMinutes * 60 / idlePollingInterval).rounded()))
}
