# 作業延長機能 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 25分作業完了後の休憩オーバーレイに「作業を延長する」ボタンを追加し、2分間の延長を何度でも繰り返せるようにする。延長時間は元のセッションに含めて記録する。

**Architecture:** `workCompleted` フラグを導入し、セッション記録タイミングを `finishWork()` から `stopWork()` / `resumeWork()` / `finishBreak()` に後ろ倒しにする。これにより `workStartedAt` が延長中も保持され、延長分も同一セッション時間として自動的に集計される。

**Tech Stack:** Swift 5.9+、SwiftUI、AppKit、SwiftData、Combine

---

## ファイル変更マップ

| ファイル | 変更内容 |
|---|---|
| `scrpm/State/Durations.swift` | `extensionDuration` 定数追加 |
| `scrpm/State/TimerStateManager.swift` | `workCompleted` フラグ、`finishWork()` 変更、`extendWork()` 追加、`tick()` 変更、`stopWork()` / `resumeWork()` / `finishBreak()` / `recordSessionIfNeeded()` の記録ロジック変更、`recordSession()` の duration キャップ除去 |
| `scrpm/Views/BreakOverlayView.swift` | 「作業を延長する」ボタン追加（最初の60秒のみ表示） |

---

### Task 1: `extensionDuration` 定数を追加

**Files:**
- Modify: `scrpm/State/Durations.swift`

- [ ] **Step 1: `extensionDuration` を追加**

`scrpm/State/Durations.swift` をこの内容に置き換える：

```swift
import Foundation

let workDuration: TimeInterval = 25 * 60
let breakDuration: TimeInterval = 5 * 60
let minimumRecordDuration: TimeInterval = 60
let extensionDuration: TimeInterval = 2 * 60
```

- [ ] **Step 2: ビルドが通ることを確認**

```bash
xcodebuild -project scrpm.xcodeproj -target scrpm -configuration Debug build 2>&1 | tail -5
```

期待出力: `BUILD SUCCEEDED`

- [ ] **Step 3: コミット**

```bash
git add scrpm/State/Durations.swift
git commit -m "feat: extensionDuration 定数を追加（2分）"
```

---

### Task 2: `workCompleted` フラグを追加し `startWork()` でリセット

**Files:**
- Modify: `scrpm/State/TimerStateManager.swift`

- [ ] **Step 1: プロパティ宣言を追加**

`TimerStateManager` の `private var timerCancellable` の行の直下に追加：

```swift
private var workCompleted: Bool = false
```

- [ ] **Step 2: `startWork()` にリセットを追加**

`startWork()` の先頭行（`let now = Date()` の前）に追加：

```swift
workCompleted = false
```

完成後の `startWork()`:

```swift
func startWork() {
    workCompleted = false
    let now = Date()
    phase = .working
    phaseStartedAt = now
    workStartedAt = now
    remaining = workDuration
    startTimer()
}
```

- [ ] **Step 3: ビルドが通ることを確認**

```bash
xcodebuild -project scrpm.xcodeproj -target scrpm -configuration Debug build 2>&1 | tail -5
```

期待出力: `BUILD SUCCEEDED`

- [ ] **Step 4: コミット**

```bash
git add scrpm/State/TimerStateManager.swift
git commit -m "feat: workCompleted フラグを追加、startWork() でリセット"
```

---

### Task 3: `finishWork()` からセッション記録を除去

**Files:**
- Modify: `scrpm/State/TimerStateManager.swift`

- [ ] **Step 1: `finishWork()` を変更**

`finishWork()` 全体をこの内容に置き換える：

```swift
private func finishWork() {
    workCompleted = true
    let now = Date()
    phase = .breaking
    phaseStartedAt = now
    remaining = breakDuration
    // workStartedAt は保持したまま（記録は stopWork/resumeWork/finishBreak で行う）
}
```

- [ ] **Step 2: ビルドが通ることを確認**

```bash
xcodebuild -project scrpm.xcodeproj -target scrpm -configuration Debug build 2>&1 | tail -5
```

期待出力: `BUILD SUCCEEDED`

- [ ] **Step 3: コミット**

```bash
git add scrpm/State/TimerStateManager.swift
git commit -m "refactor: finishWork() からセッション記録を除去、workCompleted フラグをセット"
```

