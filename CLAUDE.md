# scrpm — ポモドーロタイマー

## 技術スタック
- SwiftUI + AppKit (macOS 14+)
- SwiftData（ローカル永続化）
- Swift Charts（履歴棒グラフ）
- 外部依存なし

## ビルド
```bash
# Xcode が active developer directory に設定されている必要がある
# sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
# 初回は xcodebuild -runFirstLaunch も必要

xcodebuild -project scrpm.xcodeproj -target scrpm -configuration Debug build

# 起動（動作確認用。build/Debug から直接起動するだけ）
open build/Debug/scrpm.app
```

**普段使っているアプリ（`/Applications/scrpm.app`）はこれでは更新されない。**
`xcodebuild` は `build/Debug` または `build/Release` に成果物を作るだけで、
`/Applications` へのコピーは別工程。「コードを直したのに挙動が変わらない、
再起動しても直らない」は大抵このコピー漏れが原因（2026-08-10 に実際にハマった）。
普段使いのアプリに反映させたいときは `tools/install.sh` を使う
（Release ビルド → 起動中の scrpm を終了 → `/Applications/scrpm.app` を置き換え → 起動、を一括実行）。
```bash
./tools/install.sh
```

## サイクル設計（2026-08-17 に 25/5 から変更）

**15分作業 + 2分の短い休憩を1セット**とし、**4セット終えたら10分の長い休憩**を取る。
短い休憩は**スキップできない**（ボタンを一切出さない）。長い休憩は「席を立って何をしてもよい」時間。

変更の根拠:
- マイクロブレイクのメタ分析（Albulescu et al. 2022, PLOS ONE, 22研究）では 10分以下の休憩で
  活力 d=.36 / 疲労低減 d=.35。27〜40秒の休憩でも効果が観測されており、**2分は下限を十分超える**
- 同メタ分析のサブグループ分析で、**認知負荷の高いタスクの成績回復には10分超の休憩が必要**。
  つまり2分休憩だけでは足りず、**長い休憩とセットで初めて成立する**
- vigilance decrement は time-on-task が伸びるほど成績のばらつき（state instability）が増える。
  25分より15分の方が「ばらつきが出る前に切る」設計になる
- 一方 15分を下回ると立ち上げコストの比率が上がる（ADHD特性ではタスク切替コストが大きい）。
  復帰期は15分、慣れたら20分に伸ばす想定。

作業比率は 25/5 の 83% から、(15+2)×3 + 15 + 10 = 76分中60分＝**79%** に下がる。

**時間はUIから変更できる**（2026-08-22 追加）。Idle画面の「設定」ボタン→`SettingsView`で
作業時間・短い休憩・長い休憩・セット数・`longBreakActionDelay` をすべて変更可能。
値は UserDefaults に保存され（`Durations.swift` の各グローバル変数が読み書きする computed
property になっている）、コード上の `let` は変更不可の値（`minimumRecordDuration` 等）にのみ残す。
設定画面は Idle のときしか開けない（作業中・休憩中に値が変わると
「次のフェーズから反映」という前提が崩れるため）。Idle 以外に遷移したら
`SettingsView` 側の `.onChange(of: timerManager.phase)` で自動的にタイマー画面へ戻す。

**長い休憩を 15分ではなく 10分にした理由**（2026-08-17）: 上の「10分超が必要」は、
高負荷タスクのサブグループで有意差が出なかったという null result からの推論にすぎず、
「15分が最適」と直接測った研究ではない。当人が15分は長すぎる（そわそわする）と判断したため、
体感を優先して境界線上の10分にした。合わなければ `Durations.swift` の1行で戻せる。

## 状態遷移
```
[Idle] ──「作業開始」──────────────→ [Working]
[Idle] ──約5分の入力継続を検出────→ [Working]（無音自動開始）
[Working] ──15分経過（4セット未満）──→ [ShortBreak]（セッションを即記録）
[Working] ──15分経過（4セット目）────→ [LongBreak]（セッションを即記録）
[Working] ──「作業をやめる」──→ [Idle]（中断セッションとして記録・セット数リセット）
[Working] ──約5分の無操作を検出──→ [Idle]（無音自動中断・同上）
[ShortBreak] ──2分経過──→ [Working]（無音で自動再開。ボタンは一切出さない＝スキップ不可）
[LongBreak] ──15分経過──→ [Idle]（セット数リセット）
[LongBreak] ──「作業を再開する」（休憩開始から longBreakActionDelay 秒後に表示）──→ [Working]
[LongBreak] ──「作業をやめる」（同上）──→ [Idle]
```

