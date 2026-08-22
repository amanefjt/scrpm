# 過集中保護・負荷可視化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** scrpm を「デフォルトが常に計測中」のポモドーロタイマーにし、過集中による休憩スキップ・再開忘れ・無休連続作業を構造的に防ぐ。

**Architecture:** `TimerStateManager`（@Observable 状態機械）に延長上限・自動再開・idle 中の入力検出を追加する。負荷集計は SwiftData に依存しない純関数群 `WorkloadStats` に切り出し、swiftc でコンパイルする軽量テストハーネスで検証する。UI は既存ビューへの小改修＋警告バナー 1 ビュー追加。

**Tech Stack:** SwiftUI + AppKit (macOS 14+)、SwiftData、CoreGraphics（`CGEventSource`）。外部依存なし。

**Spec:** `docs/superpowers/specs/2026-07-10-hyperfocus-protection.md`

## Global Constraints

- 外部ライブラリ追加禁止。テストハーネスも swiftc 直接コンパイルのみ
- 定数はすべて `scrpm/State/Durations.swift` に置く（グローバル let、既存スタイルに合わせる）
- 音による告知は一切実装しない（ユーザー要望）
- セッション記録の既存仕様を壊さない: 記録は `stopWork()` / `resumeWork()` / `finishBreak()` で行う。`duration` に休憩時間を混入させない。`minimumRecordDuration = 60` 未満は記録しない
- ビルドコマンド: `xcodebuild -project scrpm.xcodeproj -target scrpm -configuration Debug build`（リポジトリルートで実行。Expected: `** BUILD SUCCEEDED **`）
- コミットメッセージは日本語。末尾に `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` を付ける
- 新規 .swift ファイルは `scrpm.xcodeproj/project.pbxproj` への手動登録が必要（旧式 PBXGroup 形式。各タスク内に正確な編集内容を記載）
- SourceKit がグローバル定数に "Cannot find in scope" を出すことがあるが、ビルドが通れば無視してよい（CLAUDE.md 参照）

---

### Task 0: 前セッションの未コミット変更を先にコミット

**Files:**
- 対象: `scrpm/ScrpmApp.swift`, `scrpm/Views/CountdownLabel.swift`, `scrpm/Views/TimerView.swift`, `scrpm/Assets.xcassets/WorkingGray.colorset/`（untracked）

作業ツリーに前セッションの UI 微調整（WorkingGray カラー、ウィンドウリサイズ対応、tint）が未コミットで残っている。本プランの変更と混ざらないよう先に分離コミットする。

- [ ] **Step 1: 内容を確認する**

Run: `git diff && git status --short`
Expected: 上記 3 ファイルの変更（`windowResizability(.automatic)`、`Color("WorkingGray")`、`.tint(.orange)`、frame の maxWidth/maxHeight 追加）と untracked の `WorkingGray.colorset/`。これ以外の想定外の差分があれば停止してユーザーに確認する。

- [ ] **Step 2: ビルドが通ることを確認する**

Run: `xcodebuild -project scrpm.xcodeproj -target scrpm -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: コミット**

```bash
git add scrpm/ScrpmApp.swift scrpm/Views/CountdownLabel.swift scrpm/Views/TimerView.swift "scrpm/Assets.xcassets/WorkingGray.colorset"
git commit -m "style: 作業中の表示色を WorkingGray に変更、ウィンドウをリサイズ可能に

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

※ `docs/`, `README.md`, `.superpowers/` などの untracked はこのプランの対象外。触らない。

---

### Task 1: workAccumulatedDuration リセット漏れの修正（既存バグ）

**Files:**
- Modify: `scrpm/State/TimerStateManager.swift`（`recordSession(completed:)`、108–137 行付近）

**Interfaces:**
- Produces: `recordSession()` がセッション記録確定後（および 60 秒未満で破棄した後）に `workAccumulatedDuration = 0` にリセットする、という不変条件。以後のタスク（特に Task 3 の自動再開）はこれを前提にする。

**バグの内容:** `resumeWork()` はセッションを記録して新しい作業を開始するが、`workAccumulatedDuration` をリセットしない。そのため「25分完走 → 休憩 → 作業を再開する → 25分完走 → 休憩満了」の流れで、2 本目のセッションの `duration` が `1500(前セッションの残骸) + 1500 = 3000` と二重計上される。Task 3 で休憩満了時の自動再開を入れると全セッションがこの経路を通るため、先に直す必要がある。

- [ ] **Step 1: recordSession の両方の出口でリセットする**

