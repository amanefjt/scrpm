# Scrpm — ポモドーロタイマー for macOS

Scrpm は、作業と休憩のサイクルを管理し、集中力を高めるための macOS 専用ポモドーロタイマーアプリです。
休憩時間になると、画面全体が心地よい休憩画面（フルスクリーンオーバーレイ）で覆われ、強制的にリフレッシュを促すのが特徴です。

---

## 📥 ダウンロード

[Releases ページ](https://github.com/amanefjt/scrpm/releases/latest) から `scrpm.zip` をダウンロードしてください。

---

## インストール・起動方法

このアプリは、個人開発の「署名なしアプリ」として直接配布されているため、macOS のセキュリティ機能（Gatekeeper）によって、普通にダブルクリックしただけでは起動できないようになっています。

以下の手順に沿って、インストールと初回起動を行ってください。

### 1. アプリケーションフォルダへの移動
1. ダウンロードした `scrpm.zip` をダブルクリックして解凍します。
2. 解凍された `scrpm.app`（または `scrpm`）を、Finder で **「アプリケーション」フォルダ** にドラッグ＆ドロップして移動します。

---

### 2. 初回起動手順（セキュリティ警告の回避）

普通にダブルクリックすると、以下の警告が表示されて起動できません。
> **「"scrpm"は開発元を検証できないため開けません。」**

この警告を回避するために、以下の手順で起動してください。

#### 【手順 A】右クリックから開く（一番簡単）
1. `アプリケーション` フォルダ内の `scrpm` アプリを **右クリック（または二本指タップ）** します。
2. メニューから **「開く」** を選択します。
3. 再び警告ダイアログが表示されますが、今回は **「開く」** というボタンが表示されますので、それをクリックします。
4. 一度この手順で起動すれば、次回からはダブルクリックだけで通常通り起動できるようになります。

#### 【手順 B】上記で開けない場合（ターミナルを使用）
macOSのバージョンや設定によっては、手順Aでも開けない場合があります。その場合は以下のコマンドを1度だけ実行してください。

1. Macの「ターミナル」アプリ（Finder の「アプリケーション」＞「ユーティリティ」フォルダ内にあります）を起動します。
2. 以下のコマンドをコピーして貼り付け、Enterキーを押します。
   ```bash
   xattr -cr /Applications/scrpm.app
   ```
3. その後、通常通りダブルクリックして起動できるか確認してください。

---

## 🛠️ 基本的な使い方

1. **作業の開始**
   * アプリを起動し、メイン画面の「作業開始」ボタンを押すと作業タイマーがスタートします（初期設定は15分）。
2. **短い休憩（スキップ不可）**
   * 1セット終えると自動的に短い休憩（初期設定は2分）に入り、画面全体が休憩用フルスクリーン画面で覆われます。
   * この休憩にはボタンが一切なく、スキップできません。時間が来ると自動的に次の作業セットが始まります。
3. **長い休憩**
   * 既定のセット数（初期設定は4セット）をこなすと、長い休憩（初期設定は10分）に入ります。
   * 開始からしばらく（初期設定は5分）経つと「作業を再開する」「作業をやめる」ボタンが表示されます。それまでは席を立って自由に過ごす時間です。
4. **時間のカスタマイズ**
   * 作業していない・休憩していないとき（Idle画面）に「設定」ボタンから、作業時間・短い休憩・長い休憩・セット数・長い休憩でボタンが出るまでの時間をそれぞれ変更できます。
   * 変更は次に始まる作業・休憩から反映されます。作業中・休憩中はこの画面を開けません。
5. **履歴の確認**
   * 「記録」ボタン（作業中は「記録を見る」）から、日別・週別・月別の作業実績を振り返ることができます。作業中に開いても、今まさに進行中のセットはまだ記録されていないため一覧には含まれません。

---

## 💻 開発者向け（ビルドと実行）

ソースコードからビルドして実行する場合は、以下の手順に従ってください。

### 前提条件
- macOS 14 以上
- Xcode 15 以上

### 動作確認用（Debugビルド、都度ビルドして直接起動）
コードを軽く動かして確認するだけなら Debug ビルドで十分。
```bash
xcodebuild -project scrpm.xcodeproj -target scrpm -configuration Debug build
open build/Debug/scrpm.app
```

### 普段使いのアプリを更新する（重要）

> [!IMPORTANT]
> **`xcodebuild` でビルドしただけでは `/Applications/scrpm.app`（Dock や Spotlight から起動している実体）は更新されません。**
> `build/Debug` または `build/Release` に成果物ができるだけで、`/Applications` へのコピーは別工程です。
> これに気づかず「コードを直したのにアプリの挙動が変わらない、再起動しても直らない」とハマりやすいので注意。

普段使っているアプリ（`/Applications/scrpm.app`）に変更を反映させたいときは、
Release ビルド → 起動中のアプリを終了 → `/Applications` に配置し直す → 起動、を
まとめて行うスクリプトを使う。

```bash
./tools/install.sh
```

このスクリプトがやっていること:
1. `xcodebuild -configuration Release build` で `build/Release/scrpm.app` を作る
2. `osascript -e 'quit app "scrpm"'` で起動中の scrpm を終了する
3. `/Applications/scrpm.app` を削除して、新しくビルドしたものをコピーする
4. `open /Applications/scrpm.app` で起動する

手動で同じことをする場合のコマンド列（スクリプトの中身と同じ）:
```bash
xcodebuild -project scrpm.xcodeproj -target scrpm -configuration Release build
osascript -e 'quit app "scrpm"'
rm -rf /Applications/scrpm.app
cp -R build/Release/scrpm.app /Applications/scrpm.app
open /Applications/scrpm.app
```

### 新しい Release を公開する（配布用 zip を作る）

```bash
xcodebuild -project scrpm.xcodeproj -target scrpm -configuration Release build
cd build/Release && zip -r scrpm.zip scrpm.app && cd ../..
gh release create v1.0.1 build/Release/scrpm.zip --title "v1.0.1" --notes "..."
```

`gh release create` の代わりに GitHub の Releases ページから手動でアップロードしてもよい。

---

## 📦 配布方法について

このアプリはフルスクリーンオーバーレイ（休憩画面）を実現するために App Sandbox を無効化しており
（`CODE_SIGNING_REQUIRED = NO` のアドホック署名）、その関係で App Store 配布はできない。
選べる配布方法はおおよそ次の2つ。

| 方法 | 必要なもの | 相手側の手間 |
|---|---|---|
| **アドホック署名のまま zip で渡す**（本リポジトリで採用） | なし | 初回だけ「右クリック→開く」または `xattr -cr` が必要（上記手順） |
| Developer ID 署名 + 公証（notarization） | Apple Developer Program（年 $99） | 通常どおりダブルクリックで起動できる |

数人の友人・同僚に配る程度なら、費用も手間もかからない前者で十分という判断。継続的に大人数へ
配りたくなったら後者を検討する（Sandbox 無効のままでも公証自体は可能）。

使う人ごとに `~/Library/Application Support/com.scrpm.app/` に独立したデータベースが
作られるので、複数人で使っても記録が混ざったり衝突したりする心配はない。

---

## リポジトリについて

https://github.com/amanefjt/scrpm

このリポジトリは公開にあたって単一コミットから始めています（開発途中のやり取りを含む
詳細な変更履歴は非公開のローカル履歴として別に保持）。
