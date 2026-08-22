# 休憩ボタンの表示統一・延長機能撤廃・休憩終了サウンド 仕様

**日付**: 2026-08-09
**対象**: scrpm ポモドーロタイマー

## 背景・目的

休憩オーバーレイの「作業を延長する」ボタンには、休憩を跨ぐたびに延長回数（`extensionCount`）が
リセットされる仕様上、延長を繰り返せば休憩を無限に先延ばしできてしまう問題があった
（過去の設計: `docs/superpowers/specs/2026-06-09-extend-work-timer-design.md`）。これは
scrpm が目指す「過集中保護（休憩を強制する）」という設計思想と矛盾するため、延長機能自体を
撤廃した。

延長ボタンを含めた旧UIには、さらに「作業をやめる」（`stopButtonDelay`=10秒で有効化）と
「作業を再開する」（60秒後に表示）の間に大きな非対称があった。「やめる」の方がずっと早く
押せるため、本当は作業を続けたい（休憩をスキップして再開したい）場面でも先に「やめる」を
押してしまい、直後に再開系のボタンが使えるようになった時点で早計だったと気づく、という
体験になっていた。今回この非対称を解消した。

最後に、休憩満了後の無音自動再開（`finishBreak()` → `resumeWork()`。spec F2,
`docs/superpowers/specs/2026-07-10-hyperfocus-protection.md`）は席を外していると
気づけないため、この遷移だけサウンドで知らせるようにした。

## 変更1: 延長機能をコードから完全削除

- `scrpm/State/TimerStateManager.swift`: `extendWork()`、`extensionCount`、
  `tick()`/`finishWork()` の延長分岐（`workCompleted ? extensionDuration : workDuration`）を削除
- `scrpm/Views/BreakOverlayView.swift`: 「作業を延長する」ボタンを削除
- `scrpm/State/Durations.swift`: `extensionDuration`、`maxExtensions` を削除
- `workCompleted` フラグと `workAccumulatedDuration`（休憩時間を `duration` に混入させないための
  累積）は延長専用ではなく通常セッションの記録にも必要なため残した
- 削除の記録として `docs/superpowers/specs/2026-06-09-extend-work-timer-design.md` と
  `docs/superpowers/specs/2026-07-10-hyperfocus-protection.md`（F1節）の先頭に削除済み注記を追記
  （コード自体はコメントアウト等で温存せず、git履歴と注記のみをアーカイブとする）

## 変更2: 休憩中の2ボタンの表示タイミングを統一

- `scrpm/State/Durations.swift`: `stopButtonDelay`（10秒）を削除し、
  新規定数 `breakActionDelay: TimeInterval = 3 * 60` を追加
- `scrpm/Views/BreakOverlayView.swift` / `scrpm/Views/TimerView.swift`:
  「作業を再開する」「作業をやめる」を `if timerManager.remaining <= breakDuration - breakActionDelay`
  という単一条件でまとめ、休憩開始から3分間はどちらも非表示、3分経過後に同時表示にした
  （旧「やめる」の disabled/残り秒数カウントダウン表示は撤廃）
- メインウィンドウ（`TimerView.swift`）の breaking 表示にも同じ条件を適用し、オーバーレイ裏での
  抜け道を防いだ
- `docs/superpowers/specs/2026-07-10-hyperfocus-protection.md`（F4節）に変更済み注記を追記

### 検討したが不採用: Idle 中の自動再開ロジックの変更

当初「やめた後にPCを触っていると約5分で自動再開してしまう」問題として提起されたが、確認の結果
実際の要望は上記の非対称解消であり、`checkActivity()` の `.idle` 自動開始ロジック
（`idleActivationCount` 等）自体の変更は不要と判断し、スコープ外とした。

## 変更3: 休憩終了時のサウンド通知

- `scrpm/State/TimerStateManager.swift`: `finishBreak()`（休憩5分経過による自動再開の
  タイミングのみ）で通知音を再生する。手動で「作業を再開する」/「作業をやめる」を押した場合は
  鳴らさない（自分でクリックした行動なので通知不要という判断）
- 使用サウンド: "Sonar"（iOS/macOS の着信音の一つ）。`/System/Library/Sounds/` の
  `NSSound(named:)` 標準一覧には含まれておらず、実体は `ToneLibrary.framework`
  （プライベートフレームワーク）内の `Sonar.m4r`。そのため絶対パスを直接指定して
  `NSSound(contentsOfFile:byReference:)` で再生している
  （`private static let breakEndSoundPath` として `TimerStateManager.swift` に定義）
- リスク: 将来の macOS でこのファイルパスが変わる可能性があるが、見つからなければ
  `NSSound(contentsOfFile:)` は `nil` を返すだけで、鳴らないだけに留まりクラッシュしない

## 変更ファイル一覧

- `scrpm/State/Durations.swift`
- `scrpm/State/TimerStateManager.swift`
- `scrpm/Views/BreakOverlayView.swift`
- `scrpm/Views/TimerView.swift`
- `CLAUDE.md`
- `docs/superpowers/specs/2026-06-09-extend-work-timer-design.md`（削除済み注記のみ）
- `docs/superpowers/specs/2026-07-10-hyperfocus-protection.md`（削除済み・変更済み注記のみ）

## 検証

- `xcodebuild -project scrpm.xcodeproj -target scrpm -configuration Debug build` でビルド成功
- `swiftc -o /tmp/workload_tests scrpm/State/Durations.swift scrpm/State/WorkloadStats.swift scrpm/State/TimerPhase.swift scrpm/State/ScrpmStateWriter.swift tools/main.swift && /tmp/workload_tests` で既存テスト全パス
- 実機確認（`workDuration=70`, `breakDuration=30`, `breakActionDelay=5` に一時短縮）:
  延長ボタンが出ないこと、休憩開始5秒間は両ボタン非表示、5秒後に同時表示、
  30秒経過（自動再開）で "Sonar" が鳴ることを確認済み。確認後 `Durations.swift` を本番値
  （`workDuration=25*60`, `breakDuration=5*60`, `breakActionDelay=3*60`）に戻した
