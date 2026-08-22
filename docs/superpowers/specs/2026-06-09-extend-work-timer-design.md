# 作業延長機能 設計仕様

**日付**: 2026-06-09  
**対象**: scrpm ポモドーロタイマー

> **2026-08-09 削除済み**: 休憩を跨ぐたびに延長回数（`extensionCount`）がリセットされ、
> ポモドーロを跨いで延長を繰り返せば休憩を無限に先延ばしできてしまう仕様だったため、
> 過集中保護の意図に反するとして撤廃した。以下は当時の設計意図の記録として残す。

## 概要

25分の作業タイマー終了後、休憩オーバーレイに「作業を延長する」ボタンを追加する。押すと2分間作業を延長でき、何度でも繰り返せる。延長した時間は元のセッションに含めて記録する。

## 状態・定数の変更

### `Durations.swift`

```swift
let extensionDuration: TimeInterval = 2 * 60   // 120s（新規）
```

### `TimerStateManager` の新規プロパティ

```swift
private var workCompleted: Bool = false
```

25分完走時に `true` にセットし、`startWork()` でリセットする。`workStartedAt` は breaking フェーズ中も保持し続けることで、延長後も同一セッションとして時間を集計する。

## メソッドの変更

### `finishWork()` — セッション記録を除去

```swift
private func finishWork() {
    workCompleted = true
    phase = .breaking
    phaseStartedAt = Date()
    remaining = breakDuration
    // workStartedAt は保持したまま（記録は後続のアクションで行う）
}
```

### `tick()` — working ケースのタイムキャップ切り替え

```swift
case .working:
    let cap = workCompleted ? extensionDuration : workDuration
    remaining = max(0, cap - elapsed)
    if remaining <= 0 { finishWork() }
```

### `extendWork()` — 新メソッド

```swift
func extendWork() {
    guard phase == .breaking else { return }
    phase = .working
    phaseStartedAt = Date()
    remaining = extensionDuration
}
```

### セッション記録タイミング（3箇所に分散）

| 場所 | 条件 | `completed` |
|---|---|---|
| `stopWork()` | `.working` または `.breaking` 中 | `workCompleted` の値 |
| `resumeWork()` | `.breaking` 中かつ `workStartedAt != nil` | `true` |
| `finishBreak()` | 5分休憩終了 | `true` |

`startWork()` で `workCompleted = false` にリセット。

## UI 変更（`BreakOverlayView.swift`）

休憩開始からの経過時間によってボタンを切り替える：

| タイミング | 表示するボタン |
|---|---|
| 休憩開始〜60秒 | 「作業を延長する」、「作業をやめる」 |
| 60秒経過後 | 「作業を再開する」、「作業をやめる」 |

```swift
// 最初の60秒だけ
if timerManager.remaining > breakDuration - 60 {
    Button("作業を延長する") {
        timerManager.extendWork()
    }
    .buttonStyle(.borderedProminent)
    .controlSize(.large)
    .tint(.green)
}

// 60秒経過後
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
```

## 変更ファイル一覧

1. `scrpm/State/Durations.swift` — `extensionDuration` 定数追加
2. `scrpm/State/TimerStateManager.swift` — `workCompleted` フラグ、`finishWork()` 変更、`extendWork()` 追加、記録タイミング変更
3. `scrpm/Views/BreakOverlayView.swift` — 「作業を延長する」ボタン追加

## 非変更事項

- `TimerPhase` enum は変更しない（`.working`/`.breaking`/`.idle` のまま）
- `WorkSession` モデルは変更しない
- `TimerView.swift` は変更しない（延長ボタンはオーバーレイのみ）
