import Foundation

var failures = 0
func expect(_ cond: Bool, _ label: String) {
    if cond { print("PASS: \(label)") } else { failures += 1; print("FAIL: \(label)") }
}

var cal = Calendar(identifier: .gregorian)
cal.firstWeekday = 2
cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!

func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 12) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: day, hour: h))!
}
func session(_ y: Int, _ m: Int, _ day: Int, minutes: Double, hour: Int = 12) -> SessionRecord {
    SessionRecord(startTime: d(y, m, day, hour), duration: minutes * 60)
}

// --- totalDuration(onDay:) ---
let dayA = [
    session(2026, 7, 9, minutes: 25, hour: 9),
    session(2026, 7, 9, minutes: 25, hour: 14),
    session(2026, 7, 8, minutes: 50),
]
expect(WorkloadStats.totalDuration(onDay: d(2026, 7, 9), sessions: dayA, calendar: cal) == 50 * 60,
       "totalDuration: 同日 2 セッションを合算し他日を除外")
expect(WorkloadStats.totalDuration(onDay: d(2026, 7, 1), sessions: dayA, calendar: cal) == 0,
       "totalDuration: 記録のない日は 0")

// --- hasNoRestDay(asOf:) --- (restDayThreshold=1800, noRestWarningDays=10 前提)
let now = d(2026, 7, 10, 10)
// 昨日までの 10 日間 (7/9 〜 6/30) すべて 30 分以上
var noRest: [SessionRecord] = []
for offset in 1...10 {
    noRest.append(SessionRecord(startTime: cal.date(byAdding: .day, value: -offset, to: now)!,
                                duration: 1800))
}
expect(WorkloadStats.hasNoRestDay(asOf: now, sessions: noRest, calendar: cal) == true,
       "hasNoRestDay: 10 日間すべて閾値以上なら true")

// 1 日だけ閾値未満（休養日あり）
var withRest = noRest
withRest[4] = SessionRecord(startTime: withRest[4].startTime, duration: 1799)
expect(WorkloadStats.hasNoRestDay(asOf: now, sessions: withRest, calendar: cal) == false,
       "hasNoRestDay: 閾値未満の日が 1 日でもあれば false")

// データが 3 日分しかない → 残りの日は 0 なので false
let recentOnly = Array(noRest.prefix(3))
expect(WorkloadStats.hasNoRestDay(asOf: now, sessions: recentOnly, calendar: cal) == false,
       "hasNoRestDay: データ不足なら false")

// 今日 (7/10) が 0 でも判定に影響しない（昨日まで 10 日で判定）
expect(WorkloadStats.hasNoRestDay(asOf: now, sessions: noRest + [session(2026, 7, 10, minutes: 0)], calendar: cal) == true,
       "hasNoRestDay: 今日の実績は判定に含めない")

// --- previousFourWeekAverage(asOf:) ---
// 2026-07-10 は金曜。週初は 7/6(月)。過去 4 週間 = 6/8(月) 〜 7/5(日)
var fourWeeks: [SessionRecord] = [
    session(2026, 6, 8, minutes: 60),    // 窓の初日（境界内）
    session(2026, 6, 15, minutes: 60),
    session(2026, 6, 22, minutes: 60),
    session(2026, 7, 5, minutes: 60),    // 窓の最終日（境界内）
    session(2026, 7, 6, minutes: 999),   // 今週分 → 除外されるべき
    session(2026, 6, 7, minutes: 999),   // 窓より前 → 除外されるべき（かつ nil 回避のためのデータ存在証明）
]
let avg = WorkloadStats.previousFourWeekAverage(asOf: now, sessions: fourWeeks, calendar: cal)
expect(avg == 60 * 60, "previousFourWeekAverage: 窓内 4 時間 ÷ 4 週 = 1 時間/週")

// データが窓の開始より新しい → nil
let tooRecent = [session(2026, 7, 1, minutes: 60)]
expect(WorkloadStats.previousFourWeekAverage(asOf: now, sessions: tooRecent, calendar: cal) == nil,
       "previousFourWeekAverage: 4 週間分のデータがなければ nil")