`scrpm/State/TimerStateManager.swift` の `recordSession(completed:)` を以下のように変更（変更点は `workAccumulatedDuration = 0` の 2 行）:

```swift
    private func recordSession(completed: Bool) {
        guard let start = workStartedAt else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(start)
        guard elapsed >= minimumRecordDuration else {
            workStartedAt = nil
            workAccumulatedDuration = 0
            return
        }
        // workAccumulatedDuration: 完了したフェーズの作業時間合計
        // 延長中に中断した場合は現フェーズの経過分も加算する
        let duration: TimeInterval
        if workAccumulatedDuration > 0 {
            if phase == .working, let phaseStart = phaseStartedAt {
                duration = workAccumulatedDuration + now.timeIntervalSince(phaseStart)
            } else {
                duration = workAccumulatedDuration
            }
        } else {
            duration = elapsed
        }
        let session = WorkSession(
            startTime: start,
            endTime: now,
            duration: duration,
            completed: completed
        )
        context.insert(session)
        try? context.save()
        workStartedAt = nil
        workAccumulatedDuration = 0
    }
```

- [ ] **Step 2: ビルド**

Run: `xcodebuild -project scrpm.xcodeproj -target scrpm -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 手動確認（短縮値を使用）**

`scrpm/State/Durations.swift` を一時的に `workDuration = 70`, `breakDuration = 20` にしてビルド・起動（`open build/Debug/scrpm.app`）。「作業開始 → 70秒完走 → 休憩 → 作業を再開する → 70秒完走 → 休憩を満了させる」を実行し、履歴の日タブで 2 本のセッションがそれぞれ約 1 分（70秒）で記録されていることを確認する（修正前は 2 本目が約 140 秒になる）。確認後、Durations.swift を本番値（`25 * 60` / `5 * 60`）に戻して再ビルドする。

- [ ] **Step 4: コミット**

```bash
git add scrpm/State/TimerStateManager.swift
git commit -m "fix: recordSession 後に workAccumulatedDuration をリセットし duration の二重計上を修正

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: F1 延長回数の上限

**Files:**
- Modify: `scrpm/State/Durations.swift`
- Modify: `scrpm/State/TimerStateManager.swift`
- Modify: `scrpm/Views/BreakOverlayView.swift`

**Interfaces:**
- Produces: `TimerStateManager.extensionCount: Int`（`private(set)`、UI から参照可）、定数 `maxExtensions: Int = 2`。延長カウントは `startWork()` と `recordSession()` の両出口でリセットされる。

- [ ] **Step 1: 定数を追加**

`scrpm/State/Durations.swift` に追記:

```swift
let maxExtensions: Int = 2
```

- [ ] **Step 2: TimerStateManager にカウンタを追加**

`scrpm/State/TimerStateManager.swift`:

プロパティ宣言部（`workAccumulatedDuration` の直後）に追加:

```swift
    private(set) var extensionCount: Int = 0
```

`startWork()` の先頭部を変更（`extensionCount = 0` を追加）:

```swift
    func startWork() {
        workCompleted = false
        workAccumulatedDuration = 0
        extensionCount = 0
        let now = Date()
        phase = .working
        phaseStartedAt = now
        workStartedAt = now
        remaining = workDuration
        startTimer()
    }
```

`extendWork()` を変更（ガードとインクリメント追加）:

```swift
    func extendWork() {
        guard phase == .breaking, extensionCount < maxExtensions else { return }
        extensionCount += 1
        phase = .working
        phaseStartedAt = Date()
        remaining = extensionDuration
        // workStartedAt は変えない: 元のセッション開始時刻を引き継ぎ、延長分も同一セッションに含める
    }
```

`recordSession(completed:)` の両出口（Task 1 で `workAccumulatedDuration = 0` を入れた 2 箇所）にそれぞれ `extensionCount = 0` を追加:

```swift
        guard elapsed >= minimumRecordDuration else {
            workStartedAt = nil
            workAccumulatedDuration = 0
            extensionCount = 0
            return
        }
```

```swift
        workStartedAt = nil
        workAccumulatedDuration = 0
        extensionCount = 0
    }
```

- [ ] **Step 3: BreakOverlayView のボタン表示条件に上限を追加**

`scrpm/Views/BreakOverlayView.swift` の延長ボタンの条件を変更:

```swift
                    if timerManager.remaining > breakDuration - 60,
                       timerManager.extensionCount < maxExtensions {
                        Button("作業を延長する") {
                            timerManager.extendWork()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.green)
                    }
```

