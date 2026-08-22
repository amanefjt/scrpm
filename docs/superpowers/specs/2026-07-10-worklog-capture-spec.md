# worklog-capture — スクリーンショット日報ツール 仕様

> **注**: これは scrpm とは**別プロジェクト**の spec。実装時は新しいリポジトリ
> （例: `~/Code/worklog`）を作り、この spec をコピーして起点にする。
> scrpm 側リポジトリには置き場所の都合で保管しているだけ。
>
> **scrpm 本体への変更を1件含む**（C1 が scrpm の稼働状態を読むため）。
> 「scrpm 側の変更」セクション参照。scrpm リポジトリ側の別タスクとして実装する。

## 背景・目的

作業ログ（その日の午前・午後に何をしたか + 作業時間）を手で書く運用は続かない
（ADHD ではセルフモニタリングの手動記録は最も脱落しやすい介入であることが研究上
ほぼ確定）。記録を「書く」から「発生させる」に変える:

1. scrpm が Working 中の間だけ、毎分画面をキャプチャしてローカル OCR → JSONL に蓄積
   （完全自動・無人）
2. 日々の記録は蓄積ログ + scrpm の作業時間記録から、ローカルの Swift CLI が
   1日1行の CSV に要約・追記する
3. 振り返りは**その CSV を Google スプレッドシート等に貼り付けて眺めるだけ**に
   設計する（毎日の義務を作らない）

参考: けんすう氏の同型ツール（AppleScript + screencapture + Vision OCR + JSONL、
OCR はローカルで割り切る。スクショ画像は OCR 後に破棄）。

過去の手書き運用は「月・日・曜・午前内容・午前時間・午後内容・午後時間・分類・合計」
の列を持つスプレッドシートで、日ごとに1行ずつ追記していく形だった。今回のツールは
「分類」列（作業/仕事の主観的区別を含み自動化になじまない）を除いた形で、この体験を
自動生成する。

## 設計方針

- **ローカルファースト**: スクショ・OCR テキストは一切クラウドに送らない。
  要約生成も含めて全工程がローカルで完結する（後述、Apple Foundation Models
  framework を使うため）
- **依存最小**: すべてのコンポーネントが**単一ファイルの Swift CLI**（swiftc で
  コンパイル、外部パッケージゼロ）。ScreenCaptureKit / Vision / AppKit /
  FoundationModels はすべて OS 標準。Python + pyobjc 案は依存が重くなるため採らない
- **記録の摩擦ゼロ**: launchd LaunchAgent で自動起動。ユーザーが何かを「する」必要が
  あるのは日次コマンドを叩いて CSV を眺めるときだけ

## コンポーネント

### C1. キャプチャ CLI（`worklog-capture`、Swift 単一ファイル）

1 回の起動で 1 キャプチャを行い終了する（stateless。常駐しない）:

1. **スキップ判定**（該当したら何も書かず終了）:
   - スクリーンロック中 / スクリーンセーバ中
   - 最終ユーザー入力から `idleSkipThreshold = 120` 秒以上経過
     （`CGEventSource.secondsSinceLastEventType`。離席中の同一画面を延々記録しない）
   - 一時停止フラグファイル `~/.worklog/paused` が存在する
   - 最前面アプリが除外リストに含まれる
   - **scrpm が Working 中でない**（下記「scrpm 連動」参照）
2. 最前面アプリ名・ウィンドウタイトルを取得
   （`NSWorkspace.shared.frontmostApplication` + `CGWindowListCopyWindowInfo`）
3. メインディスプレイ全体をキャプチャ（CGImage をメモリ上で扱い、**画像ファイルは
   一切ディスクに書かない**）
4. Vision（`VNRecognizeTextRequest`、`recognitionLanguages = ["ja", "en"]`、
   `recognitionLevel = .fast`）で OCR
5. 1 行の JSON を `~/.worklog/logs/YYYY-MM-DD.jsonl` に追記:

```json
{"ts": "2026-07-10T14:03:00+09:00", "app": "Preview", "title": "some-paper.pdf", "text": "OCR結果..."}
```

- 除外リスト・各種閾値はソース冒頭の定数にまとめる（ハードコード分散禁止）:
  - `excludedBundleIDs`: 初期値 `["com.apple.mail"]`（事務メールの本文を蓄積しない。
    運用しながら追加）
  - `idleSkipThreshold = 120`、`logRetentionDays = 90`、`workStartGracePeriod = 60`
- 古いログの削除: 起動時に `logRetentionDays` より古い JSONL を削除
- **必要権限**: 画面収録（TCC）。初回実行時に macOS がダイアログを出す。
  システム設定 → プライバシーとセキュリティ → 画面収録 で許可が必要なことを
  README に明記する

#### scrpm 連動（Working 中のみキャプチャ）

作業開始ボタンを押した直後はまだウィンドウを切り替えている最中で、メインの作業画面に
いない可能性が高い。また Idle 中・Break 中の非作業画面（休憩中の動画視聴など）を撮って
しまう懸念もある。これを避けるため、scrpm の稼働状態と連動させる:

1. `~/.worklog/scrpm-state.json` を読む（スキーマは「scrpm 側の変更」参照）
2. `phase` が `"working"` でなければスキップ
3. `phase == "working"` でも、`since` から `workStartGracePeriod`（60秒）以内なら
   スキップ（Working 開始直後のウィンドウ切り替え中を確実に避ける猶予期間）
4. **fail-closed**: ファイルが存在しない・パースできない・scrpm が起動していない
   等、状態が不明な場合は「Working 中ではない」とみなしスキップする
   （誤って無関係な画面を撮るリスクより記録漏れの方が安全側）