長い休憩の後に自動開始しないのは、長い休憩が「席を立つ時間」だから
（戻っていないのに作業時間が計上されるのを避ける）。戻ってキーボードを触り続ければ
既存の入力検出が約5分で自動開始する。

**「休憩をスキップできない」ことの非常口**: 体調が急変したときは、カウントダウンを放置して
その場を離れればよい。休憩満了 → 自動再開 → 約5分の無操作検出 → `stopWork()` で Idle に戻る。
そのため「作業をやめる」に遅延表示のような仕掛けは入れていない。

定数: `workDuration = 900s`、`shortBreakDuration = 120s`、`longBreakDuration = 600s`、`setsPerCycle = 4`、`minimumRecordDuration = 60s`、`longBreakActionDelay = 300s`、`idlePollingInterval = 30s`、`idleActivationCount = 10`、`workInactivityDeactivationCount = 10`（各≒5分）、`restDayThreshold = 1800s`、`noRestWarningDays = 10`

## データモデル (SwiftData)
```swift
@Model WorkSession {
    startTime: Date
    endTime: Date
    duration: TimeInterval   // 実作業秒数
    completed: Bool          // 15分完走=true / 中断=false
    note: String = ""        // そのセッションで何をやったか。休憩中に入力する（未入力可）
}
```
記録条件: 完走した作業セット（常に記録）、および Working が 60秒以上続いた中断セッション

`note` はデフォルト値を持つので、SwiftData の軽量マイグレーションで既存レコードは空文字になる
（明示的なマイグレーションプラン不要）。

**保存先**: `~/Library/Application Support/com.scrpm.app/default.store`（`ScrpmApp.swift` で
`ModelConfiguration(url:)` により明示指定）。`build/Debug` や `/Applications/scrpm.app` とは
無関係な場所にあるため、リビルドや `tools/install.sh` での再配置では記録は消えない。
パスを明示せず `ModelContainer(for: WorkSession.self)` とだけ書くと、SwiftData（非サンドボックス
アプリ）は `~/Library/Application Support/default.store` という**バンドルIDに紐付かない共有パス**
をデフォルトで使ってしまい、他の非サンドボックス SwiftData アプリと衝突しうる罠がある
（2026-08-10、この罠に気づいて `com.scrpm.app` サブディレクトリに固定する修正を入れた。
旧パスに残っていた既存データは初回起動時に自動でコピー移行する `migrateLegacyStoreIfNeeded`
を `ScrpmApp.swift` に実装済み。旧ファイルは削除せず残す設計）。

## ファイル構成
```
scrpm/
├── ScrpmApp.swift                   # @main, ModelContainer + OverlayWindowController 初期化
├── Models/WorkSession.swift         # SwiftData モデル
├── State/
│   ├── Durations.swift              # ユーザー設定値（UserDefaults 経由）+ 変更不可の定数
│   ├── TimerPhase.swift             # idle/working/shortBreak/longBreak enum
│   ├── TimerStateManager.swift      # @Observable 状態機械 + セッション記録
│   ├── WorkloadStats.swift          # 負荷集計の純関数、SwiftData 非依存
│   ├── WorkLog.swift                # 作業ログのテキスト整形（純関数）、SwiftData 非依存
│   └── WorkLogExporter.swift        # 作業ログのファイル書き出し
├── Views/
│   ├── RootView.swift               # .timer / .history / .settings ルーティング
│   ├── TimerView.swift              # 4状態のメインUI + セット進捗インジケータ
│   ├── SettingsView.swift           # 時間・セット数の設定画面（Idleのときのみ開ける）
│   ├── CountdownLabel.swift         # SF Mono 大型カウントダウン
│   ├── BreakOverlayView.swift       # フルスクリーンオーバーレイ内コンテンツ
│   ├── SessionNoteField.swift       # 作業内容の入力欄（メイン/オーバーレイ共用）
│   ├── WorkLogWindow.swift          # 作業ログ専用の独立ウィンドウ
│   ├── RestWarningBanner.swift      # 休養日ゼロ警告
│   └── History/
│       ├── HistoryView.swift        # 日/週/月タブ + 左右ナビ
│       ├── DaySummaryView.swift     # 日別: 合計時間・完走数・中断数 + セッション一覧
│       ├── WeekChartView.swift      # 週別: 7日棒グラフ
│       └── MonthChartView.swift     # 月別: 日ごと棒グラフ
└── Overlay/
    └── OverlayWindowController.swift  # NSWindow (level=screenSaver) 全スクリーン管理
```
`tools/main.swift`（swiftc テストハーネス。`WorkloadStats.swift` / `WorkLog.swift` /
`ScrpmStateWriter.swift` / `TimerPhase.swift` を SwiftData 非依存で単体検証する）