- [ ] **Step 4: ビルド**

Run: `xcodebuild -project scrpm.xcodeproj -target scrpm -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: コミット**

```bash
git add scrpm/State/Durations.swift scrpm/State/TimerStateManager.swift scrpm/Views/BreakOverlayView.swift
git commit -m "feat: 作業延長を maxExtensions (2回) までに制限

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: F2 休憩満了後の自動再開

**Files:**
- Modify: `scrpm/State/TimerStateManager.swift`（`finishBreak()`、95–101 行付近）
- Modify: `CLAUDE.md`（状態遷移図は Task 7 でまとめて更新するのでここでは触らない）

**Interfaces:**
- Consumes: Task 1 の不変条件（recordSession 後は accumulated/extension カウントがリセット済み）
- Produces: 休憩満了時の遷移が `[Break] → [Working]`（無音・自動）になる。`.idle` への遷移経路は `stopWork()` と起動直後のみになる（Task 4 がこれを前提にする）。

- [ ] **Step 1: finishBreak を resumeWork 委譲に変更**

`scrpm/State/TimerStateManager.swift` の `finishBreak()` を以下に置き換え:

```swift
    private func finishBreak() {
        // 休憩満了後は Idle に戻さず、無音で次の作業セッションを自動開始する。
        // 再開の意思決定・操作という摩擦を排除するための設計（spec F2）
        resumeWork()
    }
```

`resumeWork()` は `guard phase == .breaking` を持ち、記録 → 新セッション開始（`workStartedAt` 再設定）を行うため、そのまま流用できる。タイマー（`timerCancellable`）は動き続けているので `startTimer()` の再呼び出しは不要。オーバーレイは `ScrpmApp` の `.onChange(of: phase)` が `.breaking` 以外への変化で `hide()` するため追加対応不要。

- [ ] **Step 2: ビルド**

Run: `xcodebuild -project scrpm.xcodeproj -target scrpm -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 手動確認（短縮値）**

`workDuration = 70`, `breakDuration = 20` で起動し、作業開始 → 70秒完走 → オーバーレイ表示 → 20秒放置。オーバーレイが自動で閉じ、メインウィンドウが作業中カウントダウン（25分…ではなく70秒）に無音で戻ることを確認。履歴に 1 本目のセッションが記録されていることも確認。終了後、本番値に戻す。

- [ ] **Step 4: コミット**

```bash
git add scrpm/State/TimerStateManager.swift
git commit -m "feat: 休憩満了後に Idle へ戻さず次の作業セッションを自動開始

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: F3 Idle 中の入力検出 → 無音自動開始

**Files:**
- Modify: `scrpm/State/Durations.swift`
- Modify: `scrpm/State/TimerStateManager.swift`

**Interfaces:**
- Consumes: Task 3 により `.idle` への遷移経路は `stopWork()` と `init` 直後のみ
- Produces: 定数 `idlePollingInterval: TimeInterval = 30`、`idleActivationCount: Int = 6`。`TimerStateManager` が idle 中のみ入力ポーリングを行い、約 3 分の継続入力で `startWork()` を自動呼び出しする。

- [ ] **Step 1: 定数を追加**

`scrpm/State/Durations.swift` に追記:

```swift
let idlePollingInterval: TimeInterval = 30
let idleActivationCount: Int = 6
```

- [ ] **Step 2: TimerStateManager に idle 監視を実装**

`scrpm/State/TimerStateManager.swift` に以下を追加・変更する。

プロパティ宣言部（`timerCancellable` の直後）に追加:

```swift
    private var idleMonitorCancellable: AnyCancellable?
    private var consecutiveActivityCount = 0
```

`init` の末尾（`setupTerminationObserver()` の後）に追加:

```swift
        startIdleMonitor()
```

`startWork()` の先頭に追加:

```swift
        stopIdleMonitor()
```

`stopWork()` の末尾（`stopTimer()` の後）に追加:

```swift
        startIdleMonitor()
```

ファイル末尾近く（`stopTimer()` の後）に以下のメソッド群を追加:

```swift
    // MARK: - Idle 中の入力検出（spec F3）
    // 「作業をやめる」後に PC 作業を続けている場合、約3分で無音で自動再開する。
    // 誤検出（動画視聴等）は許容する設計判断: 止めるのはワンクリックであり、
    // 止め忘れ（計測なし・休憩なしの連続作業）の害の方が大きい

    private func startIdleMonitor() {
        stopIdleMonitor()
        idleMonitorCancellable = Timer.publish(every: idlePollingInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.checkIdleActivity() }
    }

    private func stopIdleMonitor() {
        idleMonitorCancellable?.cancel()
        idleMonitorCancellable = nil
        consecutiveActivityCount = 0
    }

    private func checkIdleActivity() {
        guard phase == .idle else {
            stopIdleMonitor()
            return
        }
        if Self.secondsSinceLastUserInput() < idlePollingInterval {
            consecutiveActivityCount += 1
        } else {
            consecutiveActivityCount = 0
        }
        if consecutiveActivityCount >= idleActivationCount {
            startWork()
        }
    }

    private static func secondsSinceLastUserInput() -> TimeInterval {
        let types: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]
        return types
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? .infinity
    }
```

補足: `CGEventSource.secondsSinceLastEventType` は読み取り専用でアクセシビリティ権限不要（App Sandbox も無効）。`import AppKit` 済みなので CoreGraphics の追加 import は不要。

- [ ] **Step 3: ビルド**

Run: `xcodebuild -project scrpm.xcodeproj -target scrpm -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 手動確認（短縮値）**

`idlePollingInterval = 5`, `idleActivationCount = 3` に一時変更してビルド・起動。Idle 状態のままタイピングやマウス操作を 15 秒ほど続けると、無音でカウントダウンが始まることを確認。次に Idle 状態で 20 秒放置 → その後入力、でカウントがリセットされてから 15 秒かかることも確認。終了後、本番値（30 / 6）に戻して再ビルド。

- [ ] **Step 5: コミット**

```bash
git add scrpm/State/Durations.swift scrpm/State/TimerStateManager.swift
git commit -m "feat: Idle 中の入力継続を検出して作業セッションを無音で自動開始

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: F4 休憩オーバーレイ「作業をやめる」の遅延有効化

**Files:**
- Modify: `scrpm/State/Durations.swift`
- Modify: `scrpm/Views/BreakOverlayView.swift`

**Interfaces:**
- Produces: 定数 `stopButtonDelay: TimeInterval = 10`。`0` にすると従来挙動（即時有効）に戻る。適用対象は休憩オーバーレイのみ（`TimerView` の「作業をやめる」には適用しない）。

- [ ] **Step 1: 定数を追加**

`scrpm/State/Durations.swift` に追記:

```swift
let stopButtonDelay: TimeInterval = 10   // 0 にすると即時有効（実質オフ）
```

- [ ] **Step 2: BreakOverlayView のボタンを遅延有効化**

`scrpm/Views/BreakOverlayView.swift` の「作業をやめる」ボタン部分を以下に置き換え:

```swift
                    let stopRemaining = stopButtonDelay - (breakDuration - timerManager.remaining)
                    Button(
                        stopRemaining > 0
                            ? "作業をやめる（あと\(Int(stopRemaining.rounded(.up)))秒）"
                            : "作業をやめる"
                    ) {
                        timerManager.stopWork()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .foregroundStyle(stopRemaining > 0 ? Color.gray : Color.white)
                    .disabled(stopRemaining > 0)
```

`breakDuration - timerManager.remaining` は休憩開始からの経過秒。延長 → 再度休憩に入った場合も `remaining` がリセットされるため、毎回の休憩で遅延が効く（意図通り）。残り秒数を表示するのは「あと何秒で押せるか」を見せて苛立ちを防ぐため。

- [ ] **Step 3: ビルド**

Run: `xcodebuild -project scrpm.xcodeproj -target scrpm -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 手動確認（短縮値）**

`workDuration = 70`, `stopButtonDelay = 3` で起動し完走。オーバーレイの「作業をやめる」が 3 秒間グレーアウト＋カウントダウン表示され、その後押せるようになることを確認。次に `stopButtonDelay = 0` にして従来通り即時に押せることを確認。終了後、本番値（10）に戻す。

- [ ] **Step 5: コミット**

```bash
git add scrpm/State/Durations.swift scrpm/Views/BreakOverlayView.swift
git commit -m "feat: 休憩オーバーレイの「作業をやめる」を stopButtonDelay 秒間無効化

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: F5 負荷集計の純関数 WorkloadStats + テストハーネス

