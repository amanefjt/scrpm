import SwiftUI
import SwiftData
import AppKit

/// 作業ログだけを表示する独立ウィンドウ。
///
/// タイマーとは別に開いておき、その日の作業ログをそのままコピーして日記にまとめる用途。
/// 記録画面（HistoryView）が「集計を見る」ためのものなのに対し、こちらは
/// 「テキストとして取り出す」ことに特化している
struct WorkLogWindow: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkSession.startTime) private var allSessions: [WorkSession]

    @State private var date: Date = Date()
    @State private var copied = false
    @State private var exportDirectory: URL? = WorkLogExporter.directoryURL

    private var sessions: [WorkSession] {
        let cal = Calendar.current
        return allSessions.filter { cal.isDate($0.startTime, inSameDayAs: date) }
    }

    private var logText: String {
        WorkLog.body(entries: sessions.map(\.logEntry), on: date, calendar: .current)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            logBody
            Divider()
            footer
        }
        .frame(minWidth: 420, minHeight: 320)
    }

    private var header: some View {
        HStack {
            Button { navigate(by: -1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
            Spacer()
            Text(title)
                .font(.headline)
            Spacer()
            Button { navigate(by: 1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
                .disabled(Calendar.current.isDateInToday(date))
        }
        .padding()
    }

    @ViewBuilder
    private var logBody: some View {
        if logText.isEmpty {
            VStack {
                Spacer()
                Text("この日の記録はありません")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            ScrollView {
                // 選択してそのままコピーできるよう、行ごとではなく1つのテキストとして出す
                Text(logText)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack {
                Text("合計 \(totalText)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(copied ? "コピーしました" : "全部コピー") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logText, forType: .string)
                    copied = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(logText.isEmpty)
            }

            HStack(spacing: 8) {
                Text("書き出し先")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(exportDirectory?.path ?? "未設定（書き出さない）")
                    .font(.caption)
                    .foregroundStyle(exportDirectory == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                Button("変更…") { chooseExportDirectory() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                if exportDirectory != nil {
                    Button("解除") {
                        WorkLogExporter.directoryURL = nil
                        exportDirectory = nil
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
        }
        .padding()
    }

    private var totalText: String {
        let total = Int(sessions.reduce(0.0) { $0 + $1.duration })
        return String(format: "%d:%02d", total / 3600, (total % 3600) / 60)
    }

    private var title: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.locale = Locale(identifier: "ja_JP")
        return fmt.string(from: date)
    }

    private func navigate(by delta: Int) {
        date = Calendar.current.date(byAdding: .day, value: delta, to: date) ?? date
        copied = false
    }

    /// クラウド同期フォルダ（Google Drive 等）を選ばせる。選んだ時点で当日分を1回書き出し、
    /// 実際にファイルが出ることをその場で確認できるようにする
    private func chooseExportDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "ここに書き出す"
        panel.message = "作業ログの書き出し先フォルダを選んでください（Google Drive 等のクラウド同期フォルダ）"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        WorkLogExporter.directoryURL = url
        exportDirectory = url
        WorkLogExporter.export(day: date, context: context)
    }
}