## フルスクリーンオーバーレイ仕様
- `toggleFullScreen(nil)` で独立した fullscreen Space を作成し全ディスプレイを覆う
- `collectionBehavior = [.fullScreenPrimary]`、`styleMask = [.titled, .fullSizeContentView]`
- `OverlayWindow: NSWindow` サブクラスで `animationResizeTime → 0`（遷移アニメーション短縮）
- App Sandbox 無効（`CODE_SIGNING_REQUIRED = NO`）
- オーバーレイ内 SwiftUI ビューは `.colorScheme(.dark)` を適用（ダーク背景でボタンを正しく描画するため）
- `OverlayWindowController` は `TimerStateManager` への参照を持たず、`show(timerManager:)` で都度注入する設計（循環参照を避けるため）

## オーバーレイ実装の既知の罠
- **`.canJoinAllSpaces` + `.screenSaver` レベルは native fullscreen Space では機能しない**
  - `CGWindowListCopyWindowInfo` にも出ない（Space に入れていない）
  - `CGDisplayCapture` も解決しない（3本指スワイプが壊れる副作用あり）
  - `NSApp.activate(ignoringOtherApps:)` も無効（アプリが inactive のまま）
  - 唯一の解決策: `toggleFullScreen` で独自 Space を作る
- **スクリーンショットでオーバーレイが写らない**: `.screenSaver` レベル以上のウィンドウは macOS スクリーンショットでキャプチャされない。「動いていない」と誤解しやすい
- **`hide()` 時のクラッシュ**: `window.close()` を SwiftUI state 変化と同じサイクルで呼ぶと `@Observable` の二重解放で `EXC_BAD_ACCESS`。`contentView = nil` を先に呼んで SwiftUI の観測を切り、`DispatchQueue.main.async` + `isReleasedWhenClosed = false` で close を defer することで解決

## 休憩オーバーレイのUI仕様
- **短い休憩（2分）はボタンを一切表示しない**。スキップさせないための設計であり、
  「作業をやめる → 作業を再開」で無理やり抜ける抜け道も同時に塞いでいる
- **長い休憩（10分）は `longBreakActionDelay`（5分）経過後**（`remaining <= longBreakDuration - longBreakActionDelay`）に
  「作業を再開する」「作業をやめる」が同時に表示される（意思決定を急かさない設計）
- メインウィンドウ（`TimerView.swift`）の休憩表示も同じ条件でボタンを表示する（オーバーレイ裏での抜け道を防ぐため）
- 休憩中は `SessionNoteField` で直前のセッションの作業内容を入力できる。
  確定操作は要求せず、**休憩中はいつでも書き直せる状態のまま**にしておく。
  `TimerStateManager.noteTarget` が対象セッションを保持し、フェーズ遷移時に save + 再書き出しする

## 作業ログ（2026-08-17 追加）
目的は RPE（報酬予測誤差）が減衰しやすい特性への対処。「大きな論文を書き上げる」ではなく
「今日この15分で文献のここを整理した」という**小さな報酬を可視化する**ためにある。

- 記録画面（`DaySummaryView`）にセッション一覧を出す。`12:12-12:27 読み方第1章を読む` 形式。
  この一覧の作業内容は**あとから編集できる**（休憩中に入力しそびれた分を補えるようにするため）