### scrpm 側の変更（scrpm リポジトリの別タスク）

worklog-capture が scrpm の稼働状態を読めるようにするため、scrpm 本体に軽量な書き出し
機能を追加する:

- `TimerStateManager` の `phase` が変化するたびに `~/.worklog/scrpm-state.json` へ
  以下を書き出す:
  ```json
  {"phase": "working", "since": "2026-07-14T14:03:00+09:00"}
  ```
- `phase` は `idle` / `working` / `breaking` のいずれか。`since` はその phase に
  入った時刻（ISO 8601）
- 書き込み失敗（`~/.worklog/` ディレクトリ不存在など）は無視してよい。scrpm 本体の
  動作に影響を与えない。ディレクトリは worklog-capture 側が作る前提
- scrpm の `CLAUDE.md` にもこの仕様を追記する

### C2. launchd LaunchAgent

- `~/Library/LaunchAgents/com.shufujita.worklog-capture.plist`
- `StartInterval = 60`（毎分 1 回起動。常駐プロセスを持たないので堅牢）
- インストール/アンインストールは `make install` / `make uninstall`
  （swiftc コンパイル + plist 配置 + `launchctl bootstrap` をまとめる）

### C3. 日次記録生成 CLI（`worklog-report`、Swift 単一ファイル）

C1 と同じ思想（単一ファイル・外部パッケージゼロ）の Swift CLI。Claude Code スキルは
使わない（後述「オンデバイス要約」参照。要約自体をローカルで完結させるため）。

- `worklog-report daily [日付]`（省略時は今日）:
  1. その日の JSONL（`~/.worklog/logs/YYYY-MM-DD.jsonl`）を読む
  2. 正午（12:00）を境に午前/午後に分割
  3. 各時間帯について、app/title 単位で重複除去・集計してから
     Foundation Models framework（オンデバイス要約、後述）に渡し、
     短いキーワード列挙（カンマ区切り、数個程度）を生成する
  4. scrpm の SwiftData ストアから、その日の実作業時間（分）を午前/午後別に集計する
     （既存方針: `sqlite3` で読み取り専用アクセス。WAL ロック競合を避けるため
     `/tmp` にコピーしてから開く。パス・テーブル名は実装時に実機で確認して
     README に記録する）
  5. 1 行を `~/.worklog/reports/worklog.csv` に追記（同じ日付の行が既にあれば上書き）

CSV の列（旧手書き運用から「分類」列を除いた構成）:

```
月,日,曜,午前内容,午前時間,午後内容,午後時間,合計
7,14,火,"Antigravity、レポート作成",120,"会議、メール確認",90,210
```

- 実行は手動（自動化はスコープ外。まずは自分でコマンドを叩く運用から）
- `worklog-report weekly` のような週次コマンドは持たない。CSV は日ごとの追記で
  1本の連続ログになるので、週の振り返りは Google スプレッドシート等に貼り付けて
  直近の行を眺めれば足りる

#### オンデバイス要約（Apple Foundation Models framework）

- `import FoundationModels` でオンデバイス LLM を呼び出す。ネットワーク通信なし
- コンテキスト長の制約があるため、OCR テキストをそのまま渡さず、
  事前に app/title 単位で重複除去・集計したものを渡す
- 要件（macOS バージョン、Apple Intelligence 対応デバイス等）は実装時に確認し
  README に明記する
- 要約品質はクラウド LLM に劣る可能性がある。運用しながら許容できるか判断する

## スコープ外（YAGNI）

- **Google カレンダー / Google スプレッドシート連携**（別段階の spec として
  フェーズ2で扱う）。理由:
  - どちらも Swift 公式 SDK がなく REST API を直接叩く必要があり、
    OAuth2 認証フロー（ブラウザでの初回同意 + リフレッシュトークン管理）という
    コア機能とは毛色の異なる実装が要る
  - Calendar 読み取りと Sheets 書き込みは同じ OAuth 基盤を共有できるため、
    まとめて1つの拡張フェーズとして実装するのが効率的
  - コア機能（キャプチャ・OCR・オンデバイス要約・CSV 追記）はローカル完結・
    外部認証ゼロで単独リリース・単独運用開始できる。Google 連携をコアに混ぜると
    コア機能の完成がそちらの実装状況に引きずられる
  - 着手する際は CSV の列や `worklog-report` の内部構造に予定情報の列を
    足しやすいか確認するところから始める（今回は列追加を見越した抽象化まではしない）
- Slack 等その他の外部ソース統合
- スクショ画像の保存・閲覧機能（画像はそもそもディスクに書かない）
- 日次コマンドの自動生成スケジューリング（まずは手動で `worklog-report daily` を
  叩く運用から。続かなければ launchd + 自動実行を検討）
- マルチディスプレイの全画面キャプチャ（まずメインディスプレイのみ。足りなければ拡張）

## 成功基準

- LaunchAgent 導入後、操作ゼロで JSONL が毎分（scrpm が Working 中のみ）蓄積される
- ロック中・離席中・除外アプリ使用中・scrpm が Working 中でない間はログが増えない
- 1 日分の JSONL サイズが常識的範囲（数 MB 以下）に収まる
- `worklog-report daily` が CSV に1行を追記し、旧手書き運用と同等の粒度
  （午前/午後それぞれ短いキーワード列挙 + scrpm 実作業時間）で読んで納得できる
- スクショ画像がディスク上に残らない。ログ・要約生成を含め全工程がクラウドに
  送信されない（Foundation Models framework によりオンデバイスで完結）