---

### Task 4: `tick()` の working ケースに延長モード対応

**Files:**
- Modify: `scrpm/State/TimerStateManager.swift`

- [ ] **Step 1: `tick()` の working ケースを変更**

`tick()` 内の `case .working:` ブロックをこの内容に置き換える：

```swift
case .working:
    let cap = workCompleted ? extensionDuration : workDuration
    remaining = max(0, cap - elapsed)
    if remaining <= 0 {
        finishWork()
    }
```

- [ ] **Step 2: ビルドが通ることを確認**

```bash
xcodebuild -project scrpm.xcodeproj -target scrpm -configuration Debug build 2>&1 | tail -5
```

期待出力: `BUILD SUCCEEDED`

- [ ] **Step 3: コミット**

```bash
git add scrpm/State/TimerStateManager.swift
git commit -m "feat: tick() で workCompleted に応じて延長タイマーを使用"
```

---

### Task 5: `extendWork()` メソッドを追加

**Files:**
- Modify: `scrpm/State/TimerStateManager.swift`

- [ ] **Step 1: `extendWork()` を追加**

`resumeWork()` の直後に以下を追加：

```swift
func extendWork() {
    guard phase == .breaking else { return }
    phase = .working
    phaseStartedAt = Date()
    remaining = extensionDuration
}
```

- [ ] **Step 2: ビルドが通ることを確認**

```bash
xcodebuild -project scrpm.xcodeproj -target scrpm -configuration Debug build 2>&1 | tail -5
```

期待出力: `BUILD SUCCEEDED`

- [ ] **Step 3: コミット**

```bash
git add scrpm/State/TimerStateManager.swift
git commit -m "feat: extendWork() メソッドを追加（breaking → working、2分セット）"
```

---

### Task 6: セッション記録タイミングを修正（3箇所 + duration キャップ除去）

**Files:**
- Modify: `scrpm/State/TimerStateManager.swift`

- [ ] **Step 1: `stopWork()` を変更**

working 中だけでなく breaking 中も記録し、`workCompleted` でフラグを使う：

```swift
func stopWork() {
    if phase == .working || phase == .breaking {
        recordSession(completed: workCompleted)
    }
    workCompleted = false
    phase = .idle
    remaining = workDuration
    stopTimer()
}
```

- [ ] **Step 2: `resumeWork()` を変更**

休憩から作業に戻る前に完走セッションを記録し、新規セッションとして開始する：

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
}
```

- [ ] **Step 3: `finishBreak()` を変更**

5分休憩が終了したとき、未記録のセッションを記録してからアイドルへ戻る：

```swift
private func finishBreak() {
    recordSession(completed: true)
    workCompleted = false
    phase = .idle
    remaining = workDuration
    stopTimer()
}
```

- [ ] **Step 4: `recordSessionIfNeeded()` を変更**

アプリ終了時、breaking 中の未記録セッションも保存する：

```swift
func recordSessionIfNeeded() {
    guard phase == .working || (phase == .breaking && workStartedAt != nil) else { return }
    recordSession(completed: workCompleted)
}
```

- [ ] **Step 5: `recordSession()` の duration キャップを除去**

延長分も含めた実時間を記録するため、`min(elapsed, workDuration)` を `elapsed` に変更する：

```swift
private func recordSession(completed: Bool) {
    guard let start = workStartedAt else { return }
    let now = Date()
    let elapsed = now.timeIntervalSince(start)
    guard elapsed >= minimumRecordDuration else {
        workStartedAt = nil
        return
    }
    let session = WorkSession(
        startTime: start,
        endTime: now,
        duration: elapsed,
        completed: completed
    )
    context.insert(session)
    try? context.save()
    workStartedAt = nil
}
```

- [ ] **Step 6: ビルドが通ることを確認**

```bash
xcodebuild -project scrpm.xcodeproj -target scrpm -configuration Debug build 2>&1 | tail -5
```

期待出力: `BUILD SUCCEEDED`

- [ ] **Step 7: コミット**

```bash
git add scrpm/State/TimerStateManager.swift
git commit -m "feat: セッション記録タイミングを後ろ倒し、延長時間も含めて duration に記録"
```

---

### Task 7: `BreakOverlayView` に「作業を延長する」ボタンを追加

**Files:**
- Modify: `scrpm/Views/BreakOverlayView.swift`

- [ ] **Step 1: BreakOverlayView を更新**

`scrpm/Views/BreakOverlayView.swift` 全体をこの内容に置き換える：

```swift
import SwiftUI