- **作業中（Working）でも記録画面を開ける**（2026-08-22 追加）。`TimerView` の Working 画面に
  「記録を見る」ボタンを常設。進行中のセットは `finishWork()` の時点でしか記録されないので、
  開いても当然そのセット自体は一覧に含まれない（特別な除外処理は不要）
- **独立ウィンドウ**（`WorkLogWindow.swift`、⌘⇧L）でログだけを開ける。
  「研究室で作業 → 家で夕方その日のログを日記にまとめる」という使い方のため
- 「全部コピー」で素のテキストをクリップボードへ

### なぜ DB ではなくテキストを同期するのか
別マシンとログを共有したくなるが、**SwiftData の SQLite をクラウド同期フォルダに置いてはいけない**。
`.store` / `.store-wal` / `.store-shm` の3ファイルの整合性で成り立っており、同期クライアントは
これを原子的に扱わないので DB が壊れる。本来の解である CloudKit 同期はエンタイトルメントを
要求するが、本アプリはフルスクリーンオーバーレイのために App Sandbox 無効・アドホック署名
（`CODE_SIGNING_REQUIRED = NO`）にしているので使えない。

そこで **DB を正本、テキストを派生物**とする。`WorkLogExporter` が書き出し先ディレクトリ
（`UserDefaults` の `workLogExportDirectory`、未設定なら書き出さない）に
`2026-08-17.md` を置く。**当日分を丸ごと書き直す冪等な方式**なので、途中で落ちてもファイルは壊れない。
別マシンからは読むだけで済み、DB を同期する必要がなくなる。
書き出しの契機はセッション記録時と `finalizeNote()`（作業内容は記録より後に入力されるため）。

## SourceKit 誤検知
- 同一モジュール内のグローバル定数（`shortBreakDuration` 等）に "Cannot find in scope" が出ることがある
- ビルドが通れば無視してよい

## テスト用タイマー短縮
`Durations.swift` の値を以下に変更するとオーバーレイを素早く確認できる。
`workDuration = 70` は `minimumRecordDuration = 60` を超えないと記録されないため 70 以上にすること。

```swift
let workDuration: TimeInterval = 70          // 本番: 15 * 60
let shortBreakDuration: TimeInterval = 10    // 本番: 2 * 60
let longBreakDuration: TimeInterval = 30     // 本番: 15 * 60
let longBreakActionDelay: TimeInterval = 5   // 本番: 5 * 60
let setsPerCycle: Int = 2                    // 本番: 4（長い休憩まで待たずに済む）
```

`idlePollingInterval = 5` / `idleActivationCount = 3` で自動開始を素早く確認できる。
Working 中の自動中断（無操作検出）を確認する場合は `workInactivityDeactivationCount = 3` も合わせて短縮する
（`idlePollingInterval = 5` なら 15 秒の無操作で自動中断する）。

テスト後は必ず本番値に戻すこと。

## オーバーレイ表示タイミング
`ScrpmApp` が `timerManager.phase` の変化を `.onChange` で監視し、
`newPhase.isBreak`（shortBreak / longBreak）になったら `overlayController.show()`、それ以外で `hide()`。

## アプリ終了時の処理
`NSApplication.willTerminateNotification` を購読し、Working 中なら中断セッションとして記録、
休憩中なら入力途中の作業内容を保存する（`recordSessionIfNeeded()`）。

## セッション記録の仕組み（2026-08-17 に大幅簡素化）
**1セット＝1レコード**。`finishWork()` の時点で即座に記録する。

以前は「休憩をまたいだ連続作業」を1レコードにまとめるため、`workCompleted` フラグと
`workAccumulatedDuration`（休憩時間が `duration` に混入しないよう作業時間だけを累積する）を
持ち回して `stopWork()` / `resumeWork()` / `finishBreak()` で記録していた。作業ログが
セッション単位の時刻を必要とするようになったため、この累積の仕組みは**丸ごと不要になり削除した**。

- 完走セッション: `duration = workDuration`、`endTime = startTime + workDuration`。
  wall-clock（`phaseStartedAt` からの経過）でタイマーを回している都合上、スリープを跨ぐと
  経過時間が飛ぶ。定義上ちょうど workDuration である完走セッションは実測値を使わないことで、
  作業ログの時刻表示が破綻しないようにしている
