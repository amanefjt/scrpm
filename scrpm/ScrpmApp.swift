import SwiftUI
import SwiftData

@main
struct ScrpmApp: App {
    let container: ModelContainer
    let timerManager: TimerStateManager
    let overlayController: OverlayWindowController

    init() {
        do {
            let storeURL = Self.makeStoreURL()
            Self.migrateLegacyStoreIfNeeded(to: storeURL)
            let config = ModelConfiguration(url: storeURL)
            let c = try ModelContainer(for: WorkSession.self, configurations: config)
            Self.backfillSessionIDsIfNeeded(context: c.mainContext)
            SessionSyncExporter.importAll(context: c.mainContext)
            let tm = TimerStateManager(context: c.mainContext)
            self.container = c
            self.timerManager = tm
            self.overlayController = OverlayWindowController()
        } catch {
            fatalError("ModelContainer の初期化に失敗: \(error)")
        }
    }

    /// アプリ専用の保存先を組み立てる。
    ///
    /// `ModelContainer(for:)` にパスを渡さないと、SwiftData（非サンドボックスアプリ）は
    /// `~/Library/Application Support/default.store` という「バンドルIDに紐付かない共有パス」を
    /// デフォルトで使ってしまう。同じ Mac 上に同種のデフォルト設定を使う SwiftData アプリが
    /// 増えると、このファイルを取り合って上書き・破損する恐れがあるため、
    /// `Application Support/<bundle identifier>/default.store` に固定する（2026-08-10 対応）。
    private static func makeStoreURL() -> URL {
        let fm = FileManager.default
        let appSupport = (try? fm.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )) ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let bundleID = Bundle.main.bundleIdentifier ?? "com.scrpm.app"
        let storeDir = appSupport.appendingPathComponent(bundleID, isDirectory: true)
        try? fm.createDirectory(at: storeDir, withIntermediateDirectories: true)
        return storeDir.appendingPathComponent("default.store")
    }

    /// `WorkSession.id` を初めて導入した際の一度きりの後始末。
    ///
    /// `var id: UUID = UUID()` というデフォルト値は、SwiftData の軽量マイグレーションでは
    /// 移行時に1回だけ評価される可能性があり、既存レコード全件が同じ UUID になりうる
    /// （CoreData/SwiftData のよく知られた落とし穴）。id は端末間同期での一意識別に使うため、
    /// 全件が同じ値のままでは同期が成立しない。まだどこにも同期していない時点なので、
    /// 既存レコード全件の id を無条件で振り直しても安全（UserDefaults フラグで一度きりに絞る）
    private static let idBackfillDoneKey = "sessionIDBackfillDone"

    private static func backfillSessionIDsIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: idBackfillDoneKey) else { return }
        let descriptor = FetchDescriptor<WorkSession>()
        if let sessions = try? context.fetch(descriptor) {
            for session in sessions {
                session.id = UUID()
            }
            try? context.save()
        }
        UserDefaults.standard.set(true, forKey: idBackfillDoneKey)
    }

    /// 旧デフォルト共有パスに残っている既存データを新しい保存先へコピーする（移動ではない）。
    ///
    /// 新しい保存先にまだファイルが無い場合のみ、一度だけ実行される。元ファイルは
    /// 削除せずそのまま残す（他アプリが同じ共有パスを使っていた場合に備えた保険）。
    private static func migrateLegacyStoreIfNeeded(to newStoreURL: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: newStoreURL.path) else { return }

        let legacyStoreURL = (try? fm.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false
        ))?.appendingPathComponent("default.store")
        guard let legacyStoreURL, fm.fileExists(atPath: legacyStoreURL.path) else { return }

        for suffix in ["", "-shm", "-wal"] {
            let src = URL(fileURLWithPath: legacyStoreURL.path + suffix)
            let dst = URL(fileURLWithPath: newStoreURL.path + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            try? fm.copyItem(at: src, to: dst)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(timerManager)
                .onChange(of: timerManager.phase) { _, newPhase in
                    if newPhase.isBreak {
                        overlayController.show(timerManager: timerManager)
                    } else {
                        overlayController.hide()
                    }
                }
        }
        .modelContainer(container)
        .windowResizability(.automatic)
        .defaultSize(width: 400, height: 380)

        // 作業ログはタイマーと独立したウィンドウで開けるようにする。
        // 「区切りで作業をやめる → 夕方その日のログを日記にまとめる」という使い方のため
        Window("作業ログ", id: "worklog") {
            WorkLogWindow()
        }
        .modelContainer(container)
        .defaultSize(width: 480, height: 420)
        .keyboardShortcut("l", modifiers: [.command, .shift])
    }
}
