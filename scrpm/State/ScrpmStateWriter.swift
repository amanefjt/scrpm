import Foundation

private struct ScrpmStateFile: Codable {
    let phase: String
    let since: String
}

enum ScrpmStateWriter {
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// 短い休憩・長い休憩はどちらも "breaking" として書き出す。
    /// 読み手（worklog-capture）は「Working かどうか」だけを知りたいので、
    /// 休憩の種類を区別させる必要がなく、既存の 3 値フォーマットとの互換も保てる
    static func phaseString(_ phase: TimerPhase) -> String {
        switch phase {
        case .idle: return "idle"
        case .working: return "working"
        case .shortBreak, .longBreak: return "breaking"
        }
    }

    static func jsonString(phase: TimerPhase, since: Date) throws -> String {
        let file = ScrpmStateFile(phase: phaseString(phase), since: isoFormatter.string(from: since))
        let data = try JSONEncoder().encode(file)
        return String(decoding: data, as: UTF8.self)
    }

    static var stateFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".worklog")
            .appendingPathComponent("scrpm-state.json")
    }

    /// 書き込み失敗（ディレクトリ不存在等）は無視する。scrpm 本体の動作に影響を与えないため。
    static func write(phase: TimerPhase, since: Date) {
        guard let json = try? jsonString(phase: phase, since: since) else { return }
        try? json.write(to: stateFileURL, atomically: true, encoding: .utf8)
    }
}