- 中断セッション: 実測値。`minimumRecordDuration`（60秒）未満は記録しない
- `completedSets`: サイクル内で完走したセット数。`setsPerCycle` に達したら長い休憩に入り、
  長い休憩を抜けるときに 0 に戻す。中断（`stopWork()`）でもサイクルは崩れるので 0 に戻す

## 過集中保護（2026-07 追加）
- 短い休憩の満了後は Idle に戻らず次のセットを自動開始（`finishBreak()` → `startWork()`）。
  長い休憩の満了後は Idle に戻す（席を立っている前提のため。2026-08-17 変更）。
  どちらも遷移自体は無音だが、席を外していると気づけないため `finishBreak()` 内で "Sonar" 着信音を鳴らす。
  手動で「作業を再開する」/「作業をやめる」を押した場合は鳴らさない（自分でクリックした行動なので通知不要）
  - "Sonar" は `/System/Library/Sounds/` の標準音一覧には無く、`ToneLibrary.framework`
    （プライベートフレームワーク）内の `Sonar.m4r` を絶対パスで直接参照している
    （`NSSound(named:)` は使えない）。将来の macOS でパスが変わったら鳴らなくなるだけで
    クラッシュはしない
- Idle 中は `CGEventSource.secondsSinceLastEventType` を 30 秒間隔でポーリングし、
  連続 10 回（約5分）入力を検出したら `startWork()` を自動呼び出し（誤検出は許容する設計）
- Working 中は同じポーリングで逆に無操作を検出する。連続 `workInactivityDeactivationCount`
  回（約5分）無操作が続いたら `stopWork()` を自動呼び出し、中断セッションとして記録して
  Idle に戻す（休憩中は対象外。`finishWork()` で監視を停止する）
- Idle/Working の監視は `startActivityMonitor()` / `stopActivityMonitor()` /
  `checkActivity()` に統合されている（`TimerStateManager.swift`）
- 週次負荷: 履歴の週タブに過去4週平均を表示。昨日までの 10 日間に休養日
  （日合計 < 30分）がなければ TimerView / HistoryView に警告バナー
- 負荷集計・状態ファイル・作業ログのテスト: `swiftc -o /tmp/workload_tests scrpm/State/Durations.swift scrpm/State/WorkloadStats.swift scrpm/State/TimerPhase.swift scrpm/State/ScrpmStateWriter.swift scrpm/State/WorkLog.swift tools/main.swift && /tmp/workload_tests`
- 仕様: docs/superpowers/specs/2026-07-10-hyperfocus-protection.md

## worklog-capture 連携（2026-07 追加、2026-07-16 時点で worklog-capture 側は凍結中）

**2026-07-16 時点で `worklog-capture` プロジェクトは運用停止（凍結）中。** 理由は
OCR 要約が実用に耐えず、確実に価値があった「作業時間の自動集計」は scrpm 単体で
完結しているため（詳細: `~/Code/adhdworklog/docs/2026-07-16-worklog-capture-retrospective.md`）。
以下の書き出し機能自体は軽量・無害（読み手がいなくても実害なし）なので scrpm 側は
削除せず残している。

`TimerStateManager` の phase が変化するたびに
`~/.worklog/scrpm-state.json` へ `{"phase": "...", "since": "<ISO8601>"}` を書き出す
（`ScrpmStateWriter.swift`）。別プロジェクト `worklog-capture`
（`docs/superpowers/specs/2026-07-10-worklog-capture-spec.md`）が、scrpm が
Working 中かどうかを判定するために読む。

- 書き込み失敗（`~/.worklog/` ディレクトリ不存在など）は無視する。scrpm 本体の
  動作に影響を与えない
- `~/.worklog/` ディレクトリ自体は scrpm 側では作らない（worklog-capture 側の責務）
- **短い休憩・長い休憩はどちらも `"breaking"` として書き出す**（`ScrpmStateWriter.phaseString`）。
  読み手は「Working かどうか」だけを知りたいので休憩の種類を区別する必要がなく、
  既存の 3 値フォーマットとの互換も保てる。この「作業ログ」（`~/.worklog/`）は
  上の「作業ログ書き出し」（`WorkLogExporter`）とは別物なので混同しないこと
