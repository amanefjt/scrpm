# フルスクリーンオーバーレイ調査メモ

Chrome などフルスクリーンアプリの上に休憩オーバーレイを出す実装を調査・実験した記録。

## 問題

macOS の native fullscreen アプリ（Chrome、Keynote など）は独立した Space を持つ。
外部ウィンドウは原則としてその Space に入れないため、単純な「最前面ウィンドウ」では覆えない。

## 試みたアプローチと結果

### 機能しないもの

| アプローチ | 結果 |
|-----------|------|
| `.canJoinAllSpaces` + `.screenSaver` level | fullscreen Space には入れない |
| `.canJoinAllApplications` + `.stationary` + `.screenSaver` level（macOS 14 新 API） | 同上。Chrome 全画面の上に出ない（2026-06 実験済み） |
| `CGDisplayCapture` | 3 本指スワイプが壊れる副作用あり |
| `NSApp.activate(ignoringOtherApps:)` | アプリが inactive のまま |

`canJoinAllApplications` は Apple ドキュメントに「join all apps for Stage Manager and full screen」とあるが、
他アプリの fullscreen Space への侵入は許可されなかった。macOS が API レベルで封じている。

### 機能する唯一の方法

**`toggleFullScreen` で独自の fullscreen Space を作る。**

```swift
window.collectionBehavior = [.fullScreenPrimary]
window.makeKeyAndOrderFront(nil)
window.toggleFullScreen(nil)
```

これにより独立した fullscreen Space が生成され、Chrome の Space とは別に全画面を覆える。
欠点は Space 切り替えアニメーション（約 0.5〜1 秒）が発生すること。

## アニメーション除去の試み

Space 切り替えアニメーションは macOS システムレベルで制御されており、アプリ側から完全に消す方法はない。

| 手法 | 効果 |
|------|------|
| `animationResizeTime` を 0 返し | ウィンドウリサイズアニメーション用。Space 切り替えには無関係 |
| `window.animationBehavior = .none` | `toggleFullScreen` の Space 切り替えには効かない |
| `NSWindowDelegate.startCustomAnimationToEnterFullScreen` | ウィンドウ自体のアニメーションは制御できるが Space スライドは残る |
| システム設定「視差効果を減らす」 | スライドがフェードになる。アプリ側から設定変更はできず検出のみ |

事前準備（Space を手前に用意しておく）も検討したが、`toggleFullScreen` は常に foreground Space switch を引き起こすため、
作業中に呼ぶとユーザーの画面を奪ってしまい逆効果。

## 参考

- [Apple Developer Forums: Window visible on all spaces](https://developer.apple.com/forums/thread/26677)
- [Electron issue #10078: alwaysOnTop over other fullscreen apps](https://github.com/electron/electron/issues/10078)
- [canJoinAllApplications — Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications?language=objc)
- Mozilla Firefox も同問題に苦労し一部実装をリバート（bugzilla #1631735）
