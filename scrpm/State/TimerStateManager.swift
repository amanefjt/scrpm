import Foundation
import AppKit
import Observation
import Combine
import SwiftData

@Observable
final class TimerStateManager {
    private(set) var phase: TimerPhase = .idle
    private(set) var remaining: TimeInterval = workDuration

    /// このサイクルで完走した作業セット数（0..<setsPerCycle）。
    /// setsPerCycle に達した時点で長い休憩に入り、そこで 0 に戻る
    private(set) var completedSets: Int = 0

    /// 休憩中に作業内容を書き込む対象（直前に完走したセッション）。
    /// 休憩が終わるまで編集でき、フェーズが変わった時点で確定する
    private(set) var noteTarget: WorkSession?

    /// 今日の記録済み作業時間の合計。作業中も休憩中も常に見せる。
    ///
    /// SwiftData の @Query ではなくここで保持しているのは、休憩オーバーレイが
    /// NSHostingView 直下（modelContainer が environment に無い）で描画されるため。
    /// セットを完走するたびに跳ね上がるので、小さな報酬の可視化としても機能する
    private(set) var todayTotalDuration: TimeInterval = 0

    private var phaseStartedAt: Date?
    private var timerCancellable: AnyCancellable?
    private var activityMonitorCancellable: AnyCancellable?
    private var consecutiveActivityCount = 0
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        setupTerminationObserver()
        startActivityMonitor()
        setPhase(.idle, since: Date())
        refreshTodayTotal()
    }

    private func refreshTodayTotal() {
        let sessions = WorkLogExporter.fetchSessions(on: Date(), context: context) ?? []
        todayTotalDuration = sessions.reduce(0) { $0 + $1.duration }
    }

    private func setPhase(_ newPhase: TimerPhase, since: Date) {
        phase = newPhase
        phaseStartedAt = since
        ScrpmStateWriter.write(phase: newPhase, since: since)
    }

    // MARK: - 操作

    func startWork() {
        finalizeNote()
        startActivityMonitor()
        setPhase(.working, since: Date())
        remaining = workDuration
        startTimer()
    }

    /// 作業を中断する（手動またはWorking中の無操作検出）。サイクルは崩れるのでリセットする。
    /// 休憩中のセッションは finishWork() で記録済みなので、ここで記録するのは Working 中のみ
    func stopWork() {
        if phase == .working {
            recordInterruptedSession()
        }
        finalizeNote()
        completedSets = 0
        setPhase(.idle, since: Date())
        remaining = workDuration
        stopTimer()
        startActivityMonitor()
    }

    /// 長い休憩を切り上げて次のサイクルに入る（短い休憩ではボタンを出さないので呼ばれない）
    func resumeWork() {
        guard phase.isBreak else { return }
        if phase == .longBreak { completedSets = 0 }
        startWork()
    }

    // MARK: - 自動遷移

    private func tick() {
        guard let start = phaseStartedAt else { return }
        let elapsed = Date().timeIntervalSince(start)

        switch phase {
        case .idle:
            stopTimer()
        case .working:
            remaining = max(0, workDuration - elapsed)
            if remaining <= 0 { finishWork() }
        case .shortBreak, .longBreak:
            remaining = max(0, phase.duration - elapsed)
            if remaining <= 0 { finishBreak() }
        }
    }

    /// 作業セットを完走した。1セット＝1レコードとして即座に記録し、休憩に入る。
    /// 記録したセッションは noteTarget として保持し、休憩中に作業内容を書き込めるようにする
    private func finishWork() {
        guard let start = phaseStartedAt else { return }
        completedSets += 1

        // 完走の duration は定義上ちょうど workDuration。endTime も start + workDuration に
        // 揃えることで、スリープ跨ぎで wall-clock が飛んでも記録画面の時刻表示が破綻しない
        let session = WorkSession(
            startTime: start,
            endTime: start.addingTimeInterval(workDuration),
            duration: workDuration,
            completed: true
        )
        context.insert(session)
        try? context.save()
        WorkLogExporter.export(day: start, context: context)
        refreshTodayTotal()
        noteTarget = session

        let isCycleEnd = completedSets >= setsPerCycle
        let next: TimerPhase = isCycleEnd ? .longBreak : .shortBreak
        setPhase(next, since: Date())
        remaining = next.duration
        stopActivityMonitor()
    }

    private static let breakEndSoundPath =
        "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/Ringtones/Sonar.m4r"

    /// 休憩が満了した。短い休憩なら次のセットを自動開始し、長い休憩なら Idle に戻す。
    ///
    /// 長い休憩の後に自動開始しないのは、長い休憩は「席を立って何をしてもよい時間」であり、
    /// 戻っていないのに作業時間が計上されるのを避けるため。戻ってキーボードを触り続ければ
    /// 既存の入力検出（idleActivationCount）が約5分で自動開始してくれる。
    ///
    /// どちらの場合も、席を外していて気づけないケースがあるためサウンドで知らせる
    /// （手動で再開・終了した場合は自分でクリックした行動なので鳴らさない）。
    /// "Sonar" は /System/Library/Sounds/ の標準音一覧には無く、ToneLibrary.framework
    /// （プライベートフレームワーク）内のファイルを直接参照している。将来の macOS で
    /// パスが変わる可能性はあるが、見つからなければ nil を返すだけで鳴らないだけに留まる
    private func finishBreak() {
        NSSound(contentsOfFile: Self.breakEndSoundPath, byReference: true)?.play()
        if phase == .longBreak {
            finalizeNote()
            completedSets = 0
            setPhase(.idle, since: Date())
            remaining = workDuration
            stopTimer()
            startActivityMonitor()
        } else {
            startWork()
        }
    }

    // MARK: - 記録

    /// 中断されたセッション（Working 中に stopWork）を記録する。
    /// minimumRecordDuration に満たないものは記録しない
    private func recordInterruptedSession() {
        guard let start = phaseStartedAt else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(start)
        guard elapsed >= minimumRecordDuration else { return }
        context.insert(WorkSession(
            startTime: start,
            endTime: now,
            duration: elapsed,
            completed: false
        ))
        try? context.save()
        WorkLogExporter.export(day: start, context: context)
        refreshTodayTotal()
    }

    /// 休憩中に編集していた作業内容を確定する。noteTarget は SwiftData の @Model なので
    /// View 側の編集は既にオブジェクトへ反映されている。ここでは保存して参照を手放すだけ
    private func finalizeNote() {
        guard let target = noteTarget else { return }
        try? context.save()
        // 作業内容はセッション記録より後に入力されるので、書き出しをやり直す必要がある
        WorkLogExporter.export(day: target.startTime, context: context)
        noteTarget = nil
    }

    /// アプリ終了時に呼ぶ。Working 中なら中断セッションとして記録し、
    /// 休憩中なら入力途中の作業内容を保存する
    func recordSessionIfNeeded() {
        if phase == .working {
            recordInterruptedSession()
        }
        finalizeNote()
    }

    private func startTimer() {
        stopTimer()
        timerCancellable = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    // MARK: - 入力検出によるフェーズ自動遷移（spec F3, F5）
    // Idle 中: 「作業をやめる」後に PC 作業を続けている場合、約5分で無音で自動開始する。
    // Working 中: 逆に約5分操作がなければ、手を止めている（＝作業していない）とみなし
    // 無音で自動的に「作業をやめる」扱いにする（中断セッションとして記録）。
    // 休憩中は対象外（休憩中は元々作業していない前提のため）。
    // 誤検出は許容する設計判断: 止め忘れ・止め遅れの害の方が大きい

    private func startActivityMonitor() {
        stopActivityMonitor()
        activityMonitorCancellable = Timer.publish(every: idlePollingInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.checkActivity() }
    }

    private func stopActivityMonitor() {
        activityMonitorCancellable?.cancel()
        activityMonitorCancellable = nil
        consecutiveActivityCount = 0
    }

    private func checkActivity() {
        switch phase {
        case .idle:
            if Self.secondsSinceLastUserInput() < idlePollingInterval {
                consecutiveActivityCount += 1
            } else {
                consecutiveActivityCount = 0
            }
            if consecutiveActivityCount >= idleActivationCount {
                startWork()
            }
        case .working:
            if Self.secondsSinceLastUserInput() >= idlePollingInterval {
                consecutiveActivityCount += 1
            } else {
                consecutiveActivityCount = 0
            }
            if consecutiveActivityCount >= workInactivityDeactivationCount {
                stopWork()
            }
        case .shortBreak, .longBreak:
            stopActivityMonitor()  // 到達しないはずの防御的分岐
        }
    }

    private static func secondsSinceLastUserInput() -> TimeInterval {
        let types: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]
        return types
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? .infinity
    }

    private func setupTerminationObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.recordSessionIfNeeded()
        }
    }
}
