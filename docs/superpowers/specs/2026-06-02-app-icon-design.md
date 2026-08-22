# scrpm アプリアイコン デザイン仕様

## 概要

scrpm（ポモドーロタイマー）の macOS アプリアイコンを SVG で生成し、Xcode の AppIcon.appiconset に組み込む。

## デザイン決定

### コンセプト
**砂時計** — 時間・集中・休憩のサイクルを視覚的に表現。

### 形状
- **ベース**: スクワークル（角丸の正方形、rx ≒ アイコンサイズの 27%）
- 白地 + 薄いドロップシャドウ（sage green 系）

### カラー
| 要素 | 値 |
|------|-----|
| ベース背景 | `#ffffff` → `#f4f9f7`（微グラデーション） |
| 砂時計・上半分 | `#8cc5b0` → `#6daa94`（縦グラデーション） |
| 砂時計・下半分 | `#a8d5c4` → `#8cc5b0`（縦グラデーション）、opacity 55% |
| 上下のバー | `#6daa94` / `#8cc5b0` |
| 落下する砂の粒 | `#b8ddd0`（3段階フェードアウト） |
| ドロップシャドウ | `#7aad9d` opacity 30% |

### 砂時計の構造
- 上三角形: 頂点が下向き（▽）、頂点 = アイコン中央
- 下三角形: 頂点が上向き（△）、頂点 = アイコン中央
- 上下に水平バー（stroke-linecap: round）
- 砂の落下: 中央直下に円を 3 個（サイズ・opacity を段階的に縮小）

### サイズ別 rx（角丸半径）
| サイズ | rx |
|--------|----|
| 1024px | 276px |
| 512px  | 138px |
| 256px  | 69px |
| 128px  | 34px |
| 64px   | 17px |
| 32px   | 9px |
| 16px   | 5px |

## 生成方法

1. Python スクリプト（`tools/generate_icon.py`）で各サイズの SVG を生成
2. `cairosvg`（pip install cairosvg）で SVG → PNG に変換
   - `rsvg-convert`（brew install librsvg）でも可
3. PNG を `scrpm/Assets.xcassets/AppIcon.appiconset/` に配置
4. `Contents.json` を更新

## 必要な PNG サイズ（macOS）

| ファイル名 | サイズ |
|------------|--------|
| icon_16x16.png | 16×16 |
| icon_16x16@2x.png | 32×32 |
| icon_32x32.png | 32×32 |
| icon_32x32@2x.png | 64×64 |
| icon_128x128.png | 128×128 |
| icon_128x128@2x.png | 256×256 |
| icon_256x256.png | 256×256 |
| icon_256x256@2x.png | 512×512 |
| icon_512x512.png | 512×512 |
| icon_512x512@2x.png | 1024×1024 |

## 成功基準

- 全サイズで砂時計が視認できる（32px 以上）
- 16px ではシルエットのみでも識別可能
- Xcode ビルドが通り、アプリが正しいアイコンを表示する
