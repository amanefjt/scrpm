import SwiftUI

/// 直前に完走したセッションの作業内容を入力する欄。
///
/// 休憩中はいつでも書き直せる状態のままにしておく（確定操作を要求しない）。
/// SwiftData の @Model は @Observable なので、ここでの編集はオブジェクトに直接反映され、
/// TimerStateManager がフェーズ遷移時に save する
struct SessionNoteField: View {
    let session: WorkSession
    /// 休憩オーバーレイ内（ダーク背景）で使うかどうか
    var isOverlay: Bool = false

    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text("作業内容")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("", text: Binding(
                get: { session.note },
                set: { session.note = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: isOverlay ? 18 : 13))
            .frame(maxWidth: isOverlay ? 480 : .infinity)
            .focused($focused)
            .onSubmit { focused = false }
        }
        .onAppear {
            // 休憩に入った瞬間に打ち始められるようにする。入力しないまま放置してもよい
            if isOverlay { focused = true }
        }
    }
}