// --- ScrpmStateWriter.jsonString ---
let sinceDate = d(2026, 7, 14, 14)
let workingJSON = try! ScrpmStateWriter.jsonString(phase: .working, since: sinceDate)
expect(workingJSON.contains("\"phase\":\"working\""),
       "jsonString: phase working が正しくエンコードされる")
expect(workingJSON.contains("2026-07-14T"),
       "jsonString: since が ISO8601 形式でエンコードされる")

let idleJSON = try! ScrpmStateWriter.jsonString(phase: .idle, since: sinceDate)
expect(idleJSON.contains("\"phase\":\"idle\""),
       "jsonString: phase idle が正しくエンコードされる")

// 短い休憩・長い休憩はどちらも "breaking"（worklog-capture 向けの 3 値互換）
let shortBreakJSON = try! ScrpmStateWriter.jsonString(phase: .shortBreak, since: sinceDate)
expect(shortBreakJSON.contains("\"phase\":\"breaking\""),
       "jsonString: shortBreak は breaking としてエンコードされる")

let longBreakJSON = try! ScrpmStateWriter.jsonString(phase: .longBreak, since: sinceDate)
expect(longBreakJSON.contains("\"phase\":\"breaking\""),
       "jsonString: longBreak は breaking としてエンコードされる")

expect(ScrpmStateWriter.stateFileURL.path.hasSuffix(".worklog/scrpm-state.json"),
       "stateFileURL: パスが ~/.worklog/scrpm-state.json で終わる")

// --- TimerPhase ---
expect(TimerPhase.shortBreak.isBreak && TimerPhase.longBreak.isBreak,
       "TimerPhase: 短い休憩・長い休憩はどちらも isBreak")
expect(!TimerPhase.idle.isBreak && !TimerPhase.working.isBreak,
       "TimerPhase: idle / working は isBreak ではない")
expect(TimerPhase.shortBreak.duration == shortBreakDuration
       && TimerPhase.longBreak.duration == longBreakDuration,
       "TimerPhase: duration がフェーズごとの長さを返す")

// --- WorkLog ---
func entry(_ h1: Int, _ m1: Int, _ h2: Int, _ m2: Int, _ note: String, day: Int = 17) -> WorkLogEntry {
    WorkLogEntry(
        startTime: cal.date(from: DateComponents(year: 2026, month: 8, day: day, hour: h1, minute: m1))!,
        endTime: cal.date(from: DateComponents(year: 2026, month: 8, day: day, hour: h2, minute: m2))!,
        note: note
    )
}

let logDay = d(2026, 8, 17)
let logEntries = [
    entry(12, 12, 12, 27, "読み方第1章を読む"),
    entry(12, 29, 12, 44, "読み方第1章を読む"),
    entry(12, 46, 12, 56, ""),                    // 作業内容なし（中断セッション）
    entry(13, 12, 13, 27, "  読み方第1章を読む  "),  // 前後の空白は落とす
    entry(9, 0, 9, 15, "前日の記録", day: 16),      // 別日 → 除外されるべき
]

let expectedBody = """
12:12-12:27 読み方第1章を読む
12:29-12:44 読み方第1章を読む
12:46-12:56
13:12-13:27 読み方第1章を読む
"""
expect(WorkLog.body(entries: logEntries, on: logDay, calendar: cal) == expectedBody,
       "WorkLog.body: 当日分のみを時刻順に整形し、作業内容なしは時刻だけの行になる")

expect(WorkLog.body(entries: logEntries, on: d(2026, 8, 15), calendar: cal) == "",
       "WorkLog.body: 記録のない日は空文字")

// 入力順が前後していても開始時刻順に並ぶ
expect(WorkLog.body(entries: logEntries.reversed(), on: logDay, calendar: cal) == expectedBody,
       "WorkLog.body: 入力順によらず開始時刻順に並ぶ")

