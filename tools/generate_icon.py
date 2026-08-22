#!/usr/bin/env python3
"""scrpm app icon generator — hourglass on white squircle."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

# ---- カラー定義 ----
WHITE        = (255, 255, 255, 255)
SAGE_DARK    = (109, 170, 148, 255)   # #6daa94  上バー・上三角暗部
SAGE_MID     = (140, 197, 176, 217)   # #8cc5b0  上三角
SAGE_LIGHT   = (168, 213, 196, 140)   # #a8d5c4  下三角（opacity 55%）
SAGE_BAR_BOT = (140, 197, 176, 255)   # 下バー
SAND         = (184, 221, 208)         # 砂の粒（opacityは個別）
SHADOW_CLR   = (122, 173, 157)        # ドロップシャドウ色

SCALE = 4  # スーパーサンプリング倍率（アンチエイリアス用）

# macOS で必要な (ファイル名, 実ピクセルサイズ) のリスト
SIZES = [
    ("icon_16x16.png",      16),
    ("icon_16x16@2x.png",   32),
    ("icon_32x32.png",      32),
    ("icon_32x32@2x.png",   64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png", 1024),
]


def draw_icon(size: int) -> Image.Image:
    """size × size の RGBA アイコンを返す（スーパーサンプリングなし）。"""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    rx = max(4, int(size * 0.27))   # スクワークル角丸半径

    # ── 白背景（角丸） ──
    draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=rx, fill=WHITE)

    # ── 砂時計の座標 ──
    margin = int(size * 0.215)      # 左右余白
    top_y  = int(size * 0.215)      # 上バー Y
    bot_y  = int(size * 0.785)      # 下バー Y
    cx     = size // 2              # 中心 X
    mid_y  = size // 2              # くびれ Y

    # ── 上三角形（頂点が下向き ▽）：グラデーション風に2層で表現 ──
    top_pts = [(margin, top_y), (size - margin, top_y), (cx, mid_y)]
    draw.polygon(top_pts, fill=SAGE_MID)
    # 上 1/3 に暗め色を重ねてグラデーション感を出す
    grad_y = top_y + (mid_y - top_y) // 3
    grad_pts = [(margin, top_y),
                (size - margin, top_y),
                (size - margin - (size - margin - cx) // 3, grad_y),
                (margin + (cx - margin) // 3, grad_y)]
    dark_fill = (*SAGE_DARK[:3], 120)
    draw.polygon(grad_pts, fill=dark_fill)

    # ── 下三角形（頂点が上向き △）: opacity 55% 相当 ──
    bot_pts = [(margin, bot_y), (size - margin, bot_y), (cx, mid_y)]
    draw.polygon(bot_pts, fill=SAGE_LIGHT)

    # ── 上下バー ──
    bw = max(2, int(size * 0.028))  # バー幅
    draw.line([(margin, top_y), (size - margin, top_y)],
              fill=SAGE_DARK, width=bw)
    draw.line([(margin, bot_y), (size - margin, bot_y)],
              fill=SAGE_BAR_BOT, width=bw)

    # ── 落下する砂の粒（くびれ直下 3 個）──
    # 16px / 32px は粒なし（視認できないため省略）
    if size >= 64 * SCALE:
        offsets  = [0.06, 0.12, 0.175]
        radii    = [0.034, 0.025, 0.018]
        opacities= [255, 163, 97]
        for y_off, r_ratio, opacity in zip(offsets, radii, opacities):
            r  = max(1, int(size * r_ratio))
            dy = mid_y + int(size * y_off)
            fill = (*SAND, opacity)
            draw.ellipse([cx - r, dy - r, cx + r, dy + r], fill=fill)

    return img


def render_with_shadow(size: int) -> Image.Image:
    """スーパーサンプリング＋ドロップシャドウで最終 PNG を生成する。"""
    big = size * SCALE

    # 高解像度で描画
    hi = draw_icon(big)

    # シャドウ：同じ形を暗い色で描いてブラー
    shadow_img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(shadow_img)
    rx_big = max(4, int(big * 0.27))
    shadow_color = (*SHADOW_CLR, 80)
    sdraw.rounded_rectangle([0, 0, big - 1, big - 1], radius=rx_big, fill=shadow_color)
    blur_r = max(2, big // 20)
    shadow_img = shadow_img.filter(ImageFilter.GaussianBlur(radius=blur_r))

    # シャドウを少しずらして合成
    offset = max(1, big // 40)
    base = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    base.paste(shadow_img, (0, offset), shadow_img)
    base = Image.alpha_composite(base, hi)

    # ダウンサンプリング（ランチョス）
    out = base.resize((size, size), Image.LANCZOS)
    return out


def main():
    out_dir = Path(__file__).parent.parent / \
              "scrpm/Assets.xcassets/AppIcon.appiconset"
    out_dir.mkdir(parents=True, exist_ok=True)

    for filename, size in SIZES:
        img = render_with_shadow(size)
        dest = out_dir / filename
        img.save(dest, "PNG")
        print(f"  ✓  {filename}  ({size}×{size})")

    print(f"\n完了: {len(SIZES)} ファイルを {out_dir} に出力しました。")


if __name__ == "__main__":
    main()