struct BreakOverlayView: View {
    @Environment(TimerStateManager.self) var timerManager

    var body: some View {
        ZStack {
            Color.clear
            VStack(spacing: 32) {
                Text("休憩中")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                CountdownLabel(remaining: timerManager.remaining, phase: timerManager.phase)

                VStack(spacing: 12) {
                    if timerManager.remaining > breakDuration - 60 {
                        Button("作業を延長する") {
                            timerManager.extendWork()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.green)
                    }

                    if timerManager.remaining <= breakDuration - 60 {
                        Button("作業を再開する") {
                            timerManager.resumeWork()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.orange)
                    }

                    Button("作業をやめる") {
                        timerManager.stopWork()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .foregroundStyle(.white)
                }
            }
        }
        .colorScheme(.dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 2: ビルドが通ることを確認**

```bash
xcodebuild -project scrpm.xcodeproj -target scrpm -configuration Debug build 2>&1 | tail -5
```

期待出力: `BUILD SUCCEEDED`

- [ ] **Step 3: コミット**

```bash
git add scrpm/Views/BreakOverlayView.swift
git commit -m "feat: 休憩オーバーレイに「作業を延長する」ボタンを追加（最初の60秒のみ表示）"
```

---

### Task 8: 動作確認（手動テスト）

- [ ] **Step 1: タイマーを短縮してテスト用にビルド**

`scrpm/State/Durations.swift` を一時的にこの内容に変更する。
`workDuration = 70` は `minimumRecordDuration = 60` を超えるようにするため：

```swift
let workDuration: TimeInterval = 70    // テスト用（通常は 25 * 60）
let breakDuration: TimeInterval = 5 * 60
let minimumRecordDuration: TimeInterval = 60
let extensionDuration: TimeInterval = 10   // テスト用（通常は 2 * 60）
```

ビルドして起動：

```bash
xcodebuild -project scrpm.xcodeproj -target scrpm -configuration Debug build 2>&1 | tail -5
open build/Debug/scrpm.app
```

- [ ] **Step 2: シナリオ1 — 延長して休憩に入る**

1. 「作業開始」を押す
2. 10秒後に休憩オーバーレイが出ることを確認
3. **「作業を延長する」ボタンが緑で表示されていることを確認**
4. 「作業を延長する」を押す → オーバーレイが消え、`00:10` から Working カウントダウン開始を確認
5. 10秒後に再び休憩オーバーレイが出ることを確認

- [ ] **Step 3: シナリオ2 — 60秒後にボタンが切り替わる**

1. 「作業開始」 → 10秒後にオーバーレイ出現
2. 60秒待つ（実際の5分タイマーの最初の60秒）
3. 「作業を延長する」が消え、「作業を再開する」が出ることを確認

- [ ] **Step 4: シナリオ3 — 延長後「作業をやめる」でセッション記録確認**

1. 「作業開始」 → 10秒後にオーバーレイ
2. 「作業を延長する」押下 → 2分延長
3. 2分のうちに「作業をやめる」を押す
4. 「記録」タブを確認 → 1セッション（70秒 + 一部延長時間）が記録されていることを確認（`minimumRecordDuration = 60` を超えているので記録される）

- [ ] **Step 5: `workDuration` を元に戻してビルド確認**

```swift
let workDuration: TimeInterval = 25 * 60
let breakDuration: TimeInterval = 5 * 60
let minimumRecordDuration: TimeInterval = 60
let extensionDuration: TimeInterval = 2 * 60
```

```bash
xcodebuild -project scrpm.xcodeproj -target scrpm -configuration Debug build 2>&1 | tail -5
```

期待出力: `BUILD SUCCEEDED`

- [ ] **Step 6: 最終コミット**

```bash
git add scrpm/State/Durations.swift
git commit -m "test: workDuration を本番値（25分）に戻す"
```