**Files:**
- Create: `scrpm/State/WorkloadStats.swift`
- Create: `tools/workload_tests.swift`
- Modify: `scrpm/State/Durations.swift`
- Modify: `scrpm.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces:
  - `struct SessionRecord { let startTime: Date; let duration: TimeInterval }`
  - `WorkloadStats.totalDuration(onDay: Date, sessions: [SessionRecord], calendar: Calendar) -> TimeInterval`
  - `WorkloadStats.hasNoRestDay(asOf: Date, sessions: [SessionRecord], calendar: Calendar) -> Bool` — **昨日までの** `noRestWarningDays` 日間すべてが `restDayThreshold` 以上なら true（今日を含めない理由: 今日はまだ途中なので朝は必ず休養日に見えてしまい、警告が夕方まで出なくなるため)
  - `WorkloadStats.previousFourWeekAverage(asOf: Date, sessions: [SessionRecord], calendar: Calendar) -> TimeInterval?` — 表示週の週初（月曜）から遡る 4 週間の週平均。データがその期間より新しい場合は nil
  - 定数 `restDayThreshold: TimeInterval = 1800`、`noRestWarningDays: Int = 10`
- SwiftData に依存しない（Foundation のみ）。Task 7 の UI がこれを使う。

- [ ] **Step 1: 定数を追加**

`scrpm/State/Durations.swift` に追記:

```swift
let restDayThreshold: TimeInterval = 1800   // 日合計がこれ未満なら「休養日」
let noRestWarningDays: Int = 10             // 休養日ゼロ警告の対象期間（昨日までの日数）
```

- [ ] **Step 2: 失敗するテストを書く**

`tools/workload_tests.swift` を作成:

```swift
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

if failures > 0 {
    print("\(failures) test(s) FAILED")
    exit(1)
}
print("ALL TESTS PASSED")
```

- [ ] **Step 3: テストが失敗（コンパイルエラー）することを確認**

Run: `swiftc -o /tmp/workload_tests scrpm/State/Durations.swift tools/workload_tests.swift && /tmp/workload_tests`
Expected: FAIL — `cannot find 'WorkloadStats' in scope` / `cannot find 'SessionRecord' in scope`

- [ ] **Step 4: WorkloadStats を実装**

`scrpm/State/WorkloadStats.swift` を作成:

```swift
import Foundation

/// WorkSession から必要最小限を写した値型。
/// WorkloadStats を SwiftData 非依存（swiftc 単体でテスト可能）に保つためのもの
struct SessionRecord {
    let startTime: Date
    let duration: TimeInterval
}

/// 負荷集計の純関数群。日付・セッション列を引数に取り、状態を持たない
enum WorkloadStats {
    static func totalDuration(onDay day: Date, sessions: [SessionRecord], calendar: Calendar) -> TimeInterval {
        sessions
            .filter { calendar.isDate($0.startTime, inSameDayAs: day) }
            .reduce(0) { $0 + $1.duration }
    }

    /// 昨日までの noRestWarningDays 日間に「休養日」（日合計 < restDayThreshold）が
    /// 1 日もなければ true。今日を含めないのは、今日はまだ途中で朝は必ず休養日に
    /// 見えてしまい、警告が夕方まで出なくなるため
    static func hasNoRestDay(asOf now: Date, sessions: [SessionRecord], calendar: Calendar) -> Bool {
        for offset in 1...noRestWarningDays {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { return false }
            if totalDuration(onDay: day, sessions: sessions, calendar: calendar) < restDayThreshold {
                return false
            }
        }
        return true
    }

    /// date が属する週の週初（月曜）。WeekChartView の weekStart と同じ定義
    static func weekStart(for date: Date, calendar: Calendar) -> Date {
        var cal = calendar
        cal.firstWeekday = 2
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    /// 表示週の週初から遡る 4 週間（28 日）の週平均作業時間。
    /// 最古のセッションが窓の開始より新しい場合は比較に足るデータがないので nil
    static func previousFourWeekAverage(asOf date: Date, sessions: [SessionRecord], calendar: Calendar) -> TimeInterval? {
        let thisWeekStart = weekStart(for: date, calendar: calendar)
        guard let windowStart = calendar.date(byAdding: .day, value: -28, to: thisWeekStart),
              let earliest = sessions.map(\.startTime).min(),
              earliest <= windowStart else { return nil }
        let total = sessions
            .filter { $0.startTime >= windowStart && $0.startTime < thisWeekStart }
            .reduce(0) { $0 + $1.duration }
        return total / 4
    }
}
```

- [ ] **Step 5: テストが通ることを確認**

Run: `swiftc -o /tmp/workload_tests scrpm/State/Durations.swift scrpm/State/WorkloadStats.swift tools/workload_tests.swift && /tmp/workload_tests`
Expected: 全行 `PASS:` で最後に `ALL TESTS PASSED`

- [ ] **Step 6: pbxproj に WorkloadStats.swift を登録**

`scrpm.xcodeproj/project.pbxproj` を 4 箇所編集する（ID `AA0000000000000000000040` / `AA0000000000000000000041` は未使用であることを確認済み。編集前に `grep -c "AA0000000000000000000040" scrpm.xcodeproj/project.pbxproj` が 0 であることを確認すること）:

1. PBXBuildFile セクション（`AA0000000000000000000028 /* Durations.swift in Sources */ = ...` の行の直後）に追加:

```
		AA0000000000000000000041 /* WorkloadStats.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000040 /* WorkloadStats.swift */; };