let doc = WorkLog.document(entries: logEntries, on: logDay,
                           totalDuration: 55 * 60, calendar: cal)
expect(doc.hasPrefix("# 2026-08-17\n"), "WorkLog.document: 見出しが日付になる")
expect(doc.contains("12:12-12:27 読み方第1章を読む"), "WorkLog.document: 本文を含む")
expect(doc.contains("合計 0:55"), "WorkLog.document: 合計時間を含む")
expect(WorkLog.fileName(for: logDay, calendar: cal) == "2026-08-17.md",
       "WorkLog.fileName: YYYY-MM-DD.md 形式")

// --- SessionSync ---
func snapshot(_ id: UUID, _ y: Int, _ m: Int, _ day: Int, note: String = "",
              hour: Int = 12, completed: Bool = true) -> SessionSnapshot {
    let start = cal.date(from: DateComponents(year: y, month: m, day: day, hour: hour))!
    let end = start.addingTimeInterval(15 * 60)
    return SessionSnapshot(id: id, startTime: start, endTime: end, duration: 15 * 60,
                           completed: completed, note: note)
}

let idA = UUID()
let idB = UUID()
let idC = UUID()

// エンコード/デコードのラウンドトリップ
let originalSnapshots = [snapshot(idA, 2026, 8, 17, note: "第1章を読む")]
let roundTripped = try! SessionSync.decode(SessionSync.encode(originalSnapshots))
expect(roundTripped == originalSnapshots, "SessionSync: encode/decode のラウンドトリップで値が保たれる")

// planImport: ローカルに無い id はそのまま insert
let planNew = SessionSync.planImport(local: [], imported: [snapshot(idA, 2026, 8, 17)])
expect(planNew.toInsert.map(\.id) == [idA] && planNew.notesToFill.isEmpty,
       "planImport: ローカルに無いセッションは toInsert に入る")

// planImport: ローカルの note が空、インポート側が非空 → note を埋める
let planFill = SessionSync.planImport(
    local: [snapshot(idB, 2026, 8, 17, note: "")],
    imported: [snapshot(idB, 2026, 8, 17, note: "他マシンで書いた内容")]
)
expect(planFill.toInsert.isEmpty && planFill.notesToFill[idB] == "他マシンで書いた内容",
       "planImport: ローカルが空・リモートが非空なら note を埋める")

// planImport: ローカルに既に何か書かれていれば一切触らない（上書き事故の防止）
let planProtect = SessionSync.planImport(
    local: [snapshot(idC, 2026, 8, 17, note: "自分で書いた内容")],
    imported: [snapshot(idC, 2026, 8, 17, note: "他マシンの内容")]
)
expect(planProtect.toInsert.isEmpty && planProtect.notesToFill.isEmpty,
       "planImport: ローカルの note が非空なら同期で上書きしない")

// planImport: 両方空なら何もしない
let planBothEmpty = SessionSync.planImport(
    local: [snapshot(idA, 2026, 8, 17, note: "")],
    imported: [snapshot(idA, 2026, 8, 17, note: "")]
)
expect(planBothEmpty.toInsert.isEmpty && planBothEmpty.notesToFill.isEmpty,
       "planImport: 両方 note が空なら変化なし")

// sanitizedFileName: 表示名 + インスタンスIDの先頭6文字がファイル名になる
let instanceID = UUID(uuidString: "ABCDEF12-0000-0000-0000-000000000000")!
expect(SessionSync.sanitizedFileName(deviceLabel: "研究室", instanceID: instanceID) == "研究室-abcdef.json",
       "sanitizedFileName: 表示名とインスタンスIDから安定したファイル名を作る")
expect(SessionSync.sanitizedFileName(deviceLabel: "  ", instanceID: instanceID) == "device-abcdef.json",
       "sanitizedFileName: 表示名が空白のみならフォールバック名を使う")

if failures > 0 {
    print("\(failures) test(s) FAILED")
    exit(1)
}
print("ALL TESTS PASSED")
