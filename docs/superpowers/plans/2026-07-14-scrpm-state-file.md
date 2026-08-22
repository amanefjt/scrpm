# scrpm 状態ファイル書き出し Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `TimerStateManager` の phase（idle/working/breaking）が変化するたびに `~/.worklog/scrpm-state.json` へ現在の状態を書き出し、別プロジェクト（worklog-capture）が scrpm の稼働状態を読み取れるようにする。

**Architecture:** JSON エンコード用の純粋関数を持つ新規ファイル `ScrpmStateWriter.swift` を追加し、`TimerStateManager` の phase 遷移を単一の private メソッド `setPhase(_:since:)` に集約してそこから呼び出す。ファイル I/O は副作用として `write` 関数に閉じ込め、テスト可能な部分（JSON 文字列生成）は純粋関数として切り出す。

**Tech Stack:** Swift、Foundation（`JSONEncoder`、`ISO8601DateFormatter`）。外部依存なし。

## Global Constraints

- 状態ファイルパス: `~/.worklog/scrpm-state.json`
- スキーマ: `{"phase": "idle"|"working"|"breaking", "since": "<ISO 8601>"}`（spec: `docs/superpowers/specs/2026-07-10-worklog-capture-spec.md` の「scrpm 側の変更」節）
- 書き込み失敗（`~/.worklog/` ディレクトリ不存在など）は無視してよい。scrpm 本体の動作に影響を与えてはならない
- `~/.worklog/` ディレクトリ自体は作らない（worklog-capture 側が作る前提）
- 外部依存なし（Foundation のみ）
- 負荷集計テストの既存コマンドパターンを踏襲: `swiftc -o /tmp/xxx <files> tools/main.swift && /tmp/xxx`

---

### Task 1: ScrpmStateWriter の作成（TDD）

**Files:**
- Create: `scrpm/State/ScrpmStateWriter.swift`
- Modify: `tools/main.swift`（末尾にテストケースを追記）

**Interfaces:**
- Consumes: `TimerPhase`（`scrpm/State/TimerPhase.swift` で定義済み、`.idle` / `.working` / `.breaking`）
- Produces:
  - `ScrpmStateWriter.phaseString(_ phase: TimerPhase) -> String`
  - `ScrpmStateWriter.jsonString(phase: TimerPhase, since: Date) throws -> String`
  - `ScrpmStateWriter.stateFileURL: URL`
  - `ScrpmStateWriter.write(phase: TimerPhase, since: Date) -> Void`（Task 2 が使う）

- [ ] **Step 1: 既存のテストコマンドで現状のテストが通ることを確認する**

Run: `swiftc -o /tmp/workload_tests scrpm/State/Durations.swift scrpm/State/WorkloadStats.swift tools/main.swift && /tmp/workload_tests`
Expected: `ALL TESTS PASSED`

- [ ] **Step 2: 失敗するテストを `tools/main.swift` の末尾に追記する**

`tools/main.swift` の末尾、`if failures > 0 { ... }` ブロックの**直前**に以下を追記する:

```swift
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

let breakingJSON = try! ScrpmStateWriter.jsonString(phase: .breaking, since: sinceDate)
expect(breakingJSON.contains("\"phase\":\"breaking\""),
       "jsonString: phase breaking が正しくエンコードされる")

expect(ScrpmStateWriter.stateFileURL.path.hasSuffix(".worklog/scrpm-state.json"),
       "stateFileURL: パスが ~/.worklog/scrpm-state.json で終わる")
```

（`d(...)` は `tools/main.swift` 冒頭で既に定義済みの日時ヘルパーをそのまま使う。`JSONEncoder` はデフォルトでキー間・コロン後にスペースを入れない出力になるため `"\"phase\":\"working\""` のようにスペースなしで比較する）

- [ ] **Step 3: テストが失敗することを確認する（コンパイルエラーで失敗するはず）**

Run: `swiftc -o /tmp/scrpm_state_tests scrpm/State/Durations.swift scrpm/State/WorkloadStats.swift scrpm/State/TimerPhase.swift tools/main.swift && /tmp/scrpm_state_tests`
Expected: コンパイルエラー（`error: cannot find 'ScrpmStateWriter' in scope`）

- [ ] **Step 4: `ScrpmStateWriter.swift` を実装する**

`scrpm/State/ScrpmStateWriter.swift` を新規作成:

```swift
import Foundation

private struct ScrpmStateFile: Codable {
    let phase: String
    let since: String
}

enum ScrpmStateWriter {
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func phaseString(_ phase: TimerPhase) -> String {
        switch phase {
        case .idle: return "idle"
        case .working: return "working"
        case .breaking: return "breaking"
        }
    }

    static func jsonString(phase: TimerPhase, since: Date) throws -> String {
        let file = ScrpmStateFile(phase: phaseString(phase), since: isoFormatter.string(from: since))
        let data = try JSONEncoder().encode(file)
        return String(decoding: data, as: UTF8.self)
    }

    static var stateFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".worklog")
            .appendingPathComponent("scrpm-state.json")
    }

    /// 書き込み失敗（ディレクトリ不存在等）は無視する。scrpm 本体の動作に影響を与えないため。
    static func write(phase: TimerPhase, since: Date) {
        guard let json = try? jsonString(phase: phase, since: since) else { return }
        try? json.write(to: stateFileURL, atomically: true, encoding: .utf8)
    }
}
```

- [ ] **Step 5: テストが通ることを確認する**

Run: `swiftc -o /tmp/scrpm_state_tests scrpm/State/Durations.swift scrpm/State/WorkloadStats.swift scrpm/State/TimerPhase.swift scrpm/State/ScrpmStateWriter.swift tools/main.swift && /tmp/scrpm_state_tests`
Expected: `ALL TESTS PASSED`

- [ ] **Step 6: CLAUDE.md のテストコマンドを更新する**

`CLAUDE.md` 内の以下の行を探す:

```
- 負荷集計のテスト: `swiftc -o /tmp/workload_tests scrpm/State/Durations.swift scrpm/State/WorkloadStats.swift tools/main.swift && /tmp/workload_tests`
```

これを以下に置き換える:

```
- 負荷集計・状態ファイルのテスト: `swiftc -o /tmp/workload_tests scrpm/State/Durations.swift scrpm/State/WorkloadStats.swift scrpm/State/TimerPhase.swift scrpm/State/ScrpmStateWriter.swift tools/main.swift && /tmp/workload_tests`
```

- [ ] **Step 7: Xcode プロジェクトに新規ファイルを追加する**

`scrpm/State/ScrpmStateWriter.swift` は Xcode プロジェクトのターゲットに含める必要がある。Xcode で `scrpm.xcodeproj` を開き、`scrpm/State/` グループに `ScrpmStateWriter.swift` を「Add Files to scrpm...」で追加する（ターゲットメンバーシップ: `scrpm` をチェック）。もしくは `xcodebuild` が自動検出する設定であれば不要（`Task 2` のビルドで確認する）。

- [ ] **Step 8: コミット**

```bash
git add scrpm/State/ScrpmStateWriter.swift tools/main.swift CLAUDE.md
git commit -m "feat: worklog-capture 連携用の scrpm 状態ファイル書き出し機能を追加"
```

---

### Task 2: TimerStateManager への統合

**Files:**
- Modify: `scrpm/State/TimerStateManager.swift`

**Interfaces:**
- Consumes: `ScrpmStateWriter.write(phase: TimerPhase, since: Date)`（Task 1 で定義済み）
- Produces: なし（他タスクはこのファイルの変更に依存しない）

phase を直接代入している箇所（`init`、`startWork`、`stopWork`、`resumeWork`、`extendWork`、`finishWork`）を、状態ファイル書き出しも行う共通の private メソッド経由に置き換える。

- [ ] **Step 1: `setPhase(_:since:)` ヘルパーを追加する**

`scrpm/State/TimerStateManager.swift` の `startWork()` メソッドの直前（15行目付近、`init` の閉じ `}` の後）に以下を追加する:

```swift
    private func setPhase(_ newPhase: TimerPhase, since: Date) {
        phase = newPhase
        phaseStartedAt = since
        ScrpmStateWriter.write(phase: newPhase, since: since)
    }
```

- [ ] **Step 2: `init` で初期状態を書き出す**

現在の `init`:

```swift
    init(context: ModelContext) {
        self.context = context
        setupTerminationObserver()
        startActivityMonitor()
    }
```

これを以下に置き換える:

```swift
    init(context: ModelContext) {
        self.context = context
        setupTerminationObserver()
        startActivityMonitor()
        setPhase(.idle, since: Date())
    }
```

- [ ] **Step 3: `startWork()` を置き換える**

現在:

```swift
    func startWork() {
        startActivityMonitor()
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

これを以下に置き換える（`phase = .working` と `phaseStartedAt = now` の2行を `setPhase` 呼び出し1行にまとめる）:

```swift
    func startWork() {
        startActivityMonitor()
        workCompleted = false
        workAccumulatedDuration = 0
        extensionCount = 0
        let now = Date()
        setPhase(.working, since: now)
        workStartedAt = now
        remaining = workDuration
        startTimer()
    }
```

- [ ] **Step 4: `stopWork()` を置き換える**

現在:

```swift
    func stopWork() {
        if phase == .working || phase == .breaking {
            recordSession(completed: workCompleted)
        }
        workCompleted = false
        phase = .idle
        remaining = workDuration
        stopTimer()
        startActivityMonitor()
    }