```

2. PBXFileReference セクション（`AA0000000000000000000019 /* Durations.swift */ = ...` の行の直後）に追加:

```
		AA0000000000000000000040 /* WorkloadStats.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WorkloadStats.swift; sourceTree = "<group>"; };
```

3. State グループ（`AA0000000000000000000006 /* State */` の `children`、`AA0000000000000000000019 /* Durations.swift */,` の直後）に追加:

```
				AA0000000000000000000040 /* WorkloadStats.swift */,
```

4. PBXSourcesBuildPhase の `files`（`AA0000000000000000000028 /* Durations.swift in Sources */,` の直後）に追加:

```
				AA0000000000000000000041 /* WorkloadStats.swift in Sources */,
```

- [ ] **Step 7: Xcode ビルドが通ることを確認**

Run: `xcodebuild -project scrpm.xcodeproj -target scrpm -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: コミット**

```bash
git add scrpm/State/Durations.swift scrpm/State/WorkloadStats.swift tools/workload_tests.swift scrpm.xcodeproj/project.pbxproj
git commit -m "feat: 負荷集計の純関数 WorkloadStats を追加（休養日判定・4週平均）

swiftc 単体でコンパイルできる SwiftData 非依存の設計。
tools/workload_tests.swift のテストハーネスで検証済み。

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: F5 UI — 4週平均の表示と休養日ゼロ警告バナー

**Files:**
- Create: `scrpm/Views/RestWarningBanner.swift`
- Modify: `scrpm/Views/History/WeekChartView.swift`
- Modify: `scrpm/Views/TimerView.swift`
- Modify: `scrpm/Views/History/HistoryView.swift`
- Modify: `scrpm.xcodeproj/project.pbxproj`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: `WorkloadStats.previousFourWeekAverage(asOf:sessions:calendar:)`、`WorkloadStats.hasNoRestDay(asOf:sessions:calendar:)`、`SessionRecord(startTime:duration:)`（Task 6）
- Produces: `RestWarningBanner`（引数なしの SwiftUI View。警告条件を満たさないときは何も描画しない）

- [ ] **Step 1: RestWarningBanner を作成**

`scrpm/Views/RestWarningBanner.swift` を作成:

```swift
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
```

- [ ] **Step 2: pbxproj に RestWarningBanner.swift を登録**

Task 6 Step 6 と同じ要領で 4 箇所（ID は `AA0000000000000000000042` / `AA0000000000000000000043`。事前に grep で未使用を確認）:

1. PBXBuildFile セクション（`AA000000000000000000002C /* BreakOverlayView.swift in Sources */ = ...` の行の直後）:

```
		AA0000000000000000000043 /* RestWarningBanner.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000042 /* RestWarningBanner.swift */; };
```

2. PBXFileReference セクション（`AA000000000000000000001D /* BreakOverlayView.swift */ = ...` の行の直後）:

```
		AA0000000000000000000042 /* RestWarningBanner.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = RestWarningBanner.swift; sourceTree = "<group>"; };
```

3. Views グループ（`AA0000000000000000000007 /* Views */` の `children`、`AA000000000000000000001D /* BreakOverlayView.swift */,` の直後）:

```
				AA0000000000000000000042 /* RestWarningBanner.swift */,
```

4. PBXSourcesBuildPhase の `files`（`AA000000000000000000002C /* BreakOverlayView.swift in Sources */,` の直後）:

```
				AA0000000000000000000043 /* RestWarningBanner.swift in Sources */,