```

これを以下に置き換える:

```swift
    func stopWork() {
        if phase == .working || phase == .breaking {
            recordSession(completed: workCompleted)
        }
        workCompleted = false
        setPhase(.idle, since: Date())
        remaining = workDuration
        stopTimer()
        startActivityMonitor()
    }
```

- [ ] **Step 5: `resumeWork()` を置き換える**

現在:

```swift
    func resumeWork() {
        guard phase == .breaking else { return }
        recordSession(completed: true)
        workCompleted = false
        let now = Date()
        phase = .working
        phaseStartedAt = now
        workStartedAt = now
        remaining = workDuration
        startActivityMonitor()
    }
```

これを以下に置き換える:

```swift
    func resumeWork() {
        guard phase == .breaking else { return }
        recordSession(completed: true)
        workCompleted = false
        let now = Date()
        setPhase(.working, since: now)
        workStartedAt = now
        remaining = workDuration
        startActivityMonitor()
    }
```

- [ ] **Step 6: `extendWork()` を置き換える**

現在:

```swift
    func extendWork() {
        guard phase == .breaking, extensionCount < maxExtensions else { return }
        extensionCount += 1
        phase = .working
        phaseStartedAt = Date()
        remaining = extensionDuration
        // workStartedAt は変えない: 元のセッション開始時刻を引き継ぎ、延長分も同一セッションに含める
        startActivityMonitor()
    }
```

これを以下に置き換える:

```swift
    func extendWork() {
        guard phase == .breaking, extensionCount < maxExtensions else { return }
        extensionCount += 1
        setPhase(.working, since: Date())
        remaining = extensionDuration
        // workStartedAt は変えない: 元のセッション開始時刻を引き継ぎ、延長分も同一セッションに含める
        startActivityMonitor()
    }
```

- [ ] **Step 7: `finishWork()` を置き換える**

現在:

```swift
    private func finishWork() {
        workAccumulatedDuration += workCompleted ? extensionDuration : workDuration
        workCompleted = true
        let now = Date()
        phase = .breaking
        phaseStartedAt = now
        remaining = breakDuration
        // workStartedAt は保持したまま（記録は stopWork/resumeWork/finishBreak で行う）
        stopActivityMonitor()
    }
```

これを以下に置き換える:

```swift
    private func finishWork() {
        workAccumulatedDuration += workCompleted ? extensionDuration : workDuration
        workCompleted = true
        let now = Date()
        setPhase(.breaking, since: now)
        remaining = breakDuration
        // workStartedAt は保持したまま（記録は stopWork/resumeWork/finishBreak で行う）
        stopActivityMonitor()
    }
```

- [ ] **Step 8: ビルドが通ることを確認する**

Run: `xcodebuild -project scrpm.xcodeproj -target scrpm -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

（`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` が必要な場合がある。CLAUDE.md 参照）

- [ ] **Step 9: 実機で状態ファイルが書き出されることを手動確認する**

```bash
rm -f ~/.worklog/scrpm-state.json
mkdir -p ~/.worklog
open build/Debug/scrpm.app
sleep 2
cat ~/.worklog/scrpm-state.json
```

Expected: `{"phase":"idle","since":"2026-...T..."}` のような JSON が出力される。アプリで「作業開始」を押し、再度 `cat ~/.worklog/scrpm-state.json` を実行して `phase` が `working` に変わることも確認する。

- [ ] **Step 10: コミット**

```bash
git add scrpm/State/TimerStateManager.swift
git commit -m "feat: TimerStateManager の phase 遷移で状態ファイルを書き出す"
```

---

### Task 3: CLAUDE.md にドキュメント追記

**Files:**
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: なし
- Produces: なし

- [ ] **Step 1: 「過集中保護」節の後に新しい節を追記する**

`CLAUDE.md` の「## 過集中保護（2026-07 追加）」節の直後（次の見出しの直前）に以下を追記する:

```markdown

## worklog-capture 連携（2026-07 追加）

`TimerStateManager` の phase（idle/working/breaking）が変化するたびに
`~/.worklog/scrpm-state.json` へ `{"phase": "...", "since": "<ISO8601>"}` を書き出す
（`ScrpmStateWriter.swift`）。別プロジェクト `worklog-capture`
（`docs/superpowers/specs/2026-07-10-worklog-capture-spec.md`）が、scrpm が
Working 中かどうかを判定するために読む。

- 書き込み失敗（`~/.worklog/` ディレクトリ不存在など）は無視する。scrpm 本体の
  動作に影響を与えない
- `~/.worklog/` ディレクトリ自体は scrpm 側では作らない（worklog-capture 側の責務）
```

- [ ] **Step 2: コミット**

```bash
git add CLAUDE.md
git commit -m "docs: worklog-capture 連携の状態ファイル仕様を CLAUDE.md に追記"
```