```

- [ ] **Step 3: WeekChartView に 4 週平均を表示**

`scrpm/Views/History/WeekChartView.swift` の `body` の週合計 Text の直後に平均 Text を追加し、computed property を足す:

`body` 内を変更:

```swift
        VStack(spacing: 8) {
            Text("週合計: \(formattedTotal)")
                .font(.headline)
                .padding(.top, 8)

            Text("過去4週平均: \(formattedFourWeekAverage)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Chart(dailyMinutes, id: \.label) { item in
```

ファイル末尾（`formattedTotal` の後）に追加:

```swift
    private var formattedFourWeekAverage: String {
        let records = allSessions.map { SessionRecord(startTime: $0.startTime, duration: $0.duration) }
        guard let avg = WorkloadStats.previousFourWeekAverage(asOf: date, sessions: records, calendar: .current) else {
            return "—（データ4週間未満）"
        }
        let totalMin = Int(avg / 60)
        return String(format: "%02d:%02d", totalMin / 60, totalMin % 60)
    }
```

- [ ] **Step 4: TimerView（Idle 時）と HistoryView にバナーを追加**

`scrpm/Views/TimerView.swift` の `.idle` ケースを変更（`RestWarningBanner()` を追加）:

```swift
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

                    RestWarningBanner()
                }
```

`scrpm/Views/History/HistoryView.swift` の戻るボタンの HStack と Picker の間に追加:

```swift
            RestWarningBanner()
                .padding(.horizontal)
                .padding(.bottom, 8)
```

（挿入位置: `.padding(.bottom, 8)` で閉じる HStack の直後、`Picker("表示", ...)` の直前）

- [ ] **Step 5: ビルド**

Run: `xcodebuild -project scrpm.xcodeproj -target scrpm -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: 手動確認**

起動して履歴 → 週タブで「過去4週平均: —（データ4週間未満）」または実データの平均が表示されることを確認（実データが 4 週間分あれば数値、なければプレースホルダ。どちらでも正常）。警告バナーは直近 10 日無休の場合のみ出る（出なければ正常データでは未発火なだけ。判定ロジック自体は Task 6 のテストで検証済み）。

- [ ] **Step 7: CLAUDE.md を更新**

`CLAUDE.md` の以下を更新する:

1. 「状態遷移」セクションの図と定数行を差し替え:

```
## 状態遷移
```
[Idle] ──「作業開始」──────────────→ [Working]
[Idle] ──約3分の入力継続を検出────→ [Working]（無音自動開始）
[Working] ──25分経過──→ [Break]
[Working] ──「作業をやめる」──→ [Idle]
[Break] ──5分経過──→ [Working]（無音で自動再開。Idle には戻らない）
[Break] ──「作業を延長する」（最初の60秒のみ・最大 maxExtensions 回）──→ [Working(2分)]
[Break] ──「作業を再開する」（60秒経過後）──→ [Working]
[Break] ──「作業をやめる」（表示から stopButtonDelay 秒後に有効化）──→ [Idle]
```

定数: `workDuration = 1500s`、`breakDuration = 300s`、`minimumRecordDuration = 60s`、`extensionDuration = 120s`、`maxExtensions = 2`、`stopButtonDelay = 10s`（0 で無効）、`idlePollingInterval = 30s`、`idleActivationCount = 6`、`restDayThreshold = 1800s`、`noRestWarningDays = 10`
```

2. 「ファイル構成」に追記: `State/WorkloadStats.swift`（負荷集計の純関数、SwiftData 非依存）、`Views/RestWarningBanner.swift`（休養日ゼロ警告）、`tools/workload_tests.swift`（swiftc テストハーネス）

3. 「休憩オーバーレイのUI仕様」に追記: 延長は `maxExtensions` 回まで。「作業をやめる」は表示から `stopButtonDelay` 秒間無効（残り秒数表示）。

4. 新セクションを追加:

```
## 過集中保護（2026-07 追加）
- 休憩満了後は Idle に戻らず無音で次の作業を自動開始（`finishBreak()` → `resumeWork()`）
- Idle 中は `CGEventSource.secondsSinceLastEventType` を 30 秒間隔でポーリングし、
  連続 6 回（約3分）入力を検出したら `startWork()` を自動呼び出し（誤検出は許容する設計）
- 週次負荷: 履歴の週タブに過去4週平均を表示。昨日までの 10 日間に休養日
  （日合計 < 30分）がなければ TimerView / HistoryView に警告バナー
- 負荷集計のテスト: `swiftc -o /tmp/workload_tests scrpm/State/Durations.swift scrpm/State/WorkloadStats.swift tools/workload_tests.swift && /tmp/workload_tests`
- 仕様: docs/superpowers/specs/2026-07-10-hyperfocus-protection.md
```

5. 「テスト用タイマー短縮」に追記: `idlePollingInterval = 5` / `idleActivationCount = 3` / `stopButtonDelay = 3` で自動開始・遅延ボタンを素早く確認できる。テスト後は必ず本番値に戻すこと。

- [ ] **Step 8: コミット**

```bash
git add scrpm/Views/RestWarningBanner.swift scrpm/Views/History/WeekChartView.swift scrpm/Views/TimerView.swift scrpm/Views/History/HistoryView.swift scrpm.xcodeproj/project.pbxproj CLAUDE.md
git commit -m "feat: 週タブに過去4週平均を表示、10日間無休で警告バナーを表示

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: 総合手動検証

**Files:**
- Modify（一時的）: `scrpm/State/Durations.swift`（検証後に必ず元へ戻す）

- [ ] **Step 1: 短縮値に変更してビルド・起動**

`Durations.swift` を一時変更: `workDuration = 70`, `breakDuration = 20`, `extensionDuration = 10`, `stopButtonDelay = 3`, `idlePollingInterval = 5`, `idleActivationCount = 3`。ビルドして `open build/Debug/scrpm.app`。

- [ ] **Step 2: シナリオ検証**

以下を順に確認する:

1. **延長上限**: 作業開始 → 70秒完走 → オーバーレイで「作業を延長する」→ 10秒完走 → 再度「延長」→ 10秒完走 → 3 回目の休憩では延長ボタンが出ない
2. **遅延ボタン**: 各休憩の最初の 3 秒間「作業をやめる（あとN秒）」がグレーアウトし、その後押せる
3. **自動再開**: 休憩を 20 秒放置 → 無音でオーバーレイが閉じ作業カウントダウンが始まる
4. **idle 自動開始**: 「作業をやめる」→ Idle のままタイピングを 15 秒継続 → 無音でカウントダウンが始まる
5. **記録の整合**: 履歴の日タブで、上記で完走したセッションの duration に休憩時間が混入していない（70 秒 + 延長分のオーダーになっている）こと、資格（60秒以上）を満たさない断片が記録されていないことを確認

- [ ] **Step 3: 本番値に戻して最終ビルド**

`Durations.swift` を本番値に戻す:

```swift
import Foundation

let workDuration: TimeInterval = 25 * 60
let breakDuration: TimeInterval = 5 * 60
let minimumRecordDuration: TimeInterval = 60
let extensionDuration: TimeInterval = 2 * 60
let maxExtensions: Int = 2
let stopButtonDelay: TimeInterval = 10   // 0 にすると即時有効（実質オフ）
let idlePollingInterval: TimeInterval = 30
let idleActivationCount: Int = 6
let restDayThreshold: TimeInterval = 1800   // 日合計がこれ未満なら「休養日」
let noRestWarningDays: Int = 10             // 休養日ゼロ警告の対象期間（昨日までの日数）
```

Run: `xcodebuild -project scrpm.xcodeproj -target scrpm -configuration Debug build && swiftc -o /tmp/workload_tests scrpm/State/Durations.swift scrpm/State/WorkloadStats.swift tools/workload_tests.swift && /tmp/workload_tests`
Expected: `** BUILD SUCCEEDED **` と `ALL TESTS PASSED`

- [ ] **Step 4: 差分がないこと（Durations が本番値であること）を確認してコミット**

Run: `git status --short`
Expected: 差分なし（Step 3 で戻した Durations.swift が Task 6 コミット時点と同一のため）。もし差分が残っていれば内容を確認し、検証用の値の戻し忘れなら修正する。

---

## Self-Review 結果（作成時に実施済み）

- **Spec coverage**: F1→Task 2、F2→Task 3、F3→Task 4、F4→Task 5、F5a/F5b→Task 6+7、F5c→スコープ外（spec 通り、データ収集後に判断）。テスト可能な純関数化の要求→Task 6。CLAUDE.md 更新→Task 7 Step 7 ✓
- **追加事項**: spec にない Task 1（workAccumulatedDuration 二重計上バグ）はプラン作成時のコードレビューで発見。F2 実装の前提となるため先頭に配置
- **型整合**: `SessionRecord(startTime:duration:)` / `WorkloadStats.hasNoRestDay(asOf:sessions:calendar:)` / `previousFourWeekAverage(asOf:sessions:calendar:)` の署名は Task 6 定義と Task 7 使用箇所で一致 ✓。`extensionCount` は Task 2 定義・BreakOverlayView 使用で一致 ✓
